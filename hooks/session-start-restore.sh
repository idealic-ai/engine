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
  ACTIVE_SESSION_DIR=$(dirname "$f")
  ACTIVE_SKILL=$(jq -r '.skill // "unknown"' "$f" 2>/dev/null)
  ACTIVE_PHASE=$(jq -r '.currentPhase // "unknown"' "$f" 2>/dev/null)
  S_HEARTBEAT=$(jq -r '.toolCallsSinceLastLog // 0' "$f" 2>/dev/null)
  S_HEARTBEAT_MAX=$(jq -r '.toolUseWithoutLogsBlockAfter // 10' "$f" 2>/dev/null)
  ACTIVE_HEARTBEAT="${S_HEARTBEAT}/${S_HEARTBEAT_MAX}"
}

# Single-pass scan: extract lifecycle + fleetPaneId + pid + dehydratedContext in one jq call per file.
# Checks fleet match first, then PID fallback. Also notes dehydratedContext for later use.
# Replaces the former 3-pass approach (fleet, PID, dehydration — each with separate jq calls).
DEHYDRATED_STATE_FILE=""
for sessions_dir in "${SESSION_DIRS[@]}"; do
  for f in "$sessions_dir"/*/.state.json; do
    [ -f "$f" ] || continue
    # Single jq call extracts all needed fields
    S_JSON=$(jq -r '[.lifecycle // "", .fleetPaneId // "", (.pid // 0 | tostring), (.dehydratedContext // null | type)]
      | join("\t")' "$f" 2>/dev/null) || continue
    S_LIFECYCLE=$(echo "$S_JSON" | cut -f1)
    S_FLEET=$(echo "$S_JSON" | cut -f2)
    S_PID=$(echo "$S_JSON" | cut -f3)
    S_DEHY_TYPE=$(echo "$S_JSON" | cut -f4)

    # Note dehydrated context (for startup restore later)
    if [ "$S_DEHY_TYPE" = "object" ] && [ -z "$DEHYDRATED_STATE_FILE" ]; then
      DEHYDRATED_STATE_FILE="$f"
    fi

    # Only match active/resuming sessions
    { [ "$S_LIFECYCLE" = "active" ] || [ "$S_LIFECYCLE" = "resuming" ]; } || continue

    # Fleet match (if in tmux)
    if [ -n "$FLEET_LABEL" ] && [ -n "$S_FLEET" ] && [[ "$S_FLEET" == *"$FLEET_LABEL" ]]; then
      _set_active_session "$f"
      debug "fleet match: $ACTIVE_SESSION (paneId=$S_FLEET)"
      break 2
    fi

    # PID fallback (if no fleet match yet)
    if [ -z "$ACTIVE_SESSION" ] && [ "$S_PID" != "0" ] && pid_exists "$S_PID"; then
      _set_active_session "$f"
      debug "pid match: $ACTIVE_SESSION (pid=$S_PID)"
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

# Clear stale preload state for the active session only — these track what was injected
# into the PREVIOUS context window. A new Claude process = new context = must re-inject.
# Only the active session matters; dead sessions' state is never read by PostToolUse hooks.
debug "clearing preload state for fresh context"
PRELOAD_SEEDS=$(get_session_start_seeds)
if [ -n "${ACTIVE_SESSION_DIR:-}" ] && [ -f "$ACTIVE_SESSION_DIR/.state.json" ]; then
  debug "  clearing preload state in $ACTIVE_SESSION (active)"
  jq --argjson stds "$PRELOAD_SEEDS" \
    '.preloadedFiles = $stds | .touchedDirs = {} | .pendingPreloads = [] | .pendingAllowInjections = []' \
    "$ACTIVE_SESSION_DIR/.state.json" | safe_json_write "$ACTIVE_SESSION_DIR/.state.json"
fi

for sessions_dir in "${SESSION_DIRS[@]}"; do
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

      # Collect all dep paths: prose refs + current-phase CMDs + templates
      # Deduplicate before delivery to prevent dupes (e.g., CMD_REPORT_INTENT in both)
      ALL_DEP_PATHS=""
      SEEN_DEPS=""

      # 1. Prose refs from SKILL.md (orchestrator CMDs, FMTs, INVs outside code fences)
      skill_prose_refs=$(resolve_refs "$skill_md" 1 "$PRELOAD_SEEDS" 2>/dev/null || true)
      if [ -n "$skill_prose_refs" ]; then
        while IFS= read -r ref_path; do
          [ -n "$ref_path" ] || continue
          case "$SEEN_DEPS" in *"|$ref_path|"*) continue ;; esac
          SEEN_DEPS="${SEEN_DEPS}|${ref_path}|"
          ALL_DEP_PATHS="${ALL_DEP_PATHS}${ALL_DEP_PATHS:+
}$ref_path"
        done <<< "$skill_prose_refs"
      fi

      # 2. Current phase CMDs + templates (phase-aware)
      PHASE_LABEL=$(echo "$ACTIVE_PHASE" | sed 's/:.*//' | tr -d ' ')
      debug "  phase label: '$PHASE_LABEL'"
      phase_paths=$(resolve_phase_cmds "$ACTIVE_SKILL" "$PHASE_LABEL" 2>/dev/null || true)
      if [ -n "$phase_paths" ]; then
        while IFS= read -r dep_path; do
          [ -n "$dep_path" ] || continue
          # Normalize for dedup comparison
          local_norm=$(normalize_preload_path "${dep_path/#\~/$HOME}" 2>/dev/null || echo "$dep_path")
          case "$SEEN_DEPS" in *"|$local_norm|"*) debug "  skip dedup: $(basename "$dep_path") (already in prose refs)"; continue ;; esac
          SEEN_DEPS="${SEEN_DEPS}|${local_norm}|"
          ALL_DEP_PATHS="${ALL_DEP_PATHS}${ALL_DEP_PATHS:+
}$dep_path"
        done <<< "$phase_paths"
      fi

      # Deliver all unique deps, deduped against boot standards
      if [ -n "$ALL_DEP_PATHS" ]; then
        while IFS= read -r dep_path; do
          [ -n "$dep_path" ] || continue
          resolved="${dep_path/#\~/$HOME}"
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
              debug "  delivered dep: $(basename "$resolved")"
            fi
          fi
        done <<< "$ALL_DEP_PATHS"
      fi
    fi
  fi

  # Track skill deps in seed preloadedFiles
  if [ -n "$SKILL_DEPS_OUTPUT" ]; then
    # Build list of delivered skill dep paths (SKILL.md + all unique deps)
    SKILL_DEP_PATHS=""
    skill_md_norm=$(normalize_preload_path "$skill_md" 2>/dev/null || true)
    [ -n "$skill_md_norm" ] && SKILL_DEP_PATHS="$skill_md_norm"
    if [ -n "${ALL_DEP_PATHS:-}" ]; then
      SKILL_DEP_PATHS="${SKILL_DEP_PATHS}${SKILL_DEP_PATHS:+
}${ALL_DEP_PATHS}"
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

