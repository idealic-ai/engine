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
| `project.sh` | Fetch a Linear **project** as one JSON payload of everything at/after an optional `--since` cutoff — bare fetch = full snapshot (comment trees, new tickets, attachments, lifecycle events, structure catalog, summary). Read-only GraphQL; stateless — `--since` is caller-owned, no stored waterline. Subcommands: `fetch`, `next`, `lint`. Needs `LINEAR_API_KEY` (env/.env). Consumed by `/intake` | `engine project fetch "<project>" [--since=<ISO>]` |
| `project.sh lint` | **Container conformance** against the section schema: reads a project's description (`Project.content` — *not* `Project.description`, which is a ~130-char summary), its Inbox Handbook document (matched by `slugId`) and its channel tickets, and checks each against `skills/intake/assets/project-schema.json`. `--all` derives its target list from the schema's own `scope` block and adds the cross-project peer comparison + a `scope`↔`INBOX_REGISTRY.md` agreement check; `--stdin --container <c>` lints text the caller already holds (a wave's pre-write gate) and reports that it had no peers rather than a clean comparison. Read-only toward Linear. Exit **0** clean-or-warnings · **1** failures · **2** could-not-run **or partial coverage** | `engine project lint --all [--json] [--strict]` |
| `lint-lib.sh` | Pure lint logic behind `project lint` — heading parser, section matcher, required/order checks, peer comparison, exit-code contract. No network, no `$HOME`, no Linear: every function takes a schema path + a text file and returns a JSON findings array, which is what keeps the rules testable offline. `belongsIn` is **derived** by looking a stray heading up across the *other* containers' section lists — there is deliberately no bad-heading→destination table and no alias list (normalization is generic; aliasing is curation) | sourced by `project.sh`, not run directly |
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

## Credentials — `engine env` (one command, one parser, one rule)

Every credential the engine reads resolves through **one** rule, in `scripts/env-lib.sh`:

*   **`$KEY` already exported** in the environment, else
*   **`<anchor>/.env.local`**, else **`<anchor>/.env`** — where `<anchor>` is the **current session's project root**, not `$PWD`.

**`<anchor>` is session-derived, so the answer does not change with which subdirectory you are standing in** — `apps/api/src` resolves the same value as the repo root, and a write from a subdirectory lands where the reader looks. With **no session there is no anchor and nothing resolves**: the resolver returns non-zero and says so, rather than guessing.

> **⚠️ `~/.claude/engine/.env` is NOT searched, and has not been since FIN-3576.** Resolution is deliberately project-scoped: a global engine-home file would let one project's wave authenticate as another's. Earlier revisions of this README advertised it as an "enable it everywhere" location — that was true once and is not now. Anything you want available across projects belongs in the **`core` domain** (`scripts/credentials.json`), which every domain's doctor checks. There is also **no `$HOME/.env` / `$HOME/.claude/.env`** lookup any more; the Gemini tools used to consult those and no longer do.

Duplicate definitions of a key in one file resolve **first-non-empty** (so a blank placeholder above a pasted value does not mask it), and a key in both dotfiles resolves to `.env.local`, with one stderr line naming the flip — never the value.

### The commands

| command | what it does |
|---|---|
| `engine env doctor --domain <name>` | red/green per credential; **exits non-zero on any `req` miss**. Checks the `core` rows on top of the named domain's. |
| `engine env setup --domain <name>` | wizard: prompts for each missing secret, **fetches** any `aws-secret` row. Resolve-all-then-write-once — a mid-run failure leaves your dotfile byte-identical. |
| `engine env setup --aws-key <path>` | installs a **delivered** agent AWS key: writes `~/.aws/credentials`, writes **no `login_session`**, verifies, then shreds the delivered file. |
| `engine env resolve <KEY> [--show-value]` | says **where** a credential comes from. The value is printed only with `--show-value`. |
| `engine env env-example --domain <name>` | the manifest-derived `.env.example`. |
| `engine env provision --person <n> --tier <triage\|member>` | mints a `<n>-agent` IAM user with a policy **derived from the manifest**. **Dry-run by default**; `--apply` is required and refuses while any statement is underivable. |

`engine intake <doctor|setup|env-example>` is **retired** — `scripts/intake.sh` is a tombstone that exits 2 and names the replacement. (`engine intake-announce` is a different, live command.)

### Domains

A domain is a manifest: `skills/<domain>/assets/credentials.json`, plus **`core`** at `scripts/credentials.json` for what the *engine* consumes on the session lifecycle (`LINEAR_API_KEY`, `GEMINI_API_KEY`). The doctor composes **core + the named domain**, so a credential every session needs is never skipped just because you asked about `design`. `env_load_domain <domain>` deliberately does **not** compose — loading stays per-domain, so sourcing `/prove`'s helper cannot sweep in unrelated credentials.

### LINEAR_API_KEY

A `core` row, so every domain's doctor checks it. Paste a Linear personal API key (`lin_api_…`) as `LINEAR_API_KEY=…` into your **project's** `.env.local`. Without one, `ticket-search` is **fail-soft** — `engine session activate` emits `## SRC_RELATED_TICKETS → (none — set LINEAR_API_KEY …)` and never blocks; the `/ticket-search` skill falls back to the Linear MCP. Set `TICKET_SEARCH_DISABLED=1` to skip the emit entirely.

### Adding a credential

Add a row to the domain's `credentials.json` — never to a script. `engine doctor`'s **EP-01** check fails the build on any `KEY=` extraction outside `env-lib.sh`, in either the `cut -d=` or the anchored-`grep` shape, anywhere under `scripts/`, `skills/` or `tools/`.

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
