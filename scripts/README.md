# Scripts

Shell scripts for the workflow engine. Symlinked to `~/.claude/scripts/` and whitelisted globally with `Bash(~/.claude/scripts/*)` — no permission prompts.

## The `engine` CLI Alias

All scripts can be invoked via the `engine` CLI alias, which routes `engine <command> [args]` to the corresponding `<command>.sh` script:

```bash
engine session activate sessions/2026_02_09_TOPIC implement   # → engine session activate ...
engine log sessions/.../LOG.md <<'EOF'                         # → log.sh ...
engine tag find '#needs-review'                                # → tag.sh find ...
engine glob '**/*.md' sessions/                                # → glob.sh ...
```

The alias is the preferred invocation method — it's shorter and whitelisted via `Bash(engine *)`.

## Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `engine.sh` | CLI alias — routes `engine <cmd>` to the corresponding script | `engine session activate ...` |
| `session.sh` | Session lifecycle: activate, phase tracking, deactivate, restart, context scans | `engine session activate <path> <skill>` |
| `log.sh` | Append content to any file. Creates parent dirs. Auto-injects timestamps into `## ` headings | `log.sh <file> <<'EOF'` |
| `tag.sh` | Manage semantic tags on markdown files. Subcommands: `add`, `remove`, `swap`, `find` | `tag.sh add <file> '#tag'` |
| `ticket.sh` | Cross-session Linear-ticket updates + the per-ticket Linear pull. Signal subcommands (`subscribe`, `unsubscribe`, `notify`, `read`, `list`) track a dirty queue + ONE shared read cursor `.ticketCursor` (W) over the watched set. `watch` (fswatch) blocks until a watched ticket updates, then **auto-drains** — `ticket fetch`es the delta since W into a payload file, advances W, emits the path (self-registers `watchTaskId` for the auto-watch hard gate). `fetch <KEY...> [--since] [--out]` is the stateless multi-key Linear pull (comment trees w/ reactions + lifecycle + attachments), grouped by team; needs `LINEAR_API_KEY`. The `/communicate` skill drives a full ask/reply discussion turn | `ticket.sh fetch FIN-123 FIN-456 --since=<ISO>` · `ticket.sh watch FIN-123` |
| `project.sh` | Fetch a Linear **project** as one JSON payload of everything at/after an optional `--since` cutoff — bare fetch = full snapshot (comment trees, new tickets, attachments, lifecycle events, structure catalog, summary). Read-only GraphQL; stateless — `--since` is caller-owned, no stored waterline. Subcommand: `fetch`. Needs `LINEAR_API_KEY` (env/.env). Consumed by `/intake` | `engine project fetch "<project>" [--since=<ISO>]` |
| `linear-lib.sh` | Shared Linear GraphQL seam (`_graphql`/`_load_key`/fixture mechanism) + the per-issue jq transform (comment tree w/ reactions, normalized lifecycle, attachments) + child-pagination. Sourced by both `project.sh` and `ticket.sh` so a field added for one is added for both (`¶INV_SHARED_TRANSFORM_NO_DIVERGE`). Fixture var: `LINEAR_FIXTURE` (or the `PROJECT_FETCH_FIXTURE` back-compat alias) | sourced, not run directly |
| `ticket-search.sh` | Rank **related Linear tickets** for a free-text query (read-only `searchIssues` GraphQL). Emits `SRC_RELATED_TICKETS` at session startup + backs the `/ticket-search` skill. Needs `LINEAR_API_KEY` (env/.env); fail-soft to `(none)` without it. Flags: `--team`, `--include-closed`/`--open-only`, `--limit`, `--json` | `engine ticket-search "<text>" [--open-only] [--json]` |
| `lib.sh` | Shared utilities for hooks: fleet notification, tmux guards, JSON helpers | Sourced by hooks, not invoked directly |
| `find-sessions.sh` | Find sessions by date, topic, tag, or date range | `find-sessions.sh recent --files` |
| `glob.sh` | Symlink-aware file globbing. Fallback when Glob tool can't traverse symlinks | `glob.sh '**/*.ts' sessions/` |
| `research.sh` | Gemini Deep Research API wrapper. Polls until complete, writes report | `research.sh <output> <<'EOF'` |
| `write.sh` | Copy stdin to system clipboard | `write.sh <<'EOF'` |
| `escape-tags.sh` | Retroactive backtick escaping for bare tag references in markdown | `escape-tags.sh <file>` |
| `config.sh` | Session configuration management. Reads/writes `.state.json` fields | Sourced by session.sh |
| `run.sh` | Generic script runner with error handling | `run.sh <script> [args]` |
| `discover-directives.sh` | Walk-up discovery of directive files (README, CHECKLIST, PITFALLS, INVARIANTS) from a directory | `discover-directives.sh <dir>` |
| `doc-search.sh` | Documentation search via embeddings. Index and query project docs | `doc-search.sh query "search terms"` |
| `session-search.sh` | Session search via embeddings. Index and query past session artifacts | `session-search.sh query "search terms"` |
| `setup-lib.sh` | Bootstrap shared library functions for other scripts | Sourced by scripts at startup |
| `setup-migrations.sh` | Run schema migrations on `.state.json` when engine updates | `setup-migrations.sh` |
| `await-tag.sh` | Background watcher that blocks until a specific tag appears on a file | `await-tag.sh <file> '#tag'` |
| `fleet.sh` | Multi-pane tmux fleet management. Launch, query, coordinate agent panes | `fleet.sh pane-id` |
| `user-info.sh` | Auto-detect user identity from Google Drive symlink | `user-info.sh username` / `email` / `json` |
| `doctor.sh` | Validate engine ecosystem health (skills, CMDs, directives, sessions, sigils) | `doctor.sh [-v] [dir]` |
| `worker.sh` | Daemon worker process. Picks up tagged work items and dispatches to skills | `worker.sh` |
| `account-switch.sh` | Claude account credential rotation — save, switch, rotate profiles via macOS Keychain | `engine account-switch save user@gmail.com` |
| `migrate-fleet-pane-ids.sh` | One-time migration for fleet pane ID format changes | `migrate-fleet-pane-ids.sh` |

## LINEAR_API_KEY (enables `project.sh`, `ticket.sh fetch`/`watch` auto-drain + `ticket-search.sh`)

Both Linear-GraphQL tools resolve the key the same way (first hit wins):

*   **`$LINEAR_API_KEY`** already exported in the environment.
*   **`./.env`** — the current working directory, which at `engine session activate` time is the **project root** (e.g. `finch/.env`). Same file `session-search`/`doc-search` read `GEMINI_API_KEY` from.
*   **`~/.claude/engine/.env`** — the engine's own env (project-agnostic; use this to enable ticket-search across every project).

Both `.env` files are gitignored. To enable: paste a Linear personal API key (`lin_api_…`) as `LINEAR_API_KEY=…` into whichever file matches your scope. Without a key, `ticket-search` is **fail-soft** — `engine session activate` emits `## SRC_RELATED_TICKETS → (none — set LINEAR_API_KEY …)` and never blocks; the `/ticket-search` skill falls back to reading tickets via the Linear MCP.

*   **Disable at startup**: set `TICKET_SEARCH_DISABLED=1` to skip the emit entirely.
*   **Scope**: project-root `.env` → that project only; `~/.claude/engine/.env` → all projects. The project-root file wins when both define it.

## find-sessions.sh

The session discovery tool. All subcommands output session directory paths by default.

**By directory name** (matches the date prefix in the folder name):
```
find-sessions.sh today                          # Sessions from today
find-sessions.sh yesterday                      # Sessions from yesterday
find-sessions.sh recent                         # Today + yesterday
find-sessions.sh date 2026_02_03                # Specific date
find-sessions.sh range 2026_02_01 2026_02_03    # Date range (inclusive)
```

**By file modification time** (catches overnight sessions, multi-day work, sessions that span midnight):
```
find-sessions.sh active                         # Any file modified in last 24h
find-sessions.sh since '2026-02-03 14:00'       # Any file modified since timestamp
find-sessions.sh window '2026-02-03 06:00' '2026-02-04 02:00'  # Files modified in window
```

**By content**:
```
find-sessions.sh topic RESEARCH                 # Case-insensitive name match
find-sessions.sh tag '#needs-review'            # Sessions containing a tag
find-sessions.sh all                            # Everything
```

**Flags** (append to any subcommand):
- `--files` — Show all files with timestamps, sorted by mtime
- `--debriefs` — Show only debrief files (excludes logs, plans, details, requests, responses)
- `--path <dir>` — Search in a different directory (default: `sessions/`)

## tag.sh

Tag management with two-pass discovery.

```
tag.sh add    <file> '#tag'                     # Add tag to Tags line
tag.sh remove <file> '#tag'                     # Remove from Tags line
tag.sh remove <file> '#tag' --inline <line>     # Remove inline tag at line N
tag.sh swap   <file> '#old' '#new'              # Swap on Tags line
tag.sh swap   <file> '#old1,#old2' '#new'       # Swap any of several tags
tag.sh swap   <file> '#old' '#new' --inline N   # Swap inline tag at line N
tag.sh find   '#tag' [path]                     # Find files with tag
tag.sh find   '#tag' [path] --context           # Find with line numbers + lookaround
```

## glob.sh

Symlink-aware file globbing. The Glob tool's internal engine doesn't traverse symlinks (e.g., `sessions/` → Google Drive). Use this as a fallback.

```
glob.sh '**/*.md' sessions/                     # All .md files recursively
glob.sh '*.md' sessions/2026_02_04_FOO          # Shallow — top-level .md only
glob.sh '**/*.test.ts' packages/estimate/src    # Recursive with name filter
glob.sh '**' sessions/2026_02_04_FOO            # All files in a session
```

Output is sorted by mtime (newest first), paths relative to the root argument.

## log.sh

Append-only. Blind write — never reads the file. Creates parent dirs automatically.

```
log.sh <file> <<'EOF'
## [2026-02-03 10:00:00] Header
*   **Key**: Value
EOF
```

## research.sh

Gemini Deep Research API wrapper. Requires `$GEMINI_API_KEY`.

```
research.sh <output-file> <<'EOF'               # Initial research
query text
EOF

research.sh --continue <id> <output-file> <<'EOF'  # Follow-up
follow-up query
EOF
```

Output file format: line 1 is `INTERACTION_ID=<id>`, remaining lines are the report.
