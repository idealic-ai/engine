#!/bin/bash
# ============================================================================
# Setup Library — Pure functions for workflow engine setup
# ============================================================================
# Sourced by engine.sh. All functions are parameterized (no global reads).
# See ~/.claude/docs/SETUP_PROTOCOL.md for the full protocol.
#
# Testability: All path dependencies come via parameters or $SETUP_* env vars.
# Tests source this file directly and call functions in isolation.
#
# Related:
#   Docs: (~/.claude/docs/)
#     SETUP_PROTOCOL.md — Architecture and testing requirements
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_TEST_SANDBOX_ISOLATION — Testability requirement
# ============================================================================

# ---- Logging (caller sets VERBOSE before sourcing) ----

setup_log_verbose() {
  if [ "${VERBOSE:-false}" = true ]; then
    echo "[VERBOSE] $*"
  fi
}

setup_log_step() {
  if [ "${VERBOSE:-false}" = true ]; then
    echo ""
    echo "==== $* ===="
  fi
}

# ---- Mode resolution ----

# current_mode "$mode_file"
# Echoes "local" or "remote" based on the mode file content.
current_mode() {
  local mode_file="$1"
  if [ -f "$mode_file" ] && [ "$(cat "$mode_file")" = "local" ]; then
    echo "local"
  else
    echo "remote"
  fi
}

# resolve_engine_dir "$mode" "$local_engine" "$gdrive_engine" "$script_dir"
# Echoes the resolved engine directory path, or "" if not found.
resolve_engine_dir() {
  local mode="$1"
  local local_engine="$2"
  local gdrive_engine="$3"
  local script_dir="$4"

  if [ "$mode" = "local" ]; then
    echo "$local_engine"
  elif [ -d "$gdrive_engine/.directives" ] && [ -d "$gdrive_engine/skills" ]; then
    echo "$gdrive_engine"
  elif [ -d "$script_dir/../.directives" ] && [ -d "$script_dir/../skills" ]; then
    (cd "$script_dir/.." && pwd)
  elif [ -d "$script_dir/.directives" ] && [ -d "$script_dir/skills" ]; then
    echo "$script_dir"
  else
    echo ""
  fi
}

# ---- Symlinking (core) ----

# link_if_needed "$target" "$link_path" "$display_name" ["$interactive"]
# Creates or updates a symlink. Returns:
#   0 = success (created, updated, or already correct)
#   2 = real directory exists and interactive=0 (caller should handle)
# Appends to ACTIONS array (must be declared by caller).
link_if_needed() {
  local target="$1"
  local link="$2"
  local name="$3"
  local interactive="${4:-1}"

  if [ -L "$link" ]; then
    local current
    current=$(readlink "$link")
    if [ "$current" = "$target" ]; then
      setup_log_verbose "$name: OK (symlink exists)"
      return 0
    else
      setup_log_verbose "$name: updating symlink"
      rm "$link"
      ln -s "$target" "$link"
      ACTIONS+=("Updated $name -> $target")
      return 0
    fi
  elif [ -d "$link" ]; then
    if [ "$interactive" = "0" ]; then
      setup_log_verbose "$name: REAL DIRECTORY - non-interactive mode, skipping"
      return 0
    fi
    setup_log_verbose "$name: REAL DIRECTORY - waiting for input"
    echo ""
    echo "=============================================="
    echo "WARNING: $link is a real directory, not a symlink."
    echo "Back it up and remove it to proceed, or skip with Ctrl+C."
    echo "=============================================="
    echo ""
    read -rp "Remove $link and replace with symlink? [y/N] " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
      setup_log_verbose "$name: replacing with symlink"
      rm -rf "$link"
      ln -s "$target" "$link"
      ACTIONS+=("Replaced $name -> $target")
      return 0
    else
      setup_log_verbose "$name: skipped by user"
      return 0
    fi
  else
    setup_log_verbose "$name: creating symlink"
    ln -s "$target" "$link"
    ACTIONS+=("Linked $name -> $target")
    return 0
  fi
}

