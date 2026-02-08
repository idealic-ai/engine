#!/bin/bash
# ~/.claude/scripts/session.sh — Session directory and agent state management
#
# Usage:
#   session.sh init <path>                         # Create session directory (legacy)
#   session.sh activate <path> <skill> [--target-file FILE] [--user-approved REASON] [<<JSON]
#                                                  # Create session + .state.json + PID tracking
#                                                  # Accepts optional JSON on stdin (session params → merged into .state.json)
#                                                  # Outputs: Markdown context (alerts, delegations, RAG suggestions)
#                                                  # Fleet pane is auto-detected from tmux
#                                                  # --user-approved: Required to re-activate a previously completed skill
#   session.sh update <path> <field> <value>       # Update field in .state.json
#   session.sh phase <path> <phase>                # Shortcut: update currentPhase
#   session.sh target <path> <file>               # Shortcut: update targetFile (for status line)
#   session.sh deactivate <path> [--keywords 'kw1,kw2'] <<DESCRIPTION
#                                                  # Set lifecycle=completed (gate re-engages)
#                                                  # REQUIRES 1-3 line description on stdin for RAG/search
#                                                  # --keywords: comma-separated search keywords (stored in .state.json)
#                                                  # Outputs: Related sessions from RAG search (if GEMINI_API_KEY set)
#   session.sh restart <path>                      # Set status=ready-to-kill, signal wrapper
#   session.sh find                                 # Find session dir for current process (read-only)
#
# Examples:
#   session.sh init sessions/2026_02_03_MY_TOPIC
#   session.sh activate sessions/2026_02_03_MY_TOPIC brainstorm
#   session.sh update sessions/2026_02_03_MY_TOPIC contextUsage 0.85
#   session.sh phase sessions/2026_02_03_MY_TOPIC "Phase 3: Execution"
#   session.sh restart sessions/2026_02_03_MY_TOPIC
#   session.sh find                                  # outputs session dir path or exits 1
#
# Related:
#   Docs: (~/.claude/docs/)
#     SESSION_LIFECYCLE.md — Session state machine, activation/deactivation flows
#     CONTEXT_GUARDIAN.md — Overflow protection, restart handling
#     FLEET.md — Fleet pane ID auto-detection, multi-agent coordination
#   Invariants: (~/.claude/standards/INVARIANTS.md)
#     ¶INV_PHASE_ENFORCEMENT — Phase transition enforcement via session.sh phase
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — Graceful degradation without fleet/tmux
#     ¶INV_QUESTION_GATE_OVER_TEXT_GATE — User approval gates (--user-approved)
#   Commands: (~/.claude/standards/COMMANDS.md)
#     §CMD_MAINTAIN_SESSION_DIR — Session directory management
#     §CMD_PARSE_PARAMETERS — Session activation with JSON params
#     §CMD_UPDATE_PHASE — Phase tracking and enforcement
#     §CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL — Session completion
#     §CMD_REANCHOR_AFTER_RESTART — Restart recovery

set -euo pipefail

# Source shared utilities (timestamp, pid_exists, safe_json_write)
source "$HOME/.claude/scripts/lib.sh"

ACTION="${1:?Usage: session.sh <init|activate|update|find|restart> <path> [args...]}"

# DIR is required for all commands except 'find'
if [ "$ACTION" = "find" ]; then
  DIR=""
else
  DIR="${2:?Missing directory path}"
fi

STATE_FILE="$DIR/.state.json"

# Helper: Auto-detect fleet pane ID from tmux
# Returns composite fleetPaneId (session:window:pane) if inside fleet, empty otherwise
get_fleet_pane_id() {
  # Use fleet.sh pane-id for composite format (session:window:pane)
  # This is the canonical source of truth for fleet identity
  "$HOME/.claude/scripts/fleet.sh" pane-id 2>/dev/null || echo ""
}

