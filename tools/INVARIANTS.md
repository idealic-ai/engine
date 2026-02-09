# Tool Invariants

Tool-specific behavioral rules. For shared engine invariants, see `directives/INVARIANTS.md`.

## 1. Reliability Invariants

*   **¶INV_TOOL_GRACEFUL_DEGRADATION**: Search tools must handle missing Gemini API key gracefully.
    *   **Rule**: When `$GEMINI_API_KEY` is not set, tools must exit with a clear error message rather than crashing with an API error. The workflow engine must remain functional without search tools — they are an enhancement, not a dependency.
    *   **Reason**: Not all environments have Gemini API access. The engine must degrade gracefully to basic file-based operations.

*   **¶INV_TOOL_REBUILDABLE_DB**: Vector databases must be rebuildable from source data.
    *   **Rule**: SQLite databases used by doc-search and session-search must be treated as caches, not primary storage. An `index` command must be able to rebuild the entire database from the source files (docs/ and sessions/ respectively). Database corruption or deletion must not cause data loss.
    *   **Reason**: SQLite files can corrupt (especially on cloud sync per `¶INV_NO_GIT_ON_CLOUD_SYNC`). Rebuild-from-source is the recovery path.

*   **¶INV_TOOL_FLEET_OPTIONAL**: All tools must work without fleet/tmux.
    *   **Rule**: Tools that interact with tmux (statusline.sh, dispatch-daemon.sh) must check for tmux availability and exit cleanly without it. Guard with `[ -n "${TMUX:-}" ]`. This is a specialization of `¶INV_TMUX_AND_FLEET_OPTIONAL` for the tools/ directory.
    *   **Reason**: Users may run Claude in plain terminals, VS Code, or other non-tmux environments.

## 2. Data Invariants

*   **¶INV_TOOL_SQLITE_WAL**: SQLite databases should use WAL mode for concurrent access.
    *   **Rule**: When creating or opening SQLite databases, enable WAL mode (`PRAGMA journal_mode=WAL`). This allows concurrent readers during write operations — critical when session-search indexes while another agent queries.
    *   **Reason**: Default rollback journal mode blocks all readers during writes. WAL mode is the standard solution for read-heavy concurrent access.

*   **¶INV_TOOL_EMBEDDING_VERSION_PIN**: Gemini embedding model versions must be pinned.
    *   **Rule**: Embedding API calls must specify the exact model version (e.g., `text-embedding-004`), not a floating alias (e.g., `text-embedding-latest`). When upgrading the model version, all existing vector databases must be rebuilt — vectors from different model versions are incompatible.
    *   **Reason**: Mixing embedding vectors from different model versions produces nonsensical similarity scores. Version pinning ensures consistency.

## 3. Interface Invariants

*   **¶INV_TOOL_CLI_CONVENTION**: Tools must follow the engine CLI convention.
    *   **Rule**: Each tool's entry point is a shell script (`<tool-name>.sh`) that accepts subcommands as the first argument. Tools with TypeScript source use the shell script as a thin wrapper that invokes `npx tsx src/...`. This matches the `engine <tool> <subcommand>` routing pattern.
    *   **Reason**: Consistent interface across all tools. The engine CLI alias routes based on this convention.
