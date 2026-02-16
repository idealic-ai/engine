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

# Find active session — fleet pane match first, then PID fallback.
# In fleet mode (TMUX_PANE set), match fleetPaneId in .state.json against
# the current pane's window:label from tmux. Falls back to first alive PID.
FLEET_LABEL=""
if [ -n "${TMUX_PANE:-}" ]; then
  FLEET_LABEL=$(tmux display -p -t "$TMUX_PANE" '#{window_name}:#{@pane_label}' 2>/dev/null || echo "")
  debug "fleet label: '$FLEET_LABEL'"
fi

# Helper: extract session fields from .state.json into ACTIVE_* vars
_set_active_session() {
  local f="$1"
  ACTIVE_SESSION=$(basename "$(dirname "$f")")
  ACTIVE_SKILL=$(jq -r '.skill // "unknown"' "$f" 2>/dev/null)
  ACTIVE_PHASE=$(jq -r '.currentPhase // "unknown"' "$f" 2>/dev/null)
  S_HEARTBEAT=$(jq -r '.toolCallsSinceLastLog // 0' "$f" 2>/dev/null)
  S_HEARTBEAT_MAX=$(jq -r '.toolUseWithoutLogsBlockAfter // 10' "$f" 2>/dev/null)
  ACTIVE_HEARTBEAT="${S_HEARTBEAT}/${S_HEARTBEAT_MAX}"
}

# Pass 1: Fleet pane match (if in tmux)
if [ -n "$FLEET_LABEL" ]; then
  for sessions_dir in "${SESSION_DIRS[@]}"; do
    for f in "$sessions_dir"/*/.state.json; do
      [ -f "$f" ] || continue
      S_LIFECYCLE=$(jq -r '.lifecycle // ""' "$f" 2>/dev/null)
      { [ "$S_LIFECYCLE" = "active" ] || [ "$S_LIFECYCLE" = "resuming" ]; } || continue
      S_FLEET=$(jq -r '.fleetPaneId // ""' "$f" 2>/dev/null)
      # Match: fleetPaneId ends with the current pane's window:label
      if [ -n "$S_FLEET" ] && [[ "$S_FLEET" == *"$FLEET_LABEL" ]]; then
        _set_active_session "$f"
        debug "fleet match: $ACTIVE_SESSION (paneId=$S_FLEET)"
        break 2
      fi
    done
  done
fi

# Pass 2: PID fallback (if no fleet match found)
if [ -z "$ACTIVE_SESSION" ]; then
  for sessions_dir in "${SESSION_DIRS[@]}"; do
    for f in "$sessions_dir"/*/.state.json; do
      [ -f "$f" ] || continue
      S_LIFECYCLE=$(jq -r '.lifecycle // ""' "$f" 2>/dev/null)
      S_PID=$(jq -r '.pid // 0' "$f" 2>/dev/null)
      if { [ "$S_LIFECYCLE" = "active" ] || [ "$S_LIFECYCLE" = "resuming" ]; } && pid_exists "$S_PID"; then
        _set_active_session "$f"
        debug "pid match: $ACTIVE_SESSION (pid=$S_PID)"
        break 2
      fi
    done
  done