case "$ACTION" in
  init)
    # Legacy: just create directory
    if [ -d "$DIR" ]; then
      echo "Session already exists: $DIR"
    else
      mkdir -p "$DIR"
      echo "New session created: $DIR"
    fi
    ;;

  activate)
    SKILL="${3:?Missing skill name}"

    # Parse optional flags: --fleet-pane NAME, --target-file FILE, --user-approved REASON
    # PID comes from CLAUDE_SUPERVISOR_PID env var (exported by run.sh)
    TARGET_PID="${CLAUDE_SUPERVISOR_PID:-$PPID}"
    FLEET_PANE=""
    TARGET_FILE=""
    USER_APPROVED=""
    shift 3  # Remove action, dir, skill
    while [ $# -gt 0 ]; do
      case "$1" in
        --fleet-pane)
          FLEET_PANE="${2:?--fleet-pane requires a value}"
          shift 2
          ;;
        --target-file)
          TARGET_FILE="${2:?--target-file requires a value}"
          shift 2
          ;;
        --user-approved)
          USER_APPROVED="${2:?--user-approved requires a reason string}"
          shift 2
          ;;
        *)
          echo "WARNING: Unknown flag '$1'" >&2
          shift
          ;;
      esac
    done

    # Read optional JSON from stdin (session parameters)
    # Heredoc usage: session.sh activate path skill <<'EOF' ... EOF
    # No-JSON usage: session.sh activate path skill < /dev/null
    # WARNING: calling without heredoc AND without < /dev/null will hang on non-terminal stdin
    STDIN_JSON=""
    if [ ! -t 0 ]; then
      STDIN_JSON=$(cat)
      if [ -n "$STDIN_JSON" ]; then
        if ! echo "$STDIN_JSON" | jq empty 2>/dev/null; then
          echo "ERROR: Invalid JSON on stdin" >&2
          exit 1
        fi
      fi
    fi

    # Tracking: should we run context scans? Was .state.json already handled?
    SHOULD_SCAN=false
    ACTIVATED=false

    # Fleet pane: prefer --fleet-pane flag, then auto-detect via fleet.sh pane-id
    if [ -z "$FLEET_PANE" ]; then
      FLEET_PANE=$(get_fleet_pane_id)
    fi

    # Claim fleet pane: clear fleetPaneId from any OTHER session that has it
    if [ -n "$FLEET_PANE" ]; then
      SESSIONS_DIR=$(dirname "$DIR")
      grep -l "\"fleetPaneId\": \"$FLEET_PANE\"" "$SESSIONS_DIR"/*/.state.json 2>/dev/null | while read -r other_file; do
        [ "$other_file" = "$STATE_FILE" ] && continue
        jq 'del(.fleetPaneId)' "$other_file" | safe_json_write "$other_file"
        echo "Cleared stale fleetPaneId from: $(dirname "$other_file" | xargs basename)"
      done || true
    fi

    # Claim PID: clear our PID from any OTHER session that has it
    # Ensures only one session is "held" per run.sh instance
    SESSIONS_DIR=$(dirname "$DIR")
    grep -l "\"pid\": $TARGET_PID" "$SESSIONS_DIR"/*/.state.json 2>/dev/null | while read -r other_file; do
      [ "$other_file" = "$STATE_FILE" ] && continue
      jq '.pid = 0' "$other_file" | safe_json_write "$other_file"
      echo "Cleared stale PID from: $(dirname "$other_file" | xargs basename)"
    done || true

    # Create directory if needed
    mkdir -p "$DIR"

    # --- Migration: .agent.json → .state.json ---
    if [ -f "$DIR/.agent.json" ] && [ ! -f "$STATE_FILE" ]; then
      mv "$DIR/.agent.json" "$STATE_FILE"
      echo "Migrated .agent.json → .state.json in $DIR"
    fi

    # --- completedSkills Gate ---
    # If the state file has a completedSkills array containing the requested skill, reject
    # unless --user-approved is provided (same pattern as phase enforcement)
    if [ -f "$STATE_FILE" ]; then
      SKILL_COMPLETED=$(jq -r --arg s "$SKILL" \
        '(.completedSkills // []) | any(. == $s)' "$STATE_FILE" 2>/dev/null || echo "false")
      if [ "$SKILL_COMPLETED" = "true" ]; then
        if [ -z "$USER_APPROVED" ]; then
          COMPLETED_LIST=$(jq -r '(.completedSkills // []) | join(", ")' "$STATE_FILE" 2>/dev/null || echo "")
          echo "ERROR: Skill '$SKILL' was already completed in this session." >&2
          echo "  Completed skills: $COMPLETED_LIST" >&2
          echo "  Session: $DIR" >&2
          echo "" >&2
          echo "Ensure you are doing the right thing — right skill, right phase. You may re-activate this skill if the user explicitly allowed it." >&2
          echo "  To proceed: session.sh activate $DIR $SKILL --user-approved \"Reason: ...\"" >&2
          exit 1
        fi
        echo "Skill re-activation approved (previously completed): $SKILL"
        echo "  Approval: $USER_APPROVED"
      fi
    fi

    # Check for existing .state.json
    if [ -f "$STATE_FILE" ]; then
      EXISTING_PID=$(jq -r '.pid // empty' "$STATE_FILE" 2>/dev/null || echo "")

      if [ -n "$EXISTING_PID" ]; then
        if [ "$EXISTING_PID" == "$TARGET_PID" ]; then
          # Same Claude process — check if skill changed
          EXISTING_SKILL=$(jq -r '.skill // empty' "$STATE_FILE")

          # IMPORTANT: Always reset to clean state — clears killRequested/overflowed from restarts
          # loading=true: heartbeat hook skips all counting during bootstrap (cleared by session.sh phase)
          JQ_EXPR='.skill = $skill | .lifecycle = "active" | .loading = true | .overflowed = false | .killRequested = false | .lastHeartbeat = $ts'
          JQ_ARGS=(--arg skill "$SKILL" --arg ts "$(timestamp)")

          if [ -n "$FLEET_PANE" ]; then
            JQ_EXPR="$JQ_EXPR | .fleetPaneId = \$pane"
            JQ_ARGS+=(--arg pane "$FLEET_PANE")
          fi

          if [ -n "$TARGET_FILE" ]; then
            JQ_EXPR="$JQ_EXPR | .targetFile = \$file"
            JQ_ARGS+=(--arg file "$TARGET_FILE")
          fi

          jq "${JQ_ARGS[@]}" "$JQ_EXPR" \
            "$STATE_FILE" | safe_json_write "$STATE_FILE"

          # Skill change: wipe phase state BEFORE merge so old phases don't persist
          if [ "$EXISTING_SKILL" != "$SKILL" ]; then
            jq 'del(.phases) | .phaseHistory = []' \
              "$STATE_FILE" | safe_json_write "$STATE_FILE"
          fi

          # Merge stdin JSON into .state.json if provided
          if [ -n "$STDIN_JSON" ]; then
            jq -s '.[0] * .[1]' "$STATE_FILE" <(echo "$STDIN_JSON") | safe_json_write "$STATE_FILE"
          fi

          ACTIVATED=true
          if [ "$EXISTING_SKILL" != "$SKILL" ]; then
            SHOULD_SCAN=true
            # Derive currentPhase from new phases array (if provided by new skill)
            HAS_NEW_PHASES=$(jq 'has("phases") and (.phases | length > 0)' "$STATE_FILE" 2>/dev/null || echo "false")
            if [ "$HAS_NEW_PHASES" = "true" ]; then
              jq '.currentPhase = (
                .phases | sort_by(.major, .minor) | first |
                if .minor == 0 then "\(.major): \(.name)"
                else "\(.major).\(.minor): \(.name)" end
              )' "$STATE_FILE" | safe_json_write "$STATE_FILE"
            else
              # No phases array in new activation — reset to default
              jq '.currentPhase = "Phase 1: Setup"' \
                "$STATE_FILE" | safe_json_write "$STATE_FILE"
            fi
          else
            # Same skill, same PID — brief confirmation, no scans
            echo "Session re-activated: $DIR (skill: $SKILL, pid: $TARGET_PID)"
            exit 0
          fi
        elif pid_exists "$EXISTING_PID"; then
          # Different Claude process is active — reject
          echo "ERROR: Session has active agent (PID $EXISTING_PID). Choose another folder." >&2
          exit 1
        else
          # Stale PID, process dead — clean up
          echo "Cleaning up stale .state.json (PID $EXISTING_PID no longer running)"
          rm "$STATE_FILE"
        fi
      fi
    fi

    # Create fresh .state.json (skip if already handled via same-PID path)
    if [ "$ACTIVATED" = false ]; then
      NOW=$(timestamp)
      # Build base JSON and conditionally add optional fields
      BASE_JSON=$(jq -n \
        --argjson pid "$TARGET_PID" \
        --arg skill "$SKILL" \
        --arg startedAt "$NOW" \
        --arg lastHeartbeat "$NOW" \
        '{
          pid: $pid,
          skill: $skill,
          lifecycle: "active",
          loading: true,
          overflowed: false,
          killRequested: false,
          contextUsage: 0,
          currentPhase: "Phase 1: Setup",
          toolCallsSinceLastLog: 0,
          toolUseWithoutLogsWarnAfter: 3,
          toolUseWithoutLogsBlockAfter: 10,
          startedAt: $startedAt,
          lastHeartbeat: $lastHeartbeat
        }')

      # Add optional fields
      if [ -n "$FLEET_PANE" ]; then
        BASE_JSON=$(echo "$BASE_JSON" | jq --arg pane "$FLEET_PANE" '.fleetPaneId = $pane')
      fi
      if [ -n "$TARGET_FILE" ]; then
        BASE_JSON=$(echo "$BASE_JSON" | jq --arg file "$TARGET_FILE" '.targetFile = $file')
      fi

      # Merge stdin JSON (session parameters) if provided
      if [ -n "$STDIN_JSON" ]; then
        BASE_JSON=$(echo "$BASE_JSON" | jq -s '.[0] * .[1]' - <(echo "$STDIN_JSON"))
      fi

      # If phases array was provided, set currentPhase to first phase's label
      # Label derived: minor=0 → "N: Name", minor>0 → "N.M: Name"
      HAS_PHASES_CHECK=$(echo "$BASE_JSON" | jq 'has("phases") and (.phases | length > 0)' 2>/dev/null || echo "false")
      if [ "$HAS_PHASES_CHECK" = "true" ]; then
        BASE_JSON=$(echo "$BASE_JSON" | jq '
          .currentPhase = (
            .phases | sort_by(.major, .minor) | first |
            if .minor == 0 then "\(.major): \(.name)"
            else "\(.major).\(.minor): \(.name)" end
          )
        ')
      fi

      echo "$BASE_JSON" | safe_json_write "$STATE_FILE"
      SHOULD_SCAN=true
    fi

    # --- Output: Structured Markdown Context ---

    # Confirmation line
    MSG="Session activated: $DIR (skill: $SKILL, pid: $TARGET_PID"
    [ -n "$FLEET_PANE" ] && MSG="$MSG, fleet: $FLEET_PANE"
    [ -n "$TARGET_FILE" ] && MSG="$MSG, target: $TARGET_FILE"
    echo "$MSG)"

    # Context scanning (only on fresh activation or skill change)
    if [ "$SHOULD_SCAN" = true ]; then
      SESSION_SEARCH="$HOME/.claude/tools/session-search/session-search.sh"
      DOC_SEARCH="$HOME/.claude/tools/doc-search/doc-search.sh"

      # Extract taskSummary for thematic search
      TASK_SUMMARY=""
      if [ -n "$STDIN_JSON" ]; then
        TASK_SUMMARY=$(echo "$STDIN_JSON" | jq -r '.taskSummary // empty')
      fi

      # Active Alerts (thematic via session-search)
      echo ""
      echo "## Active Alerts"
      if [ -n "$TASK_SUMMARY" ]; then
        ALERTS=$("$SESSION_SEARCH" query "$TASK_SUMMARY" --tag '#active-alert' --limit 10 2>/dev/null || true)
      fi
      if [ -n "${ALERTS:-}" ]; then
        echo "$ALERTS"
      else
        echo "(none)"
      fi

      # Open Delegations (thematic via session-search)
      echo ""
      echo "## Open Delegations"
      if [ -n "$TASK_SUMMARY" ]; then
        DELEGATIONS=$("$SESSION_SEARCH" query "$TASK_SUMMARY" --tag '#needs-delegation' --limit 10 2>/dev/null || true)
      fi
      if [ -n "${DELEGATIONS:-}" ]; then
        echo "$DELEGATIONS"
      else
        echo "(none)"
      fi

      # RAG: Sessions (semantic search over past session logs)
      echo ""
      echo "## RAG: Sessions"
      if [ -n "$TASK_SUMMARY" ]; then
        SESSION_RAG=$("$SESSION_SEARCH" query "$TASK_SUMMARY" --limit 10 2>/dev/null || true)
      fi
      if [ -n "${SESSION_RAG:-}" ]; then
        echo "$SESSION_RAG"
      else
        echo "(none)"
      fi

      # RAG: Docs (semantic search over project documentation)
      echo ""
      echo "## RAG: Docs"
      if [ -n "$TASK_SUMMARY" ]; then
        DOC_RAG=$("$DOC_SEARCH" query "$TASK_SUMMARY" --limit 10 2>/dev/null || true)
      fi
      if [ -n "${DOC_RAG:-}" ]; then
        echo "$DOC_RAG"
      else
        echo "(none)"
      fi
    fi
    ;;

  update)
    FIELD="${3:?Missing field name}"
    VALUE="${4:?Missing value}"

    if [ ! -f "$STATE_FILE" ]; then
      echo "ERROR: No .state.json in $DIR" >&2
      exit 1
    fi

    # Update the field and lastHeartbeat
    # Handle numeric vs string values
    if [[ "$VALUE" =~ ^[0-9]+\.?[0-9]*$ ]]; then
      # Numeric value
      jq --arg field "$FIELD" --argjson value "$VALUE" --arg ts "$(timestamp)" \
        '.[$field] = $value | .lastHeartbeat = $ts' \
        "$STATE_FILE" | safe_json_write "$STATE_FILE"
    else
      # String value
      jq --arg field "$FIELD" --arg value "$VALUE" --arg ts "$(timestamp)" \
        '.[$field] = $value | .lastHeartbeat = $ts' \
        "$STATE_FILE" | safe_json_write "$STATE_FILE"
    fi

    echo "Updated $FIELD=$VALUE in $DIR"
    ;;

  phase)
    PHASE="${3:?Missing phase name (e.g., '3: Execution')}"

    if [ ! -f "$STATE_FILE" ]; then
      echo "ERROR: No .state.json in $DIR" >&2
      exit 1
    fi

    # Parse optional --user-approved flag for non-sequential transitions
    USER_APPROVED=""
    shift 3  # Remove action, dir, phase
    while [ $# -gt 0 ]; do
      case "$1" in
        --user-approved)
          USER_APPROVED="${2:?--user-approved requires a reason string}"
          shift 2
          ;;
        *)
          echo "WARNING: Unknown flag '$1'" >&2
          shift
          ;;
      esac
    done

    # --- Phase Enforcement ---
    # If .state.json has a "phases" array, enforce sequential progression.
    # If no "phases" array, skip enforcement (backward compat with old sessions).
    # Phases use {major, minor} integer pairs — no floats.
    HAS_PHASES=$(jq 'has("phases") and (.phases | length > 0)' "$STATE_FILE" 2>/dev/null || echo "false")

    if [ "$HAS_PHASES" = "true" ]; then
      # Extract major.minor from the requested phase label
      # Format: "N: Name" (major only) or "N.M: Name" (with minor)
      REQ_MAJOR=$(echo "$PHASE" | grep -oE '^[0-9]+' || echo "")
      if [ -z "$REQ_MAJOR" ]; then
        echo "ERROR: Phase label must start with a number (e.g., '3: Execution', '4.1: Sub-Step'). Got: '$PHASE'" >&2
        exit 1
      fi
      # Extract minor: if "4.1: ..." → minor=1, if "4: ..." → minor=0
      REQ_MINOR=$(echo "$PHASE" | grep -oE '^\d+\.(\d+)' | grep -oE '\.\d+' | tr -d '.' || echo "0")
      [ -z "$REQ_MINOR" ] && REQ_MINOR=0

      # Get current phase major.minor
      CURRENT_PHASE=$(jq -r '.currentPhase // ""' "$STATE_FILE")
      CUR_MAJOR=$(echo "$CURRENT_PHASE" | grep -oE '^[0-9]+' || echo "0")
      CUR_MINOR=$(echo "$CURRENT_PHASE" | grep -oE '^\d+\.(\d+)' | grep -oE '\.\d+' | tr -d '.' || echo "0")
      [ -z "$CUR_MINOR" ] && CUR_MINOR=0

      # Helper: compare two major.minor pairs
      # Returns: "lt", "eq", "gt"
      phase_cmp() {
        local a_maj=$1 a_min=$2 b_maj=$3 b_min=$4
        if [ "$a_maj" -lt "$b_maj" ]; then echo "lt"
        elif [ "$a_maj" -gt "$b_maj" ]; then echo "gt"
        elif [ "$a_min" -lt "$b_min" ]; then echo "lt"
        elif [ "$a_min" -gt "$b_min" ]; then echo "gt"
        else echo "eq"
        fi
      }

      # Find the next declared phase (first phase with major.minor > current)
      NEXT_PHASE_JSON=$(jq -r --argjson cm "$CUR_MAJOR" --argjson cn "$CUR_MINOR" \
        '[.phases[] | select(.major > $cm or (.major == $cm and .minor > $cn))] | sort_by(.major, .minor) | first // empty' \
        "$STATE_FILE" 2>/dev/null || echo "")

      NEXT_MAJOR=""
      NEXT_MINOR=""
      if [ -n "$NEXT_PHASE_JSON" ]; then
        NEXT_MAJOR=$(echo "$NEXT_PHASE_JSON" | jq -r '.major')
        NEXT_MINOR=$(echo "$NEXT_PHASE_JSON" | jq -r '.minor')
      fi

      # Determine if transition is sequential
      IS_SEQUENTIAL=false

      # Case 0: Re-entering the same phase (no-op, always allowed)
      # Happens after skill switch: activate sets currentPhase, agent formally enters it
      if [ "$REQ_MAJOR" = "$CUR_MAJOR" ] && [ "$REQ_MINOR" = "$CUR_MINOR" ]; then
        IS_SEQUENTIAL=true
      fi

      # Case 1: Moving to the next declared phase
      if [ -n "$NEXT_MAJOR" ] && [ "$REQ_MAJOR" = "$NEXT_MAJOR" ] && [ "$REQ_MINOR" = "$NEXT_MINOR" ]; then
        IS_SEQUENTIAL=true
      fi

      # Case 2: Sub-phase auto-append — same major as current, higher minor
      # e.g., current=4.0, requested=4.1 → valid sub-phase (auto-appended)
      if [ "$IS_SEQUENTIAL" = "false" ]; then
        IS_DECLARED=$(jq -r --argjson m "$REQ_MAJOR" --argjson n "$REQ_MINOR" \
          '[.phases[]] | any(.major == $m and .minor == $n)' \
          "$STATE_FILE" 2>/dev/null || echo "false")

        if [ "$IS_DECLARED" = "false" ] && [ "$REQ_MAJOR" = "$CUR_MAJOR" ] && [ "$REQ_MINOR" -gt "$CUR_MINOR" ]; then
          IS_SEQUENTIAL=true
          # Auto-append: insert this sub-phase into the phases array
          REQUESTED_NAME=$(echo "$PHASE" | sed -E 's/^[0-9]+(\.[0-9]+)?: //')
          jq --argjson maj "$REQ_MAJOR" --argjson min "$REQ_MINOR" --arg name "$REQUESTED_NAME" \
            '.phases += [{"major": $maj, "minor": $min, "name": $name}] | .phases |= sort_by(.major, .minor)' \
            "$STATE_FILE" | safe_json_write "$STATE_FILE"
        fi
      fi

      # If not sequential, require --user-approved
      if [ "$IS_SEQUENTIAL" = "false" ]; then
        if [ -z "$USER_APPROVED" ]; then
          echo "ERROR: Non-sequential phase transition rejected." >&2
          echo "  Current phase: $CURRENT_PHASE ($CUR_MAJOR.$CUR_MINOR)" >&2
          echo "  Requested phase: $PHASE ($REQ_MAJOR.$REQ_MINOR)" >&2
          if [ -n "$NEXT_MAJOR" ]; then
            NEXT_NAME=$(echo "$NEXT_PHASE_JSON" | jq -r '.name')
            if [ "$NEXT_MINOR" = "0" ]; then
              NEXT_LABEL="$NEXT_MAJOR: $NEXT_NAME"
            else
              NEXT_LABEL="$NEXT_MAJOR.$NEXT_MINOR: $NEXT_NAME"
            fi
            echo "  Expected next: $NEXT_LABEL" >&2
          fi
          echo "" >&2
          echo "Ensure you are doing the right thing — right skill, right phase. You may change phase if the user explicitly allowed it." >&2
          echo "  To proceed: session.sh phase $DIR \"$PHASE\" --user-approved \"Reason: ...\"" >&2
          exit 1
        fi
        # Log the approved non-sequential transition
        echo "Phase transition approved (non-sequential): $CURRENT_PHASE → $PHASE"
        echo "  Approval: $USER_APPROVED"
      fi
    fi

    # Update phase, clear loading flag, and reset all heartbeat transcript counters
    # loading=true is set by activate; cleared here when the agent transitions to a named phase
    # Counter reset gives a clean slate for the work phase
    # Append to phaseHistory for audit trail
    jq --arg phase "$PHASE" --arg ts "$(timestamp)" \
      '.currentPhase = $phase | .lastHeartbeat = $ts | del(.loading) | .toolCallsByTranscript = {} | .phaseHistory = ((.phaseHistory // []) + [$phase])' \
      "$STATE_FILE" | safe_json_write "$STATE_FILE"

    # Notify fleet of state change (if running in fleet context)
    # WAITING: or DONE = needs attention (unchecked), otherwise = working (orange)
    if [[ "$PHASE" == WAITING:* ]] || [[ "$PHASE" == "DONE" ]]; then
      "$HOME/.claude/scripts/fleet.sh" notify unchecked 2>/dev/null || true
    else
      "$HOME/.claude/scripts/fleet.sh" notify working 2>/dev/null || true
    fi

    echo "Phase: $PHASE"
    ;;

  target)
    # Update target file (for status line clickability)
    FILE="${3:?Missing target file path (relative to session dir)}"

    if [ ! -f "$STATE_FILE" ]; then
      echo "ERROR: No .state.json in $DIR" >&2
      exit 1
    fi

    jq --arg file "$FILE" --arg ts "$(timestamp)" \
      '.targetFile = $file | .lastHeartbeat = $ts' \
      "$STATE_FILE" | safe_json_write "$STATE_FILE"

    echo "Target file: $FILE"
    ;;

  deactivate)
    if [ ! -f "$STATE_FILE" ]; then
      echo "ERROR: No .state.json in $DIR" >&2
      exit 1
    fi

    # Parse optional flags: --keywords "kw1,kw2,..."
    KEYWORDS=""
    shift 2  # Remove action, dir
    while [ $# -gt 0 ]; do
      case "$1" in
        --keywords)
          KEYWORDS="${2:?--keywords requires a value}"
          shift 2
          ;;
        *)
          echo "WARNING: Unknown flag '$1'" >&2
          shift
          ;;
      esac
    done

    # Read REQUIRED description from stdin (1-3 lines for RAG/search)
    DESCRIPTION=""
    if [ ! -t 0 ]; then
      DESCRIPTION=$(cat)
    fi

    if [ -z "$DESCRIPTION" ]; then
      echo "ERROR: Description is required. Pipe 1-3 lines via stdin:" >&2
      echo "  session.sh deactivate <path> [--keywords 'kw1,kw2'] <<'EOF'" >&2
      echo "  What was done in this session (1-3 lines)" >&2
      echo "  EOF" >&2
      exit 1
    fi

    # Build jq expression based on whether keywords were provided
    if [ -n "$KEYWORDS" ]; then
      jq --arg ts "$(timestamp)" --arg desc "$DESCRIPTION" --arg kw "$KEYWORDS" \
        '.lifecycle = "completed" | .lastHeartbeat = $ts | .sessionDescription = $desc | .searchKeywords = ($kw | split(",") | map(gsub("^\\s+|\\s+$"; "")))' \
        "$STATE_FILE" | safe_json_write "$STATE_FILE"
    else
      jq --arg ts "$(timestamp)" --arg desc "$DESCRIPTION" \
        '.lifecycle = "completed" | .lastHeartbeat = $ts | .sessionDescription = $desc' \
        "$STATE_FILE" | safe_json_write "$STATE_FILE"
    fi

    # Append current skill to completedSkills (idempotent — skip if already present)
    CURRENT_SKILL=$(jq -r '.skill // empty' "$STATE_FILE" 2>/dev/null || echo "")
    if [ -n "$CURRENT_SKILL" ]; then
      jq --arg s "$CURRENT_SKILL" \
        'if (.completedSkills // []) | any(. == $s) then . else .completedSkills = ((.completedSkills // []) + [$s]) end' \
        "$STATE_FILE" | safe_json_write "$STATE_FILE"
    fi

    # Notify fleet of completion (if running in fleet context)
    "$HOME/.claude/scripts/fleet.sh" notify unchecked 2>/dev/null || true

    echo "Session deactivated: $DIR (lifecycle=completed)"

    # Reindex search databases (background, best-effort)
    # Keeps RAG fresh so the next session's context ingestion finds this session's work
    "$HOME/.claude/tools/session-search/session-search.sh" index &>/dev/null &
    "$HOME/.claude/tools/doc-search/doc-search.sh" index &>/dev/null &

    # Run RAG search on deactivation (non-blocking, best-effort)
    # Uses description as search query to find related sessions
    if command -v "$HOME/.claude/scripts/session-search.sh" &>/dev/null && [ -n "${GEMINI_API_KEY:-}" ]; then
      RAG_RESULTS=$("$HOME/.claude/scripts/session-search.sh" query "$DESCRIPTION" --limit 5 2>/dev/null || echo "")
      if [ -n "$RAG_RESULTS" ]; then
        echo ""
        echo "## Related Sessions"
        echo "$RAG_RESULTS"
      fi
    fi
    ;;

  restart)
    if [ ! -f "$STATE_FILE" ]; then
      echo "ERROR: No .state.json in $DIR" >&2
      exit 1
    fi

    # Read current state
    SKILL=$(jq -r '.skill' "$STATE_FILE")
    CURRENT_PHASE=$(jq -r '.currentPhase // "Phase 1: Setup"' "$STATE_FILE")

    # Create the prompt for the new Claude - invoke /reanchor skill with --continue for unbroken restart
    PROMPT="/reanchor --session $DIR --skill $SKILL --phase \"$CURRENT_PHASE\" --continue"

    # State-only restart: set killRequested, write restartPrompt, reset contextUsage, delete sessionId
    # The watchdog (signaled below) handles the actual kill
    jq --arg ts "$(timestamp)" --arg prompt "$PROMPT" \
      '.killRequested = true | .lastHeartbeat = $ts | .restartPrompt = $prompt | .contextUsage = 0 | del(.sessionId)' \
      "$STATE_FILE" | safe_json_write "$STATE_FILE"

    # Signal the watchdog to kill Claude
    if [ -n "${WATCHDOG_PID:-}" ]; then
      echo "Restart prepared. Signaling watchdog (PID $WATCHDOG_PID) to kill Claude..."
      kill -USR1 "$WATCHDOG_PID" 2>/dev/null || true
    else
      echo "WARNING: No watchdog active (WATCHDOG_PID not set)."
      echo "Not running under run.sh wrapper. To restart manually, run:"
      echo ""
      echo "claude '$PROMPT'"
    fi
    exit 0
    ;;

  find)
    # Find the session directory for the current Claude process
    # Pure lookup — no side effects, no PID claiming
    #
    # Strategy:
    #   1. Fleet mode: call fleet.sh pane-id, match by fleetPaneId
    #   2. Fallback: match by CLAUDE_SUPERVISOR_PID (or $PPID)
    #
    # PID guard: if a different alive PID holds the session, return 1
    # Output: session directory path (one line) or exit 1

    SESSIONS_DIR="$PWD/sessions"
    if [ ! -d "$SESSIONS_DIR" ]; then
      exit 1
    fi

    CLAUDE_PID="${CLAUDE_SUPERVISOR_PID:-$PPID}"
    FOUND_DIR=""

    # Strategy 1: Fleet mode — lookup by fleetPaneId
    FLEET_PANE=$(get_fleet_pane_id)
    if [ -n "$FLEET_PANE" ]; then
      while IFS= read -r f; do
        [ -f "$f" ] || continue
        file_fleet_pane=$(jq -r '.fleetPaneId // ""' "$f" 2>/dev/null)
        if [ "$file_fleet_pane" = "$FLEET_PANE" ]; then
          # PID guard: reject if a different alive PID holds the session
          file_pid=$(jq -r '.pid // 0' "$f" 2>/dev/null)
          if [ "$file_pid" != "0" ] && [ "$file_pid" != "$CLAUDE_PID" ]; then
            if kill -0 "$file_pid" 2>/dev/null; then
              # Different Claude is active — not our session
              exit 1
            fi
          fi
          FOUND_DIR=$(dirname "$f")
          break
        fi
      done < <(find -L "$SESSIONS_DIR" -name ".state.json" -type f 2>/dev/null)
    fi

    # Strategy 2: Non-fleet fallback — lookup by PID
    if [ -z "$FOUND_DIR" ] && [ -z "$FLEET_PANE" ]; then
      while IFS= read -r f; do
        [ -f "$f" ] || continue
        file_pid=$(jq -r '.pid // 0' "$f" 2>/dev/null)
        if [ "$file_pid" = "$CLAUDE_PID" ]; then
          FOUND_DIR=$(dirname "$f")
          break
        fi
      done < <(find -L "$SESSIONS_DIR" -name ".state.json" -type f 2>/dev/null)
    fi

    if [ -z "$FOUND_DIR" ]; then
      exit 1
    fi

    echo "$FOUND_DIR"
    ;;

  *)
    echo "ERROR: Unknown action '$ACTION'. Use: init, activate, update, find, phase, target, deactivate, restart" >&2
    exit 1
    ;;
esac
