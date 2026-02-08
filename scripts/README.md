# Scripts

Shell scripts for the workflow engine. Symlinked to `~/.claude/scripts/` and whitelisted globally with `Bash(~/.claude/scripts/*)` — no permission prompts.

## Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `log.sh` | Append content to any file. Creates parent dirs. Auto-prepends blank line. | `log.sh <file> <<'EOF'` |
| `tag.sh` | Manage semantic tags on markdown files. Subcommands: `add`, `remove`, `swap`, `find`. | `tag.sh add <file> '#tag'` |
| `find-sessions.sh` | Find sessions by date, topic, tag, or date range. | `find-sessions.sh recent --files` |
| `session.sh` | Session lifecycle: activate, phase tracking, deactivate, restart, context scans. | `session.sh activate <path> <skill>` |
| `lib.sh` | Shared utilities for hooks: fleet notification, tmux guards, JSON helpers. | Sourced by hooks, not invoked directly. |
| `research.sh` | Gemini Deep Research API wrapper. Polls until complete, writes report. | `research.sh <output> <<'EOF'` |
| `write.sh` | Copy stdin to system clipboard. Used by `/dehydrate`. | `write.sh <<'EOF'` |
| `glob.sh` | Symlink-aware file globbing. Fallback when Glob tool can't traverse symlinks. | `glob.sh '**/*.ts' sessions/` |
| `escape-tags.sh` | Retroactive backtick escaping for bare tag references in markdown. | `escape-tags.sh <file>` |
| `engine.sh` | One-time project setup. Symlinks engine dirs, creates session dir on GDrive. | See engine README. |

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
