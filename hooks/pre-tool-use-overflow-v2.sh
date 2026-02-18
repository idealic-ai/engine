#!/bin/bash
# ~/.claude/engine/hooks/pre-tool-use-overflow-v2.sh — Unified PreToolUse guard engine
#
# Single hook that replaces session-gate, heartbeat, and overflow hooks.
# Flow:
#   1. Parse tool info from stdin
#   2. Hardcoded critical bypass (engine log → counter reset + allow, engine session → allow)
#   3. Find session dir, read .state.json
#   4. Lifecycle bypass (dehydrating, loading, completed/restarting for heartbeat-only)
#   5. Per-transcript counter increment (with same-file edit suppression, Task bypass)
#   6. Evaluate ALL rules via evaluate_rules() — reads guards.json + .state.json
#   7. Separate matched rules into blocking vs allow
#   8. Compute union whitelist from ALL blocking rules
#   9. Tool matches union whitelist? → allow (skip all blocking guards)
#  10. Deliver blocking guards (deny + message)
#  11. Deliver allow guards (inject guidance via PostToolUse additionalContext)
#  12. Fallback: allow
#
# Mode × Urgency matrix:
#   inline+allow  → stashed for PostToolUse delivery, allow tool
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
#   Engine: guards.json (rule store), lib.sh (evaluate_rules, match_whitelist)
#   Invariants: ¶INV_TMUX_AND_FLEET_OPTIONAL

set -euo pipefail

# Source shared utilities (hook_allow, hook_deny, state_read, safe_json_write,
# tmux_*, evaluate_rules, match_whitelist)
source "$HOME/.claude/scripts/lib.sh"

# Source config (OVERFLOW_THRESHOLD)
source "$HOME/.claude/engine/config.sh" 2>/dev/null || true
OVERFLOW_THRESHOLD="${OVERFLOW_THRESHOLD:-0.76}"

HOOK_NAME="overflow-v2"
GUARDS_FILE="$HOME/.claude/engine/guards.json"

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

# --- Step 2: Find session directory (once, reuse throughout) ---
# Cached in _CACHED_SESSION_DIR to avoid redundant session.sh find calls.
_CACHED_SESSION_DIR=""
find_session_dir() {
  if [ -z "$_CACHED_SESSION_DIR" ]; then
    _CACHED_SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
  fi
  echo "$_CACHED_SESSION_DIR"
}

# --- Step 3: Hardcoded critical bypass ---
# engine log and engine session MUST always pass through.
# engine log also resets the per-transcript counter.
if [ "$TOOL_NAME" = "Bash" ]; then
  if is_engine_log_cmd "$BASH_CMD"; then
    # Reset counter on log command (same as heartbeat-v2)
    session_dir=$(find_session_dir)
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

