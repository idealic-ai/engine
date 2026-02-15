#!/bin/bash
# ~/.claude/tools/dispatch-daemon/dispatch-daemon.sh — Automatic tag processor
#
# Usage:
#   dispatch-daemon.sh start [--project <path>]   # Start daemon (default: cwd)
#   dispatch-daemon.sh stop                        # Stop daemon
#   dispatch-daemon.sh status                      # Check if running
#
# The daemon watches sessions/ for #needs-* tags and routes to fleet workers.
# Workers self-register in ~/.claude/fleet/workers/{id}.md with their accepted tags.
#
# Related:
#   Docs: (~/.claude/docs/)
#     DAEMON.md — Dispatch protocol, tag routing
#     FLEET.md — Worker coordination
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_CLAIM_BEFORE_WORK — Tag swap before routing to worker
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — Fleet dependency
#   Tags: (~/.claude/.directives/SIGILS.md)
#     §TAG_DISPATCH — Tag-to-skill routing table
#
# Dependencies:
#   - fswatch (brew install fswatch)
#   - ~/.claude/scripts/tag.sh (tag operations)
#
# Invariants:
#   - ¶INV_DAEMON_STATELESS: No state beyond tags. Workers own their status.
#   - ¶INV_CLAIM_BEFORE_WORK: Worker swaps #needs-X -> #active-X before processing.

set -euo pipefail

# Source shared utilities
source "$HOME/.claude/scripts/lib.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

PIDFILE="/tmp/dispatch-daemon.pid"
LOGFILE="/tmp/dispatch-daemon.log"
TAG_SCRIPT="$HOME/.claude/scripts/tag.sh"
WORKERS_DIR="$HOME/.claude/fleet/workers"
TAGS_FILE="$HOME/.claude/.directives/SIGILS.md"

# Debounce: ignore rapid-fire events on same file (seconds)
DEBOUNCE_SECS=2
declare -A LAST_PROCESSED

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

die() {
  log "ERROR: $*"
  exit 1
}

check_deps() {
  command -v fswatch >/dev/null 2>&1 || die "fswatch not found. Install: brew install fswatch"
  [ -x "$TAG_SCRIPT" ] || die "tag.sh not found at $TAG_SCRIPT"
  [ -f "$TAGS_FILE" ] || die "SIGILS.md not found at $TAGS_FILE"
}

# Parse §TAG_DISPATCH table from SIGILS.md to get tag->skill mapping
# Returns: tag|skill (pipe-separated, one per line)
parse_dispatch_table() {
  # Extract table rows from §TAG_DISPATCH section
  # Format: | `#needs-xxx` | `/skill` | ... |
  awk '
    /^## §TAG_DISPATCH/,/^---$|^## [^§]/ {
      # Match table data rows (skip header row with "Tag")
      if (/^\|.*#needs-.*\//) {
        # Extract tag: find #needs-[word]
        if (match($0, /#needs-[a-z]+/)) {
          tag = substr($0, RSTART, RLENGTH)
          # Extract skill: find /word after the tag
          rest = substr($0, RSTART + RLENGTH)
          if (match(rest, /\/[a-z-]+/)) {
            skill = substr(rest, RSTART, RLENGTH)
            print tag "|" skill
          }
        }
      }
    }
  ' "$TAGS_FILE"
}

# Get skill for a tag (returns empty if not found)
get_skill_for_tag() {
  local tag="$1"
  parse_dispatch_table | grep "^${tag}|" | cut -d'|' -f2 || true
}

# ─────────────────────────────────────────────────────────────────────────────
# Fleet Worker Routing
# ─────────────────────────────────────────────────────────────────────────────

