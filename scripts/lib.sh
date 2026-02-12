#!/bin/bash
# ~/.claude/scripts/lib.sh — Shared utilities for session infrastructure
#
# Related:
#   Docs: (~/.claude/docs/)
#     CONTEXT_GUARDIAN.md — lib.sh API section, consumer list
#     ENGINE_TESTING.md — Testing patterns for lib functions
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     (none directly — utility layer)
#
# Source this file at the top of scripts that need these functions:
#   source "$HOME/.claude/scripts/lib.sh"
#
# Functions:
#   safe_json_write FILE    — Reads JSON from stdin, validates, writes atomically with locking
#   hook_allow              — Outputs PreToolUse allow JSON and exits 0
#   hook_deny REASON GUIDANCE DEBUG_INFO — Outputs PreToolUse deny JSON and exits 0
#   timestamp               — Outputs UTC ISO timestamp
#   pid_exists PID          — Returns 0 if PID is running, 1 otherwise
#   notify_fleet STATE      — Send fleet notification if in fleet tmux (no-ops safely outside fleet)
#   state_read FILE FIELD [DEFAULT] — Read a field from .state.json with fallback
#   is_engine_cmd CMD SUBCMD — Returns 0 if CMD is "engine SUBCMD ..." (anchored regex)
#   is_engine_log_cmd CMD   — Returns 0 if CMD is an engine log invocation
#   is_engine_session_cmd CMD — Returns 0 if CMD is an engine session invocation
#   is_engine_tag_cmd CMD   — Returns 0 if CMD is an engine tag invocation
#   is_engine_glob_cmd CMD  — Returns 0 if CMD is an engine glob invocation

# Guard against double-sourcing
[ -n "${_LIB_SH_LOADED:-}" ] && return 0
_LIB_SH_LOADED=1

# notify_fleet STATE — Send fleet notification if in fleet tmux
# Safely no-ops outside fleet. STATE: working|done|error|unchecked
notify_fleet() {
  [ -n "${TMUX:-}" ] || return 0
  local socket
  socket=$(echo "$TMUX" | cut -d, -f1 | xargs basename 2>/dev/null || echo "")
  [[ "$socket" == "fleet" || "$socket" == fleet-* ]] || return 0
  "$HOME/.claude/scripts/fleet.sh" notify "$1" 2>/dev/null || true
}

# state_read FILE FIELD [DEFAULT] — Read a field from .state.json with fallback
state_read() {
  local file="${1:?state_read requires FILE}" field="${2:?state_read requires FIELD}" default="${3:-}"
  jq -r ".$field // \"$default\"" "$file" 2>/dev/null || echo "$default"
}

# timestamp — Outputs UTC ISO timestamp: 2026-02-08T16:00:00Z
timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# pid_exists PID — Returns 0 if PID is running, 1 otherwise
pid_exists() {
  kill -0 "$1" 2>/dev/null
}

# hook_allow — Outputs PreToolUse allow JSON and exits 0
hook_allow() {
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  exit 0
}

# hook_deny REASON GUIDANCE DEBUG_INFO
#   Outputs PreToolUse deny JSON with reason and guidance.
#   DEBUG_INFO is only included when DEBUG=1.
#   All 3 args required (pass "" for empty).
hook_deny() {
  local reason="${1:?hook_deny requires REASON as arg 1}"
  local guidance="${2:?hook_deny requires GUIDANCE as arg 2}"
  local debug_info="${3?hook_deny requires DEBUG_INFO as arg 3}"

  local full_reason="$reason"
  if [ -n "$guidance" ]; then
    full_reason="${full_reason}\n${guidance}"
  fi
  if [ "${DEBUG:-}" = "1" ] && [ -n "$debug_info" ]; then
    full_reason="${full_reason}\n[DEBUG] ${debug_info}"
  fi

  jq -n --arg reason "$full_reason" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$reason}}'
  exit 0
}

