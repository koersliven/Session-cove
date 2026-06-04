#!/usr/bin/env bash
#
# Session Cove — verify-providers.sh
#
# Read-only smoke check for the multi-framework hook plumbing.
# Confirms ~/.session-cove/* exists, lists per-provider settings file
# install state, and pipes a mock PermissionRequest payload through
# session_cove_claude_hook.py for each provider dialect.
#
# This script does NOT toggle providers, write to UserDefaults, or
# mutate any settings file. The only side effect is that the bridge
# script may write a pending file to ~/.session-cove/hooks/pending/
# while we feed it stdin — those files are removed before exit.

set -u

SUPPORT_DIR="${HOME}/.session-cove"
HOOK_DIR="${SUPPORT_DIR}/hooks"
PENDING_DIR="${HOOK_DIR}/pending"
RESPONSES_DIR="${HOOK_DIR}/responses"
BIN_DIR="${SUPPORT_DIR}/bin"
SCRIPT="${BIN_DIR}/session_cove_claude_hook.py"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

ok()    { printf "  ${GREEN}OK${NC}  %s\n" "$*"; }
warn()  { printf "  ${YELLOW}!!${NC}  %s\n" "$*"; }
fail()  { printf "  ${RED}XX${NC}  %s\n" "$*"; }
info()  { printf "  ${DIM}--${NC}  %s\n" "$*"; }
header(){ printf "\n${CYAN}== %s ==${NC}\n" "$*"; }

# --- 1. Bootstrap dirs ---------------------------------------------------

header "Session Cove bootstrap"

for d in "$SUPPORT_DIR" "$HOOK_DIR" "$PENDING_DIR" "$RESPONSES_DIR" "$BIN_DIR"; do
    if [[ -d "$d" ]]; then
        ok "$d"
    else
        warn "$d (missing — launch Session Cove once to bootstrap)"
    fi
done

if [[ -f "$SCRIPT" ]]; then
    ok "bridge script: $SCRIPT"
else
    warn "bridge script not found ($SCRIPT) — launch Session Cove once to install"
fi

# --- 2. Enabled providers (read CoveSettings UserDefaults) ---------------

header "Enabled providers (CoveSettings → UserDefaults)"

ENABLED_RAW="$(defaults read com.sessioncove.app coveEnabledProviders 2>/dev/null || true)"

if [[ -z "$ENABLED_RAW" ]]; then
    info "coveEnabledProviders not set yet — defaulting to {claude}"
    ENABLED="claude"
else
    # `defaults read` prints a parenthesized array of quoted strings.
    # Strip parens, quotes, commas and squash to a space-separated list.
    ENABLED="$(printf '%s' "$ENABLED_RAW" \
        | tr -d '(){}\"'  \
        | tr ',' ' '       \
        | tr '\n' ' '      \
        | xargs)"
fi
info "enabled set: ${ENABLED}"

# Per-provider settings file lookup.
#
# We resolve the file lazily (case "$id") rather than as an associative
# array because /bin/bash on macOS is 3.2 and lacks declare -A.
settings_file_for() {
    case "$1" in
        claude)    printf '%s' "${HOME}/.claude/settings.json" ;;
        qoder)     printf '%s' "${HOME}/.qoder/settings.json" ;;
        qoderwork) printf '%s' "${HOME}/.qoderwork/settings.json" ;;
        cursor)    printf '%s' "${HOME}/.cursor/hooks.json" ;;
        *)         printf '' ;;
    esac
}

# We test all four whether or not they are currently enabled — the
# install-status row reflects what's actually on disk, which is what
# the user usually wants to see when debugging.
for id in claude qoder qoderwork cursor; do
    file="$(settings_file_for "$id")"
    enabled_marker="(disabled)"
    case " $ENABLED " in *" $id "*) enabled_marker="(enabled)";; esac

    if [[ -f "$file" ]]; then
        if grep -q "session_cove_claude_hook.py" "$file" 2>/dev/null; then
            ok  "${id} ${enabled_marker} — hook registered: $file"
        else
            warn "${id} ${enabled_marker} — settings file exists but no SC hook entry: $file"
        fi
    else
        info "${id} ${enabled_marker} — settings file missing: $file"
    fi
done

# --- 3. Dry-run the bridge script through each dialect -------------------

header "Bridge dry-runs"

if [[ ! -f "$SCRIPT" ]]; then
    fail "skipping dry-runs — bridge script missing"
    exit 0
fi

