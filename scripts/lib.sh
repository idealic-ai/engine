#!/bin/bash
# ~/.claude/scripts/lib.sh — Shared utilities for session infrastructure
#
# Related:
#   Docs: (~/.claude/docs/)
#     CONTEXT_GUARDIAN.md — lib.sh API section, consumer list
#     ENGINE_TESTING.md — Testing patterns for lib functions
#   Invariants: (~/.claude/directives/INVARIANTS.md)
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
