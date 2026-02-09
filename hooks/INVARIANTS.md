# Hook Invariants

Hook-specific behavioral rules. For shared engine invariants, see `directives/INVARIANTS.md`.

## Execution Invariants

*   **¶INV_HOOK_IDEMPOTENT**: Hook execution must be idempotent.
    *   **Rule**: Running a hook multiple times with the same input must produce the same result. Hooks must not accumulate state across invocations beyond what `.state.json` explicitly tracks.
    *   **Reason**: Claude Code may retry tool calls, causing hooks to fire multiple times for the same event.

*   **¶INV_HOOK_EXIT_CODES**: Exit codes have strict semantics for PreToolUse hooks.
    *   **Rule**: Exit 0 = allow (no output to stdout). Non-empty stdout = deny (message shown to agent as blocking error). Exit 1+ without stdout = hook error (logged but does not block).
    *   **Reason**: Claude Code interprets PreToolUse hook output as deny messages. Silent exit 0 is the "allow" signal.

*   **¶INV_HOOK_NO_SIDE_EFFECTS_ON_READ**: Hooks must not produce side effects for read-only tool calls.
    *   **Rule**: When the tool call is a read operation (Read, Glob, Grep), hooks should not modify `.state.json`, send notifications, or perform writes — unless explicitly tracking read patterns (e.g., directive discovery).
    *   **Exception**: `post-tool-use-discovery.sh` tracks touched directories on Read calls to discover directives. This is an intentional read-triggered side effect.
    *   **Reason**: Read operations are frequent and should be cheap. Side effects on reads cause performance degradation and unexpected state changes.

*   **¶INV_HOOK_ORDERING_MATTERS**: PreToolUse hooks execute in array order from settings.json.
    *   **Rule**: The session gate (`pre-tool-use-session-gate.sh`) must be first in the PreToolUse array. All other PreToolUse hooks read `.state.json`, which only exists after session activation. If the session gate isn't first, other hooks will fail on missing state.
    *   **Reason**: Hook ordering is the only sequencing mechanism. Claude Code provides no dependency declaration for hooks.

*   **¶INV_HOOK_STATE_JSON_DEPENDENCY**: Hooks that read `.state.json` must handle its absence gracefully.
    *   **Rule**: Before reading `.state.json`, check if the file exists. If missing, the hook should either exit 0 (allow, no-op) or handle the case explicitly. Never crash on missing state.
    *   **Reason**: Before session activation, `.state.json` does not exist. The session gate whitelists certain tools pre-activation, so other hooks may fire before state exists.

## Performance Invariants

*   **¶INV_HOOK_FAST_EXIT**: Hooks must exit quickly when they have nothing to do.
    *   **Rule**: Every hook should have early-exit checks at the top (tool type whitelist, session state check). The common case should be a fast no-op. Target: <50ms for no-op cases.
    *   **Reason**: Hooks fire on every tool call. Slow hooks compound into noticeable latency for the user.

*   **¶INV_HOOK_NO_NETWORK**: Hooks must not make network calls.
    *   **Rule**: No HTTP requests, API calls, or DNS lookups in hook execution paths. All data must come from local filesystem (`.state.json`, tool call JSON, environment variables).
    *   **Reason**: Network calls add unpredictable latency and failure modes to every tool call.