# is_engine_cmd CMD SUBCMD — Returns 0 if CMD starts with "engine SUBCMD"
# Uses anchored regex: ^engine\s+SUBCMD(\s|$)
# The anchor prevents false positives from heredoc bodies.
is_engine_cmd() {
  local cmd="$1" subcmd="$2"
  [[ "$cmd" =~ ^engine[[:space:]]+"$subcmd"([[:space:]]|$) ]]
}

# Convenience wrappers for specific engine subcommands
is_engine_log_cmd()     { is_engine_cmd "$1" "log"; }
is_engine_session_cmd() { is_engine_cmd "$1" "session"; }
is_engine_tag_cmd()     { is_engine_cmd "$1" "tag"; }
is_engine_glob_cmd()    { is_engine_cmd "$1" "glob"; }

# --- Directory exclusion utilities ---
# Standard directories to exclude from discovery/scanning
STANDARD_EXCLUDED_DIRS="node_modules .git sessions tmp dist build"

# is_excluded_dir DIR_PATH [EXCLUDED_LIST]
#   Returns 0 if the basename of DIR_PATH matches any excluded name.
#   Defaults to $STANDARD_EXCLUDED_DIRS if no second arg.
is_excluded_dir() {
  local dir_path="$1"
  local excluded="${2:-$STANDARD_EXCLUDED_DIRS}"
  local dir_name
  dir_name=$(basename "$dir_path")
  for excl in $excluded; do
    if [ "$dir_name" = "$excl" ]; then
      return 0
    fi
  done
  return 1
}

# is_path_excluded DIR_PATH [EXCLUDED_LIST]
#   Returns 0 if any path component matches an excluded name.
#   Uses parameter expansion (Bash 3.2 safe). Defaults to $STANDARD_EXCLUDED_DIRS.
is_path_excluded() {
  local dir_path="$1"
  local excluded="${2:-$STANDARD_EXCLUDED_DIRS}"
  local remaining="$dir_path"
  while [ -n "$remaining" ]; do
    local component="${remaining%%/*}"
    if [ "$component" = "$remaining" ]; then
      remaining=""
    else
      remaining="${remaining#*/}"
    fi
    [ -z "$component" ] && continue
    for excl in $excluded; do
      if [ "$component" = "$excl" ]; then
        return 0
      fi
    done
  done
  return 1
}

# safe_json_write FILE
#   Reads JSON from stdin, validates with `jq empty`, writes atomically.
#   Uses mkdir-based spinlock for concurrency safety.
#   Stale locks (>10s) are force-removed.
#   Exit 1 on invalid JSON or write failure.
safe_json_write() {
  local file="${1:?safe_json_write requires FILE as arg 1}"
  local lock_dir="${file}.lock"
  local tmp_file="${file}.tmp.$$"
  local json

  # Read JSON from stdin
  json=$(cat)

  # Validate JSON
  if ! echo "$json" | jq empty 2>/dev/null; then
    echo "ERROR: safe_json_write: invalid JSON for $file" >&2
    return 1
  fi

  # Acquire lock (mkdir is atomic)
  local retries=0
  local max_retries=100
  while ! mkdir "$lock_dir" 2>/dev/null; do
    retries=$((retries + 1))
    if [ "$retries" -ge "$max_retries" ]; then
      echo "ERROR: safe_json_write: lock timeout for $file" >&2
      return 1
    fi
    # Stale lock detection: if lock dir is older than 10 seconds, force-remove
    # Uses stat instead of find -mmin (macOS find doesn't support fractional -mmin)
    if [ -d "$lock_dir" ]; then
      local lock_mtime now_epoch lock_age
      lock_mtime=$(stat -f "%m" "$lock_dir" 2>/dev/null || echo "0")
      now_epoch=$(date +%s)
      lock_age=$((now_epoch - lock_mtime))
      if [ "$lock_age" -gt 10 ]; then
        rmdir "$lock_dir" 2>/dev/null || true
        continue
      fi
    fi
    sleep 0.01
  done

  # Write atomically: temp file + mv
  if echo "$json" > "$tmp_file" && mv "$tmp_file" "$file"; then
    rmdir "$lock_dir" 2>/dev/null || true
    return 0
  else
    rm -f "$tmp_file"
    rmdir "$lock_dir" 2>/dev/null || true
    echo "ERROR: safe_json_write: write failed for $file" >&2
    return 1
  fi
}

