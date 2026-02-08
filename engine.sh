#!/bin/bash
set -euo pipefail

# ============================================================================
# Workflow Engine CLI
# ============================================================================
# Sets up the shared workflow engine for a team member on a specific project.
#
# Usage (from your project root):
#   path/to/engine.sh [project-name]
#
# Everything is inferred automatically:
#   - Email and username: from the script's own GDrive path
#   - Project name: from the argument, or the current directory name
#
# Examples:
#   ~/Library/CloudStorage/GoogleDrive-.../engine/engine.sh        # infers project from cwd
#   ~/Library/CloudStorage/GoogleDrive-.../engine/engine.sh finch  # explicit project name
#
# Prerequisites:
#   - Google Drive desktop app installed and syncing
#   - Access to the finch-os Shared Drive
#
# Related:
#   Docs: (~/.claude/docs/)
#     SETUP_PROTOCOL.md — Complete setup protocol and modes
#   Invariants: (~/.claude/directives/INVARIANTS.md)
#     ¶INV_TEST_SANDBOX_ISOLATION — Test safety requirements
#     ¶INV_INFER_USER_FROM_GDRIVE — Identity detection
# ============================================================================

# ---- Locate GDrive and infer identity from script path or cache ----

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
USER_CACHE="$HOME/.claude/engine/.user.json"

# Extract email from the GDrive mount path (GoogleDrive-user@domain.com)
EMAIL=$(echo "$SCRIPT_DIR" | grep -o 'GoogleDrive-[^/]*' | sed 's/GoogleDrive-//' || true)

# Fall back to cached identity (local mode)
if [ -z "$EMAIL" ] && [ -f "$USER_CACHE" ]; then
  EMAIL=$(jq -r '.email // empty' "$USER_CACHE" 2>/dev/null || true)
fi

if [ -z "$EMAIL" ]; then
  echo "ERROR: Could not infer email from script path or cache."
  echo "Expected script to live under ~/Library/CloudStorage/GoogleDrive-<email>/..."
  echo "Or have a cached identity at $USER_CACHE"
  exit 1
fi

USER_NAME="${EMAIL%%@*}"
PROJECT_NAME="${1:-$(basename "$(pwd)")}"

# Auto-detect engine dir and mode
MODE_FILE="$HOME/.claude/engine/.mode"
LOCAL_ENGINE="$HOME/.claude/engine"

if [ -f "$MODE_FILE" ] && [ "$(cat "$MODE_FILE")" = "local" ]; then
  # Local mode: engine is at ~/.claude/engine, GDrive root found via CloudStorage
  ENGINE_DIR="$LOCAL_ENGINE"
  GDRIVE_ROOT=$(find "$HOME/Library/CloudStorage" -maxdepth 1 -name "GoogleDrive-$EMAIL" -type d 2>/dev/null | head -1)
  if [ -z "$GDRIVE_ROOT" ]; then
    GDRIVE_ROOT="$HOME/Library/CloudStorage/GoogleDrive-$EMAIL"
  fi
  GDRIVE_ROOT="$GDRIVE_ROOT/Shared drives/finch-os"
elif [ -d "$SCRIPT_DIR/commands" ] && [ -d "$SCRIPT_DIR/skills" ]; then
  # Remote mode: engine is where the script lives
  ENGINE_DIR="$SCRIPT_DIR"
  GDRIVE_ROOT="$(dirname "$ENGINE_DIR")"
else
  echo "ERROR: Engine not found. Expected commands/ and skills/ next to this script."
  exit 1
fi

if [ ! -d "$ENGINE_DIR/skills" ]; then
  echo "ERROR: Engine directory not found at: $ENGINE_DIR/skills"
  echo "Make sure the engine/ directory exists on the Shared Drive."
  exit 1
fi

ENGINE_MODE="remote"
if [ -f "$MODE_FILE" ] && [ "$(cat "$MODE_FILE")" = "local" ]; then
  ENGINE_MODE="local"
fi

echo "Setting up workflow engine"
echo "  User:    $USER_NAME ($EMAIL)"
echo "  Project: $PROJECT_NAME"
echo "  Mode:    $ENGINE_MODE"
echo "  Engine:  $ENGINE_DIR"
echo "  GDrive:  $GDRIVE_ROOT"
echo ""