# link_files_if_needed "$src_dir" "$dest_dir" "$display_name"
# Creates per-file symlinks from src_dir/* to dest_dir/*.
# Migrates from whole-dir symlink if present. Preserves local overrides.
link_files_if_needed() {
  local src_dir="$1"
  local dest_dir="$2"
  local display_name="$3"

  if [ -L "$dest_dir" ]; then
    setup_log_verbose "$display_name: migrating from whole-dir symlink to per-file"
    rm "$dest_dir"
    ACTIONS+=("Removed whole-dir symlink $display_name (migrating to per-file)")
  fi

  mkdir -p "$dest_dir"

  local count=0
  for src_file in "$src_dir"/*; do
    [ -e "$src_file" ] || continue
    local name
    name=$(basename "$src_file")
    local dest_file="$dest_dir/$name"

    if [ -L "$dest_file" ]; then
      local current
      current=$(readlink "$dest_file")
      if [ "$current" = "$src_file" ]; then
        continue
      else
        rm "$dest_file"
        ln -s "$src_file" "$dest_file"
        count=$((count + 1))
      fi
    elif [ -e "$dest_file" ]; then
      # Regular file exists where symlink should be — backup and replace
      local backup_file="${dest_file}.local-backup"
      setup_log_verbose "$display_name/$name: regular file exists, backing up to $name.local-backup"
      mv "$dest_file" "$backup_file"
      ln -s "$src_file" "$dest_file"
      count=$((count + 1))
      ACTIONS+=("Backed up $display_name/$name → $name.local-backup, replaced with symlink")
    else
      ln -s "$src_file" "$dest_file"
      count=$((count + 1))
    fi
  done

  if [ "$count" -gt 0 ]; then
    setup_log_verbose "$display_name: linked $count files"
    ACTIONS+=("Linked $count files in $display_name")
  else
    setup_log_verbose "$display_name: OK"
  fi
}

# setup_engine_symlinks "$engine_dir" "$claude_dir"
# Orchestrates all engine symlinks: whole-dir, per-file, per-skill, tools, permissions.
setup_engine_symlinks() {
  local engine_dir="$1"
  local claude_dir="$2"

  mkdir -p "$claude_dir"

  # Whole-dir symlinks
  link_if_needed "$engine_dir/.directives" "$claude_dir/.directives" ".directives" "0"
  link_files_if_needed "$engine_dir/agents" "$claude_dir/agents" "agents"

  # Per-file symlinks (allows local overrides)
  link_files_if_needed "$engine_dir/scripts" "$claude_dir/scripts" "scripts"
  link_files_if_needed "$engine_dir/hooks"   "$claude_dir/hooks"   "hooks"

  # Per-skill symlinks
  if [ -L "$claude_dir/skills" ]; then
    setup_log_verbose "Migrating skills from whole-dir symlink to per-skill"
    rm "$claude_dir/skills"
    ACTIONS+=("Removed whole-dir skills symlink (migrating to per-skill)")
  fi
  mkdir -p "$claude_dir/skills"
  for skill_dir in "$engine_dir/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    local skill_name
    skill_name="$(basename "$skill_dir")"
    link_if_needed "$skill_dir" "$claude_dir/skills/$skill_name" "skills/$skill_name" "0"
  done

  # Clean up stale skill symlinks pointing to a different engine
  # Uses find -type l instead of glob */ to catch broken (dangling) symlinks too
  local stale_count=0
  while IFS= read -r skill_link; do
    local link_target
    link_target=$(readlink "$skill_link")
    if [[ "$link_target" == "$engine_dir/skills/"* ]]; then
      continue
    fi
    # Only remove symlinks that point into an engine skills dir
    if [[ "$link_target" != *"/engine/skills/"* ]]; then
      continue
    fi
    setup_log_verbose "Removing stale skill symlink: $(basename "$skill_link") -> $link_target"
    rm "$skill_link"
    stale_count=$((stale_count + 1))
  done < <(find "$claude_dir/skills" -maxdepth 1 -type l 2>/dev/null)
  if [ "$stale_count" -gt 0 ]; then
    ACTIONS+=("Removed $stale_count stale skill symlinks from previous engine")
  fi

  # Clean up broken (dangling) symlinks in skills/
  local broken_count=0
  while IFS= read -r skill_link; do
    [ -e "$skill_link" ] && continue  # target exists, not broken
    local link_target
    link_target=$(readlink "$skill_link")
    setup_log_verbose "Removing broken skill symlink: $(basename "$skill_link") -> $link_target"
    rm "$skill_link"
    broken_count=$((broken_count + 1))
  done < <(find "$claude_dir/skills" -maxdepth 1 -type l 2>/dev/null)
  if [ "$broken_count" -gt 0 ]; then
    ACTIONS+=("Removed $broken_count broken skill symlinks")
  fi

  # Tools
  if [ -d "$engine_dir/tools" ]; then
    link_if_needed "$engine_dir/tools" "$claude_dir/tools" "tools" "0"
    for tool_dir in "$engine_dir/tools"/*/; do
      [ -d "$tool_dir" ] || continue
      local tool_name
      tool_name="$(basename "$tool_dir")"
      if [ -f "$tool_dir/$tool_name.sh" ]; then
        link_if_needed "$tool_dir/$tool_name.sh" "$claude_dir/scripts/$tool_name.sh" "scripts/$tool_name.sh" "0"
      fi
    done
  fi

  # Fix permissions (GDrive sync often strips +x)
  fix_script_permissions "$engine_dir"
}

# fix_script_permissions "$engine_dir"
# Ensures all .sh files in the engine are executable.
fix_script_permissions() {
  local engine_dir="$1"
  local fixed_scripts=0

  while IFS= read -r -d '' script; do
    if [ ! -x "$script" ]; then
      chmod +x "$script"
      fixed_scripts=$((fixed_scripts + 1))
    fi
  done < <(find "$engine_dir" -name "*.sh" -type f -print0 2>/dev/null)

  if [ "$fixed_scripts" -gt 0 ]; then
    ACTIONS+=("Fixed +x permissions on $fixed_scripts scripts")
    setup_log_verbose "Scripts: fixed +x on $fixed_scripts files"
  else
    setup_log_verbose "Scripts: all executable"
  fi
}

# ---- Safe copy with realpath guard ----

# cp_if_different "$source" "$dest" "$label"
# Copies source to dest only if they resolve to different files (realpath check).
# Prevents cp-to-self when source and dest are symlinks to the same file (e.g., GDrive).
# Returns 0 on success or skip, 1 if source doesn't exist.
# Appends to ACTIONS array (must be declared by caller).
cp_if_different() {
  local source="$1"
  local dest="$2"
  local label="${3:-$(basename "$source")}"

  if [ ! -f "$source" ]; then
    setup_log_verbose "$label: source not found ($source)"
    return 1
  fi

  local src_real dest_real
  src_real=$(realpath "$source" 2>/dev/null) || src_real="$source"
  dest_real=$(realpath "$dest" 2>/dev/null) || dest_real=""

  if [ -n "$dest_real" ] && [ "$src_real" = "$dest_real" ]; then
    setup_log_verbose "$label: skipping (same file)"
    return 0
  fi

  cp "$source" "$dest"
  ACTIONS+=("Copied $label")
  return 0
}

# ---- Settings.json operations ----

# merge_permissions "$settings_file" "$permissions_json"
# Merges permission rules into settings.json using jq. Creates file if missing.
# Returns 0 on success, 1 if jq not available.
merge_permissions() {
  local settings_file="$1"
  local permissions_json="$2"

  if ! command -v jq &>/dev/null; then
    # Fallback: write raw permissions if file is empty/missing
    if [ ! -f "$settings_file" ] || [ ! -s "$settings_file" ] || [ "$(cat "$settings_file" 2>/dev/null)" = "{}" ]; then
      echo "$permissions_json" > "$settings_file"
      ACTIONS+=("Created $(basename "$settings_file") (basic, no jq)")
    fi
    return 1
  fi

  if [ -f "$settings_file" ] && [ -s "$settings_file" ]; then
    local existing merged
    existing=$(cat "$settings_file")
    merged=$(echo "$existing" | jq --argjson new "$permissions_json" '
      .permissions.allow = ((.permissions.allow // []) + $new.permissions.allow | unique)
    ')
    if [ "$existing" != "$merged" ]; then
      echo "$merged" > "$settings_file"
      ACTIONS+=("Updated $(basename "$settings_file") permissions")
    fi
  else
    echo "$permissions_json" > "$settings_file"
    ACTIONS+=("Created $(basename "$settings_file")")
  fi
  return 0
}

# configure_statusline "$settings_file"
# Adds the engine statusLine hook to settings.json.
configure_statusline() {
  local settings_file="$1"

  if ! command -v jq &>/dev/null; then return 1; fi
  if [ ! -f "$settings_file" ]; then return 1; fi

  local current_sl
  current_sl=$(jq -r '.statusLine.command // ""' "$settings_file" 2>/dev/null)
  if [[ "$current_sl" != *"statusline.sh"* ]]; then
    local merged
    merged=$(cat "$settings_file" | jq '.statusLine = {
      "type": "command",
      "command": "~/.claude/tools/statusline.sh"
    }')
    echo "$merged" > "$settings_file"
    if [ -z "$current_sl" ]; then
      ACTIONS+=("Added statusLine hook")
    else
      ACTIONS+=("Replaced default statusLine with engine statusLine")
    fi
  fi
  return 0
}

# configure_hooks "$settings_file"
# Deep-merges engine hooks into settings.json. Preserves user's custom hooks.
# Uses add_if_missing pattern: adds engine hook entries only if their command
# path isn't already present in the category. Safe to run multiple times.
configure_hooks() {
  local settings_file="$1"

  if ! command -v jq &>/dev/null; then return 1; fi
  if [ ! -f "$settings_file" ]; then return 1; fi

  local merged
  merged=$(cat "$settings_file" | jq '
    # Helper: add entry to array if command not already present
    def add_if_missing(entry):
      if any(.[]; .hooks[]? | .command == (entry | .hooks[0].command))
      then .
      else . + [entry]
      end;

    # PreToolUse: overflow + heartbeat + session-gate
    .hooks.PreToolUse = ((.hooks.PreToolUse // [])
      | add_if_missing({
          "matcher": "*",
          "hooks": [{
            "type": "command",
            "command": "~/.claude/hooks/pre-tool-use-overflow.sh",
            "timeout": 5,
            "statusMessage": "Checking context..."
          }]
        })
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

    # Stop
    | .hooks.Stop = ((.hooks.Stop // [])
      | add_if_missing({
          "hooks": [{"type": "command", "command": "~/.claude/hooks/stop-notify.sh"}]
        })
    )

    # Notification
    | .hooks.Notification = ((.hooks.Notification // [])
      | add_if_missing({
          "matcher": "permission_prompt",
          "hooks": [{"type": "command", "command": "~/.claude/hooks/notification-attention.sh"}]
        })
      | add_if_missing({
          "matcher": "idle_prompt",
          "hooks": [{"type": "command", "command": "~/.claude/hooks/notification-idle.sh"}]
        })
      | add_if_missing({
          "matcher": "elicitation_dialog",
          "hooks": [{"type": "command", "command": "~/.claude/hooks/notification-attention.sh"}]
        })
    )

    # UserPromptSubmit: working + session-gate
    | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // [])
      | add_if_missing({
          "hooks": [{"type": "command", "command": "~/.claude/hooks/user-prompt-working.sh"}]
        })
      | add_if_missing({
          "hooks": [{"type": "command", "command": "~/.claude/hooks/user-prompt-submit-session-gate.sh", "timeout": 5}]
        })
    )

    # SessionEnd
    | .hooks.SessionEnd = ((.hooks.SessionEnd // [])
      | add_if_missing({
          "hooks": [{"type": "command", "command": "~/.claude/hooks/session-end-notify.sh"}]
        })
    )

    # PostToolUse: complete-notify + discovery
    | (if .hooks.PostToolUseSuccess then
        .hooks.PostToolUse = ((.hooks.PostToolUse // []) + .hooks.PostToolUseSuccess | unique_by(.hooks[0].command))
        | del(.hooks.PostToolUseSuccess)
       else . end)
    | .hooks.PostToolUse = ((.hooks.PostToolUse // [])
      | add_if_missing({
          "hooks": [{"type": "command", "command": "~/.claude/hooks/post-tool-complete-notify.sh"}]
        })
    )

    # PostToolUseFailure
    | .hooks.PostToolUseFailure = ((.hooks.PostToolUseFailure // [])
      | add_if_missing({
          "hooks": [{"type": "command", "command": "~/.claude/hooks/post-tool-failure-notify.sh"}]
        })
    )
  ' 2>/dev/null) || return 1

  echo "$merged" > "$settings_file"
  ACTIONS+=("Configured engine hooks (deep-merge)")
  return 0
}

# ---- Project-level setup ----

# link_project_dir "$target" "$link_path" "$display_name"
# Symlinks project directories (sessions/, reports/). No interactive prompts
# for real dirs — just warns.
link_project_dir() {
  local target="$1"
  local link="$2"
  local name="$3"

  if [ -L "$link" ]; then
    local current
    current=$(readlink "$link")
    if [ "$current" = "$target" ]; then
      setup_log_verbose "$name: OK (symlink exists)"
      return 0
    else
      setup_log_verbose "$name: updating symlink"
      rm "$link"
      ln -s "$target" "$link"
      ACTIONS+=("Updated $name -> $target")
      return 0
    fi
  elif [ -d "$link" ]; then
    setup_log_verbose "$name: REAL DIRECTORY - manual action required"
    echo "WARNING: $name is a real directory with existing data."
    echo "Move its contents to $target first, then re-run."
    return 2
  else
    setup_log_verbose "$name: creating symlink"
    ln -s "$target" "$link"
    ACTIONS+=("Linked $name -> $target")
    return 0
  fi
}

# ensure_project_directives "$project_root"
# Creates .claude/.directives/INVARIANTS.md stub if missing.
ensure_project_directives() {
  local project_root="$1"
  local directives_dir="$project_root/.claude/.directives"
  local invariants_file="$directives_dir/INVARIANTS.md"

  mkdir -p "$directives_dir"

  if [ ! -f "$invariants_file" ]; then
    cat > "$invariants_file" << 'STDINV'
# Project Invariants

Project-specific rules that extend the shared engine standards. Every command loads this file automatically after the shared `~/.claude/.directives/INVARIANTS.md`.

Add your project's architectural rules, naming conventions, framework-specific constraints, and domain logic invariants here.
STDINV
    ACTIONS+=("Created .claude/.directives/INVARIANTS.md")
    return 0
  fi
  setup_log_verbose "INVARIANTS.md: OK"
  return 0
}

# update_gitignore "$project_root" entry1 entry2 ...
# Adds entries to .gitignore if not already present.
update_gitignore() {
  local project_root="$1"
  shift
  local entries=("$@")
  local gitignore="$project_root/.gitignore"

  if [ -f "$gitignore" ]; then
    for entry in "${entries[@]}"; do
      if ! grep -qx "$entry" "$gitignore" && ! grep -qx "${entry}/" "$gitignore"; then
        setup_log_verbose ".gitignore: adding '$entry'"
        echo "$entry" >> "$gitignore"
        ACTIONS+=("Added '$entry' to .gitignore")
      fi
    done
  else
    printf '%s\n' "${entries[@]}" > "$gitignore"
    ACTIONS+=("Created .gitignore")
  fi
}
