# Engine Lifecycle Reference

How the workflow engine is developed, synced, and deployed across the team. This document supersedes `SETUP_PROTOCOL.md`.

---

## The Two-Axis Architecture

The engine operates on two independent axes: **mode** (what Claude reads) and **sync** (how content moves).

### Axis 1 — Mode (What Claude Sees)

Mode controls which copy of the engine is active — the local Git checkout or the GDrive shared drive.

| Command | Effect | Symlinks point to |
|---------|--------|-------------------|
| `engine local` | Switch to local development mode | `~/.claude/engine/` |
| `engine remote` | Switch to GDrive production mode | GDrive shared drive path |

**What mode switching does:**
- Rewrites all `~/.claude/` symlinks (scripts, skills, hooks, agents, tools) to point at the selected engine copy
- Writes the mode to `~/.claude/engine/.mode` (read by `engine status`)
- Installs npm deps for tools if missing (local mode only)
- Bootstraps search DBs from GDrive if available (local mode only)

**What mode switching does NOT do:**
- Copy, sync, or transfer any files between copies
- Touch session data or search databases (except the initial DB bootstrap on `engine local`)
- Commit, push, or deploy anything

### Axis 2 — Sync (How Content Moves)

Sync operations move content between the three locations: local engine, GitHub, and GDrive.

| Command | Direction | Mechanism | What moves |
|---------|-----------|-----------|------------|
| `engine push` | Local → GitHub | `git push` | Everything tracked by Git |
| `engine pull` | GitHub → Local | `git pull` | Everything tracked by Git |
| `engine deploy` | Local → GDrive | `rsync --delete` | Everything except `.git`, `.mode`, `.user.json`, `node_modules` |

**Key principle**: These axes are **orthogonal**. `push` does not touch GDrive. `deploy` does not touch Git. Mode switching does not sync. Each operation has exactly one effect.

---

## The Developer Workflow

The daily development cycle, from start to finish:

```
Step 1:  engine local              One-time. Switch symlinks to local Git checkout.
Step 2:  Edit engine code          Scripts, skills, hooks in ~/.claude/engine/.
Step 3:  git commit                Ad-hoc, when convenient. In ~/.claude/engine/.
Step 4:  engine push               Save to GitHub. Backup + collaboration.
Step 5:  engine deploy             Sync to GDrive. The "release" step.
Step 6:  [optional] engine remote  Verify the GDrive copy looks right.
Step 7:  [optional] engine local   Switch back to continue developing.
```

**Rules:**
- Always develop in local mode (`¶ENG_LOCAL_MODE_DEVELOPMENT`). The local copy is a Git repo; GDrive is not.
- Push and deploy are independent (`¶ENG_PUSH_AND_DEPLOY_SEPARATE`). Run both when releasing; push alone for backup; deploy alone for quick team updates.
- `.git` never touches GDrive (`¶ENG_NO_GIT_ON_GDRIVE`). The deploy excludes it.

---

## Sessions vs. Engine

These are independent systems with separate storage and sync mechanisms.

| Concern | Engine | Sessions |
|---------|--------|----------|
| **What** | Scripts, hooks, skills, tools, agents | Logs, plans, debriefs, details |
| **Where** | `~/.claude/engine/` (local) or GDrive shared drive (remote) | `./sessions/` in each project root |
| **Scope** | Shared across all projects | Per-project |
| **Sync** | Git + `engine deploy` | GDrive symlink (remote) or local dir (local) |
| **Managed by** | `engine.sh` | `session.sh` |

In **remote mode**, `sessions/` is a symlink to GDrive:
```
./sessions/ → ~/Library/CloudStorage/GoogleDrive-user@domain/Shared drives/finch-os/username/projectname/sessions/
```

In **local mode**, `engine local` ensures `sessions/` exists as a real local directory. If a GDrive symlink exists but is broken (GDrive offline), it's replaced with a local dir.

---

## Search Databases

Two SQLite databases power the search tools:

| Database | File | Indexed content | Tool |
|----------|------|-----------------|------|
| Doc search | `sessions/.doc-search.db` | Project documentation files | `doc-search.sh` |
| Session search | `sessions/.session-search.db` | Session debriefs and logs | `session-search.sh` |

