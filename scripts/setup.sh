#!/bin/bash
set -euo pipefail

# ============================================================================
# Workflow Engine Setup Script
# ============================================================================
# Sets up the shared workflow engine for a team member on a specific project.
#
# Usage (from your project root):
#   setup.sh [project-name]       Normal project setup (respects current mode)
#   setup.sh --report             Full system health report
#   setup.sh --verbose [project]  Verbose output
#
# Mode switching:
#   setup.sh local                Switch to local mode (+ Git onboarding if no .git)
#   setup.sh remote               Switch engine symlinks to GDrive
#   setup.sh status               Show current mode + symlink audit
#
# Git operations (requires .git in ~/.claude/engine/):
#   setup.sh push                 git push current branch to origin
#   setup.sh pull                 git pull current branch from origin
#   setup.sh deploy               Sync local engine → GDrive (rsync, excludes .git)
#
# Everything is inferred automatically:
#   - Email and username: from the script's own GDrive path or .user.json cache
#   - Project name: from the argument, or the current directory name
#
# Prerequisites:
#   - Google Drive desktop app installed and syncing
#   - Access to the finch-os Shared Drive
#
# Related:
#   Docs: (~/.claude/docs/)
#     SETUP_PROTOCOL.md — Complete setup protocol and modes
#     STANDARDS_SYSTEM.md — Standards symlink creation
#   Invariants: (~/.claude/standards/INVARIANTS.md)
#     ¶INV_TEST_SANDBOX_ISOLATION — Test safety requirements
#     ¶INV_INFER_USER_FROM_GDRIVE — Identity detection
#
# CONTRIBUTING:
#   Before modifying this script, read ~/.claude/docs/SETUP_PROTOCOL.md.
#   - New pure functions → setup-lib.sh (parameterized, no globals)
#   - New migrations → setup-migrations.sh (numbered, idempotent, tested)
#   - Test coverage required for all changes (test-setup-lib.sh / test-setup-migrations.sh)
#   - All paths use $SETUP_* env vars for testability (see protocol doc)
# ============================================================================

# ---- Parse flags ----
VERBOSE=false
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]:-}"

# ---- Utility functions ----

log_verbose() {
  if [ "$VERBOSE" = true ]; then
    echo "[VERBOSE] $*"
  fi
}

log_step() {
  if [ "$VERBOSE" = true ]; then
    echo ""
    echo "==== $* ===="
  fi
}

# ---- Resolve paths and identity ----

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
LOCAL_ENGINE="$HOME/.claude/engine"
MODE_FILE="$HOME/.claude/engine/.mode"
ACTIONS=()

# Source libraries (functions become available for all subcommands)
source "$SCRIPT_DIR/setup-lib.sh"
source "$SCRIPT_DIR/setup-migrations.sh"

# Extract email from GDrive mount path or cache
EMAIL=$(echo "$SCRIPT_DIR" | grep -o 'GoogleDrive-[^/]*' | sed 's/GoogleDrive-//' || true)
if [ -z "$EMAIL" ]; then
  USER_INFO_SCRIPT="$HOME/.claude/scripts/user-info.sh"
  if [ -x "$USER_INFO_SCRIPT" ]; then
    EMAIL=$("$USER_INFO_SCRIPT" email 2>/dev/null || true)
  fi
fi
if [ -z "$EMAIL" ]; then
  echo "ERROR: Could not infer email from script path or user-info.sh."
  echo "Expected script to live under ~/Library/CloudStorage/GoogleDrive-<email>/..."
  echo "Or run 'setup.sh pull' first to cache identity."
  exit 1
fi

USER_NAME="${EMAIL%%@*}"

# Engine path constants
GDRIVE_ENGINE="$HOME/Library/CloudStorage/GoogleDrive-$EMAIL/Shared drives/finch-os/engine"
GDRIVE_ROOT="$HOME/Library/CloudStorage/GoogleDrive-$EMAIL/Shared drives/finch-os"

log_verbose "User: $USER_NAME ($EMAIL)"

# ---- Mode helpers: now in setup-lib.sh (current_mode, resolve_engine_dir) ----

# ---- Symlink functions: now in setup-lib.sh ----

# ---- Engine symlink setup: now in setup-lib.sh (setup_engine_symlinks) ----

# ============================================================================
# Subcommand handlers
# ============================================================================