# --- Rule evaluation engine ---
# Core evaluation function for the unified injection rule engine.
# Extracted from session.sh evaluate-injections for shared use between
# the hook (inline) and session.sh (backward compat wrapper).

# _resolve_payload_refs PAYLOAD_JSON STATE_FILE
#   Resolve "$fieldName" references in payload values from .state.json.
#   Walks all payload keys. If a value is a string starting with "$",
#   looks up the field name (without $) in state and replaces the value.
#   Returns the resolved payload JSON.
_resolve_payload_refs() {
  local payload="$1" state_file="$2"

  if [ -z "$state_file" ] || [ ! -f "$state_file" ]; then
    echo "$payload"
    return 0
  fi

  # Get all keys whose values are strings starting with "$"
  local ref_keys
  ref_keys=$(echo "$payload" | jq -r 'to_entries[] | select(.value | type == "string" and startswith("$")) | .key' 2>/dev/null || echo "")

  if [ -z "$ref_keys" ]; then
    echo "$payload"
    return 0
  fi

  local resolved="$payload"
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    # Extract the field name (strip leading $)
    local ref_val field_name
    ref_val=$(echo "$payload" | jq -r --arg k "$key" '.[$k]')
    field_name="${ref_val#\$}"

    # Look up the field in state (expected to be an array)
    local state_val
    state_val=$(jq --arg f "$field_name" '.[$f] // null' "$state_file" 2>/dev/null || echo "null")

    if [ "$state_val" != "null" ]; then
      resolved=$(echo "$resolved" | jq --arg k "$key" --argjson v "$state_val" '.[$k] = $v')
    fi
  done <<< "$ref_keys"

  echo "$resolved"
}

