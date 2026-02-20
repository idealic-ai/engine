# RPC Invariants

Rules specific to the daemon RPC layer. For shared engine invariants see `~/.claude/.directives/INVARIANTS.md`. For tool-level invariants see `tools/.directives/INVARIANTS.md`.

## Data Boundary

*   **¶INV_DAEMON_IS_PURE_DB**: The daemon touches ONLY SQLite. Zero filesystem reads, zero filesystem writes.
    *   **Rule**: RPC handlers receive data as arguments and return data as JSON. They never import `fs`, `path`, or any filesystem module. All FS I/O is performed by the bash CLI layer that calls the daemon.
    *   **Reason**: Clean separation — daemon owns state, bash owns files. This makes the daemon testable with in-memory SQLite and eliminates FS-related race conditions.

*   **¶INV_DAEMON_IS_THE_LOCK**: The single-threaded event loop serializes all mutations.
    *   **Rule**: No explicit locking, mutexes, or advisory locks in RPC handlers. The Node.js event loop processes one RPC at a time. Ordinal assignment, phase transitions, and session auto-cleanup are safe because they execute atomically within a single handler call.
    *   **Reason**: sql.js is synchronous (WASM). Each handler runs to completion before the next request is processed. This is the concurrency model — don't fight it.

## Transaction Discipline

*   **¶INV_RPC_TRANSACTION_WRAP**: Multi-statement mutations MUST be wrapped in BEGIN/COMMIT/ROLLBACK.
    *   **Rule**: Any handler that runs more than one write statement must use explicit transactions. Single-statement writes (heartbeat, context update) may skip transactions.
    *   **Pattern**: `db.exec("BEGIN"); try { ... db.exec("COMMIT"); } catch { db.exec("ROLLBACK"); throw err; }`
    *   **Reason**: sql.js in WAL mode auto-commits each statement. Without explicit transactions, a crash between statements leaves partial state.

## Error Conventions

*   **¶INV_RPC_ERROR_TAXONOMY**: Use the 3-level error taxonomy consistently.
    *   **Rule**: Handler-level errors use descriptive error codes: `NOT_FOUND`, `ALREADY_FINISHED`, `EFFORT_FINISHED`, `UNKNOWN_PHASE`, `PHASE_NOT_SEQUENTIAL`, `ALREADY_ENDED`, `TASK_NOT_FOUND`. Framework-level errors (`UNKNOWN_COMMAND`, `VALIDATION_ERROR`, `HANDLER_ERROR`) are set by dispatch.ts.
    *   **Reason**: Callers (bash scripts) match on `error` field to decide behavior — descriptive codes enable precise error handling.

*   **¶INV_RPC_GUARD_BEFORE_MUTATE**: Validate preconditions before starting transactions.
    *   **Rule**: Check existence (NOT_FOUND), lifecycle state (ALREADY_FINISHED), and other preconditions BEFORE `db.exec("BEGIN")`. Early returns avoid unnecessary transaction overhead and rollback paths.
    *   **Reason**: Cleaner error paths. Guards are read-only and don't need transaction protection.

## Registration

*   **¶INV_RPC_SELF_REGISTERING**: Each handler file registers itself as a side effect of import.
    *   **Rule**: The last line of every handler file is `registerCommand("db.namespace.verb", { schema, handler })`. The registry.ts barrel file imports all handlers. Adding a new RPC = create file + add import.
    *   **Reason**: No central switch statement or config object to maintain. Registration is co-located with the handler code.
