#!/bin/bash
# ~/.claude/scripts/worker.sh — Fleet worker daemon
#
# Related:
#   Docs: (~/.claude/docs/)
#     DAEMON.md — Worker protocol, lifecycle
#     FLEET.md — Worker registration and coordination
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_CLAIM_BEFORE_WORK — Tag swap before processing
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — Fleet requirement
#   Commands: (~/.claude/.directives/COMMANDS.md)
#     §CMD_HANDOFF_TO_AGENT — Worker spawns agents
#
# Usage:
#   worker.sh --pane-id <id> --accepts <tags> [--project <path>] [--agent <name>] [--description <text>]
#
# Examples:
#   worker.sh --pane-id pool-worker-1 --accepts "#needs-delegation,#needs-implementation"
#   worker.sh --pane-id pool-worker-1 --accepts "#needs-delegation" --project ~/Projects/finch
#   worker.sh --pane-id pool-worker-1 --accepts "#needs-implementation" --agent operator --description "General-purpose worker"
#
# The worker:
#   1. Registers itself in ~/.claude/fleet/workers/{pane-id}.md
#   2. Watches for #has-work tag on its own file (via fswatch)
#   3. When work arrives: claims request, spawns run.sh, logs history
#   4. After completion: rescans for more #needs-* work before going idle
#
# Worker file format:
#   # Worker: {pane-id}
#   **Tags**: #idle | #has-work | #working
#
#   ## Identity
#   ## Accepts
#   ## Current
#   ## History

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

WORKERS_DIR="$HOME/.claude/fleet/workers"
TAG_SCRIPT="$HOME/.claude/scripts/tag.sh"
RUN_SCRIPT="$HOME/.claude/scripts/run.sh"
LOG_SCRIPT="$HOME/.claude/scripts/log.sh"

# Parsed arguments
PANE_ID=""
ACCEPTS=""
PROJECT_DIR=""
AGENT_NAME=""
AGENT_DESCRIPTION_VAL=""

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [worker:$PANE_ID] $*"
}

die() {
  echo "[worker] ERROR: $*" >&2
  exit 1
}

worker_file() {
  echo "$WORKERS_DIR/$PANE_ID.md"
}

# ─────────────────────────────────────────────────────────────────────────────
# Worker File Management
# ─────────────────────────────────────────────────────────────────────────────

create_worker_file() {
  local file
  file=$(worker_file)

  # Build accepts list as markdown bullets
  local accepts_md=""
  IFS=',' read -ra TAGS <<< "$ACCEPTS"
  for tag in "${TAGS[@]}"; do
    accepts_md+="*   \`$tag\`"$'\n'
  done

  cat > "$file" << EOF
# Worker: $PANE_ID
**Tags**: #idle

## Identity
*   **PID**: $$
*   **Pane**: $PANE_ID
*   **Started**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
*   **Project**: ${PROJECT_DIR:-$(pwd)}

## Accepts
$accepts_md
## Current
(none)

## History
EOF

  log "Registered: $file"
}

cleanup_worker_file() {
  local file
  file=$(worker_file)
  if [ -f "$file" ]; then
    rm -f "$file"
    log "Unregistered: $file"
  fi
}

# Update ## Current section
set_current() {
  local request_path="$1"
  local file
  file=$(worker_file)

  # Replace the line after "## Current" with the request path
  sed -i '' '/^## Current$/,/^## /{
    /^## Current$/!{
      /^## /!{
        s|.*|'"$request_path"'|
      }
    }
  }' "$file"
}

clear_current() {
  set_current "(none)"
}

# Get current request path from ## Current section
get_current() {
  local file
  file=$(worker_file)

  # Extract line between ## Current and ## History
  sed -n '/^## Current$/,/^## History$/p' "$file" | sed '1d;$d' | head -1
}

