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

# rotation_log EVENT DETAIL — Append to account rotation log
# Format: [YYYY-MM-DD HH:MM:SS] EVENT: detail
# Log file: ~/.claude/accounts/rotation.log
rotation_log() {
  local event="${1:?rotation_log requires EVENT}" detail="${2:-}"
  local log_dir="$HOME/.claude/accounts"
  local log_file="$log_dir/rotation.log"
  mkdir -p "$log_dir"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$ts] $event: $detail" >> "$log_file"
}

# notify_fleet STATE — Send fleet notification if in fleet tmux
# Safely no-ops outside fleet. STATE: working|done|error|unchecked
notify_fleet() {
  [ -n "${TMUX:-}" ] || return 0
  local socket
  local tmux_path
  tmux_path=$(echo "$TMUX" | cut -d, -f1)
  socket="${tmux_path##*/}"
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

# --- Path normalization utilities ---

# normalize_preload_path PATH → canonical absolute path on stdout
#   1. Resolves ~ to $HOME
#   2. Resolves directory symlinks (e.g., ~/.claude/.directives/ → ~/.claude/engine/.directives/)
#   Outputs absolute paths for consistent dedup in preloadedFiles/pendingPreloads.
normalize_preload_path() {
  local path="$1"
  local resolved="${path/#\~/$HOME}"
  # Resolve directory symlinks (macOS compatible: cd + pwd -P)
  # Use parameter expansion instead of dirname/basename for zsh compatibility
  if [ -f "$resolved" ]; then
    local dir_part="${resolved%/*}"
    local base_part="${resolved##*/}"
    local real_dir
    real_dir=$(cd "$dir_part" 2>/dev/null && pwd -P) || real_dir="$dir_part"
    resolved="$real_dir/$base_part"
  fi
  echo "$resolved"
}

# get_session_start_seeds → JSON array of canonical seed paths on stdout
#   Returns the same 6 paths that SessionStart seeds into preloadedFiles.
#   Deterministic — any hook can call this to know what SessionStart injected.
get_session_start_seeds() {
  local engine_dir
  engine_dir=$(cd "$HOME/.claude/.directives" 2>/dev/null && pwd -P) || engine_dir="$HOME/.claude/.directives"
  jq -n --arg d "$engine_dir" '[$d+"/COMMANDS.md",$d+"/INVARIANTS.md",$d+"/SIGILS.md",$d+"/commands/CMD_DEHYDRATE.md",$d+"/commands/CMD_RESUME_SESSION.md",$d+"/commands/CMD_PARSE_PARAMETERS.md"]'
}

# filter_preseeded_paths PATHS_NEWLINE_DELIMITED → filtered paths on stdout
#   Removes any path that matches a SessionStart seed. Use when no active session
#   exists and preloadedFiles can't be checked in .state.json.
filter_preseeded_paths() {
  local input="$1"
  [ -n "$input" ] || return 0
  local seeds_json
  seeds_json=$(get_session_start_seeds)
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    local is_seed
    is_seed=$(echo "$seeds_json" | jq -r --arg f "$p" 'any(. == $f)' 2>/dev/null || echo "false")
    if [ "$is_seed" = "false" ]; then
      echo "$p"
    fi
  done <<< "$input"
}

# extract_skill_preloads SKILL_NAME
#   Reads SKILL.md, extracts Phase 0 CMD files + template files.
#   Outputs normalized tilde-prefix paths (one per line) to stdout.
#   Does NOT check dedup — caller handles that.
#   Fails silently on malformed JSON or missing files.
extract_skill_preloads() {
  local skill_name="$1"
  local skill_dir="$HOME/.claude/skills/$skill_name"
  local skill_file="$skill_dir/SKILL.md"
  [ -f "$skill_file" ] || return 0

  # Extract JSON block from SKILL.md
  local params_json
  params_json=$(sed -n '/^```json$/,/^```$/p' "$skill_file" | sed '1d;$d' 2>/dev/null || echo "")
  [ -n "$params_json" ] || return 0

  # Phase 0 CMD files
  local phase0_cmds
  phase0_cmds=$(echo "$params_json" | jq -r '
    (.phases // [])[0] |
    ((.steps // []) + (.commands // [])) |
    .[] | select(startswith("§CMD_"))
  ' 2>/dev/null || echo "")

  local cmd_dir="$HOME/.claude/engine/.directives/commands"
  local seen_cmds=""
  if [ -n "$phase0_cmds" ]; then
    while IFS= read -r field; do
      [ -n "$field" ] || continue
      local name="${field#§CMD_}"
      name=$(echo "$name" | sed -E 's/_[a-z][a-z_]*$//')
      case "$seen_cmds" in *"|${name}|"*) continue ;; esac
      seen_cmds="${seen_cmds}|${name}|"
      local cmd_file="$cmd_dir/CMD_${name}.md"
      [ -f "$cmd_file" ] || continue
      normalize_preload_path "$cmd_file"
    done <<< "$phase0_cmds"
  fi

  # Template files (logTemplate, debriefTemplate, planTemplate)
  local template_paths
  template_paths=$(echo "$params_json" | jq -r '[.logTemplate, .debriefTemplate, .planTemplate] | .[] // empty' 2>/dev/null || echo "")
  if [ -n "$template_paths" ]; then
    while IFS= read -r rel_path; do
      [ -n "$rel_path" ] || continue
      local candidate="$skill_dir/$rel_path"
      [ -f "$candidate" ] || continue
      normalize_preload_path "$candidate"
    done <<< "$template_paths"
  fi
}

# --- Workspace path resolution utilities ---

# resolve_sessions_dir — Returns the sessions directory path
# Without WORKSPACE: returns "sessions"
# With WORKSPACE: returns "$WORKSPACE/sessions"
resolve_sessions_dir() {
  if [ -n "${WORKSPACE:-}" ]; then
    echo "${WORKSPACE}/sessions"
  else
    echo "sessions"
  fi
}

# resolve_session_path — Normalizes a session path argument
# Accepts 3 forms:
#   1. Bare name: "2026_02_14_X" → "$SESSIONS_DIR/2026_02_14_X"
#   2. With prefix: "sessions/2026_02_14_X" → "$SESSIONS_DIR/2026_02_14_X"
#   3. Full path: "epic/sessions/2026_02_14_X" → used as-is (must contain "sessions/")
# Does NOT validate existence — caller decides.
resolve_session_path() {
  local input="$1"
  local sessions_dir
  sessions_dir=$(resolve_sessions_dir)

  case "$input" in
    */sessions/*)
      # Full path with sessions/ segment — use as-is
      echo "$input"
      ;;
    sessions/*)
      # Strip "sessions/" prefix, prepend resolved sessions dir
      echo "$sessions_dir/${input#sessions/}"
      ;;
    *)
      # Bare session name — prepend resolved sessions dir
      echo "$sessions_dir/$input"
      ;;
  esac
}

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
  dir_name="${dir_path##*/}"
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

# --- Input validation functions ---
# Boundary validation for user/LLM-provided strings.
# All validators exit 1 with stderr on failure (fail-hard).

# validate_tag TAG
#   Strips leading # if present. Validates: ^[a-z][a-z0-9-]*$
#   Outputs the clean tag (without #) on stdout.
#   Exit 1 on invalid input.
validate_tag() {
  local raw="${1:-}"
  # Strip leading #
  local tag="${raw#\#}"
  if [ -z "$tag" ]; then
    echo "ERROR: validate_tag: empty tag" >&2
    return 1
  fi
  if ! [[ "$tag" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "ERROR: validate_tag: invalid tag '$raw' (must match ^[a-z][a-z0-9-]*$)" >&2
    return 1
  fi
  echo "$tag"
}

# validate_subcmd SUBCMD
#   Validates: ^[a-z][a-z0-9-]+$ (minimum 2 chars)
#   Exit 1 on invalid input.
validate_subcmd() {
  local subcmd="${1:-}"
  if [ -z "$subcmd" ]; then
    echo "ERROR: validate_subcmd: empty subcommand" >&2
    return 1
  fi
  if ! [[ "$subcmd" =~ ^[a-z][a-z0-9-]+$ ]]; then
    echo "ERROR: validate_subcmd: invalid subcommand '$subcmd' (must match ^[a-z][a-z0-9-]+$)" >&2
    return 1
  fi
}

# validate_path PATH
#   Rejects ".." traversal components. Checks file or directory exists.
#   Exit 1 on invalid input.
validate_path() {
  local path="${1:-}"
  if [ -z "$path" ]; then
    echo "ERROR: validate_path: empty path" >&2
    return 1
  fi
  # Reject ".." path components
  if [[ "$path" == *".."* ]]; then
    echo "ERROR: validate_path: path traversal detected in '$path'" >&2
    return 1
  fi
  # Check existence (file or directory)
  if [ ! -e "$path" ]; then
    echo "ERROR: validate_path: path does not exist: '$path'" >&2
    return 1
  fi
}

# validate_phase PHASE_LABEL
#   Rejects sed metacharacters (/, &, \) and newlines.
#   Exit 1 on invalid input.
validate_phase() {
  local phase="${1:-}"
  if [ -z "$phase" ]; then
    echo "ERROR: validate_phase: empty phase label" >&2
    return 1
  fi
  # Reject sed metacharacters and newlines
  if [[ "$phase" == *"/"* ]] || [[ "$phase" == *"&"* ]] || [[ "$phase" == *"\\"* ]] || [[ "$phase" == *$'\n'* ]]; then
    echo "ERROR: validate_phase: invalid characters in phase label '$phase' (no /, &, \\, or newlines)" >&2
    return 1
  fi
}

# --- Rule evaluation engine ---
# Core evaluation function for the unified guard rule engine.
# Extracted from session.sh evaluate-guards for shared use between
# the hook (inline) and session.sh (backward compat wrapper).

# _resolve_payload_refs PAYLOAD_JSON STATE_FILE
#   Resolve "$fieldName" references in payload values from .state.json.
#   Two-pass resolution:
#     Pass 1 (whole-value): Strings starting with "$" get replaced entirely.
#       Example: "$pendingPreloads" → ["~/.claude/.directives/a.md", "~/.claude/.directives/b.md"]
#     Pass 2 (inline): Strings containing "$field" get interpolated in-place.
#       Example: "lifecycle: $lifecycle" → "lifecycle: completed"
#       Only substitutes scalar state values (string, number, boolean).
#   Returns the resolved payload JSON.
_resolve_payload_refs() {
  local payload="$1" state_file="$2"

  if [ -z "$state_file" ] || [ ! -f "$state_file" ]; then
    echo "$payload"
    return 0
  fi

  local resolved="$payload"

  # Pass 1: Whole-value $field resolution
  # Keys whose values are strings starting with "$" get replaced entirely
  local ref_keys
  ref_keys=$(echo "$payload" | jq -r 'to_entries[] | select(.value | type == "string" and startswith("$")) | .key' 2>/dev/null || echo "")

  if [ -n "$ref_keys" ]; then
    while IFS= read -r key; do
      [ -z "$key" ] && continue
      local ref_val field_name
      ref_val=$(echo "$payload" | jq -r --arg k "$key" '.[$k]')
      field_name="${ref_val#\$}"

      local state_val
      state_val=$(jq --arg f "$field_name" '.[$f] // null' "$state_file" 2>/dev/null || echo "null")

      if [ "$state_val" != "null" ]; then
        resolved=$(echo "$resolved" | jq --arg k "$key" --argjson v "$state_val" '.[$k] = $v')
      fi
    done <<< "$ref_keys"
  fi

  # Pass 2: Inline $field interpolation within string values
  # Handles strings like "lifecycle: $lifecycle, dir: $sessionDir"
  # Only substitutes scalar state values (string, number, boolean)
  local inline_keys
  inline_keys=$(echo "$resolved" | jq -r 'to_entries[] | select(.value | type == "string" and contains("$") and (startswith("$") | not)) | .key' 2>/dev/null || echo "")

  if [ -n "$inline_keys" ]; then
    while IFS= read -r key; do
      [ -z "$key" ] && continue
      local str_val
      str_val=$(echo "$resolved" | jq -r --arg k "$key" '.[$k]')
      local vars
      vars=$(echo "$str_val" | grep -oE '\$[a-zA-Z_][a-zA-Z0-9_]*' | sort -u | awk '{print length, $0}' | sort -rnk1 | awk '{print $2}' || echo "")
      if [ -n "$vars" ]; then
        local new_val="$str_val"
        while IFS= read -r var_ref; do
          [ -z "$var_ref" ] && continue
          local var_name="${var_ref#\$}"
          local var_val
          var_val=$(jq -r --arg f "$var_name" '.[$f] // null | if type == "string" or type == "number" or type == "boolean" then tostring else "" end' "$state_file" 2>/dev/null || echo "")
          if [ -n "$var_val" ]; then
            new_val="${new_val//$var_ref/$var_val}"
          fi
        done <<< "$vars"
        resolved=$(echo "$resolved" | jq --arg k "$key" --arg v "$new_val" '.[$k] = $v')
      fi
    done <<< "$inline_keys"
  fi

  echo "$resolved"
}

# evaluate_rules STATE_FILE GUARDS_FILE [TRANSCRIPT_KEY] [TOOL_NAME]
#   Evaluate all guard rules against current session state.
#   Outputs matched rules as a JSON array (sorted by priority) to stdout.
#   TRANSCRIPT_KEY is optional — used for perTranscriptToolCount trigger.
#   TOOL_NAME is optional — used for toolFilter exclusion (e.g., skip preload on Bash/Grep/Glob).
#
#   Reads: .state.json fields (contextUsage, lifecycle, currentPhase, etc.)
#   Reads: guards.json rules
#   Reads: config.sh for OVERFLOW_THRESHOLD
#
#   Returns 0 always (errors produce empty array).
evaluate_rules() {
  local state_file="${1:?evaluate_rules requires STATE_FILE}"
  local guards_file="${2:?evaluate_rules requires GUARDS_FILE}"
  local transcript_key="${3:-}"
  local tool_name="${4:-}"

  if [ ! -f "$state_file" ] || [ ! -f "$guards_file" ]; then
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
  rule_count=$(jq 'length' "$guards_file" 2>/dev/null || echo "0")
  local i
  for (( i=0; i<rule_count; i++ )); do
    local rule rule_id inject_freq trigger_type
    rule=$(jq ".[$i]" "$guards_file")
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

    # Skip rules excluded for this tool type (toolFilter.exclude)
    if [ -n "$tool_name" ]; then
      local excluded
      excluded=$(echo "$rule" | jq -r --arg t "$tool_name" '(.toolFilter.exclude // []) | any(. == $t)')
      if [ "$excluded" = "true" ]; then
        continue
      fi
      # Skip rules that only apply to specific tools (toolFilter.include)
      local has_include
      has_include=$(echo "$rule" | jq -r '.toolFilter.include // null | type')
      if [ "$has_include" = "array" ]; then
        local included
        included=$(echo "$rule" | jq -r --arg t "$tool_name" '.toolFilter.include | any(. == $t)')
        if [ "$included" != "true" ]; then
          continue
        fi
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
        local no_active lifecycle_eq
        no_active=$(echo "$rule" | jq -r '.trigger.condition.noActiveSession // false')
        lifecycle_eq=$(echo "$rule" | jq -r '.trigger.condition.eq // ""')
        if [ "$no_active" = "true" ]; then
          if [ "$lifecycle" != "active" ] && [ "$lifecycle" != "idle" ] && [ "$lifecycle" != "resuming" ] && [ "$lifecycle" != "restarting" ]; then
            matched=true
          fi
        elif [ -n "$lifecycle_eq" ]; then
          if [ "$lifecycle" = "$lifecycle_eq" ]; then
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
      # Example: payload.preload = "$pendingPreloads" → resolves to actual array from state
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

# --- tmux guard utilities ---
# Used by guard framework hooks for paste mode delivery.
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
  sleep 0.3
  # Second ESC for reliability (belt and suspenders)
  tmux send-keys $target_flag Escape 2>/dev/null
  sleep 0.3
  # Ctrl+U clears the textarea (any leftover typed text)
  tmux send-keys $target_flag C-u 2>/dev/null
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

# --- Reference resolution utilities ---

# resolve_refs FILE_PATH [DEPTH] [ALREADY_LOADED_JSON]
#   Scans FILE_PATH for unescaped §(CMD|FMT|INV)_ references.
#   Resolves each to a file path via convention-based prefix-to-folder mapping.
#   Recurses to DEPTH (default 2). Deduplicates against ALREADY_LOADED_JSON.
#   Walk-up resolution: starts from FILE_PATH's directory, walks up checking
#   .directives/{prefix_folder}/ at each level, falls back to engine .directives/.
#   Outputs resolved file paths (one per line, tilde-prefix normalized) to stdout.
#
#   Prefix-to-folder mapping:
#     CMD → commands/
#     FMT → formats/
#     INV → invariants/
#
#   SKILL.md files are excluded from CMD preloading (preserves lazy per-phase loading).
#   SKILL.md CAN trigger FMT preloading.
#   Only § (section sign) references are resolved, not ¶ (pilcrow) definitions.
#
#   Returns: 0 always. Empty output = no refs found or all already loaded.
resolve_refs() {
  local file_path="${1:-}"
  local depth="${2:-2}"
  local already_loaded_json="${3:-[]}"

  [ -n "$file_path" ] || return 0
  [ -f "$file_path" ] || return 0
  [ "$depth" -gt 0 ] 2>/dev/null || return 0

  # Determine if this is a SKILL.md file (excluded from CMD preloading)
  local basename_file
  basename_file="${file_path##*/}"
  local is_skill_md=false
  if [ "$basename_file" = "SKILL.md" ]; then
    is_skill_md=true
  fi

  # Two-pass regex: strip code fences + backtick spans, then extract § references
  # Pass 1: awk skips lines inside ``` code fences AND strips inline `code` spans
  # Pass 2: Extract bare §(CMD|FMT|INV)_NAME references
  local refs
  refs=$(awk '/^```/{skip=!skip; next} skip{next} {gsub(/`[^`]*`/, ""); print}' "$file_path" | grep -oE '§(CMD|FMT|INV)_[A-Z][A-Z0-9_]*' | sort -u || true)

  [ -n "$refs" ] || return 0

  # Resolve the starting directory for walk-up
  local start_dir
  start_dir=$(cd "${file_path%/*}" && pwd)

  # Project root detection (stop walk-up here)
  local project_root="${PROJECT_ROOT:-$(pwd)}"

  # Engine directives fallback
  local engine_directives="$HOME/.claude/engine/.directives"

  local new_depth=$((depth - 1))
  local collected=""

  while IFS= read -r ref; do
    [ -n "$ref" ] || continue

    # Extract prefix and name: §CMD_FOO → prefix=CMD, name=FOO, full=CMD_FOO
    local full_name="${ref#§}"
    local prefix="${full_name%%_*}"
    local ref_name="$full_name"

    # Prefix-to-folder mapping
    local folder
    case "$prefix" in
      CMD) folder="commands" ;;
      FMT) folder="formats" ;;
      INV) folder="invariants" ;;
      *)   continue ;;
    esac

    # Walk-up resolution: check .directives/{folder}/ at each ancestor level
    local resolved=""
    local search_dir="$start_dir"
    while true; do
      local candidate="$search_dir/.directives/$folder/${ref_name}.md"
      if [ -f "$candidate" ]; then
        resolved="$candidate"
        break
      fi

      # Stop at project root or filesystem root
      if [ "$search_dir" = "$project_root" ] || [ "$search_dir" = "/" ] || [ -z "$search_dir" ]; then
        break
      fi

      # Move up one level
      search_dir="${search_dir%/*}"
    done

    # Fallback to engine .directives/
    if [ -z "$resolved" ]; then
      local engine_candidate="$engine_directives/$folder/${ref_name}.md"
      if [ -f "$engine_candidate" ]; then
        resolved="$engine_candidate"
      fi
    fi

    [ -n "$resolved" ] || continue

    # Normalize the path for dedup
    local normalized
    normalized=$(normalize_preload_path "$resolved")

    # Check against already_loaded list
    local already_present
    already_present=$(echo "$already_loaded_json" | jq -r --arg p "$normalized" 'any(. == $p)' 2>/dev/null || echo "false")
    if [ "$already_present" = "true" ]; then
      continue
    fi

    # Check against collected so far (prevent duplicates in output)
    case "$collected" in
      *"|$normalized|"*) continue ;;
    esac
    collected="${collected}|${normalized}|"

    # Output this resolved path
    echo "$normalized"

    # Recurse into the resolved file (depth - 1)
    if [ "$new_depth" -gt 0 ]; then
      # Add current file to already_loaded for recursion dedup
      local updated_loaded
      updated_loaded=$(echo "$already_loaded_json" | jq --arg p "$normalized" '. + [$p]' 2>/dev/null || echo "$already_loaded_json")
      local sub_refs
      sub_refs=$(resolve_refs "$resolved" "$new_depth" "$updated_loaded")
      if [ -n "$sub_refs" ]; then
        while IFS= read -r sub_path; do
          [ -n "$sub_path" ] || continue
          # Dedup against collected
          case "$collected" in
            *"|$sub_path|"*) continue ;;
          esac
          collected="${collected}|${sub_path}|"
          echo "$sub_path"
        done <<< "$sub_refs"
      fi
    fi
  done <<< "$refs"

  return 0
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
