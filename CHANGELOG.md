# Changelog

All notable changes to Session Cove are tracked here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) loosely; dates use
the YYYY-MM-DD that the work landed on `main`.

The project-internal narrative log lives at `.claude/CHANGELOG.md` (not
shipped). This file is the user-visible summary.

---

## Multi-framework support (Phase 1-4)

Session Cove was originally Claude Code-only; phases 1-4 generalised the
hook plumbing, scanner / watcher / process / resumer / allowlist layers
and the UI surface so any number of Claude-shaped coding agents can be
managed side by side. The default behaviour on first launch is unchanged
(only Claude Code is enabled), and existing `~/.claude/settings.json`
hook entries are written exactly as before.

### Foundation — `0a5927a`

- New `AgentProvider` protocol + `AgentProviderRegistry.shared` keyed by
  stable provider id. Single source of truth for "what frameworks does
  Session Cove know about".
- `HookPermissionRequest` gained a `providerId` field (schema v3) so a
  pending request always carries its origin framework. Decoders default
  to `"claude"` for legacy v2 payloads.
- `bridgeScript` (the Python hook script written to
  `~/.session-cove/bin/`) accepts `--provider <id>` and routes stdout
  through a per-provider `DIALECTS` table. Schema bumped to v4.
- `AllowlistRule.providerId` added; matcher only fires when the rule's
  provider matches the request's, so Cursor sessions can never
  accidentally trip a Claude allowlist row.

### Refactor — `c55951f`

- `SessionScanner`, `SessionWatcher`, `ProcessDetector`,
  `SessionResumer` and `AllowlistStore` all delegate framework-specific
  paths and command shapes to their `AgentProvider`. Adding a new
  provider no longer requires patching every service file.
- `~/.claude/projects/` discovery is the Claude provider's
  responsibility; the scanner only iterates over `enabled()` providers.

### New providers — `821e65e`

- `QoderProvider`, `QoderWorkProvider`, `CursorProvider` registered
  alongside `ClaudeProvider` in `AgentProviderRegistry.bootstrap()`.
- Qoder / QoderWork share the Claude `PermissionRequest` +
  `PreToolUse` + `Stop` schema verbatim and route through the
  `claude` stdout dialect with their own `--provider` arg.
- Cursor is **experimental**: `Stop` only (Cursor has no
  `PermissionRequest` equivalent today). The dialect emitter prints
  a stub stderr message until step 9 wires the real Cursor contract.
- All three providers ship inert in this commit — `enabled()` still
  filters to `["claude"]` by default; the AI 框架 settings tab in the
  next commit is what activates them.

### UI / polish — _(pending — replace placeholder hash on commit)_

- `CoveSettings.enabledProviders: Set<String>` becomes the single
  source of truth for which providers are active. The setter
  guarantees `"claude"` cannot be removed; the UI also disables the
  Claude toggle as a belt-and-suspenders safeguard.
- New **Settings → AI 框架** tab: per-provider toggle row with a live
  install-status dot (read from `ClaudePermissionHook.isInstalled`).
  Toggling a provider runs `installFor<Provider>` /
  `uninstall(providerId:)` immediately — no relaunch required.
- `ClaudePermissionHook.install()` now fans out to per-provider
  installers driven by `enabledProviders`. Each provider's settings
  file is written / cleaned independently so a failure on one does
  not abort the others.
- `~/.claude/settings.json` writes are byte-for-byte equivalent to
  the pre-multi-framework path on a fresh machine (default enabled
  set is `{"claude"}`).
- UI strings + mascot resources fall back through the provider:
  - `MascotImage.loadMascot(state:prefix:)` first tries
    `<prefix>_<state>` and falls back to `claude_<state>`, so a
    provider that ships its own assets gets them automatically and
    one that doesn't keeps the original octopus.
  - `HookQuestionView` header reads
    `provider.ui.askQuestionTitle`; `CompletionPingCard` title
    reads `provider.ui.completionTitle`. Existing Claude visuals
    are unchanged — `ClaudeProvider().ui.completionTitle` is still
    `"任务完成"` and `askQuestionTitle` is still
    `"Question from Claude"`.
- Companion script `scripts/verify-providers.sh` performs a
  read-only smoke check: confirms `~/.session-cove/` bootstrap,
  reports per-provider settings file state, and pipes a mock
  `PermissionRequest` through the bridge for `--provider claude`,
  `--provider qoder`, and `--provider cursor`. No settings are
  modified.

### How to enable

1. Launch Session Cove (or relaunch if it's already running).
2. Open **Settings → AI 框架**.
3. Toggle Qoder / QoderWork / Cursor as needed. Each toggle
   installs (or removes) the equivalent hook entry under
   `~/.qoder/`, `~/.qoderwork/`, or `~/.cursor/`. The Claude row
   stays on by default and cannot be disabled.

To roll back, toggle the provider off — the Session Cove hook entry
is removed but pre-existing user entries (`r2c` hooks, audit
scripts, etc.) are preserved verbatim.
