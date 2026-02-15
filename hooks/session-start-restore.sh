#!/bin/bash
# SessionStart hook: Restore dehydrated context after context overflow restart
#
# Fires on Claude start. Scans sessions/ for a .state.json with dehydratedContext,
# reads required files, injects as additionalContext, then clears the field.
#
# Input (stdin): {"hook_event_name":"SessionStart","source":"startup|resume|clear|compact",...}
# Output (stdout): Plain text injected as Claude's additional context
#
# Fires on all sources (startup, resume, clear, compact).
# Standards are preloaded on every fire. Dehydration restore is startup-only.

set -euo pipefail

# Debug logging
DEBUG_LOG="/tmp/hooks-debug.log"
debug() {
  if [ "${HOOK_DEBUG:-}" = "1" ] || [ -f /tmp/hooks-debug-enabled ]; then
    echo "[$(date +%H:%M:%S)] [session-start] $*" >> "$DEBUG_LOG"
  fi
}

# Read hook input
INPUT=$(cat)
debug "fired: source=$(echo "$INPUT" | jq -r '.source // "?"')"

# Parse source for dehydration guard (dehydration is startup-only)
SOURCE=$(echo "$INPUT" | jq -r '.source // "unknown"' 2>/dev/null)

# Find sessions directories (project root cwd from hook input)
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
if [ -z "$CWD" ]; then
  exit 0
fi

# Build list of session directories to scan (workspace first, then global)
SESSION_DIRS=()
if [ -n "${WORKSPACE:-}" ] && [ -d "$CWD/$WORKSPACE/sessions" ]; then
  SESSION_DIRS+=("$CWD/$WORKSPACE/sessions")
fi
if [ -d "$CWD/sessions" ]; then
  SESSION_DIRS+=("$CWD/sessions")
fi