### Location
Both DBs live inside `sessions/` — they index project-specific content and belong near it.

### Bootstrapping
When switching to local mode (`engine local`):
1. If GDrive is accessible, copies the DBs from GDrive `sessions/` to local `sessions/`
2. If GDrive is unavailable, the DBs start empty. Run `doc-search.sh index && session-search.sh index` to rebuild.

### Schema Changes
Search DBs use **delete-and-rebuild** (`¶ENG_SEARCH_DB_REBUILD`). No formal migrations — delete the `.db` file and re-index. The source data (session files, project docs) is the source of truth; the DB is a derived cache.

---

## Git Model

| Property | Value |
|----------|-------|
| Repository | `git@github.com:idealic-ai/engine.git` |
| Branch pattern | `{username}/engine` (e.g., `yarik/engine`) |
| Commit cadence | Ad-hoc — when convenient, not tied to deploy |
| Multi-developer | Yes — each developer has their own branch |

### First-Time Git Setup
`engine local` handles Git onboarding automatically:
1. Detects that `~/.claude/engine/` has no `.git` directory
2. Prompts for the Git repository URL (or reads from `.user.json` if cached)
3. Clones into a temp dir, moves `.git` into the existing engine directory
4. Creates the personal branch (`{username}/engine`)
5. Caches the repo URL and branch in `.user.json`

### Merge Conflicts
`engine pull` detects merge conflicts and outputs resolution instructions:
```
MERGE CONFLICT detected.
Conflicted files:
  - scripts/session.sh
To resolve:
  1. cd ~/.claude/engine
  2. Edit conflicted files
  3. git add <resolved-files>
  4. git commit
```

---

## First-Time Setup

`engine setup [project-name]` runs the full initialization sequence:

1. **Dependencies**: Installs `jq`, `sqlite3`, `fswatch` via Homebrew (if available)
2. **GDrive directories**: Creates `sessions/` and `reports/` on the shared drive
3. **Engine symlinks**: Links `~/.claude/{scripts,skills,hooks,agents,tools,commands,standards}` to the active engine
4. **Migrations**: Runs any pending numbered migrations from `setup-migrations.sh`
5. **Project symlinks**: Links `./sessions/` and `./reports/` to GDrive paths
6. **Project directives**: Creates `.claude/.directives/INVARIANTS.md` stub if missing
7. **Gitignore**: Adds `sessions` and `reports` to `.gitignore`
8. **Permissions**: Configures `~/.claude/settings.json` (engine permissions, hooks, statusLine)
9. **Global symlink**: Creates `/usr/local/bin/engine` (may require sudo)

Running `engine` with no arguments auto-triggers setup on first run (detected via `.setup-done` marker).

---

## Troubleshooting

### Symlinks pointing to wrong engine
Run `engine status` to audit. If mismatched, run `engine local` or `engine remote` to re-link.

### GDrive not accessible
`engine local` gracefully handles this: broken `sessions/` symlinks are replaced with local directories. Search DBs start empty — rebuild with `doc-search.sh index`.

### Scripts not executable
GDrive sync strips `+x` permissions. `engine local` and `engine setup` both call `fix_script_permissions` to restore them. Manual fix: `find ~/.claude/engine -name "*.sh" -exec chmod +x {} +`.

### Stale `/usr/local/bin/engine` symlink
Every `engine` launch checks the symlink target and updates it if stale. If it points to a different engine path (e.g., after reinstall), it auto-corrects.

---

## Related Documentation

| Document | Location | Covers |
|----------|----------|--------|
| `CONTRIBUTING.md` | `~/.claude/engine/CONTRIBUTING.md` | Development rules (the directive) |
| `scripts/CONTRIBUTING.md` | `~/.claude/engine/scripts/CONTRIBUTING.md` | Script and test conventions |
| `ENGINE_CLI.md` | `~/.claude/docs/ENGINE_CLI.md` | CLI protocol, function signatures, migration system |
| `INVARIANTS.md` | `~/.claude/engine/docs/INVARIANTS.md` | Engine-specific invariants (tmux, hooks) |
| `CONTRIBUTING.md` | `~/.claude/engine/CONTRIBUTING.md` | Dev environment setup and architecture |
