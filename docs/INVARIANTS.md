# Engine Invariants

Rules specific to the workflow engine shell scripts (fleet.sh, session.sh, hooks, statusline). These complement the shared invariants in `~/.claude/directives/INVARIANTS.md`.

Reference this file alongside `ENGINE_TESTING.md` in all engine shell script headers.

---

## Tmux / Fleet

*   **INV_NO_FOCUS_CHANGE_IN_NOTIFY**: Notification commands MUST NOT change the focused pane.
    *   **Rule**: When applying visual state (background color) to a non-focused pane, use the atomic compound command `select-pane -t "$pane" -P "bg=$color" \; select-pane -t "$active"` — this sets style AND restores focus in one tmux server round-trip (no race window). For the focused pane, skip style entirely (avoid flash/distraction).
    *   **Prohibited**: (1) `set-option -p -t style "bg=..."` — INVALID in tmux 3.6a, "style" is not a recognized pane option. (2) `select-pane -t "$pane" -P "bg=$color"` without focus restoration — creates a focus-theft race.
    *   **Reason**: Multiple agents call `fleet.sh notify` concurrently. The atomic compound command eliminates the race window. Skipping focused pane style prevents visual flashing.
    *   **Discovered**: 2026-02-08 — `sessions/2026_02_08_TMUX_TESTING/ANALYSIS.md` § Theme A. Updated 2026-02-08 after discovering `set-option style` is invalid.

*   **INV_FLEET_GRACEFUL_OUTSIDE_TMUX**: Fleet commands MUST be no-ops outside tmux.
    *   **Rule**: All tmux calls in fleet.sh and session.sh fleet paths must use `2>/dev/null || true`. Missing `$TMUX` or `$TMUX_PANE` means "not in fleet" — exit silently, don't error.
    *   **Cross-ref**: `INV_TMUX_AND_FLEET_OPTIONAL` in shared INVARIANTS.md.

*   **INV_SILENT_FAILURE_AUDIT**: Shell commands guarded by `|| true` must be audited for correctness.
    *   **Rule**: When adding `|| true` to a command, verify that the command actually works as expected. Silent failure masking can hide regressions that persist for multiple sessions before being discovered.
    *   **Pattern**: After adding `|| true`, run the command without `|| true` at least once to confirm it succeeds. If it fails, investigate — don't just silence it.
    *   **Reason**: The style regression in fleet.sh (`set-option -p -t style "bg=..."`) was silently broken by `|| true` for an entire session cycle. The command was INVALID in tmux 3.6a but the error was invisible.
    *   **Discovered**: 2026-02-08 — `sessions/2026_02_08_TMUX_TESTING/TESTING.md` § Defect Analysis.

*   **INV_SUPPRESS_HOOKS_FOR_PROGRAMMATIC_STYLE**: Programmatic style changes via `select-pane -P` MUST suppress the `after-select-pane` hook using `@suppress_focus_hook`.
    *   **Rule**: Any code that calls `select-pane -P` for styling purposes (not user-initiated focus change) must wrap it in `set -g @suppress_focus_hook 1 \; select-pane -P ... \; set -g @suppress_focus_hook 0`. The hook checks `@suppress_focus_hook` at the top and exits early if set to 1.
    *   **Reason**: Without suppression, `select-pane -P` triggers the focus hook, which calls `select-pane -P` again, creating a rendering cascade that causes visible pane flashing.
    *   **Discovered**: 2026-02-08 — `sessions/2026_02_08_TMUX_TESTING/BRAINSTORM.md` § Insight 3.

*   **INV_SKIP_REDUNDANT_STYLE_APPLY**: Visual style updates MUST be skipped when the target state hasn't changed.
    *   **Rule**: Before calling `select-pane -P`, read the current `@pane_notify` value. If it matches the requested state, skip the visual update. Data layer (`@pane_notify` set-option) still updates every time — only the visual `select-pane -P` is skipped.
    *   **Reason**: Redundant `select-pane -P` calls cause unnecessary tmux redraws and visible flashing. State-check debouncing eliminates redundancy at zero overhead.
    *   **Discovered**: 2026-02-08 — `sessions/2026_02_08_TMUX_TESTING/BRAINSTORM.md` § Insight 4.

## Hooks

*   **INV_HOOKS_NOOP_WHEN_IDLE**: Hooks MUST be no-ops when there is nothing to do.
    *   **Rule**: If a hook has no work to perform (e.g., no session active, no fleet pane, no applicable condition), it must exit 0 immediately. No logging, no side effects, no errors.
    *   **Reason**: Hooks fire on every tool call. Unnecessary work or errors in idle hooks degrade the entire agent experience.
