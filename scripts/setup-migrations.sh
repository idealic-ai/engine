#!/bin/bash
# ============================================================================
# Setup Migrations — Numbered idempotent migrations for engine state
# ============================================================================
# Sourced by engine.sh. Each migration is a function that transforms engine
# state from version N to N+1. Migrations are idempotent — safe to run twice.
#
# Related:
#   Docs: (~/.claude/docs/)
#     SETUP_PROTOCOL.md — Migration protocol, numbering, idempotency
#
# See ~/.claude/docs/SETUP_PROTOCOL.md for the full protocol on adding
# new migrations, testing requirements, and the PR checklist.
#
# Usage (standalone):
#   source setup-migrations.sh
#   run_migrations "$claude_dir" "$sessions_dir"
#
# Adding a new migration:
#   1. Add "NNN:descriptive_name" to MIGRATIONS array (next sequential number)
#   2. Write migration_NNN_descriptive_name() function below
#   3. Add tests in tests/test-setup-migrations.sh (fresh + idempotent + partial)
#   4. Run tests: bash tests/test-setup-migrations.sh
# ============================================================================

# ---- Migration registry ----
# Format: "NNN:function_suffix"
# Functions must be named: migration_NNN_function_suffix
# Order matters — migrations run top to bottom.

MIGRATIONS=(
  "001:perfile_scripts_hooks"
  "002:perfile_skills"
  "003:state_json_rename"
  "004:remove_stale_skill_symlinks"
  "005:add_hooks_to_settings"
  "006:hooks_to_project_local"
)

# ---- Migration functions ----

# migration_001_perfile_scripts_hooks "$claude_dir" "$engine_dir"
# What: Convert whole-dir symlinks for scripts/ and hooks/ to per-file symlinks.
# Why: Per-file symlinks allow local overrides without breaking the engine link.
# Idempotency: Checks if target is a whole-dir symlink. If already a directory, no-op.
migration_001_perfile_scripts_hooks() {
  local claude_dir="${1:?}"
  local engine_dir="${2:-}"

  for name in scripts hooks; do
    local link="$claude_dir/$name"
    if [ -L "$link" ] && [ -d "$link" ]; then
      local target
      target=$(readlink "$link")
      # Only migrate if it's a whole-dir symlink to the engine
      if [[ "$target" == *"engine"* ]] || [[ "$target" == *"GoogleDrive"* ]] || [[ "$target" == *"CloudStorage"* ]]; then
        rm "$link"
        mkdir -p "$link"
        for f in "$target"/*; do
          [ -e "$f" ] || continue
          ln -s "$f" "$link/$(basename "$f")"
        done
      fi
    fi
    # If it's already a directory (not symlink), it's already migrated
  done
  return 0
}

# migration_002_perfile_skills "$claude_dir" "$engine_dir"
# What: Convert whole-dir skills/ symlink to per-skill symlinks.
# Why: Per-skill symlinks allow project-local skill overrides.
# Idempotency: Checks if skills/ is a symlink. If already a directory, no-op.
migration_002_perfile_skills() {
  local claude_dir="${1:?}"
  local engine_dir="${2:-}"

  local skills_link="$claude_dir/skills"
  if [ -L "$skills_link" ] && [ -d "$skills_link" ]; then
    local target
    target=$(readlink "$skills_link")
    rm "$skills_link"
    mkdir -p "$skills_link"
    for skill_dir in "$target"/*/; do
      [ -d "$skill_dir" ] || continue
      local skill_name
      skill_name=$(basename "$skill_dir")
      ln -s "$skill_dir" "$skills_link/$skill_name"
    done
  fi
  return 0
}

# migration_003_state_json_rename "$claude_dir" "$sessions_dir"
# What: Rename .agent.json → .state.json in all session directories.
# Why: Renamed for clarity — .state.json better describes session state tracking.
# Idempotency: Only renames if .agent.json exists AND .state.json doesn't.
migration_003_state_json_rename() {
  local claude_dir="${1:?}"
  local sessions_dir="${2:-}"

  # If no sessions dir provided or doesn't exist, nothing to do
  if [ -z "$sessions_dir" ] || [ ! -d "$sessions_dir" ]; then
    return 0
  fi

  find "$sessions_dir" -name ".agent.json" -type f 2>/dev/null | while read -r f; do
    local dir
    dir=$(dirname "$f")
    if [ ! -f "$dir/.state.json" ]; then
      mv "$f" "$dir/.state.json"
    fi
  done
  return 0
}

