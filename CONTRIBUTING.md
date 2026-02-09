# Contributing to the Workflow Engine

Rules for developing, testing, and deploying changes to the engine. This is a **directive** — loaded by AI agents working in the engine directory and read by human contributors.

For script-specific conventions (adding scripts, writing tests), see `scripts/CONTRIBUTING.md`.
For detailed CLI protocol and function signatures, see `~/.claude/docs/ENGINE_CLI.md`.
For the full lifecycle reference, see `docs/ENGINE_LIFECYCLE.md`.

---

## Development Rules

*   **¶ENG_LOCAL_MODE_DEVELOPMENT**: Always develop in local mode.
    *   **Rule**: Run `engine local` before editing engine code. All edits happen in `~/.claude/engine/` (the local Git checkout). Never edit files on GDrive directly — that's the production copy.
    *   **Reason**: GDrive sync is file-level and asynchronous. Editing there risks partial states and violates `¶INV_NO_GIT_ON_CLOUD_SYNC`.

*   **¶ENG_PUSH_AND_DEPLOY_SEPARATE**: `push` and `deploy` are independent operations.
    *   **Rule**: `engine push` saves to GitHub (Git). `engine deploy` syncs to GDrive (rsync). Neither triggers the other. Run both when ready to release; run push alone for backup; run deploy alone for quick team updates.
    *   **Reason**: Explicit control over what goes where. Git is for history and collaboration. GDrive is for team consumption.

*   **¶ENG_NO_GIT_ON_GDRIVE**: The `.git` directory never touches GDrive.
    *   **Rule**: `engine deploy` excludes `.git`, `.mode`, `.user.json`, and `node_modules` via rsync. The GDrive copy is a clean snapshot — no repository metadata.
    *   **Reason**: Cloud sync services corrupt `.git` internals. See `¶INV_NO_GIT_ON_CLOUD_SYNC`.

*   **¶ENG_PERSONAL_BRANCHES**: Use `{username}/engine` as your branch name.
    *   **Rule**: `engine local` auto-creates your personal branch (e.g., `yarik/engine`). Commit and push to this branch. Coordinate merges with the team.
    *   **Reason**: Multi-developer repo. Personal branches prevent commit collisions.

## Code Organization Rules

*   **¶ENG_FUNCTIONS_IN_LIB**: New pure functions go in `setup-lib.sh`, not `engine.sh`.
    *   **Rule**: `engine.sh` is the CLI dispatcher — arg parsing, orchestration, interactive prompts. `setup-lib.sh` holds all pure functions (parameterized, no globals, testable). If your change is a reusable function, it belongs in the lib.
    *   **Reason**: Unit testability. Functions in `setup-lib.sh` can be tested in isolation via `test-setup-lib.sh`.

*   **¶ENG_MIGRATIONS_NUMBERED**: New migrations are sequential, idempotent, and tested.
    *   **Rule**: Add to `setup-migrations.sh` with the next number. Each migration checks "already done?" before acting. Add test cases (fresh, idempotent, partial) to `test-setup-migrations.sh`.
    *   **Reason**: Migrations run on every `engine setup`. They must be safe to re-run and verifiable.

*   **¶ENG_ENV_VAR_INJECTION**: All paths use `$SETUP_*` env vars with defaults.
    *   **Rule**: Never hardcode `$HOME/.claude` or `$HOME/.claude/engine` in functions. Use `$SETUP_CLAUDE_DIR`, `$SETUP_ENGINE_DIR`, etc. (see `ENGINE_CLI.md` for the full list).
    *   **Reason**: Tests override these vars to sandboxed temp directories. Hardcoded paths escape the sandbox.

## Data Rules

*   **¶ENG_SEARCH_DB_REBUILD**: Search DBs use delete-and-rebuild, not migrations.
    *   **Rule**: If you change the schema for `.doc-search.db` or `.session-search.db`, delete the DB and let it rebuild via re-indexing. No formal DB migrations.
    *   **Reason**: The DBs are derived caches. The source data (session files, docs) is the source of truth. Rebuilding is always safe.

*   **¶ENG_SESSIONS_SEPARATE**: Sessions are per-project, not per-engine.
    *   **Rule**: `sessions/` lives in each project root (symlinked to GDrive in remote mode, local dir in local mode). Engine code never writes to `sessions/` — session management is handled by `session.sh`, not `engine.sh`.
    *   **Reason**: Separation of concerns. The engine is shared infrastructure; sessions are project-specific state.
