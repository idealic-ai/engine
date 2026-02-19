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
#   session.sh continue <path>                     # Resume after context overflow (clears loading, resets heartbeat)
#   session.sh target <path> <file>               # Shortcut: update targetFile (for status line)
#   session.sh deactivate <path> [--keywords 'kw1,kw2'] <<DESCRIPTION
#                                                  # Set lifecycle=completed (gate re-engages)
#                                                  # REQUIRES 1-3 line description on stdin for RAG/search
#                                                  # --keywords: comma-separated search keywords (stored in .state.json)
#                                                  # Outputs: Related sessions from RAG search (if GEMINI_API_KEY set)
#   session.sh idle <path> [--keywords 'kw1,kw2'] <<DESCRIPTION
#                                                  # Set lifecycle=idle (restricted gate, reactivatable)
#                                                  # Like deactivate but session stays alive for fast-track reactivation
#                                                  # Clears PID (null sentinel), stores description + keywords
#   session.sh dehydrate <path> <<JSON              # Merge dehydrated context JSON into .state.json
#   session.sh restart <path>                      # Set status=ready-to-kill, signal wrapper
#   session.sh clear <path>                        # Clear context and restart fresh (no prompt)
#                                                  # TMUX: /clear keystroke, Watchdog: kill+restart, Neither: manual
#   session.sh check <path> [<<STDIN]                 # Tag scan + checklist validation (sets checkPassed=true)
#   session.sh find                                 # Find session dir for current process (read-only)
#   session.sh evaluate-guards <path>                # Evaluate guard rules, populate pendingGuards[]
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
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_PHASE_ENFORCEMENT — Phase transition enforcement via session.sh phase
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — Graceful degradation without fleet/tmux
#     ¶INV_QUESTION_GATE_OVER_TEXT_GATE — User approval gates (--user-approved)
#   Commands: (~/.claude/.directives/COMMANDS.md)
#     §CMD_MAINTAIN_SESSION_DIR — Session directory management
#     §CMD_PARSE_PARAMETERS — Session activation with JSON params
#     §CMD_UPDATE_PHASE — Phase tracking and enforcement
#     §CMD_CLOSE_SESSION — Session completion
#     §CMD_RECOVER_SESSION — Restart recovery
#     §CMD_REQUIRE_ACTIVE_SESSION — Session gate enforcement
#     §CMD_RESOLVE_REQUEST_TEMPLATE — Tag-to-skill template resolution

set -euo pipefail

# Source shared utilities (timestamp, pid_exists, safe_json_write)
source "$HOME/.claude/scripts/lib.sh"

ACTION="${1:?Usage: session.sh <init|activate|update|find|restart> <path> [args...]}"

# DIR is required for all commands except 'find' and 'request-template'
if [ "$ACTION" = "find" ] || [ "$ACTION" = "request-template" ]; then
  DIR=""
elif [ "$ACTION" = "continue" ] && [ -z "${2:-}" ]; then
  DIR=""  # Auto-detect in the continue handler
else
  DIR=$(resolve_session_path "${2:?Missing directory path}")
fi

STATE_FILE="$DIR/.state.json"

# Helper: Auto-detect fleet pane ID from tmux
# Returns composite fleetPaneId (session:window:pane) if inside fleet, empty otherwise
get_fleet_pane_id() {
  # Use fleet.sh pane-id for composite format (session:window:pane)
  # This is the canonical source of truth for fleet identity
  "$HOME/.claude/scripts/fleet.sh" pane-id 2>/dev/null || echo ""
}

# Helper: Validate a JSON instance against a JSON Schema
# Usage: validate_json_schema <schema_json_string> <instance_json_string>
# Returns: 0 if valid, 1 if invalid (errors on stderr), 2 if tool missing
validate_json_schema() {
  local schema_json="$1"
  local instance_json="$2"
  local validate_sh="$HOME/.claude/tools/json-schema-validate/validate.sh"

  if [ ! -x "$validate_sh" ]; then
    echo "validate_json_schema: validate.sh not found at $validate_sh" >&2
    return 2
  fi

  local tmp_instance
  tmp_instance=$(mktemp)
  trap "rm -f '$tmp_instance'" RETURN

  echo "$instance_json" > "$tmp_instance"
  echo "$schema_json" | "$validate_sh" --schema-stdin "$tmp_instance"
}

# Helper: Extract proof schema JSON from a CMD_*.md file
# Usage: extract_proof_schema <cmd_file_path>
# Returns: JSON Schema string, or empty if not found
extract_proof_schema() {
  local cmd_file="$1"
  awk '/## PROOF FOR/,0{if(/```json/){f=1;next}if(/```/){f=0;next}if(f)print}' "$cmd_file" 2>/dev/null || echo ""
}

# Static fields extracted from SKILL.md — engine-authoritative
# These fields are defined in the skill's SKILL.md JSON block and cannot be overridden by agents
SKILL_STATIC_FIELDS='["taskType","phases","nextSkills","directives","modes","logTemplate","debriefTemplate","planTemplate","requestTemplate","responseTemplate"]'

# Extract the first JSON block from a SKILL.md file and resolve relative paths
# Usage: extract_skill_json <skill_name>
# Returns: JSON string with resolved paths, or empty string if no SKILL.md / no JSON block
extract_skill_json() {
  local skill="$1"
  local skill_md="$HOME/.claude/skills/$skill/SKILL.md"

  if [ ! -f "$skill_md" ]; then
    echo ""
    return 0
  fi

  # Extract first ```json block
  local raw_json
  raw_json=$(awk '/^```json$/,/^```$/' "$skill_md" | sed '/^```/d')

  if [ -z "$raw_json" ] || ! echo "$raw_json" | jq empty 2>/dev/null; then
    echo ""
    return 0
  fi

  # Resolve relative paths to absolute (skill_dir/relative_path)
  local skill_dir="$HOME/.claude/skills/$skill"
  echo "$raw_json" | jq --arg dir "$skill_dir" '
    def resolve_path: if . and (. | startswith("/") | not) then "\($dir)/\(.)" else . end;
    (if has("planTemplate") then .planTemplate |= resolve_path else . end) |
    (if has("logTemplate") then .logTemplate |= resolve_path else . end) |
    (if has("debriefTemplate") then .debriefTemplate |= resolve_path else . end) |
    (if has("requestTemplate") then .requestTemplate |= resolve_path else . end) |
    (if has("responseTemplate") then .responseTemplate |= resolve_path else . end) |
    (if has("modes") then .modes |= (to_entries | map(
      if .value | has("file") then .value.file |= resolve_path else . end
    ) | from_entries) else . end)
  '
}

# Shared jq helper functions for phase label operations
# Used by both activate (proof display) and phase (enforcement + proof display)
JQ_LABEL_HELPERS='
  def phase_lbl: if has("label") then .label elif .minor == 0 then "\(.major)" else "\(.major).\(.minor)" end;
  def sort_key: phase_lbl | split(".") | map(if test("^[0-9]+$") then ("000" + .)[-3:] else . end) | join(".");
