# Engine CLI Protocol

How to safely modify `engine.sh`, write testable additions, and manage migrations across the team.

**Applies to**: `~/.claude/engine/scripts/engine.sh`, `setup-lib.sh`, `setup-migrations.sh`

## Architecture

```
engine.sh                      # CLI entry point — parses args, orchestrates setup
setup-lib.sh                  # Pure functions (symlinking, mode resolution, settings merge)
setup-migrations.sh           # Numbered idempotent migrations
```

**Current state**: `engine.sh` sources both `setup-lib.sh` and `setup-migrations.sh` via `source "$SCRIPT_DIR/setup-lib.sh"`. Mode helpers, symlink functions, and engine orchestration use the lib versions with explicit parameters. The migration runner (`run_migrations`) is called after engine symlinks in the normal setup flow. Tests also source the libs directly for unit testing.

### Files

| File | Role | Testable? |
|------|------|-----------|
| `engine.sh` | CLI dispatcher — arg parsing, subcommand routing, orchestration | Integration only |
| `setup-lib.sh` | Pure functions — no globals, all inputs via parameters or env vars | Unit testable |
| `setup-migrations.sh` | Numbered migrations — each is an idempotent function | Unit testable |
| `tests/test-setup-lib.sh` | Tests for setup-lib.sh functions | — |
| `tests/test-setup-migrations.sh` | Tests for each migration | — |
| `tests/test-engine-integration.sh` | End-to-end integration tests for engine.sh | — |

## Environment Variable Injection

Every path that engine.sh uses is overridable via env var. This is the primary testability mechanism — tests set these to temp directories.

| Env Var | Default | What It Controls |
|---------|---------|-----------------|
| `SETUP_CLAUDE_DIR` | `$HOME/.claude` | Where symlinks are created (`~/.claude/scripts/`, etc.) |
| `SETUP_ENGINE_DIR` | `$HOME/.claude/engine` | Local engine directory |
| `SETUP_GDRIVE_ROOT` | Auto-detected from email | GDrive shared drive root |
| `SETUP_MODE_FILE` | `$SETUP_ENGINE_DIR/.mode` | File that stores current mode (`local`/`remote`) |
| `SETUP_PROJECT_ROOT` | `$(pwd)` | Project root for project-level setup |
| `SETUP_MIGRATION_STATE` | `$SETUP_CLAUDE_DIR/engine/.migrations` | State file tracking applied migrations |
| `SETUP_DRY_RUN` | unset | If set to `1`, log actions but don't execute filesystem changes |

### Usage in Tests

```bash
setup() {
  TEST_DIR=$(mktemp -d)
  export SETUP_CLAUDE_DIR="$TEST_DIR/claude"
  export SETUP_ENGINE_DIR="$TEST_DIR/engine"
  export SETUP_GDRIVE_ROOT="$TEST_DIR/gdrive"
  export SETUP_MODE_FILE="$TEST_DIR/engine/.mode"
  export SETUP_PROJECT_ROOT="$TEST_DIR/project"

  # Create fake engine tree
  mkdir -p "$SETUP_ENGINE_DIR"/{scripts,hooks,skills/brainstorm,skills/implement,commands,standards,agents}
  touch "$SETUP_ENGINE_DIR/scripts/session.sh"
  touch "$SETUP_ENGINE_DIR/scripts/log.sh"
  touch "$SETUP_ENGINE_DIR/hooks/pre-tool-use-overflow.sh"
  chmod +x "$SETUP_ENGINE_DIR"/scripts/*.sh "$SETUP_ENGINE_DIR"/hooks/*.sh

  mkdir -p "$SETUP_CLAUDE_DIR"
  mkdir -p "$SETUP_PROJECT_ROOT"
}

teardown() {
  rm -rf "$TEST_DIR"
  unset SETUP_CLAUDE_DIR SETUP_ENGINE_DIR SETUP_GDRIVE_ROOT SETUP_MODE_FILE SETUP_PROJECT_ROOT SETUP_DRY_RUN
}
```

### Usage in Production (engine.sh)

```bash
# At top of engine.sh, after sourcing setup-lib.sh:
CLAUDE_DIR="${SETUP_CLAUDE_DIR:-$HOME/.claude}"
LOCAL_ENGINE="${SETUP_ENGINE_DIR:-$HOME/.claude/engine}"
MODE_FILE="${SETUP_MODE_FILE:-$LOCAL_ENGINE/.mode}"
# etc.
```