# evaluate_rules STATE_FILE INJECTIONS_FILE [TRANSCRIPT_KEY]
#   Evaluate all injection rules against current session state.
#   Outputs matched rules as a JSON array (sorted by priority) to stdout.
#   TRANSCRIPT_KEY is optional — used for perTranscriptToolCount trigger.
#
#   Reads: .state.json fields (contextUsage, lifecycle, currentPhase, etc.)
#   Reads: injections.json rules
#   Reads: config.sh for OVERFLOW_THRESHOLD
#
#   Returns 0 always (errors produce empty array).
evaluate_rules() {
  local state_file="${1:?evaluate_rules requires STATE_FILE}"
  local injections_file="${2:?evaluate_rules requires INJECTIONS_FILE}"
  local transcript_key="${3:-}"

  if [ ! -f "$state_file" ] || [ ! -f "$injections_file" ]; then
    echo "[]"
    return 0
  fi

  # Source config for OVERFLOW_THRESHOLD (may already be sourced but safe to re-source)
  source "$HOME/.claude/engine/config.sh" 2>/dev/null || true
  local overflow_threshold="${OVERFLOW_THRESHOLD:-0.76}"

  # Read current state
  local context_usage current_phase lifecycle
  context_usage=$(state_read "$state_file" "contextUsage" "0")
  current_phase=$(state_read "$state_file" "currentPhase" "")
  lifecycle=$(state_read "$state_file" "lifecycle" "")

  # Read existing injectedRules
  local injected_rules
  injected_rules=$(jq -r '.injectedRules // {}' "$state_file" 2>/dev/null || echo '{}')

  # Build new matched rules array
  local new_pending="[]"

  # Process each rule
  local rule_count
  rule_count=$(jq 'length' "$injections_file" 2>/dev/null || echo "0")
  local i
  for (( i=0; i<rule_count; i++ )); do
    local rule rule_id inject_freq trigger_type
    rule=$(jq ".[$i]" "$injections_file")
    rule_id=$(echo "$rule" | jq -r '.id')
    inject_freq=$(echo "$rule" | jq -r '.inject')
    trigger_type=$(echo "$rule" | jq -r '.trigger.type')

    # Skip inject:once rules already delivered
    if [ "$inject_freq" = "once" ]; then
      local already_injected
      already_injected=$(echo "$injected_rules" | jq -r --arg id "$rule_id" '.[$id] // "false"')
      if [ "$already_injected" = "true" ]; then
        continue
      fi
    fi

    local matched=false

    case "$trigger_type" in
      contextThreshold)
        local threshold
        threshold=$(echo "$rule" | jq -r '.trigger.condition.gte')
        # Resolve OVERFLOW_THRESHOLD reference
        if [ "$threshold" = "OVERFLOW_THRESHOLD" ]; then
          threshold="$overflow_threshold"
        fi
        if [ "$(echo "$context_usage >= $threshold" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
          matched=true
        fi
        ;;

      lifecycle)
        local no_active
        no_active=$(echo "$rule" | jq -r '.trigger.condition.noActiveSession // false')
        if [ "$no_active" = "true" ]; then
          if [ "$lifecycle" != "active" ]; then
            matched=true
          fi
        fi
        ;;

      phase)
        local phase_pattern
        phase_pattern=$(echo "$rule" | jq -r '.trigger.condition.matches')
        if [[ "$current_phase" == *"$phase_pattern"* ]]; then
          matched=true
        fi
        ;;

      toolCount)
        local field gte_field field_val threshold_val
        field=$(echo "$rule" | jq -r '.trigger.condition.field')
        gte_field=$(echo "$rule" | jq -r '.trigger.condition.gte')
        field_val=$(state_read "$state_file" "$field" "0")
        threshold_val=$(state_read "$state_file" "$gte_field" "999")
        if [ "$field_val" -ge "$threshold_val" ] 2>/dev/null; then
          matched=true
        fi
        ;;

      discovery)
        local disc_field non_empty
        disc_field=$(echo "$rule" | jq -r '.trigger.condition.field')
        non_empty=$(echo "$rule" | jq -r '.trigger.condition.nonEmpty // false')
        if [ "$non_empty" = "true" ]; then
          local field_len
          field_len=$(jq --arg f "$disc_field" '.[$f] // [] | length' "$state_file" 2>/dev/null || echo 0)
          if [ "$field_len" -gt 0 ]; then
            matched=true
          fi
        fi
        ;;

      perTranscriptToolCount)
        # Per-transcript counter trigger: reads toolCallsByTranscript[key]
        # Supports gte (>=) and eq (==) conditions
        if [ -n "$transcript_key" ]; then
          local counter_val
          counter_val=$(jq -r --arg key "$transcript_key" '(.toolCallsByTranscript // {})[$key] // 0' "$state_file" 2>/dev/null || echo "0")

          local gte_val eq_val
          gte_val=$(echo "$rule" | jq -r '.trigger.condition.gte // ""')
          eq_val=$(echo "$rule" | jq -r '.trigger.condition.eq // ""')

          if [ -n "$gte_val" ] && [ "$counter_val" -ge "$gte_val" ] 2>/dev/null; then
            matched=true
          elif [ -n "$eq_val" ] && [ "$counter_val" -eq "$eq_val" ] 2>/dev/null; then
            matched=true
          fi
        fi
        ;;

      *)
        # Unknown trigger type — skip
        continue
        ;;
    esac

    if [ "$matched" = "true" ]; then
      local mode urgency priority payload whitelist_arr
      mode=$(echo "$rule" | jq -r '.mode')
      urgency=$(echo "$rule" | jq -r '.urgency')
      priority=$(echo "$rule" | jq -r '.priority')
      payload=$(echo "$rule" | jq '.payload')

      # Dynamic payload resolution: resolve "$fieldName" references from .state.json
      # Example: payload.preload = "$pendingDirectives" → resolves to actual array from state
      payload=$(_resolve_payload_refs "$payload" "$state_file")

      whitelist_arr=$(echo "$rule" | jq '.whitelist // []')

      local entry
      entry=$(jq -n \
        --arg ruleId "$rule_id" \
        --arg mode "$mode" \
        --arg urgency "$urgency" \
        --argjson priority "$priority" \
        --argjson payload "$payload" \
        --argjson whitelist "$whitelist_arr" \
        --arg evaluatedAt "$(timestamp)" \
        '{ruleId: $ruleId, mode: $mode, urgency: $urgency, priority: $priority, payload: $payload, whitelist: $whitelist, evaluatedAt: $evaluatedAt}')

      new_pending=$(echo "$new_pending" | jq --argjson entry "$entry" '. + [$entry]')
    fi
  done

  # Sort by priority (lower number = higher priority)
  echo "$new_pending" | jq 'sort_by(.priority)'
}

