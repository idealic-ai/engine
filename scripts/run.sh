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
#   --workspace PATH          Set WORKSPACE env var for workspace-scoped sessions
#
# Examples:
#   ~/.claude/scripts/run.sh                      # Plain Claude
#   ~/.claude/scripts/run.sh --agent operator     # Claude with operator agent
#   ~/.claude/scripts/run.sh --agent builder      # Claude with builder agent
#   ~/.claude/scripts/run.sh --agent researcher --description "Deep research" --focus "Insurance,Claims"
#   ~/.claude/scripts/run.sh --monitor-tags '#delegated-implementation,#delegated-chores'  # Daemon mode
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
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — Fleet auto-detection
#     ¶INV_CLAIM_BEFORE_WORK — Tag swap before processing (daemon mode)
#   Commands: (~/.claude/.directives/COMMANDS.md)
#     §CMD_RECOVER_SESSION — Triggered by run.sh after restart

set -euo pipefail

# Source shared utilities
source "$HOME/.claude/scripts/lib.sh"

# Export run.sh's PID as the canonical "supervisor PID"
# Both session.sh and statusline.sh use this instead of $PPID (which varies by spawn path)
export CLAUDE_SUPERVISOR_PID=$$

# Snapshot current account for race condition prevention in account rotation
# stop-notify.sh compares this to the active account — if they differ, another pane already rotated
CLAUDE_ACCOUNT=$(jq -r '.activeAccount // ""' "$HOME/.claude/accounts/state.json" 2>/dev/null || echo "")
export CLAUDE_ACCOUNT
rotation_log "LAUNCH" "account=$CLAUDE_ACCOUNT pid=$$"

# Session gate: require formal session activation before tool use
# Gate hook (pre-tool-use-session-gate.sh) blocks non-whitelisted tools when this is set
export SESSION_REQUIRED=1

# Context management: disable auto-compaction, use full context window
export DISABLE_AUTO_COMPACT=1
export DISABLE_CLEAR=1
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=100
export CLAUDE_CODE_BLOCKING_LIMIT_OVERRIDE=197000
export DISABLE_COMPACT=1

AGENTS_DIR="$HOME/.claude/agents"
SCRIPTS_DIR="$HOME/.claude/scripts"

# Load user config and build system prompt additions
build_system_prompt_additions() {
  local additions=""

  # Terminal link protocol
  local protocol=$("$SCRIPTS_DIR/config.sh" get terminalLinkProtocol 2>/dev/null || echo "cursor://file")
  additions+="Terminal link protocol: $protocol"
  additions+=$'\n'"CRITICAL: Read ~/.claude/.directives/COMMANDS.md at session start and follow it religiously. It defines your operational discipline — logging, tagging, session management, and communication rules."

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
WORKSPACE_ARG=""
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
    --workspace=*)
      WORKSPACE_ARG="${1#--workspace=}"
      shift
      ;;
    --workspace)
      WORKSPACE_ARG="${2:?--workspace requires a value}"
      shift 2
      ;;
    *)
      REMAINING_ARGS+=("$1")
      shift
      ;;
  esac
done

# Export WORKSPACE env var if --workspace flag was provided
if [ -n "$WORKSPACE_ARG" ]; then
  export WORKSPACE="$WORKSPACE_ARG"
  echo "[run.sh] Workspace: $WORKSPACE"
fi

# Setup is handled by engine CLI (auto-setup on first run).
# run.sh no longer invokes engine.sh directly — callers should use `engine` entrypoint.

# Auto-detect fleet pane ID using fleet.sh pane-id
# Format: {session}:{window}:{pane_label} e.g., "yarik-fleet:company:SDK"
FLEET_PANE_ID=$("$SCRIPTS_DIR/fleet.sh" pane-id 2>/dev/null || echo "")
if [ -n "$FLEET_PANE_ID" ]; then
  echo "[run.sh] Fleet pane ID: $FLEET_PANE_ID"
fi

# Fleet pane ID is used locally by run.sh for find_fleet_session()
# Not exported — session.sh find and statusline.sh call fleet.sh pane-id directly

