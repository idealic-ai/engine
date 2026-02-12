#!/bin/bash
# ~/.claude/tools/statusline.sh — Status line script for Claude Code
#
# This script is called by Claude Code to generate the status line display.
# It receives JSON on stdin with context window information.
#
# Display format:
#   SESSION · skill · N. Phase · agent · $X.XX · XX%
#   ↑         ↑       ↑                         ↑
#   clickable clickable clickable                context usage
#   → plan    → SKILL.md → target file           (normalized)
#
# When no session is active:
#   No session (red)
#
# Related:
#   Docs: (~/.claude/docs/)
#     CONTEXT_GUARDIAN.md — Context usage normalization, threshold display
#     SESSION_LIFECYCLE.md — Session state display, skill/phase tracking
#     FLEET.md — Fleet pane identity
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — Fleet-aware display

# Don't use set -e, we want to handle errors gracefully
set -u

# Source shared utilities
source "$HOME/.claude/scripts/lib.sh"

# Source shared config (threshold constant)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../engine/config.sh
source "$HOME/.claude/engine/config.sh" 2>/dev/null || true
OVERFLOW_THRESHOLD="${OVERFLOW_THRESHOLD:-0.76}"

# Read input from stdin
INPUT=$(cat)

# Extract context usage percentage (raw from Claude)
RAW_PERCENT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0' 2>/dev/null || echo "0")

# Extract session_id from Claude (needed to bind session for overflow hook)
CLAUDE_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")

# Extract agent name (if running with --agent flag)
AGENT_NAME=$(echo "$INPUT" | jq -r '.agent.name // ""' 2>/dev/null || echo "")

# Extract total cost
TOTAL_COST=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // 0' 2>/dev/null || echo "0")

# Convert to decimal (0.0 - 1.0) for .state.json (raw value, used by overflow hook)
CONTEXT_DECIMAL=$(awk "BEGIN {printf \"%.4f\", $RAW_PERCENT / 100}")

# Normalize for display: our threshold = 100% (dehydration triggers at threshold)
# When DISABLE_AUTO_COMPACT=1: show raw %, cap at 100 (full context is the target)
# When compact enabled (default): normalized = raw / (threshold * 100), capped at 100
# OVERFLOW_THRESHOLD is sourced from ~/.claude/engine/config.sh
if [ "${DISABLE_AUTO_COMPACT:-}" = "1" ]; then
  DISPLAY_PERCENT=$(awk "BEGIN {v = $RAW_PERCENT; if (v > 100) v = 100; printf \"%.0f\", v}")
else
  THRESHOLD_PERCENT=$(awk "BEGIN {printf \"%.2f\", $OVERFLOW_THRESHOLD * 100}")
  DISPLAY_PERCENT=$(awk "BEGIN {v = $RAW_PERCENT / $THRESHOLD_PERCENT * 100; if (v > 100) v = 100; printf \"%.0f\", v}")
fi

# ANSI colors
RED='\033[31m'
RESET='\033[0m'

# Get terminal link protocol from env (default to cursor://file)
LINK_PROTOCOL="${TERMINAL_LINK_PROTOCOL:-cursor://file}"

# Create an OSC 8 hyperlink
# Usage: osc8_link <uri> <display_text>
osc8_link() {
  local uri="$1"
  local text="$2"
  printf '\e]8;;%s\e\\%s\e]8;;\e\\' "$uri" "$text"
}

# Debug helper — only outputs when DEBUG=1
dbg() {
  if [ "${DEBUG:-}" = "1" ]; then
    echo "[statusline] $*" >&2
  fi
}

# Update .state.json if session exists, output session_dir and skill
# Uses session.sh find for session lookup (single source of truth)
# Handles PID claiming + sessionId binding + contextUsage update
update_session() {
  local session_dir
  # session.sh find: read-only lookup via fleet.sh pane-id or CLAUDE_SUPERVISOR_PID
  if ! session_dir=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null); then
    return 1
  fi

  local agent_file="$session_dir/.state.json"
  if [ ! -f "$agent_file" ]; then
    return 1
  fi

  local claude_pid="${CLAUDE_SUPERVISOR_PID:-$PPID}"

  dbg "--- update_session ---"
  dbg "session_dir=$session_dir, claude_pid=$claude_pid"

  # PID claiming: if session was found by fleet pane and PID doesn't match, claim it
  local file_pid
  file_pid=$(state_read "$agent_file" pid "0")
  if [ "$file_pid" != "$claude_pid" ]; then
    dbg "Claiming PID: $file_pid → $claude_pid"
    jq --argjson pid "$claude_pid" '.pid = $pid' "$agent_file" | safe_json_write "$agent_file"
  fi

  # Defense-in-depth: Check state fields — skip sessionId write during kill/overflow/dehydration
  # This prevents the race condition where statusline.sh resurrects sessionId
  # after session.sh restart deletes it (R1 in SESSION_LIFECYCLE.md)
  local kill_req overflowed lifecycle
  kill_req=$(state_read "$agent_file" killRequested "false")
  overflowed=$(state_read "$agent_file" overflowed "false")
  lifecycle=$(state_read "$agent_file" lifecycle "active")

  local ts
  ts=$(timestamp)

  if [ "$kill_req" = "true" ] || [ "$overflowed" = "true" ] || [ "$lifecycle" = "dehydrating" ]; then
    # Session is being terminated/overflowed — only update contextUsage and heartbeat, NOT sessionId
    jq --argjson usage "$CONTEXT_DECIMAL" --arg ts "$ts" \
      '.contextUsage = $usage | .lastHeartbeat = $ts' \
      "$agent_file" | safe_json_write "$agent_file"
  else
    # Normal update — include sessionId binding
    jq --argjson usage "$CONTEXT_DECIMAL" --arg ts "$ts" --arg sid "$CLAUDE_SESSION_ID" \
      '.contextUsage = $usage | .lastHeartbeat = $ts | .sessionId = $sid' \
      "$agent_file" | safe_json_write "$agent_file"
  fi

  # Output session_dir (line 1) and skill (line 2)
  echo "$session_dir"
  state_read "$agent_file" skill ""
  return 0
}