# ---- Step 1: Create GDrive directories ----
SESSION_DIR="$GDRIVE_ROOT/$USER_NAME/$PROJECT_NAME/sessions"
REPORTS_DIR="$GDRIVE_ROOT/$USER_NAME/$PROJECT_NAME/reports"
mkdir -p "$SESSION_DIR" "$REPORTS_DIR"
echo "[1/7] Created GDrive directories:"
echo "  sessions: $SESSION_DIR"
echo "  reports:  $REPORTS_DIR"

# ---- Step 2: User-level shared engine (one-time per machine) ----
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"

link_if_needed() {
  local target="$1"
  local link="$2"
  local name="$3"

  if [ -L "$link" ]; then
    current=$(readlink "$link")
    if [ "$current" = "$target" ]; then
      echo "  $name: already linked"
      return
    else
      echo "  $name: updating link (was: $current)"
      rm "$link"
    fi
  elif [ -d "$link" ]; then
    echo "  WARNING: $link is a real directory, not a symlink."
    echo "  Back it up and remove it to proceed, or skip with Ctrl+C."
    read -rp "  Remove $link and replace with symlink? [y/N] " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
      rm -rf "$link"
    else
      echo "  Skipping $name"
      return
    fi
  fi

  ln -s "$target" "$link"
  echo "  $name: linked -> $target"
}

echo ""
echo "[2/7] Linking shared engine to ~/.claude/"
link_if_needed "$ENGINE_DIR/commands"  "$CLAUDE_DIR/commands"  "commands"
link_if_needed "$ENGINE_DIR/directives" "$CLAUDE_DIR/directives" "directives"
link_if_needed "$ENGINE_DIR/scripts"   "$CLAUDE_DIR/scripts"   "scripts"

# Skills use per-skill symlinks so project overrides can coexist with shared ones.
echo ""
echo "[2b/7] Linking individual skills"
if [ -L "$CLAUDE_DIR/skills" ]; then
  echo "  skills/: removing whole-dir symlink (migrating to per-skill links)"
  rm "$CLAUDE_DIR/skills"
