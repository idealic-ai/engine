#!/bin/bash
# ~/.claude/scripts/run.sh — Claude process supervisor
#
# Usage:
#   ~/.claude/scripts/run.sh [claude args...]
#
# Options:
#   --agent NAME              Load agent persona from ~/.claude/agents/NAME.md
#   --description TEXT        Agent description injected into system prompt
#   --focus TEXT              Focus areas (comma-separated) injected into system prompt
#   --monitor-tags TAGS       Daemon mode: watch for files with these tags (comma-separated)
#
# Examples:
#   ~/.claude/scripts/run.sh                      # Plain Claude
#   ~/.claude/scripts/run.sh --agent operator     # Claude with operator agent
#   ~/.claude/scripts/run.sh --agent builder      # Claude with builder agent
#   ~/.claude/scripts/run.sh --agent researcher --description "Deep research" --focus "Insurance,Claims"
#   ~/.claude/scripts/run.sh --monitor-tags '#needs-implementation,#needs-chores'  # Daemon mode
#
# Or alias it:
#   alias claude='~/.claude/scripts/run.sh'
#
# Features:
#   - Runs Claude in foreground (proper terminal control)
#   - Passes --agent to Claude natively (zero token cost, system prompt injection)
#   - Checks for restart request after Claude exits
#   - Loops with new prompt if restart was requested
#   - Auto-detects fleet pane and resumes last session if in fleet tmux
#   - Daemon mode (--monitor-tags): watches sessions/ for tagged files, auto-dispatches
#
# Related:
#   Docs: (~/.claude/docs/)
#     CONTEXT_GUARDIAN.md — Process supervision, restart handling
#     SESSION_LIFECYCLE.md — Session resumption, fleet integration
#     FLEET.md — Fleet pane detection, session binding
#   Invariants: (~/.claude/directives/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — Fleet auto-detection
#     ¶INV_CLAIM_BEFORE_WORK — Tag swap before processing (daemon mode)
#   Commands: (~/.claude/directives/COMMANDS.md)
#     §CMD_REANCHOR_AFTER_RESTART — Triggered by run.sh after restart

set -euo pipefail

# Source shared utilities
source "$HOME/.claude/scripts/lib.sh"

# Export run.sh's PID as the canonical "supervisor PID"
# Both session.sh and statusline.sh use this instead of $PPID (which varies by spawn path)
export CLAUDE_SUPERVISOR_PID=$$

# Session gate: require formal session activation before tool use
# Gate hook (pre-tool-use-session-gate.sh) blocks non-whitelisted tools when this is set
export SESSION_REQUIRED=1

AGENTS_DIR="$HOME/.claude/agents"
SCRIPTS_DIR="$HOME/.claude/scripts"

# Load user config and build system prompt additions
build_system_prompt_additions() {
  local additions=""

  # Terminal link protocol
  local protocol=$("$SCRIPTS_DIR/config.sh" get terminalLinkProtocol 2>/dev/null || echo "cursor://file")
  additions+="Terminal link protocol: $protocol"
  additions+=$'\n'"CRITICAL: Read ~/.claude/directives/COMMANDS.md at session start and follow it religiously. It defines your operational discipline — logging, tagging, session management, and communication rules."

  echo "$additions"
}

SYSTEM_PROMPT_ADDITIONS=$(build_system_prompt_additions)

# Daemon mode signal handling
# When in daemon mode, SIGINT/SIGTERM sets this flag to exit cleanly
DAEMON_EXIT=0
daemon_exit_handler() {
  DAEMON_EXIT=1
  echo ""  # newline after ^C
  echo "[run.sh] Caught signal, exiting..."
}

