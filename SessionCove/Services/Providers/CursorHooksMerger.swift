import Foundation

/// Pure helper that merges Session Cove's hook command into a Cursor
/// `hooks.json` document **without** clobbering user-defined entries.
///
/// Cursor's schema is FLAT and unlike Claude's. A typical document:
///
/// ```json
/// {
///   "stop": [
///     {"type": "command", "command": "/path/to/r2c-audit.sh"},
///     {"type": "command", "command": "/path/to/session_cove_claude_hook.py --provider cursor stop"}
///   ],
///   "sessionStart": [
///     {"type": "command", "command": "/path/to/some-user-script.sh"}
///   ]
/// }
/// ```
///
/// Top level is a dictionary keyed by event name; each value is an array
/// of command entries. There is **no** Claude-style `{"hooks":[...]}`
/// nesting. There is also no `PermissionRequest` event, so we only
/// subscribe to events Cursor actually emits.
///
/// The merger is intentionally pure: it accepts an in-memory dictionary
/// and returns a new dictionary. The actual disk I/O (read existing
/// `hooks.json`, atomically write merged output, set permissions) is
/// step 10's job. This keeps step 9 entirely side-effect free; the only
/// way this code can touch the user's `hooks.json` is if step 10 wires
/// it up *and* `AgentProviderRegistry.enabled()` returns Cursor.
///
/// ## Idempotence
///
/// Existing entries whose `command` contains the marker
/// `session_cove_claude_hook.py` are *replaced* (so re-running install
/// upgrades the bridge command without duplicating it). Every other
/// entry is preserved verbatim, including any extra keys the user
/// added (e.g. `"description"`, `"timeout"`).
///
/// ## Example before / after
///
/// Input `existing`:
///
/// ```json
/// {
///   "stop": [
///     {"type": "command", "command": "/Users/me/r2c-audit.sh", "description": "audit"}
///   ]
/// }
/// ```
///
/// `sessionCoveCommand` = `"/usr/bin/python3 /Library/.../session_cove_claude_hook.py --provider cursor stop"`
///
/// Output:
///
/// ```json
/// {
///   "stop": [
///     {"type": "command", "command": "/Users/me/r2c-audit.sh", "description": "audit"},
///     {"type": "command", "command": "/usr/bin/python3 /Library/.../session_cove_claude_hook.py --provider cursor stop"}
///   ]
/// }
/// ```
///
/// Re-running `merged(into: <output above>, sessionCoveCommand: <new command>)`
/// will *replace* the second entry rather than appending a duplicate.
enum CursorHooksMerger {
    /// Marker substring used to identify Session Cove-owned entries.
    /// The Python bridge filename is unique enough to avoid collisions
    /// with user scripts in practice.
    static let ownershipMarker = "session_cove_claude_hook.py"

    /// Events Session Cove subscribes to in Cursor's hook chain.
    ///
    /// - `stop` — turn-completion toast (mirrors Claude Stop, fire-and-forget).
    /// - `beforeShellExecution` / `beforeMCPExecution` / `beforeReadFile`
    ///   — approval-equivalent surfaces. Cursor fires these on EVERY
    ///   tool invocation (auto-allow or sandbox), but the payload's
    ///   `tool_input.sandbox` boolean tells us which case we're in:
    ///     * `sandbox=true` (or `block_at_threshold=true`) → Cursor will
    ///       surface its own dialog; SC writes a pending reminder so the
    ///       popup appears alongside, and emits `permission: "ask"` to
    ///       let Cursor's dialog drive the actual decision.
    ///     * `sandbox=false` → Cursor auto-allows; SC stays silent and
    ///       emits `permission: "allow"` so the hook chain continues.
    /// `preToolUse` is intentionally NOT subscribed — its `"ask"` return
    /// is documented as "accepted by the schema but not enforced",
    /// making it useless for surfacing approval flow.
    static let subscribedEvents: [String] = [
        "stop",
        "beforeShellExecution",
        "beforeMCPExecution",
        "beforeReadFile",
    ]

    /// Merge `sessionCoveCommand` into `existing`. The returned dict has:
    ///
    ///   * Every key from `existing` preserved (even ones we don't
    ///     subscribe to).
    ///   * For each key in `subscribedEvents`:
    ///       - All non-Session-Cove entries preserved in original order
    ///         and with all their original fields.
    ///       - Exactly one Session Cove entry, appended after the
    ///         user's entries. Any prior Session Cove entries (matched
    ///         by `ownershipMarker`) are removed before appending so
    ///         install is idempotent.
    static func merged(
        into existing: [String: Any],
        sessionCoveCommand: String
    ) -> [String: Any] {
        var result = existing

        // `timeout` is critical: without it Cursor uses an internal
        // default that empirically does NOT wait for our stdout decision
        // long enough — the agent appears to "ignore" our allow/deny and
        // hang. The working r2c hook in the wild sets timeout=10 on its
        // before* / preToolUse / postToolUse entries, so we mirror that
        // floor. Long enough to absorb a normal SC popup decision (a few
        // hundred ms once the user clicks) but short enough that a
        // genuinely stuck SC won't dead-lock the agent.
        let ourEntry: [String: Any] = [
            "type": "command",
            "command": sessionCoveCommand,
            "timeout": 60
        ]

        for event in subscribedEvents {
            let userEntries: [Any] = (existing[event] as? [Any]) ?? []
            let preserved: [Any] = userEntries.filter { entry in
                guard let dict = entry as? [String: Any],
                      let cmd = dict["command"] as? String else {
                    // Anything we can't introspect (unexpected shape) is
                    // preserved verbatim — better safe than sorry.
                    return true
                }
                return !cmd.contains(ownershipMarker)
            }

            result[event] = preserved + [ourEntry]
        }

        return result
    }

    /// Inverse of `merged`: strip every Session Cove-owned entry from
    /// `existing` while preserving everything else. Used by step 10's
    /// uninstall path when the user toggles Cursor off in the AI 框架
    /// settings tab. Idempotent — running it twice is harmless.
    ///
    /// Behavior matches `merged` symmetrically:
    ///   * Keys NOT in `subscribedEvents` are passed through untouched.
    ///   * For each subscribed event, entries whose `command` contains
    ///     `ownershipMarker` are dropped; everything else preserved.
    ///   * If an event's array becomes empty after stripping, the key
    ///     is REMOVED entirely so the on-disk file does not accumulate
    ///     empty `"stop": []` arrays. (This matches "leave no trace"
    ///     after uninstall.)
    static func removed(
        from existing: [String: Any]
    ) -> [String: Any] {
        var result = existing

        for event in subscribedEvents {
            guard let userEntries = existing[event] as? [Any] else { continue }
            let preserved: [Any] = userEntries.filter { entry in
                guard let dict = entry as? [String: Any],
                      let cmd = dict["command"] as? String else {
                    return true
                }
                return !cmd.contains(ownershipMarker)
            }
            if preserved.isEmpty {
                result.removeValue(forKey: event)
            } else {
                result[event] = preserved
            }
        }

        return result
    }
}