# --- tmux injection utilities ---
# Used by injection framework hooks for paste mode delivery.
# All functions degrade gracefully outside tmux (¶INV_TMUX_AND_FLEET_OPTIONAL).

# tmux_paste TEXT
#   Send text to the CALLER'S tmux pane via send-keys (literal mode).
#   Uses $TMUX_PANE to target the correct pane, preventing cross-pane contamination
#   in multi-agent fleet setups. Falls back to active pane if $TMUX_PANE is unset.
#   Returns 1 if not inside tmux.
tmux_paste() {
  local text="${1:?tmux_paste requires TEXT as arg 1}"
  if [ -z "${TMUX:-}" ]; then
    return 1
  fi
  local target_flag=""
  if [ -n "${TMUX_PANE:-}" ]; then
    target_flag="-t $TMUX_PANE"
  fi
  # Use literal mode (-l) to avoid key interpretation, then send Enter
  tmux send-keys $target_flag -l "$text" 2>/dev/null && tmux send-keys $target_flag Enter 2>/dev/null
}

# tmux_interrupt_and_paste TEXT
#   Send Escape to cancel current generation, wait for settle, then paste.
#   The 0.5s delay gives Claude Code time to process the interrupt.
#   Uses $TMUX_PANE for pane targeting (same as tmux_paste).
#   Returns 1 if not inside tmux.
tmux_interrupt_and_paste() {
  local text="${1:?tmux_interrupt_and_paste requires TEXT as arg 1}"
  if [ -z "${TMUX:-}" ]; then
    return 1
  fi
  local target_flag=""
  if [ -n "${TMUX_PANE:-}" ]; then
    target_flag="-t $TMUX_PANE"
  fi
  # ESC cancels Claude Code's current generation
  tmux send-keys $target_flag Escape 2>/dev/null
  sleep 0.5
  # Second ESC for reliability (belt and suspenders)
  tmux send-keys $target_flag Escape 2>/dev/null
  sleep 0.3
  # Now paste the text
  tmux_paste "$text"
}

# --- Whitelist matching utilities ---
# Used by the unified rule engine hook for tool whitelisting.

# PRIMARY_INPUT_FIELD — maps tool name to its primary input field for whitelist matching
# Hardcoded per plan: Bash→command, Read→file_path, Edit→file_path, Write→file_path,
# Skill→skill, Glob→pattern, Grep→pattern. All others → tool name only (no input match).
_primary_input_field() {
  case "$1" in
    Bash)  echo "command" ;;
    Read)  echo "file_path" ;;
    Edit)  echo "file_path" ;;
    Write) echo "file_path" ;;
    Skill) echo "skill" ;;
    Glob)  echo "pattern" ;;
    Grep)  echo "pattern" ;;
    *)     echo "" ;;
  esac
}

