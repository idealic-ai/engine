#!/bin/bash
set -euo pipefail

# ============================================================================
# Workflow Engine CLI
# ============================================================================
# The main entrypoint for the Claude workflow engine. Dispatches sub-commands
# to scripts in the scripts/ directory, with built-in commands for setup,
# mode switching, and Git operations.
#
# Usage:
#   engine                          Launch Claude (auto-setup if needed)
#   engine run [args...]            Launch Claude (explicit)
#   engine <command> [args...]      Run a sub-command (any script in scripts/)
#   engine --help                   Show all commands with descriptions
#   engine --verbose <command>      Verbose output
#
# Built-in commands:
#   engine run [args...]            Launch Claude via run.sh
#   engine fleet <cmd> [args...]    Fleet management (start, stop, status)
#   engine setup [project-name]     Full project setup (symlinks, permissions, etc.)
#   engine local                    Switch to local mode (+ Git onboarding)
#   engine remote                   Switch engine symlinks to GDrive
#   engine status                   Show current mode + symlink audit
#   engine report                   Full system health report
#   engine toc                      Show engine directory tree (~/.claude/)
#   engine push [message]            Commit (if dirty) + push to origin
#   engine pull                     git pull engine from origin
#   engine deploy                   Sync local engine → GDrive (rsync)
#   engine test [args...]           Run engine test suite
#   engine reindex                  Rebuild doc-search + session-search DBs
#   engine uninstall                Remove engine symlinks
#
# Auto-dispatch:
#   engine session activate ...     → scripts/session.sh activate ...
#   engine tag find '#needs-review' → scripts/tag.sh find '#needs-review'
#   engine log ...                  → scripts/log.sh ...
#   (any scripts/*.sh file)
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
#   Engine docs: (~/.claude/engine/docs/)
#     ENGINE_LIFECYCLE.md — Mode system, sync operations, Git workflow, troubleshooting
#     INVARIANTS.md — Engine-specific invariants (tmux, hooks)
#   Shared docs: (~/.claude/docs/)
#     ENGINE_CLI.md — CLI protocol, function signatures, migration system
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_TEST_SANDBOX_ISOLATION — Test safety requirements
#     ¶INV_INFER_USER_FROM_GDRIVE — Identity detection
#
# CONTRIBUTING:
#   Before modifying this script, read ~/.claude/engine/CONTRIBUTING.md.
#   - New pure functions → setup-lib.sh (parameterized, no globals)
#   - New migrations → setup-migrations.sh (numbered, idempotent, tested)
#   - Test coverage required for all changes (test-setup-lib.sh / test-setup-migrations.sh)
#   - All paths use $SETUP_* env vars for testability (see ENGINE_CLI.md)
# ============================================================================

# ---- Parse top-level flags ----
VERBOSE=false
AUTO_YES=false