'

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

    # Parse optional flags: --fleet-pane NAME, --target-file FILE, --user-approved REASON, --fast-track
    # PID comes from CLAUDE_SUPERVISOR_PID env var (exported by run.sh)
    TARGET_PID="${CLAUDE_SUPERVISOR_PID:-$PPID}"
    FLEET_PANE=""
    TARGET_FILE=""
    USER_APPROVED=""
    FAST_TRACK=""
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
        --fast-track)
          FAST_TRACK=true
          shift
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

        # --- Schema Validation (§CMD_PARSE_PARAMETERS) ---
        # Extract JSON Schema from CMD_PARSE_PARAMETERS.md and validate stdin JSON.
        # Only dynamic fields are required from agents — static fields come from SKILL.md.
        PARAMS_CMD_FILE="$HOME/.claude/engine/.directives/commands/CMD_PARSE_PARAMETERS.md"
        PARAMS_SCHEMA=""
        if [ -f "$PARAMS_CMD_FILE" ]; then
          PARAMS_SCHEMA=$(awk '/```json/{f=1;next}/```/{if(f){f=0;exit}}f' "$PARAMS_CMD_FILE" 2>/dev/null || echo "")
        fi
        if [ -n "$PARAMS_SCHEMA" ] && echo "$PARAMS_SCHEMA" | jq empty 2>/dev/null; then
          if ! validate_json_schema "$PARAMS_SCHEMA" "$STDIN_JSON" 2>/tmp/params_validation_err; then
            echo "§CMD_PARSE_PARAMETERS: Session parameters validation failed:" >&2
            cat /tmp/params_validation_err >&2
            rm -f /tmp/params_validation_err
            exit 1
          fi
          rm -f /tmp/params_validation_err
        else
          # Fallback: hardcoded required fields check (if schema extraction fails)
          REQUIRED_FIELDS="taskSummary scope directoriesOfInterest contextPaths requestFiles extraInfo"
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
    fi

    # --- SKILL.md Static Field Extraction ---
    # Extract static fields from SKILL.md JSON block (engine-authoritative)
    SKILL_JSON=""
    SKILL_JSON=$(extract_skill_json "$SKILL")

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
      jq 'del(.pid)' "$other_file" | safe_json_write "$other_file"
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
    # unless --user-approved or --fast-track is provided
    # Exception: "do" skill is always reactivatable (ad-hoc work, meant to be reusable)
    if [ -f "$STATE_FILE" ] && [ "$SKILL" != "do" ] && [ -z "$FAST_TRACK" ]; then
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

          if [ -n "${WORKSPACE:-}" ]; then
            JQ_EXPR="$JQ_EXPR | .workspace = \$ws"
            JQ_ARGS+=(--arg ws "$WORKSPACE")
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

          # Apply SKILL.md static fields (engine-authoritative) — overwrites any agent-provided static values
          if [ -n "$SKILL_JSON" ]; then
            jq -s --argjson fields "$SKILL_STATIC_FIELDS" '
              .[0] * (.[1] | with_entries(select(.key as $k | $fields | index($k))))
            ' "$STATE_FILE" <(echo "$SKILL_JSON") | safe_json_write "$STATE_FILE"
          fi

          ACTIVATED=true
          if [ "$EXISTING_SKILL" != "$SKILL" ]; then
            SHOULD_SCAN=true
            # Derive currentPhase from new phases array (if provided by new skill)
            HAS_NEW_PHASES=$(jq 'has("phases") and (.phases | length > 0)' "$STATE_FILE" 2>/dev/null || echo "false")
            if [ "$HAS_NEW_PHASES" = "true" ]; then
              jq '
                def phase_lbl: if has("label") then .label elif .minor == 0 then "\(.major)" else "\(.major).\(.minor)" end;
                def sort_key: phase_lbl | split(".") | map(if test("^[0-9]+$") then ("000" + .)[-3:] else . end) | join(".");
                .currentPhase = (.phases | sort_by(sort_key) | first | "\(phase_lbl): \(.name)")
              ' "$STATE_FILE" | safe_json_write "$STATE_FILE"
            else
              # No phases array in new activation — reset to default
              jq '.currentPhase = "Phase 1: Setup"' \
                "$STATE_FILE" | safe_json_write "$STATE_FILE"
            fi
          else
            # Same skill, same PID — merge seed (if any) before early exit.
            # After /clear, SessionStart resets preloadedFiles to 6 seeds and creates
            # a new seed file. Without this merge, the seed's accumulated entries are
            # lost — causing discovery hook to re-queue directives that were already loaded.
            SESSIONS_BASE=$(dirname "$DIR")
            SEED_FILE="$SESSIONS_BASE/.seeds/${TARGET_PID}.json"
            if [ -f "$SEED_FILE" ]; then
              SEED_LIFECYCLE=$(jq -r '.lifecycle // ""' "$SEED_FILE" 2>/dev/null || echo "")
              if [ "$SEED_LIFECYCLE" = "seeding" ]; then
                jq -s '
                  (.[0].preloadedFiles // []) as $sp |
                  (.[1].preloadedFiles // []) as $seedp |
                  (.[0].pendingPreloads // []) as $pp |
                  (.[1].pendingPreloads // []) as $seedpp |
                  (.[0].touchedDirs // {}) as $td |
                  (.[1].touchedDirs // {}) as $seedtd |
                  .[0] |
                  .preloadedFiles = ($sp + $seedp | unique) |
                  .pendingPreloads = ($pp + $seedpp | unique) |
                  .touchedDirs = ($td * $seedtd)
                ' "$STATE_FILE" "$SEED_FILE" | safe_json_write "$STATE_FILE"
                rm -f "$SEED_FILE"
              fi
            fi
            echo "Session re-activated: $DIR (skill: $SKILL, pid: $TARGET_PID)"
            exit 0
          fi
        elif pid_exists "$EXISTING_PID"; then
          # Different Claude process is active — reject
          echo "§CMD_MAINTAIN_SESSION_DIR: Session has active agent (PID $EXISTING_PID). Choose another folder." >&2
          exit 1
        else
          # PID dead — check if dehydrated (awaiting continue) vs truly abandoned
          IS_DEHYDRATED=$(jq -r 'if (.dehydratedContext != null) or (.killRequested == true) then "true" else "false" end' "$STATE_FILE" 2>/dev/null || echo "false")
          if [ "$IS_DEHYDRATED" = "true" ]; then
            # Dehydrated session — preserve state, update PID for reactivation
            echo "Dehydrated session detected (PID $EXISTING_PID dead). Preserving state and reactivating."
            JQ_EXPR='.pid = $pid | .lifecycle = "active" | .loading = true | .killRequested = false | .lastHeartbeat = $ts'
            JQ_ARGS=(--argjson pid "$TARGET_PID" --arg ts "$(timestamp)")
            if [ -n "$FLEET_PANE" ]; then
              JQ_EXPR="$JQ_EXPR | .fleetPaneId = \$pane"
              JQ_ARGS+=(--arg pane "$FLEET_PANE")
            fi
            if [ -n "${WORKSPACE:-}" ]; then
              JQ_EXPR="$JQ_EXPR | .workspace = \$ws"
              JQ_ARGS+=(--arg ws "$WORKSPACE")
            fi
            jq "${JQ_ARGS[@]}" "$JQ_EXPR" "$STATE_FILE" | safe_json_write "$STATE_FILE"
            ACTIVATED=true
            SHOULD_SCAN=true
            echo "Session reactivated (dehydrated → active): $DIR (skill: $SKILL, pid: $TARGET_PID)"
          else
            # Truly stale PID, no dehydration markers — clean up
            echo "Cleaning up stale .state.json (PID $EXISTING_PID no longer running)"
            rm "$STATE_FILE"
          fi
        fi
      else
        # PID is null/empty — check if this is an idle session (reactivatable)
        EXISTING_LIFECYCLE=$(jq -r '.lifecycle // ""' "$STATE_FILE" 2>/dev/null || echo "")
        if [ "$EXISTING_LIFECYCLE" = "idle" ]; then
          # Idle → active. Preserve state, swap skill, reset phases.
          # SHOULD_SCAN determined by --fast-track flag (unified with other paths).
          EXISTING_SKILL=$(jq -r '.skill // empty' "$STATE_FILE")

          JQ_EXPR='.pid = $pid | .skill = $skill | .lifecycle = "active" | .loading = true | .overflowed = false | .killRequested = false | .lastHeartbeat = $ts'
          JQ_ARGS=(--argjson pid "$TARGET_PID" --arg skill "$SKILL" --arg ts "$(timestamp)")

          if [ -n "$FLEET_PANE" ]; then
            JQ_EXPR="$JQ_EXPR | .fleetPaneId = \$pane"
            JQ_ARGS+=(--arg pane "$FLEET_PANE")
          fi

          if [ -n "${WORKSPACE:-}" ]; then
            JQ_EXPR="$JQ_EXPR | .workspace = \$ws"
            JQ_ARGS+=(--arg ws "$WORKSPACE")
          fi

          jq "${JQ_ARGS[@]}" "$JQ_EXPR" \
            "$STATE_FILE" | safe_json_write "$STATE_FILE"

          # Wipe phase state for new skill
          jq 'del(.phases) | .phaseHistory = []' \
            "$STATE_FILE" | safe_json_write "$STATE_FILE"

          # Merge stdin JSON if provided
          if [ -n "$STDIN_JSON" ]; then
            jq -s '.[0] * .[1]' "$STATE_FILE" <(echo "$STDIN_JSON") | safe_json_write "$STATE_FILE"
          fi

          # Apply SKILL.md static fields (engine-authoritative) — overwrites any agent-provided static values
          if [ -n "$SKILL_JSON" ]; then
            jq -s --argjson fields "$SKILL_STATIC_FIELDS" '
              .[0] * (.[1] | with_entries(select(.key as $k | $fields | index($k))))
            ' "$STATE_FILE" <(echo "$SKILL_JSON") | safe_json_write "$STATE_FILE"
          fi

          ACTIVATED=true
          SHOULD_SCAN=true  # Unified: --fast-track override applied later if set

          # Derive currentPhase from new phases array
          HAS_NEW_PHASES=$(jq 'has("phases") and (.phases | length > 0)' "$STATE_FILE" 2>/dev/null || echo "false")
          if [ "$HAS_NEW_PHASES" = "true" ]; then
            jq '
              def phase_lbl: if has("label") then .label elif .minor == 0 then "\(.major)" else "\(.major).\(.minor)" end;
              def sort_key: phase_lbl | split(".") | map(if test("^[0-9]+$") then ("000" + .)[-3:] else . end) | join(".");
              .currentPhase = (.phases | sort_by(sort_key) | first | "\(phase_lbl): \(.name)")
            ' "$STATE_FILE" | safe_json_write "$STATE_FILE"
          else
            jq '.currentPhase = "Phase 1: Setup"' \
              "$STATE_FILE" | safe_json_write "$STATE_FILE"
          fi

          echo "Session reactivated (idle → active): $DIR (skill: $SKILL, pid: $TARGET_PID)"
        fi
      fi
    fi

    # Create fresh .state.json (skip if already handled via same-PID or idle path)
    if [ "$ACTIVATED" = false ]; then
      NOW=$(timestamp)
      # Build preload seeds with absolute paths (resolved through symlinks)
      ACTIVATE_ENGINE_DIR=$(cd "$HOME/.claude/.directives" 2>/dev/null && pwd -P) || ACTIVATE_ENGINE_DIR="$HOME/.claude/.directives"
      ACTIVATE_SEEDS=$(jq -n --arg d "$ACTIVATE_ENGINE_DIR" '[$d+"/COMMANDS.md",$d+"/INVARIANTS.md",$d+"/SIGILS.md",$d+"/commands/CMD_DEHYDRATE.md",$d+"/commands/CMD_RESUME_SESSION.md",$d+"/commands/CMD_PARSE_PARAMETERS.md"]')
      # Build base JSON and conditionally add optional fields
      BASE_JSON=$(jq -n \
        --argjson pid "$TARGET_PID" \
        --arg skill "$SKILL" \
        --arg startedAt "$NOW" \
        --arg lastHeartbeat "$NOW" \
        --argjson seeds "$ACTIVATE_SEEDS" \
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
          lastHeartbeat: $lastHeartbeat,
          preloadedFiles: $seeds,
          touchedDirs: {},
          pendingPreloads: [],
          pendingAllowInjections: []
        }')

      # Add optional fields
      if [ -n "$FLEET_PANE" ]; then
        BASE_JSON=$(echo "$BASE_JSON" | jq --arg pane "$FLEET_PANE" '.fleetPaneId = $pane')
      fi
      if [ -n "$TARGET_FILE" ]; then
        BASE_JSON=$(echo "$BASE_JSON" | jq --arg file "$TARGET_FILE" '.targetFile = $file')
      fi
      if [ -n "${WORKSPACE:-}" ]; then
        BASE_JSON=$(echo "$BASE_JSON" | jq --arg ws "$WORKSPACE" '.workspace = $ws')
      fi

      # Merge stdin JSON (session parameters) if provided
      if [ -n "$STDIN_JSON" ]; then
        BASE_JSON=$(echo "$BASE_JSON" | jq -s '.[0] * .[1]' - <(echo "$STDIN_JSON"))
      fi

      # Apply SKILL.md static fields (engine-authoritative) — overwrites any agent-provided static values
      if [ -n "$SKILL_JSON" ]; then
        BASE_JSON=$(echo "$BASE_JSON" | jq -s --argjson fields "$SKILL_STATIC_FIELDS" '
          .[0] * (.[1] | with_entries(select(.key as $k | $fields | index($k))))
        ' - <(echo "$SKILL_JSON"))
      fi

      # If phases array was provided, set currentPhase to first phase's label
      # Label derived: minor=0 → "N: Name", minor>0 → "N.M: Name"
      HAS_PHASES_CHECK=$(echo "$BASE_JSON" | jq 'has("phases") and (.phases | length > 0)' 2>/dev/null || echo "false")
      if [ "$HAS_PHASES_CHECK" = "true" ]; then
        BASE_JSON=$(echo "$BASE_JSON" | jq '
          def phase_lbl: if has("label") then .label elif .minor == 0 then "\(.major)" else "\(.major).\(.minor)" end;
          def sort_key: phase_lbl | split(".") | map(if test("^[0-9]+$") then ("000" + .)[-3:] else . end) | join(".");
          .currentPhase = (.phases | sort_by(sort_key) | first | "\(phase_lbl): \(.name)")
        ')
      fi

      echo "$BASE_JSON" | safe_json_write "$STATE_FILE"
      SHOULD_SCAN=true
    fi

    # --- Seed File Merge ---
    # If a pre-session seed file exists for this PID, merge its tracking fields
    # into the session .state.json and delete the seed.
    SESSIONS_BASE=$(dirname "$DIR")
    SEED_FILE="$SESSIONS_BASE/.seeds/${TARGET_PID}.json"
    if [ -f "$SEED_FILE" ]; then
      SEED_LIFECYCLE=$(jq -r '.lifecycle // ""' "$SEED_FILE" 2>/dev/null || echo "")
      if [ "$SEED_LIFECYCLE" = "seeding" ]; then
        # Merge: seed preloadedFiles + pendingPreloads + touchedDirs into session state
        jq -s '
          (.[0].preloadedFiles // []) as $sp |
          (.[1].preloadedFiles // []) as $seedp |
          (.[0].pendingPreloads // []) as $pp |
          (.[1].pendingPreloads // []) as $seedpp |
          (.[0].touchedDirs // {}) as $td |
          (.[1].touchedDirs // {}) as $seedtd |
          .[0] |
          .preloadedFiles = ($sp + $seedp | unique) |
          .pendingPreloads = ($pp + $seedpp | unique) |
          .touchedDirs = ($td * $seedtd)
        ' "$STATE_FILE" "$SEED_FILE" | safe_json_write "$STATE_FILE"
        rm -f "$SEED_FILE"
      fi
    fi

    # --- PID Cache: write on activate ---
    # All activation paths (fresh, same-PID, idle→active) converge here.
    # Write cache so session.sh find can skip the sweep.
    echo "$DIR" > "/tmp/claude-session-cache-$TARGET_PID" 2>/dev/null || true

    # --- Fast-Track Override ---
    # --fast-track forces SHOULD_SCAN=false regardless of which code path set it.
    # Stores fastTrack: true in .state.json (informational — not read on restart).
    if [ "$FAST_TRACK" = true ]; then
      SHOULD_SCAN=false
      jq '.fastTrack = true' "$STATE_FILE" | safe_json_write "$STATE_FILE"
    fi

    # --- Output: Structured Markdown Context ---

    # Confirmation line
    MSG="Session activated: $DIR (skill: $SKILL, pid: $TARGET_PID"
    [ -n "$FLEET_PANE" ] && MSG="$MSG, fleet: $FLEET_PANE"
    [ -n "$TARGET_FILE" ] && MSG="$MSG, target: $TARGET_FILE"
    echo "$MSG)"

    # Session context line — matches SessionStart/UserPromptSubmit format so agent sees fresh state
    # Critical after overflow restart: overrides stale "90%+" belief from dehydrated context
    ACT_PHASE=$(jq -r '.currentPhase // "0: Setup"' "$STATE_FILE" 2>/dev/null)
    ACT_HB_COUNT=$(jq -r '.toolCallsSinceLastLog // 0' "$STATE_FILE" 2>/dev/null)
    ACT_HB_MAX=$(jq -r '.toolUseWithoutLogsBlockAfter // 10' "$STATE_FILE" 2>/dev/null)
    ACT_CTX_RAW=$(jq -r '.contextUsage // 0' "$STATE_FILE" 2>/dev/null)
    ACT_CTX_PCT=$(awk "BEGIN {printf \"%.0f\", $ACT_CTX_RAW * 100}")
    ACT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    ACT_SESSION_NAME=$(basename "$DIR")
    echo ""
    echo "[Session Context] Time: ${ACT_TIME} | Session: ${ACT_SESSION_NAME} | Skill: ${SKILL} | Phase: ${ACT_PHASE} | Heartbeat: ${ACT_HB_COUNT}/${ACT_HB_MAX} | Context: ${ACT_CTX_PCT}%"

    # Global invariant self-affirmations (cognitive anchoring — agent grounds on these before any phase work)
    # These are system-level truths that apply to ALL phases of ALL skills.
    echo ""
    echo "## Global Invariants (Self-Affirm Before Every Phase)"
    echo "  - ¶INV_PROTOCOL_IS_TASK: The protocol defines the task. Do not skip steps."
    echo "  - ¶INV_ENGINE_COMMAND_DISPATCH: Use \`engine <command>\` only. Never resolve script paths."
    echo "  - ¶INV_PHASE_ENFORCEMENT: Phase transitions are mechanically enforced. Do not self-authorize skips."
    echo "  - ¶INV_USER_APPROVED_REQUIRES_TOOL: --user-approved requires AskUserQuestion. Never self-author reasons."
    echo "  - ¶INV_STEPS_ARE_COMMANDS: Phase steps must be §CMD_* references. No prose in steps arrays."
    echo "  - ¶INV_PROOF_IS_DERIVED: Phase proof comes from step CMD schemas. Do not invent proof fields."
    echo "  - ¶INV_TRUST_CACHED_CONTEXT: Do not re-read files already in context. Memory over IO."

    # --- Initial Phase Proof Display ---
    # Show proof requirements for the initial phase (Phase 0) so agents know what's needed
    # before their first phase transition. Uses the same combined merge logic as the phase subcommand.
    ACT_INITIAL_PHASE=$(jq -r '.currentPhase // ""' "$STATE_FILE" 2>/dev/null)
    if [ -n "$ACT_INITIAL_PHASE" ]; then
      # Extract label from "N: Name" format
      ACT_INIT_LABEL="${ACT_INITIAL_PHASE%%:*}"
      ACT_INIT_LABEL=$(echo "$ACT_INIT_LABEL" | sed 's/ *$//')

      # Read steps[], commands[], and proof[] for initial phase
      ACT_INIT_STEPS=$(jq -r --arg rl "$ACT_INIT_LABEL" "
        $JQ_LABEL_HELPERS
        (.phases[] | select(phase_lbl == \$rl) | .steps) // empty
      " "$STATE_FILE" 2>/dev/null || echo "")
      ACT_INIT_COMMANDS=$(jq -r --arg rl "$ACT_INIT_LABEL" "
        $JQ_LABEL_HELPERS
        (.phases[] | select(phase_lbl == \$rl) | .commands) // empty
      " "$STATE_FILE" 2>/dev/null || echo "")

      # Build combined proof schema (same logic as phase subcommand lines 1319-1381)
      ACT_PROPS="{}"
      ACT_REQ="[]"
      ACT_CMD_DIR="$HOME/.claude/engine/.directives/commands"

      # Merge from steps[]
      if [ -n "${ACT_INIT_STEPS:-}" ] && [ "${ACT_INIT_STEPS:-}" != "null" ]; then
        for step_cmd in $(echo "$ACT_INIT_STEPS" | jq -r '.[]'); do
          cmd_name="${step_cmd#§CMD_}"
          cmd_file="$ACT_CMD_DIR/CMD_${cmd_name}.md"
          [ -f "$cmd_file" ] || continue
          json_block=$(extract_proof_schema "$cmd_file")
          if [ -n "$json_block" ] && echo "$json_block" | jq empty 2>/dev/null; then
            sp=$(echo "$json_block" | jq -r '.properties // empty' 2>/dev/null || echo "")
            sr=$(echo "$json_block" | jq -r '.required // empty' 2>/dev/null || echo "")
            [ -n "$sp" ] && [ "$sp" != "null" ] && ACT_PROPS=$(echo "$ACT_PROPS" | jq -s '.[0] * .[1]' - <(echo "$sp"))
            [ -n "$sr" ] && [ "$sr" != "null" ] && ACT_REQ=$(echo "$ACT_REQ" | jq -s '.[0] + .[1] | unique' - <(echo "$sr"))
          fi
        done
      fi

      # Merge from commands[]
      if [ -n "${ACT_INIT_COMMANDS:-}" ] && [ "${ACT_INIT_COMMANDS:-}" != "null" ]; then
        for cmd_ref in $(echo "$ACT_INIT_COMMANDS" | jq -r '.[]'); do
          cmd_name="${cmd_ref#§CMD_}"
          cmd_file="$ACT_CMD_DIR/CMD_${cmd_name}.md"
          [ -f "$cmd_file" ] || continue
          json_block=$(extract_proof_schema "$cmd_file")
          if [ -n "$json_block" ] && echo "$json_block" | jq empty 2>/dev/null; then
            sp=$(echo "$json_block" | jq -r '.properties // empty' 2>/dev/null || echo "")
            sr=$(echo "$json_block" | jq -r '.required // empty' 2>/dev/null || echo "")
            [ -n "$sp" ] && [ "$sp" != "null" ] && ACT_PROPS=$(echo "$ACT_PROPS" | jq -s '.[0] * .[1]' - <(echo "$sp"))
            [ -n "$sr" ] && [ "$sr" != "null" ] && ACT_REQ=$(echo "$ACT_REQ" | jq -s '.[0] + .[1] | unique' - <(echo "$sr"))
          fi
        done
      fi

      # Add declared proof fields
      ACT_PROOF_FIELDS=$(jq -r --arg rl "$ACT_INIT_LABEL" "
        $JQ_LABEL_HELPERS
        (.phases[] | select(phase_lbl == \$rl) | .proof) // empty
      " "$STATE_FILE" 2>/dev/null || echo "")
      if [ -n "$ACT_PROOF_FIELDS" ] && [ "$ACT_PROOF_FIELDS" != "null" ]; then
        for df in $(echo "$ACT_PROOF_FIELDS" | jq -r '.[]'); do
          [ -n "$df" ] || continue
          HAS_F=$(echo "$ACT_PROPS" | jq --arg f "$df" 'has($f)' 2>/dev/null || echo "false")
          if [ "$HAS_F" = "false" ]; then
            ACT_PROPS=$(echo "$ACT_PROPS" | jq --arg f "$df" '. + {($f): {"type": "string"}}')
          fi
          ACT_REQ=$(echo "$ACT_REQ" | jq --arg f "$df" 'if index($f) then . else . + [$f] end')
        done
      fi

      # Display combined proof
      ACT_REQ_COUNT=$(echo "$ACT_REQ" | jq 'length' 2>/dev/null || echo "0")
      if [ "$ACT_REQ_COUNT" -gt 0 ]; then
        echo ""
        echo "Proof required to leave this phase ($ACT_INITIAL_PHASE):"
        echo "$ACT_REQ" | jq -r --argjson props "$ACT_PROPS" '.[] |
          ($props[.].description // "") as $desc |
          if $desc != "" then "  - \(.): \($desc)" else "  - \(.)" end'
      fi
    fi

    # Context scanning (only on fresh activation or skill change)
    if [ "$SHOULD_SCAN" = true ]; then
      SESSION_SEARCH="$HOME/.claude/tools/session-search/session-search.sh"
      DOC_SEARCH="$HOME/.claude/tools/doc-search/doc-search.sh"

      # Extract taskSummary for thematic search
      TASK_SUMMARY=""
      if [ -n "$STDIN_JSON" ]; then
        TASK_SUMMARY=$(echo "$STDIN_JSON" | jq -r '.taskSummary // empty')
      fi

      # SRC_ACTIVE_ALERTS (thematic via session-search)
      echo ""
      echo "## SRC_ACTIVE_ALERTS"
      if [ -n "$TASK_SUMMARY" ]; then
        SURFACE_ALERTS=$("$SESSION_SEARCH" query "$TASK_SUMMARY" --tag '#active-alert' --limit 10 2>/dev/null || true)
      fi
      if [ -n "${SURFACE_ALERTS:-}" ]; then
        echo "$SURFACE_ALERTS"
      else
        echo "(none)"
      fi

      # SRC_OPEN_DELEGATIONS (scan for #next-* tags in current session)
      echo ""
      echo "## SRC_OPEN_DELEGATIONS"
      TAG_SH="$HOME/.claude/scripts/tag.sh"
      if [ -d "$DIR" ]; then
        SURFACE_DELEGATIONS=$("$TAG_SH" find '#next-*' "$DIR" 2>/dev/null || true)
      fi
      if [ -n "${SURFACE_DELEGATIONS:-}" ]; then
        echo "$SURFACE_DELEGATIONS"
      else
        echo "(none)"
      fi

      # SRC_PRIOR_SESSIONS (semantic search over past session logs)
      echo ""
      echo "## SRC_PRIOR_SESSIONS"
      if [ -n "$TASK_SUMMARY" ]; then
        RECALL_SESSIONS=$("$SESSION_SEARCH" query "$TASK_SUMMARY" --limit 10 2>/dev/null || true)
      fi
      if [ -n "${RECALL_SESSIONS:-}" ]; then
        echo "$RECALL_SESSIONS"
      else
        echo "(none)"
      fi

      # SRC_RELEVANT_DOCS (semantic search over project documentation)
      echo ""
      echo "## SRC_RELEVANT_DOCS"
      if [ -n "$TASK_SUMMARY" ]; then
        RECALL_DOCS=$("$DOC_SEARCH" query "$TASK_SUMMARY" --limit 10 2>/dev/null || true)
      fi
      if [ -n "${RECALL_DOCS:-}" ]; then
        echo "$RECALL_DOCS"
      else
        echo "(none)"
      fi

      # §CMD_DISCOVER_DIRECTIVES: walk-up from directoriesOfInterest
      # Finds soft directives (AGENTS.md, INVARIANTS.md, TESTING.md, PITFALLS.md, TEMPLATE.md) and
      # hard directives (CHECKLIST.md — enforced at deactivation).
      # Skill filtering: core directives always shown; skill directives only if declared.
      # See ¶INV_DIRECTIVE_STACK and ¶INV_CHECKLIST_BEFORE_CLOSE
      DISCOVER_SCRIPT="$HOME/.claude/scripts/discover-directives.sh"
      if [ -x "$DISCOVER_SCRIPT" ]; then
        # Extract directoriesOfInterest from .state.json
        DIRS_JSON=$(jq -r '(.directoriesOfInterest // []) | .[]' "$STATE_FILE" 2>/dev/null || true)
        # Auto-inject the active skill's directory for directive discovery
        SKILL_DIR="$HOME/.claude/skills/$SKILL"
        if [ -d "$SKILL_DIR" ]; then
          if [ -n "$DIRS_JSON" ]; then
            DIRS_JSON="${DIRS_JSON}"$'\n'"${SKILL_DIR}"
          else
            DIRS_JSON="$SKILL_DIR"
          fi
        fi
        if [ -n "$DIRS_JSON" ]; then
          ALL_DISCOVERED=""
          while IFS= read -r interest_dir; do
            [ -n "$interest_dir" ] || continue
            # Resolve relative paths against PWD
            if [[ "$interest_dir" != /* ]]; then
              interest_dir="$PWD/$interest_dir"
            fi
            [ -d "$interest_dir" ] || continue
            # Add --root for cross-tree dirs (e.g., ~/.claude/skills/) so walk-up
            # boundary is correct. Without this, walk-up defaults to $PWD which
            # is not an ancestor of ~/.claude/ paths.
            ROOT_ARG=""
            if [[ "$interest_dir" == "$HOME/.claude"* ]]; then
              ROOT_ARG="--root $HOME/.claude"
            fi
            FOUND=$("$DISCOVER_SCRIPT" "$interest_dir" --walk-up --include-shared $ROOT_ARG 2>/dev/null || true)
            if [ -n "$FOUND" ]; then
              ALL_DISCOVERED="${ALL_DISCOVERED}${ALL_DISCOVERED:+$'\n'}${FOUND}"
            fi
          done <<< "$DIRS_JSON"

          echo ""
          echo "## §CMD_DISCOVER_DIRECTIVES"
          if [ -n "$ALL_DISCOVERED" ]; then
            # Skill-directive filtering: core directives always shown,
            # skill directives (TESTING.md, PITFALLS.md) only if declared in `directives` array
            CORE_DIRECTIVES="AGENTS.md INVARIANTS.md"
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
              # Normalize path to match _run_discovery() format (full path, symlinks resolved)
              norm_file=$(normalize_preload_path "$discovered_file")
              # Add to touchedDirs (full normalized path, not basename)
              jq --arg dir "$discovered_dir" --arg name "$norm_file" \
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

    # SRC_SESSION_ARTIFACTS (runs unconditionally — shows all files in session dir)
    echo ""
    echo "## SRC_SESSION_ARTIFACTS"
    if [ -d "$DIR" ]; then
      ARTIFACT_LIST=$(ls -1 "$DIR" 2>/dev/null | grep -v '\.state\.json$' | grep -v '^\.' || true)
      if [ -n "$ARTIFACT_LIST" ]; then
        echo "$ARTIFACT_LIST"
      else
        echo "(empty session)"
      fi
    else
      echo "(session dir not yet created)"
    fi

    # SRC_PRIOR_SKILL_CONTEXT (preloads last skill's debrief or log on skill change)
    # When switching skills within the same session, the prior skill's decisions
    # are critical context — especially for interrogation deduplication.
    if [ "$SHOULD_SCAN" = true ] && [ -d "$DIR" ]; then
      echo ""
      echo "## SRC_PRIOR_SKILL_CONTEXT"
      # Find the most recent log (contains interrogation decisions and build progress)
      PRIOR_LOG=$(ls -1t "$DIR"/*_LOG.md 2>/dev/null | head -1 || true)
      if [ -n "$PRIOR_LOG" ] && [ -f "$PRIOR_LOG" ]; then
        echo "Prior log: $PRIOR_LOG"
        echo "[Suggested — read this file for prior skill decisions and interrogation answers]"
      fi
      # Find the most recent debrief (synthesized summary, if one exists)
      PRIOR_DEBRIEF=$(ls -1t "$DIR"/*.md 2>/dev/null \
        | grep -v '_LOG\.md$' | grep -v '_PLAN\.md$' | grep -v 'DETAILS\.md$' \
        | grep -v 'TEMPLATE' | grep -v 'CHECKLIST' | grep -v 'REQUEST' | grep -v 'RESPONSE' \
        | head -1 || true)
      if [ -n "$PRIOR_DEBRIEF" ] && [ -f "$PRIOR_DEBRIEF" ]; then
        echo "Prior debrief: $PRIOR_DEBRIEF"
        echo "[Suggested — read this file for prior skill synthesis]"
      fi
      if [ -z "$PRIOR_LOG" ] && [ -z "$PRIOR_DEBRIEF" ]; then
        echo "(no prior skill artifacts)"
      fi
      # Always suggest DIALOGUE.md if it exists (cross-skill Q&A history)
      if [ -f "$DIR/DIALOGUE.md" ]; then
        echo "Cross-skill Q&A: $DIR/DIALOGUE.md"
        echo "[Suggested — read for prior interrogation answers]"
      fi
      echo ""
      echo "⚠️  Prior skill decisions may overlap with interrogation topics. Check before re-asking."
    fi

    # SRC_DELEGATION_TARGETS (runs unconditionally — fresh context needs this)
    # Scans skills for TEMPLATE_*_REQUEST.md to build a delegation targets table.
    echo ""
    echo "## SRC_DELEGATION_TARGETS"
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
    validate_phase "$PHASE"

    if [ ! -f "$STATE_FILE" ]; then
      echo "§CMD_REQUIRE_ACTIVE_SESSION: No .state.json in $DIR — is the session active?" >&2
      exit 1
    fi

    # Parse optional flags: --user-approved
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

    # Read proof from STDIN (if available)
    # Timeout prevents hang when called without heredoc and without < /dev/null
    PROOF_INPUT=""
    if [ ! -t 0 ]; then
      if IFS= read -r -t 1 _first_line 2>/dev/null; then
        _rest=$(cat)
        PROOF_INPUT="${_first_line}${_rest:+$'\n'${_rest}}"
      fi
    fi

    # --- Phase Enforcement ---
    # If .state.json has a "phases" array, enforce sequential progression.
    # If no "phases" array, skip enforcement (backward compat with old sessions).
    # Bilingual: supports label-based phases ({"label": "3.C"}) and legacy major/minor.
    # Labels are hierarchical: "3.C" (branch), "4.1" (sequential), "4.A.1.2" (deep).
    HAS_PHASES=$(jq 'has("phases") and (.phases | length > 0)' "$STATE_FILE" 2>/dev/null || echo "false")

    if [ "$HAS_PHASES" = "true" ]; then

      # --- Helper: derive label from a phase JSON entry ---
      phase_entry_label() {
        jq -r 'if has("label") then .label elif .minor == 0 then "\(.major)" else "\(.major).\(.minor)" end'
      }

      # --- Helper: extract major number from a label string ---
      label_major() { echo "$1" | grep -oE '^[0-9]+' || echo "0"; }

      # --- Helper: check if label has sub-parts ---
      label_is_sub() { echo "$1" | grep -q '\.'; }

      # --- Helper: detect branch switching by walking label segments ---
      # Returns 0 (true) if cur→req crosses between letter branches at the same depth.
      # "3.A.1" vs "3.B" → true (A≠B at depth 1 under parent "3")
      # "3.A.1" vs "3.A.2" → false (same branch A, different sub-phase)
      # "4.1" vs "4.2" → false (numbers, not branches)
      is_branch_switch() {
        local cur="$1" req="$2"
        IFS='.' read -ra CS <<< "$cur"
        IFS='.' read -ra RS <<< "$req"
        local min=${#CS[@]}
        [ ${#RS[@]} -lt $min ] && min=${#RS[@]}
        local i
        for ((i=0; i<min; i++)); do
          local c="${CS[$i]}" r="${RS[$i]}"
          if [[ "$c" =~ ^[A-Z]+$ ]] && [[ "$r" =~ ^[A-Z]+$ ]] && [ "$c" != "$r" ]; then
            return 0  # branch switch: different letters at same depth
          fi
          [ "$c" != "$r" ] && return 1  # diverged on non-letter segment
        done
        return 1  # no branch switch detected
      }

      # --- Helper: compute sort key for label (pad numbers to 3 digits) ---
      label_sort_key() {
        echo "$1" | awk -F. '{ for(i=1;i<=NF;i++) { if($i ~ /^[0-9]+$/) printf "%03d",$i; else printf "%s",$i; if(i<NF) printf "." } }'
      }

      # --- jq helpers for label sorting ---
      # JQ_LABEL_HELPERS defined at top of file (shared between activate and phase)

      # --- Parse requested phase ---
      REQ_LABEL=$(echo "$PHASE" | sed -E 's/: .*//')
      REQ_MAJOR=$(label_major "$REQ_LABEL")
      if [ -z "$REQ_MAJOR" ]; then
        echo "§CMD_UPDATE_PHASE: Phase label must start with a number (e.g., '3: Exec', '3.C: Branch'). Got: '$PHASE'" >&2
        exit 1
      fi
      # --- Label format validation ---
      # Valid: N, N.M, N.A, N.MA (single uppercase letter suffix on sub-phase), N.A.M, etc.
      # First segment: pure number. Subsequent: number, letters, or number+single uppercase letter.
      # Rejects: alpha-style (1a, 5B), double letter suffix (3.1AB), lowercase suffix (3.1a)
      if ! echo "$REQ_LABEL" | grep -qE '^[0-9]+(\.(([0-9]+[A-Z]?)|[A-Z]+))*$'; then
        echo "§CMD_UPDATE_PHASE: Invalid phase label format: '$REQ_LABEL'. Valid formats: N, N.M, N.A, N.MA (single uppercase). Got: '$PHASE'" >&2
        exit 1
      fi
      # --- Parse current phase ---
      CURRENT_PHASE=$(jq -r '.currentPhase // ""' "$STATE_FILE")
      CUR_LABEL=$(echo "$CURRENT_PHASE" | sed -E 's/: .*//')
      CUR_MAJOR=$(label_major "$CUR_LABEL")

      # --- Find the next declared phase (by label sort order) ---
      NEXT_PHASE_JSON=$(jq -r --arg cl "$CUR_LABEL" "
        $JQ_LABEL_HELPERS
        def cur_key: \$cl | split(\".\") | map(if test(\"^[0-9]+$\") then (\"000\" + .)[-3:] else . end) | join(\".\");
        [.phases[] | select(sort_key > cur_key)] | sort_by(sort_key) | first // empty
      " "$STATE_FILE" 2>/dev/null || echo "")

      NEXT_LABEL=""
      NEXT_MAJOR=""
      if [ -n "$NEXT_PHASE_JSON" ]; then
        NEXT_LABEL=$(echo "$NEXT_PHASE_JSON" | phase_entry_label)
        NEXT_MAJOR=$(label_major "$NEXT_LABEL")
      fi

      # --- Determine if transition is sequential ---
      IS_SEQUENTIAL=false
      IS_BRANCH_SWITCH=false

      # Case 0: Re-entering the same phase (no-op, always allowed)
      if [ "$REQ_LABEL" = "$CUR_LABEL" ]; then
        IS_SEQUENTIAL=true
      fi

      # Case 1: Moving to the next declared phase (next in label sort order)
      # Guard: branch switching is forbidden even for adjacent phases (3.A → 3.B)
      if [ "$IS_SEQUENTIAL" = "false" ] && [ -n "$NEXT_LABEL" ] && [ "$REQ_LABEL" = "$NEXT_LABEL" ]; then
        if ! is_branch_switch "$CUR_LABEL" "$REQ_LABEL"; then
          IS_SEQUENTIAL=true
        else
          IS_BRANCH_SWITCH=true
        fi
      fi

      # Case 1b: Sub-phases/branches are optional — skip to next major always allowed
      # If the next declared phase is under the same major as current,
      # allow jumping to the next major phase (current_major + 1).
      if [ "$IS_SEQUENTIAL" = "false" ] && [ -n "$NEXT_MAJOR" ] && [ "$NEXT_MAJOR" = "$CUR_MAJOR" ]; then
        NEXT_MAJOR_NUM=$(( CUR_MAJOR + 1 ))
        if [ "$REQ_MAJOR" = "$NEXT_MAJOR_NUM" ]; then
          IS_SEQUENTIAL=true
        fi
      fi

      # Case 1c: From a sub-phase/branch, allow jumping to the next major
      if [ "$IS_SEQUENTIAL" = "false" ] && label_is_sub "$CUR_LABEL"; then
        NEXT_MAJOR_NUM=$(( CUR_MAJOR + 1 ))
        if [ "$REQ_MAJOR" = "$NEXT_MAJOR_NUM" ]; then
          IS_SEQUENTIAL=true
        fi
      fi

      # Case 1d: Forward transitions for declared phases (branch-aware)
      # ALLOWS:
      #   - Entry into next major: 2 → 3.B (any declared phase under CUR_MAJOR + 1)
      #   - Forward sub-phase skip: 4 → 4.2, 4.1 → 4.3 (numbered, forward only)
      # FORBIDS:
      #   - Branch switching: 3.A → 3.B (letter-to-letter under same parent)
      #   - Backward movement: 4.2 → 4.1
      if [ "$IS_SEQUENTIAL" = "false" ]; then
        IS_DECLARED=$(jq -r --arg rl "$REQ_LABEL" "
          $JQ_LABEL_HELPERS
          [.phases[]] | any(phase_lbl == \$rl)
        " "$STATE_FILE" 2>/dev/null || echo "false")

        if [ "$IS_DECLARED" = "true" ]; then
          NEXT_MAJOR_NUM=$(( CUR_MAJOR + 1 ))

          if [ "$REQ_MAJOR" = "$NEXT_MAJOR_NUM" ]; then
            # Sub-case A: Entry into next major — always allowed for declared phases
            # Handles: 2 → 3.A, 2 → 3.B, 2 → 3.C
            IS_SEQUENTIAL=true

          elif [ "$REQ_MAJOR" = "$CUR_MAJOR" ]; then
            # Sub-case B: Same-major forward movement (not branch switching)
            REQ_SK=$(label_sort_key "$REQ_LABEL")
            CUR_SK=$(label_sort_key "$CUR_LABEL")

            if [[ "$REQ_SK" > "$CUR_SK" ]]; then
              # Forward — check for branch switching at any depth
              if ! is_branch_switch "$CUR_LABEL" "$REQ_LABEL"; then
                IS_SEQUENTIAL=true
              else
                IS_BRANCH_SWITCH=true
              fi
            fi
            # If not forward, fall through to rejection (backward movement)
          fi
        fi
      fi

      # Case 2: Auto-append — same major, not yet declared
      if [ "$IS_SEQUENTIAL" = "false" ]; then
        IS_DECLARED=$(jq -r --arg rl "$REQ_LABEL" "
          $JQ_LABEL_HELPERS
          [.phases[]] | any(phase_lbl == \$rl)
        " "$STATE_FILE" 2>/dev/null || echo "false")

        if [ "$IS_DECLARED" = "false" ] && [ "$REQ_MAJOR" = "$CUR_MAJOR" ]; then
          IS_SEQUENTIAL=true
          # Auto-append: insert this phase into the phases array with label
          REQUESTED_NAME=$(echo "$PHASE" | sed -E 's/^[^:]+: //')
          jq --arg lbl "$REQ_LABEL" --arg name "$REQUESTED_NAME" "
            $JQ_LABEL_HELPERS
            .phases += [{\"label\": \$lbl, \"name\": \$name}] | .phases |= sort_by(sort_key)
          " "$STATE_FILE" | safe_json_write "$STATE_FILE"
        fi
      fi

      # If not sequential, require --user-approved
      if [ "$IS_SEQUENTIAL" = "false" ]; then
        if [ -z "$USER_APPROVED" ]; then
          if [ "$IS_BRANCH_SWITCH" = "true" ]; then
            echo "§CMD_UPDATE_PHASE: Branch switch rejected ($CUR_LABEL → $REQ_LABEL)." >&2
            echo "  Letter-labeled phases (N.A, N.B, N.C) are alternative branches, not sequential steps." >&2
            echo "  You are in branch $CUR_LABEL — switching to $REQ_LABEL requires explicit approval." >&2
            NEXT_MAJOR_NUM=$(( CUR_MAJOR + 1 ))
            echo "  To exit this branch: engine session phase $DIR \"$NEXT_MAJOR_NUM: [NextPhase]\"" >&2
          else
            echo "§CMD_UPDATE_PHASE: Non-sequential phase transition rejected." >&2
            echo "  Current phase: $CURRENT_PHASE (label: $CUR_LABEL)" >&2
            echo "  Requested phase: $PHASE (label: $REQ_LABEL)" >&2
            if [ -n "$NEXT_LABEL" ]; then
              NEXT_NAME=$(echo "$NEXT_PHASE_JSON" | jq -r '.name')
              echo "  Expected next: $NEXT_LABEL: $NEXT_NAME" >&2
            fi
          fi
          echo "" >&2
          echo "  To proceed: engine session phase $DIR \"$PHASE\" --user-approved \"Reason: ...\"" >&2
          exit 1
        fi
        echo "Phase transition approved (non-sequential): $CURRENT_PHASE -> $PHASE"
        echo "  Approval: $USER_APPROVED"
      fi
    fi
    # --- Proof Parsing ---
    # Always parse STDIN proof into JSON when provided, regardless of validation.
    # This ensures proof is stored in phaseHistory even when the target phase has no proof fields.
    # Supports two formats:
    #   1. JSON object (preferred): {"depth_chosen": "Short", "rounds_completed": 3}
    #   2. key: value lines (deprecated): depth_chosen: Short\nrounds_completed: 3
    PROOF_JSON="{}"
    PROOF_FORMAT=""
    if [ -n "$PROOF_INPUT" ]; then
      # Try JSON parse first
      if echo "$PROOF_INPUT" | jq empty 2>/dev/null; then
        PROOF_JSON="$PROOF_INPUT"
        PROOF_FORMAT="json"
      else
        # Fallback: key: value line parsing (backward compat, deprecated)
        echo "⚠️  DEPRECATED: Proof piped as key:value lines. Use JSON objects instead." >&2
        PROOF_FORMAT="key-value"
        while IFS= read -r line; do
          [ -n "$line" ] || continue
          # Extract key (everything before first ': ')
          # Supports: alphanumeric keys (e.g., debrief_file) and §CMD_ prefixed keys (e.g., §CMD_PROCESS_CHECKLISTS)
          PKEY=$(echo "$line" | sed -n 's/^\([§a-zA-Z_][§a-zA-Z0-9_]*\): .*/\1/p')
          [ -z "$PKEY" ] && continue
          # Extract value: everything after the first ': ' separator
          PVAL="${line#*: }"
          PROOF_JSON=$(echo "$PROOF_JSON" | jq --arg k "$PKEY" --arg v "$PVAL" '. + {($k): $v}')
        done <<< "$PROOF_INPUT"
      fi
    fi

    # --- Proof Validation (FROM-validation) ---
    # If the CURRENT phase (being left) declares proof fields, validate STDIN contains all required fields.
    # Proof validates what the agent accomplished in the current phase before leaving it.
    # Example: Phase "2: Interrogation" has proof ["depth_chosen", "rounds_completed"] —
    #   when transitioning FROM Phase 2 to Phase 3, agent must prove interrogation was done.
    if [ "$HAS_PHASES" = "true" ] && [ -n "$CURRENT_PHASE" ]; then
      # Look up proof fields for the current phase being left (FROM validation)
      # Match current phase by label (bilingual: try .label, fallback to major/minor)
      PROOF_FIELDS_JSON=$(jq -r --arg cl "$CUR_LABEL" "
        $JQ_LABEL_HELPERS
        (.phases[] | select(phase_lbl == \$cl) | .proof) // empty
      " "$STATE_FILE" 2>/dev/null || echo "")

      if [ -n "$PROOF_FIELDS_JSON" ] && [ "$PROOF_FIELDS_JSON" != "null" ]; then
        PROOF_FIELDS_COUNT=$(echo "$PROOF_FIELDS_JSON" | jq 'length' 2>/dev/null || echo "0")

        if [ "$PROOF_FIELDS_COUNT" -gt 0 ]; then
          # Re-entering same phase (Case 0) skips FROM validation — nothing to prove yet
          if [ "$REQ_LABEL" = "$CUR_LABEL" ]; then
            : # No FROM validation when re-entering same phase
          else
            # Proof fields are declared on current phase — validate STDIN
            if [ -z "$PROOF_INPUT" ]; then
              echo "§CMD_UPDATE_PHASE: Proof required to leave phase '$CURRENT_PHASE' but no STDIN provided." >&2
              echo "  Required proof fields: $(echo "$PROOF_FIELDS_JSON" | jq -r 'join(", ")')" >&2
              echo "" >&2
              echo "  Usage: echo 'field: value' | session.sh phase $DIR \"$PHASE\"" >&2
              exit 1
            fi

            # Validate all required fields are present (proof already parsed above)
            MISSING_FIELDS=""
            for field in $(echo "$PROOF_FIELDS_JSON" | jq -r '.[]'); do
              FIELD_VAL=$(echo "$PROOF_JSON" | jq -r --arg f "$field" '.[$f] // ""')
              if [ -z "$FIELD_VAL" ]; then
                MISSING_FIELDS="${MISSING_FIELDS}${MISSING_FIELDS:+, }$field"
              elif [ "$FIELD_VAL" = "________" ]; then
                echo "§CMD_UPDATE_PHASE: Proof field '$field' has unfilled blank (________). Complete the work before transitioning." >&2
                exit 1
              fi
            done

            if [ -n "$MISSING_FIELDS" ]; then
              echo "§CMD_UPDATE_PHASE: Missing proof to leave phase '$CURRENT_PHASE': $MISSING_FIELDS" >&2
              echo "  Required: $(echo "$PROOF_FIELDS_JSON" | jq -r 'join(", ")')" >&2
              echo "  Provided: $(echo "$PROOF_JSON" | jq -r 'keys | join(", ")')" >&2
              exit 1
            fi

            # --- Proof Schema Validation ---
            # If phase has steps, extract CMD proof schemas and validate proof against them.
            # Two levels: (1) key recognition (warning), (2) full JSON Schema validation (exit 1).
            CUR_STEPS_JSON=$(jq -r --arg cl "$CUR_LABEL" "
              $JQ_LABEL_HELPERS
              (.phases[] | select(phase_lbl == \$cl) | .steps) // empty
            " "$STATE_FILE" 2>/dev/null || echo "")
            if [ -n "$CUR_STEPS_JSON" ] && [ "$CUR_STEPS_JSON" != "null" ]; then
              CUR_STEPS_COUNT=$(echo "$CUR_STEPS_JSON" | jq 'length' 2>/dev/null || echo "0")
              if [ "$CUR_STEPS_COUNT" -gt 0 ]; then
                # Build combined schema from CMD file PROOF schemas
                COMBINED_PROPERTIES="{}"
                COMBINED_REQUIRED="[]"
                CMD_DIR="$HOME/.claude/engine/.directives/commands"
                for step_cmd in $(echo "$CUR_STEPS_JSON" | jq -r '.[]'); do
                  # Strip §CMD_ prefix to get CMD file name
                  cmd_name="${step_cmd#§CMD_}"
                  cmd_file="$CMD_DIR/CMD_${cmd_name}.md"
                  [ -f "$cmd_file" ] || continue
                  # Extract JSON Schema from ## PROOF FOR section
                  json_block=$(extract_proof_schema "$cmd_file")
                  if [ -n "$json_block" ] && echo "$json_block" | jq empty 2>/dev/null; then
                    # Merge properties from this schema into combined
                    step_props=$(echo "$json_block" | jq -r '.properties // empty' 2>/dev/null || echo "")
                    step_req=$(echo "$json_block" | jq -r '.required // empty' 2>/dev/null || echo "")
                    if [ -n "$step_props" ] && [ "$step_props" != "null" ]; then
                      COMBINED_PROPERTIES=$(echo "$COMBINED_PROPERTIES" | jq -s '.[0] * .[1]' - <(echo "$step_props"))
                    fi
                    if [ -n "$step_req" ] && [ "$step_req" != "null" ]; then
                      COMBINED_REQUIRED=$(echo "$COMBINED_REQUIRED" | jq -s '.[0] + .[1] | unique' - <(echo "$step_req"))
                    fi
                  fi
                done

                # Also merge proof schemas from commands[] array (not just steps[])
                # See PITFALLS.md #12: without this, commands[] proof fields fall through
                # to the string fallback below, causing type mismatches
                CUR_COMMANDS_JSON=$(jq -r --arg cl "$CUR_LABEL" "
                  $JQ_LABEL_HELPERS
                  (.phases[] | select(phase_lbl == \$cl) | .commands) // empty
                " "$STATE_FILE" 2>/dev/null || echo "")
                if [ -n "$CUR_COMMANDS_JSON" ] && [ "$CUR_COMMANDS_JSON" != "null" ]; then
                  for cmd_ref in $(echo "$CUR_COMMANDS_JSON" | jq -r '.[]'); do
                    cmd_name="${cmd_ref#§CMD_}"
                    cmd_file="$CMD_DIR/CMD_${cmd_name}.md"
                    [ -f "$cmd_file" ] || continue
                    json_block=$(extract_proof_schema "$cmd_file")
                    if [ -n "$json_block" ] && echo "$json_block" | jq empty 2>/dev/null; then
                      step_props=$(echo "$json_block" | jq -r '.properties // empty' 2>/dev/null || echo "")
                      step_req=$(echo "$json_block" | jq -r '.required // empty' 2>/dev/null || echo "")
                      if [ -n "$step_props" ] && [ "$step_props" != "null" ]; then
                        COMBINED_PROPERTIES=$(echo "$COMBINED_PROPERTIES" | jq -s '.[0] * .[1]' - <(echo "$step_props"))
                      fi
                      if [ -n "$step_req" ] && [ "$step_req" != "null" ]; then
                        COMBINED_REQUIRED=$(echo "$COMBINED_REQUIRED" | jq -s '.[0] + .[1] | unique' - <(echo "$step_req"))
                      fi
                    fi
                  done
                fi

                # Also include declared proof fields as valid (phase-level data fields)
                DECLARED_FIELDS=$(echo "$PROOF_FIELDS_JSON" | jq -r '.[]' 2>/dev/null || echo "")
                if [ -n "$DECLARED_FIELDS" ]; then
                  while IFS= read -r df; do
                    [ -n "$df" ] || continue
                    # Add undeclared phase-level fields as string type
                    HAS_FIELD=$(echo "$COMBINED_PROPERTIES" | jq --arg f "$df" 'has($f)' 2>/dev/null || echo "false")
                    if [ "$HAS_FIELD" = "false" ]; then
                      COMBINED_PROPERTIES=$(echo "$COMBINED_PROPERTIES" | jq --arg f "$df" '. + {($f): {"type": "string"}}')
                    fi
                    COMBINED_REQUIRED=$(echo "$COMBINED_REQUIRED" | jq --arg f "$df" 'if index($f) then . else . + [$f] end')
                  done <<< "$DECLARED_FIELDS"
                fi

                # Build the combined JSON Schema
                HAS_PROPS=$(echo "$COMBINED_PROPERTIES" | jq 'length > 0' 2>/dev/null || echo "false")
                if [ "$HAS_PROPS" = "true" ]; then
                  COMBINED_SCHEMA=$(jq -n \
                    --argjson props "$COMBINED_PROPERTIES" \
                    --argjson req "$COMBINED_REQUIRED" \
                    '{
                      "$schema": "https://json-schema.org/draft/2020-12/schema",
                      "type": "object",
                      "properties": $props,
                      "required": $req
                    }')

                  # Full JSON Schema validation (exit 1 on failure)
                  if ! validate_json_schema "$COMBINED_SCHEMA" "$PROOF_JSON" 2>/tmp/proof_validation_err; then
                    echo "§CMD_UPDATE_PHASE: Proof validation failed against CMD schemas:" >&2
                    cat /tmp/proof_validation_err >&2
                    echo "" >&2
                    echo "  Schema required: $(echo "$COMBINED_REQUIRED" | jq -r 'join(", ")')" >&2
                    echo "  Proof provided: $PROOF_JSON" >&2
                    rm -f /tmp/proof_validation_err
                    exit 1
                  fi
                  rm -f /tmp/proof_validation_err
                fi
              fi
            fi
          fi
        fi
      else
        # Current phase has no proof field — warn if sibling phases have proof (backward-compat nudge)
        # Only warn when leaving a phase (not re-entering same phase)
        if [ "$REQ_LABEL" != "$CUR_LABEL" ]; then
          HAS_PROOF_SIBLINGS=$(jq '[.phases[] | select(has("proof") and (.proof | length > 0))] | length > 0' "$STATE_FILE" 2>/dev/null || echo "false")
          if [ "$HAS_PROOF_SIBLINGS" = "true" ]; then
            echo "§CMD_UPDATE_PHASE: Phase '$CURRENT_PHASE' has no proof fields declared, but other phases in this session declare proof. Consider adding proof fields to this phase." >&2
          fi
        fi
      fi
    fi

    # Update phase, clear loading flag, and reset all heartbeat transcript counters
    # loading=true is set by activate; cleared here when the agent transitions to a named phase
    # Counter reset gives a clean slate for the work phase
    # Append to phaseHistory for audit trail (with proof if provided)
    #
    # currentPhase stores the full label for display and enforcement.
    # Labels are hierarchical paths parsed at enforcement time.
    # phaseHistory stores objects with proof when proof was provided.
    # Proof is FROM-validation: it describes what was accomplished in the phase being LEFT.
    if [ "$PROOF_JSON" != "{}" ] && [ -n "$PROOF_INPUT" ]; then
      # Store phase + proof in phaseHistory as an object
      jq --arg phase "$PHASE" --arg ts "$(timestamp)" --argjson proof "$PROOF_JSON" \
        '.currentPhase = $phase | .lastHeartbeat = $ts | del(.loading) | .toolCallsByTranscript = {} | del(.primaryTranscriptKey) | .phaseHistory = ((.phaseHistory // []) + [{"phase": $phase, "ts": $ts, "proof": $proof}])' \
        "$STATE_FILE" | safe_json_write "$STATE_FILE"
    else
      jq --arg phase "$PHASE" --arg ts "$(timestamp)" \
        '.currentPhase = $phase | .lastHeartbeat = $ts | del(.loading) | .toolCallsByTranscript = {} | del(.primaryTranscriptKey) | .phaseHistory = ((.phaseHistory // []) + [$phase])' \
        "$STATE_FILE" | safe_json_write "$STATE_FILE"
    fi

    # --- Populate pendingPreloads for CMD file preloading ---
    # Resolve §CMD_X step/command names to CMD_X.md file paths (absolute, symlink-resolved).
    # The preload rule in guards.json fires when pendingPreloads is non-empty.
    if [ "$HAS_PHASES" = "true" ]; then
      CMD_DIR="$HOME/.claude/.directives/commands"
      PENDING_CMDS="[]"

      # Collect from both steps and commands arrays for the new phase
      for array_name in steps commands; do
        ARRAY_JSON=$(jq -r --arg rl "$REQ_LABEL" \
          "$JQ_LABEL_HELPERS (.phases[] | select(phase_lbl == \$rl) | .$array_name) // empty" \
          "$STATE_FILE" 2>/dev/null || echo "")
        if [ -n "$ARRAY_JSON" ] && [ "$ARRAY_JSON" != "null" ]; then
          ARRAY_COUNT=$(echo "$ARRAY_JSON" | jq 'length' 2>/dev/null || echo "0")
          if [ "$ARRAY_COUNT" -gt 0 ]; then
            for cmd_ref in $(echo "$ARRAY_JSON" | jq -r '.[]'); do
              # Strip §CMD_ prefix → CMD_X.md
              cmd_name="${cmd_ref#§CMD_}"
              cmd_file="$CMD_DIR/CMD_${cmd_name}.md"
              if [ -f "$cmd_file" ]; then
                # Normalize to absolute path and add if not already in the list
                norm_file=$(normalize_preload_path "$cmd_file")
                PENDING_CMDS=$(echo "$PENDING_CMDS" | jq --arg f "$norm_file" \
                  'if any(. == $f) then . else . + [$f] end')
              fi
            done
          fi
        fi
      done

      # Write to .state.json if any CMD files were found
      PENDING_COUNT=$(echo "$PENDING_CMDS" | jq 'length')
      if [ "$PENDING_COUNT" -gt 0 ]; then
        # Filter out already-preloaded files
        jq --argjson cmds "$PENDING_CMDS" \
          '(.preloadedFiles // []) as $already |
           ($cmds | map(select(. as $f | $already | any(. == $f) | not))) as $new |
           if ($new | length) > 0 then .pendingPreloads = ((.pendingPreloads // []) + $new | unique) else . end' \
          "$STATE_FILE" | safe_json_write "$STATE_FILE"
      fi
    fi

    # Notify fleet of state change (if running in fleet context)
    # WAITING: or DONE = needs attention (unchecked), otherwise = working (orange)
    if [[ "$PHASE" == WAITING:* ]] || [[ "$PHASE" == "DONE" ]]; then
      "$HOME/.claude/scripts/fleet.sh" notify unchecked 2>/dev/null || true
    else
      "$HOME/.claude/scripts/fleet.sh" notify working 2>/dev/null || true
    fi

    echo "Phase: $PHASE"

    # Output steps, commands, and proof for the new current phase (if declared)
    if [ "$HAS_PHASES" = "true" ]; then
      # Extract phase prefix for step sub-indexing (e.g., "1: Interrogation" → "1", "3.1: Agent Handoff" → "3.1")
      PHASE_PREFIX=$(echo "$PHASE" | sed -E 's/[: ].*//')

      # Output invariants for this phase (cognitive anchoring / grounding — agent self-affirms each)
      NEW_INVARIANTS=$(jq -r --arg rl "$REQ_LABEL" "
        $JQ_LABEL_HELPERS
        (.phases[] | select(phase_lbl == \$rl) | .invariants) // empty
      " "$STATE_FILE" 2>/dev/null || echo "")
      if [ -n "$NEW_INVARIANTS" ] && [ "$NEW_INVARIANTS" != "null" ]; then
        INV_COUNT=$(echo "$NEW_INVARIANTS" | jq 'length' 2>/dev/null || echo "0")
        if [ "$INV_COUNT" -gt 0 ]; then
          echo "Invariants:"
          echo "$NEW_INVARIANTS" | jq -r '.[] | "  - \(.)"'
        fi
      fi

      # Output steps listing with sub-indices
      NEW_STEPS=$(jq -r --arg rl "$REQ_LABEL" "
        $JQ_LABEL_HELPERS
        (.phases[] | select(phase_lbl == \$rl) | .steps) // empty
      " "$STATE_FILE" 2>/dev/null || echo "")
      if [ -n "$NEW_STEPS" ] && [ "$NEW_STEPS" != "null" ]; then
        STEP_COUNT=$(echo "$NEW_STEPS" | jq 'length' 2>/dev/null || echo "0")
        if [ "$STEP_COUNT" -gt 0 ]; then
          echo "Steps:"
          echo "$NEW_STEPS" | jq -r 'to_entries[] | "  '"$PHASE_PREFIX"'.\(.key + 1): \(.value)"'
        fi
      fi

      # Output commands listing (preloads for this phase)
      NEW_COMMANDS=$(jq -r --arg rl "$REQ_LABEL" "
        $JQ_LABEL_HELPERS
        (.phases[] | select(phase_lbl == \$rl) | .commands) // empty
      " "$STATE_FILE" 2>/dev/null || echo "")
      if [ -n "$NEW_COMMANDS" ] && [ "$NEW_COMMANDS" != "null" ]; then
        CMD_COUNT=$(echo "$NEW_COMMANDS" | jq 'length' 2>/dev/null || echo "0")
        if [ "$CMD_COUNT" -gt 0 ]; then
          echo "Commands:"
          echo "$NEW_COMMANDS" | jq -r '.[] | "  - \(.)"'
        fi
      fi

      # Output proof requirements (combined from steps[], commands[], and declared proof[])
      # Build the same combined schema used during FROM validation so agents see ALL required fields at entry
      ENTRY_PROPS="{}"
      ENTRY_REQ="[]"
      ENTRY_CMD_DIR="$HOME/.claude/engine/.directives/commands"

      # Merge proof from steps[] (reuses $NEW_STEPS already read above)
      if [ -n "${NEW_STEPS:-}" ] && [ "${NEW_STEPS:-}" != "null" ]; then
        for step_cmd in $(echo "$NEW_STEPS" | jq -r '.[]'); do
          cmd_name="${step_cmd#§CMD_}"
          cmd_file="$ENTRY_CMD_DIR/CMD_${cmd_name}.md"
          [ -f "$cmd_file" ] || continue
          json_block=$(extract_proof_schema "$cmd_file")
          if [ -n "$json_block" ] && echo "$json_block" | jq empty 2>/dev/null; then
            sp=$(echo "$json_block" | jq -r '.properties // empty' 2>/dev/null || echo "")
            sr=$(echo "$json_block" | jq -r '.required // empty' 2>/dev/null || echo "")
            [ -n "$sp" ] && [ "$sp" != "null" ] && ENTRY_PROPS=$(echo "$ENTRY_PROPS" | jq -s '.[0] * .[1]' - <(echo "$sp"))
            [ -n "$sr" ] && [ "$sr" != "null" ] && ENTRY_REQ=$(echo "$ENTRY_REQ" | jq -s '.[0] + .[1] | unique' - <(echo "$sr"))
          fi
        done
      fi

      # Merge proof from commands[] (reuses $NEW_COMMANDS already read above)
      if [ -n "${NEW_COMMANDS:-}" ] && [ "${NEW_COMMANDS:-}" != "null" ]; then
        for cmd_ref in $(echo "$NEW_COMMANDS" | jq -r '.[]'); do
          cmd_name="${cmd_ref#§CMD_}"
          cmd_file="$ENTRY_CMD_DIR/CMD_${cmd_name}.md"
          [ -f "$cmd_file" ] || continue
          json_block=$(extract_proof_schema "$cmd_file")
          if [ -n "$json_block" ] && echo "$json_block" | jq empty 2>/dev/null; then
            sp=$(echo "$json_block" | jq -r '.properties // empty' 2>/dev/null || echo "")
            sr=$(echo "$json_block" | jq -r '.required // empty' 2>/dev/null || echo "")
            [ -n "$sp" ] && [ "$sp" != "null" ] && ENTRY_PROPS=$(echo "$ENTRY_PROPS" | jq -s '.[0] * .[1]' - <(echo "$sp"))
            [ -n "$sr" ] && [ "$sr" != "null" ] && ENTRY_REQ=$(echo "$ENTRY_REQ" | jq -s '.[0] + .[1] | unique' - <(echo "$sr"))
          fi
        done
      fi

      # Add declared proof fields (phase-level fields from SKILL.md)
      NEW_PROOF_FIELDS=$(jq -r --arg rl "$REQ_LABEL" "
        $JQ_LABEL_HELPERS
        (.phases[] | select(phase_lbl == \$rl) | .proof) // empty
      " "$STATE_FILE" 2>/dev/null || echo "")
      if [ -n "$NEW_PROOF_FIELDS" ] && [ "$NEW_PROOF_FIELDS" != "null" ]; then
        for df in $(echo "$NEW_PROOF_FIELDS" | jq -r '.[]'); do
          [ -n "$df" ] || continue
          HAS_F=$(echo "$ENTRY_PROPS" | jq --arg f "$df" 'has($f)' 2>/dev/null || echo "false")
          if [ "$HAS_F" = "false" ]; then
            ENTRY_PROPS=$(echo "$ENTRY_PROPS" | jq --arg f "$df" '. + {($f): {"type": "string"}}')
          fi
          ENTRY_REQ=$(echo "$ENTRY_REQ" | jq --arg f "$df" 'if index($f) then . else . + [$f] end')
        done
      fi

      # Display combined proof with descriptions from CMD schemas
      ENTRY_REQ_COUNT=$(echo "$ENTRY_REQ" | jq 'length' 2>/dev/null || echo "0")
      if [ "$ENTRY_REQ_COUNT" -gt 0 ]; then
        echo "Proof required to leave this phase:"
        echo "$ENTRY_REQ" | jq -r --argjson props "$ENTRY_PROPS" '.[] |
          ($props[.].description // "") as $desc |
          if $desc != "" then "  - \(.): \($desc)" else "  - \(.)" end'
      fi

      # Output gate configuration (default: true)
      NEW_GATE=$(jq -r --arg rl "$REQ_LABEL" "
        $JQ_LABEL_HELPERS
        (.phases[] | select(phase_lbl == \$rl) | .gate) // true
      " "$STATE_FILE" 2>/dev/null || echo "true")
      echo "Gate: $NEW_GATE"
    fi
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

  continue)
    # Resume session after context overflow restart (used by /session continue).
    # Registers PID, sets lifecycle=active, clears loading flag, resets heartbeat counters.
    # Does NOT touch phase state — the saved phase in .state.json is the single source of truth.
    # Subsumes what `activate` does for resume scenarios — agent needs only this one command.
    #
    # Usage: session.sh continue [path]
    # If path omitted: auto-detect via fleet pane ID (tmux) or PID fallback
    # Output: Rich context info (session, skill, phase, log file, artifacts, next skills)

    # Auto-detect session if no path given
    if [ -z "$DIR" ]; then
      DIR=$("$0" find 2>/dev/null) || {
        echo "No active session found. Use a /skill to start one." >&2
        exit 1
      }
      STATE_FILE="$DIR/.state.json"
    fi

    if [ ! -f "$STATE_FILE" ]; then
      echo "§CMD_REQUIRE_ACTIVE_SESSION: No .state.json in $DIR — is the session active?" >&2
      exit 1
    fi

    # Check lifecycle — completed sessions should not be resumed
    LIFECYCLE=$(jq -r '.lifecycle // "active"' "$STATE_FILE")
    if [ "$LIFECYCLE" = "completed" ]; then
      echo "Session already completed. Nothing to resume." >&2
      # Still output next skills so the agent can route
      NEXT_SKILLS_C=$(jq -r '(.nextSkills // []) | .[]' "$STATE_FILE" 2>/dev/null || echo "")
      if [ -n "$NEXT_SKILLS_C" ]; then
        echo ""
        echo "## Next Skills"
        echo "$NEXT_SKILLS_C"
      fi
      exit 1
    fi

    # Register PID + set lifecycle=active + clear loading + reset heartbeat + reset context usage
    TARGET_PID="${CLAUDE_SUPERVISOR_PID:-$PPID}"
    jq --argjson pid "$TARGET_PID" --arg ts "$(timestamp)" \
      '.pid = $pid | .lifecycle = "active" | del(.loading) | .toolCallsByTranscript = {} | del(.primaryTranscriptKey) | .lastHeartbeat = $ts | .contextUsage = 0 | .overflowed = false | .killRequested = false' \
      "$STATE_FILE" | safe_json_write "$STATE_FILE"

    # Claim fleet pane: clear fleetPaneId from any OTHER session that has it (same as activate)
    FLEET_PANE_C=$(jq -r '.fleetPaneId // ""' "$STATE_FILE" 2>/dev/null)
    if [ -z "$FLEET_PANE_C" ]; then
      FLEET_PANE_C=$(get_fleet_pane_id 2>/dev/null || echo "")
    fi
    if [ -n "$FLEET_PANE_C" ]; then
      SESSIONS_DIR_C=$(dirname "$DIR")
      grep -l "\"fleetPaneId\": \"$FLEET_PANE_C\"" "$SESSIONS_DIR_C"/*/.state.json 2>/dev/null | while read -r other_file; do
        [ "$other_file" = "$STATE_FILE" ] && continue
        jq 'del(.fleetPaneId)' "$other_file" | safe_json_write "$other_file"
      done || true
    fi

    # Claim PID: clear our PID from any OTHER session that has it (same as activate)
    SESSIONS_DIR_C=$(dirname "$DIR")
    grep -l "\"pid\": $TARGET_PID" "$SESSIONS_DIR_C"/*/.state.json 2>/dev/null | while read -r other_file; do
      [ "$other_file" = "$STATE_FILE" ] && continue
      jq 'del(.pid)' "$other_file" | safe_json_write "$other_file"
    done || true

    # PID Cache: write on continue (same as activate)
    echo "$DIR" > "/tmp/claude-session-cache-$TARGET_PID" 2>/dev/null || true

    # --- Seed File Merge (continue-specific) ---
    # After context overflow restart, SessionStart created a seed with 6 boot files.
    # The session's preloadedFiles are stale (from the OLD process). Replace them
    # with the seed's preloadedFiles so the templates hook doesn't skip deps.
    SESSIONS_BASE=$(dirname "$DIR")
    SEED_FILE="$SESSIONS_BASE/.seeds/${TARGET_PID}.json"
    if [ -f "$SEED_FILE" ]; then
      SEED_LIFECYCLE=$(jq -r '.lifecycle // ""' "$SEED_FILE" 2>/dev/null || echo "")
      if [ "$SEED_LIFECYCLE" = "seeding" ]; then
        # REPLACE (not union) — seed has the truth of what this process has seen
        jq -s '
          (.[1].preloadedFiles // []) as $seedp |
          (.[1].pendingPreloads // []) as $seedpp |
          .[0] |
          .preloadedFiles = $seedp |
          .pendingPreloads = $seedpp
        ' "$STATE_FILE" "$SEED_FILE" | safe_json_write "$STATE_FILE"
        rm -f "$SEED_FILE"
      fi
    fi

    # Read state for rich output
    SKILL=$(jq -r '.skill // "unknown"' "$STATE_FILE")
    CURRENT_PHASE=$(jq -r '.currentPhase // "unknown"' "$STATE_FILE")
    LOG_FILE="${DIR}/$(echo "$SKILL" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z]/_/g')_LOG.md"

    # Derive log file from logTemplate if available (more reliable than skill name mangling)
    LOG_TEMPLATE=$(jq -r '.logTemplate // ""' "$STATE_FILE")
    if [ -n "$LOG_TEMPLATE" ]; then
      LOG_BASENAME=$(basename "$LOG_TEMPLATE")
      LOG_FILE="${DIR}/${LOG_BASENAME#TEMPLATE_}"
    fi

    echo "Session continued: $DIR"
    echo "  Skill: $SKILL"
    echo "  Phase: $CURRENT_PHASE"
    echo "  Log: $LOG_FILE"

    # List session artifacts for slow-path resume (agent uses this instead of manual ls)
    echo ""
    echo "## Artifacts"
    for f in "$DIR"/*.md; do
      [ -f "$f" ] && echo "  $(basename "$f")"
    done

    # Output nextSkills for routing context
    NEXT_SKILLS_C=$(jq -r '(.nextSkills // []) | .[]' "$STATE_FILE" 2>/dev/null || echo "")
    if [ -n "$NEXT_SKILLS_C" ]; then
      echo ""
      echo "## Next Skills"
      echo "$NEXT_SKILLS_C"
    fi
    ;;

  debrief)
    # Pre-flight scan for synthesis pipeline.
    # Reads phases array from .state.json, discovers §CMD_ proof fields,
    # runs scans for recognized commands, outputs structured Markdown.
    #
    # Usage: session.sh debrief <path>
    # Output: Markdown sections with ## §CMD_NAME (N) headings
    # Exit: 0 always (scan results are informational)

    if [ ! -f "$STATE_FILE" ]; then
      echo "§CMD_REQUIRE_ACTIVE_SESSION: No .state.json in $DIR — is the session active?" >&2
      exit 1
    fi

    # Step 1: Discover §CMD_ references from phases array (proof + steps + commands)
    HAS_PHASES=$(jq 'has("phases") and (.phases | length > 0)' "$STATE_FILE" 2>/dev/null || echo "false")
    if [ "$HAS_PHASES" != "true" ]; then
      echo "(no phases array — nothing to scan)"
      exit 0
    fi

    # Collect all unique §CMD_ names from proof[], steps[], and commands[] arrays
    CMD_FIELDS=$(jq -r '[.phases[] | ((.proof // [])[], (.steps // [])[], (.commands // [])[])] | unique | .[] | select(startswith("§CMD_"))' "$STATE_FILE" 2>/dev/null || echo "")

    if [ -z "$CMD_FIELDS" ]; then
      echo "(no §CMD_ references in phases — nothing to scan)"
      exit 0
    fi

    # Step 2: Output instructions header
    echo "## Instructions"
    echo "Process each section below in order. After completing all sections, prove each"
    echo "via \`session.sh phase\` with the §CMD_ names as proof keys."
    echo ""

    # Step 3: Run scans and output sections in canonical pipeline order
    # Canonical order: SCAN sections first, then STATIC, then DEPENDENT
    # Within SCAN: delegations → discoveries → leftover
    # Within STATIC: directives → cross-session-tags → backlinks → alerts
    # DEPENDENT: dispatch (only if delegations > 0)

    DELEGATIONS_COUNT=0

    # --- SCAN: §CMD_PROCESS_DELEGATIONS ---
    if echo "$CMD_FIELDS" | grep -q "§CMD_PROCESS_DELEGATIONS"; then
      # Scan for bare #needs-* tags in session artifacts (excluding backtick-escaped)
      DELEG_RESULTS=""
      if command -v "$HOME/.claude/scripts/tag.sh" > /dev/null 2>&1; then
        DELEG_RESULTS=$("$HOME/.claude/scripts/tag.sh" find '#needs-*' "$DIR" --context 2>/dev/null || echo "")
      else
        # Fallback: grep for bare #needs- tags (not backtick-escaped)
        DELEG_RESULTS=$(grep -rn '#needs-' "$DIR"/*.md 2>/dev/null | grep -v '`#needs-' || echo "")
      fi
      if [ -n "$DELEG_RESULTS" ]; then
        DELEGATIONS_COUNT=$(echo "$DELEG_RESULTS" | wc -l | tr -d ' ')
      fi
      echo "## §CMD_PROCESS_DELEGATIONS ($DELEGATIONS_COUNT)"
      if [ -n "$DELEG_RESULTS" ]; then
        echo "$DELEG_RESULTS"
      else
        echo "(none)"
      fi
      echo ""
    fi

    # --- SCAN: §CMD_CAPTURE_SIDE_DISCOVERIES ---
    if echo "$CMD_FIELDS" | grep -q "§CMD_CAPTURE_SIDE_DISCOVERIES"; then
      # Grep for side discovery emojis in LOG files: 👁️ (observation), 😟 (concern), 🗑️ (parking lot), 🅿️ (parking lot alt), 🩺 (doc observation)
      DISC_RESULTS=""
      for logfile in "$DIR"/*_LOG.md; do
        [ -f "$logfile" ] || continue
        DISC_LINES=$(grep -n '👁️\|😟\|🗑️\|🅿️\|🩺' "$logfile" 2>/dev/null || echo "")
        if [ -n "$DISC_LINES" ]; then
          while IFS= read -r dline; do
            DISC_RESULTS="${DISC_RESULTS}${DISC_RESULTS:+
}${logfile}:${dline}"
          done <<< "$DISC_LINES"
        fi
      done
      DISC_COUNT=0
      if [ -n "$DISC_RESULTS" ]; then
        DISC_COUNT=$(echo "$DISC_RESULTS" | wc -l | tr -d ' ')
      fi
      echo "## §CMD_CAPTURE_SIDE_DISCOVERIES ($DISC_COUNT)"
      if [ -n "$DISC_RESULTS" ]; then
        echo "$DISC_RESULTS"
      else
        echo "(none)"
      fi
      echo ""
    fi

    # --- SCAN: §CMD_REPORT_LEFTOVER_WORK ---
    if echo "$CMD_FIELDS" | grep -q "§CMD_REPORT_LEFTOVER_WORK"; then
      LEFT_RESULTS=""
      # Scan PLAN files for unchecked items: [ ]
      for planfile in "$DIR"/*_PLAN.md "$DIR"/*PLAN*.md; do
        [ -f "$planfile" ] || continue
        UNCHECKED=$(grep -n '\[ \]' "$planfile" 2>/dev/null || echo "")
        if [ -n "$UNCHECKED" ]; then
          while IFS= read -r uline; do
            LEFT_RESULTS="${LEFT_RESULTS}${LEFT_RESULTS:+
}${planfile}:${uline}"
          done <<< "$UNCHECKED"
        fi
      done
      # Scan LOG files for unresolved blocks: 🚧 Block
      for logfile in "$DIR"/*_LOG.md; do
        [ -f "$logfile" ] || continue
        BLOCKS=$(grep -n '🚧 Block' "$logfile" 2>/dev/null || echo "")
        if [ -n "$BLOCKS" ]; then
          while IFS= read -r bline; do
            LEFT_RESULTS="${LEFT_RESULTS}${LEFT_RESULTS:+
}${logfile}:${bline}"
          done <<< "$BLOCKS"
        fi
      done
      # Scan debrief files for tech debt (💸) and unchecked doc impact items
      for debrieffile in "$DIR"/*.md; do
        [ -f "$debrieffile" ] || continue
        # Skip LOG and PLAN files (already scanned above)
        case "$(basename "$debrieffile")" in
          *_LOG.md|*_PLAN.md|DIALOGUE.md) continue ;;
        esac
        DEBT=$(grep -n '💸' "$debrieffile" 2>/dev/null || echo "")
        if [ -n "$DEBT" ]; then
          while IFS= read -r dline; do
            LEFT_RESULTS="${LEFT_RESULTS}${LEFT_RESULTS:+
}${debrieffile}:${dline}"
          done <<< "$DEBT"
        fi
      done
      LEFT_COUNT=0
      if [ -n "$LEFT_RESULTS" ]; then
        LEFT_COUNT=$(echo "$LEFT_RESULTS" | wc -l | tr -d ' ')
      fi
      echo "## §CMD_REPORT_LEFTOVER_WORK ($LEFT_COUNT)"
      if [ -n "$LEFT_RESULTS" ]; then
        echo "$LEFT_RESULTS"
      else
        echo "(none)"
      fi
      echo ""
    fi

    # --- STATIC: §CMD_MANAGE_DIRECTIVES ---
    if echo "$CMD_FIELDS" | grep -q "§CMD_MANAGE_DIRECTIVES"; then
      echo "## §CMD_MANAGE_DIRECTIVES"
      echo "Review whether session work warrants directive updates:"
      echo "- AGENTS.md — doc directory READMEs near touched files"
      echo "- INVARIANTS.md — new rules or constraints discovered"
      echo "- PITFALLS.md — gotchas encountered during implementation"
      echo "- CONTRIBUTING.md — patterns worth documenting for contributors"
      echo "- TEMPLATE.md — template updates needed"
      echo ""
    fi

    # --- STATIC: §CMD_RESOLVE_CROSS_SESSION_TAGS ---
    if echo "$CMD_FIELDS" | grep -q "§CMD_RESOLVE_CROSS_SESSION_TAGS"; then
      echo "## §CMD_RESOLVE_CROSS_SESSION_TAGS"
      echo "Check if this session's work resolves tags in other sessions."
      echo "- Scan request files this session is fulfilling"
      echo "- Trace back to requesting sessions and resolve source tags"
      echo ""
    fi

    # --- STATIC: §CMD_MANAGE_BACKLINKS ---
    if echo "$CMD_FIELDS" | grep -q "§CMD_MANAGE_BACKLINKS"; then
      echo "## §CMD_MANAGE_BACKLINKS"
      echo "Detect and create cross-session links."
      echo "- Continuations: sessions that continue this work"
      echo "- Derived work: sessions spawned from this session's findings"
      echo "- Delegations: request/response relationships"
      echo ""
    fi

    # --- STATIC: §CMD_MANAGE_ALERTS ---
    if echo "$CMD_FIELDS" | grep -q "§CMD_MANAGE_ALERTS"; then
      echo "## §CMD_MANAGE_ALERTS"
      echo "Check whether to raise or resolve alerts based on session work."
      echo "- Raise: Ongoing issues that future sessions need to know about"
      echo "- Resolve: Previously raised alerts that this session addressed"
      echo ""
    fi

    # --- DEPENDENT: §CMD_DISPATCH_APPROVAL ---
    if echo "$CMD_FIELDS" | grep -q "§CMD_DISPATCH_APPROVAL"; then
      if [ "$DELEGATIONS_COUNT" -gt 0 ]; then
        echo "## §CMD_DISPATCH_APPROVAL"
        echo "Delegation scan found $DELEGATIONS_COUNT items above."
        echo "Present dispatch approval walkthrough for user triage."
        echo ""
      fi
      # If delegations = 0, dispatch section is omitted (nothing to dispatch)
    fi

    exit 0
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
          echo "§CMD_CLOSE_SESSION: Unknown flag '$1'" >&2
          shift
          ;;
      esac
    done

    # Read stdin (description or proof, depending on lifecycle — see below)
    STDIN_INPUT=""
    if [ ! -t 0 ]; then
      STDIN_INPUT=$(cat)
    fi

    # --- Lifecycle-aware stdin interpretation ---
    # If session is idle (went through engine session idle), description is already stored.
    # Stdin is interpreted as terminal phase proof instead.
    PROOF_INPUT=""
    DESCRIPTION=""
    LIFECYCLE=$(jq -r '.lifecycle // "active"' "$STATE_FILE" 2>/dev/null || echo "active")
    if [ "$LIFECYCLE" = "idle" ]; then
      PROOF_INPUT="$STDIN_INPUT"
      DESCRIPTION=$(jq -r '.sessionDescription // ""' "$STATE_FILE" 2>/dev/null || echo "")
    else
      DESCRIPTION="$STDIN_INPUT"
    fi

    # --- Smart Deactivate: skip validation gates for early phases ---
    # Phase 0 (Setup) and Phase 1 (Interrogation) have no work product to debrief.
    # When currentPhase major <= 1, skip debrief/checklist/proof gates entirely.
    CURRENT_PHASE=$(jq -r '.currentPhase // ""' "$STATE_FILE" 2>/dev/null || echo "")
    PHASE_MAJOR=$(echo "$CURRENT_PHASE" | grep -oE '^[0-9]+' || echo "0")
    EARLY_PHASE=false
    if [ "$PHASE_MAJOR" -le 1 ] 2>/dev/null; then
      EARLY_PHASE=true
    fi

    # PID Cache: invalidate before deactivation
    DEACTIVATE_PID=$(jq -r '.pid // empty' "$STATE_FILE" 2>/dev/null)
    if [ -n "$DEACTIVATE_PID" ]; then
      rm -f "/tmp/claude-session-cache-$DEACTIVATE_PID" 2>/dev/null || true
    fi

    # --- Collect all validation errors before exiting ---
    # All gates append to DEACTIVATE_ERRORS instead of exiting immediately.
    # This lets the agent see ALL issues at once and fix them in a single pass.
    DEACTIVATE_ERRORS=()

    # --- Description Gate (§CMD_CLOSE_SESSION) ---
    if [ -z "$DESCRIPTION" ]; then
      DEACTIVATE_ERRORS+=("$(printf '%s\n%s\n%s\n%s' \
        "§CMD_CLOSE_SESSION: Description is required. Pipe 1-3 lines via stdin:" \
        "  session.sh deactivate <path> [--keywords 'kw1,kw2'] <<'EOF'" \
        "  What was done in this session (1-3 lines)" \
        "  EOF")")
    fi

    # --- Debrief Gate (§CMD_CLOSE_SESSION) ---
    # Check if the skill's debrief file exists before allowing deactivation
    # Derives filename from debriefTemplate in .state.json (e.g., TEMPLATE_TESTING.md → TESTING.md)
    # Skipped for early phases (Phase 0/1) — no work product to debrief
    if [ "$EARLY_PHASE" = "true" ]; then
      SKIP_DEBRIEF="Early abandonment — phase $PHASE_MAJOR has no work product"
    fi
    if [ -z "$SKIP_DEBRIEF" ]; then
      DEBRIEF_TEMPLATE=$(jq -r '.debriefTemplate // ""' "$STATE_FILE" 2>/dev/null || echo "")
      if [ -n "$DEBRIEF_TEMPLATE" ]; then
        DEBRIEF_BASENAME=$(basename "$DEBRIEF_TEMPLATE")
        DEBRIEF_NAME="${DEBRIEF_BASENAME#TEMPLATE_}"
        DEBRIEF_FILE="$DIR/$DEBRIEF_NAME"
        if [ ! -f "$DEBRIEF_FILE" ]; then
          DEACTIVATE_ERRORS+=("$(printf '%s\n%s\n%s\n%s\n%s' \
            "§CMD_CLOSE_SESSION: Cannot deactivate — no debrief file found." \
            "  Expected: $DEBRIEF_NAME in $DIR" \
            "" \
            "  To fix: Write the debrief via §CMD_GENERATE_DEBRIEF." \
            "  To skip: session.sh deactivate $DIR --user-approved \"Reason: [quote user's words]\"")")
        fi
      fi
    fi

    # --- Checklist Gate (¶INV_CHECKLIST_BEFORE_CLOSE) ---
    # Requires checkPassed=true (set by session.sh check) if any checklists were discovered
    # Skipped for early phases (Phase 0/1) — no checklists apply
    DISCOVERED=$(jq -r '(.discoveredChecklists // []) | length' "$STATE_FILE" 2>/dev/null || echo "0")
    if [ "$EARLY_PHASE" != "true" ] && [ "$DISCOVERED" -gt 0 ]; then
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

    # --- Terminal Phase Proof Gate (¶INV_PHASE_ENFORCEMENT) ---
    # When deactivating from idle, validate proof for the current (terminal) phase.
    # Mirrors FROM validation in engine session phase — the terminal phase never gets
    # FROM-validated because there's no next phase transition. Deactivation IS the terminal transition.
    # Only applies when: session was idle (stdin=proof), not early phase, phases array exists.
    HAS_PHASES=$(jq 'has("phases") and (.phases | length > 0)' "$STATE_FILE" 2>/dev/null || echo "false")
    if [ "$EARLY_PHASE" != "true" ] && [ "$LIFECYCLE" = "idle" ] && [ "$HAS_PHASES" = "true" ] && [ -n "$CURRENT_PHASE" ]; then
      CUR_LABEL=$(echo "$CURRENT_PHASE" | sed -E 's/: .*//')

      # jq helper (same as phase case)
      JQ_DEACT_HELPERS='
        def phase_lbl: if has("label") then .label elif .minor == 0 then "\(.major)" else "\(.major).\(.minor)" end;
      '

      # Look up proof fields for current (terminal) phase
      TERM_PROOF_JSON=$(jq -r --arg cl "$CUR_LABEL" "
        $JQ_DEACT_HELPERS
        (.phases[] | select(phase_lbl == \$cl) | .proof) // empty
      " "$STATE_FILE" 2>/dev/null || echo "")

      if [ -n "$TERM_PROOF_JSON" ] && [ "$TERM_PROOF_JSON" != "null" ]; then
        TERM_PROOF_COUNT=$(echo "$TERM_PROOF_JSON" | jq 'length' 2>/dev/null || echo "0")

        if [ "$TERM_PROOF_COUNT" -gt 0 ]; then
          # Parse proof from stdin (same format as phase: key: value lines)
          TERM_PROOF_OBJ="{}"
          if [ -n "$PROOF_INPUT" ]; then
            while IFS= read -r line; do
              [ -n "$line" ] || continue
              PKEY=$(echo "$line" | sed -n 's/^\([§a-zA-Z_][§a-zA-Z0-9_]*\): .*/\1/p')
              [ -z "$PKEY" ] && continue
              PVAL="${line#*: }"
              TERM_PROOF_OBJ=$(echo "$TERM_PROOF_OBJ" | jq --arg k "$PKEY" --arg v "$PVAL" '. + {($k): $v}')
            done <<< "$PROOF_INPUT"
          fi

          if [ -z "$PROOF_INPUT" ]; then
            term_proof_err="$(printf '%s\n%s\n%s\n%s' \
              "¶INV_PHASE_ENFORCEMENT: Terminal proof required — current phase '$CURRENT_PHASE' has proof fields but no proof provided via stdin." \
              "  Required proof fields: $(echo "$TERM_PROOF_JSON" | jq -r 'join(", ")')" \
              "" \
              "  Usage: engine session deactivate $DIR [--keywords ...] <<< 'field: value'")"
            DEACTIVATE_ERRORS+=("$term_proof_err")
          else
            # Validate all required fields are present
            MISSING_TERM_FIELDS=""
            for field in $(echo "$TERM_PROOF_JSON" | jq -r '.[]'); do
              FIELD_VAL=$(echo "$TERM_PROOF_OBJ" | jq -r --arg f "$field" '.[$f] // ""')
              if [ -z "$FIELD_VAL" ]; then
                MISSING_TERM_FIELDS="${MISSING_TERM_FIELDS}${MISSING_TERM_FIELDS:+, }$field"
              elif [ "$FIELD_VAL" = "________" ]; then
                MISSING_TERM_FIELDS="${MISSING_TERM_FIELDS}${MISSING_TERM_FIELDS:+, }$field (unfilled blank)"
              fi
            done

            if [ -n "$MISSING_TERM_FIELDS" ]; then
              term_proof_err="$(printf '%s\n%s\n%s' \
                "¶INV_PHASE_ENFORCEMENT: Terminal proof incomplete — missing: $MISSING_TERM_FIELDS" \
                "  Required: $(echo "$TERM_PROOF_JSON" | jq -r 'join(", ")')" \
                "  Provided: $(echo "$TERM_PROOF_OBJ" | jq -r 'keys | join(", ")')")"
              DEACTIVATE_ERRORS+=("$term_proof_err")
            fi
          fi
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

    # Output nextSkills so the agent can present the menu without reading .state.json
    NEXT_SKILLS=$(jq -r '(.nextSkills // []) | .[]' "$STATE_FILE" 2>/dev/null || echo "")
    if [ -n "$NEXT_SKILLS" ]; then
      echo ""
      echo "## Next Skills"
      echo "$NEXT_SKILLS"
    fi

    # Run RAG search FIRST (query old index — still useful for session linkage)
    # The search scripts load .env internally — no GEMINI_API_KEY guard needed here
    SESSION_SEARCH="$HOME/.claude/tools/session-search/session-search.sh"
    DOC_SEARCH="$HOME/.claude/tools/doc-search/doc-search.sh"
    if [ -x "$SESSION_SEARCH" ]; then
      RAG_RESULTS=$("$SESSION_SEARCH" query "$DESCRIPTION" --limit 5 2>/dev/null || echo "")
      if [ -n "$RAG_RESULTS" ]; then
        echo ""
        echo "## Related Sessions"
        echo "$RAG_RESULTS"
      fi
    fi

    # THEN reindex search databases (background, best-effort)
    # Keeps RAG fresh so the next session's context ingestion finds this session's work
    "$SESSION_SEARCH" index &>/dev/null &
    "$DOC_SEARCH" index &>/dev/null &
    ;;

  idle)
    # Transition session to idle state (post-synthesis, awaiting next skill)
    # Usage: engine session idle <path> [--keywords 'kw1,kw2'] <<DESCRIPTION
    # Like deactivate but sets lifecycle=idle instead of completed, and clears PID.
    # The session remains reactivatable via `engine session activate`.
    if [ ! -f "$STATE_FILE" ]; then
      echo "§CMD_REQUIRE_ACTIVE_SESSION: No .state.json in $DIR — is the session active?" >&2
      exit 1
    fi

    # Parse optional flags
    KEYWORDS=""
    shift 2  # Remove action, dir
    while [ $# -gt 0 ]; do
      case "$1" in
        --keywords)
          KEYWORDS="${2:?--keywords requires a value}"
          shift 2
          ;;
        *)
          echo "§CMD_CLOSE_SESSION: Unknown flag '$1'" >&2
          shift
          ;;
      esac
    done

    # Read description from stdin
    DESCRIPTION=""
    if [ ! -t 0 ]; then
      DESCRIPTION=$(cat)
    fi
    if [ -z "$DESCRIPTION" ]; then
      echo "§CMD_CLOSE_SESSION: Description is required. Pipe 1-3 lines via stdin." >&2
      exit 1
    fi

    # PID Cache: invalidate before clearing PID
    IDLE_PID=$(jq -r '.pid // empty' "$STATE_FILE" 2>/dev/null)
    if [ -n "$IDLE_PID" ]; then
      rm -f "/tmp/claude-session-cache-$IDLE_PID" 2>/dev/null || true
    fi

    # Set lifecycle=idle, preserve PID as lastKnownPid, clear active PID, store description/keywords
    # lastKnownPid enables session.sh find to locate idle sessions (Strategy 3)
    # without claiming ownership (multi-agent safe — different from keeping .pid)
    if [ -n "$KEYWORDS" ]; then
      jq --arg ts "$(timestamp)" --arg desc "$DESCRIPTION" --arg kw "$KEYWORDS" \
        '.lifecycle = "idle" | .lastKnownPid = .pid | del(.pid) | .lastHeartbeat = $ts | .sessionDescription = $desc | .searchKeywords = ($kw | split(",") | map(gsub("^\\s+|\\s+$"; "")))' \
        "$STATE_FILE" | safe_json_write "$STATE_FILE"
    else
      jq --arg ts "$(timestamp)" --arg desc "$DESCRIPTION" \
        '.lifecycle = "idle" | .lastKnownPid = .pid | del(.pid) | .lastHeartbeat = $ts | .sessionDescription = $desc' \
        "$STATE_FILE" | safe_json_write "$STATE_FILE"
    fi

    # Append current skill to completedSkills
    CURRENT_SKILL=$(jq -r '.skill // empty' "$STATE_FILE" 2>/dev/null || echo "")
    if [ -n "$CURRENT_SKILL" ]; then
      jq --arg s "$CURRENT_SKILL" \
        'if (.completedSkills // []) | any(. == $s) then . else .completedSkills = ((.completedSkills // []) + [$s]) end' \
        "$STATE_FILE" | safe_json_write "$STATE_FILE"
    fi

    echo "Session idle: $DIR (lifecycle=idle, awaiting next skill)"

    # Output nextSkills so the agent can present the menu without reading .state.json
    NEXT_SKILLS=$(jq -r '(.nextSkills // []) | .[]' "$STATE_FILE" 2>/dev/null || echo "")
    if [ -n "$NEXT_SKILLS" ]; then
      echo ""
      echo "## Next Skills"
      echo "$NEXT_SKILLS"
    fi

    # Run RAG search (same as deactivate)
    SESSION_SEARCH="$HOME/.claude/tools/session-search/session-search.sh"
    DOC_SEARCH="$HOME/.claude/tools/doc-search/doc-search.sh"
    if [ -x "$SESSION_SEARCH" ]; then
      RAG_RESULTS=$("$SESSION_SEARCH" query "$DESCRIPTION" --limit 5 2>/dev/null || echo "")
      if [ -n "$RAG_RESULTS" ]; then
        echo ""
        echo "## Related Sessions"
        echo "$RAG_RESULTS"
      fi
    fi

    # Reindex in background
    "$SESSION_SEARCH" index &>/dev/null &
    "$DOC_SEARCH" index &>/dev/null &
    ;;

  dehydrate)
    # Combined dehydrate + restart: stores JSON in .state.json, then triggers restart
    # Usage: engine session dehydrate <path> <<< '{"summary":"...","requiredFiles":[...]}'
    if [ ! -f "$STATE_FILE" ]; then
      echo "Error: No .state.json in $DIR — is the session active?" >&2
      exit 1
    fi

    # Read JSON from stdin
    DEHYDRATED_JSON=$(cat)
    if [ -z "$DEHYDRATED_JSON" ]; then
      echo "Error: No JSON provided on stdin" >&2
      exit 1
    fi

    # Validate it's valid JSON
    if ! echo "$DEHYDRATED_JSON" | jq empty 2>/dev/null; then
      echo "Error: Invalid JSON on stdin" >&2
      exit 1
    fi

    # Cap requiredFiles at 8
    FILE_COUNT=$(echo "$DEHYDRATED_JSON" | jq '.requiredFiles // [] | length' 2>/dev/null || echo "0")
    if [ "$FILE_COUNT" -gt 8 ]; then
      echo "Warning: requiredFiles has $FILE_COUNT entries, capping at 8" >&2
      DEHYDRATED_JSON=$(echo "$DEHYDRATED_JSON" | jq '.requiredFiles = (.requiredFiles // [])[:8]')
    fi

    # Merge into .state.json under dehydratedContext key
    jq --argjson ctx "$DEHYDRATED_JSON" '.dehydratedContext = $ctx' "$STATE_FILE" | safe_json_write "$STATE_FILE"
    echo "Dehydrated context saved to $STATE_FILE"

    # Trigger restart (same logic as restart subcommand)
    SKILL=$(jq -r '.skill' "$STATE_FILE")
    CURRENT_PHASE=$(jq -r '.currentPhase // "Phase 1: Setup"' "$STATE_FILE")
    PROMPT="/session continue --session $DIR --skill $SKILL --phase \"$CURRENT_PHASE\""

    # dehydratedContext is always present (we just wrote it) — use hook-based restore
    RESTART_MODE="hook"

    jq --arg ts "$(timestamp)" --arg prompt "$PROMPT" --arg mode "$RESTART_MODE" \
      '.killRequested = true | .lastHeartbeat = $ts | .restartPrompt = $prompt | .restartMode = $mode | .contextUsage = 0 | del(.sessionId)' \
      "$STATE_FILE" | safe_json_write "$STATE_FILE"

    # Signal restart
    if [ "${TEST_MODE:-}" = "1" ]; then
      echo "TEST: Would send tmux keystroke injection to restart session"
      echo "TEST: Prompt: $PROMPT"
      echo "TEST: Restart mode: $RESTART_MODE"
    elif [ -n "${TMUX:-}" ] && [ "${DISABLE_CLEAR:-}" != "1" ]; then
      target_flag=""
      if [ -n "${TMUX_PANE:-}" ]; then
        target_flag="-t $TMUX_PANE"
      fi
      (
        sleep 0.5
        tmux send-keys $target_flag Escape 2>/dev/null
        sleep 1
        tmux send-keys $target_flag Escape 2>/dev/null
        sleep 0.5
        tmux send-keys $target_flag -l "/clear" 2>/dev/null
        tmux send-keys $target_flag Enter 2>/dev/null
        if [ -n "$PROMPT" ]; then
          sleep 1.5
          tmux send-keys $target_flag -l "$PROMPT" 2>/dev/null
          tmux send-keys $target_flag Enter 2>/dev/null
        fi
      ) &
      disown
      echo "Dehydrated and restart prepared. Sending /clear + prompt via tmux."
    elif [ -n "${WATCHDOG_PID:-}" ]; then
      echo "Dehydrated. Signaling watchdog (PID $WATCHDOG_PID) to restart..."
      kill -USR1 "$WATCHDOG_PID" 2>/dev/null || true
    else
      echo "Dehydrated to $STATE_FILE. No tmux/watchdog — restart manually:"
      echo "  claude '$PROMPT'"
    fi
    exit 0
    ;;

  restart)
    if [ ! -f "$STATE_FILE" ]; then
      echo "§CMD_REQUIRE_ACTIVE_SESSION: No .state.json in $DIR — is the session active?" >&2
      exit 1
    fi

    # Read current state
    SKILL=$(jq -r '.skill' "$STATE_FILE")
    CURRENT_PHASE=$(jq -r '.currentPhase // "Phase 1: Setup"' "$STATE_FILE")

    # Create the prompt for the new Claude - invoke /session continue for unbroken restart
    PROMPT="/session continue --session $DIR --skill $SKILL --phase \"$CURRENT_PHASE\""

    # Detect if hook-based restore is available (dehydratedContext exists in .state.json)
    HAS_DEHYDRATED=$(jq -r '.dehydratedContext // null | type' "$STATE_FILE" 2>/dev/null)
    if [ "$HAS_DEHYDRATED" = "object" ]; then
      RESTART_MODE="hook"
    else
      RESTART_MODE="prompt"
    fi

    # State-only restart: set killRequested, write restartPrompt, reset contextUsage, delete sessionId
    # restartMode: "hook" = SessionStart hook will inject context; "prompt" = /session continue fallback
    # The watchdog (signaled below) handles the actual kill
    jq --arg ts "$(timestamp)" --arg prompt "$PROMPT" --arg mode "$RESTART_MODE" \
      '.killRequested = true | .lastHeartbeat = $ts | .restartPrompt = $prompt | .restartMode = $mode | .contextUsage = 0 | del(.sessionId)' \
      "$STATE_FILE" | safe_json_write "$STATE_FILE"

    # Signal restart — tmux keystroke injection (preferred) or watchdog kill (fallback)
    # TEST_MODE=1 skips tmux injection to prevent sending /clear to the test runner's pane
    if [ "${TEST_MODE:-}" = "1" ]; then
      echo "TEST: Would send tmux keystroke injection to restart session"
      echo "TEST: Prompt: $PROMPT"
      echo "TEST: Restart mode: $RESTART_MODE"
    elif [ -n "${TMUX:-}" ] && [ "${DISABLE_CLEAR:-}" != "1" ]; then
      # tmux path: send Esc → 1s delay → Esc → /clear → Enter
      target_flag=""
      if [ -n "${TMUX_PANE:-}" ]; then
        target_flag="-t $TMUX_PANE"
      fi
      # Background the keystroke sequence to avoid race condition:
      # the Esc would interrupt Claude mid-execution of this script
      (
        sleep 0.5  # let the calling command finish first
        tmux send-keys $target_flag Escape 2>/dev/null
        sleep 1
        tmux send-keys $target_flag Escape 2>/dev/null
        sleep 0.5
        tmux send-keys $target_flag -l "/clear" 2>/dev/null
        tmux send-keys $target_flag Enter 2>/dev/null
        # Send restart prompt after /clear settles (if set)
        if [ -n "$PROMPT" ]; then
          sleep 1.5
          tmux send-keys $target_flag -l "$PROMPT" 2>/dev/null
          tmux send-keys $target_flag Enter 2>/dev/null
        fi
      ) &
      disown
      echo "Restart prepared. Sending /clear + prompt via tmux keystroke injection (backgrounded)."
    elif [ -n "${WATCHDOG_PID:-}" ]; then
      echo "Restart prepared. Signaling watchdog (PID $WATCHDOG_PID) to kill Claude..."
      kill -USR1 "$WATCHDOG_PID" 2>/dev/null || true
    else
      echo "§CMD_RECOVER_SESSION: No watchdog active (WATCHDOG_PID not set)."
      echo "Not running under run.sh wrapper. To restart manually, run:"
      echo ""
      echo "claude '$PROMPT'"
    fi
    exit 0
    ;;

  clear)
    # Clear context and restart fresh — no session continuation prompt.
    # Used by §CMD_PRESENT_NEXT_STEPS "Done and clear" option.
    # Unlike restart, this does NOT set a restartPrompt — the new Claude starts blank.
    #
    # TMUX: sends /clear via keystroke injection (context reset, no process kill)
    # Watchdog: sets killRequested=true (no prompt), watchdog kills, run.sh loops fresh
    # Neither: prints manual instructions
    if [ ! -f "$STATE_FILE" ]; then
      echo "§CMD_REQUIRE_ACTIVE_SESSION: No .state.json in $DIR — is the session active?" >&2
      exit 1
    fi

    # Set killRequested but NO restartPrompt — signals "restart fresh" to run.sh
    jq --arg ts "$(timestamp)" \
      '.killRequested = true | .lastHeartbeat = $ts | .contextUsage = 0 | del(.sessionId) | del(.restartPrompt)' \
      "$STATE_FILE" | safe_json_write "$STATE_FILE"

    if [ "${TEST_MODE:-}" = "1" ]; then
      echo "TEST: Would clear context (tmux /clear or watchdog kill)"
    elif [ -n "${TMUX:-}" ] && [ "${DISABLE_CLEAR:-}" != "1" ]; then
      # tmux path: send /clear to reset context without killing process
      target_flag=""
      if [ -n "${TMUX_PANE:-}" ]; then
        target_flag="-t $TMUX_PANE"
      fi
      (
        sleep 0.5
        tmux send-keys $target_flag Escape 2>/dev/null
        sleep 1
        tmux send-keys $target_flag Escape 2>/dev/null
        sleep 0.5
        tmux send-keys $target_flag -l "/clear" 2>/dev/null
        tmux send-keys $target_flag Enter 2>/dev/null
      ) &
      disown
      echo "Clearing context via tmux /clear."
    elif [ -n "${WATCHDOG_PID:-}" ]; then
      echo "Signaling watchdog (PID $WATCHDOG_PID) to restart fresh..."
      kill -USR1 "$WATCHDOG_PID" 2>/dev/null || true
    else
      echo "No tmux/watchdog available. Restart manually."
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

    # Build search paths: workspace sessions first, then global fallback
    SEARCH_PATHS=()
    if [ -n "${WORKSPACE:-}" ] && [ -d "$PWD/${WORKSPACE}/sessions" ]; then
      SEARCH_PATHS+=("$PWD/${WORKSPACE}/sessions")
    fi
    if [ -d "$PWD/sessions" ]; then
      SEARCH_PATHS+=("$PWD/sessions")
    fi
    if [ ${#SEARCH_PATHS[@]} -eq 0 ]; then
      exit 1
    fi

    CLAUDE_PID="${CLAUDE_SUPERVISOR_PID:-$PPID}"
    FOUND_DIR=""

    # --- PID Cache: fast path ---
    # Cache written by activate/continue, keyed by PID. Avoids full sweep.
    CACHE_FILE="/tmp/claude-session-cache-$CLAUDE_PID"
    if [ -f "$CACHE_FILE" ]; then
      CACHED_DIR=$(cat "$CACHE_FILE" 2>/dev/null) || CACHED_DIR=""
      if [ -n "$CACHED_DIR" ] && [ -f "$CACHED_DIR/.state.json" ]; then
        # Validate: PID or fleet pane must still match
        cached_pid=$(jq -r '.pid // empty' "$CACHED_DIR/.state.json" 2>/dev/null)
        if [ "$cached_pid" = "$CLAUDE_PID" ]; then
          echo "$CACHED_DIR"
          exit 0
        fi
        # Fleet fallback: check fleetPaneId match
        FLEET_PANE_CHECK=$(get_fleet_pane_id)
        if [ -n "$FLEET_PANE_CHECK" ]; then
          cached_fleet=$(jq -r '.fleetPaneId // ""' "$CACHED_DIR/.state.json" 2>/dev/null)
          if [ "$cached_fleet" = "$FLEET_PANE_CHECK" ]; then
            # PID guard: reject if a different alive PID holds the session
            if [ -n "$cached_pid" ] && [ "$cached_pid" != "$CLAUDE_PID" ]; then
              if kill -0 "$cached_pid" 2>/dev/null; then
                exit 1
              fi
            fi
            echo "$CACHED_DIR"
            exit 0
          fi
        fi
      fi
      # Cache stale — remove and fall through to sweep
      rm -f "$CACHE_FILE" 2>/dev/null || true
    fi

    # Strategy 1: Fleet mode — lookup by fleetPaneId
    FLEET_PANE=$(get_fleet_pane_id)
    if [ -n "$FLEET_PANE" ]; then
      for SESSIONS_DIR in "${SEARCH_PATHS[@]}"; do
        while IFS= read -r f; do
          [ -f "$f" ] || continue
          file_fleet_pane=$(jq -r '.fleetPaneId // ""' "$f" 2>/dev/null)
          if [ "$file_fleet_pane" = "$FLEET_PANE" ]; then
            # PID guard: reject if a different alive PID holds the session
            file_pid=$(jq -r '.pid // empty' "$f" 2>/dev/null)
            if [ -n "$file_pid" ] && [ "$file_pid" != "$CLAUDE_PID" ]; then
              if kill -0 "$file_pid" 2>/dev/null; then
                # Different Claude is active — not our session
                exit 1
              fi
            fi
            FOUND_DIR=$(dirname "$f")
            break 2
          fi
        done < <(find -L "$SESSIONS_DIR" -name ".state.json" -type f 2>/dev/null)
      done
    fi

    # Strategy 2: Non-fleet fallback — lookup by PID
    if [ -z "$FOUND_DIR" ]; then
      for SESSIONS_DIR in "${SEARCH_PATHS[@]}"; do
        while IFS= read -r f; do
          [ -f "$f" ] || continue
          file_pid=$(jq -r '.pid // empty' "$f" 2>/dev/null)
          if [ -n "$file_pid" ] && [ "$file_pid" = "$CLAUDE_PID" ]; then
            FOUND_DIR=$(dirname "$f")
            break 2
          fi
        done < <(find -L "$SESSIONS_DIR" -name ".state.json" -type f 2>/dev/null)
      done
    fi

    # Strategy 3: Match by lastKnownPid (for idle sessions where PID was cleared)
    # lastKnownPid is set by `engine session idle` before clearing .pid
    # Same PID guard applies — reject if a different alive PID holds the session
    if [ -z "$FOUND_DIR" ]; then
      for SESSIONS_DIR in "${SEARCH_PATHS[@]}"; do
        while IFS= read -r f; do
          [ -f "$f" ] || continue
          file_last_pid=$(jq -r '.lastKnownPid // empty' "$f" 2>/dev/null)
          if [ -n "$file_last_pid" ] && [ "$file_last_pid" = "$CLAUDE_PID" ]; then
            # PID guard: reject if a different alive PID holds the session
            file_pid=$(jq -r '.pid // empty' "$f" 2>/dev/null)
            if [ -n "$file_pid" ] && [ "$file_pid" != "$CLAUDE_PID" ]; then
              if kill -0 "$file_pid" 2>/dev/null; then
                exit 1
              fi
            fi
            FOUND_DIR=$(dirname "$f")
            break 2
          fi
        done < <(find -L "$SESSIONS_DIR" -name ".state.json" -type f 2>/dev/null)
      done
    fi

    if [ -z "$FOUND_DIR" ]; then
      exit 1
    fi

    # Write cache for future calls (best-effort, silent on failure)
    echo "$FOUND_DIR" > "$CACHE_FILE" 2>/dev/null || true

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
    #   session.sh check <path> <<'EOF'                  # Tag scan + checklist validation (JSON)
    #   {"path/to/CHECKLIST.md": "- [x] Item one\n- [ ] Item two"}
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
      # Pattern: all lifecycle tag families (¶INV_ESCAPE_BY_DEFAULT)
      TAG_PATTERN='#(needs|delegated|next|claimed|active|done)-[a-z]+'
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

              # Double-check: is the tag inside a backtick code span in this line?
              # Strip all backtick code spans, then check if the tag still appears bare
              STRIPPED_LINE=$(echo "$LINE_TEXT" | sed 's/`[^`]*`//g')
              TAGS_IN_LINE=$(echo "$STRIPPED_LINE" | grep -oE '#(needs|delegated|next|claimed|active|done)-[a-z]+' || true)
              for tag in $TAGS_IN_LINE; do
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
      echo "§CMD_RESOLVE_BARE_TAGS: Tag scan passed — no bare inline lifecycle tags."
    else
      echo "§CMD_RESOLVE_BARE_TAGS: Tag scan already passed."
    fi

    # ─── Validation 2: Checklist Processing (¶INV_CHECKLIST_BEFORE_CLOSE) ───
    # Read checklist results from stdin (JSON format)
    # Schema: {"path/to/CHECKLIST.md": "full markdown with [x] filled", ...}
    CHECK_INPUT=""
    if [ ! -t 0 ]; then
      CHECK_INPUT=$(cat)
    fi

    # Get discovered checklists from .state.json
    DISCOVERED_JSON=$(jq -r '(.discoveredChecklists // [])' "$STATE_FILE" 2>/dev/null || echo "[]")
    DISCOVERED_COUNT=$(echo "$DISCOVERED_JSON" | jq 'length')

    # Helper: normalize content for checkbox-blind comparison
    # 1. Normalize CRLF→LF
    # 2. Replace all checkbox variants [x], [X], [ ] with [ ]
    # 3. Trim trailing whitespace per line
    normalize_checklist() {
      printf '%s' "$1" | tr -d '\r' | sed -E 's/- \[(x|X| )\]/- [ ]/g' | sed 's/[[:space:]]*$//'
    }

    if [ "$DISCOVERED_COUNT" -eq 0 ]; then
      # No checklists discovered — checklist check passes trivially
      echo "§CMD_PROCESS_CHECKLISTS: No checklists discovered — passed trivially."
    else
      # Checklists discovered — stdin required
      if [ -z "$CHECK_INPUT" ]; then
        echo "§CMD_PROCESS_CHECKLISTS: Checklists discovered but no results provided on stdin." >&2
        echo "" >&2
        echo "  JSON format required. Schema:" >&2
        echo '  {"path/to/CHECKLIST.md": "full markdown with [x] filled"}' >&2
        exit 1
      fi

      # Validate stdin is valid JSON
      if ! echo "$CHECK_INPUT" | jq empty 2>/dev/null; then
        echo "§CMD_PROCESS_CHECKLISTS: Invalid JSON on stdin." >&2
        echo "" >&2
        echo "  JSON format required. Schema:" >&2
        echo '  {"path/to/CHECKLIST.md": "full markdown with [x] filled"}' >&2
        exit 1
      fi

      # Validate it's a JSON object (not array, string, etc.)
      JSON_TYPE=$(echo "$CHECK_INPUT" | jq -r 'type')
      if [ "$JSON_TYPE" != "object" ]; then
        echo "§CMD_PROCESS_CHECKLISTS: Expected JSON object, got $JSON_TYPE." >&2
        exit 1
      fi

      CHECKLIST_FAILURES=()

      while IFS= read -r discovered_path; do
        [ -n "$discovered_path" ] || continue

        # (a) Check path exists as key in JSON
        HAS_KEY=$(echo "$CHECK_INPUT" | jq --arg k "$discovered_path" 'has($k)')
        if [ "$HAS_KEY" != "true" ]; then
          CHECKLIST_FAILURES+=("$discovered_path: missing from JSON input")
          continue
        fi

        # (b) Extract agent's content from JSON
        AGENT_CONTENT=$(echo "$CHECK_INPUT" | jq -r --arg k "$discovered_path" '.[$k]')

        # (c) Read original CHECKLIST.md from disk
        if [ ! -f "$discovered_path" ]; then
          CHECKLIST_FAILURES+=("$discovered_path: original file not found on disk")
          continue
        fi
        ORIGINAL_CONTENT=$(cat "$discovered_path")

        # (d) Branching validation on agent's content (fast fail on format)
        # Detect nesting: any line with 2-space indented checkbox
        HAS_NESTING=$(echo "$AGENT_CONTENT" | grep -cE '^  - \[(x|X| )\]' 2>/dev/null) || HAS_NESTING=0

        if [ "$HAS_NESTING" -gt 0 ]; then
          CURRENT_PARENT=""
          CURRENT_PARENT_CHECKED=""
          PARENT_COUNT=0
          CHECKED_PARENTS=0
          CHILD_FAILURES=""
          SECTION_HAS_NESTING=false

          # Helper: validate the completed section's branching rules
          # Only validates if the section actually has nested items (branch parents with children)
          _validate_section() {
            # Check last parent's children in this section
            if [ -n "$CURRENT_PARENT" ] && [ "$CURRENT_PARENT_CHECKED" = "true" ] && [ -n "$CHILD_FAILURES" ]; then
              CHECKLIST_FAILURES+=("$discovered_path: unchecked child under checked parent '$CURRENT_PARENT': $CHILD_FAILURES")
            fi
            # Validate: exactly one parent checked per section (only if section has nesting)
            if [ "$SECTION_HAS_NESTING" = "true" ] && [ "$PARENT_COUNT" -gt 0 ]; then
              if [ "$CHECKED_PARENTS" -eq 0 ]; then
                CHECKLIST_FAILURES+=("$discovered_path: no branch parent checked (must check exactly one)")
              elif [ "$CHECKED_PARENTS" -gt 1 ]; then
                CHECKLIST_FAILURES+=("$discovered_path: $CHECKED_PARENTS branch parents checked (must be exactly one)")
              fi
            fi
          }

          while IFS= read -r line; do
            [ -n "$line" ] || continue

            # Section boundary: ## heading resets per-section counters
            if echo "$line" | grep -qE '^## '; then
              # Validate the previous section (if any parents were found)
              if [ "$PARENT_COUNT" -gt 0 ]; then
                _validate_section
              fi
              # Reset for new section
              CURRENT_PARENT=""
              CURRENT_PARENT_CHECKED=""
              PARENT_COUNT=0
              CHECKED_PARENTS=0
              CHILD_FAILURES=""
              SECTION_HAS_NESTING=false
              continue
            fi

            # Parent checkbox (top-level, no indent)
            if echo "$line" | grep -qE '^- \[(x|X| )\]'; then
              # Check previous parent's children
              if [ -n "$CURRENT_PARENT" ] && [ "$CURRENT_PARENT_CHECKED" = "true" ] && [ -n "$CHILD_FAILURES" ]; then
                CHECKLIST_FAILURES+=("$discovered_path: unchecked child under checked parent '$CURRENT_PARENT': $CHILD_FAILURES")
              fi

              PARENT_COUNT=$((PARENT_COUNT + 1))
              CURRENT_PARENT=$(echo "$line" | sed -E 's/^- \[.\] //')
              CHILD_FAILURES=""

              if echo "$line" | grep -qE '^- \[(x|X)\]'; then
                CURRENT_PARENT_CHECKED="true"
                CHECKED_PARENTS=$((CHECKED_PARENTS + 1))
              else
                CURRENT_PARENT_CHECKED="false"
              fi

            # Child checkbox (2-space indented)
            elif echo "$line" | grep -qE '^  - \[(x|X| )\]'; then
              SECTION_HAS_NESTING=true
              if [ "$CURRENT_PARENT_CHECKED" = "true" ]; then
                if echo "$line" | grep -qE '^  - \[ \]'; then
                  CHILD_TEXT=$(echo "$line" | sed -E 's/^  - \[.\] //')
                  CHILD_FAILURES="${CHILD_FAILURES:+$CHILD_FAILURES, }$CHILD_TEXT"
                fi
              fi
            fi
          done <<< "$AGENT_CONTENT"

          # Validate the final section
          _validate_section

          unset -f _validate_section
        fi

        # (e) Strict text diff: normalize both, compare
        NORM_ORIGINAL=$(normalize_checklist "$ORIGINAL_CONTENT")
        NORM_AGENT=$(normalize_checklist "$AGENT_CONTENT")

        if [ "$NORM_ORIGINAL" != "$NORM_AGENT" ]; then
          CHECKLIST_FAILURES+=("$discovered_path: content mismatch — agent's version differs from original after normalizing checkboxes")
        fi

      done < <(echo "$DISCOVERED_JSON" | jq -r '.[]')

      if [ ${#CHECKLIST_FAILURES[@]} -gt 0 ]; then
        echo "§CMD_PROCESS_CHECKLISTS: Checklist validation failed — ${#CHECKLIST_FAILURES[@]} issue(s)." >&2
        echo "" >&2
        echo "  Failures:" >&2
        for cf in "${CHECKLIST_FAILURES[@]}"; do
          echo "    - $cf" >&2
        done
        echo "" >&2
        echo "  JSON format required. Schema:" >&2
        echo '  {"path/to/CHECKLIST.md": "full markdown with [x] filled"}' >&2
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

          # Strip all backtick code spans, then extract remaining bare tags
          stripped_line=$(echo "$line_text" | sed 's/`[^`]*`//g')
          tags_in_line=$(echo "$stripped_line" | grep -oE '#needs-[a-z-]+' || true)
          for tag in $tags_in_line; do
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

    echo "§CMD_VALIDATE_ARTIFACTS: All checks passed."
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

  evaluate-guards)
    # Evaluate guard rules against current session state.
    # Backward-compat wrapper around evaluate_rules() from lib.sh.
    # Writes matched rules to pendingGuards[] in .state.json.
    #
    # Usage:
    #   session.sh evaluate-guards <path>
    #
    # NOTE: The unified hook (overflow-v2.sh) now evaluates rules inline.
    # This subcommand is kept for backward compatibility and testing.

    GUARDS_FILE="$HOME/.claude/engine/guards.json"

    if [ ! -f "$STATE_FILE" ]; then
      exit 0  # No session — nothing to evaluate
    fi

    if [ ! -f "$GUARDS_FILE" ]; then
      exit 0  # No rules file — nothing to evaluate
    fi

    # Delegate to evaluate_rules() from lib.sh
    NEW_PENDING=$(evaluate_rules "$STATE_FILE" "$GUARDS_FILE")

    # Write pendingGuards to .state.json
    jq --argjson pending "$NEW_PENDING" --arg ts "$(timestamp)" \
      '.pendingGuards = $pending | .lastHeartbeat = $ts' \
      "$STATE_FILE" | safe_json_write "$STATE_FILE"

    PENDING_COUNT=$(echo "$NEW_PENDING" | jq 'length')
    if [ "$PENDING_COUNT" -gt 0 ]; then
      echo "evaluate-guards: $PENDING_COUNT rule(s) matched"
      echo "$NEW_PENDING" | jq -r '.[] | "  \(.ruleId) (priority \(.priority), \(.mode)+\(.urgency))"'
    fi
    ;;

  *)
    echo "§CMD_MAINTAIN_SESSION_DIR: Unknown action '$ACTION'. Use: init, activate, update, find, phase, target, deactivate, restart, clear, check, prove, request-template, debrief, evaluate-guards" >&2
    exit 1
    ;;
esac