# Mock PermissionRequest payload. We use a deliberately unique
# tool_name so it cannot accidentally match a pre-existing allowlist
# rule the user has saved. The session_id is namespaced for the same
# reason — guarantees no collision with `trusted_sessions.json`.
MOCK_PAYLOAD='{
  "hook_event_name": "PermissionRequest",
  "tool_name": "__SessionCoveVerify",
  "tool_input": {"command": "verify-providers"},
  "cwd": "/tmp/session-cove-verify",
  "session_id": "session-cove-verify-providers"
}'

# Compute the request_id the bridge will assign for this payload, so
# we can target the pending file deterministically. This mirrors the
# bridge's `make_request_id`: sha256(json.dumps(stable, sort_keys=True))
# where `stable` keeps tool_name / tool_input / cwd.
REQUEST_ID="$(/usr/bin/python3 -c '
import hashlib, json
stable = {
    "tool_name": "__SessionCoveVerify",
    "tool_input": {"command": "verify-providers"},
    "cwd": "/tmp/session-cove-verify",
}
seed = json.dumps(stable, ensure_ascii=False, sort_keys=True, default=str)
print(hashlib.sha256(seed.encode("utf-8")).hexdigest()[:24])
')"

run_dialect() {
    local provider="$1"
    local label="$2"
    local expect="$3"  # "stdout-json" | "stderr-stub"

    printf "\n  %s --provider %s\n" "$label" "$provider"

    local out_file err_file
    out_file="$(mktemp -t sc-verify-out)"
    err_file="$(mktemp -t sc-verify-err)"

    # Spawn bridge in background. Without a Session Cove app on the
    # other end, the bridge writes a pending file and polls forever.
    # We trigger its `default_pass_through` branch by deleting the
    # pending file we just made it write — that emits the right
    # dialect output and the bridge exits 0 cleanly.
    (
        printf '%s' "$MOCK_PAYLOAD" \
            | /usr/bin/python3 "$SCRIPT" --provider "$provider" \
              >"$out_file" 2>"$err_file"
    ) &
    pid=$!

    # Wait briefly for the bridge to land its pending file, then
    # delete it. Loop up to ~2s in case the host is slow.
    local pending_file="${PENDING_DIR}/${REQUEST_ID}.json"
    local i=0
    while (( i < 10 )); do
        if [[ -f "$pending_file" ]]; then
            rm -f "$pending_file"
            break
        fi
        sleep 0.2
        i=$(( i + 1 ))
    done

    # Bridge polls every 0.2s; give it up to 2s to notice and emit.
    i=0
    while (( i < 10 )); do
        if [[ -s "$out_file" || -s "$err_file" ]] && ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 0.2
        i=$(( i + 1 ))
    done

    # Hard stop in case the bridge somehow missed the deletion.
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true

    local stdout_first stderr_first
    stdout_first="$(head -n 1 "$out_file" 2>/dev/null || true)"
    stderr_first="$(head -n 1 "$err_file" 2>/dev/null || true)"

    case "$expect" in
        stdout-json)
            if [[ -n "$stdout_first" ]] \
               && /usr/bin/python3 -c "import json,sys; json.loads(sys.argv[1])" "$stdout_first" 2>/dev/null; then
                ok "JSON response: $stdout_first"
            elif [[ -n "$stdout_first" ]]; then
                warn "non-JSON stdout: $stdout_first"
            else
                warn "no stdout produced"
                [[ -n "$stderr_first" ]] && info "stderr: $stderr_first"
            fi
            ;;
        stderr-stub)
            if [[ "$stderr_first" == *"cursor dialect not yet wired"* ]]; then
                ok "stub stderr matches expected sentinel: $stderr_first"
            elif [[ -n "$stdout_first" ]]; then
                info "cursor produced stdout (dialect now wired): $stdout_first"
            else
                warn "no sentinel observed; stderr=${stderr_first:-<empty>} stdout=${stdout_first:-<empty>}"
            fi
            ;;
    esac

    rm -f "$out_file" "$err_file"

    # Belt-and-suspenders: sweep any leftover pending/response file
    # for our request id so this run leaves no trace.
    rm -f "${PENDING_DIR}/${REQUEST_ID}.json" \
          "${RESPONSES_DIR}/${REQUEST_ID}.json"
}

run_dialect "claude"    "Claude Code" stdout-json
run_dialect "qoder"     "Qoder"       stdout-json
run_dialect "cursor"    "Cursor"      stderr-stub

header "Done"
info "verify-providers.sh is read-only — no settings were modified."
exit 0
