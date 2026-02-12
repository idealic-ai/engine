#!/bin/bash
# ~/.claude/engine/hooks/pre-tool-use-overflow-v2.sh — Unified PreToolUse rule engine
#
# Single hook that replaces session-gate, heartbeat, and overflow hooks.
# Flow:
#   1. Parse tool info from stdin
#   2. Hardcoded critical bypass (engine log → counter reset + allow, engine session → allow)
#   3. Find session dir, read .state.json
#   4. Lifecycle bypass (dehydrating, loading, completed/restarting for heartbeat-only)
#   5. Per-transcript counter increment (with same-file edit suppression, Task bypass)
#   6. Evaluate ALL rules via evaluate_rules() — reads injections.json + .state.json
#   7. Separate matched rules into blocking vs allow
#   8. Compute union whitelist from ALL blocking rules
#   9. Tool matches union whitelist? → allow (skip all blocking injections)
#  10. Deliver blocking injections (deny + message)
#  11. Deliver allow injections (inject guidance as permissionDecisionReason)
#  12. Fallback: allow
#
# Mode × Urgency matrix:
#   inline+allow  → permissionDecisionReason text, allow tool
#   inline+block  → hook_deny with content in message
#   read+allow    → "REQUIRED: Read [file]" in reason, allow tool
#   read+block    → hook_deny with read instruction
#   paste+allow   → tmux paste, allow tool (falls back to read+block without tmux)
#   paste+block   → tmux paste + deny tool (falls back to block without tmux)
#   paste+interrupt → ESC + paste (falls back to block without tmux)
#   preload+allow → reads files, injects as [Preloaded: path] content, allow tool
#   preload+block → reads files, injects as [Preloaded: path] content in deny message
#
# Related:
#   Engine: injections.json (rule store), lib.sh (evaluate_rules, match_whitelist)
#   Invariants: ¶INV_TMUX_AND_FLEET_OPTIONAL

set -euo pipefail

# Source shared utilities (hook_allow, hook_deny, state_read, safe_json_write,
# tmux_*, evaluate_rules, match_whitelist)
source "$HOME/.claude/scripts/lib.sh"

# Source config (OVERFLOW_THRESHOLD)
source "$HOME/.claude/engine/config.sh" 2>/dev/null || true
OVERFLOW_THRESHOLD="${OVERFLOW_THRESHOLD:-0.76}"

INJECTIONS_FILE="$HOME/.claude/engine/injections.json"

# Read hook input from stdin
INPUT=$(cat)

# Parse tool info
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
SKILL_ARG=$(echo "$INPUT" | jq -r '.tool_input.skill // ""' 2>/dev/null || echo "")
SKILL_ARGS=$(echo "$INPUT" | jq -r '.tool_input.args // ""' 2>/dev/null || echo "")
BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
TRANSCRIPT_KEY=$(basename "$TRANSCRIPT_PATH" 2>/dev/null || echo "unknown")
TOOL_INPUT=$(echo "$INPUT" | jq '.tool_input // {}' 2>/dev/null || echo '{}')

# --- Step 2: Hardcoded critical bypass ---
# engine log and engine session MUST always pass through.
# engine log also resets the per-transcript counter.
if [ "$TOOL_NAME" = "Bash" ]; then
  if is_engine_log_cmd "$BASH_CMD"; then
    # Reset counter on log command (same as heartbeat-v2)
    session_dir=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
    if [ -n "$session_dir" ] && [ -f "$session_dir/.state.json" ]; then
      jq --arg key "$TRANSCRIPT_KEY" \
        '(.toolCallsByTranscript //= {}) | .toolCallsByTranscript[$key] = 0 | .toolCallsSinceLastLog = 0' \
        "$session_dir/.state.json" | safe_json_write "$session_dir/.state.json"
    fi
    hook_allow
  fi
  if is_engine_session_cmd "$BASH_CMD"; then
    hook_allow
  fi
fi

# --- Step 3: Find session directory ---
find_session_dir() {
  "$HOME/.claude/scripts/session.sh" find 2>/dev/null
}