# Append to ## History section
log_history() {
  local request_path="$1"
  local duration="$2"
  local outcome="$3"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local request_name
  request_name=$(basename "$request_path" .md)

  local file
  file=$(worker_file)

  # Append history entry
  "$LOG_SCRIPT" "$file" << EOF

### [$timestamp] $request_name
*   **Request**: \`$request_path\`
*   **Duration**: $duration
*   **Outcome**: \`$outcome\`
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# Work Processing
# ─────────────────────────────────────────────────────────────────────────────

# Claim request file: swap #needs-* -> #active-*
claim_request() {
  local request_path="$1"

  # Find which #needs-* tag is on the file
  local needs_tag
  needs_tag=$(grep -o '#needs-[a-z]*' "$request_path" 2>/dev/null | head -1 || true)

  if [ -z "$needs_tag" ]; then
    log "WARNING: No #needs-* tag found on $request_path"
    return 1
  fi

  local active_tag="${needs_tag/needs/active}"

  if "$TAG_SCRIPT" swap "$request_path" "$needs_tag" "$active_tag"; then
    log "Claimed: $needs_tag -> $active_tag"
    return 0
  else
    log "Failed to claim $request_path"
    return 1
  fi
}

# Process a single request
process_request() {
  local request_path="$1"
  local start_time
  start_time=$(date +%s)

  log "Processing: $request_path"

  # Swap #has-work -> #working on worker file
  "$TAG_SCRIPT" swap "$(worker_file)" '#has-work' '#working'

  # Claim the request file
  if ! claim_request "$request_path"; then
    # Failed to claim - someone else got it, go back to idle
    "$TAG_SCRIPT" swap "$(worker_file)" '#working' '#idle'
    clear_current
    return 1
  fi

  # Spawn run.sh with the request
  # Pass the request file as an argument - run.sh will invoke appropriate skill
  local project_arg=""
  if [ -n "$PROJECT_DIR" ]; then
    project_arg="--project $PROJECT_DIR"
  fi

  # Run Claude with the request file as the prompt
  # The request file should contain instructions for what to do
  cd "${PROJECT_DIR:-$(pwd)}"
  local run_args=(--fleet-pane "$PANE_ID")
  [ -n "$AGENT_NAME" ] && run_args+=(--agent "$AGENT_NAME")
  [ -n "$AGENT_DESCRIPTION_VAL" ] && run_args+=(--description "$AGENT_DESCRIPTION_VAL")
  "$RUN_SCRIPT" "${run_args[@]}" "/dispatch $request_path" || true

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
  local duration_fmt
  duration_fmt="$((duration / 60))m $((duration % 60))s"

  # Determine outcome by checking final tag state
  local outcome
  if grep -q '#done-' "$request_path" 2>/dev/null; then
    outcome=$(grep -o '#done-[a-z]*' "$request_path" | head -1)
  elif grep -q '#active-' "$request_path" 2>/dev/null; then
    outcome="incomplete (still #active)"
  else
    outcome="unknown"
  fi

  # Log to history
  log_history "$request_path" "$duration_fmt" "$outcome"

  log "Completed: $request_path ($duration_fmt)"
  return 0
}

# Rescan for unclaimed work matching our accepts tags
rescan_for_work() {
  local sessions_dir="${PROJECT_DIR:-$(pwd)}/sessions"

  IFS=',' read -ra TAGS <<< "$ACCEPTS"
  for tag in "${TAGS[@]}"; do
    # Find files with this tag
    local found
    found=$("$TAG_SCRIPT" find "$tag" "$sessions_dir" 2>/dev/null | head -1 || true)

    if [ -n "$found" ] && [ -f "$found" ]; then
      log "Rescan found: $found ($tag)"
      echo "$found"
      return 0
    fi
  done

  return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Loop
# ─────────────────────────────────────────────────────────────────────────────

wait_for_work() {
  local file
  file=$(worker_file)

  log "Waiting for work (fswatch on $file)..."

  # Watch for changes to our worker file
  # When #has-work tag is added, fswatch will trigger
  fswatch -1 "$file" >/dev/null 2>&1

  # Check if we now have #has-work tag
  if grep -q '^\*\*Tags\*\*:.*#has-work' "$file" 2>/dev/null; then
    return 0
  fi

  # Spurious wake, no work
  return 1
}

main_loop() {
  log "Starting main loop..."

  while true; do
    # Wait for work via fswatch
    if wait_for_work; then
      # Get request path from ## Current
      local request_path
      request_path=$(get_current)

      if [ "$request_path" != "(none)" ] && [ -n "$request_path" ] && [ -f "$request_path" ]; then
        process_request "$request_path"
      else
        log "WARNING: #has-work but no valid request in Current"
        "$TAG_SCRIPT" swap "$(worker_file)" '#has-work' '#idle'
      fi

      # Clear current
      clear_current

      # Rescan for more work before going idle
      local next_request
      if next_request=$(rescan_for_work); then
        set_current "$next_request"
        "$TAG_SCRIPT" swap "$(worker_file)" '#working' '#has-work'
        continue  # Process immediately without waiting
      fi

      # No more work, go idle
      "$TAG_SCRIPT" swap "$(worker_file)" '#working' '#idle'
    fi
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pane-id)
        PANE_ID="${2:?--pane-id requires a value}"
        shift 2
        ;;
      --accepts)
        ACCEPTS="${2:?--accepts requires a value}"
        shift 2
        ;;
      --project)
        PROJECT_DIR="${2:?--project requires a value}"
        shift 2
        ;;
      --agent)
        AGENT_NAME="${2:?--agent requires a value}"
        shift 2
        ;;
      --description)
        AGENT_DESCRIPTION_VAL="${2:?--description requires a value}"
        shift 2
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  [ -n "$PANE_ID" ] || die "--pane-id is required"
  [ -n "$ACCEPTS" ] || die "--accepts is required"
}

main() {
  parse_args "$@"

  # Export for child processes
  export FLEET_PANE_ID="$PANE_ID"

  # Ensure workers directory exists
  mkdir -p "$WORKERS_DIR"

  # Check dependencies
  command -v fswatch >/dev/null 2>&1 || die "fswatch not found. Install: brew install fswatch"
  [ -x "$TAG_SCRIPT" ] || die "tag.sh not found at $TAG_SCRIPT"
  [ -x "$RUN_SCRIPT" ] || die "run.sh not found at $RUN_SCRIPT"

  # Register worker file
  create_worker_file

  # Cleanup on exit
  trap cleanup_worker_file EXIT SIGTERM SIGINT

  # Enter main loop
  main_loop
}

main "$@"