# Export FLEET_* env vars from tmux @pane_* options (capability-based identity)
# await-next and other fleet tools read these to determine what work to accept
if [ -n "$FLEET_PANE_ID" ] && [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
  _read_pane_opt() { tmux display -p -t "$TMUX_PANE" "#{$1}" 2>/dev/null || true; }
  _pane_label=$(_read_pane_opt "@pane_label")
  _window_name=$(tmux display -p -t "$TMUX_PANE" "#{window_name}" 2>/dev/null || true)
  if [ -n "$_pane_label" ] && [ -n "$_window_name" ]; then
    export FLEET_PANE="${_window_name}:${_pane_label}"
  fi
  _pane_parent=$(_read_pane_opt "@pane_parent")
  [ -n "$_pane_parent" ] && export FLEET_PARENT="$_pane_parent"
  _pane_claims=$(_read_pane_opt "@pane_claims")
  [ -n "$_pane_claims" ] && export FLEET_CLAIMS="$_pane_claims"
  _pane_targeted=$(_read_pane_opt "@pane_targeted_claims")
  [ -n "$_pane_targeted" ] && export FLEET_TARGETED_CLAIMS="$_pane_targeted"
  _pane_manages=$(_read_pane_opt "@pane_manages")
  [ -n "$_pane_manages" ] && export FLEET_MANAGES="$_pane_manages"
  if [ -n "${FLEET_PANE:-}" ]; then
    echo "[run.sh] Fleet env: FLEET_PANE=$FLEET_PANE"
  fi
  unset _read_pane_opt _pane_label _window_name _pane_parent _pane_claims _pane_targeted _pane_manages
fi

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
    jq 'del(.pid) | .lifecycle = "resuming"' "$agent_file" > "$agent_file.tmp" \
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

# Check for fleet pane resume (bypass with FRESH_START=1)
RESUME_SESSION_ID=""
if [ "${FRESH_START:-}" = "1" ]; then
  echo "[run.sh] FRESH_START=1 — skipping session restoration"
elif [ -n "$FLEET_PANE_ID" ]; then
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

# Detect context exhaustion from JSONL tail and trigger session restart
# This is the defense-in-depth path — runs unconditionally after Claude exits.
# The Stop hook (stop-notify.sh) also checks, but may not fire on context exhaustion.
detect_context_exhaustion() {
  # Find the current conversation JSONL (same logic as stop-notify.sh)
  local project_slug=$(echo "$PWD" | sed 's|/|-|g')
  local projects_dir="$HOME/.claude/projects/$project_slug"
  local jsonl_file=""

  if [ -d "$projects_dir" ]; then
    jsonl_file=$(ls -t "$projects_dir"/*.jsonl 2>/dev/null | head -1) || true
  fi

  [ -n "$jsonl_file" ] && [ -f "$jsonl_file" ] || return 0

  local tail_content
  tail_content=$(tail -50 "$jsonl_file" 2>/dev/null || true)

  if echo "$tail_content" | grep -qiE 'prompt is too long|conversation is too long|context_length_exceeded'; then
    echo "[run.sh] Context exhaustion detected in JSONL"
    # Find active session and trigger restart
    local session_dir
    session_dir=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
    if [ -n "$session_dir" ]; then
      echo "[run.sh] Triggering session restart for $session_dir"
      "$HOME/.claude/scripts/session.sh" restart "$session_dir" 2>/dev/null || true
    else
      echo "[run.sh] Context exhaustion detected but no active session found" >&2
    fi
  fi
}

# Find .state.json ready for restart (scoped by fleet pane in fleet mode)
find_restart_agent_json() {
  local sessions_dir="$PWD/sessions"
  [ -d "$sessions_dir" ] || return 1

  find -L "$sessions_dir" -name ".state.json" -type f 2>/dev/null | while read -r f; do
    local kill_req=$(jq -r '.killRequested // false' "$f" 2>/dev/null)
    if [ "$kill_req" = "true" ]; then
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
# Returns all TAG:PATH pairs (one per line), grouped by tag type
# With debounce: after first match, waits DAEMON_DEBOUNCE_SEC for batch writes to settle
DAEMON_DEBOUNCE_SEC=3

daemon_scan_for_work() {
  local sessions_dir="$PWD/sessions/"
  [ -d "$sessions_dir" ] || return 1

  local results=""
  IFS=',' read -ra TAGS <<< "$MONITOR_TAGS"
  for tag in "${TAGS[@]}"; do
    # Trim whitespace
    tag="${tag#"${tag%%[![:space:]]*}"}"
    tag="${tag%"${tag##*[![:space:]]}"}"

    local found_files
    found_files=$("$TAG_SCRIPT" find "$tag" "$sessions_dir" --tags-only 2>/dev/null || true)

    while IFS= read -r found; do
      if [ -n "$found" ] && [ -f "$found" ]; then
        results+="${tag}:${found}"$'\n'
      fi
    done <<< "$found_files"
  done

  # Trim trailing newline
  results="${results%$'\n'}"

  if [ -z "$results" ]; then
    return 1
  fi

  echo "$results"
  return 0
}

# Scan with debounce: initial scan, wait, re-scan to collect batch writes
daemon_scan_with_debounce() {
  local initial_results
  initial_results=$(daemon_scan_for_work) || return 1

  echo "[run.sh] Found work, debouncing ${DAEMON_DEBOUNCE_SEC}s for batch writes..." >&2
  sleep "$DAEMON_DEBOUNCE_SEC"

  # Re-scan after debounce to catch any additional tags written during the window
  daemon_scan_for_work || echo "$initial_results"
}

# Process a batch of delegated work items: spawn /delegation-claim to handle claiming + routing
# The daemon no longer claims work directly — /delegation-claim handles #delegated-X → #claimed-X
daemon_process_work() {
  local scan_results="$1"
  local start_time
  start_time=$(date +%s)

  # Count items
  local item_count
  item_count=$(echo "$scan_results" | wc -l | tr -d ' ')

  echo "[run.sh] Processing batch: $item_count delegated item(s)"

  # Start watchdog BEFORE Claude — kills Claude on restart signal
  WATCHDOG_PID=$(start_watchdog)
  export WATCHDOG_PID

  # Spawn Claude with /delegation-claim — it handles scanning, grouping, claiming, and routing
  # /delegation-claim will re-scan for #delegated-* tags and present them for worker approval
  local daemon_prompt="$SYSTEM_PROMPT_ADDITIONS
DAEMON_MODE: You were spawned by the daemon (run.sh --monitor-tags). Run /delegation-claim to pick up delegated work items. After /delegation-claim routes you to a target skill and you complete it, EXIT immediately — do NOT offer a next-skill menu or ask 'What's next?'. The daemon will automatically pick up the next batch of delegated items."
  set +e
  "$CLAUDE_BIN" --append-system-prompt "$daemon_prompt" "/delegation-claim"
  set -e

  # Cleanup watchdog
  kill "$WATCHDOG_PID" 2>/dev/null || true
  wait "$WATCHDOG_PID" 2>/dev/null || true
  unset WATCHDOG_PID

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
  local duration_fmt="$((duration / 60))m $((duration % 60))s"

  echo "[run.sh] Batch completed ($duration_fmt)"
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
    # Check for work (returns TAG:PATH pairs, debounced for batch collection)
    local scan_results
    if scan_results=$(daemon_scan_with_debounce); then
      was_idle=0
      daemon_process_work "$scan_results"
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

  # Track start time for stale-session detection
  local_start_time=$(date +%s)

  if [ -n "$RESTART_PROMPT" ]; then
    clear
    echo "[run.sh] Restarting with new prompt..."
    # Get sessionId from agent file for --resume (preserves Claude conversation history)
    # Defense in depth: skip sessionId if overflowed=true OR killRequested=true
    RESTART_SESSION_ID=""
    if [ "${FRESH_START:-}" = "1" ]; then
      echo "[run.sh] FRESH_START=1 — skipping restart session resume"
    elif [ -n "$RESTART_AGENT_FILE" ] && [ -f "$RESTART_AGENT_FILE" ]; then
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

  # Stale session detection: if Claude exited within 5 seconds and we were resuming,
  # the session ID is likely invalid ("No conversation found"). Strip --resume and retry.
  # Covers both fleet-resume (RESUME_SESSION_ID) and restart-resume (RESTART_SESSION_ID).
  local_end_time=$(date +%s)
  local_duration=$((local_end_time - local_start_time))
  if [ "$local_duration" -le 5 ] && { [ -n "${RESUME_SESSION_ID:-}" ] || [ -n "${RESTART_SESSION_ID:-}" ]; }; then
    echo "[run.sh] Claude exited in ${local_duration}s with --resume — session likely stale. Retrying fresh..."
    RESUME_SESSION_ID=""
    RESTART_SESSION_ID=""
    RESTART_PROMPT=""
    RESTART_AGENT_FILE=""
    CLAUDE_ARGS=("--append-system-prompt" "$SYSTEM_PROMPT_ADDITIONS")
    if [ ${#REMAINING_ARGS[@]} -gt 0 ]; then
      CLAUDE_ARGS+=("${REMAINING_ARGS[@]}")
    fi
    # Cleanup watchdog before retry
    kill "$WATCHDOG_PID" 2>/dev/null || true
    wait "$WATCHDOG_PID" 2>/dev/null || true
    unset WATCHDOG_PID
    continue
  fi

  # Claude exited — cleanup watchdog
  kill "$WATCHDOG_PID" 2>/dev/null || true
  wait "$WATCHDOG_PID" 2>/dev/null || true
  unset WATCHDOG_PID

  # Brief settle time
  sleep 0.5

  # ─── Context exhaustion detection (defense-in-depth) ───────────────────
  # The Stop hook (stop-notify.sh) also checks for this, but Stop may not
  # fire on context exhaustion (it fires on "agent stops", not "agent exits").
  # This check runs unconditionally after Claude exits — most reliable path.
  detect_context_exhaustion

  # Check if restart was requested
  RESTART_AGENT_FILE=$(find_restart_agent_json || true)
  if [ -n "$RESTART_AGENT_FILE" ] && [ -f "$RESTART_AGENT_FILE" ]; then
    RESTART_PROMPT=$(jq -r '.restartPrompt // empty' "$RESTART_AGENT_FILE" 2>/dev/null || true)
    # Clear restart state, transition to restarting
    jq 'del(.restartPrompt) | .killRequested = false | .lifecycle = "restarting"' \
      "$RESTART_AGENT_FILE" > "$RESTART_AGENT_FILE.tmp" && mv "$RESTART_AGENT_FILE.tmp" "$RESTART_AGENT_FILE"
    if [ -n "$RESTART_PROMPT" ]; then
      echo "[run.sh] Restart requested with prompt. Looping..."
    else
      # killRequested but no prompt — "done and clear" case. Restart fresh.
      echo "[run.sh] Clear requested. Restarting fresh..."
    fi
    continue
  fi

  # Normal exit
  break
done

echo "[run.sh] Goodbye."