fi

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
PRELOAD_SEEDS=$(get_session_start_seeds)
for sessions_dir in "${SESSION_DIRS[@]}"; do
  for f in "$sessions_dir"/*/.state.json; do
    [ -f "$f" ] || continue
    debug "  clearing preload state in $(basename "$(dirname "$f")")"
    jq --argjson stds "$PRELOAD_SEEDS" \
      '.preloadedFiles = $stds | .touchedDirs = {} | .pendingPreloads = [] | .pendingAllowInjections = []' "$f" | safe_json_write "$f"
  done

  # Clean stale seed files (dead PIDs) and create fresh seed for this process
  SEEDS_DIR="$sessions_dir/.seeds"
  if [ -d "$SEEDS_DIR" ]; then
    for seed_file in "$SEEDS_DIR"/*.json; do
      [ -f "$seed_file" ] || continue
      SEED_PID=$(jq -r '.pid // 0' "$seed_file" 2>/dev/null || echo "0")
      if [ "$SEED_PID" != "0" ] && ! pid_exists "$SEED_PID"; then
        debug "  cleaning stale seed: $(basename "$seed_file") (PID $SEED_PID dead)"
        rm -f "$seed_file"
      fi
    done
  fi

  # Create fresh seed for this Claude process
  mkdir -p "$sessions_dir/.seeds"
  SEED_FILE="$sessions_dir/.seeds/$PPID.json"
  jq -n --argjson pid "$PPID" --argjson seeds "$PRELOAD_SEEDS" '{
    pid: $pid,
    lifecycle: "seeding",
    preloadedFiles: $seeds,
    pendingPreloads: [],
    touchedDirs: {}
  }' > "$SEED_FILE"
  _log_delivery "session-start" "seed" "$SEED_FILE" "create-seed(pid=$PPID)"
  debug "  created seed: $SEED_FILE"
done

# --- Active skill dep delivery (when active session detected) ---
# After /clear, the agent needs SKILL.md + Phase 0 CMDs + templates immediately.
# Without this, they only arrive on the next PostToolUse (templates hook), which
# requires a tool call — leaving the agent without skill context after /clear.
SKILL_DEPS_OUTPUT=""
if [ -n "$ACTIVE_SKILL" ]; then
  debug "active skill detected: $ACTIVE_SKILL — delivering skill deps"

  # SKILL.md
  skill_md="$HOME/.claude/skills/$ACTIVE_SKILL/SKILL.md"
  if [ -f "$skill_md" ]; then
    skill_md_content=$(cat "$skill_md" 2>/dev/null || true)
    if [ -n "$skill_md_content" ]; then
      SKILL_DEPS_OUTPUT="[Preloaded: $skill_md]
$skill_md_content

"
      debug "  delivered SKILL.md"
    fi
  fi

  # Phase 0 CMDs + templates (via extract_skill_preloads), deduped against boot standards
  phase0_paths=$(extract_skill_preloads "$ACTIVE_SKILL" 2>/dev/null || true)
  if [ -n "$phase0_paths" ]; then
    while IFS= read -r dep_path; do
      [ -n "$dep_path" ] || continue
      resolved="${dep_path/#\~/$HOME}"
      # Skip if already delivered as a boot standard
      resolved_real=$(cd "$(dirname "$resolved")" 2>/dev/null && echo "$(pwd -P)/$(basename "$resolved")")
      if echo "$PRELOAD_SEEDS" | jq -e --arg p "$resolved_real" 'index($p) != null' >/dev/null 2>&1; then
        debug "  skip dedup: $(basename "$resolved") (boot standard)"
        continue
      fi
      if [ -f "$resolved" ]; then
        dep_content=$(cat "$resolved" 2>/dev/null || true)
        if [ -n "$dep_content" ]; then
          SKILL_DEPS_OUTPUT="${SKILL_DEPS_OUTPUT}[Preloaded: $dep_path]
$dep_content

"
          debug "  delivered Phase 0 dep: $(basename "$resolved")"
        fi
      fi
    done <<< "$phase0_paths"
  fi

  # Track skill deps in seed preloadedFiles
  if [ -n "$SKILL_DEPS_OUTPUT" ]; then
    # Build JSON array of delivered skill dep paths
    SKILL_DEP_PATHS=""
    skill_md_norm=$(normalize_preload_path "$skill_md" 2>/dev/null || true)
    [ -n "$skill_md_norm" ] && SKILL_DEP_PATHS="$skill_md_norm"
    if [ -n "$phase0_paths" ]; then
      while IFS= read -r dep_path; do
        [ -n "$dep_path" ] || continue
        SKILL_DEP_PATHS="${SKILL_DEP_PATHS}${SKILL_DEP_PATHS:+
}$dep_path"
      done <<< "$phase0_paths"
    fi

    # Update seed files with skill dep paths
    for sessions_dir in "${SESSION_DIRS[@]}"; do
      SEED_FILE="$sessions_dir/.seeds/$PPID.json"
      if [ -f "$SEED_FILE" ]; then
        # Add each path to preloadedFiles
        while IFS= read -r add_path; do
          [ -n "$add_path" ] || continue
          jq --arg p "$add_path" '
            (.preloadedFiles //= []) |
            if (.preloadedFiles | index($p)) then .
            else .preloadedFiles += [$p]
            end
          ' "$SEED_FILE" | safe_json_write "$SEED_FILE"
        done <<< "$SKILL_DEP_PATHS"
        debug "  updated seed with $(echo "$SKILL_DEP_PATHS" | wc -l | tr -d ' ') skill dep paths"
      fi
    done
  fi
fi

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

# Prepend session context line, append skill deps after standards
STANDARDS_OUTPUT="${SESSION_CONTEXT_LINE}
${STANDARDS_OUTPUT}${SKILL_DEPS_OUTPUT}"

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