# Parse our custom flags (--agent, --description, --focus, --monitor-tags), pass rest to Claude
# Supports both --flag value and --flag=value syntax
AGENT_NAME=""
AGENT_DESCRIPTION=""
AGENT_FOCUS=""
MONITOR_TAGS=""
REMAINING_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --agent=*)
      AGENT_NAME="${1#--agent=}"
      shift
      ;;
    --agent)
      AGENT_NAME="${2:?--agent requires a value}"
      shift 2
      ;;
    --description=*)
      AGENT_DESCRIPTION="${1#--description=}"
      shift
      ;;
    --description)
      AGENT_DESCRIPTION="${2:?--description requires a value}"
      shift 2
      ;;
    --focus=*)
      AGENT_FOCUS="${1#--focus=}"
      shift
      ;;
    --focus)
      AGENT_FOCUS="${2:?--focus requires a value}"
      shift 2
      ;;
    --monitor-tags=*)
      MONITOR_TAGS="${1#--monitor-tags=}"
      shift
      ;;
    --monitor-tags)
      MONITOR_TAGS="${2:?--monitor-tags requires a value}"
      shift 2
      ;;
    *)
      REMAINING_ARGS+=("$1")
      shift
      ;;
  esac
done

# Run engine.sh to ensure engine is up to date (unless fleet already ran it)
if [ -z "${FLEET_SETUP_DONE:-}" ]; then
  if ! "$SCRIPTS_DIR/engine.sh"; then
    echo "[run.sh] ERROR: engine.sh failed. Please run from a project directory."
    exit 1
  fi
fi

# Auto-detect fleet pane ID using fleet.sh pane-id
# Format: {session}:{window}:{pane_label} e.g., "yarik-fleet:company:SDK"
FLEET_PANE_ID=$("$SCRIPTS_DIR/fleet.sh" pane-id 2>/dev/null || echo "")
if [ -n "$FLEET_PANE_ID" ]; then
  echo "[run.sh] Fleet pane ID: $FLEET_PANE_ID"
fi

# Fleet pane ID is used locally by run.sh for find_fleet_session()
# Not exported — session.sh find and statusline.sh call fleet.sh pane-id directly

# Load agent file and append to system prompt (instead of passing --agent to Claude)
# This preserves the full toolset while still loading the agent persona
if [ -n "$AGENT_NAME" ]; then
  AGENT_FILE="$AGENTS_DIR/$AGENT_NAME.md"
  if [ -f "$AGENT_FILE" ]; then
    AGENT_CONTENT=$(cat "$AGENT_FILE")
    SYSTEM_PROMPT_ADDITIONS="$AGENT_CONTENT

$SYSTEM_PROMPT_ADDITIONS"
    echo "[run.sh] Loaded agent '$AGENT_NAME' via system prompt"
  else
    echo "[run.sh] WARNING: Agent file not found: $AGENT_FILE" >&2
  fi
fi

# Add description and focus areas to system prompt if provided
if [ -n "$AGENT_DESCRIPTION" ] || [ -n "$AGENT_FOCUS" ]; then
  AGENT_CONTEXT=""
  if [ -n "$AGENT_DESCRIPTION" ]; then
    AGENT_CONTEXT="Agent Description: $AGENT_DESCRIPTION"
  fi
  if [ -n "$AGENT_FOCUS" ]; then
    if [ -n "$AGENT_CONTEXT" ]; then
      AGENT_CONTEXT="$AGENT_CONTEXT
Focus Areas: $AGENT_FOCUS"
    else
      AGENT_CONTEXT="Focus Areas: $AGENT_FOCUS"
    fi
  fi
  SYSTEM_PROMPT_ADDITIONS="$AGENT_CONTEXT

$SYSTEM_PROMPT_ADDITIONS"
  echo "[run.sh] Added agent context (description/focus) to system prompt"
fi