## setup-lib.sh — Function Library

### Design Rules

1. **No global reads**: Functions receive ALL inputs as parameters. Never read `$CLAUDE_DIR` etc. directly — pass them in.
2. **No interactive prompts**: Functions that need confirmation return a status code; the caller handles the prompt.
3. **Return values via stdout**: Functions that compute values echo them. Functions that modify filesystem return 0/1.
4. **ACTIONS array**: Logging-only side effect. Functions append to `ACTIONS` (declared by caller). Tests can inspect it.

### Function Signatures

```bash
# Mode resolution
current_mode "$mode_file"
# → echoes "local" or "remote"

resolve_engine_dir "$mode" "$local_engine" "$gdrive_engine" "$script_dir"
# → echoes resolved engine directory path, or "" if not found

# Symlinking (core)
link_if_needed "$target" "$link_path" "$display_name" "$interactive"
# → creates/updates symlink. $interactive=0 skips read -rp for real dirs (returns 2 instead)

link_files_if_needed "$src_dir" "$dest_dir" "$display_name"
# → per-file symlinks from src_dir/* to dest_dir/*

setup_engine_symlinks "$engine_dir" "$claude_dir"
# → orchestrates all engine symlinks

# Settings.json
merge_permissions "$settings_file" "$permissions_json"
# → merges permission rules into settings.json using jq

configure_hooks "$settings_file"
# → deep-merges hook configuration into settings.json
# Uses add_if_missing jq helper: checks by command path, only adds missing entries.
# Preserves user-added custom hooks — never overwrites existing entries.

configure_statusline "$settings_file"
# → adds statusLine hook to settings.json

# Project setup
link_project_dir "$target" "$link_path" "$display_name"
# → symlinks project dirs (sessions/, reports/)

ensure_project_standards "$project_root"
# → creates .claude/.directives/INVARIANTS.md stub if missing

update_gitignore "$project_root" "sessions" "reports"
# → adds entries to .gitignore if missing

fix_script_permissions "$engine_dir"
# → ensures all .sh files in engine are executable (GDrive sync strips +x)
```

### What STAYS in engine.sh (Not Extracted)

- Arg parsing (`while [[ $# -gt 0 ]]`)
- Email/identity inference (GDrive path detection)
- `cmd_pull` / `cmd_push` (rsync operations — too environment-specific to unit test)
- `brew install` / `npm install` (external package managers)
- Interactive prompts (user confirmation before destructive ops)

These are tested via integration tests or manual QA. They're the "shell" around the testable core.

## cmd_uninstall — Cleanup Subcommand

Removes all engine-created artifacts from the user's environment. Invoked via `engine.sh uninstall`.

### What It Cleans

| Category | What | How |
|----------|------|-----|
| **Project symlinks** | `sessions/`, `reports/` in project root | Remove symlinks |
| **User-level symlinks** | `~/.claude/skills`, `~/.claude/agents`, `~/.claude/hooks` | Remove symlinks |
| **Per-file symlinks** | Individual files inside `~/.claude/scripts/`, `~/.claude/skills/`, `~/.claude/hooks/` | Iterate dir, remove each symlink pointing into engine |
| **Hook settings** | `statusLine`, all `hooks.*` entries referencing `~/.claude/hooks/` or `~/.claude/tools/` | `jq` removal from `settings.json` |
| **Engine permissions** | Engine-specific permission entries in `settings.json` | `jq` removal from `settings.json` |
| **Global symlink** | `/usr/local/bin/engine` | Remove (may require `sudo`) |

### Design Notes

- **Per-file symlinks**: After `migration_001`, `scripts/` is a real directory with per-file symlinks inside (not a whole-dir symlink). The uninstall loop iterates `scripts/ skills/ agents/ hooks/` and removes individual symlinks.
- **Hook cleanup**: Uses `jq` to surgically remove engine-owned keys from `settings.json`. Preserves any user-added settings that don't reference engine paths.
- **Preserved**: `settings.json` file itself is preserved (not deleted). Only engine-owned entries are removed.
- **Idempotent**: Safe to run multiple times — checks existence before removal.

### Test Coverage

9 dedicated uninstall tests in `test-engine-integration.sh` verify:
- Project symlink removal
- User-level symlink removal
- Per-file symlink cleanup (scripts/, skills/, hooks/)
- Hook cleanup from settings.json (statusLine, hooks.*, permissions)

## setup-migrations.sh — Migration System

### Design

