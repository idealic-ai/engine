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
#   session.sh check <path> [<<STDIN]                 # Tag scan + checklist validation (sets checkPassed=true)
#   session.sh find                                 # Find session dir for current process (read-only)
#   session.sh request-template <tag>               # Output REQUEST template for a #needs-* tag to stdout
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
#   Invariants: (~/.claude/directives/INVARIANTS.md)
#     ¶INV_PHASE_ENFORCEMENT — Phase transition enforcement via session.sh phase
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — Graceful degradation without fleet/tmux
#     ¶INV_QUESTION_GATE_OVER_TEXT_GATE — User approval gates (--user-approved)
#   Commands: (~/.claude/directives/COMMANDS.md)
#     §CMD_MAINTAIN_SESSION_DIR — Session directory management
#     §CMD_PARSE_PARAMETERS — Session activation with JSON params
#     §CMD_UPDATE_PHASE — Phase tracking and enforcement
#     §CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL — Session completion
#     §CMD_REANCHOR_AFTER_RESTART — Restart recovery
#     §CMD_REQUIRE_ACTIVE_SESSION — Session gate enforcement
#     §CMD_RESOLVE_REQUEST_TEMPLATE — Tag-to-skill template resolution

set -euo pipefail

# Source shared utilities (timestamp, pid_exists, safe_json_write)
source "$HOME/.claude/scripts/lib.sh"

ACTION="${1:?Usage: session.sh <init|activate|update|find|restart> <path> [args...]}"