# _clear_preloaded_directives STATE_FILE PRELOADED_PATHS
#   Remove successfully preloaded files from pendingDirectives and track them
#   in preloadedFiles to prevent double-loading on re-discovery.
#   PRELOADED_PATHS is newline-separated list of original (unresolved) paths.
_clear_preloaded_directives() {
  local state_file="$1" preloaded_paths="$2"

  # Batch: collect all paths to remove and track
  local remove_paths="[]"
  while IFS= read -r ppath; do
    [ -z "$ppath" ] && continue
    local resolved="${ppath/#\~/$HOME}"
    remove_paths=$(echo "$remove_paths" | jq --arg p "$ppath" --arg r "$resolved" '. + [$p, $r]')
  done <<< "$preloaded_paths"

  # Single atomic write: remove from pendingDirectives + add to preloadedFiles
  jq --argjson paths "$remove_paths" \
    '(.pendingDirectives //= []) | .pendingDirectives -= $paths |
     (.preloadedFiles //= []) | .preloadedFiles = (.preloadedFiles + $paths | unique)' \
    "$state_file" | safe_json_write "$state_file"
}

main() {
  notify_fleet working

  local session_dir
  if ! session_dir=$(find_session_dir); then
    # No session found — evaluate rules without session context
    # (session-gate rule will fire via lifecycle trigger)
    if [ -f "$INJECTIONS_FILE" ]; then
      # Create a minimal temp state for evaluation (no session = lifecycle not active)
      local tmp_state
      tmp_state=$(mktemp)
      echo '{"lifecycle":"none","contextUsage":0}' > "$tmp_state"
      local matched_rules
      matched_rules=$(evaluate_rules "$tmp_state" "$INJECTIONS_FILE" "$TRANSCRIPT_KEY")
      rm -f "$tmp_state"

      # Process blocking rules with union whitelist
      _process_rules "$matched_rules" "" ""
    fi
    hook_allow
  fi

  local state_file="$session_dir/.state.json"
  if [ ! -f "$state_file" ]; then
    hook_allow
  fi

  # --- Step 4: Lifecycle bypass ---
  local lifecycle killRequested loading overflowed
  lifecycle=$(state_read "$state_file" lifecycle "active")
  killRequested=$(state_read "$state_file" killRequested "false")
  loading=$(state_read "$state_file" loading "false")
  overflowed=$(state_read "$state_file" overflowed "false")

  # Allow /session dehydrate or /session continue (overflow recovery path)
  if [ "$TOOL_NAME" = "Skill" ] && [ "$SKILL_ARG" = "session" ]; then
    if [[ "$SKILL_ARGS" == *dehydrate* ]] || [[ "$SKILL_ARGS" == *continue* ]]; then
      jq '.lifecycle = "dehydrating"' "$state_file" | safe_json_write "$state_file"
      hook_allow
    fi
  fi

  # Allow all tools during dehydration/restart flow
  if [ "$lifecycle" = "dehydrating" ] || [ "$killRequested" = "true" ]; then
    hook_allow
  fi

  # Loading/completed/restarting/overflowed bypass for heartbeat counters
  # (don't increment or enforce heartbeat during these states)
  local skip_heartbeat=false
  if [ "$loading" = "true" ] || [ "$lifecycle" = "completed" ] || [ "$lifecycle" = "restarting" ] || [ "$overflowed" = "true" ]; then
    skip_heartbeat=true
  fi

  # --- Step 5: Per-transcript counter increment ---
  if [ "$skip_heartbeat" = "false" ]; then
    # Task tool bypasses counter
    if [ "$TOOL_NAME" != "Task" ]; then
      local counter
      counter=$(jq -r --arg key "$TRANSCRIPT_KEY" '(.toolCallsByTranscript // {})[$key] // 0' "$state_file" 2>/dev/null || echo "0")

      # Same-file edit suppression
      local suppress_increment=false
      if [ "$TOOL_NAME" = "Edit" ]; then
        local edit_file
        edit_file=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
        local last_edit_key="lastEditFile_${TRANSCRIPT_KEY}"
        local last_edit_file
        last_edit_file=$(jq -r --arg key "$last_edit_key" '.[$key] // ""' "$state_file" 2>/dev/null || echo "")
        jq --arg key "$last_edit_key" --arg val "$edit_file" \
          '.[$key] = $val' "$state_file" | safe_json_write "$state_file"
        if [ "$edit_file" = "$last_edit_file" ] && [ -n "$edit_file" ]; then
          suppress_increment=true
        fi
      else
        local last_edit_key="lastEditFile_${TRANSCRIPT_KEY}"
        jq --arg key "$last_edit_key" 'del(.[$key])' \
          "$state_file" | safe_json_write "$state_file"
      fi

      if [ "$suppress_increment" = "false" ]; then
        local new_counter=$((counter + 1))
        jq --arg key "$TRANSCRIPT_KEY" --argjson tc "$new_counter" \
          '(.toolCallsByTranscript //= {}) | .toolCallsByTranscript[$key] = $tc | .toolCallsSinceLastLog = $tc' \
          "$state_file" | safe_json_write "$state_file"
      fi
    fi
  fi

  # --- Step 6: Evaluate ALL rules ---
  local matched_rules="[]"
  if [ -f "$INJECTIONS_FILE" ]; then
    matched_rules=$(evaluate_rules "$state_file" "$INJECTIONS_FILE" "$TRANSCRIPT_KEY")
  fi

  # --- Steps 7-11: Process matched rules ---
  _process_rules "$matched_rules" "$state_file" "$session_dir"

  # --- Step 12: Fallback allow ---
  hook_allow
}

# _process_rules MATCHED_RULES_JSON STATE_FILE SESSION_DIR
#   Separates blocking vs allow rules, computes union whitelist,
#   checks tool against union, delivers injections.
_process_rules() {
  local matched_rules="$1" state_file="$2" session_dir="$3"

  local rule_count
  rule_count=$(echo "$matched_rules" | jq 'length' 2>/dev/null || echo "0")

  if [ "$rule_count" -eq 0 ]; then
    return 0
  fi

  # --- Step 7: Separate blocking vs allow ---
  local blocking_rules allow_rules
  blocking_rules=$(echo "$matched_rules" | jq '[.[] | select(.urgency == "block" or .urgency == "interrupt")]')
  allow_rules=$(echo "$matched_rules" | jq '[.[] | select(.urgency == "allow")]')

  local blocking_count
  blocking_count=$(echo "$blocking_rules" | jq 'length')

  if [ "$blocking_count" -gt 0 ]; then
    # --- Step 8: Compute union whitelist from ALL blocking rules ---
    local union_whitelist
    union_whitelist=$(echo "$blocking_rules" | jq '[.[].whitelist // [] | .[]] | unique')

    local union_len
    union_len=$(echo "$union_whitelist" | jq 'length')

    # --- Step 9: Tool matches union whitelist? → allow ---
    if [ "$union_len" -gt 0 ]; then
      if match_whitelist "$union_whitelist" "$TOOL_NAME" "$TOOL_INPUT"; then
        # Tool is whitelisted — skip blocking, but still deliver allow injections
        _deliver_allow_rules "$allow_rules" "$state_file"
        return 0
      fi
    fi

    # --- Step 10: Deliver blocking injections ---
    local block_reason=""
    local i

    for (( i=0; i<blocking_count; i++ )); do
      local injection
      injection=$(echo "$blocking_rules" | jq ".[$i]")
      local rule_id mode urgency
      rule_id=$(echo "$injection" | jq -r '.ruleId')
      mode=$(echo "$injection" | jq -r '.mode')
      urgency=$(echo "$injection" | jq -r '.urgency')

      case "$mode" in
        inline)
          local text
          text=$(echo "$injection" | jq -r '.payload.text // ""')
          if [ -z "$text" ]; then
            text=$(echo "$injection" | jq -r '.payload.files // [] | map("INJECTION [\(.)]") | join("\n")')
          fi
          block_reason="${block_reason}${block_reason:+\n}[Injection: $rule_id] $text"
          ;;
        read)
          local files
          files=$(echo "$injection" | jq -r '.payload.files // [] | join(", ")')
          block_reason="${block_reason}${block_reason:+\n}[Injection: $rule_id] REQUIRED: Read these files: $files"
          ;;
        paste)
          local command
          command=$(echo "$injection" | jq -r '.payload.command // ""')
          if [ "$urgency" = "interrupt" ]; then
            tmux_interrupt_and_paste "$command" 2>/dev/null || true
          else
            tmux_paste "$command" 2>/dev/null || true
          fi
          block_reason="${block_reason}${block_reason:+\n}[Injection: $rule_id] $command"
          ;;
        preload)
          local preload_content=""
          local preloaded_paths=""
          local preload_files
          preload_files=$(echo "$injection" | jq -r '.payload.preload // [] | .[]')
          # Read already-preloaded set for dedup
          local already_preloaded="[]"
          if [ -n "$state_file" ] && [ -f "$state_file" ]; then
            already_preloaded=$(jq '.preloadedFiles // []' "$state_file" 2>/dev/null || echo '[]')
          fi
          while IFS= read -r pfile; do
            [ -z "$pfile" ] && continue
            local resolved="${pfile/#\~/$HOME}"
            # Skip if already preloaded (check both original and resolved forms)
            if echo "$already_preloaded" | jq -e --arg p "$pfile" --arg r "$resolved" \
              'any(. == $p or . == $r)' >/dev/null 2>&1; then
              continue
            fi
            if [ -f "$resolved" ]; then
              local content
              content=$(cat "$resolved")
              preload_content="${preload_content}${preload_content:+\n\n}[Preloaded: $resolved]\n$content"
              preloaded_paths="${preloaded_paths}${preloaded_paths:+
}$pfile"
            else
              echo "Warning: preload file not found, skipping: $resolved" >&2
            fi
          done <<< "$preload_files"
          if [ -n "$preload_content" ]; then
            block_reason="${block_reason}${block_reason:+\n}$preload_content"
          fi
          # Auto-clear preloaded files from pendingDirectives + track in preloadedFiles
          if [ -n "$preloaded_paths" ] && [ -n "$state_file" ] && [ -f "$state_file" ]; then
            _clear_preloaded_directives "$state_file" "$preloaded_paths"
          fi
          ;;
      esac
    done

    # Track delivered injections in .state.json
    _track_delivered "$matched_rules" "$state_file"

    # Build descriptive deny reason from blocking rule IDs
    local deny_summary=""
    for (( i=0; i<blocking_count; i++ )); do
      local rid
      rid=$(echo "$blocking_rules" | jq -r ".[$i].ruleId")
      deny_summary="${deny_summary}${deny_summary:+, }${rid}"
    done

    notify_fleet error
    hook_deny \
      "Blocked by: ${deny_summary}." \
      "$block_reason" \
      ""
  fi

  # --- Step 11: Deliver allow injections ---
  _deliver_allow_rules "$allow_rules" "$state_file"
}