# We need to handle --help and --verbose before anything else,
# but pass all other args through to sub-commands.
SHOW_HELP=false
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    --help|-h)
      SHOW_HELP=true
      shift
      ;;
    --yes|-y)
      AUTO_YES=true
      shift
      ;;
    *)
      # Once we hit a non-flag, everything from here is positional
      POSITIONAL_ARGS+=("$1")
      shift
      while [[ $# -gt 0 ]]; do
        POSITIONAL_ARGS+=("$1")
        shift
      done
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

# ---- Resolve paths ----

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
LOCAL_ENGINE="$HOME/.claude/engine"
MODE_FILE="$HOME/.claude/engine/.mode"
ACTIONS=()
SETUP_MARKER="$HOME/.claude/.setup-done"

# ---- Global symlink helper ----
# Relinks /usr/local/bin/engine → the given engine.sh path.
# Called by cmd_setup, cmd_local, cmd_remote.
_relink_engine_bin() {
  local target="$1"
  if [ ! -f "$target" ]; then
    log_verbose "/usr/local/bin/engine: target $target does not exist, skipping"
    return 0
  fi

  if [ -L "/usr/local/bin/engine" ]; then
    local current
    current=$(readlink "/usr/local/bin/engine")
    if [ "$current" = "$target" ]; then
      log_verbose "/usr/local/bin/engine: already correct"
      return 0
    fi
    ln -sf "$target" "/usr/local/bin/engine" 2>/dev/null || {
      echo ""
      echo "  Need sudo to update /usr/local/bin/engine → $target"
      echo "  (This makes the 'engine' command available globally)"
      (sudo mkdir -p /usr/local/bin && sudo ln -sf "$target" "/usr/local/bin/engine") || {
        echo "  WARNING: Could not update /usr/local/bin/engine"
        return 0
      }
    }
    ACTIONS+=("Updated /usr/local/bin/engine → $target")
  elif [ ! -e "/usr/local/bin/engine" ]; then
    mkdir -p /usr/local/bin 2>/dev/null || true
    ln -s "$target" "/usr/local/bin/engine" 2>/dev/null || {
      echo ""
      echo "  Need sudo to create /usr/local/bin/engine → $target"
      echo "  (This makes the 'engine' command available globally)"
      (sudo mkdir -p /usr/local/bin && sudo ln -sf "$target" "/usr/local/bin/engine") || {
        echo "  WARNING: Could not create /usr/local/bin/engine"
        return 0
      }
    }
    ACTIONS+=("Created /usr/local/bin/engine → $target")
  else
    log_verbose "/usr/local/bin/engine: exists but is not a symlink (skipping)"
  fi
}

# ---- Help command (early exit, no identity needed) ----

cmd_help() {
  cat <<'HELPTEXT'
Usage: engine [--verbose] [--help] [<command>] [args...]

The Claude workflow engine CLI. Dispatches sub-commands to scripts,
manages setup, and launches Claude.

LIFECYCLE COMMANDS
  run [args...]          Launch Claude (same as bare `engine`)
  fleet <cmd> [args...]  Fleet management (start, stop, status, list, attach)
  setup [project]        Full project setup (symlinks, permissions, deps)
  uninstall              Remove engine symlinks and hooks

MODE COMMANDS
  local                  Switch to local engine mode (+ Git onboarding)
  remote                 Switch engine symlinks to GDrive
  status                 Show current mode + symlink audit
  report                 Full system health report

GIT COMMANDS
  push [message]         Commit (if dirty) + push engine to origin
  pull                   git pull engine from origin
  deploy                 Sync local engine → GDrive (rsync)

TESTING & DIAGNOSTICS
  test [args...]         Run engine test suite
  reindex                Delete and rebuild doc-search + session-search DBs
  toc                    Show engine directory tree (~/.claude/)
  skill-doctor [name]    Validate skill definitions

SESSION MANAGEMENT
  session <cmd>          Session lifecycle (activate, phase, deactivate, check, find)
    activate <path> <skill>   Activate a session
    phase <path> "N: Name"    Transition phase
    deactivate <path>         Deactivate session
    check <path>              Validate session artifacts
    find <query>              Search sessions
    request-template <tag>    Find REQUEST template for a tag

LOGGING & TAGS
  log <file>             Append-only logging (stdin-based, auto-timestamp)
  tag <cmd>              Semantic tag management
    add <file> '#tag'         Add tag to file
    remove <file> '#tag'      Remove tag from file
    swap <file> '#old' '#new' Swap one tag for another
    find '#tag' [path]        Find files with tag

SEARCH & DISCOVERY
  session-search <cmd>   Session search via embeddings
    index [path]              Index session artifacts
    query "text"              Search sessions
  doc-search <cmd>       Documentation search via embeddings
    index [path]              Index documentation
    query "text"              Search docs
  find-sessions <cmd>    Session discovery by date/topic/tag
    today | yesterday | recent | active | topic <q> | tag <t>
  glob '<pattern>' [path]  Symlink-aware file globbing
  discover-directives <dir>  Walk-up directive file discovery

UTILITIES
  config <cmd>           Session state management (.state.json)
    get <key>                 Read a config value
    set <key> <value>         Write a config value
  user-info <cmd>        User identity detection
    username | email | json
  research <file>        Gemini Deep Research API wrapper (stdin-based)
  rewrite <in> <out>     Gemini 3 Pro document rewriter (stdin instructions)
  await-tag <file> '#tag'  Block until tag appears (fswatch)
  escape-tags <file>     Retroactive backtick-escaping for tags
  worker                 Fleet worker daemon (background)

OPTIONS
  --verbose, -v          Verbose output
  --yes, -y              Skip confirmation prompts (for scripts/tests)
  --help, -h             Show this help

EXAMPLES
  engine                              # Launch Claude (auto-setup if needed)
  engine run --agent operator         # Launch Claude with agent persona
  engine fleet start                  # Start fleet workspace
  engine setup                        # Run full project setup
  engine session activate path skill  # Activate session
  engine tag find '#needs-review'     # Find tagged files
  engine toc                          # Show engine directory tree
HELPTEXT
}

cmd_toc() {
  local engine_dir="$HOME/.claude"
  echo "Engine Directory Tree: $engine_dir"
  echo "========================================"
  echo ""

  # Scripts
  echo "scripts/"
  for script in "$engine_dir/scripts"/*.sh; do
    [ -f "$script" ] || continue
    local name
    name=$(basename "$script")
    # Extract short description: find first comment line with " — " separator
    local desc=""
    desc=$(grep -m1 '^ *# .*— ' "$script" 2>/dev/null | sed 's/.*— //' | head -c 60)
    if [ -z "$desc" ]; then
      # Fallback: second comment line, strip path prefixes
      desc=$(sed -n '2s|^# *\(~/.claude/[^ ]* — \)\{0,1\}||p' "$script" 2>/dev/null | head -c 60)
    fi
    printf "  %-30s %s\n" "$name" "${desc:-(no description)}"
  done
  echo ""

  # Skills
  echo "skills/"
  for skill_dir in "$engine_dir/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    local skill_name
    skill_name=$(basename "$skill_dir")
    # Read description from SKILL.md frontmatter
    local desc=""
    if [ -f "$skill_dir/SKILL.md" ]; then
      desc=$(sed -n '/^description:/{ s/^description: *"\{0,1\}//; s/"\{0,1\} *$//; s/\. Triggers:.*//; p; q; }' "$skill_dir/SKILL.md" 2>/dev/null)
    fi
    printf "  %-25s %s\n" "$skill_name/" "${desc:-(no description)}"
    # List assets
    if [ -d "$skill_dir/assets" ]; then
      for asset in "$skill_dir/assets"/*.md; do
        [ -f "$asset" ] || continue
        printf "    assets/%-20s\n" "$(basename "$asset")"
      done
    fi
    # List modes
    if [ -d "$skill_dir/modes" ]; then
      for mode in "$skill_dir/modes"/*.md; do
        [ -f "$mode" ] || continue
        printf "    modes/%-20s\n" "$(basename "$mode")"
      done
    fi
  done
  echo ""

  # Agents
  if [ -d "$engine_dir/agents" ]; then
    echo "agents/"
    for agent in "$engine_dir/agents"/*.md; do
      [ -f "$agent" ] || continue
      local name
      name=$(basename "$agent" .md)
      local desc
      desc=$(sed -n '/^description:/{ s/^description: *"\{0,1\}//; s/"\{0,1\} *$//; p; q; }' "$agent" 2>/dev/null)
      printf "  %-25s %s\n" "$name.md" "${desc:-(no description)}"
    done
    echo ""
  fi

  # Hooks
  if [ -d "$engine_dir/hooks" ]; then
    echo "hooks/"
    for hook in "$engine_dir/hooks"/*.sh; do
      [ -f "$hook" ] || continue
      local name
      name=$(basename "$hook")
      local desc
      desc=$(sed -n '2s/^# *//p' "$hook" 2>/dev/null | head -c 80)
      printf "  %-40s %s\n" "$name" "${desc:-(no description)}"
    done
    echo ""
  fi

  # Directives
  if [ -d "$engine_dir/.directives" ]; then
    echo ".directives/"
    for directive in "$engine_dir/.directives"/*.md; do
      [ -f "$directive" ] || continue
      printf "  %s\n" "$(basename "$directive")"
    done
    if [ -d "$engine_dir/.directives/commands" ]; then
      echo "  commands/"
      for cmd_file in "$engine_dir/.directives/commands"/*.md; do
        [ -f "$cmd_file" ] || continue
        printf "    %s\n" "$(basename "$cmd_file")"
      done
    fi
    echo ""
  fi

  # Docs
  if [ -d "$engine_dir/docs" ]; then
    echo "docs/"
    for doc in "$engine_dir/docs"/*.md; do
      [ -f "$doc" ] || continue
      printf "  %s\n" "$(basename "$doc")"
    done
    echo ""
  fi

  # Engine-specific docs
  local engine_engine="$engine_dir/engine"
  if [ -d "$engine_engine/docs" ]; then
    echo "engine/docs/"
    for doc in "$engine_engine/docs"/*.md; do
      [ -f "$doc" ] || continue
      printf "  %s\n" "$(basename "$doc")"
    done
    echo ""
  fi

  # Tools
  if [ -d "$engine_dir/tools" ]; then
    echo "tools/"
    for tool_dir in "$engine_dir/tools"/*/; do
      [ -d "$tool_dir" ] || continue
      printf "  %s\n" "$(basename "$tool_dir")/"
    done
    echo ""
  fi
}

if [ "$SHOW_HELP" = true ]; then
  cmd_help
  exit 0
fi

# ---- Early-exit commands (no identity needed) ----

# toc: directory tree (doesn't need identity resolution)
if [ "${POSITIONAL_ARGS[0]:-}" = "toc" ]; then
  cmd_toc
  exit 0
fi

# ---- Resolve identity (needed for most commands) ----

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
  echo "Or run 'engine setup' first to cache identity."
  exit 1
fi

USER_NAME="${EMAIL%%@*}"

# Engine path constants
GDRIVE_ENGINE="$HOME/Library/CloudStorage/GoogleDrive-$EMAIL/Shared drives/finch-os/engine"
GDRIVE_ROOT="$HOME/Library/CloudStorage/GoogleDrive-$EMAIL/Shared drives/finch-os"

log_verbose "User: $USER_NAME ($EMAIL)"

# ============================================================================
# Built-in subcommand handlers
# ============================================================================

cmd_local() {
  local PROJECT_NAME="${1:-$(basename "$(pwd)")}"

  if [ ! -d "$LOCAL_ENGINE" ]; then
    echo "ERROR: Local engine not found at $LOCAL_ENGINE"
    echo "Run 'engine pull' first to copy engine from GDrive."
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
        echo "You can re-run 'engine local' to try again."
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

  # Install npm deps for tools if needed
  for tool_dir in "$LOCAL_ENGINE/tools"/*/; do
    local tool_name
    tool_name="$(basename "$tool_dir")"
    if [ -f "$tool_dir/package.json" ] && [ ! -d "$tool_dir/node_modules" ]; then
      echo "  Installing $tool_name npm deps..."
      (cd "$tool_dir" && npm install --silent 2>/dev/null) && ACTIONS+=("Installed $tool_name npm deps")
    fi
  done

  # Install brew deps if needed
  if command -v brew &> /dev/null; then
    for dep in jq sqlite3 fswatch tmuxinator; do
      local formula="$dep"
      [ "$dep" = "sqlite3" ] && formula="sqlite"
      if ! command -v "$dep" &> /dev/null; then
        echo "  Installing $dep..."
        brew install "$formula" >/dev/null 2>&1 && ACTIONS+=("Installed $dep via brew")
      fi
    done
  fi

  # Ensure sessions/ and reports/ exist via project-local .claude/ storage
  local project_root
  project_root="$(pwd)"
  local local_sessions="$project_root/.claude/sessions"
  local local_reports="$project_root/.claude/reports"
  local sessions_link="$project_root/sessions"
  local reports_link="$project_root/reports"

  if [ ! -d "$GDRIVE_ROOT" ] 2>/dev/null; then
    # GDrive unavailable: create project-local dirs + symlinks
    mkdir -p "$local_sessions" "$local_reports"

    # Fix or create sessions/ symlink
    if [ -L "$sessions_link" ] && [ ! -e "$sessions_link" ]; then
      echo "  sessions/ symlink is broken (GDrive not accessible). Relinking to .claude/sessions..."
      rm "$sessions_link"
      ln -s "$local_sessions" "$sessions_link"
      ACTIONS+=("Relinked sessions/ → .claude/sessions (GDrive unavailable)")
    elif [ ! -e "$sessions_link" ]; then
      echo "  Creating sessions/ → .claude/sessions..."
      ln -s "$local_sessions" "$sessions_link"
      ACTIONS+=("Linked sessions/ → .claude/sessions")
    fi

    # Fix or create reports/ symlink
    if [ -L "$reports_link" ] && [ ! -e "$reports_link" ]; then
      echo "  reports/ symlink is broken (GDrive not accessible). Relinking to .claude/reports..."
      rm "$reports_link"
      ln -s "$local_reports" "$reports_link"
      ACTIONS+=("Relinked reports/ → .claude/reports (GDrive unavailable)")
    elif [ ! -e "$reports_link" ]; then
      echo "  Creating reports/ → .claude/reports..."
      ln -s "$local_reports" "$reports_link"
      ACTIONS+=("Linked reports/ → .claude/reports")
    fi
  else
    # GDrive available: ensure sessions/ exists (may be real dir or symlink)
    local sessions_dir="$project_root/sessions"
    if [ ! -e "$sessions_dir" ]; then
      echo "  Creating local sessions/ directory..."
      mkdir -p "$sessions_dir"
      ACTIONS+=("Created local sessions/ directory")
    fi
  fi

  # Bootstrap search DBs: copy from GDrive if available, otherwise auto-index
  # Resolve the actual sessions dir (follows symlink or uses real dir)
  local resolved_sessions_dir="$project_root/sessions"
  if [ -L "$resolved_sessions_dir" ]; then
    resolved_sessions_dir="$(readlink "$resolved_sessions_dir")"
  fi
  local doc_db="$resolved_sessions_dir/.doc-search.db"
  local session_db="$resolved_sessions_dir/.session-search.db"

  if [ -d "$GDRIVE_ROOT" ] 2>/dev/null; then
    local gdrive_sessions="$GDRIVE_ROOT/$USER_NAME/$PROJECT_NAME/sessions"
    local gdrive_doc_db="$gdrive_sessions/.doc-search.db"
    local gdrive_session_db="$gdrive_sessions/.session-search.db"
    local gdrive_tool_doc_db="$GDRIVE_ENGINE/tools/doc-search/.doc-search.db"

    if [ -f "$gdrive_doc_db" ]; then
      cp_if_different "$gdrive_doc_db" "$doc_db" "doc-search DB from GDrive sessions/"
    elif [ -f "$gdrive_tool_doc_db" ]; then
      cp_if_different "$gdrive_tool_doc_db" "$doc_db" "doc-search DB from GDrive tool dir"
    fi

    if [ -f "$gdrive_session_db" ]; then
      cp_if_different "$gdrive_session_db" "$session_db" "session-search DB from GDrive"
    fi
  else
    echo "  GDrive not accessible. Search DBs will be empty until indexed."
    echo "  Run: doc-search.sh index && session-search.sh index"
  fi

  # Relink /usr/local/bin/engine → local engine
  _relink_engine_bin "$LOCAL_ENGINE/scripts/engine.sh"

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

  # Relink /usr/local/bin/engine → GDrive engine
  _relink_engine_bin "$engine_dir/scripts/engine.sh"

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
    echo "Run 'engine local' first to initialize Git."
    exit 1
  fi
  if [ ! -d "$LOCAL_ENGINE/.git" ]; then
    echo "ERROR: No Git repository found in $LOCAL_ENGINE"
    echo "Run 'engine local' first to initialize Git."
    exit 1
  fi
  if ! command -v git &>/dev/null; then
    echo "ERROR: Git is required. Install with: brew install git"
    exit 1
  fi

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
    echo "Run 'engine local' first to initialize Git."
    exit 1
  fi
  if ! command -v git &>/dev/null; then
    echo "ERROR: Git is required. Install with: brew install git"
    exit 1
  fi

  local branch
  branch=$(git -C "$LOCAL_ENGINE" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -z "$branch" ]; then
    echo "ERROR: Could not determine current Git branch."
    exit 1
  fi

  # Commit message: from argument or interactive prompt
  local commit_msg="${1:-}"

  # Check for uncommitted changes
  local status
  status=$(git -C "$LOCAL_ENGINE" status --porcelain 2>/dev/null)

  if [ -n "$status" ]; then
    echo "Uncommitted changes detected on $branch:"
    echo ""
    git -C "$LOCAL_ENGINE" status --short 2>/dev/null
    echo ""

    # Prompt for commit message if not provided as argument
    if [ -z "$commit_msg" ]; then
      printf "Commit message (empty to abort): "
      read -r commit_msg
      if [ -z "$commit_msg" ]; then
        echo "Aborted. No commit created, nothing pushed."
        exit 0
      fi
    fi

    # Stage all and commit
    git -C "$LOCAL_ENGINE" add -A 2>&1
    git -C "$LOCAL_ENGINE" commit -m "$commit_msg" 2>&1
    ACTIONS+=("Committed: $commit_msg")
    echo ""
  else
    echo "Working tree clean on $branch."
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
  if [ -d "$GDRIVE_ENGINE" ]; then
    echo "  Backing up GDrive → ${GDRIVE_ENGINE}.bak"
    rm -rf "${GDRIVE_ENGINE}.bak"
    cp -a "$GDRIVE_ENGINE" "${GDRIVE_ENGINE}.bak"
    ACTIONS+=("Backed up $GDRIVE_ENGINE → ${GDRIVE_ENGINE}.bak")
  fi
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
  for link in "$CLAUDE_DIR"/{standards,agents,tools} "$CLAUDE_DIR/scripts"/* "$CLAUDE_DIR/hooks"/* "$CLAUDE_DIR/skills"/*; do
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

  if [ "$mode" = "local" ] && [ "$gdrive_count" -gt 0 ]; then
    echo "⚠️  Mode is 'local' but $gdrive_count symlinks still point to GDrive."
    echo "   Run 'engine local' to fix."
  elif [ "$mode" = "remote" ] && [ "$local_count" -gt 0 ]; then
    echo "⚠️  Mode is 'remote' but $local_count symlinks still point to local engine."
    echo "   Run 'engine remote' to fix."
  elif [ "$broken_count" -gt 0 ]; then
    echo "⚠️  $broken_count broken symlinks detected."
    echo "   Run 'engine $mode' to fix."
  else
    echo "✓ All symlinks consistent with mode."
  fi

  echo ""
  echo "Dependencies:"
  local dep_ok=true
  for cmd in jq sqlite3 fswatch tmuxinator; do
    if command -v $cmd &>/dev/null; then
      echo "  $cmd: ✓"
    else
      echo "  $cmd: ✗ (not installed)"
      dep_ok=false
    fi
  done
  if [ "$dep_ok" = false ]; then
    echo ""
    echo "⚠️  Missing dependencies. Run 'engine setup' to install via brew."
  fi

  echo ""
  echo "Backups:"
  [ -d "${LOCAL_ENGINE}.bak" ] && echo "  Local:  ${LOCAL_ENGINE}.bak ✓" || echo "  Local:  (none)"
  [ -d "${GDRIVE_ENGINE}.bak" ] && echo "  GDrive: ${GDRIVE_ENGINE}.bak ✓" || echo "  GDrive: (none)"
}

cmd_test() {
  local tests_dir
  tests_dir="$(cd "$(dirname "$0")" && pwd)/tests"

  if [ ! -f "$tests_dir/run-all.sh" ]; then
    echo "ERROR: Test runner not found at $tests_dir/run-all.sh"
    exit 1
  fi

  bash "$tests_dir/run-all.sh" "$@"
}

cmd_uninstall() {
  local project_root
  project_root="${PROJECT_ROOT:-$(pwd)}"

  echo "Uninstalling engine from: $project_root"
  echo ""

  local removed=0
  for link in "$project_root/sessions" "$project_root/reports"; do
    if [ -L "$link" ]; then
      rm "$link"
      echo "  Removed: $(basename "$link")/ symlink"
      removed=$((removed + 1))
    fi
  done

  local claude_dir="$HOME/.claude"
  for link in "$claude_dir/standards" "$claude_dir/directives" "$claude_dir/.directives" "$claude_dir/scripts" "$claude_dir/tools"; do
    if [ -L "$link" ]; then
      rm "$link"
      echo "  Removed: ~/.claude/$(basename "$link") symlink"
      removed=$((removed + 1))
    fi
  done

  for dir in scripts skills agents hooks; do
    if [ -d "$claude_dir/$dir" ]; then
      local link_count=0
      for link in "$claude_dir/$dir"/*; do
        if [ -L "$link" ]; then
          rm "$link"
          link_count=$((link_count + 1))
        fi
      done
      if [ "$link_count" -gt 0 ]; then
        echo "  Removed: $link_count ~/.claude/$dir/ symlinks"
        removed=$((removed + 1))
      fi
    fi
  done

  if [ -L "/usr/local/bin/engine" ]; then
    rm "/usr/local/bin/engine" 2>/dev/null || sudo rm "/usr/local/bin/engine" 2>/dev/null || {
      echo "  WARNING: Could not remove /usr/local/bin/engine (try: sudo rm /usr/local/bin/engine)"
    }
    echo "  Removed: /usr/local/bin/engine symlink"
    removed=$((removed + 1))
  fi

  local settings="$claude_dir/settings.json"
  if [ -f "$settings" ] && command -v jq &>/dev/null; then
    local hooks_removed=0

    local sl_cmd
    sl_cmd=$(jq -r '.statusLine.command // ""' "$settings" 2>/dev/null)
    if [[ "$sl_cmd" == *"statusline.sh"* ]]; then
      jq 'del(.statusLine)' "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
      hooks_removed=$((hooks_removed + 1))
    fi

    for hook_type in PreToolUse PostToolUse Stop Notification UserPromptSubmit SessionEnd PostToolUseSuccess PostToolUseFailure; do
      if jq -e ".hooks.${hook_type}" "$settings" &>/dev/null; then
        local remaining
        remaining=$(jq --arg ht "$hook_type" '
          .hooks[$ht] |= [.[] | select(
            (.hooks // []) | all(.command // "" | (contains("~/.claude/hooks/") or contains("~/.claude/tools/")) | not)
          )] | if .hooks[$ht] | length == 0 then del(.hooks[$ht]) else . end
        ' "$settings" 2>/dev/null)
        if [ -n "$remaining" ] && [ "$remaining" != "$(cat "$settings")" ]; then
          echo "$remaining" > "$settings"
          hooks_removed=$((hooks_removed + 1))
        fi
      fi
    done

    if jq -e '.hooks | length == 0' "$settings" &>/dev/null; then
      jq 'del(.hooks)' "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
    fi

    if jq -e '.permissions.allow' "$settings" &>/dev/null; then
      jq '.permissions.allow = [.permissions.allow[] | select(
        (startswith("Read(~/.claude/") or
         startswith("Glob(~/.claude/") or
         startswith("Grep(~/.claude/") or
         startswith("Bash(~/.claude/scripts/") or
         startswith("Bash(~/.claude/tools/")) | not
      )]' "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
      hooks_removed=$((hooks_removed + 1))
    fi

    if [ "$hooks_removed" -gt 0 ]; then
      echo "  Cleaned engine hooks from ~/.claude/settings.json"
      removed=$((removed + 1))
    fi
  fi

  # Remove setup marker
  rm -f "$SETUP_MARKER"

  echo ""
  if [ "$removed" -gt 0 ]; then
    echo "Uninstalled ($removed items removed)."
    echo "Settings preserved: ~/.claude/settings.json (hooks cleaned, file kept)"
  else
    echo "Nothing to uninstall — no engine symlinks found."
  fi
}

cmd_report() {
  # ---- Resolve ENGINE_DIR based on current mode ----
  local ENGINE_DIR
  ENGINE_DIR=$(resolve_engine_dir "$(current_mode "$MODE_FILE")" "$LOCAL_ENGINE" "$GDRIVE_ENGINE" "$SCRIPT_DIR")

  local PROJECT_ROOT
  PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

  echo "Workflow Engine Status"
  echo "======================"
  echo ""
  echo "Mode: $(current_mode "$MODE_FILE")"
  echo "User: $USER_NAME ($EMAIL)"
  echo "Engine: $ENGINE_DIR"
  echo ""

  # Check symlinks
  echo "Engine Symlinks (~/.claude/):"
  for name in standards scripts agents tools; do
    local link="$CLAUDE_DIR/$name"
    if [ -L "$link" ]; then
      local target
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

  echo ""
  echo "Skills (~/.claude/skills/):"
  if [ -L "$CLAUDE_DIR/skills" ]; then
    echo "  WARNING: whole-dir symlink (should be per-skill)"
  elif [ -d "$CLAUDE_DIR/skills" ]; then
    local engine_skills installed_skills
    engine_skills=$(find "$ENGINE_DIR/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    installed_skills=$(find "$CLAUDE_DIR/skills" -mindepth 1 -maxdepth 1 -type l 2>/dev/null | wc -l | tr -d ' ')
    echo "  $installed_skills/$engine_skills skills linked"
    for skill_dir in "$ENGINE_DIR/skills"/*/; do
      local skill_name
      skill_name="$(basename "$skill_dir")"
      if [ ! -L "$CLAUDE_DIR/skills/$skill_name" ]; then
        echo "    MISSING: $skill_name"
      fi
    done
  else
    echo "  MISSING: ~/.claude/skills/ directory"
  fi

  echo ""
  echo "Tools (~/.claude/tools/):"
  if [ -d "$CLAUDE_DIR/tools" ]; then
    for tool_dir in "$ENGINE_DIR/tools"/*/; do
      local tool_name
      tool_name="$(basename "$tool_dir")"
      if [ -f "$tool_dir/package.json" ]; then
        if [ -d "$tool_dir/node_modules" ]; then
          echo "  $tool_name: OK"
        else
          echo "  $tool_name: MISSING node_modules (run engine setup)"
        fi
      fi
    done
  else
    echo "  MISSING: ~/.claude/tools/ directory"
  fi

  echo ""
  echo "Hooks (~/.claude/settings.json):"
  if [ -f "$CLAUDE_DIR/settings.json" ] && command -v jq &>/dev/null; then
    if jq -e '.statusLine' "$CLAUDE_DIR/settings.json" &>/dev/null; then
      local sl_cmd
      sl_cmd=$(jq -r '.statusLine.command // "none"' "$CLAUDE_DIR/settings.json")
      if [[ "$sl_cmd" == *"statusline.sh"* ]]; then
        echo "  statusLine: OK (engine)"
      elif [[ "$sl_cmd" == *"input=\$(cat)"* ]] || [[ ${#sl_cmd} -gt 100 ]]; then
        echo "  statusLine: DEFAULT (not engine) - run engine setup to fix"
      else
        echo "  statusLine: $sl_cmd"
      fi
    else
      echo "  statusLine: NOT CONFIGURED"
    fi
    local ptu_count perm_count
    ptu_count=$(jq '.hooks.PreToolUse // [] | length' "$CLAUDE_DIR/settings.json" 2>/dev/null || echo "0")
    echo "  PreToolUse hooks: $ptu_count"
    perm_count=$(jq '.permissions.allow // [] | length' "$CLAUDE_DIR/settings.json" 2>/dev/null || echo "0")
    echo "  Permissions: $perm_count rules"
  elif [ -f "$CLAUDE_DIR/settings.json" ]; then
    echo "  (install jq for detailed hook info)"
  else
    echo "  MISSING: ~/.claude/settings.json"
  fi

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

  echo ""
  echo "Script Permissions:"
  local non_exec_count=0
  local non_exec_files=()
  while IFS= read -r -d '' script; do
    if [ ! -x "$script" ]; then
      non_exec_count=$((non_exec_count + 1))
      non_exec_files+=("$(basename "$script")")
    fi
  done < <(find "$ENGINE_DIR" -name "*.sh" -type f -print0 2>/dev/null)

  local total_scripts exec_count
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
      echo "    ... and $((non_exec_count - 10)) more (run engine setup to fix)"
    fi
  fi

  echo ""
  echo "Dependencies:"
  for cmd in jq sqlite3 fswatch tmuxinator; do
    if command -v $cmd &>/dev/null; then
      echo "  $cmd: $(which $cmd)"
    else
      echo "  $cmd: NOT INSTALLED (brew install $cmd)"
    fi
  done
}

# ============================================================================
# cmd_setup — Full project setup (was the old default behavior)
# ============================================================================

cmd_setup() {
  # Parse cmd_setup's own args (supports `engine setup --yes [name]`)
  local setup_args=()
  while [[ $# -gt 0 ]]; do
    case $1 in
      --yes|-y) AUTO_YES=true; shift ;;
      *)        setup_args+=("$1"); shift ;;
    esac
  done
  set -- "${setup_args[@]+"${setup_args[@]}"}"

  local ENGINE_DIR
  ENGINE_DIR=$(resolve_engine_dir "$(current_mode "$MODE_FILE")" "$LOCAL_ENGINE" "$GDRIVE_ENGINE" "$SCRIPT_DIR")

  if [ -z "$ENGINE_DIR" ] || [ ! -d "$ENGINE_DIR/skills" ]; then
    echo "ERROR: Engine not found."
    echo "Expected skills/ in engine directory."
    exit 1
  fi

  local PROJECT_NAME="${1:-$(basename "$(pwd)")}"
  local PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

  # Resolve where sessions/reports live:
  #   - Remote mode: GDrive path (via ENGINE_DIR parent)
  #   - Local mode + GDrive available: GDrive path
  #   - Local mode + GDrive unavailable: project-local .claude/ directory
  local GDRIVE_ROOT_RESOLVED
  local USE_LOCAL_STORAGE=false
  if [ "$(current_mode "$MODE_FILE")" = "local" ]; then
    if [ -d "$GDRIVE_ROOT" ] 2>/dev/null; then
      GDRIVE_ROOT_RESOLVED="$GDRIVE_ROOT"
    else
      USE_LOCAL_STORAGE=true
      GDRIVE_ROOT_RESOLVED="$PROJECT_ROOT/.claude"
    fi
  else
    GDRIVE_ROOT_RESOLVED="$(dirname "$ENGINE_DIR")"
  fi

  log_verbose "Engine: $ENGINE_DIR"
  log_verbose "Project: $PROJECT_ROOT"

  # Prevent running from home directory
  if [ "$PROJECT_ROOT" = "$HOME" ] || [ "$PROJECT_ROOT" = "/" ]; then
    echo "ERROR: Cannot run setup from home directory or root."
    echo "Please cd to your project directory first."
    echo ""
    echo "Example:"
    echo "  cd ~/Projects/myproject"
    echo "  engine setup"
    exit 1
  fi

  # Confirmation prompt (skip with --yes)
  if [ "$AUTO_YES" != true ]; then
    local storage_desc
    if [ "$USE_LOCAL_STORAGE" = true ]; then
      storage_desc="project-local (.claude/sessions)"
    else
      storage_desc="GDrive ($GDRIVE_ROOT_RESOLVED/$USER_NAME/$PROJECT_NAME)"
    fi
    echo ""
    echo "About to set up workflow engine:"
    echo "  Project:  $PROJECT_NAME"
    echo "  Path:     $PROJECT_ROOT"
    echo "  Engine:   $ENGINE_DIR"
    echo "  Mode:     $(current_mode "$MODE_FILE")"
    echo "  Storage:  $storage_desc"
    echo ""
    echo "This will create symlinks, configure settings, and set up session directories."
    echo ""
    read -rp "Proceed? [y/N] " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
      echo "Aborted."
      exit 0
    fi
    echo ""
  fi

  echo "Setting up workflow engine for $USER_NAME/$PROJECT_NAME"

  local MISSING_DEPS=()

  # ---- Install dependencies via brew ----
  log_step "Checking dependencies"
  if command -v brew &> /dev/null; then
    for dep in jq sqlite3 fswatch tmuxinator; do
      # sqlite3 is installed via the "sqlite" brew formula
      local formula="$dep"
      [ "$dep" = "sqlite3" ] && formula="sqlite"
      if ! command -v "$dep" &> /dev/null; then
        echo "  Installing $dep..."
        if [ "$VERBOSE" = true ]; then
          brew install "$formula" && ACTIONS+=("Installed $dep via brew")
        else
          brew install "$formula" >/dev/null 2>&1 && ACTIONS+=("Installed $dep via brew")
        fi
      else
        log_verbose "$dep: OK"
      fi
    done
  else
    for dep in jq sqlite3 fswatch tmuxinator; do
      if ! command -v "$dep" &> /dev/null; then MISSING_DEPS+=("$dep"); fi
    done
  fi

  # ---- Step 1: Create session/report directories ----
  log_step "Step 1: Create session/report directories"
  local SESSION_DIR REPORTS_DIR
  if [ "$USE_LOCAL_STORAGE" = true ]; then
    # Local mode without GDrive: store directly under project/.claude/
    SESSION_DIR="$PROJECT_ROOT/.claude/sessions"
    REPORTS_DIR="$PROJECT_ROOT/.claude/reports"
    log_verbose "Using project-local storage (GDrive unavailable)"
  else
    # GDrive available: store under GDrive user/project path
    SESSION_DIR="$GDRIVE_ROOT_RESOLVED/$USER_NAME/$PROJECT_NAME/sessions"
    REPORTS_DIR="$GDRIVE_ROOT_RESOLVED/$USER_NAME/$PROJECT_NAME/reports"
  fi
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
      local tool_name
      tool_name="$(basename "$tool_dir")"
      if [ -f "$tool_dir/package.json" ] && [ ! -d "$tool_dir/node_modules" ]; then
        echo "  Installing $tool_name npm deps..."
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

  # ---- Step 4: Create project directives stub ----
  log_step "Step 4: Project directives"
  ensure_project_directives "$PROJECT_ROOT"

  # ---- Step 5: Update .gitignore ----
  log_step "Step 5: Update .gitignore"
  local GITIGNORE="$PROJECT_ROOT/.gitignore"
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

Each subdirectory is one work session, named `YYYY_MM_DD_TOPIC/`. Sessions are created automatically by workflow commands (`/brainstorm`, `/implement`, `/fix`, etc.).

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

  # ---- Step 7: Configure Claude Code settings ----
  # Engine config (hooks, statusLine, permissions) lives in PROJECT-LOCAL .claude/settings.json.
  # Global ~/.claude/settings.json is for non-engine user config only.
  log_step "Step 7: Configure settings"
  local GLOBAL_SETTINGS="$CLAUDE_DIR/settings.json"
  local PROJECT_SETTINGS="$PROJECT_ROOT/.claude/settings.json"
  mkdir -p "$PROJECT_ROOT/.claude"

  # All engine permissions — combined global + project scope
  read -r -d '' ENGINE_PERMISSIONS << 'PERMS' || true
{
  "permissions": {
    "allow": [
      "Bash(engine *)",
      "Bash(~/.claude/scripts/*)",
      "Bash(~/.claude/tools/doc-search/doc-search.sh *)",
      "Bash(~/.claude/tools/session-search/session-search.sh *)",
      "Glob(reports/**)",
      "Glob(sessions/**)",
      "Glob(~/.claude/**)",
      "Grep(reports/**)",
      "Grep(sessions/**)",
      "Grep(~/.claude/**)",
      "Read(reports/**)",
      "Read(sessions/**)",
      "Read(~/.claude/agents/**)",
      "Read(~/.claude/commands/**)",
      "Read(~/.claude/.directives/**)",
      "Read(~/.claude/skills/**)"
    ]
  }
}
PERMS

  if command -v jq &> /dev/null; then
    # ---- Project-local settings (hooks + statusLine + permissions) ----
    log_verbose ".claude/settings.json: configuring project settings with jq"

    if [ -f "$PROJECT_SETTINGS" ] && [ -s "$PROJECT_SETTINGS" ]; then
      log_verbose "  merging project permissions..."
      local EXISTING MERGED
      EXISTING=$(cat "$PROJECT_SETTINGS")
      MERGED=$(echo "$EXISTING" | jq --argjson new "$ENGINE_PERMISSIONS" '
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
      echo "$ENGINE_PERMISSIONS" > "$PROJECT_SETTINGS"
      ACTIONS+=("Created .claude/settings.json")
    fi

    # StatusLine hook (project-local)
    log_verbose "  checking statusLine hook..."
    configure_statusline "$PROJECT_SETTINGS"

    # Engine hooks (project-local, deep-merge via setup-lib.sh)
    log_verbose "  checking engine hooks..."
    configure_hooks "$PROJECT_SETTINGS"

    # ---- Global settings (strip engine config) ----
    # Ensure global settings.json exists but has no engine-owned config
    if [ -f "$GLOBAL_SETTINGS" ] && [ -s "$GLOBAL_SETTINGS" ]; then
      log_verbose "~/.claude/settings.json: ensuring no engine config in global"
      local HAS_HOOKS HAS_SL
      HAS_HOOKS=$(jq 'has("hooks")' "$GLOBAL_SETTINGS" 2>/dev/null)
      HAS_SL=$(jq 'has("statusLine")' "$GLOBAL_SETTINGS" 2>/dev/null)
      if [ "$HAS_HOOKS" = "true" ] || [ "$HAS_SL" = "true" ]; then
        log_verbose "  stripping hooks/statusLine from global settings..."
        MERGED=$(cat "$GLOBAL_SETTINGS" | jq 'del(.hooks) | del(.statusLine)')
        echo "$MERGED" > "$GLOBAL_SETTINGS"
        ACTIONS+=("Stripped engine config from ~/.claude/settings.json")
      else
        log_verbose "  global settings: clean"
      fi
    else
      log_verbose "~/.claude/settings.json: creating minimal"
      echo '{}' > "$GLOBAL_SETTINGS"
      ACTIONS+=("Created ~/.claude/settings.json (minimal)")
    fi
  else
    log_verbose ".claude/settings.json: jq not available, using basic config"
    if [ ! -f "$PROJECT_SETTINGS" ] || [ "$(cat "$PROJECT_SETTINGS" 2>/dev/null)" = "{}" ] || [ ! -s "$PROJECT_SETTINGS" ]; then
      echo "$ENGINE_PERMISSIONS" > "$PROJECT_SETTINGS"
      ACTIONS+=("Created .claude/settings.json (basic, no jq)")
    fi
  fi

  # ---- Global symlink (/usr/local/bin/engine) ----
  # Links to the mode-resolved engine.sh so `engine` always runs the right copy.
  _relink_engine_bin "$ENGINE_DIR/scripts/engine.sh"

  # ---- Mark setup as complete ----
  mkdir -p "$(dirname "$SETUP_MARKER")"
  touch "$SETUP_MARKER"

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
    echo "Missing: ${MISSING_DEPS[*]} (install Homebrew, then re-run engine setup)"
  fi
}

# ============================================================================
# Main dispatch
# ============================================================================

# Get the sub-command (first positional arg)
SUBCMD="${1:-}"

# If a sub-command was given, shift it off so "$@" contains only its args
if [ -n "$SUBCMD" ]; then
  shift
fi

cmd_reindex() {
  local sessions_dir
  sessions_dir=$(cd "$(pwd)/sessions" 2>/dev/null && pwd -P 2>/dev/null || echo "$(pwd)/sessions")

  echo "Reindexing search databases..."
  echo ""

  # Remove existing DB files
  local removed=0
  for db_file in "$sessions_dir/.doc-search.db" "$sessions_dir/.session-search.db"; do
    if [ -f "$db_file" ]; then
      rm "$db_file"
      echo "  Deleted: $(basename "$db_file")"
      removed=$((removed + 1))
    fi
  done

  # Also remove lock files
  for lock_file in "$sessions_dir/.doc-search.lock"; do
    if [ -f "$lock_file" ]; then
      rm "$lock_file"
      echo "  Deleted: $(basename "$lock_file")"
    fi
  done

  if [ "$removed" -eq 0 ]; then
    echo "  No existing DB files found."
  fi
  echo ""

  # Run doc-search index
  local doc_search="$SCRIPT_DIR/doc-search.sh"
  if [ -x "$doc_search" ]; then
    echo "Running doc-search index..."
    "$doc_search" index 2>&1 || echo "  WARNING: doc-search index failed"
    echo ""
  else
    echo "  SKIP: doc-search.sh not found"
  fi

  # Run session-search index
  local session_search="$SCRIPT_DIR/session-search.sh"
  if [ -x "$session_search" ]; then
    echo "Running session-search index..."
    "$session_search" index 2>&1 || echo "  WARNING: session-search index failed"
    echo ""
  else
    echo "  SKIP: session-search.sh not found"
  fi

  echo "Done. Search databases rebuilt."
}

# 1. Built-in commands (explicit handlers)
case "$SUBCMD" in
  setup)     cmd_setup "$@";     exit 0 ;;
  local)     cmd_local;          exit 0 ;;
  remote)    cmd_remote;         exit 0 ;;
  pull)      cmd_pull;           exit 0 ;;
  push)      cmd_push "$@";      exit 0 ;;
  deploy)    cmd_deploy;         exit 0 ;;
  status)    cmd_status;         exit 0 ;;
  report)    cmd_report;         exit 0 ;;
  test)      cmd_test "$@";      exit 0 ;;
  reindex)   cmd_reindex;        exit 0 ;;
  uninstall) cmd_uninstall;      exit 0 ;;
  help)      cmd_help;           exit 0 ;;
  toc)       cmd_toc;            exit 0 ;;
  run)
    # Thin wrapper: delegate to run.sh
    RUN_SCRIPT="$SCRIPT_DIR/run.sh"
    if [ -x "$RUN_SCRIPT" ]; then
      exec "$RUN_SCRIPT" "$@"
    else
      echo "ERROR: run.sh not found at $RUN_SCRIPT"
      exit 1
    fi
    ;;
  fleet)
    # Ensure setup has run before fleet operations
    if [ ! -f "$SETUP_MARKER" ]; then
      echo "First run detected. Running setup..."
      echo ""
      cmd_setup --yes
      echo ""
    fi
    # Thin wrapper: delegate to fleet.sh
    FLEET_SCRIPT="$SCRIPT_DIR/fleet.sh"
    if [ -x "$FLEET_SCRIPT" ]; then
      exec "$FLEET_SCRIPT" "$@"
    else
      echo "ERROR: fleet.sh not found at $FLEET_SCRIPT"
      exit 1
    fi
    ;;
esac

# 2. Auto-dispatch: check if scripts/<subcmd>.sh exists
if [ -n "$SUBCMD" ]; then
  SUBCMD_SCRIPT="$SCRIPT_DIR/${SUBCMD}.sh"
  if [ -x "$SUBCMD_SCRIPT" ]; then
    # Pure passthrough: exec replaces this process
    exec "$SUBCMD_SCRIPT" "$@"
  elif [[ "$SUBCMD" == --* ]]; then
    # Flag intended for run.sh (e.g., --monitor-tags, --agent, --description, --focus)
    # Forward to run.sh as the default action
    RUN_SCRIPT="$SCRIPT_DIR/run.sh"
    if [ -x "$RUN_SCRIPT" ]; then
      exec "$RUN_SCRIPT" "$SUBCMD" "$@"
    else
      echo "ERROR: run.sh not found at $RUN_SCRIPT"
      exit 1
    fi
  else
    echo "ERROR: Unknown command '$SUBCMD'"
    echo ""
    echo "Run 'engine --help' to see available commands."
    exit 1
  fi
fi

# 3. Default (no args): auto-setup if needed, then launch Claude
if [ ! -f "$SETUP_MARKER" ]; then
  echo "First run detected. Running setup..."
  echo ""
  cmd_setup
  echo ""
fi

# Ensure /usr/local/bin/engine symlink exists (lightweight check, every launch)
_relink_engine_bin "$(cd "$(dirname "$SCRIPT_PATH")" && pwd)/$(basename "$SCRIPT_PATH")"

# Launch Claude via run.sh
RUN_SCRIPT="$SCRIPT_DIR/run.sh"
if [ ! -x "$RUN_SCRIPT" ]; then
  echo "ERROR: run.sh not found at $RUN_SCRIPT"
  exit 1
fi

exec "$RUN_SCRIPT" "$@"