# _clear_preloaded STATE_FILE PRELOADED_PATHS
#   Remove successfully preloaded files from pendingPreloads,
#   and track them in preloadedFiles to prevent double-loading on re-discovery.
#   PRELOADED_PATHS is newline-separated list of original (unresolved) paths.
_clear_preloaded() {
  local state_file="$1" preloaded_paths="$2"

  # Batch: collect all paths to remove and track
  local remove_paths="[]"
  while IFS= read -r ppath; do
    [ -z "$ppath" ] && continue
    local resolved="${ppath/#\~/$HOME}"
    remove_paths=$(echo "$remove_paths" | jq --arg p "$ppath" --arg r "$resolved" '. + [$p, $r]')
  done <<< "$preloaded_paths"

  # Single atomic write: remove from pendingPreloads + add to preloadedFiles
  jq --argjson paths "$remove_paths" \
    '(.pendingPreloads //= []) | .pendingPreloads -= $paths |
     (.preloadedFiles //= []) | .preloadedFiles = (.preloadedFiles + $paths | unique)' \
    "$state_file" | safe_json_write "$state_file"
}

# NOTE: _claim_and_preload() removed — replaced by preload_ensure() in lib.sh
# preload_ensure() handles dedup, atomic tracking, delivery, and auto-expansion
# of § references via _auto_expand_refs(). See steps 2/1–2/5.

# _atomic_claim_dir DIR_PATH STATE_FILE
#   Atomically checks if a directory is tracked in touchedDirs and claims it if not.
#   Uses the same mkdir lock as safe_json_write for mutual exclusion.
#   Prevents TOCTOU race when parallel tool calls touch the same directory.
#   Echoes "claimed" if newly claimed, "already" if already tracked.
_atomic_claim_dir() {
  local dir_path="$1" state_file="$2"
  local lock_dir="${state_file}.lock"

  # Acquire lock (same mechanism as safe_json_write)
  local retries=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    retries=$((retries + 1))
    if [ "$retries" -ge 100 ]; then
      echo "already"  # Timeout — treat as claimed to avoid duplicate discovery
      return 0
    fi
    if [ -d "$lock_dir" ]; then
      local lock_mtime now_epoch
      lock_mtime=$(stat -f "%m" "$lock_dir" 2>/dev/null || echo "0")
      now_epoch=$(date +%s)
      if [ $((now_epoch - lock_mtime)) -gt 10 ]; then
        rmdir "$lock_dir" 2>/dev/null || true
        continue
      fi
    fi
    sleep 0.01
  done

  # Under lock: check + claim
  local already
  already=$(jq -r --arg dir "$dir_path" \
    '(.touchedDirs // {}) | has($dir)' "$state_file" 2>/dev/null || echo "false")

  if [ "$already" = "true" ]; then
    rmdir "$lock_dir" 2>/dev/null || true
    echo "already"
    return 0
  fi

  # Claim: register directory in touchedDirs
  jq --arg dir "$dir_path" \
    '(.touchedDirs //= {}) | .touchedDirs[$dir] = []' \
    "$state_file" > "${state_file}.tmp.$$"
  mv "${state_file}.tmp.$$" "$state_file"

  rmdir "$lock_dir" 2>/dev/null || true
  echo "claimed"
  return 0
}

# _run_discovery STATE_FILE
#   Runs directive discovery for Read/Edit/Write tools BEFORE evaluate_rules().
#   Extracts file_path from TOOL_INPUT, discovers directives in the directory,
#   populates pendingPreloads + touchedDirs + discoveredChecklists.
#   This enables the directive-autoload rule to fire in the SAME tool call,
#   eliminating the one-call latency of PostToolUse-based discovery.
_run_discovery() {
  local state_file="$1"

  # Process tools that indicate directory interaction
  # Read/Edit/Write: file being worked on → discover directives in its directory
  # Glob/Grep: path param is search scope → discover directives there too
  case "$TOOL_NAME" in
    Read|Edit|Write|Glob|Grep) ;;
    *) return 0 ;;
  esac

  # Extract file path from tool_input (Read/Edit/Write use file_path, Grep/Glob use path)
  local file_path
  file_path=$(echo "$TOOL_INPUT" | jq -r '.file_path // .path // ""' 2>/dev/null || echo "")
  [ -n "$file_path" ] || return 0

  # Get directory from file path (Grep/Glob path may already be a directory)
  local dir_path
  if [ -d "$file_path" ]; then
    dir_path="$file_path"
  else
    dir_path=$(dirname "$file_path")
  fi
  [ -n "$dir_path" ] || return 0

  # Atomic claim: check + register directory in one locked operation.
  # Prevents TOCTOU race when parallel tool calls touch the same directory —
  # only the winning hook proceeds with discovery.
  local claim_result
  claim_result=$(_atomic_claim_dir "$dir_path" "$state_file")
  if [ "$claim_result" = "already" ]; then
    return 0
  fi

  # Multi-root: if path is under ~/.claude/, pass --root to cap walk-up
  local root_arg=""
  if [[ "$dir_path" == "$HOME/.claude/"* ]]; then
    root_arg="--root $HOME/.claude"
  fi

  # Run discovery for all directive files (soft — CHECKLIST.md moved from hard to soft)
  local soft_files
  soft_files=$("$HOME/.claude/scripts/discover-directives.sh" "$dir_path" --walk-up --type soft $root_arg 2>/dev/null || echo "")

  # Core directives are always suggested; skill directives need declaration
  local core_directives=("AGENTS.md" "INVARIANTS.md" "COMMANDS.md")

  # Read skill-declared directives from .state.json
  local skill_directives
  skill_directives=$(jq -r '(.directives // []) | .[]' "$state_file" 2>/dev/null || echo "")

  # Track which soft files are new (not already suggested for another dir)
  local new_soft_files=()
  if [ -n "$soft_files" ]; then
    while IFS= read -r file; do
      [ -n "$file" ] || continue
      # Normalize path: resolve directory symlinks + tilde prefix
      # Prevents dupes when SessionStart uses ~/.claude/.directives/X (symlink)
      # and discovery finds ~/.claude/engine/.directives/X (canonical)
      file=$(normalize_preload_path "$file")
      local local_basename
      local_basename=$(basename "$file")

      # Check if this is a core directive (always suggested) or skill directive (needs declaration)
      local is_core=false
      local core
      for core in "${core_directives[@]}"; do
        if [ "$local_basename" = "$core" ]; then
          is_core=true
          break
        fi
      done

      if [ "$is_core" = "false" ]; then
        # Skill directive — check if declared
        local is_declared=false
        if [ -n "$skill_directives" ]; then
          local declared
          while IFS= read -r declared; do
            if [ "$local_basename" = "$declared" ]; then
              is_declared=true
              break
            fi
          done <<< "$skill_directives"
        fi
        if [ "$is_declared" = "false" ]; then
          continue  # Skip — skill doesn't care about this directive type
        fi
      fi

      # Check if file was already suggested via any touchedDir
      # Handles two value formats:
      #   Full path (from _run_discovery): "/abs/path/.directives/AGENTS.md" → direct compare
      #   Basename (from session activate): "AGENTS.md" → reconstruct as key/basename, compare
      # strip_private handles macOS /var → /private/var symlink normalization mismatch
      local already_suggested
      already_suggested=$(jq -r --arg file "$file" \
        'def sp: if startswith("/private") then ltrimstr("/private") else . end;
        [(.touchedDirs // {}) | to_entries[] |
          (.key | sp) as $dir | .value[] |
          if startswith("/") then (. | sp) == ($file | sp)
          else ($dir + "/" + .) == ($file | sp)
          end |
          select(.)
        ] | length > 0' \
        "$state_file" 2>/dev/null || echo "false")
      if [ "$already_suggested" != "true" ]; then
        new_soft_files+=("$file")
      fi
    done <<< "$soft_files"
  fi

  # Update touchedDirs with the files we're about to suggest
  if [ ${#new_soft_files[@]} -gt 0 ]; then
    local filenames_json="[]"
    local f
    for f in "${new_soft_files[@]}"; do
      filenames_json=$(echo "$filenames_json" | jq --arg name "$f" '. + [$name] | unique')
    done
    jq --arg dir "$dir_path" --argjson names "$filenames_json" \
      '(.touchedDirs //= {}) | .touchedDirs[$dir] = $names' \
      "$state_file" | safe_json_write "$state_file"
  fi

  # Add new soft files to pendingPreloads + discoveredChecklists (batched single write)
  if [ ${#new_soft_files[@]} -gt 0 ]; then
    local files_json="[]"
    local checklists_json="[]"
    local f
    for f in "${new_soft_files[@]}"; do
      files_json=$(echo "$files_json" | jq --arg f "$f" '. + [$f]')
      if [[ "$(basename "$f")" == "CHECKLIST.md" ]]; then
        checklists_json=$(echo "$checklists_json" | jq --arg f "$f" '. + [$f]')
      fi
    done
    # Read .preloadedFiles inside jq to avoid stale snapshot (TOCTOU fix)
    # Both preloadedFiles entries and new_soft_files are already normalized
    # by normalize_preload_path(), so direct comparison works.
    jq --argjson files "$files_json" --argjson checklists "$checklists_json" '
      (.preloadedFiles // []) as $pf |
      (.pendingPreloads //= []) |
      (.discoveredChecklists //= []) |
      reduce ($files[]) as $f (.;
        if ($pf | any(. == $f)) then .
        elif (.pendingPreloads | index($f)) then .
        else .pendingPreloads += [$f]
        end
      ) |
      reduce ($checklists[]) as $c (.;
        if (.discoveredChecklists | index($c)) then .
        else .discoveredChecklists += [$c]
        end
      ) |
      .directiveReadsWithoutClearing = 0
    ' "$state_file" | safe_json_write "$state_file"
  fi

  return 0
}

# _enrich_heartbeat_message TEXT STATE_FILE SESSION_DIR
#   Enriches a heartbeat message with counter (N/M) and log path.
#   Falls back to original text if no session context available.
_enrich_heartbeat_message() {
  local text="$1" state_file="$2" session_dir="$3"

  if [ -z "$session_dir" ] || [ -z "$state_file" ] || [ ! -f "$state_file" ]; then
    echo "$text"
    return 0
  fi

  # Read counter, block threshold, context usage, and current time
  local counter block_threshold context_pct current_time
  counter=$(jq -r '.toolCallsSinceLastLog // 0' "$state_file" 2>/dev/null || echo "0")
  block_threshold=$(jq -r '.toolUseWithoutLogsBlockAfter // 10' "$state_file" 2>/dev/null || echo "10")
  local context_raw
  context_raw=$(jq -r '.contextUsage // 0' "$state_file" 2>/dev/null || echo "0")
  context_pct=$(awk "BEGIN {printf \"%.0f\", $context_raw * 100}")
  current_time=$(date '+%H:%M')

  # Derive log file from logTemplate in .state.json
  local log_template log_file log_path
  log_template=$(jq -r '.logTemplate // ""' "$state_file" 2>/dev/null || echo "")
  if [ -n "$log_template" ]; then
    local log_basename
    log_basename=$(basename "$log_template")
    log_file="${log_basename#TEMPLATE_}"
  else
    local skill
    skill=$(state_read "$state_file" skill "")
    if [ -z "$skill" ]; then
      echo "$text"
      return 0
    fi
    log_file="$(echo "$skill" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z]/_/g')_LOG.md"
  fi
  log_path="${session_dir}/${log_file}"

  # Strip $PWD/ prefix from log path for cleaner output
  local display_log_path="$log_path"
  local pwd_prefix
  pwd_prefix=$(pwd)
  display_log_path="${log_path#"$pwd_prefix"/}"

  # Resolve log template filename for agent guidance
  local template_name=""
  if [ -n "$log_template" ]; then
    template_name=$(basename "$log_template")
  fi

  # Output: §CMD_APPEND_LOG (N/M) [HH:MM | Context: XX%] + engine log command with heredoc template hint
  if [ -n "$template_name" ]; then
    printf "%s (%s/%s) [%s | Context: %s%%]\n    $ engine log %s <<'EOF' [Template: %s] ... EOF" "$text" "$counter" "$block_threshold" "$current_time" "$context_pct" "$display_log_path" "$template_name"
  else
    printf '%s (%s/%s) [%s | Context: %s%%]\n    $ engine log %s' "$text" "$counter" "$block_threshold" "$current_time" "$context_pct" "$display_log_path"
  fi
}

main() {
  notify_fleet working

  local session_dir
  if ! session_dir=$(find_session_dir); then
    # No session found — auto-activate /do silently (mechanical, no agent decision)
    # Creates an ad-hoc session so the tool can proceed without gate blocking.
    # Uses date-based naming: sessions/YYYY_MM_DD_ADHOC (reuses if exists)
    local adhoc_dir="sessions/$(date +%Y_%m_%d)_ADHOC"
    "$HOME/.claude/scripts/session.sh" activate "$adhoc_dir" do < /dev/null 2>/dev/null || true
    # Re-find session dir after activation
    session_dir=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
    if [ -z "$session_dir" ]; then
      # Activation failed — fall back to old behavior (evaluate rules, gate fires)
      if [ -f "$GUARDS_FILE" ]; then
        local tmp_state
        tmp_state=$(mktemp)
        echo '{"lifecycle":"none","contextUsage":0}' > "$tmp_state"
        local matched_rules
        matched_rules=$(evaluate_rules "$tmp_state" "$GUARDS_FILE" "$TRANSCRIPT_KEY")
        rm -f "$tmp_state"
        _process_rules "$matched_rules" "" ""
      fi
      hook_allow
    fi
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

  # Allow engine session dehydrate or /session continue (overflow recovery path)
  if [ "$TOOL_NAME" = "Bash" ] && [[ "$BASH_CMD" == *"engine session dehydrate"* ]]; then
    jq '.lifecycle = "dehydrating"' "$state_file" | safe_json_write "$state_file"
    hook_allow
  fi
  if [ "$TOOL_NAME" = "Skill" ] && [ "$SKILL_ARG" = "session" ]; then
    if [[ "$SKILL_ARGS" == *continue* ]]; then
      hook_allow
    fi
  fi

  # Allow all tools during dehydration/restart flow
  if [ "$lifecycle" = "dehydrating" ] || [ "$killRequested" = "true" ]; then
    hook_allow
  fi

  # Loading/completed/idle/restarting/overflowed bypass for heartbeat counters
  # (don't increment or enforce heartbeat during these states)
  # idle: session is between skills — no logging requirement until a new skill activates
  local skip_heartbeat=false
  if [ "$loading" = "true" ] || [ "$lifecycle" = "completed" ] || [ "$lifecycle" = "idle" ] || [ "$lifecycle" = "restarting" ] || [ "$lifecycle" = "resuming" ] || [ "$overflowed" = "true" ]; then
    skip_heartbeat=true
  fi

  # --- Step 4b: Detect subagent ---
  # Subagent detection: the first transcript key to increment a counter after
  # session activation is the primary (parent). All other keys are subagents.
  # primaryTranscriptKey is set on first increment; cleared by session continue/activate.
  local is_subagent=false
  local primary_key
  primary_key=$(jq -r '.primaryTranscriptKey // ""' "$state_file" 2>/dev/null || echo "")
  if [ -n "$primary_key" ] && [ "$TRANSCRIPT_KEY" != "$primary_key" ]; then
    is_subagent=true
  fi

  # --- Step 5: Per-transcript counter increment ---
  if [ "$skip_heartbeat" = "false" ]; then
    # Task tool bypasses counter
    if [ "$TOOL_NAME" != "Task" ] && [ "$TOOL_NAME" != "TaskOutput" ]; then
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
        if [ "$is_subagent" = "true" ]; then
          # Subagent: only update per-transcript counter, not global
          jq --arg key "$TRANSCRIPT_KEY" --argjson tc "$new_counter" \
            '(.toolCallsByTranscript //= {}) | .toolCallsByTranscript[$key] = $tc' \
            "$state_file" | safe_json_write "$state_file"
        else
          # Set primaryTranscriptKey on first increment (parent identification)
          if [ -z "$primary_key" ]; then
            jq --arg key "$TRANSCRIPT_KEY" --argjson tc "$new_counter" \
              '(.toolCallsByTranscript //= {}) | .toolCallsByTranscript[$key] = $tc | .toolCallsSinceLastLog = $tc | .primaryTranscriptKey = $key' \
              "$state_file" | safe_json_write "$state_file"
          else
            jq --arg key "$TRANSCRIPT_KEY" --argjson tc "$new_counter" \
              '(.toolCallsByTranscript //= {}) | .toolCallsByTranscript[$key] = $tc | .toolCallsSinceLastLog = $tc' \
              "$state_file" | safe_json_write "$state_file"
          fi
        fi
      fi
    fi
  fi

  # --- Step 5b: Run directive discovery BEFORE rule evaluation ---
  # This populates pendingPreloads so the preload rule fires same-call.
  if [ "$skip_heartbeat" = "false" ] && [ "$loading" != "true" ]; then
    _run_discovery "$state_file"
  fi

  # --- Step 6: Evaluate ALL rules ---
  local matched_rules="[]"
  if [ -f "$GUARDS_FILE" ]; then
    matched_rules=$(evaluate_rules "$state_file" "$GUARDS_FILE" "$TRANSCRIPT_KEY" "$TOOL_NAME")
  fi

  # --- Step 6b: Subagent heartbeat downgrade ---
  # Subagents get heartbeat-warn (allow nudge) but never heartbeat-block (deny).
  # Downgrade heartbeat-block urgency from "block" to "allow" for subagents.
  if [ "$is_subagent" = "true" ]; then
    matched_rules=$(echo "$matched_rules" | jq '
      [.[] | if .ruleId == "heartbeat-block" then .urgency = "allow" else . end]
    ')
  fi

  # --- Steps 7-11: Process matched rules ---
  _process_rules "$matched_rules" "$state_file" "$session_dir"

  # --- Step 12: Fallback allow ---
  hook_allow
}

# _process_rules MATCHED_RULES_JSON STATE_FILE SESSION_DIR
#   Separates blocking vs allow rules, computes union whitelist,
#   checks tool against union, delivers guards.
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
    # --- Step 7b: Overflow priority suppression ---
    # When overflow-dehydration fires alongside other blocking guards (session-gate,
    # idle-gate, heartbeat-block), overflow wins — suppress all others.
    # This prevents the agent from seeing conflicting messages (e.g., "pick a skill"
    # from session-gate when it should be dehydrating).
    local has_overflow
    has_overflow=$(echo "$blocking_rules" | jq 'any(.ruleId == "overflow-dehydration")')
    if [ "$has_overflow" = "true" ]; then
      blocking_rules=$(echo "$blocking_rules" | jq '[.[] | select(.ruleId == "overflow-dehydration")]')
      blocking_count=1
    fi

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
            text=$(echo "$injection" | jq -r '.payload.files // [] | map("[\(.)]") | join("\n")')
          fi
          # Enrich heartbeat messages with actionable logging context
          if [[ "$rule_id" == heartbeat-* ]]; then
            text=$(_enrich_heartbeat_message "$text" "$state_file" "$session_dir")
          fi
          block_reason="${block_reason}${block_reason:+\n}$text"
          ;;
        read)
          local files
          files=$(echo "$injection" | jq -r '.payload.files // [] | join(", ")')
          block_reason="${block_reason}${block_reason:+\n}[block: $rule_id] REQUIRED: Read these files: $files"
          ;;
        paste)
          local command
          command=$(echo "$injection" | jq -r '.payload.command // ""')
          if [ "$urgency" = "interrupt" ]; then
            tmux_interrupt_and_paste "$command" 2>/dev/null || true
          else
            tmux_paste "$command" 2>/dev/null || true
          fi
          block_reason="${block_reason}${block_reason:+\n}$command"
          ;;
        preload)
          local preload_files preload_content="" processed_json="[]"
          preload_files=$(echo "$injection" | jq -r '.payload.preload // [] | .[]')
          while IFS= read -r pfile; do
            [ -n "$pfile" ] || continue
            local norm_pfile
            norm_pfile=$(normalize_preload_path "$pfile")
            processed_json=$(echo "$processed_json" | jq --arg p "$pfile" --arg n "$norm_pfile" '. + [$p, $n] | unique')
            preload_ensure "$pfile" "overflow($rule_id)" "immediate"
            if [ "$_PRELOAD_RESULT" = "delivered" ] && [ -n "$_PRELOAD_CONTENT" ]; then
              preload_content="${preload_content}${preload_content:+\n\n}$_PRELOAD_CONTENT"
            fi
          done <<< "$preload_files"
          # Clean processed files from pendingPreloads (delivered, skipped-dedup, or missing)
          if [ -n "$state_file" ] && [ -f "$state_file" ]; then
            jq --argjson proc "$processed_json" '
              (.pendingPreloads //= []) | .pendingPreloads -= $proc
            ' "$state_file" | safe_json_write "$state_file"
          fi
          if [ -n "$preload_content" ]; then
            block_reason="${block_reason}${block_reason:+\n}$preload_content"
          fi
          ;;
      esac
    done

    # Track delivered guards in .state.json
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
      "[block: ${deny_summary}]" \
      "$block_reason" \
      ""
  fi

  # --- Step 11: Deliver allow injections ---
  _deliver_allow_rules "$allow_rules" "$state_file"
}

# _deliver_allow_rules ALLOW_RULES_JSON STATE_FILE
#   Stashes allow-urgency guards to .state.json for PostToolUse delivery.
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
          text=$(echo "$injection" | jq -r '.payload.files // [] | map("[\(.)]") | join("\n")')
        fi
        # Enrich heartbeat messages with actionable logging context
        if [[ "$rule_id" == heartbeat-* ]] && [ -n "$state_file" ]; then
          local hb_session_dir
          hb_session_dir=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
          text=$(_enrich_heartbeat_message "$text" "$state_file" "$hb_session_dir")
        fi
        entry_content="$text"
        ;;
      read)
        local files
        files=$(echo "$injection" | jq -r '.payload.files // [] | join(", ")')
        entry_content="[warn: $rule_id] REQUIRED: Read these files: $files"
        ;;
      paste)
        local command
        command=$(echo "$injection" | jq -r '.payload.command // ""')
        tmux_paste "$command" 2>/dev/null || true
        entry_content="$command"
        ;;
      preload)
        local preload_files preload_content="" processed_json="[]"
        preload_files=$(echo "$injection" | jq -r '.payload.preload // [] | .[]')
        while IFS= read -r pfile; do
          [ -n "$pfile" ] || continue
          local norm_pfile
          norm_pfile=$(normalize_preload_path "$pfile")
          processed_json=$(echo "$processed_json" | jq --arg p "$pfile" --arg n "$norm_pfile" '. + [$p, $n] | unique')
          preload_ensure "$pfile" "overflow($rule_id)" "immediate"
          if [ "$_PRELOAD_RESULT" = "delivered" ] && [ -n "$_PRELOAD_CONTENT" ]; then
            preload_content="${preload_content}${preload_content:+\n\n}$_PRELOAD_CONTENT"
          fi
        done <<< "$preload_files"
        # Clean processed files from pendingPreloads
        if [ -n "$state_file" ] && [ -f "$state_file" ]; then
          jq --argjson proc "$processed_json" '
            (.pendingPreloads //= []) | .pendingPreloads -= $proc
          ' "$state_file" | safe_json_write "$state_file"
        fi
        entry_content="$preload_content"
        ;;
    esac

    if [ -n "$entry_content" ]; then
      stash_entries=$(echo "$stash_entries" | jq --arg id "$rule_id" --arg c "$entry_content" \
        '. + [{"ruleId": $id, "content": $c}]')
    fi
  done

  # Track delivered guards
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
#   Marks delivered rules in .state.json injectedRules (tracks which guards fired).
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