# DIR is required for all commands except 'find' and 'request-template'
if [ "$ACTION" = "find" ] || [ "$ACTION" = "request-template" ]; then
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
          echo "§CMD_PARSE_PARAMETERS: Unknown flag '$1'" >&2
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
          echo "§CMD_PARSE_PARAMETERS: Invalid JSON on stdin" >&2
          exit 1
        fi

        # --- Required Fields Validation (§CMD_PARSE_PARAMETERS schema) ---
        # Validate all required fields are present when JSON is provided.
        # sessionDir and startedAt are set by the script, not the caller.
        REQUIRED_FIELDS="taskType taskSummary scope directoriesOfInterest preludeFiles contextPaths planTemplate logTemplate debriefTemplate extraInfo phases"
        MISSING_FIELDS=""
        for field in $REQUIRED_FIELDS; do
          if ! echo "$STDIN_JSON" | jq -e "has(\"$field\")" > /dev/null 2>&1; then
            MISSING_FIELDS="${MISSING_FIELDS:+$MISSING_FIELDS, }$field"
          fi
        done
        if [ -n "$MISSING_FIELDS" ]; then
          echo "§CMD_PARSE_PARAMETERS: Missing required field(s) in JSON: $MISSING_FIELDS" >&2
          echo "  See §CMD_PARSE_PARAMETERS schema for required fields." >&2
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
          echo "§CMD_PARSE_PARAMETERS: Skill '$SKILL' was already completed in this session." >&2
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
          echo "§CMD_MAINTAIN_SESSION_DIR: Session has active agent (PID $EXISTING_PID). Choose another folder." >&2
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

      # §CMD_SURFACE_ACTIVE_ALERTS (thematic via session-search)
      echo ""
      echo "## §CMD_SURFACE_ACTIVE_ALERTS"
      if [ -n "$TASK_SUMMARY" ]; then
        SURFACE_ALERTS=$("$SESSION_SEARCH" query "$TASK_SUMMARY" --tag '#active-alert' --limit 10 2>/dev/null || true)
      fi
      if [ -n "${SURFACE_ALERTS:-}" ]; then
        echo "$SURFACE_ALERTS"
      else
        echo "(none)"
      fi

      # §CMD_SURFACE_OPEN_DELEGATIONS (thematic via session-search)
      echo ""
      echo "## §CMD_SURFACE_OPEN_DELEGATIONS"
      if [ -n "$TASK_SUMMARY" ]; then
        SURFACE_DELEGATIONS=$("$SESSION_SEARCH" query "$TASK_SUMMARY" --tag '#needs-delegation' --limit 10 2>/dev/null || true)
      fi
      if [ -n "${SURFACE_DELEGATIONS:-}" ]; then
        echo "$SURFACE_DELEGATIONS"
      else
        echo "(none)"
      fi

      # §CMD_RECALL_PRIOR_SESSIONS (semantic search over past session logs)
      echo ""
      echo "## §CMD_RECALL_PRIOR_SESSIONS"
      if [ -n "$TASK_SUMMARY" ]; then
        RECALL_SESSIONS=$("$SESSION_SEARCH" query "$TASK_SUMMARY" --limit 10 2>/dev/null || true)
      fi
      if [ -n "${RECALL_SESSIONS:-}" ]; then
        echo "$RECALL_SESSIONS"
      else
        echo "(none)"
      fi

      # §CMD_RECALL_RELEVANT_DOCS (semantic search over project documentation)
      echo ""
      echo "## §CMD_RECALL_RELEVANT_DOCS"
      if [ -n "$TASK_SUMMARY" ]; then
        RECALL_DOCS=$("$DOC_SEARCH" query "$TASK_SUMMARY" --limit 10 2>/dev/null || true)
      fi
      if [ -n "${RECALL_DOCS:-}" ]; then
        echo "$RECALL_DOCS"
      else
        echo "(none)"
      fi

      # Discovered Directives: walk-up from directoriesOfInterest
      # Finds soft directives (README.md, INVARIANTS.md, TESTING.md, PITFALLS.md) and
      # hard directives (CHECKLIST.md — enforced at deactivation).
      # Skill filtering: core directives always shown; skill directives only if declared.
      # See ¶INV_DIRECTIVE_STACK and ¶INV_CHECKLIST_BEFORE_CLOSE
      DISCOVER_SCRIPT="$HOME/.claude/scripts/discover-directives.sh"
      if [ -x "$DISCOVER_SCRIPT" ]; then
        # Extract directoriesOfInterest from .state.json
        DIRS_JSON=$(jq -r '(.directoriesOfInterest // []) | .[]' "$STATE_FILE" 2>/dev/null || true)
        if [ -n "$DIRS_JSON" ]; then
          ALL_DISCOVERED=""
          while IFS= read -r interest_dir; do
            [ -n "$interest_dir" ] || continue
            # Resolve relative paths against PWD
            if [[ "$interest_dir" != /* ]]; then
              interest_dir="$PWD/$interest_dir"
            fi
            [ -d "$interest_dir" ] || continue
            FOUND=$("$DISCOVER_SCRIPT" "$interest_dir" --walk-up --include-shared 2>/dev/null || true)
            if [ -n "$FOUND" ]; then
              ALL_DISCOVERED="${ALL_DISCOVERED}${ALL_DISCOVERED:+$'\n'}${FOUND}"
            fi
          done <<< "$DIRS_JSON"

          echo ""
          echo "## Discovered Directives"
          if [ -n "$ALL_DISCOVERED" ]; then
            # Skill-directive filtering: core directives always shown,
            # skill directives (TESTING.md, PITFALLS.md) only if declared in `directives` array
            CORE_DIRECTIVES="README.md INVARIANTS.md CHECKLIST.md"
            SKILL_DECLARED=$(jq -r '(.directives // []) | .[]' "$STATE_FILE" 2>/dev/null || true)
            FILTERED_DISCOVERED=""
            while IFS= read -r discovered_file; do
              [ -n "$discovered_file" ] || continue
              local_basename=$(basename "$discovered_file")
              # Core directives always pass
              is_core=false
              for core in $CORE_DIRECTIVES; do
                if [ "$local_basename" = "$core" ]; then
                  is_core=true
                  break
                fi
              done
              if [ "$is_core" = "true" ]; then
                FILTERED_DISCOVERED="${FILTERED_DISCOVERED}${FILTERED_DISCOVERED:+$'\n'}${discovered_file}"
                continue
              fi
              # Skill directives: only if declared
              if [ -n "$SKILL_DECLARED" ]; then
                while IFS= read -r declared; do
                  if [ "$local_basename" = "$declared" ]; then
                    FILTERED_DISCOVERED="${FILTERED_DISCOVERED}${FILTERED_DISCOVERED:+$'\n'}${discovered_file}"
                    break
                  fi
                done <<< "$SKILL_DECLARED"
              fi
            done <<< "$(echo "$ALL_DISCOVERED" | sort -u)"
            # Output filtered results
            if [ -n "$FILTERED_DISCOVERED" ]; then
              echo "$FILTERED_DISCOVERED"
            else
              echo "(none — skill directives filtered)"
            fi
            # Seed touchedDirs and discoveredChecklists in .state.json
            while IFS= read -r discovered_file; do
              [ -n "$discovered_file" ] || continue
              discovered_dir=$(dirname "$discovered_file")
              discovered_name=$(basename "$discovered_file")
              # Add to touchedDirs
              jq --arg dir "$discovered_dir" --arg name "$discovered_name" \
                '(.touchedDirs //= {}) | .touchedDirs[$dir] = ((.touchedDirs[$dir] // []) + [$name] | unique)' \
                "$STATE_FILE" | safe_json_write "$STATE_FILE"
              # Add CHECKLIST.md to discoveredChecklists
              if [ "$discovered_name" = "CHECKLIST.md" ]; then
                jq --arg file "$discovered_file" \
                  '(.discoveredChecklists //= []) | if (.discoveredChecklists | index($file)) then . else .discoveredChecklists += [$file] end' \
                  "$STATE_FILE" | safe_json_write "$STATE_FILE"
              fi
            done <<< "$(echo "$ALL_DISCOVERED" | sort -u)"
          else
            echo "(none)"
          fi
        fi
      fi
    fi

    # §CMD_DISCOVER_DELEGATION_TARGETS (runs unconditionally — fresh context needs this)
    # Scans skills for TEMPLATE_*_REQUEST.md to build a delegation targets table.
    echo ""
    echo "## §CMD_DISCOVER_DELEGATION_TARGETS"
    SKILLS_DIR="$HOME/.claude/skills"
    DELEGATION_TARGETS=""
    for tmpl in "$SKILLS_DIR"/*/assets/TEMPLATE_*_REQUEST.md; do
      [ -f "$tmpl" ] || continue
      # Extract skill name from path: ~/.claude/skills/SKILLNAME/assets/...
      SKILL_NAME=$(echo "$tmpl" | sed "s|$SKILLS_DIR/||" | cut -d/ -f1)
      # Extract tag from Tags line
      TMPL_TAG=$(grep '^\*\*Tags\*\*:' "$tmpl" 2>/dev/null | grep -o '#needs-[a-z-]*' | head -1 || true)
      [ -n "$TMPL_TAG" ] || continue
      DELEGATION_TARGETS="${DELEGATION_TARGETS}| ${TMPL_TAG} | /${SKILL_NAME} | ${tmpl} |\n"
    done
    if [ -n "$DELEGATION_TARGETS" ]; then
      echo "| Tag | Skill | Template |"
      echo "|-----|-------|----------|"
      printf "%b" "$DELEGATION_TARGETS"
    else
      echo "(none — no skills have REQUEST templates)"
    fi
    ;;

  update)
    FIELD="${3:?Missing field name}"
    VALUE="${4:?Missing value}"

    if [ ! -f "$STATE_FILE" ]; then
      echo "§CMD_REQUIRE_ACTIVE_SESSION: No .state.json in $DIR — is the session active?" >&2
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
      echo "§CMD_REQUIRE_ACTIVE_SESSION: No .state.json in $DIR — is the session active?" >&2
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
          echo "§CMD_UPDATE_PHASE: Unknown flag '$1'" >&2
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
        echo "§CMD_UPDATE_PHASE: Phase label must start with a number (e.g., '3: Execution', '4.1: Sub-Step'). Got: '$PHASE'" >&2
        exit 1
      fi
      # Reject alpha-style phase labels (e.g., "5b: Triage" — must use "5.1: Triage")
      if echo "$PHASE" | grep -qE '^[0-9]+[a-zA-Z]'; then
        echo "§CMD_UPDATE_PHASE: Alpha-style phase labels are not allowed. Use 'N.M: Name' format (e.g., '5.1: Finding Triage' not '5b: Finding Triage'). Got: '$PHASE'" >&2
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

      # Case 1b: Sub-phases are optional — skip to next major is always allowed
      # If the next declared phase is a sub-phase (minor > 0) of the current major,
      # also allow jumping to the next major phase (current_major + 1, minor 0).
      # This handles: 3.0 → 4.0 when 3.1 exists (skipping optional 3.1).
      if [ "$IS_SEQUENTIAL" = "false" ] && [ -n "$NEXT_MAJOR" ] && [ "$NEXT_MINOR" -gt 0 ] && [ "$NEXT_MAJOR" = "$CUR_MAJOR" ]; then
        NEXT_MAJOR_PHASE=$(( CUR_MAJOR + 1 ))
        if [ "$REQ_MAJOR" = "$NEXT_MAJOR_PHASE" ] && [ "$REQ_MINOR" = "0" ]; then
          IS_SEQUENTIAL=true
        fi
      fi

      # Case 1c: From a sub-phase, allow jumping to the next major phase
      # If current is N.M (minor > 0), allow transition to (N+1).0
      if [ "$IS_SEQUENTIAL" = "false" ] && [ "$CUR_MINOR" -gt 0 ]; then
        NEXT_MAJOR_FROM_SUB=$(( CUR_MAJOR + 1 ))
        if [ "$REQ_MAJOR" = "$NEXT_MAJOR_FROM_SUB" ] && [ "$REQ_MINOR" = "0" ]; then
          IS_SEQUENTIAL=true
        fi
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
          echo "§CMD_UPDATE_PHASE: Non-sequential phase transition rejected." >&2
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
      echo "§CMD_REQUIRE_ACTIVE_SESSION: No .state.json in $DIR — is the session active?" >&2
      exit 1
    fi

    jq --arg file "$FILE" --arg ts "$(timestamp)" \
      '.targetFile = $file | .lastHeartbeat = $ts' \
      "$STATE_FILE" | safe_json_write "$STATE_FILE"

    echo "Target file: $FILE"
    ;;

  deactivate)
    if [ ! -f "$STATE_FILE" ]; then
      echo "§CMD_REQUIRE_ACTIVE_SESSION: No .state.json in $DIR — is the session active?" >&2
      exit 1
    fi

    # Parse optional flags: --keywords "kw1,kw2,...", --user-approved "reason"
    KEYWORDS=""
    SKIP_DEBRIEF=""
    shift 2  # Remove action, dir
    while [ $# -gt 0 ]; do
      case "$1" in
        --keywords)
          KEYWORDS="${2:?--keywords requires a value}"
          shift 2
          ;;
        --user-approved)
          SKIP_DEBRIEF="${2:?--user-approved requires a reason (quote the user)}"
          shift 2
          ;;
        *)
          echo "§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL: Unknown flag '$1'" >&2
          shift
          ;;
      esac
    done

    # Read REQUIRED description from stdin (1-3 lines for RAG/search)
    DESCRIPTION=""
    if [ ! -t 0 ]; then
      DESCRIPTION=$(cat)
    fi

    # --- Collect all validation errors before exiting ---
    # All gates append to DEACTIVATE_ERRORS instead of exiting immediately.
    # This lets the agent see ALL issues at once and fix them in a single pass.
    DEACTIVATE_ERRORS=()

    # --- Description Gate (§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL) ---
    if [ -z "$DESCRIPTION" ]; then
      DEACTIVATE_ERRORS+=("$(printf '%s\n%s\n%s\n%s' \
        "§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL: Description is required. Pipe 1-3 lines via stdin:" \
        "  session.sh deactivate <path> [--keywords 'kw1,kw2'] <<'EOF'" \
        "  What was done in this session (1-3 lines)" \
        "  EOF")")
    fi

    # --- Debrief Gate (§CMD_DEBRIEF_BEFORE_CLOSE) ---
    # Check if the skill's debrief file exists before allowing deactivation
    # Derives filename from debriefTemplate in .state.json (e.g., TEMPLATE_TESTING.md → TESTING.md)
    if [ -z "$SKIP_DEBRIEF" ]; then
      DEBRIEF_TEMPLATE=$(jq -r '.debriefTemplate // ""' "$STATE_FILE" 2>/dev/null || echo "")
      if [ -n "$DEBRIEF_TEMPLATE" ]; then
        DEBRIEF_BASENAME=$(basename "$DEBRIEF_TEMPLATE")
        DEBRIEF_NAME="${DEBRIEF_BASENAME#TEMPLATE_}"
        DEBRIEF_FILE="$DIR/$DEBRIEF_NAME"
        if [ ! -f "$DEBRIEF_FILE" ]; then
          DEACTIVATE_ERRORS+=("$(printf '%s\n%s\n%s\n%s\n%s' \
            "§CMD_DEBRIEF_BEFORE_CLOSE: Cannot deactivate — no debrief file found." \
            "  Expected: $DEBRIEF_NAME in $DIR" \
            "" \
            "  To fix: Write the debrief via §CMD_GENERATE_DEBRIEF_USING_TEMPLATE." \
            "  To skip: session.sh deactivate $DIR --user-approved \"Reason: [quote user's words]\"")")
        fi
      fi
    fi

    # --- Checklist Gate (¶INV_CHECKLIST_BEFORE_CLOSE) ---
    # Requires checkPassed=true (set by session.sh check) if any checklists were discovered
    DISCOVERED=$(jq -r '(.discoveredChecklists // []) | length' "$STATE_FILE" 2>/dev/null || echo "0")
    if [ "$DISCOVERED" -gt 0 ]; then
      CHECK_PASSED=$(jq -r '.checkPassed // false' "$STATE_FILE" 2>/dev/null || echo "false")
      if [ "$CHECK_PASSED" != "true" ]; then
        # Build checklist error with dynamic list
        checklist_err="$(printf '%s\n%s\n%s' \
          "¶INV_CHECKLIST_BEFORE_CLOSE: Cannot deactivate — $DISCOVERED checklist(s) discovered but checkPassed is not set." \
          "" \
          "  Discovered checklists:")"
        while IFS= read -r f; do
          checklist_err+=$'\n'"    - $f"
        done < <(jq -r '(.discoveredChecklists // []) | .[]' "$STATE_FILE" 2>/dev/null)
        checklist_err+="$(printf '\n%s\n%s\n%s\n%s\n%s' \
          "" \
          "  To fix: Run §CMD_PROCESS_CHECKLISTS — read each checklist, evaluate items, then call:" \
          "    session.sh check $DIR <<'EOF'" \
          "    ## CHECKLIST: /path/to/CHECKLIST.md" \
          "    - [x] Verified item" \
          "    EOF")"
        DEACTIVATE_ERRORS+=("$checklist_err")
      fi
    fi

    # --- Proof Gate (¶INV_PROVABLE_DEBRIEF_PIPELINE) ---
    # Requires all declared provableDebriefItems to have proof in provenItems
    PROVABLE_JSON=$(jq -r '(.provableDebriefItems // null)' "$STATE_FILE" 2>/dev/null || echo "null")
    if [ "$PROVABLE_JSON" != "null" ]; then
      PROVABLE_COUNT=$(echo "$PROVABLE_JSON" | jq 'length')
      if [ "$PROVABLE_COUNT" -gt 0 ]; then
        PROVEN_JSON=$(jq -r '(.provenItems // {})' "$STATE_FILE" 2>/dev/null || echo "{}")
        MISSING_PROOF=()
        while IFS= read -r item; do
          [ -n "$item" ] || continue
          HAS_PROOF=$(echo "$PROVEN_JSON" | jq --arg k "$item" 'has($k)')
          if [ "$HAS_PROOF" != "true" ]; then
            MISSING_PROOF+=("$item")
          fi
        done < <(echo "$PROVABLE_JSON" | jq -r '.[]')

        if [ ${#MISSING_PROOF[@]} -gt 0 ]; then
          proof_err="$(printf '%s\n%s\n%s' \
            "¶INV_PROVABLE_DEBRIEF_PIPELINE: Cannot deactivate — ${#MISSING_PROOF[@]} debrief pipeline item(s) lack proof." \
            "" \
            "  Missing proof for:")"
          for mp in "${MISSING_PROOF[@]}"; do
            proof_err+=$'\n'"    - $mp"
          done
          proof_err+="$(printf '\n%s\n%s\n%s\n%s\n%s' \
            "" \
            "  To fix: Execute each pipeline step, then run:" \
            "    session.sh prove $DIR <<'EOF'" \
            "    §CMD_NAME: ran: description / skipped: reason" \
            "    EOF")"
          DEACTIVATE_ERRORS+=("$proof_err")
        fi
      fi
    fi

    # --- Output all collected errors and exit ---
    if [ ${#DEACTIVATE_ERRORS[@]} -gt 0 ]; then
      for i in "${!DEACTIVATE_ERRORS[@]}"; do
        echo "${DEACTIVATE_ERRORS[$i]}" >&2
        # Blank line between errors (not after the last one)
        if [ "$i" -lt $((${#DEACTIVATE_ERRORS[@]} - 1)) ]; then
          echo "" >&2
        fi
      done
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
      echo "§CMD_REQUIRE_ACTIVE_SESSION: No .state.json in $DIR — is the session active?" >&2
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
      echo "§CMD_REANCHOR_AFTER_RESTART: No watchdog active (WATCHDOG_PID not set)."
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

  check)
    # Validate session before deactivation: tag scan + checklist processing + request files
    #
    # Three validations (all must pass for checkPassed=true):
    #   1. TAG SCAN: Scans session .md files for bare unescaped inline #needs-*/#active-*/#done-* tags.
    #      If found, reports them and exits 1. Agent must promote or acknowledge each tag,
    #      then re-run check. Skip with tagCheckPassed=true in .state.json.
    #   2. CHECKLIST: Validates checklist processing results (existing behavior, requires stdin).
    #      Skip with no discoveredChecklists in .state.json.
    #   3. REQUEST FILES: Validates that all requestFiles are fulfilled (have ## Response section
    #      and no bare #needs-* on Tags line). Skip with no requestFiles in .state.json
    #      or requestCheckPassed=true.
    #
    # Usage:
    #   session.sh check <path>                          # Tag scan only (no checklists)
    #   session.sh check <path> <<'EOF'                  # Tag scan + checklist validation
    #   ## CHECKLIST: /absolute/path/to/CHECKLIST.md
    #   - [x] Item that was verified
    #   EOF
    #
    # On success: sets checkPassed=true in .state.json
    # On failure: exits 1 with descriptive error

    if [ ! -f "$STATE_FILE" ]; then
      echo "§CMD_REQUIRE_ACTIVE_SESSION: No .state.json in $DIR — is the session active?" >&2
      exit 1
    fi

    # ─── Validation 1: Tag Scan (¶INV_ESCAPE_BY_DEFAULT) ───
    # Scan session .md files for bare unescaped inline lifecycle tags.
    # Skip if tagCheckPassed is already true (tags were already addressed).
    TAG_CHECK_PASSED=$(jq -r '.tagCheckPassed // false' "$STATE_FILE" 2>/dev/null || echo "false")

    if [ "$TAG_CHECK_PASSED" != "true" ]; then
      # Scan all .md files in session dir for bare lifecycle tags
      # Pattern: #needs-*, #active-*, #done-* (the lifecycle tag families)
      TAG_PATTERN='#(needs|active|done)-[a-z]+'
      BARE_TAGS=""

      if [ -d "$DIR" ]; then
        # Find all .md files in session dir (not recursive into subdirs beyond session)
        while IFS= read -r md_file; do
          [ -f "$md_file" ] || continue
          # Search for lifecycle tags, excluding:
          #   - Tags-line matches (**Tags**: ...)
          #   - Backtick-escaped references are handled per-tag in the loop below
          #   - .state.json (not .md, but just in case)
          MATCHES=$(grep -nE "$TAG_PATTERN" "$md_file" 2>/dev/null \
            | grep -v '^\*\*Tags\*\*:' \
            | grep -vE '[0-9]+:\*\*Tags\*\*:' \
            || true)

          if [ -n "$MATCHES" ]; then
            # For each match line, extract and validate
            while IFS= read -r match_line; do
              [ -n "$match_line" ] || continue
              LINE_NUM=$(echo "$match_line" | cut -d: -f1)
              LINE_TEXT=$(echo "$match_line" | cut -d: -f2-)

              # Double-check: is this line the Tags line? (line starts with **Tags**:)
              if echo "$LINE_TEXT" | grep -qE '^\*\*Tags\*\*:'; then
                continue
              fi

              # Double-check: is the tag backtick-escaped in this line?
              # Extract each lifecycle tag from the line and check if it's escaped
              TAGS_IN_LINE=$(echo "$LINE_TEXT" | grep -oE '#(needs|active|done)-[a-z]+' || true)
              for tag in $TAGS_IN_LINE; do
                # Check if this specific tag is backtick-escaped in the line
                if echo "$LINE_TEXT" | grep -q "\`${tag}\`"; then
                  continue  # Escaped — skip
                fi
                # Bare tag found — record it
                BARE_TAGS="${BARE_TAGS}${md_file}:${LINE_NUM}: ${tag} — $(echo "$LINE_TEXT" | sed 's/^[[:space:]]*//')\n"
              done
            done <<< "$MATCHES"
          fi
        done < <(find "$DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null)
      fi

      if [ -n "$BARE_TAGS" ]; then
        echo "¶INV_ESCAPE_BY_DEFAULT: Bare inline lifecycle tags found in session artifacts." >&2
        echo "" >&2
        echo "  Each bare tag must be addressed before synthesis:" >&2
        echo "    PROMOTE — Create a request file + backtick-escape the inline tag" >&2
        echo "    ACKNOWLEDGE — Mark as intentional (tag stays bare)" >&2
        echo "    ESCAPE — Just backtick-escape it (reference, not a work item)" >&2
        echo "" >&2
        echo "  Bare tags found:" >&2
        printf "    %b" "$BARE_TAGS" | while IFS= read -r line; do
          [ -n "$line" ] && echo "    $line" >&2
        done
        echo "" >&2
        echo "  After addressing all tags, set tagCheckPassed:" >&2
        echo "    session.sh update $DIR tagCheckPassed true" >&2
        echo "  Then re-run: session.sh check $DIR" >&2
        exit 1
      fi

      # No bare tags found — mark tag check as passed
      jq --arg ts "$(timestamp)" \
        '.tagCheckPassed = true | .lastHeartbeat = $ts' \
        "$STATE_FILE" | safe_json_write "$STATE_FILE"
      echo "§CMD_PROCESS_TAG_PROMOTIONS: Tag scan passed — no bare inline lifecycle tags."
    else
      echo "§CMD_PROCESS_TAG_PROMOTIONS: Tag scan already passed."
    fi

    # ─── Validation 2: Checklist Processing (¶INV_CHECKLIST_BEFORE_CLOSE) ───
    # Read checklist results from stdin
    CHECK_INPUT=""
    if [ ! -t 0 ]; then
      CHECK_INPUT=$(cat)
    fi

    # Get discovered checklists from .state.json
    DISCOVERED_JSON=$(jq -r '(.discoveredChecklists // [])' "$STATE_FILE" 2>/dev/null || echo "[]")
    DISCOVERED_COUNT=$(echo "$DISCOVERED_JSON" | jq 'length')

    if [ "$DISCOVERED_COUNT" -eq 0 ]; then
      # No checklists discovered — checklist check passes trivially
      echo "§CMD_PROCESS_CHECKLISTS: No checklists discovered — passed trivially."
    else
      # Checklists discovered — stdin required
      if [ -z "$CHECK_INPUT" ]; then
        echo "§CMD_PROCESS_CHECKLISTS: Checklists discovered but no results provided on stdin." >&2
        echo "" >&2
        echo "  Usage: session.sh check <path> <<'EOF'" >&2
        echo "  ## CHECKLIST: /path/to/CHECKLIST.md" >&2
        echo "  - [x] Verified item" >&2
        echo "  - [ ] Not applicable (reason)" >&2
        echo "  EOF" >&2
        exit 1
      fi

      # Extract all ## CHECKLIST: paths from stdin
      SUBMITTED_PATHS=$(echo "$CHECK_INPUT" | grep -oE '^## CHECKLIST: .+' | sed 's/^## CHECKLIST: //' || true)

      # Validate: every discovered checklist has a matching block
      MISSING_PATHS=()
      while IFS= read -r discovered_path; do
        [ -n "$discovered_path" ] || continue
        if ! echo "$SUBMITTED_PATHS" | grep -qF "$discovered_path"; then
          MISSING_PATHS+=("$discovered_path")
        fi
      done < <(echo "$DISCOVERED_JSON" | jq -r '.[]')

      if [ ${#MISSING_PATHS[@]} -gt 0 ]; then
        echo "§CMD_PROCESS_CHECKLISTS: Checklist validation failed — ${#MISSING_PATHS[@]} missing." >&2
        echo "" >&2
        echo "  Missing checklist blocks:" >&2
        for mp in "${MISSING_PATHS[@]}"; do
          echo "    - $mp" >&2
        done
        echo "" >&2
        echo "  Each discovered checklist needs a matching '## CHECKLIST: /path' block in stdin." >&2
        exit 1
      fi

      # Validate: each block has at least one checklist item (- [x] or - [ ])
      EMPTY_BLOCKS=()
      while IFS= read -r discovered_path; do
        [ -n "$discovered_path" ] || continue
        BLOCK=$(echo "$CHECK_INPUT" | awk -v path="## CHECKLIST: $discovered_path" '
          $0 == path { found=1; next }
          found && /^## / { found=0 }
          found { print }
        ')
        ITEM_COUNT=$(echo "$BLOCK" | grep -cE '^\s*- \[(x| )\]' 2>/dev/null) || ITEM_COUNT=0
        if [ "$ITEM_COUNT" -eq 0 ]; then
          EMPTY_BLOCKS+=("$discovered_path")
        fi
      done < <(echo "$DISCOVERED_JSON" | jq -r '.[]')

      if [ ${#EMPTY_BLOCKS[@]} -gt 0 ]; then
        echo "§CMD_PROCESS_CHECKLISTS: Checklist blocks have no items — ${#EMPTY_BLOCKS[@]} empty." >&2
        echo "" >&2
        echo "  Empty blocks (need at least one - [x] or - [ ] item):" >&2
        for eb in "${EMPTY_BLOCKS[@]}"; do
          echo "    - $eb" >&2
        done
        exit 1
      fi

      echo "§CMD_PROCESS_CHECKLISTS: All $DISCOVERED_COUNT checklist(s) validated."
    fi

    # ─── Validation 3: Request Files (¶INV_REQUEST_BEFORE_CLOSE) ───
    # Validate that all requestFiles are fulfilled before deactivation.
    # All files: must (a) exist, (b) have no bare #needs-* tags anywhere (backtick-escaped excluded).
    # Formal REQUEST files (filename contains "REQUEST"): additionally must have ## Response section.
    # Skip if requestCheckPassed is already true or requestFiles is empty.
    REQUEST_CHECK_PASSED=$(jq -r '.requestCheckPassed // false' "$STATE_FILE" 2>/dev/null || echo "false")
    REQUEST_FILES_JSON=$(jq -r '(.requestFiles // [])' "$STATE_FILE" 2>/dev/null || echo "[]")
    REQUEST_FILES_COUNT=$(echo "$REQUEST_FILES_JSON" | jq 'length')

    if [ "$REQUEST_CHECK_PASSED" = "true" ]; then
      echo "¶INV_REQUEST_BEFORE_CLOSE: Request files check already passed."
    elif [ "$REQUEST_FILES_COUNT" -eq 0 ]; then
      echo "¶INV_REQUEST_BEFORE_CLOSE: No request files declared — passed."
    else
      REQUEST_FAILURES=()

      while IFS= read -r req_file; do
        [ -n "$req_file" ] || continue

        # (a) File must exist
        if [ ! -f "$req_file" ]; then
          REQUEST_FAILURES+=("$req_file: file not found")
          continue
        fi

        req_basename=$(basename "$req_file")

        # Formal REQUEST files additionally need ## Response
        if [[ "$req_basename" == *REQUEST* ]]; then
          HAS_RESPONSE=$(grep -c '^## Response' "$req_file" 2>/dev/null) || HAS_RESPONSE=0
          if [ "$HAS_RESPONSE" -eq 0 ]; then
            REQUEST_FAILURES+=("$req_file: missing ## Response section")
            continue
          fi
        fi

        # (b) No bare #needs-* tags anywhere (applies to ALL file types)
        BARE_NEEDS=""
        while IFS= read -r match_line; do
          [ -n "$match_line" ] || continue
          line_num=$(echo "$match_line" | cut -d: -f1)
          line_text=$(echo "$match_line" | cut -d: -f2-)

          tags_in_line=$(echo "$line_text" | grep -oE '#needs-[a-z-]+' || true)
          for tag in $tags_in_line; do
            # Skip if backtick-escaped
            if echo "$line_text" | grep -q "\`${tag}\`"; then
              continue
            fi
            BARE_NEEDS="${BARE_NEEDS}  L${line_num}: ${tag}\n"
          done
        done < <(grep -nE '#needs-[a-z-]+' "$req_file" 2>/dev/null || true)

        if [ -n "$BARE_NEEDS" ]; then
          REQUEST_FAILURES+=("$req_file: bare #needs-* tags remain:\n${BARE_NEEDS}")
          continue
        fi
      done < <(echo "$REQUEST_FILES_JSON" | jq -r '.[]')

      if [ ${#REQUEST_FAILURES[@]} -gt 0 ]; then
        echo "¶INV_REQUEST_BEFORE_CLOSE: Request files validation failed — ${#REQUEST_FAILURES[@]} unfulfilled." >&2
        echo "" >&2
        echo "  Unfulfilled request files:" >&2
        for rf in "${REQUEST_FAILURES[@]}"; do
          printf "    - %b\n" "$rf" >&2
        done
        echo "" >&2
        echo "  All request files must:" >&2
        echo "    1. Exist at the declared path" >&2
        echo "    2. Have no bare #needs-* tags anywhere (all resolved or backtick-escaped)" >&2
        echo "  Formal REQUEST files (*REQUEST* in filename) must additionally:" >&2
        echo "    3. Have a '## Response' section with fulfillment details" >&2
        echo "" >&2
        echo "  After fulfilling all requests, re-run: session.sh check $DIR" >&2
        exit 1
      fi

      # All request files fulfilled — mark passed
      jq --arg ts "$(timestamp)" \
        '.requestCheckPassed = true | .lastHeartbeat = $ts' \
        "$STATE_FILE" | safe_json_write "$STATE_FILE"
      echo "¶INV_REQUEST_BEFORE_CLOSE: All $REQUEST_FILES_COUNT request file(s) validated."
    fi

    # ─── All Validations Passed ───
    jq --arg ts "$(timestamp)" \
      '.checkPassed = true | .lastHeartbeat = $ts' \
      "$STATE_FILE" | safe_json_write "$STATE_FILE"

    echo "§CMD_CHECK: All checks passed."
    ;;

  request-template)
    # Output a REQUEST template to stdout for a given #needs-* tag
    # Usage: session.sh request-template '#needs-implementation'
    # Discovery: scans ~/.claude/skills/*/assets/TEMPLATE_*_REQUEST.md for matching tag on Tags line
    TAG="${2:?Usage: session.sh request-template '#needs-xxx'}"
    SKILLS_DIR="$HOME/.claude/skills"

    # Ensure trailing slash for BSD grep compatibility
    TEMPLATE_FILE=$(grep -rl "^\*\*Tags\*\*:.*${TAG}" "$SKILLS_DIR"/*/assets/TEMPLATE_*_REQUEST.md 2>/dev/null | head -1 || true)

    if [ -n "$TEMPLATE_FILE" ] && [ -f "$TEMPLATE_FILE" ]; then
      cat "$TEMPLATE_FILE"
    else
      echo "§CMD_RESOLVE_REQUEST_TEMPLATE: No REQUEST template found for tag '$TAG'" >&2
      echo "" >&2
      echo "Available templates:" >&2
      for tmpl in "$SKILLS_DIR"/*/assets/TEMPLATE_*_REQUEST.md; do
        [ -f "$tmpl" ] || continue
        tmpl_tag=$(grep '^\*\*Tags\*\*:' "$tmpl" 2>/dev/null | grep -o '#needs-[a-z-]*' | head -1 || true)
        [ -n "$tmpl_tag" ] && echo "  $tmpl_tag  →  $tmpl" >&2
      done
      exit 1
    fi
    ;;

  prove)
    # Write proof of debrief pipeline execution to .state.json
    #
    # Usage:
    #   session.sh prove <path> <<'EOF'
    #   §CMD_MANAGE_DIRECTIVES: skipped: no files touched
    #   §CMD_PROCESS_DELEGATIONS: ran: 2 bare tags processed
    #   §CMD_CAPTURE_SIDE_DISCOVERIES: skipped: no side discoveries
    #   §CMD_MANAGE_ALERTS: skipped: no alerts
    #   §CMD_REPORT_LEFTOVER_WORK: ran: 1 item reported
    #   /delegation-review: skipped: no #needs-X tags
    #   EOF
    #
    # Each line: §CMD_NAME: <free text proof>
    # Replaces .provenItems entirely (not merge).
    # Deactivation gate checks provenItems keys against provableDebriefItems.

    if [ ! -f "$STATE_FILE" ]; then
      echo "§CMD_REQUIRE_ACTIVE_SESSION: No .state.json in $DIR — is the session active?" >&2
      exit 1
    fi

    # Read proof from stdin
    PROOF_INPUT=""
    if [ ! -t 0 ]; then
      PROOF_INPUT=$(cat)
    fi

    if [ -z "$PROOF_INPUT" ]; then
      echo "¶INV_PROVABLE_DEBRIEF_PIPELINE: No proof provided on stdin." >&2
      echo "" >&2
      echo "  Usage: session.sh prove <path> <<'EOF'" >&2
      echo "  §CMD_MANAGE_DIRECTIVES: skipped: no files touched" >&2
      echo "  §CMD_PROCESS_DELEGATIONS: ran: 2 bare tags processed" >&2
      echo "  EOF" >&2
      exit 1
    fi

    # Parse proof lines into JSON object
    # Format: §CMD_NAME: <text> → {"§CMD_NAME": "<text>"}
    PROOF_JSON="{}"
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      # Extract command name (everything before first ': ')
      CMD_NAME=$(echo "$line" | sed -n 's/^\(§CMD_[A-Z_]*\): .*/\1/p')
      if [ -z "$CMD_NAME" ]; then
        continue  # Skip non-matching lines
      fi
      # Extract proof text (everything after first ': ')
      PROOF_TEXT=$(echo "$line" | sed "s/^${CMD_NAME}: //")
      PROOF_JSON=$(echo "$PROOF_JSON" | jq --arg k "$CMD_NAME" --arg v "$PROOF_TEXT" '.[$k] = $v')
    done <<< "$PROOF_INPUT"

    # Count proven items
    PROVEN_COUNT=$(echo "$PROOF_JSON" | jq 'length')
    if [ "$PROVEN_COUNT" -eq 0 ]; then
      echo "¶INV_PROVABLE_DEBRIEF_PIPELINE: No valid proof lines found in input." >&2
      echo "  Each line must match: §CMD_NAME: <proof text>" >&2
      exit 1
    fi

    # Write provenItems to .state.json (replace, not merge)
    jq --argjson proof "$PROOF_JSON" --arg ts "$(timestamp)" \
      '.provenItems = $proof | .lastHeartbeat = $ts' \
      "$STATE_FILE" | safe_json_write "$STATE_FILE"

    echo "¶INV_PROVABLE_DEBRIEF_PIPELINE: Proof recorded for $PROVEN_COUNT item(s)."
    echo "$PROOF_JSON" | jq -r 'to_entries[] | "  \(.key): \(.value)"'
    ;;

  *)
    echo "§CMD_MAINTAIN_SESSION_DIR: Unknown action '$ACTION'. Use: init, activate, update, find, phase, target, deactivate, restart, check, prove, request-template" >&2
    exit 1
    ;;
esac