if [ ${#SESSION_DIRS[@]} -eq 0 ]; then
  exit 0
fi

# Source lib.sh for safe_json_write, pid_exists
source "$HOME/.claude/scripts/lib.sh"

# --- Session Context Block (fires on every source) ---
# Gather ambient context: time, active session, skill, phase, heartbeat
SESSION_CONTEXT_LINE=""
ACTIVE_SESSION=""
ACTIVE_SKILL=""
ACTIVE_PHASE=""
ACTIVE_HEARTBEAT=""

# Find active session: .state.json with lifecycle=active and live PID
for sessions_dir in "${SESSION_DIRS[@]}"; do
  for f in "$sessions_dir"/*/.state.json; do
    [ -f "$f" ] || continue
    S_LIFECYCLE=$(jq -r '.lifecycle // ""' "$f" 2>/dev/null)
    S_PID=$(jq -r '.pid // 0' "$f" 2>/dev/null)
    if [ "$S_LIFECYCLE" = "active" ] && pid_exists "$S_PID"; then
      ACTIVE_SESSION=$(basename "$(dirname "$f")")
      ACTIVE_SKILL=$(jq -r '.skill // "unknown"' "$f" 2>/dev/null)
      ACTIVE_PHASE=$(jq -r '.currentPhase // "unknown"' "$f" 2>/dev/null)
      S_HEARTBEAT=$(jq -r '.toolCallsSinceLastLog // 0' "$f" 2>/dev/null)
      S_HEARTBEAT_MAX=$(jq -r '.toolUseWithoutLogsBlockAfter // 10' "$f" 2>/dev/null)
      ACTIVE_HEARTBEAT="${S_HEARTBEAT}/${S_HEARTBEAT_MAX}"
      break 2
    fi
  done
done

CONTEXT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
WORKSPACE_INFO=""
if [ -n "${WORKSPACE:-}" ]; then
  WORKSPACE_INFO=" | Workspace: $WORKSPACE"
fi
if [ -n "$ACTIVE_SESSION" ]; then
  SESSION_CONTEXT_LINE="[Session Context] Time: $CONTEXT_TIME${WORKSPACE_INFO} | Session: $ACTIVE_SESSION | Skill: $ACTIVE_SKILL | Phase: $ACTIVE_PHASE | Heartbeat: $ACTIVE_HEARTBEAT"
else
  SESSION_CONTEXT_LINE="[Session Context] Time: $CONTEXT_TIME${WORKSPACE_INFO} | Session: (none)"
fi
debug "session context: $SESSION_CONTEXT_LINE"

# Clear stale preload state on every fresh startup — these track what was injected into
# the PREVIOUS context window. A new Claude process = new context = must re-inject.
# Clears: preloadedFiles (re-seeds standards), touchedDirs, pendingPreloads, pendingAllowInjections.
debug "clearing preload state for fresh context"
for sessions_dir in "${SESSION_DIRS[@]}"; do
  for f in "$sessions_dir"/*/.state.json; do
    [ -f "$f" ] || continue
    debug "  clearing preload state in $(basename "$(dirname "$f")")"
    jq --argjson stds '["~/.claude/.directives/COMMANDS.md","~/.claude/.directives/INVARIANTS.md","~/.claude/.directives/SIGILS.md","~/.claude/.directives/commands/CMD_DEHYDRATE.md","~/.claude/.directives/commands/CMD_RESUME_SESSION.md","~/.claude/.directives/commands/CMD_PARSE_PARAMETERS.md"]' \
      '.preloadedFiles = $stds | .touchedDirs = {} | .pendingPreloads = [] | .pendingAllowInjections = []' "$f" | safe_json_write "$f"
  done
done

# Preload core standards — available to agent from first message
STANDARDS_OUTPUT=""
for std_file in "$HOME/.claude/.directives/COMMANDS.md" \
                "$HOME/.claude/.directives/INVARIANTS.md" \
                "$HOME/.claude/.directives/SIGILS.md" \
                "$HOME/.claude/.directives/commands/CMD_DEHYDRATE.md" \
                "$HOME/.claude/.directives/commands/CMD_RESUME_SESSION.md" \
                "$HOME/.claude/.directives/commands/CMD_PARSE_PARAMETERS.md"; do
  if [ -f "$std_file" ]; then
    STD_CONTENT=$(cat "$std_file" 2>/dev/null || true)
    if [ -n "$STD_CONTENT" ]; then
      STANDARDS_OUTPUT="${STANDARDS_OUTPUT}[Preloaded: $std_file]
$STD_CONTENT

"
      debug "  preloaded standard: $(basename "$std_file")"
    fi
  else
    debug "  standard missing (skipped): $std_file"
  fi
done

# Prepend session context line to standards output (fires on every source)
STANDARDS_OUTPUT="${SESSION_CONTEXT_LINE}
${STANDARDS_OUTPUT}"

# Dehydrated context restore — startup only (other sources: user didn't restart)
if [ "$SOURCE" != "startup" ]; then
  debug "$SOURCE source — preloading standards only, skipping dehydration"
  echo "$STANDARDS_OUTPUT"
  exit 0
fi

# Scan for .state.json with dehydratedContext
# Use find through the symlink (sessions/ may be symlinked)
STATE_FILE=""
for sessions_dir in "${SESSION_DIRS[@]}"; do
  [ -n "$STATE_FILE" ] && break
  for f in "$sessions_dir"/*/.state.json; do
    [ -f "$f" ] || continue
    HAS_CTX=$(jq -r '.dehydratedContext // null | type' "$f" 2>/dev/null)
    if [ "$HAS_CTX" = "object" ]; then
      STATE_FILE="$f"
      break 2
    fi
  done
done

if [ -z "$STATE_FILE" ]; then
  # No dehydrated context found — still output standards if present
  debug "no dehydrated context found"
  if [ -n "$STANDARDS_OUTPUT" ]; then
    echo "$STANDARDS_OUTPUT"
  fi
  exit 0
fi

SESSION_DIR=$(dirname "$STATE_FILE")
SESSION_NAME=$(basename "$SESSION_DIR")

# Extract dehydrated context fields
SUMMARY=$(jq -r '.dehydratedContext.summary // "No summary"' "$STATE_FILE")
LAST_ACTION=$(jq -r '.dehydratedContext.lastAction // "Unknown"' "$STATE_FILE")
NEXT_STEPS=$(jq -r '.dehydratedContext.nextSteps // [] | join("\n- ")' "$STATE_FILE")
HANDOVER=$(jq -r '.dehydratedContext.handoverInstructions // ""' "$STATE_FILE")
USER_HISTORY=$(jq -r '.dehydratedContext.userHistory // ""' "$STATE_FILE")
SKILL=$(jq -r '.skill // "unknown"' "$STATE_FILE")
PHASE=$(jq -r '.currentPhase // "unknown"' "$STATE_FILE")

# Build the context string
CONTEXT="## Session Recovery (Dehydrated Context)

**Session**: $SESSION_NAME
**Skill**: $SKILL
**Phase**: $PHASE

### Summary
$SUMMARY

### Last Action
$LAST_ACTION

### Next Steps
- $NEXT_STEPS

### Handover Instructions
$HANDOVER"

if [ -n "$USER_HISTORY" ]; then
  CONTEXT="$CONTEXT

### User Interaction History
$USER_HISTORY"
fi

# Read required files and append their contents
REQUIRED_FILES=$(jq -r '.dehydratedContext.requiredFiles // [] | .[]' "$STATE_FILE" 2>/dev/null)
if [ -n "$REQUIRED_FILES" ]; then
  CONTEXT="$CONTEXT

### Required Files (Auto-Loaded)"

  while IFS= read -r filepath; do
    [ -z "$filepath" ] && continue

    # Resolve path prefixes
    resolved="$filepath"
    case "$filepath" in
      "~/.claude/"*) resolved="$HOME/.claude/${filepath#\~/.claude/}" ;;
      "~/"*) resolved="$HOME/${filepath#\~/}" ;;
      "sessions/"*|"packages/"*|"apps/"*|"src/"*|".claude/"*) resolved="$CWD/$filepath" ;;
    esac

    if [ -f "$resolved" ]; then
      FILE_CONTENT=$(head -c 50000 "$resolved" 2>/dev/null || echo "[Error reading file]")
      CONTEXT="$CONTEXT

---
#### File: $filepath
\`\`\`
$FILE_CONTENT
\`\`\`"
    else
      CONTEXT="$CONTEXT

---
#### File: $filepath
[MISSING — file not found at $resolved]"
    fi
  done <<< "$REQUIRED_FILES"
fi

# Clear dehydratedContext from .state.json (consumed)
jq 'del(.dehydratedContext)' "$STATE_FILE" | safe_json_write "$STATE_FILE"

# Output the context — Claude Code will inject this as additionalContext
# Standards first, then dehydrated context
echo "${STANDARDS_OUTPUT}${CONTEXT}"