# _deliver_allow_rules ALLOW_RULES_JSON STATE_FILE
#   Stashes allow-urgency injections to .state.json for PostToolUse delivery.
#   Content is assembled here (preload reads, text formatting) and written to
#   pendingAllowInjections. PostToolUse hook (post-tool-use-injections.sh)
#   delivers via additionalContext, which Claude Code surfaces to the model.
_deliver_allow_rules() {
  local allow_rules="$1" state_file="$2"

  local allow_count
  allow_count=$(echo "$allow_rules" | jq 'length' 2>/dev/null || echo "0")

  if [ "$allow_count" -eq 0 ]; then
    return 0
  fi

  # Build array of {ruleId, content} entries for PostToolUse to deliver
  local stash_entries="[]"
  local i

  for (( i=0; i<allow_count; i++ )); do
    local injection
    injection=$(echo "$allow_rules" | jq ".[$i]")
    local rule_id mode entry_content=""
    rule_id=$(echo "$injection" | jq -r '.ruleId')
    mode=$(echo "$injection" | jq -r '.mode')

    case "$mode" in
      inline)
        local text
        text=$(echo "$injection" | jq -r '.payload.text // ""')
        if [ -z "$text" ]; then
          text=$(echo "$injection" | jq -r '.payload.files // [] | map("INJECTION [\(.)]") | join("\n")')
        fi
        entry_content="[Injection: $rule_id] $text"
        ;;
      read)
        local files
        files=$(echo "$injection" | jq -r '.payload.files // [] | join(", ")')
        entry_content="[Injection: $rule_id] REQUIRED: Read these files: $files"
        ;;
      paste)
        local command
        command=$(echo "$injection" | jq -r '.payload.command // ""')
        tmux_paste "$command" 2>/dev/null || true
        entry_content="[Injection: $rule_id] Pasted: $command"
        ;;
      preload)
        local preload_files preloaded_paths_allow=""
        preload_files=$(echo "$injection" | jq -r '.payload.preload // [] | .[]')
        # Read already-preloaded set for dedup
        local already_preloaded_allow="[]"
        if [ -n "$state_file" ] && [ -f "$state_file" ]; then
          already_preloaded_allow=$(jq '.preloadedFiles // []' "$state_file" 2>/dev/null || echo '[]')
        fi
        while IFS= read -r pfile; do
          [ -z "$pfile" ] && continue
          local resolved="${pfile/#\~/$HOME}"
          # Skip if already preloaded
          if echo "$already_preloaded_allow" | jq -e --arg p "$pfile" --arg r "$resolved" \
            'any(. == $p or . == $r)' >/dev/null 2>&1; then
            continue
          fi
          if [ -f "$resolved" ]; then
            local content
            content=$(cat "$resolved")
            entry_content="${entry_content}${entry_content:+\n\n}[Preloaded: $resolved]\n$content"
            preloaded_paths_allow="${preloaded_paths_allow}${preloaded_paths_allow:+
}$pfile"
          else
            echo "Warning: preload file not found, skipping: $resolved" >&2
          fi
        done <<< "$preload_files"
        # Auto-clear preloaded files from pendingDirectives + track in preloadedFiles
        if [ -n "$preloaded_paths_allow" ] && [ -n "$state_file" ] && [ -f "$state_file" ]; then
          _clear_preloaded_directives "$state_file" "$preloaded_paths_allow"
        fi
        ;;
    esac

    if [ -n "$entry_content" ]; then
      stash_entries=$(echo "$stash_entries" | jq --arg id "$rule_id" --arg c "$entry_content" \
        '. + [{"ruleId": $id, "content": $c}]')
    fi
  done

  # Track delivered injections
  _track_delivered "$allow_rules" "$state_file"

  # Stash to .state.json for PostToolUse delivery (instead of permissionDecisionReason)
  local stash_count
  stash_count=$(echo "$stash_entries" | jq 'length')
  if [ "$stash_count" -gt 0 ] && [ -n "$state_file" ] && [ -f "$state_file" ]; then
    jq --argjson entries "$stash_entries" \
      '.pendingAllowInjections = ((.pendingAllowInjections // []) + $entries)' \
      "$state_file" | safe_json_write "$state_file"
  fi
}

# _track_delivered RULES_JSON STATE_FILE
#   Marks delivered rules in .state.json injectedRules.
_track_delivered() {
  local rules_json="$1" state_file="$2"

  if [ -z "$state_file" ] || [ ! -f "$state_file" ]; then
    return 0
  fi

  local injected_updates="{}"
  local rule_count
  rule_count=$(echo "$rules_json" | jq 'length' 2>/dev/null || echo "0")

  local i
  for (( i=0; i<rule_count; i++ )); do
    local rule_id
    rule_id=$(echo "$rules_json" | jq -r ".[$i].ruleId")
    injected_updates=$(echo "$injected_updates" | jq --arg id "$rule_id" '.[$id] = true')
  done

  jq --argjson updates "$injected_updates" --arg ts "$(timestamp)" \
    '.injectedRules = ((.injectedRules // {}) + $updates) | .lastHeartbeat = $ts' \
    "$state_file" | safe_json_write "$state_file"
}

main
exit 0