# migration_004_remove_stale_skill_symlinks "$claude_dir"
# What: Remove skill symlinks that point to empty/invalid dirs (no SKILL.md).
# Why: Deprecated skills (e.g., /critique) leave dead symlinks cluttering the catalog.
# Idempotency: Only removes symlinks whose targets lack SKILL.md. Real dirs untouched.
migration_004_remove_stale_skill_symlinks() {
  local claude_dir="${1:?}"

  local skills_dir="$claude_dir/skills"
  [ -d "$skills_dir" ] || return 0

  for entry in "$skills_dir"/*/; do
    [ -d "$entry" ] || continue
    local skill_name
    skill_name=$(basename "$entry")
    local link="$skills_dir/$skill_name"

    # Only act on symlinks, not real directories (local overrides)
    [ -L "$link" ] || continue

    local target
    target=$(readlink "$link")

    # Check if the target directory has a SKILL.md
    if [ ! -f "$target/SKILL.md" ]; then
      rm "$link"
    fi
  done
  return 0
}

# migration_005_add_hooks_to_settings "$claude_dir"
# What: Deep-merge 4 new hook entries into ~/.claude/settings.json for existing users.
# Why: New installs get hooks via configure_hooks(). Existing users need this migration.
# Hooks added: pre-tool-use-heartbeat, pre-tool-use-session-gate,
#   post-tool-use-discovery, user-prompt-submit-session-gate
# Idempotency: Skips if hooks already present (checks by command path).
migration_005_add_hooks_to_settings() {
  local claude_dir="${1:?}"

  local settings="$claude_dir/settings.json"
  # If no settings.json or no jq, skip — configure_hooks() handles fresh installs
  [ -f "$settings" ] || return 0
  command -v jq &>/dev/null || return 0

  # Define the 4 new hook entries to merge
  local merged
  merged=$(cat "$settings" | jq '
    # Helper: add entry to array if command not already present
    def add_if_missing(entry):
      if any(.[]; .hooks[]? | .command == (entry | .hooks[0].command))
      then .
      else . + [entry]
      end;

    # PreToolUse: add heartbeat + session-gate
    .hooks.PreToolUse = ((.hooks.PreToolUse // [])
      | add_if_missing({
          "matcher": "*",
          "hooks": [{
            "type": "command",
            "command": "~/.claude/hooks/pre-tool-use-heartbeat.sh",
            "timeout": 10,
            "statusMessage": "Checking logging..."
          }]
        })
      | add_if_missing({
          "matcher": "*",
          "hooks": [{
            "type": "command",
            "command": "~/.claude/hooks/pre-tool-use-session-gate.sh",
            "timeout": 5,
            "statusMessage": "Checking session..."
          }]
        })
    )

    # PostToolUseSuccess: discovery hook removed (moved to PreToolUse)

    # UserPromptSubmit: add session-gate
    | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // [])
      | add_if_missing({
          "hooks": [{
            "type": "command",
            "command": "~/.claude/hooks/user-prompt-submit-session-gate.sh",
            "timeout": 5
          }]
        })
    )
  ' 2>/dev/null) || return 0

  echo "$merged" > "$settings"
  return 0
}

# migration_006_hooks_to_project_local "$claude_dir"
# What: Strip hooks, statusLine, and engine permissions from global ~/.claude/settings.json.
# Why: Engine config moves to project-local .claude/settings.json. Global should only hold
#   non-engine user config. setup-lib.sh configure_hooks() now targets project settings.
# Idempotency: If hooks/statusLine already absent, no-op. If settings.json missing, no-op.
migration_006_hooks_to_project_local() {
  local claude_dir="${1:?}"

  local settings="$claude_dir/settings.json"
  # If no settings.json or no jq, skip
  [ -f "$settings" ] || return 0
  command -v jq &>/dev/null || return 0

  # Engine permission patterns to remove from global
  # These are the exact entries that setup-lib.sh / engine.sh add
  local engine_perms=(
    'Bash(engine *)'
    'Bash(~/.claude/scripts/*)'
    'Bash(~/.claude/tools/doc-search/doc-search.sh *)'
    'Bash(~/.claude/tools/session-search/session-search.sh *)'
    'Glob(reports/**)'
    'Glob(sessions/**)'
    'Glob(~/.claude/**)'
    'Grep(reports/**)'
    'Grep(sessions/**)'
    'Grep(~/.claude/**)'
    'Read(reports/**)'
    'Read(sessions/**)'
    'Read(~/.claude/agents/**)'
    'Read(~/.claude/commands/**)'
    'Read(~/.claude/.directives/**)'
    'Read(~/.claude/skills/**)'
  )

  # Build a jq array from the patterns
  local jq_array="["
  local first=true
  for perm in "${engine_perms[@]}"; do
    if [ "$first" = true ]; then
      first=false
    else
      jq_array+=","
    fi
    jq_array+="\"$perm\""
  done
  jq_array+="]"

  local stripped
  stripped=$(cat "$settings" | jq --argjson engine_perms "$jq_array" '
    # Remove hooks section entirely
    del(.hooks)
    # Remove statusLine section entirely
    | del(.statusLine)
    # Remove engine-specific permission entries
    | if .permissions.allow then
        .permissions.allow = [.permissions.allow[] | select(. as $p | $engine_perms | index($p) | not)]
      else . end
    # Clean up empty permissions
    | if .permissions.allow == [] then del(.permissions) else . end
  ' 2>/dev/null) || return 0

  echo "$stripped" > "$settings"
  return 0
}

# ---- Migration runner ----

# run_migrations "$claude_dir" ["$sessions_dir"] ["$engine_dir"]
# Runs all pending migrations in order. Tracks state in .migrations file.
# Returns 0 if all succeed, 1 on first failure.
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
    if grep -q "^${num}:" "$state_file" 2>/dev/null; then
      continue
    fi
    echo "  Migration $num: $name..."
    if "migration_${num}_${name}" "$claude_dir" "${sessions_dir:-}" "${engine_dir:-}"; then
      echo "${num}:${name}:$(date +%s)" >> "$state_file"
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
  return 0
}

# pending_migrations "$state_file"
# Echoes the count of pending (not-yet-applied) migrations.
pending_migrations() {
  local state_file="${1:?}"

  if [ ! -f "$state_file" ]; then
    echo "${#MIGRATIONS[@]}"
    return
  fi

  local pending=0
  for entry in "${MIGRATIONS[@]}"; do
    local num="${entry%%:*}"
    if ! grep -q "^${num}:" "$state_file" 2>/dev/null; then
      pending=$((pending + 1))
    fi
  done
  echo "$pending"
}