# --- Session artifact delivery (debrief or log fallback) ---
# After /clear or restart, preload the session's debrief (or log as fallback)
# so the agent has full context about what happened in this session.
ARTIFACT_OUTPUT=""
if [ -n "$ACTIVE_SKILL" ] && [ -n "${ACTIVE_SESSION_DIR:-}" ] && [ -f "${skill_md:-}" ]; then
  debug "checking session artifacts in $ACTIVE_SESSION_DIR"

  # Extract debrief and log filenames from SKILL.md JSON block
  # debriefTemplate: "assets/TEMPLATE_IMPLEMENTATION.md" → IMPLEMENTATION.md
  # logTemplate: "assets/TEMPLATE_IMPLEMENTATION_LOG.md" → IMPLEMENTATION_LOG.md
  SKILL_JSON=$(sed -n '/^```json$/,/^```$/p' "$skill_md" 2>/dev/null | sed '1d;$d' || true)
  DEBRIEF_TEMPLATE=$(echo "$SKILL_JSON" | jq -r '.debriefTemplate // ""' 2>/dev/null || true)
  LOG_TEMPLATE=$(echo "$SKILL_JSON" | jq -r '.logTemplate // ""' 2>/dev/null || true)

  DEBRIEF_NAME=""
  LOG_NAME=""
  if [ -n "$DEBRIEF_TEMPLATE" ]; then
    DEBRIEF_NAME=$(basename "$DEBRIEF_TEMPLATE" | sed 's/^TEMPLATE_//')
  fi
  if [ -n "$LOG_TEMPLATE" ]; then
    LOG_NAME=$(basename "$LOG_TEMPLATE" | sed 's/^TEMPLATE_//')
  fi

  debug "  debrief=$DEBRIEF_NAME log=$LOG_NAME"

  ARTIFACT_PATH=""
  if [ -n "$DEBRIEF_NAME" ] && [ -f "$ACTIVE_SESSION_DIR/$DEBRIEF_NAME" ]; then
    ARTIFACT_PATH="$ACTIVE_SESSION_DIR/$DEBRIEF_NAME"
    debug "  found debrief: $DEBRIEF_NAME"
  elif [ -n "$LOG_NAME" ] && [ -f "$ACTIVE_SESSION_DIR/$LOG_NAME" ]; then
    ARTIFACT_PATH="$ACTIVE_SESSION_DIR/$LOG_NAME"
    debug "  no debrief, using log fallback: $LOG_NAME"
  fi

  # Collect artifact paths to preload (debrief or log, plus DIALOGUE.md)
  ARTIFACT_PATHS=""
  if [ -n "$ARTIFACT_PATH" ]; then
    ARTIFACT_PATHS="$ARTIFACT_PATH"
  fi
  # Always include DIALOGUE.md if it exists (interrogation context)
  if [ -f "$ACTIVE_SESSION_DIR/DIALOGUE.md" ]; then
    ARTIFACT_PATHS="${ARTIFACT_PATHS}${ARTIFACT_PATHS:+
}$ACTIVE_SESSION_DIR/DIALOGUE.md"
  fi

  if [ -n "$ARTIFACT_PATHS" ]; then
    while IFS= read -r art_path; do
      [ -n "$art_path" ] || continue
      # Smart truncation for DIALOGUE.md — last ~100 lines, aligned to entry boundary
      if [[ "$(basename "$art_path")" == "DIALOGUE.md" ]]; then
        TOTAL_LINES=$(wc -l < "$art_path" 2>/dev/null || echo "0")
        TOTAL_LINES=$(echo "$TOTAL_LINES" | tr -d ' ')
        if [ "$TOTAL_LINES" -gt 100 ]; then
          # Find the nearest ## heading at or after the 100-lines-from-end mark
          START_LINE=$((TOTAL_LINES - 100))
          # Search forward from START_LINE for the next ## heading to avoid cutting mid-entry
          HEADING_LINE=$(tail -n +"$START_LINE" "$art_path" 2>/dev/null | grep -n '^## ' | head -n 1 | cut -d: -f1 || echo "")
          if [ -n "$HEADING_LINE" ]; then
            ACTUAL_START=$((START_LINE + HEADING_LINE - 1))
            ART_CONTENT=$(tail -n +"$ACTUAL_START" "$art_path" 2>/dev/null || true)
          else
            ART_CONTENT=$(tail -n 100 "$art_path" 2>/dev/null || true)
          fi
        else
          ART_CONTENT=$(cat "$art_path" 2>/dev/null || true)
        fi
      else
        ART_CONTENT=$(cat "$art_path" 2>/dev/null || true)
      fi
      if [ -n "$ART_CONTENT" ]; then
        ARTIFACT_OUTPUT="${ARTIFACT_OUTPUT}[Preloaded: $art_path]