# Find last Claude session for this fleet pane (if specified)
# Returns sessionId if found and PID is dead, error if PID is alive
find_fleet_session() {
  local pane_id="$1"
  local sessions_dir="$PWD/sessions"

  echo "[run.sh DEBUG] Looking for pane_id: '$pane_id'" >&2
  echo "[run.sh DEBUG] PWD: $PWD" >&2
  echo "[run.sh DEBUG] Searching: $sessions_dir" >&2

  [ -d "$sessions_dir" ] || { echo "[run.sh DEBUG] sessions_dir not found" >&2; return 1; }

  # Debug: show what we're grepping for
  echo "[run.sh DEBUG] grep pattern: \"fleetPaneId\": \"$pane_id\"" >&2

  # Find .state.json files with matching fleetPaneId
  local agent_file
  agent_file=$(grep -l "\"fleetPaneId\": \"$pane_id\"" "$sessions_dir"/*/.state.json 2>/dev/null \
    | xargs ls -t 2>/dev/null \
    | head -1)
  echo "[run.sh DEBUG] grep result: '${agent_file:-'(none)'}'" >&2

  if [ -n "$agent_file" ] && [ -f "$agent_file" ]; then
    echo "[run.sh DEBUG] Found agent file: $agent_file" >&2

    # Step 1: Check if PID is still alive — prevent conversation sharing
    local existing_pid
    existing_pid=$(state_read "$agent_file" pid "0")
    echo "[run.sh DEBUG] Existing PID: $existing_pid" >&2

    if [ "$existing_pid" != "0" ] && pid_exists "$existing_pid"; then
      # PID alive — don't resume, another Claude owns this session
      echo "[run.sh] WARNING: Session has active agent (PID $existing_pid), starting fresh" >&2
      return 1
    fi

    # Check overflowed — refuse resume if context was exhausted (S9 fix)
    local is_overflowed
    is_overflowed=$(state_read "$agent_file" overflowed "false")
    echo "[run.sh DEBUG] overflowed: $is_overflowed" >&2

    if [ "$is_overflowed" = "true" ]; then
      echo "[run.sh] Session was overflowed — cannot resume (fresh start required)" >&2
      return 1
    fi

    # Reset stale fields before returning (PID is dead, not overflowed)
    jq '.pid = 0 | .lifecycle = "resuming"' "$agent_file" > "$agent_file.tmp" \
      && mv "$agent_file.tmp" "$agent_file"

    local session_id
    session_id=$(jq -r '.sessionId // empty' "$agent_file" 2>/dev/null)
    echo "[run.sh DEBUG] sessionId in file: '${session_id:-'(empty)'}'" >&2

    if [ -n "$session_id" ]; then
      echo "$session_id"
      return 0
    else
      echo "[run.sh DEBUG] No sessionId found in agent file!" >&2
    fi
  else
    echo "[run.sh DEBUG] No matching agent file found" >&2
  fi
  return 1
}

# Check for fleet pane resume
RESUME_SESSION_ID=""
if [ -n "$FLEET_PANE_ID" ]; then
  RESUME_SESSION_ID=$(find_fleet_session "$FLEET_PANE_ID" 2>/dev/null || true)
  if [ -n "$RESUME_SESSION_ID" ]; then
    echo "[run.sh] Fleet pane '$FLEET_PANE_ID' resuming session: ${RESUME_SESSION_ID:0:8}..."
  else
    echo "[run.sh] Fleet pane '$FLEET_PANE_ID' starting fresh (no previous session)"
  fi
fi

# Build Claude args: prepend system prompt additions, add resume if available
set +u  # Allow unbound variables for array handling (REMAINING_ARGS may be empty)
CLAUDE_ARGS=("--append-system-prompt" "$SYSTEM_PROMPT_ADDITIONS")
if [ -n "$RESUME_SESSION_ID" ]; then
  CLAUDE_ARGS+=("--resume" "$RESUME_SESSION_ID")
fi
if [ ${#REMAINING_ARGS[@]} -gt 0 ]; then
  CLAUDE_ARGS+=("${REMAINING_ARGS[@]}")
fi

# Agent name already extracted during arg parsing (if provided)

# Find Claude binary
CLAUDE_BIN=$(command -v claude 2>/dev/null || true)

if [ -z "$CLAUDE_BIN" ]; then
  for p in "$HOME/.claude/local/claude" "/usr/local/bin/claude" "/opt/homebrew/bin/claude"; do
    if [ -x "$p" ]; then
      CLAUDE_BIN="$p"
      break
    fi
  done
fi

if [ -z "$CLAUDE_BIN" ]; then
  echo "ERROR: claude binary not found" >&2
  exit 1
fi

# Restart watchdog — signal-driven co-process
# Spawns a background process that waits for USR1 signal.
# On USR1: kills all children of run.sh (siblings) except itself.
# Communication chain: run.sh → WATCHDOG_PID env → Claude → session.sh restart → kill -USR1
start_watchdog() {
  (
    local run_sh_pid=$$  # $$ is always the original shell PID (run.sh)

    kill_siblings() {
      local my_pid=$BASHPID
      # Kill all children of run.sh except this watchdog
      for sibling in $(pgrep -P "$run_sh_pid" 2>/dev/null); do
        [ "$sibling" = "$my_pid" ] && continue
        kill -TERM "$sibling" 2>/dev/null || true
      done
      # Escalate to SIGKILL after 1s if any survive
      sleep 1
      for sibling in $(pgrep -P "$run_sh_pid" 2>/dev/null); do
        [ "$sibling" = "$my_pid" ] && continue
        kill -0 "$sibling" 2>/dev/null && kill -KILL "$sibling" 2>/dev/null || true
      done
    }

    local sleep_pid=""
    trap 'kill "$sleep_pid" 2>/dev/null || true; kill_siblings; exit 0' USR1

    # Wait forever — responsive to signals via sleep & wait pattern
    while true; do
      sleep 86400 &
      sleep_pid=$!
      wait $sleep_pid 2>/dev/null || true
    done
  ) &>/dev/null &
  echo $!
}

# Find .state.json ready for restart (scoped by fleet pane in fleet mode)
find_restart_agent_json() {
  local sessions_dir="$PWD/sessions"
  [ -d "$sessions_dir" ] || return 1

  find -L "$sessions_dir" -name ".state.json" -type f 2>/dev/null | while read -r f; do
    local kill_req=$(jq -r '.killRequested // false' "$f" 2>/dev/null)
    local prompt=$(jq -r '.restartPrompt // ""' "$f" 2>/dev/null)
    if [ "$kill_req" = "true" ] && [ -n "$prompt" ]; then
      # Fleet mode: scope to our pane to prevent cross-pane restart theft
      if [ -n "${FLEET_PANE_ID:-}" ]; then
        local pane=$(jq -r '.fleetPaneId // ""' "$f" 2>/dev/null)
        [ "$pane" != "$FLEET_PANE_ID" ] && continue
      fi
      echo "$f"
      return 0
    fi
  done
}

# Run Claude with all args passed through (--agent handled natively)
# Uses set +e instead of || true to avoid creating an intermediate bash shell
# (Claude must be a direct child of run.sh for process group kill to work)
run_claude() {
  set +e
  if [ ${#CLAUDE_ARGS[@]} -eq 0 ]; then
    "$CLAUDE_BIN"
  else
    "$CLAUDE_BIN" "${CLAUDE_ARGS[@]}"
  fi
  set -e
}

# ─────────────────────────────────────────────────────────────────────────────
# Daemon Mode Functions
# ─────────────────────────────────────────────────────────────────────────────

TAG_SCRIPT="$HOME/.claude/scripts/tag.sh"

# Map #needs-* tag to skill command by scanning REQUEST templates
# Returns the skill command (e.g. "/implement") or empty if unknown
# Discovery: finds TEMPLATE_*_REQUEST.md with matching tag, derives skill from dir name
daemon_tag_to_skill() {
  local tag="$1"
  local skills_dir="$HOME/.claude/skills"

  local template_file
  template_file=$(grep -rl "^\*\*Tags\*\*:.*${tag}" "$skills_dir"/*/assets/TEMPLATE_*_REQUEST.md 2>/dev/null | head -1 || true)

  if [ -n "$template_file" ]; then
    # Extract skill dir name: ~/.claude/skills/SKILL_NAME/assets/...
    local skill_dir
    skill_dir=$(echo "$template_file" | sed 's|.*/skills/\([^/]*\)/assets/.*|\1|')
    echo "/$skill_dir"
  else
    echo ""
  fi
}