cmd_local() {
  if [ ! -d "$LOCAL_ENGINE" ]; then
    echo "ERROR: Local engine not found at $LOCAL_ENGINE"
    echo "Run 'setup.sh pull' first to copy engine from GDrive."
    exit 1
  fi

  # Git onboarding: if no .git in LOCAL_ENGINE, offer to set up Git
  if [ ! -d "$LOCAL_ENGINE/.git" ]; then
    echo "No Git repository found in $LOCAL_ENGINE."
    echo ""

    # Check if gitRepoUrl is already in .user.json
    local repo_url=""
    local user_json="$LOCAL_ENGINE/.user.json"
    if [ -f "$user_json" ] && command -v jq &>/dev/null; then
      repo_url=$(jq -r '.gitRepoUrl // empty' "$user_json" 2>/dev/null || true)
    fi

    if [ -z "$repo_url" ]; then
      echo "Enter the Git repository URL for the engine:"
      echo "  (e.g., git@github.com:finch-os/engine.git)"
      printf "  URL: "
      read -r repo_url
      if [ -z "$repo_url" ]; then
        echo "ERROR: No URL provided. Skipping Git setup."
        echo "You can re-run 'setup.sh local' to try again."
      fi
    fi

    if [ -n "$repo_url" ]; then
      echo ""
      echo "Initializing Git repository..."

      # Clone into a temp dir, then move .git into LOCAL_ENGINE
      local tmp_clone
      tmp_clone=$(mktemp -d)
      if git clone "$repo_url" "$tmp_clone/engine" 2>&1; then
        # Move .git into the existing LOCAL_ENGINE
        mv "$tmp_clone/engine/.git" "$LOCAL_ENGINE/.git"
        rm -rf "$tmp_clone"

        # Create personal branch
        local branch="${USER_NAME}/engine"
        if ! git -C "$LOCAL_ENGINE" rev-parse --verify "$branch" &>/dev/null; then
          git -C "$LOCAL_ENGINE" checkout -b "$branch" 2>&1
          ACTIONS+=("Created branch $branch")
        else
          git -C "$LOCAL_ENGINE" checkout "$branch" 2>&1
        fi

        # Save gitRepoUrl to .user.json
        if [ -f "$user_json" ] && command -v jq &>/dev/null; then
          local updated
          updated=$(jq --arg url "$repo_url" --arg branch "$branch" \
            '.gitRepoUrl = $url | .gitBranch = $branch' "$user_json")
          echo "$updated" > "$user_json"
        else
          cat > "$user_json" << USERJSON
{
  "username": "$USER_NAME",
  "email": "$EMAIL",
  "gitRepoUrl": "$repo_url",
  "gitBranch": "$branch"
}
USERJSON
        fi

        ACTIONS+=("Cloned $repo_url into $LOCAL_ENGINE")
        ACTIONS+=("Saved gitRepoUrl to .user.json")
        echo "Git initialized. Branch: $branch"
      else
        rm -rf "$tmp_clone"
        echo "ERROR: git clone failed. Check the URL and your SSH keys."
        echo "  URL: $repo_url"
      fi
    fi
  fi

  echo "local" > "$MODE_FILE"
  echo "Switching to local mode..."
  log_verbose "Engine: $LOCAL_ENGINE"
  setup_engine_symlinks "$LOCAL_ENGINE" "$CLAUDE_DIR"
  echo ""
  echo "Done. Mode: local"
  echo "  Engine: $LOCAL_ENGINE"
  if [ ${#ACTIONS[@]} -gt 0 ]; then
    for action in "${ACTIONS[@]}"; do echo "  - $action"; done
  fi
}

cmd_remote() {
  local engine_dir
  engine_dir=$(resolve_engine_dir "remote" "$LOCAL_ENGINE" "$GDRIVE_ENGINE" "$SCRIPT_DIR")
  if [ -z "$engine_dir" ] || [ ! -d "$engine_dir/skills" ]; then
    echo "ERROR: GDrive engine not found."
    echo "Expected at: $GDRIVE_ENGINE"
    echo "Is Google Drive running and syncing?"
    exit 1
  fi
  echo "remote" > "$MODE_FILE"
  echo "Switching to remote mode..."
  log_verbose "Engine: $engine_dir"
  setup_engine_symlinks "$engine_dir" "$CLAUDE_DIR"
  echo ""
  echo "Done. Mode: remote"
  echo "  Engine: $engine_dir"
  if [ ${#ACTIONS[@]} -gt 0 ]; then
    for action in "${ACTIONS[@]}"; do echo "  - $action"; done
  fi
}

cmd_pull() {
  if [ ! -d "$LOCAL_ENGINE" ]; then
    echo "ERROR: Local engine not found at $LOCAL_ENGINE"
    echo "Run 'setup.sh local' first to initialize Git."
    exit 1
  fi
  if [ ! -d "$LOCAL_ENGINE/.git" ]; then
    echo "ERROR: No Git repository found in $LOCAL_ENGINE"
    echo "Run 'setup.sh local' first to initialize Git."
    exit 1
  fi
  if ! command -v git &>/dev/null; then
    echo "ERROR: Git is required. Install with: brew install git"
    exit 1
  fi

  # Determine branch
  local branch
  branch=$(git -C "$LOCAL_ENGINE" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -z "$branch" ]; then
    echo "ERROR: Could not determine current Git branch."
    exit 1
  fi

  echo "Pulling $branch from origin..."
  local pull_output
  pull_output=$(git -C "$LOCAL_ENGINE" pull origin "$branch" 2>&1) || {
    local exit_code=$?
    echo ""
    # Check for merge conflict
    if git -C "$LOCAL_ENGINE" diff --name-only --diff-filter=U 2>/dev/null | grep -q .; then
      echo "MERGE CONFLICT detected."
      echo ""
      echo "Conflicted files:"
      git -C "$LOCAL_ENGINE" diff --name-only --diff-filter=U 2>/dev/null | while read -r f; do echo "  - $f"; done
      echo ""
      echo "To resolve:"
      echo "  1. cd $LOCAL_ENGINE"
      echo "  2. Edit conflicted files (look for <<<<<<< markers)"
      echo "  3. git add <resolved-files>"
      echo "  4. git commit"
      echo ""
      echo "To abort the merge:"
      echo "  git -C $LOCAL_ENGINE merge --abort"
    else
      echo "ERROR: git pull failed (exit code $exit_code)."
      echo "$pull_output"
      echo ""
      echo "Check your Git remote and authentication."
      echo "  Remote: $(git -C "$LOCAL_ENGINE" remote get-url origin 2>/dev/null || echo 'not set')"
    fi
    exit 1
  }

  ACTIONS+=("Pulled $branch from origin")
  echo "$pull_output"
  echo ""
  echo "Done. Local engine updated from origin/$branch."

  # Fix permissions on pulled scripts
  find "$LOCAL_ENGINE" -name "*.sh" -type f ! -perm -u+x -exec chmod +x {} + 2>/dev/null || true
}

cmd_push() {
  if [ ! -d "$LOCAL_ENGINE" ]; then
    echo "ERROR: Local engine not found at $LOCAL_ENGINE"
    echo "Nothing to push."
    exit 1
  fi
  if [ ! -d "$LOCAL_ENGINE/.git" ]; then
    echo "ERROR: No Git repository found in $LOCAL_ENGINE"
    echo "Run 'setup.sh local' first to initialize Git."
    exit 1
  fi
  if ! command -v git &>/dev/null; then
    echo "ERROR: Git is required. Install with: brew install git"
    exit 1
  fi

  # Determine branch
  local branch
  branch=$(git -C "$LOCAL_ENGINE" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -z "$branch" ]; then
    echo "ERROR: Could not determine current Git branch."
    exit 1
  fi

  echo "Pushing $branch to origin..."
  if git -C "$LOCAL_ENGINE" push origin "$branch" 2>&1; then
    ACTIONS+=("Pushed $branch to origin")
    echo ""
    echo "Done. Branch '$branch' pushed to origin."
  else
    echo ""
    echo "ERROR: git push failed."
    echo "Check your Git remote and authentication."
    echo "  Remote: $(git -C "$LOCAL_ENGINE" remote get-url origin 2>/dev/null || echo 'not set')"
    exit 1
  fi
}

cmd_deploy() {
  if [ ! -d "$LOCAL_ENGINE" ]; then
    echo "ERROR: Local engine not found at $LOCAL_ENGINE"
    echo "Nothing to deploy."
    exit 1
  fi
  if [ ! -d "$(dirname "$GDRIVE_ENGINE")" ]; then
    echo "ERROR: GDrive path not accessible."
    echo "Expected at: $(dirname "$GDRIVE_ENGINE")"
    echo "Is Google Drive running and syncing?"
    exit 1
  fi
  echo "Deploying local engine → GDrive..."
  echo "  WARNING: This will overwrite GDrive engine. Non-dev changes on GDrive will be lost."
  # Backup GDrive if exists
  if [ -d "$GDRIVE_ENGINE" ]; then
    echo "  Backing up GDrive → ${GDRIVE_ENGINE}.bak"
    rm -rf "${GDRIVE_ENGINE}.bak"
    cp -a "$GDRIVE_ENGINE" "${GDRIVE_ENGINE}.bak"
    ACTIONS+=("Backed up $GDRIVE_ENGINE → ${GDRIVE_ENGINE}.bak")
  fi
  # Sync (exclude .git, local-only files, and node_modules)
  rsync -a --delete \
    --exclude='.git' \
    --exclude='.mode' \
    --exclude='.user.json' \
    --exclude='.bak' \
    --exclude='node_modules' \
    "$LOCAL_ENGINE/" "$GDRIVE_ENGINE/"
  ACTIONS+=("Deployed $LOCAL_ENGINE → $GDRIVE_ENGINE (no .git)")
  echo ""
  echo "Done. GDrive engine updated from local (no .git deployed)."
  echo "  Engine: $GDRIVE_ENGINE"
  echo "  Backup: ${GDRIVE_ENGINE}.bak"
  if [ ${#ACTIONS[@]} -gt 0 ]; then
    for action in "${ACTIONS[@]}"; do echo "  - $action"; done
  fi
}

cmd_status() {
  local mode
  mode=$(current_mode "$MODE_FILE")
  local engine_dir
  engine_dir=$(resolve_engine_dir "$mode" "$LOCAL_ENGINE" "$GDRIVE_ENGINE" "$SCRIPT_DIR")

  echo "Engine Mode Status"
  echo "=================="
  echo ""
  echo "Mode:          $mode"
  echo "Local engine:  $LOCAL_ENGINE $([ -d "$LOCAL_ENGINE" ] && echo '✓' || echo '✗ (not found)')"
  echo "GDrive engine: $GDRIVE_ENGINE $([ -d "$GDRIVE_ENGINE" ] && echo '✓' || echo '✗ (not accessible)')"
  echo "Active engine: ${engine_dir:-(ERROR: could not resolve)}"
  echo ""

  # Symlink audit
  local local_count=0 gdrive_count=0 broken_count=0 other_count=0
  for link in "$CLAUDE_DIR"/{commands,standards,agents,tools} "$CLAUDE_DIR/scripts"/* "$CLAUDE_DIR/hooks"/* "$CLAUDE_DIR/skills"/*; do
    [ -L "$link" ] || continue
    local target
    target=$(readlink "$link")
    if [ ! -e "$link" ]; then
      broken_count=$((broken_count + 1))
    elif [[ "$target" == *"GoogleDrive"* ]] || [[ "$target" == *"CloudStorage"* ]]; then
      gdrive_count=$((gdrive_count + 1))
    elif [[ "$target" == "$LOCAL_ENGINE"* ]] || [[ "$target" == *"/.claude/engine/"* ]]; then
      local_count=$((local_count + 1))
    else
      other_count=$((other_count + 1))
    fi
  done

  echo "Symlinks:"
  echo "  Local:  $local_count"
  echo "  GDrive: $gdrive_count"
  echo "  Broken: $broken_count"
  [ "$other_count" -gt 0 ] && echo "  Other:  $other_count"
  echo ""

  # Consistency check
  if [ "$mode" = "local" ] && [ "$gdrive_count" -gt 0 ]; then
    echo "⚠️  Mode is 'local' but $gdrive_count symlinks still point to GDrive."
    echo "   Run 'setup.sh local' to fix."
  elif [ "$mode" = "remote" ] && [ "$local_count" -gt 0 ]; then
    echo "⚠️  Mode is 'remote' but $local_count symlinks still point to local engine."
    echo "   Run 'setup.sh remote' to fix."
  elif [ "$broken_count" -gt 0 ]; then
    echo "⚠️  $broken_count broken symlinks detected."
    echo "   Run 'setup.sh $mode' to fix."
  else
    echo "✓ All symlinks consistent with mode."
  fi

  # Backup info
  echo ""
  echo "Backups:"
  [ -d "${LOCAL_ENGINE}.bak" ] && echo "  Local:  ${LOCAL_ENGINE}.bak ✓" || echo "  Local:  (none)"
  [ -d "${GDRIVE_ENGINE}.bak" ] && echo "  GDrive: ${GDRIVE_ENGINE}.bak ✓" || echo "  GDrive: (none)"
}

# ============================================================================
# Subcommand dispatch — check before normal project setup flow
# ============================================================================

case "${1:-}" in
  local)  cmd_local;  exit 0 ;;
  remote) cmd_remote; exit 0 ;;
  pull)   cmd_pull;   exit 0 ;;
  push)   cmd_push;   exit 0 ;;
  deploy) cmd_deploy; exit 0 ;;
  status) cmd_status; exit 0 ;;
esac

# ============================================================================
# Normal project setup flow (no subcommand given)
# ============================================================================

# ---- Resolve ENGINE_DIR based on current mode ----
ENGINE_DIR=$(resolve_engine_dir "$(current_mode "$MODE_FILE")" "$LOCAL_ENGINE" "$GDRIVE_ENGINE" "$SCRIPT_DIR")

if [ -z "$ENGINE_DIR" ] || [ ! -d "$ENGINE_DIR/skills" ]; then
  echo "ERROR: Engine not found."
  echo "Expected commands/ and skills/ in engine directory."
  exit 1
fi

# GDRIVE_ROOT must point to GDrive regardless of mode (for sessions/reports)
if [ "$(current_mode "$MODE_FILE")" = "local" ]; then
  GDRIVE_ROOT_RESOLVED="$GDRIVE_ROOT"
else
  GDRIVE_ROOT_RESOLVED="$(dirname "$ENGINE_DIR")"
fi

PROJECT_NAME="${1:-$(basename "$(pwd)")}"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

log_verbose "Engine: $ENGINE_DIR"
log_verbose "Project: $PROJECT_ROOT"

# ---- Prevent running from home directory ----
if [ "$PROJECT_ROOT" = "$HOME" ] || [ "$PROJECT_ROOT" = "/" ]; then
  echo "ERROR: Cannot run setup.sh from home directory or root."
  echo "Please cd to your project directory first."
  echo ""
  echo "Example:"
  echo "  cd ~/Projects/myproject"
  echo "  ~/.claude/scripts/setup.sh"
  exit 1
fi

# ---- Report mode ----
if [ "${1:-}" = "--report" ]; then
  echo "Workflow Engine Status"
  echo "======================"
  echo ""
  echo "Mode: $(current_mode "$MODE_FILE")"
  echo "User: $USER_NAME ($EMAIL)"
  echo "Engine: $ENGINE_DIR"
  echo ""

  # Check symlinks
  echo "Engine Symlinks (~/.claude/):"
  for name in commands standards scripts agents tools; do
    link="$CLAUDE_DIR/$name"
    if [ -L "$link" ]; then
      target=$(readlink "$link")
      if [[ "$target" == *"$ENGINE_DIR"* ]] || [[ "$target" == *"engine"* ]]; then
        echo "  $name: OK"
      else
        echo "  $name: linked to $target (unexpected)"
      fi
    elif [ -d "$link" ]; then
      echo "  $name: local directory (not linked)"
    else
      echo "  $name: MISSING"
    fi
  done

  # Check skills (per-skill symlinks)
  echo ""
  echo "Skills (~/.claude/skills/):"
  if [ -L "$CLAUDE_DIR/skills" ]; then
    echo "  WARNING: whole-dir symlink (should be per-skill)"
  elif [ -d "$CLAUDE_DIR/skills" ]; then
    engine_skills=$(find "$ENGINE_DIR/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    installed_skills=$(find "$CLAUDE_DIR/skills" -mindepth 1 -maxdepth 1 -type l 2>/dev/null | wc -l | tr -d ' ')
    echo "  $installed_skills/$engine_skills skills linked"
    for skill_dir in "$ENGINE_DIR/skills"/*/; do
      skill_name="$(basename "$skill_dir")"
      if [ ! -L "$CLAUDE_DIR/skills/$skill_name" ]; then
        echo "    MISSING: $skill_name"
      fi
    done
  else
    echo "  MISSING: ~/.claude/skills/ directory"
  fi

  # Check tools
  echo ""
  echo "Tools (~/.claude/tools/):"
  if [ -d "$CLAUDE_DIR/tools" ]; then
    for tool_dir in "$ENGINE_DIR/tools"/*/; do
      tool_name="$(basename "$tool_dir")"
      if [ -f "$tool_dir/package.json" ]; then
        if [ -d "$tool_dir/node_modules" ]; then
          echo "  $tool_name: OK"
        else
          echo "  $tool_name: MISSING node_modules (run setup.sh)"
        fi
      fi
    done
  else
    echo "  MISSING: ~/.claude/tools/ directory"
  fi

  # Check hooks in settings.json
  echo ""
  echo "Hooks (~/.claude/settings.json):"
  if [ -f "$CLAUDE_DIR/settings.json" ] && command -v jq &>/dev/null; then
    if jq -e '.statusLine' "$CLAUDE_DIR/settings.json" &>/dev/null; then
      sl_cmd=$(jq -r '.statusLine.command // "none"' "$CLAUDE_DIR/settings.json")
      if [[ "$sl_cmd" == *"statusline.sh"* ]]; then
        echo "  statusLine: OK (engine)"
      elif [[ "$sl_cmd" == *"input=\$(cat)"* ]] || [[ ${#sl_cmd} -gt 100 ]]; then
        echo "  statusLine: DEFAULT (not engine) - run setup.sh to fix"
      else
        echo "  statusLine: $sl_cmd"
      fi
    else
      echo "  statusLine: NOT CONFIGURED"
    fi
    ptu_count=$(jq '.hooks.PreToolUse // [] | length' "$CLAUDE_DIR/settings.json" 2>/dev/null || echo "0")
    echo "  PreToolUse hooks: $ptu_count"
    perm_count=$(jq '.permissions.allow // [] | length' "$CLAUDE_DIR/settings.json" 2>/dev/null || echo "0")
    echo "  Permissions: $perm_count rules"
  elif [ -f "$CLAUDE_DIR/settings.json" ]; then
    echo "  (install jq for detailed hook info)"
  else
    echo "  MISSING: ~/.claude/settings.json"
  fi

  # Check project setup
  echo ""
  echo "Project ($PROJECT_ROOT):"
  if [ -L "$PROJECT_ROOT/sessions" ]; then
    echo "  sessions/: $(readlink "$PROJECT_ROOT/sessions")"
  elif [ -d "$PROJECT_ROOT/sessions" ]; then
    echo "  sessions/: local directory (not linked to GDrive)"
  else
    echo "  sessions/: MISSING"
  fi
  if [ -L "$PROJECT_ROOT/reports" ]; then
    echo "  reports/: $(readlink "$PROJECT_ROOT/reports")"
  elif [ -d "$PROJECT_ROOT/reports" ]; then
    echo "  reports/: local directory (not linked to GDrive)"
  else
    echo "  reports/: MISSING"
  fi
  if [ -f "$PROJECT_ROOT/.claude/settings.json" ]; then
    echo "  .claude/settings.json: present"
  else
    echo "  .claude/settings.json: MISSING"
  fi

  # Script permissions
  echo ""
  echo "Script Permissions:"
  non_exec_count=0
  non_exec_files=()
  while IFS= read -r -d '' script; do
    if [ ! -x "$script" ]; then
      non_exec_count=$((non_exec_count + 1))
      non_exec_files+=("$(basename "$script")")
    fi
  done < <(find "$ENGINE_DIR" -name "*.sh" -type f -print0 2>/dev/null)

  total_scripts=$(find "$ENGINE_DIR" -name "*.sh" -type f 2>/dev/null | wc -l | tr -d ' ')
  exec_count=$((total_scripts - non_exec_count))

  if [ "$non_exec_count" -eq 0 ]; then
    echo "  All $total_scripts scripts executable: OK"
  else
    echo "  $exec_count/$total_scripts scripts executable"
    echo "  MISSING +x ($non_exec_count):"
    for f in "${non_exec_files[@]:0:10}"; do
      echo "    - $f"
    done
    if [ "$non_exec_count" -gt 10 ]; then
      echo "    ... and $((non_exec_count - 10)) more (run setup.sh to fix)"
    fi
  fi

  # Dependencies
  echo ""
  echo "Dependencies:"
  for cmd in jq sqlite3 fswatch; do
    if command -v $cmd &>/dev/null; then
      echo "  $cmd: $(which $cmd)"
    else
      echo "  $cmd: NOT INSTALLED"
    fi
  done

  exit 0
fi

# ---- Begin normal setup ----
echo "Setting up workflow engine for $USER_NAME/$PROJECT_NAME"

MISSING_DEPS=()

# ---- Install dependencies via brew ----
log_step "Checking dependencies"
if command -v brew &> /dev/null; then
  if ! command -v jq &> /dev/null; then
    log_verbose "jq: installing via brew..."
    if [ "$VERBOSE" = true ]; then
      brew install jq && ACTIONS+=("Installed jq via brew")
    else
      brew install jq >/dev/null 2>&1 && ACTIONS+=("Installed jq via brew")
    fi
  else
    log_verbose "jq: OK"
  fi
  if ! command -v sqlite3 &> /dev/null; then
    log_verbose "sqlite: installing via brew..."
    if [ "$VERBOSE" = true ]; then
      brew install sqlite && ACTIONS+=("Installed sqlite via brew")
    else
      brew install sqlite >/dev/null 2>&1 && ACTIONS+=("Installed sqlite via brew")
    fi
  else
    log_verbose "sqlite3: OK"
  fi
  if ! command -v fswatch &> /dev/null; then
    log_verbose "fswatch: installing via brew..."
    if [ "$VERBOSE" = true ]; then
      brew install fswatch && ACTIONS+=("Installed fswatch via brew")
    else
      brew install fswatch >/dev/null 2>&1 && ACTIONS+=("Installed fswatch via brew")
    fi
  else
    log_verbose "fswatch: OK"
  fi
else
  if ! command -v jq &> /dev/null; then
    MISSING_DEPS+=("jq")
  fi
  if ! command -v sqlite3 &> /dev/null; then
    MISSING_DEPS+=("sqlite3")
  fi
  if ! command -v fswatch &> /dev/null; then
    MISSING_DEPS+=("fswatch")
  fi
fi

# ---- Step 1: Create GDrive directories ----
log_step "Step 1: Create GDrive directories"
SESSION_DIR="$GDRIVE_ROOT_RESOLVED/$USER_NAME/$PROJECT_NAME/sessions"
REPORTS_DIR="$GDRIVE_ROOT_RESOLVED/$USER_NAME/$PROJECT_NAME/reports"
if [ ! -d "$SESSION_DIR" ]; then
  log_verbose "sessions/: creating $SESSION_DIR"
  mkdir -p "$SESSION_DIR"
  ACTIONS+=("Created $SESSION_DIR")
else
  log_verbose "sessions/: OK"
fi
if [ ! -d "$REPORTS_DIR" ]; then
  log_verbose "reports/: creating $REPORTS_DIR"
  mkdir -p "$REPORTS_DIR"
  ACTIONS+=("Created $REPORTS_DIR")
else
  log_verbose "reports/: OK"
fi

# ---- Step 2: Engine symlinks ----
log_step "Step 2: User-level shared engine setup"
setup_engine_symlinks "$ENGINE_DIR" "$CLAUDE_DIR"

# Install npm deps for tools
if [ -d "$ENGINE_DIR/tools" ]; then
  for tool_dir in "$ENGINE_DIR/tools"/*/; do
    tool_name="$(basename "$tool_dir")"
    if [ -f "$tool_dir/package.json" ] && [ ! -d "$tool_dir/node_modules" ]; then
      log_verbose "$tool_name: npm install (this may take a while)..."
      if [ "$VERBOSE" = true ]; then
        (cd "$tool_dir" && npm install) && ACTIONS+=("Installed $tool_name npm deps")
      else
        (cd "$tool_dir" && npm install --silent 2>/dev/null) && ACTIONS+=("Installed $tool_name npm deps")
      fi
    fi
  done
fi

# ---- Step 2b: Run migrations ----
log_step "Step 2b: Run migrations"
run_migrations "$CLAUDE_DIR" "${SESSION_DIR:-}" "$ENGINE_DIR"

# ---- Step 3: Project-level symlinks (sessions + reports) ----
log_step "Step 3: Project symlinks"
link_project_dir "$SESSION_DIR" "$PROJECT_ROOT/sessions" "./sessions"
link_project_dir "$REPORTS_DIR" "$PROJECT_ROOT/reports" "./reports"

# ---- Step 4: Create project standards stub ----
log_step "Step 4: Project standards"
PROJECT_CLAUDE_DIR="$PROJECT_ROOT/.claude/standards"
PROJECT_INVARIANTS="$PROJECT_CLAUDE_DIR/INVARIANTS.md"
mkdir -p "$PROJECT_CLAUDE_DIR"

if [ ! -f "$PROJECT_INVARIANTS" ]; then
  log_verbose "INVARIANTS.md: creating"
  cat > "$PROJECT_INVARIANTS" << 'STDINV'
# Project Invariants

Project-specific rules that extend the shared engine standards. Every command loads this file automatically after the shared `~/.claude/standards/INVARIANTS.md`.

Add your project's architectural rules, naming conventions, framework-specific constraints, and domain logic invariants here.
STDINV
  ACTIONS+=("Created .claude/standards/INVARIANTS.md")
else
  log_verbose "INVARIANTS.md: OK"
fi

# ---- Step 5: Update .gitignore ----
log_step "Step 5: Update .gitignore"
GITIGNORE="$PROJECT_ROOT/.gitignore"
if [ -f "$GITIGNORE" ]; then
  for entry in "sessions" "reports"; do
    if ! grep -qx "$entry" "$GITIGNORE" && ! grep -qx "$entry/" "$GITIGNORE"; then
      log_verbose ".gitignore: adding '$entry'"
      echo "$entry" >> "$GITIGNORE"
      ACTIONS+=("Added '$entry' to .gitignore")
    fi
  done
  log_verbose ".gitignore: OK"
else
  log_verbose ".gitignore: creating"
  printf 'sessions\nreports\n' > "$GITIGNORE"
  ACTIONS+=("Created .gitignore")
fi

# ---- Step 6: Drop README files into sessions and reports ----
log_step "Step 6: Create README files"
if [ ! -f "$SESSION_DIR/README.md" ]; then
  log_verbose "sessions/README.md: creating"
  cat > "$SESSION_DIR/README.md" << 'SESSREADME'
# Sessions

Each subdirectory is one work session, named `YYYY_MM_DD_TOPIC/`. Sessions are created automatically by workflow commands (`/brainstorm`, `/implement`, `/debug`, etc.).

A typical session contains:
- **LOG.md** — Stream-of-consciousness record of decisions, blocks, and progress
- **PLAN.md** — Step-by-step execution plan (for implementation/testing sessions)
- **Debrief** (e.g. `IMPLEMENTATION.md`, `BRAINSTORM.md`) — Final summary with outcomes, deviations, and next steps
- **DETAILS.md** — Verbatim Q&A capture from interrogation phases

Sessions are stored on Google Drive and symlinked into each project. Browse anyone's sessions from the Shared Drive.
SESSREADME
  ACTIONS+=("Created sessions/README.md")
else
  log_verbose "sessions/README.md: OK"
fi

if [ ! -f "$REPORTS_DIR/README.md" ]; then
  log_verbose "reports/README.md: creating"
  cat > "$REPORTS_DIR/README.md" << 'REPREADME'
# Reports

Progress reports generated by `/summarize-progress`. Each report summarizes recent session activity — what shipped, what's in progress, and what's blocked.

Reports are stored on Google Drive and symlinked into each project.
REPREADME
  ACTIONS+=("Created reports/README.md")
else
  log_verbose "reports/README.md: OK"
fi

# ---- Step 7: Configure Claude Code permissions ----
log_step "Step 7: Configure permissions"
GLOBAL_SETTINGS="$CLAUDE_DIR/settings.json"

read -r -d '' GLOBAL_PERMISSIONS << 'PERMS' || true
{
  "permissions": {
    "allow": [
      "Read(~/.claude/agents/**)",
      "Read(~/.claude/commands/**)",
      "Read(~/.claude/skills/**)",
      "Read(~/.claude/standards/**)",
      "Glob(~/.claude/**)",
      "Grep(~/.claude/**)",
      "Bash(~/.claude/scripts/*)",
      "Bash(~/.claude/tools/session-search/session-search.sh *)",
      "Bash(~/.claude/tools/doc-search/doc-search.sh *)"
    ]
  }
}
PERMS

MISSING_DEPS=()

if command -v jq &> /dev/null; then
  log_verbose "~/.claude/settings.json: configuring with jq"
  if [ -f "$GLOBAL_SETTINGS" ] && [ -s "$GLOBAL_SETTINGS" ]; then
    log_verbose "  merging permissions..."
    EXISTING=$(cat "$GLOBAL_SETTINGS")
    MERGED=$(echo "$EXISTING" | jq --argjson new "$GLOBAL_PERMISSIONS" '
      .permissions.allow = ((.permissions.allow // []) + $new.permissions.allow | unique)
    ')
    if [ "$EXISTING" != "$MERGED" ]; then
      echo "$MERGED" > "$GLOBAL_SETTINGS"
      ACTIONS+=("Updated ~/.claude/settings.json permissions")
    fi
  else
    log_verbose "  creating new settings.json..."
    echo "$GLOBAL_PERMISSIONS" > "$GLOBAL_SETTINGS"
    ACTIONS+=("Created ~/.claude/settings.json")
  fi

  # StatusLine hook
  log_verbose "  checking statusLine hook..."
  CURRENT_STATUSLINE=$(jq -r '.statusLine.command // ""' "$GLOBAL_SETTINGS" 2>/dev/null)
  if [[ "$CURRENT_STATUSLINE" != *"statusline.sh"* ]]; then
    log_verbose "  configuring statusLine hook..."
    MERGED=$(cat "$GLOBAL_SETTINGS" | jq '.statusLine = {
      "type": "command",
      "command": "~/.claude/tools/statusline.sh"
    }')
    echo "$MERGED" > "$GLOBAL_SETTINGS"
    if [ -z "$CURRENT_STATUSLINE" ]; then
      ACTIONS+=("Added statusLine hook")
    else
      ACTIONS+=("Replaced default statusLine with engine statusLine")
    fi
  else
    log_verbose "  statusLine: OK"
  fi

  # Fleet notification hooks
  log_verbose "  checking notification hooks..."
  CURRENT_HOOKS=$(jq '.hooks // {}' "$GLOBAL_SETTINGS" 2>/dev/null)
  if ! echo "$CURRENT_HOOKS" | jq -e '.Notification' &>/dev/null; then
    log_verbose "  adding notification hooks..."
    MERGED=$(cat "$GLOBAL_SETTINGS" | jq '.hooks.PreToolUse = [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/pre-tool-use-overflow.sh",
            "timeout": 5,
            "statusMessage": "Checking context..."
          }
        ]
      }
    ] | .hooks.Stop = [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/stop-notify.sh"
          }
        ]
      }
    ] | .hooks.Notification = [
      {
        "matcher": "permission_prompt",
        "hooks": [{"type": "command", "command": "~/.claude/hooks/notification-attention.sh"}]
      },
      {
        "matcher": "idle_prompt",
        "hooks": [{"type": "command", "command": "~/.claude/hooks/notification-idle.sh"}]
      },
      {
        "matcher": "elicitation_dialog",
        "hooks": [{"type": "command", "command": "~/.claude/hooks/notification-attention.sh"}]
      }
    ] | .hooks.UserPromptSubmit = [
      {
        "hooks": [{"type": "command", "command": "~/.claude/hooks/user-prompt-working.sh"}]
      }
    ] | .hooks.SessionEnd = [
      {
        "hooks": [{"type": "command", "command": "~/.claude/hooks/session-end-notify.sh"}]
      }
    ] | .hooks.PostToolUseSuccess = [
      {
        "hooks": [{"type": "command", "command": "~/.claude/hooks/post-tool-complete-notify.sh"}]
      }
    ] | .hooks.PostToolUseFailure = [
      {
        "hooks": [{"type": "command", "command": "~/.claude/hooks/post-tool-failure-notify.sh"}]
      }
    ]')
    echo "$MERGED" > "$GLOBAL_SETTINGS"
    ACTIONS+=("Added fleet notification hooks")
  else
    log_verbose "  notification hooks: OK"
  fi
else
  log_verbose "~/.claude/settings.json: jq not available, using basic config"
  if [ ! -f "$GLOBAL_SETTINGS" ] || [ "$(cat "$GLOBAL_SETTINGS" 2>/dev/null)" = "{}" ]; then
    echo "$GLOBAL_PERMISSIONS" > "$GLOBAL_SETTINGS"
    ACTIONS+=("Created ~/.claude/settings.json (basic, no jq)")
  fi
fi

# Project permissions
log_verbose ".claude/settings.json: configuring project permissions"
PROJECT_SETTINGS="$PROJECT_ROOT/.claude/settings.json"
mkdir -p "$PROJECT_ROOT/.claude"

read -r -d '' PROJECT_PERMISSIONS << 'PERMS' || true
{
  "permissions": {
    "allow": [
      "Read(sessions/**)",
      "Read(reports/**)",
      "Grep(sessions/**)",
      "Grep(reports/**)",
      "Glob(sessions/**)",
      "Glob(reports/**)"
    ]
  }
}
PERMS

if command -v jq &> /dev/null; then
  if [ -f "$PROJECT_SETTINGS" ] && [ -s "$PROJECT_SETTINGS" ]; then
    log_verbose "  merging project permissions..."
    EXISTING=$(cat "$PROJECT_SETTINGS")
    MERGED=$(echo "$EXISTING" | jq --argjson new "$PROJECT_PERMISSIONS" '
      .permissions.allow = ((.permissions.allow // []) + $new.permissions.allow | unique)
    ')
    if [ "$EXISTING" != "$MERGED" ]; then
      echo "$MERGED" > "$PROJECT_SETTINGS"
      ACTIONS+=("Updated .claude/settings.json permissions")
    else
      log_verbose "  project permissions: OK"
    fi
  else
    log_verbose "  creating project settings.json..."
    echo "$PROJECT_PERMISSIONS" > "$PROJECT_SETTINGS"
    ACTIONS+=("Created .claude/settings.json")
  fi
else
  if [ ! -f "$PROJECT_SETTINGS" ] || [ "$(cat "$PROJECT_SETTINGS" 2>/dev/null)" = "{}" ] || [ ! -s "$PROJECT_SETTINGS" ]; then
    log_verbose "  creating project settings.json (basic)..."
    echo "$PROJECT_PERMISSIONS" > "$PROJECT_SETTINGS"
    ACTIONS+=("Created .claude/settings.json (basic)")
  else
    log_verbose "  project settings: OK"
  fi
fi

# ---- Output summary ----
log_step "Complete"
if [ ${#ACTIONS[@]} -gt 0 ]; then
  echo ""
  echo "Done:"
  for action in "${ACTIONS[@]}"; do
    echo "  - $action"
  done
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
  echo ""
  echo "Missing: ${MISSING_DEPS[*]} (install Homebrew, then re-run setup.sh)"
fi