$ART_CONTENT

"
        debug "  preloaded session artifact: $(basename "$art_path")"

        # Track in seed preloadedFiles
        ART_NORM=$(normalize_preload_path "$art_path" 2>/dev/null || echo "$art_path")
        for sessions_dir in "${SESSION_DIRS[@]}"; do
          SEED_FILE="$sessions_dir/.seeds/$PPID.json"
          if [ -f "$SEED_FILE" ]; then
            jq --arg p "$ART_NORM" '
              (.preloadedFiles //= []) |
              if (.preloadedFiles | index($p)) then .
              else .preloadedFiles += [$p]
              end
            ' "$SEED_FILE" | safe_json_write "$SEED_FILE"
          fi
        done
      fi
    done <<< "$ARTIFACT_PATHS"
  fi

  # Session directory listing — agent can see what artifacts exist
  SESSION_DIR_LISTING=""
  if [ -d "$ACTIVE_SESSION_DIR" ]; then
    FILE_LIST=$(ls -1 "$ACTIVE_SESSION_DIR" 2>/dev/null | grep -v '^\.' || true)
    if [ -n "$FILE_LIST" ]; then
      SESSION_DIR_LISTING="[Session Files: $ACTIVE_SESSION_DIR]
$FILE_LIST

"
      debug "  session dir listing: $(echo "$FILE_LIST" | wc -l | tr -d ' ') files"
    fi
  fi
  ARTIFACT_OUTPUT="${ARTIFACT_OUTPUT}${SESSION_DIR_LISTING}"
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

# Prepend session context line, append skill deps + session artifact after standards
STANDARDS_OUTPUT="${SESSION_CONTEXT_LINE}
${STANDARDS_OUTPUT}${SKILL_DEPS_OUTPUT}${ARTIFACT_OUTPUT}"

# Dehydrated context restore — startup only (other sources: user didn't restart)
if [ "$SOURCE" != "startup" ]; then
  debug "$SOURCE source — preloading standards only, skipping dehydration"
  echo "$STANDARDS_OUTPUT"
  exit 0
fi

# Dehydrated context was already detected during the single-pass scan above.
# DEHYDRATED_STATE_FILE is set if any .state.json had dehydratedContext of type "object".
STATE_FILE="${DEHYDRATED_STATE_FILE:-}"

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