# Scan sessions/ for files with monitored tags on their Tags line
# Returns TAG:PATH (e.g. "#needs-implementation:/path/to/file.md")
daemon_scan_for_work() {
  local sessions_dir="$PWD/sessions/"
  [ -d "$sessions_dir" ] || return 1

  IFS=',' read -ra TAGS <<< "$MONITOR_TAGS"
  for tag in "${TAGS[@]}"; do
    # Trim whitespace
    tag="${tag#"${tag%%[![:space:]]*}"}"
    tag="${tag%"${tag##*[![:space:]]}"}"

    local found
    found=$("$TAG_SCRIPT" find "$tag" "$sessions_dir" --tags-only 2>/dev/null | head -1 || true)

    if [ -n "$found" ] && [ -f "$found" ]; then
      echo "${tag}:${found}"
      return 0
    fi
  done

  return 1
}

# Claim a request file by swapping the specific monitored tag
daemon_claim_request() {
  local request_path="$1"
  local needs_tag="$2"

  local active_tag="${needs_tag/needs/active}"

  if "$TAG_SCRIPT" swap "$request_path" "$needs_tag" "$active_tag"; then
    echo "[run.sh] Claimed: $needs_tag -> $active_tag"
    return 0
  else
    echo "[run.sh] Failed to claim $request_path" >&2
    return 1
  fi
}

# Process a single work item: claim, map to skill, spawn Claude
daemon_process_work() {
  local needs_tag="$1"
  local request_path="$2"
  local start_time
  start_time=$(date +%s)

  # Map tag to skill
  local skill
  skill=$(daemon_tag_to_skill "$needs_tag")
  if [ -z "$skill" ]; then
    echo "[run.sh] WARNING: No skill mapping for tag '$needs_tag', skipping"
    return 1
  fi

  echo "[run.sh] Processing: $request_path ($needs_tag -> $skill)"

  # Claim the request file (swap #needs-* -> #active-*)
  if ! daemon_claim_request "$request_path" "$needs_tag"; then
    echo "[run.sh] Skipping (claim failed, another worker got it?)"
    return 1
  fi

  # Start watchdog BEFORE Claude — kills Claude on restart signal
  WATCHDOG_PID=$(start_watchdog)
  export WATCHDOG_PID

  # Spawn Claude with the mapped skill command
  # Append daemon-mode instruction so Claude exits after skill completion
  local daemon_prompt="$SYSTEM_PROMPT_ADDITIONS
DAEMON_MODE: You were spawned by the daemon (run.sh --monitor-tags). After completing the skill and deactivating the session, EXIT immediately — do NOT offer a next-skill menu or ask 'What's next?'. The daemon will automatically pick up the next tagged file."
  set +e
  "$CLAUDE_BIN" --append-system-prompt "$daemon_prompt" "$skill $request_path"
  set -e

  # Cleanup watchdog
  kill "$WATCHDOG_PID" 2>/dev/null || true
  wait "$WATCHDOG_PID" 2>/dev/null || true
  unset WATCHDOG_PID

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
  local duration_fmt="$((duration / 60))m $((duration % 60))s"

  echo "[run.sh] Completed: $request_path ($duration_fmt)"
  return 0
}

# Main daemon loop: scan for work, process, wait, repeat
daemon_main_loop() {
  local sessions_dir="$PWD/sessions"

  echo "[run.sh] Daemon mode: monitoring $MONITOR_TAGS"
  echo "[run.sh] Watching: $sessions_dir"
  echo "[run.sh] Press Ctrl+C to exit"

  # Install signal handlers for clean exit
  trap daemon_exit_handler SIGINT SIGTERM

  # Track idle state to avoid repeated messages
  local was_idle=0

  while [ "$DAEMON_EXIT" -eq 0 ]; do
    # Check for work (returns TAG:PATH)
    local scan_result
    if scan_result=$(daemon_scan_for_work); then
      was_idle=0
      local matched_tag="${scan_result%%:*}"
      local request_path="${scan_result#*:}"
      daemon_process_work "$matched_tag" "$request_path"
      # After processing, immediately check for more work
      continue
    fi

    # No work found, wait for changes
    if [ "$was_idle" -eq 0 ]; then
      echo "[run.sh] Idle. Waiting for tagged files..."
      was_idle=1
    fi

    # Use fswatch to wait for file changes
    # fswatch -1 returns on first change (or on signal)
    if command -v fswatch >/dev/null 2>&1; then
      # Run fswatch in background with latency to batch rapid changes
      # --latency=2 waits 2s after last change before reporting (reduces churn)
      (
        trap 'exit 0' TERM
        fswatch -1 --latency=2 -r "$sessions_dir" >/dev/null 2>&1
      ) &
      local fswatch_pid=$!

      # Wait for fswatch or signal
      # Poll DAEMON_EXIT flag while waiting
      while kill -0 "$fswatch_pid" 2>/dev/null; do
        if [ "$DAEMON_EXIT" -eq 1 ]; then
          kill "$fswatch_pid" 2>/dev/null || true
          break
        fi
        sleep 0.5
      done
      wait "$fswatch_pid" 2>/dev/null || true
    else
      # Fallback: simple polling without fswatch
      echo "[run.sh] WARNING: fswatch not found, using slow polling (install: brew install fswatch)"
      sleep 5
    fi
  done

  echo "[run.sh] Daemon exiting."
}

RESTART_PROMPT=""

# ─────────────────────────────────────────────────────────────────────────────
# Main Execution
# ─────────────────────────────────────────────────────────────────────────────

# If daemon mode requested, enter daemon loop and exit
if [ -n "$MONITOR_TAGS" ]; then
  daemon_main_loop
  echo "[run.sh] Goodbye."
  exit 0
fi

# Normal mode: interactive Claude
echo "[run.sh] Starting${AGENT_NAME:+ (agent: $AGENT_NAME)}${AGENT_DESCRIPTION:+ [desc: ${AGENT_DESCRIPTION:0:30}...]}..."

RESTART_AGENT_FILE=""

while true; do
  # Start watchdog BEFORE Claude — kills Claude on restart signal
  WATCHDOG_PID=$(start_watchdog)
  export WATCHDOG_PID

  if [ -n "$RESTART_PROMPT" ]; then
    clear
    echo "[run.sh] Restarting with new prompt..."
    # Get sessionId from agent file for --resume (preserves Claude conversation history)
    # Defense in depth: skip sessionId if overflowed=true OR killRequested=true
    RESTART_SESSION_ID=""
    if [ -n "$RESTART_AGENT_FILE" ] && [ -f "$RESTART_AGENT_FILE" ]; then
      restart_overflowed=$(jq -r '.overflowed // false' "$RESTART_AGENT_FILE" 2>/dev/null || echo "false")
      restart_kill=$(jq -r '.killRequested // false' "$RESTART_AGENT_FILE" 2>/dev/null || echo "false")
      if [ "$restart_overflowed" = "true" ] || [ "$restart_kill" = "true" ]; then
        echo "[run.sh] Skipping session resume (overflowed=$restart_overflowed, killRequested=$restart_kill, fresh start)"
      else
        RESTART_SESSION_ID=$(jq -r '.sessionId // empty' "$RESTART_AGENT_FILE" 2>/dev/null || true)
      fi
    fi
    # Run Claude in FOREGROUND with restart prompt + optional resume
    set +e
    if [ -n "$RESTART_SESSION_ID" ]; then
      echo "[run.sh] Resuming Claude session: ${RESTART_SESSION_ID:0:8}..."
      "$CLAUDE_BIN" --append-system-prompt "$SYSTEM_PROMPT_ADDITIONS" --resume "$RESTART_SESSION_ID" "$RESTART_PROMPT"
    else
      "$CLAUDE_BIN" --append-system-prompt "$SYSTEM_PROMPT_ADDITIONS" "$RESTART_PROMPT"
    fi
    set -e
    RESTART_PROMPT=""
    RESTART_AGENT_FILE=""
  else
    # Normal startup in FOREGROUND
    run_claude
  fi

  # Claude exited — cleanup watchdog
  kill "$WATCHDOG_PID" 2>/dev/null || true
  wait "$WATCHDOG_PID" 2>/dev/null || true
  unset WATCHDOG_PID

  # Brief settle time
  sleep 0.5

  # Check if restart was requested
  RESTART_AGENT_FILE=$(find_restart_agent_json || true)
  if [ -n "$RESTART_AGENT_FILE" ] && [ -f "$RESTART_AGENT_FILE" ]; then
    RESTART_PROMPT=$(jq -r '.restartPrompt // empty' "$RESTART_AGENT_FILE" 2>/dev/null || true)
    if [ -n "$RESTART_PROMPT" ]; then
      # Clear restart state, transition to restarting
      jq 'del(.restartPrompt) | .killRequested = false | .lifecycle = "restarting"' \
        "$RESTART_AGENT_FILE" > "$RESTART_AGENT_FILE.tmp" && mv "$RESTART_AGENT_FILE.tmp" "$RESTART_AGENT_FILE"
      echo "[run.sh] Restart requested. Looping..."
      continue
    fi
  fi

  # Normal exit
  break
done

echo "[run.sh] Goodbye."