# Get session info (if any)
SESSION_DIR=""
SESSION_NAME=""
SKILL=""
PHASE=""
TARGET_FILE=""

if output=$(update_session 2>/dev/null); then
  SESSION_DIR=$(echo "$output" | head -1)
  SKILL=$(echo "$output" | tail -1)
  # Rules are now evaluated inline by the PreToolUse hook (unified rule engine)
  # Extract session name from path, strip date prefix (YYYY_MM_DD_)
  SESSION_NAME=$(basename "$SESSION_DIR" | sed 's/^[0-9]\{4\}_[0-9]\{2\}_[0-9]\{2\}_//')
  # Get current phase: "3.C: Build" → "[3.C/4] Build" (with phases) or "3.C. Build" (without)
  FULL_PHASE=$(state_read "$SESSION_DIR/.state.json" currentPhase "")
  if [ -n "$FULL_PHASE" ]; then
    # Try to build [label/max_major] name format from phases array
    # Bilingual: uses .label if present, derives from major/minor if not
    PHASE=$(jq -r --arg cp "$FULL_PHASE" '
      def phase_lbl: if has("label") then .label elif .minor == 0 then "\(.major)" else "\(.major).\(.minor)" end;
      if has("phases") and (.phases | length > 0) then
        (.phases | map(phase_lbl | split(".") | first | tonumber) | max) as $max_major |
        (.phases[] | select(("\(phase_lbl): \(.name)") == $cp)) as $match |
        if $match != null then "[\($match | phase_lbl)/\($max_major)] \($match.name)" else "" end
      else "" end
    ' "$SESSION_DIR/.state.json" 2>/dev/null || echo "")
    # Fallback: no phases array or no match
    if [ -z "$PHASE" ]; then
      PHASE=$(echo "$FULL_PHASE" | sed 's/: /. /')
    fi
  fi
  # Get target file (for clicking on skill/phase)
  TARGET_FILE=$(state_read "$SESSION_DIR/.state.json" targetFile "")
fi

# Format cost as currency
COST_FMT=$(printf '$%.2f' "$TOTAL_COST")

# Format output for status line
# Layout: SESSION · skill · N. Phase · agent · $X.XX · XX%
# No session → "No session" in red

# Build right side: agent · $cost · %
RIGHT_SIDE=""
if [ -n "$AGENT_NAME" ]; then
  RIGHT_SIDE="$AGENT_NAME · "
fi
RIGHT_SIDE="${RIGHT_SIDE}${COST_FMT} · ${DISPLAY_PERCENT}%"

# Debug mode: env var OR file-based trigger (file works even if env isn't inherited)
if [ "${DEBUG:-}" = "1" ] || [ -f /tmp/statusline-debug ]; then
  FLEET_DBG=$("$HOME/.claude/scripts/fleet.sh" pane-id 2>&1 || echo "(exit:$?)")
  SESS_EXISTS=$([ -d "$PWD/sessions" ] && echo Y || echo N)
  printf 'sup=%s ppid=%s tmux=%s pane=%s fleet=%s pwd=%s sess=%s dir=%s' \
    "${CLAUDE_SUPERVISOR_PID:-X}" "$PPID" \
    "${TMUX:+Y}${TMUX:-X}" "${TMUX_PANE:-X}" \
    "$FLEET_DBG" \
    "$(basename "$PWD")" "$SESS_EXISTS" \
    "${SESSION_DIR:-(none)}"
  exit 0
fi

if [ -z "$SESSION_DIR" ]; then
  # No session active — show in red
  printf '%b' "${RED}No session${RESET} · ${RIGHT_SIDE}"
else
  # Session active — build clickable output
  ABS_SESSION_DIR=$(cd "$SESSION_DIR" && pwd)

  # Session name → links to session directory
  SESSION_LINK=$(osc8_link "${LINK_PROTOCOL}${ABS_SESSION_DIR}" "$SESSION_NAME")

  # Skill → links to SKILL.md ("what skill is running")
  SKILL_DISPLAY=""
  if [ -n "$SKILL" ]; then
    SKILL_MD="$HOME/.claude/skills/${SKILL}/SKILL.md"
    if [ -f "$SKILL_MD" ]; then
      SKILL_DISPLAY=$(osc8_link "${LINK_PROTOCOL}${SKILL_MD}" "$SKILL")
    else
      SKILL_DISPLAY="$SKILL"
    fi
  fi

  # Phase → links to target file ("how's it going")
  PHASE_DISPLAY=""
  if [ -n "$PHASE" ]; then
    if [ -n "$TARGET_FILE" ] && [ -f "$SESSION_DIR/$TARGET_FILE" ]; then
      PHASE_DISPLAY=$(osc8_link "${LINK_PROTOCOL}${ABS_SESSION_DIR}/${TARGET_FILE}" "$PHASE")
    else
      PHASE_DISPLAY="$PHASE"
    fi
  fi

  # Assemble: SESSION · skill · phase · agent · $cost · %
  # Only include non-empty segments
  OUTPUT="$SESSION_LINK"
  [ -n "$SKILL_DISPLAY" ] && OUTPUT="$OUTPUT · $SKILL_DISPLAY"
  [ -n "$PHASE_DISPLAY" ] && OUTPUT="$OUTPUT · $PHASE_DISPLAY"
  printf '%s · %s' "$OUTPUT" "$RIGHT_SIDE"
fi