fi
mkdir -p "$CLAUDE_DIR/skills"
for skill_dir in "$ENGINE_DIR/skills"/*/; do
  skill_name="$(basename "$skill_dir")"
  link_if_needed "$skill_dir" "$CLAUDE_DIR/skills/$skill_name" "skills/$skill_name"
done

# Agents use per-agent symlinks (same pattern as skills)
echo ""
echo "[2c/7] Linking individual agents"
if [ -L "$CLAUDE_DIR/agents" ]; then
  echo "  agents/: removing whole-dir symlink (migrating to per-agent links)"
  rm "$CLAUDE_DIR/agents"
fi
mkdir -p "$CLAUDE_DIR/agents"
for agent_file in "$ENGINE_DIR/agents"/*.md; do
  if [ -f "$agent_file" ]; then
    agent_name="$(basename "$agent_file")"
    link_if_needed "$agent_file" "$CLAUDE_DIR/agents/$agent_name" "agents/$agent_name"
  fi
done

# Hooks use per-hook symlinks (same pattern as skills/agents)
echo ""
echo "[2d/7] Linking individual hooks"
if [ -L "$CLAUDE_DIR/hooks" ]; then
  echo "  hooks/: removing whole-dir symlink (migrating to per-hook links)"
  rm "$CLAUDE_DIR/hooks"
fi
mkdir -p "$CLAUDE_DIR/hooks"
for hook_file in "$ENGINE_DIR/hooks"/*.sh; do
  if [ -f "$hook_file" ]; then
    hook_name="$(basename "$hook_file")"
    link_if_needed "$hook_file" "$CLAUDE_DIR/hooks/$hook_name" "hooks/$hook_name"
  fi
done

# Tools require separate handling (they have npm dependencies)
echo ""
echo "[2e/7] Linking tools"
if [ -d "$ENGINE_DIR/tools" ]; then
  link_if_needed "$ENGINE_DIR/tools" "$CLAUDE_DIR/tools" "tools"
else
  echo "  tools/: not found in engine (optional)"
fi

# ---- Step 3: Project-level symlinks (sessions + reports) ----
echo ""
echo "[3/7] Linking project directories"

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

link_project_dir() {
  local target="$1"
  local link="$2"
  local name="$3"

  if [ -L "$link" ]; then
    current=$(readlink "$link")
    if [ "$current" = "$target" ]; then
      echo "  $name/: already linked"
    else
      echo "  $name/: updating link (was: $current)"
      rm "$link"
      ln -s "$target" "$link"
      echo "  $name/: linked -> $target"
    fi
  elif [ -d "$link" ]; then
    echo "  WARNING: $name/ is a real directory with existing data."
    echo "  Move its contents to $target first, then re-run."
    echo "  Skipping $name/ link."
  else
    ln -s "$target" "$link"
    echo "  $name/: linked -> $target"
  fi
}

link_project_dir "$SESSION_DIR" "$PROJECT_ROOT/sessions" "sessions"
link_project_dir "$REPORTS_DIR" "$PROJECT_ROOT/reports" "reports"

# ---- Step 4: Create project directives stub ----
echo ""
echo "[4/7] Project directives"

PROJECT_CLAUDE_DIR="$PROJECT_ROOT/.claude/directives"
PROJECT_INVARIANTS="$PROJECT_CLAUDE_DIR/INVARIANTS.md"
mkdir -p "$PROJECT_CLAUDE_DIR"

if [ -f "$PROJECT_INVARIANTS" ]; then
  echo "  .claude/directives/INVARIANTS.md: already exists"
else
  cat > "$PROJECT_INVARIANTS" << 'STDINV'
# Project Invariants

Project-specific rules that extend the shared engine standards. Every command loads this file automatically after the shared `~/.claude/directives/INVARIANTS.md`.

Add your project's architectural rules, naming conventions, framework-specific constraints, and domain logic invariants here.
STDINV
  echo "  Created .claude/directives/INVARIANTS.md (starter template)"
fi

# ---- Step 5: Update .gitignore ----
echo ""
echo "[5/7] Updating .gitignore"

GITIGNORE="$PROJECT_ROOT/.gitignore"
if [ -f "$GITIGNORE" ]; then
  for entry in "sessions" "reports"; do
    if ! grep -qx "$entry" "$GITIGNORE" && ! grep -qx "$entry/" "$GITIGNORE"; then
      echo "$entry" >> "$GITIGNORE"
      echo "  Added '$entry' to .gitignore"
    else
      echo "  '$entry' already in .gitignore"
    fi
  done
else
  printf 'sessions\nreports\n' > "$GITIGNORE"
  echo "  Created .gitignore with sessions and reports"
fi

# ---- Step 6: Drop README files into sessions and reports ----
echo ""
echo "[6/7] README files"

if [ ! -f "$SESSION_DIR/README.md" ]; then
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
  echo "  Created sessions/README.md"
else
  echo "  sessions/README.md: already exists"
fi

if [ ! -f "$REPORTS_DIR/README.md" ]; then
  cat > "$REPORTS_DIR/README.md" << 'REPREADME'
# Reports

Progress reports generated by `/summarize-progress`. Each report summarizes recent session activity — what shipped, what's in progress, and what's blocked.

Reports are stored on Google Drive and symlinked into each project.
REPREADME
  echo "  Created reports/README.md"
else
  echo "  reports/README.md: already exists"
fi

# ---- Step 7: Configure Claude Code permissions ----
echo ""
echo "[7/7] Configuring permissions"

# --- Global permissions (~/.claude/settings.json) ---
GLOBAL_SETTINGS="$CLAUDE_DIR/settings.json"

# Build the desired configuration (permissions + hooks + statusLine)
read -r -d '' GLOBAL_CONFIG << 'CONFIG' || true
{
  "permissions": {
    "allow": [
      "Read(~/.claude/agents/**)",
      "Read(~/.claude/commands/**)",
      "Read(~/.claude/skills/**)",
      "Read(~/.claude/directives/**)",
      "Glob(~/.claude/**)",
      "Grep(~/.claude/**)",
      "Bash(~/.claude/scripts/*)",
      "Bash(~/.claude/tools/session-search/session-search.sh *)",
      "Bash(~/.claude/tools/doc-search/doc-search.sh *)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/pre-tool-use-overflow.sh",
            "timeout": 5
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "~/.claude/tools/statusline.sh"
  }
}
CONFIG

if command -v jq &> /dev/null; then
  # jq available — merge cleanly
  if [ -f "$GLOBAL_SETTINGS" ] && [ -s "$GLOBAL_SETTINGS" ]; then
    EXISTING=$(cat "$GLOBAL_SETTINGS")
    # Merge permissions (dedupe), and set hooks + statusLine
    MERGED=$(echo "$EXISTING" | jq --argjson new "$GLOBAL_CONFIG" '
      .permissions.allow = ((.permissions.allow // []) + $new.permissions.allow | unique) |
      .hooks = $new.hooks |
      .statusLine = $new.statusLine
    ')
    echo "$MERGED" > "$GLOBAL_SETTINGS"
    echo "  ~/.claude/settings.json: merged permissions, hooks, statusLine"
  else
    echo "$GLOBAL_CONFIG" > "$GLOBAL_SETTINGS"
    echo "  ~/.claude/settings.json: created with permissions, hooks, statusLine"
  fi
else
  # No jq — write only if empty or missing
  if [ ! -f "$GLOBAL_SETTINGS" ] || [ "$(cat "$GLOBAL_SETTINGS" 2>/dev/null)" = "{}" ]; then
    echo "$GLOBAL_CONFIG" > "$GLOBAL_SETTINGS"
    echo "  ~/.claude/settings.json: created with permissions, hooks, statusLine"
  else
    echo "  WARNING: ~/.claude/settings.json already has content and jq is not installed."
    echo "  Install jq (brew install jq) and re-run setup to configure hooks."
  fi
fi

# --- Project permissions (.claude/settings.json) ---
# Auto-allow reading sessions and reports, plus bash append for logging
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
      "Glob(reports/**)",
      "Bash(printf * | tee -a sessions/*)",
      "Bash(printf * | tee -a reports/*)"
    ]
  }
}
PERMS

if command -v jq &> /dev/null; then
  if [ -f "$PROJECT_SETTINGS" ] && [ -s "$PROJECT_SETTINGS" ]; then
    EXISTING=$(cat "$PROJECT_SETTINGS")
    MERGED=$(echo "$EXISTING" | jq --argjson new "$PROJECT_PERMISSIONS" '
      .permissions.allow = ((.permissions.allow // []) + $new.permissions.allow | unique)
    ')
    echo "$MERGED" > "$PROJECT_SETTINGS"
    echo "  .claude/settings.json: merged session/report permissions"
  else
    echo "$PROJECT_PERMISSIONS" > "$PROJECT_SETTINGS"
    echo "  .claude/settings.json: created with session/report permissions"
  fi
else
  if [ ! -f "$PROJECT_SETTINGS" ] || [ "$(cat "$PROJECT_SETTINGS" 2>/dev/null)" = "{}" ] || [ ! -s "$PROJECT_SETTINGS" ]; then
    echo "$PROJECT_PERMISSIONS" > "$PROJECT_SETTINGS"
    echo "  .claude/settings.json: created with session/report permissions"
  else
    echo "  WARNING: .claude/settings.json already has content and jq is not installed."
    echo "  Add these manually to permissions.allow:"
    echo '    "Read(sessions/**)", "Read(reports/**)",'
    echo '    "Grep(sessions/**)", "Grep(reports/**)",'
    echo '    "Glob(sessions/**)", "Glob(reports/**)",'
    echo '    "Bash(printf * | tee -a sessions/*)", "Bash(printf * | tee -a reports/*)"'
  fi
fi

# ---- Check optional dependencies ----
echo ""
echo "[*] Checking dependencies"
if command -v fswatch &> /dev/null; then
  echo "  fswatch: installed"
else
  echo "  WARNING: fswatch not found. Install it for await-tag support:"
  echo "    brew install fswatch"
fi

echo ""
echo "Setup complete!"
echo ""
echo "  Engine:    ~/.claude/{commands,skills,directives,scripts,agents,hooks}"
echo "  Sessions:  ./sessions -> $SESSION_DIR"
echo "  Reports:   ./reports -> $REPORTS_DIR"
echo ""
echo "Context overflow protection is enabled:"
echo "  - Status line shows [skill] XX% usage"
echo "  - PreToolUse hook blocks at ~72% (90% of Claude's 80% auto-compact) and prompts /dehydrate"
echo "  - /dehydrate saves state and restarts with fresh context"
echo ""
echo "You now have ~25 skills + 4 light commands. The main workflow is:"
echo "  /analyze -> /brainstorm -> /document -> /implement -> /test"
echo ""
echo "Use /dehydrate to pause a session (copies to clipboard)."
echo "Paste the result into the next command to resume: /implement <paste>"
echo ""
open "$ENGINE_DIR/README.md"
echo "Test it:   run '/brainstorm test topic' in Claude Code"