# match_whitelist_entry PATTERN TOOL_NAME TOOL_INPUT_VALUE
#   Matches a single whitelist pattern against a tool call.
#   Pattern format: "ToolName" or "ToolName(glob)"
#   Returns 0 (match) or 1 (no match).
#
#   Examples:
#     match_whitelist_entry "AskUserQuestion" "AskUserQuestion" ""        → 0
#     match_whitelist_entry "Read(~/.claude/*)" "Read" "~/.claude/foo.md" → 0
#     match_whitelist_entry "Bash(engine session *)" "Bash" "engine session activate" → 0
#     match_whitelist_entry "Read(~/.claude/*)" "Edit" "/some/file"       → 1
match_whitelist_entry() {
  local pattern="$1" tool_name="$2" tool_input="${3:-}"

  # Check if pattern has a glob: "ToolName(glob)"
  if [[ "$pattern" == *"("*")"* ]]; then
    # Extract tool part and glob part
    local pat_tool="${pattern%%(*}"
    local pat_glob="${pattern#*(}"
    pat_glob="${pat_glob%)}"

    # Tool name must match
    if [ "$pat_tool" != "$tool_name" ]; then
      return 1
    fi

    # Glob must match the tool input value
    # shellcheck disable=SC2053
    if [[ "$tool_input" == $pat_glob ]]; then
      return 0
    fi
    return 1
  else
    # Bare tool name match — "ToolName" matches any call to that tool
    if [ "$pattern" = "$tool_name" ]; then
      return 0
    fi
    return 1
  fi
}

# match_whitelist WHITELIST_JSON TOOL_NAME TOOL_INPUT_JSON
#   Check a tool against a JSON array of whitelist patterns.
#   Resolves the primary input field from TOOL_INPUT_JSON automatically.
#   Returns 0 if any pattern matches, 1 if none match.
#   Empty or null whitelist → returns 1 (no match = block all).
#
#   Usage:
#     match_whitelist '["AskUserQuestion","Bash(engine session *)"]' "Bash" '{"command":"engine session activate"}'
match_whitelist() {
  local whitelist_json="$1" tool_name="$2" tool_input_json="${3:-{\}}"

  # Empty or null whitelist means no whitelist → block all
  local wl_len
  wl_len=$(echo "$whitelist_json" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo "0")
  if [ "$wl_len" -eq 0 ]; then
    return 1
  fi

  # Resolve primary input value for this tool
  local input_field tool_input_value=""
  input_field=$(_primary_input_field "$tool_name")
  if [ -n "$input_field" ]; then
    tool_input_value=$(echo "$tool_input_json" | jq -r --arg f "$input_field" '.[$f] // ""' 2>/dev/null || echo "")
  fi

  # Check each pattern
  local i pattern
  for (( i=0; i<wl_len; i++ )); do
    pattern=$(echo "$whitelist_json" | jq -r ".[$i]" 2>/dev/null || echo "")
    if match_whitelist_entry "$pattern" "$tool_name" "$tool_input_value"; then
      return 0
    fi
  done

  return 1
}

# clear_agent_context SESSION_DIR
#   Force a context reset. In tmux: interrupt + paste "/session dehydrate restart".
#   Without tmux: signal session.sh restart for the wrapper to handle.
#   This is the generalized "clear context" primitive — intent over mechanism.
clear_agent_context() {
  local session_dir="${1:?clear_agent_context requires SESSION_DIR as arg 1}"
  if [ -n "${TMUX:-}" ]; then
    # tmux path: interrupt + paste dehydrate command
    tmux_interrupt_and_paste "/session dehydrate restart --session $session_dir"
  else
    # No tmux: signal restart via session.sh (wrapper picks it up)
    "$HOME/.claude/scripts/session.sh" restart "$session_dir" 2>/dev/null || true
  fi
}