# Find an idle worker that accepts the given tag
# Returns: path to worker file, or empty if none found
find_worker_for_tag() {
  local tag="$1"

  # No workers directory? No workers.
  [ -d "$WORKERS_DIR" ] || return 1

  for worker_file in "$WORKERS_DIR"/*.md; do
    [ -f "$worker_file" ] || continue

    # Check if worker is idle (has #idle tag)
    if ! grep -q '^\*\*Tags\*\*:.*#idle' "$worker_file" 2>/dev/null; then
      continue
    fi

    # Check if worker accepts this tag (in ## Accepts section)
    # The tag is listed as `#needs-xxx` in the Accepts section
    if grep -q "\`$tag\`" "$worker_file" 2>/dev/null; then
      echo "$worker_file"
      return 0
    fi
  done

  return 1
}

# Assign work to a worker
# - Writes request path to ## Current section
# - Swaps #idle -> #has-work
assign_work_to_worker() {
  local worker_file="$1"
  local request_file="$2"

  log "Assigning to worker: $(basename "$worker_file" .md)"

  # Update ## Current section with request path
  # Replace the line after "## Current" with the request path
  sed -i '' '/^## Current$/,/^## /{
    /^## Current$/!{
      /^## /!{
        s|.*|'"$request_file"'|
      }
    }
  }' "$worker_file"

  # Swap #idle -> #has-work to wake the worker
  if "$TAG_SCRIPT" swap "$worker_file" '#idle' '#has-work'; then
    log "Worker notified: #idle -> #has-work"
    return 0
  else
    log "Failed to notify worker"
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# File Processing
# ─────────────────────────────────────────────────────────────────────────────

# Process a file that may contain #needs-* tags
process_file() {
  local file="$1"

  # Skip if not a markdown file
  [[ "$file" == *.md ]] || return 0

  # Skip if file doesn't exist (deleted)
  [ -f "$file" ] || return 0

  # Skip worker files (prevent recursive triggering)
  [[ "$file" == "$WORKERS_DIR"/* ]] && return 0

  # Debounce: skip if processed recently
  local now=$(date +%s)
  local last="${LAST_PROCESSED[$file]:-0}"
  if (( now - last < DEBOUNCE_SECS )); then
    return 0
  fi
  LAST_PROCESSED[$file]=$now

  # Find #needs-* tags in this file (Tags line or inline, excluding backtick-escaped)
  # Only look for tags that have dispatch mappings
  local mappings
  mappings=$(parse_dispatch_table)

  while IFS='|' read -r tag skill; do
    [ -z "$tag" ] && continue

    # Check if this tag exists in the file (bare, not escaped)
    # Tags line check
    if grep -q "^\*\*Tags\*\*:.*${tag}" "$file" 2>/dev/null; then
      # Check it's not already #active-* or #done-*
      local active_tag="${tag/needs/active}"
      local done_tag="${tag/needs/done}"

      if grep -q "$active_tag\|$done_tag" "$file" 2>/dev/null; then
        # Already claimed or done, skip
        continue
      fi

      log "Detected $tag in $file"

      # Try to find an idle worker for this tag
      local worker_file
      if worker_file=$(find_worker_for_tag "$tag"); then
        # Route to worker - worker will claim the request
        if assign_work_to_worker "$worker_file" "$file"; then
          log "Routed to $(basename "$worker_file" .md)"
        fi
      else
        # No worker available - tag stays #needs-*, workers will find via rescan
        log "No idle worker for $tag — will be picked up by worker rescan"
      fi
    fi
  done <<< "$mappings"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Loop
# ─────────────────────────────────────────────────────────────────────────────

start_daemon() {
  local project_dir="${1:-$(pwd)}"
  PROJECT_DIR="$project_dir"
  export PROJECT_DIR

  local sessions_dir="$project_dir/sessions"

  [ -d "$sessions_dir" ] || die "sessions/ directory not found at $sessions_dir"

  # Check if already running
  if [ -f "$PIDFILE" ] && pid_exists "$(cat "$PIDFILE")"; then
    die "Daemon already running (PID: $(cat "$PIDFILE"))"
  fi

  check_deps

  # Ensure workers directory exists
  mkdir -p "$WORKERS_DIR"

  # Write PID
  echo $$ > "$PIDFILE"

  log "Starting dispatch daemon..."
  log "Project: $project_dir"
  log "Sessions: $sessions_dir"
  log "Workers: $WORKERS_DIR"
  log "PID: $$"

  # Initial scan: process existing #needs-* tags
  log "Initial scan for existing tags..."
  find -L "$sessions_dir" -name "*.md" -type f 2>/dev/null | while read -r file; do
    process_file "$file"
  done

  # Watch for changes
  log "Starting fswatch on $sessions_dir..."

  # fswatch options:
  #   -r: recursive
  #   -e: exclude pattern
  #   --event: filter to specific events
  #   -0: null-separated output (safer for filenames with spaces)
  fswatch -r -0 \
    --event Created --event Updated --event Renamed \
    -e '\.git' -e '\.DS_Store' -e '\.agent\.json' \
    "$sessions_dir" | while IFS= read -r -d '' file; do
    process_file "$file"
  done
}

stop_daemon() {
  if [ -f "$PIDFILE" ]; then
    local pid
    pid=$(cat "$PIDFILE")
    if pid_exists "$pid"; then
      log "Stopping daemon (PID: $pid)..."
      kill "$pid"
      rm -f "$PIDFILE"
      log "Daemon stopped."
    else
      log "Daemon not running (stale PID file)."
      rm -f "$PIDFILE"
    fi
  else
    log "Daemon not running (no PID file)."
  fi
}

status_daemon() {
  if [ -f "$PIDFILE" ]; then
    local pid
    pid=$(cat "$PIDFILE")
    if pid_exists "$pid"; then
      echo "Daemon is running (PID: $pid)"
      echo "Log: $LOGFILE"
      echo "Workers: $WORKERS_DIR"
      echo ""
      echo "Registered workers:"
      ls -1 "$WORKERS_DIR"/*.md 2>/dev/null | while read -r f; do
        local name=$(basename "$f" .md)
        local status=$(grep -o '#idle\|#has-work\|#working' "$f" 2>/dev/null | head -1 || echo "unknown")
        echo "  $name: $status"
      done
      echo ""
      echo "Recent log entries:"
      tail -10 "$LOGFILE" 2>/dev/null || echo "(no log yet)"
      return 0
    else
      echo "Daemon is not running (stale PID file)"
      rm -f "$PIDFILE"
      return 1
    fi
  else
    echo "Daemon is not running"
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

case "${1:-}" in
  start)
    shift
    project=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --project) project="$2"; shift 2 ;;
        *) die "Unknown option: $1" ;;
      esac
    done
    start_daemon "$project"
    ;;
  stop)
    stop_daemon
    ;;
  status)
    status_daemon
    ;;
  *)
    echo "Usage: dispatch-daemon.sh {start|stop|status} [--project <path>]"
    echo ""
    echo "Commands:"
    echo "  start   Start the daemon (watches sessions/ for #needs-* tags)"
    echo "  stop    Stop the daemon"
    echo "  status  Check if daemon is running"
    echo ""
    echo "Options:"
    echo "  --project <path>  Project directory (default: current directory)"
    echo ""
    echo "Workers self-register in ~/.claude/fleet/workers/{id}.md"
    echo "Start workers with: ~/.claude/scripts/worker.sh --pane-id <id> --accepts <tags>"
    exit 1
    ;;
esac