Each migration is a numbered, idempotent bash function. Migrations run in order. A state file tracks which have been applied.

```bash
# ~/.claude/engine/scripts/setup-migrations.sh

SETUP_MIGRATION_STATE="${SETUP_CLAUDE_DIR:-$HOME/.claude}/engine/.migrations"

# Registry — add new migrations at the bottom
MIGRATIONS=(
  "001:perfile_scripts_hooks"
  "002:perfile_skills"
  "003:state_json_rename"
  "004:remove_stale_skill_symlinks"
  "005:add_hooks_to_settings"
)

# --- Migration functions ---

migration_001_perfile_scripts_hooks() {
  local claude_dir="${1:?}"
  local engine_dir="${2:-}"
  # Migrate whole-dir symlinks for scripts/ and hooks/ to per-file
  for name in scripts hooks; do
    local link="$claude_dir/$name"
    if [ -L "$link" ] && [ -d "$link" ]; then
      local target=$(readlink "$link")
      if [[ "$target" == *"engine"* ]] || [[ "$target" == *"GoogleDrive"* ]]; then
        rm "$link"
        mkdir -p "$link"
        for f in "$target"/*; do
          [ -e "$f" ] || continue
          ln -s "$f" "$link/$(basename "$f")"
        done
      fi
    fi
  done
  return 0
}

migration_002_perfile_skills() {
  local claude_dir="${1:?}"
  local engine_dir="${2:-}"
  # Migrate whole-dir skills symlink to per-skill
  local skills_link="$claude_dir/skills"
  if [ -L "$skills_link" ] && [ -d "$skills_link" ]; then
    local target=$(readlink "$skills_link")
    rm "$skills_link"
    mkdir -p "$skills_link"
    for skill_dir in "$target"/*/; do
      [ -d "$skill_dir" ] || continue
      local skill_name=$(basename "$skill_dir")
      ln -s "$skill_dir" "$skills_link/$skill_name"
    done
  fi
  return 0
}

migration_003_state_json_rename() {
  local claude_dir="${1:?}"
  local sessions_dir="${2:-}"
  # Rename .agent.json → .state.json in all sessions
  if [ -z "$sessions_dir" ] || [ ! -d "$sessions_dir" ]; then
    return 0
  fi
  find "$sessions_dir" -name ".agent.json" -type f 2>/dev/null | while read -r f; do
    local dir=$(dirname "$f")
    if [ ! -f "$dir/.state.json" ]; then
      mv "$f" "$dir/.state.json"
    fi
  done
  return 0
}

# --- Runner ---

run_migrations() {
  local claude_dir="${1:?}"
  local sessions_dir="${2:-}"
  local engine_dir="${3:-}"
  local state_file="${SETUP_MIGRATION_STATE:-$claude_dir/engine/.migrations}"

  mkdir -p "$(dirname "$state_file")"
  touch "$state_file"

  local applied=0
  for entry in "${MIGRATIONS[@]}"; do
    local num="${entry%%:*}"
    local name="${entry#*:}"
    if grep -q "^$num:" "$state_file" 2>/dev/null; then
      continue  # already applied
    fi
    echo "  Migration $num: $name..."
    if "migration_${num}_${name}" "$claude_dir" "${sessions_dir:-}" "${engine_dir:-}"; then
      echo "$num:$name:$(date +%s)" >> "$state_file"
      applied=$((applied + 1))
    else
      echo "ERROR: Migration $num ($name) failed"
      return 1
    fi
  done

  if [ "$applied" -eq 0 ]; then
    echo "  All migrations up to date."
  else
    echo "  Applied $applied migration(s)."
  fi
}
```

### Writing a New Migration

**Checklist** (every migration MUST satisfy all):

1. **Number**: Next sequential number (e.g., `004`). Never reuse or reorder.
2. **Idempotent**: Running twice produces the same result. Check before acting.
3. **Self-contained**: No dependencies on other migrations having run first (if there IS a dependency, document it in the function comment).
4. **Parameters**: Receive all paths as parameters. Never read globals.
5. **Return code**: `return 0` on success (including "already done"). `return 1` on failure.
6. **Test**: Add a test case in `test-setup-migrations.sh` BEFORE merging.

**Template**:

```bash
# Add to MIGRATIONS array:
#   "NNN:descriptive_name"

migration_NNN_descriptive_name() {
  local claude_dir="${1:?}"
  # What: [one-line description of what this migration does]
  # Why: [why this migration is needed — link to PR or issue if applicable]
  # Idempotency: [how it detects "already done" state]

  # Check if already applied
  if [ ... already migrated condition ... ]; then
    return 0
  fi

  # Do the migration
  ...

  return 0
}
```

**Test template**:

```bash
test_migration_NNN_fresh() {
  # Setup: create the PRE-migration state
  ...
  # Run (pass claude_dir + sessions_dir + engine_dir as needed)
  migration_NNN_descriptive_name "$SETUP_CLAUDE_DIR" "$SESSIONS_DIR" "$SETUP_ENGINE_DIR"
  # Assert: POST-migration state
  ...
  pass "migration NNN: fresh apply"
}

test_migration_NNN_idempotent() {
  # Setup: create the POST-migration state (already migrated)
  ...
  # Run
  migration_NNN_descriptive_name "$SETUP_CLAUDE_DIR" "$SESSIONS_DIR" "$SETUP_ENGINE_DIR"
  # Assert: nothing changed
  ...
  pass "migration NNN: idempotent (no-op on re-run)"
}

test_migration_NNN_partial() {
  # Setup: create a PARTIALLY migrated state (e.g., crash mid-migration)
  ...
  # Run
  migration_NNN_descriptive_name "$SETUP_CLAUDE_DIR" "$SESSIONS_DIR" "$SETUP_ENGINE_DIR"
  # Assert: completes correctly
  ...
  pass "migration NNN: handles partial state"
}
```

### Migration Runner Behavior

- `run_migrations` is called at the END of `engine.sh`'s normal flow (after symlinks, before summary)
- State file (`.migrations`) is a simple text file: `001:name:timestamp` per line
- Migrations run in numeric order, skipping already-applied ones
- On failure: stops immediately, does NOT mark the failed migration as applied
- `engine.sh --migrate-only`: runs only migrations (no setup flow) — useful for testing

## Test Suite Design

### test-setup-lib.sh — Library Function Tests

Tests the extracted pure functions. Pattern: HOME override + fake engine tree.

**Categories**:

| Category | Functions Tested | Estimated Tests |
|----------|-----------------|----------------|
| Mode resolution | `current_mode`, `resolve_engine_dir` | 8 |
| Symlink creation | `link_if_needed`, `link_files_if_needed` | 14 |
| Engine orchestration | `setup_engine_symlinks`, `fix_script_permissions` | 10 |
| Settings merge | `merge_permissions`, `configure_hooks` (deep-merge), `configure_statusline` | 19 |
| Project setup | `link_project_dir`, `ensure_project_standards`, `update_gitignore` | 18 |
| **Total** | | **69** |

**Key scenarios per function**:

`link_if_needed`:
- Create new symlink (target exists, link doesn't)
- Update existing symlink (different target)
- Skip when already correct (idempotent)
- Handle real directory (non-interactive mode returns 2)
- Handle broken symlink

`link_files_if_needed`:
- Migrate from whole-dir symlink to per-file
- Create per-file symlinks from scratch
- Skip existing correct symlinks
- Preserve local overrides (real file in dest_dir)
- Handle empty source directory

`setup_engine_symlinks`:
- Full engine tree — all dirs linked
- Partial engine tree — missing dirs handled
- Permission fixing (create non-executable .sh, verify chmod)
- Skills per-skill migration
- Tools linkage + tool script symlinks

`merge_permissions`:
- Create new settings.json from scratch
- Merge into existing settings (dedup rules)
- Preserve existing non-permission settings
- Handle empty/malformed settings.json

### test-setup-migrations.sh — Migration Tests

Each migration gets 2-3 tests (fresh, idempotent, partial). Plus runner tests.

**Categories**:

| Category | What's Tested | Estimated Tests |
|----------|---------------|----------------|
| Migration 001 | perfile_scripts_hooks | 3 |
| Migration 002 | perfile_skills | 3 |
| Migration 003 | state_json_rename | 3 |
| Migration 004 | remove_stale_skill_symlinks (fresh, idempotent, real-dir-safe, no-skills-dir) | 6 |
| Migration 005 | add_hooks_to_settings (adds hooks, preserves existing, idempotent, no-settings) | 7 |
| Runner | ordering, state tracking, failure handling, pending count | 14 |
| **Total** | | **36** |

**Runner tests**:
- Runs all pending migrations in order
- Skips already-applied migrations
- Records applied migrations to state file
- Stops on failure, doesn't mark failed
- `--migrate-only` flag works

### test-engine-integration.sh — End-to-End Tests

Tests engine.sh as a whole — subcommands, project flow, migration runner, and lib function integration. Uses a fully sandboxed environment.

**Sandbox approach**:
- Override `HOME` to a temp dir (`$TEST_ROOT/home/`)
- Export `PROJECT_ROOT` to `$TEST_ROOT/project/` (prevents engine.sh from using real `pwd`)
- Place engine.sh + libs in a fake GDrive path so EMAIL auto-detection works
- Create fake `user-info.sh` that returns test email
- All `engine.sh` invocations wrapped in `cd "$PROJECT_DIR" && ...` as defense-in-depth

**Categories**:

| Category | IDs | What's Tested | Tests |
|----------|-----|---------------|-------|
| Source integration | SRC-01 | Libs load without file-not-found errors | 1 |
| local subcommand | LOCAL-01..03 | Symlinks, mode file, output | 3 |
| remote subcommand | REMOTE-01..03 | Symlinks, mode file, output | 3 |
| status subcommand | STATUS-01..03 | Mode display, symlink audit, consistency | 3 |
| Project flow | FLOW-01..08 | Engine symlinks, scripts/hooks dirs, skills, sessions symlink, standards | 8 |
| Migration runner | MIG-01..04 | State file creation, all migrations recorded, idempotent re-run | 4 |
| Lib verification | LIB-01..02 | Non-interactive mode for real dirs | 2 |
| Permissions | PERM-01 | fix_script_permissions restores +x | 1 |
| Uninstall | UNSUB-01..09 | Project/user symlinks, per-file cleanup, hook/permissions removal | 9 |
| Test subcommand | TEST-01..09 | Runs test suite, sandbox isolation, output formatting | 9 |
| Pull/push | PULL/PUSH-01..09 | Rsync operations, mode switching, conflict detection | 9 |
| **Total** | | | **52** |

**Critical safety rule** (see `¶INV_TEST_SANDBOX_ISOLATION`):
- NEVER run engine.sh from the real project root in tests
- ALWAYS export `PROJECT_ROOT` to the sandbox before invoking engine.sh
- ALWAYS `cd "$PROJECT_DIR"` before `bash "$SETUP_SH" ...`
- Failure to do so will overwrite the real `sessions/` symlink (which points to Google Drive)

## PR Checklist for engine.sh Changes

Before merging ANY change to engine.sh, setup-lib.sh, or setup-migrations.sh:

- [ ] **New function?** → Added to `setup-lib.sh` with parameterized inputs (no globals)
- [ ] **New migration?** → Added to `MIGRATIONS` array with next sequential number
- [ ] **Test coverage** → New/modified functions have test cases in `test-setup-lib.sh` or `test-setup-migrations.sh`
- [ ] **Idempotent** → Running `engine.sh` twice produces the same result
- [ ] **All suites green** → `bash ~/.claude/engine/scripts/tests/run-all.sh` passes
- [ ] **Env var injection** → No new hardcoded paths — use `$SETUP_*` vars with defaults
- [ ] **No interactive prompts in lib** → Prompts stay in engine.sh, not setup-lib.sh
- [ ] **Integration tests pass** → `bash ~/.claude/engine/scripts/tests/test-engine-integration.sh` passes
- [ ] **Sandbox isolation** → Any new integration test exports `PROJECT_ROOT` and uses `cd "$PROJECT_DIR"` (see `¶INV_TEST_SANDBOX_ISOLATION`)

## Reference: Current Migration History

These migrations were originally inline in `engine.sh` and are being extracted:

| # | Name | Origin | What It Does |
|---|------|--------|-------------|
| 001 | perfile_scripts_hooks | engine.sh `link_files_if_needed` migration logic | Converts whole-dir symlinks for `scripts/` and `hooks/` to per-file symlinks |
| 002 | perfile_skills | engine.sh `setup_engine_symlinks` migration logic | Converts whole-dir `skills/` symlink to per-skill symlinks |
| 003 | state_json_rename | engine session activate migration logic | Renames `.agent.json` to `.state.json` across all sessions |
| 004 | remove_stale_skill_symlinks | Analysis recommendation §5.1 | Removes symlinks in `skills/` that point to dirs without `SKILL.md` |
| 005 | add_hooks_to_settings | Analysis recommendation §5.3 | Deep-merges 4 new hook entries into `settings.json` (preserves existing user hooks) |
