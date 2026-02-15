#!/bin/bash
# ~/.claude/scripts/find-sessions.sh — Session discovery for workflow engine
#
# Related:
#   Docs: (~/.claude/docs/)
#     SESSION_LIFECYCLE.md — Session directory structure
#   Commands: (~/.claude/.directives/COMMANDS.md)
#     §CMD_INGEST_CONTEXT_BEFORE_WORK — RAG session discovery
#
# Usage:
#   find-sessions.sh today                          # Sessions from today
#   find-sessions.sh yesterday                      # Sessions from yesterday
#   find-sessions.sh recent                         # Today + yesterday
#   find-sessions.sh date 2026_02_03                # Sessions from specific date
#   find-sessions.sh range 2026_02_01 2026_02_03    # Sessions in date range (inclusive)
#   find-sessions.sh topic RESEARCH                 # Sessions with topic in name (case-insensitive)
#   find-sessions.sh tag '#needs-review'            # Sessions containing a tag (delegates to tag.sh find)
#   find-sessions.sh active                         # Sessions with files modified in the last 24h
#   find-sessions.sh since '2026-02-03 14:00'       # Sessions with files modified since timestamp
#   find-sessions.sh window '2026-02-03 06:00' '2026-02-04 02:00'  # Sessions active in time window
#   find-sessions.sh all                            # All sessions
#
# Options (append to any subcommand):
#   --files          Show all files in matched sessions with timestamps
#   --debriefs       Show only debrief files (IMPLEMENTATION.md, BRAINSTORM.md, etc.)
#   --path <dir>     Search in <dir> instead of sessions/ (default)
#
# Time-aware subcommands (active, since, window) match sessions that have ANY
# file modified within the time window — not just sessions whose directory name
# matches a date. This catches overnight sessions, multi-day work, and sessions
# that span midnight.
#
# Output:
#   Default: one session directory per line
#   --files: "YYYY-MM-DD HH:MM  path/to/file" sorted by mtime
#   --debriefs: debrief file paths only
#
# Examples:
#   find-sessions.sh recent --files
#   find-sessions.sh topic ESTIMATE --debriefs
#   find-sessions.sh range 2026_01_28 2026_02_03 --files
#   find-sessions.sh tag '#needs-review'
#   find-sessions.sh active --debriefs
#   find-sessions.sh since '2026-02-03 14:00' --files
#   find-sessions.sh window '2026-02-03 06:00' '2026-02-04 02:00'

set -euo pipefail

# Source lib.sh for resolve_sessions_dir
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# --- Defaults ---
SEARCH_PATH="$(resolve_sessions_dir)/"
MODE="dirs"  # dirs | files | debriefs

# --- Helpers ---
usage() {
  sed -n '3,38p' "$0" | sed 's/^# \?//'
  exit 1
}

list_session_dirs() {
  # Takes a pattern, lists matching session dirs
  local pattern="$1"
  find "$SEARCH_PATH" -maxdepth 1 -type d -name "$pattern" 2>/dev/null | sort
}

list_files_in_dirs() {
  # Takes dirs on stdin, lists files with timestamps
  while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    find "$dir" -type f -exec stat -f "%Sm  %N" -t "%Y-%m-%d %H:%M" {} \; 2>/dev/null
  done | sort
}

list_debriefs_in_dirs() {
  # Takes dirs on stdin, lists debrief files only
  # Debriefs: top-level .md files that are NOT _LOG, _PLAN, DETAILS, REQUEST_, RESPONSE_, RESEARCH_
  while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    find "$dir" -maxdepth 1 -type f -name "*.md" \
      ! -name "*_LOG.md" \
      ! -name "*_PLAN.md" \
      ! -name "DETAILS.md" \
      ! -name "REQUEST_*" \
      ! -name "RESPONSE_*" \
      ! -name "DELEGATION_REQUEST_*" \
      ! -name "DELEGATION_RESPONSE_*" \
      ! -name "RESEARCH_REQUEST_*" \
      ! -name "RESEARCH_RESPONSE_*" \
      2>/dev/null
  done | sort
}

# Find session dirs that have ANY file modified after a given epoch timestamp.
# Args: $1 = epoch_start, $2 = epoch_end (optional, defaults to now)
# Uses temp reference files + find -newer (macOS BSD find lacks -newermt).
# This avoids per-file stat process spawning which segfaults on FUSE mounts.
dirs_with_files_in_window() {
  local epoch_start="$1"
  local epoch_end="${2:-$(date +%s)}"

  # Create temp reference files with mtime set to window bounds
  local start_ref end_ref
  start_ref=$(mktemp)
  end_ref=$(mktemp)
  trap 'rm -f "$start_ref" "$end_ref"' RETURN
  touch -t "$(date -r "$epoch_start" +%Y%m%d%H%M.%S)" "$start_ref"
  # +1s to end_ref: touch -t has second precision but file mtimes have
  # sub-second precision, so a file at 18.500s is "newer" than ref at 18.000s
  touch -t "$(date -r "$((epoch_end + 1))" +%Y%m%d%H%M.%S)" "$end_ref"

  find "$SEARCH_PATH" -maxdepth 1 -type d ! -path "$SEARCH_PATH" 2>/dev/null | while IFS= read -r dir; do
    # O(1) filesystem check: any file modified within [start, end]?
    local matches
    matches=$(find "$dir" -type f -newer "$start_ref" ! -newer "$end_ref" -print 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
      echo "$dir"
    fi
  done | sort
}

# Parse a datetime string to epoch. Accepts:
#   "2026-02-03 14:00"  or  "2026-02-03T14:00"  or  "2026-02-03"
to_epoch() {
  local input="$1"
  # Replace T with space for consistency
  input="${input//T/ }"
  # If date-only (no time), append 00:00
  if [[ ! "$input" =~ [0-9]{2}:[0-9]{2} ]]; then
    input="$input 00:00"
  fi
  date -j -f "%Y-%m-%d %H:%M" "$input" +%s 2>/dev/null
}

output_results() {
  # Takes session dirs on stdin, outputs based on MODE
  local dirs
  dirs=$(cat)
  if [[ -z "$dirs" ]]; then
    exit 0
  fi
  case "$MODE" in
    dirs)     echo "$dirs" ;;
    files)    echo "$dirs" | list_files_in_dirs ;;
    debriefs) echo "$dirs" | list_debriefs_in_dirs ;;
  esac
}

# --- Parse subcommand ---
[[ $# -eq 0 ]] && usage
SUBCMD="$1"
shift

# --- Parse remaining args ---
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --files)    MODE="files"; shift ;;
    --debriefs) MODE="debriefs"; shift ;;
    --path)     SEARCH_PATH="${2:?--path requires a directory}"; shift 2 ;;
    *)          POSITIONAL+=("$1"); shift ;;
  esac
done

# --- Execute subcommand ---
case "$SUBCMD" in
  today)
    DATE_PATTERN="$(date +%Y_%m_%d)_*"
    list_session_dirs "$DATE_PATTERN" | output_results
    ;;

  yesterday)
    DATE_PATTERN="$(date -v-1d +%Y_%m_%d)_*"
    list_session_dirs "$DATE_PATTERN" | output_results
    ;;

  recent)
    TODAY="$(date +%Y_%m_%d)_*"
    YESTERDAY="$(date -v-1d +%Y_%m_%d)_*"
    { list_session_dirs "$TODAY"; list_session_dirs "$YESTERDAY"; } | sort -u | output_results
    ;;

  date)
    DATE="${POSITIONAL[0]:?Usage: find-sessions.sh date YYYY_MM_DD}"
    list_session_dirs "${DATE}_*" | output_results
    ;;

  range)
    START="${POSITIONAL[0]:?Usage: find-sessions.sh range YYYY_MM_DD YYYY_MM_DD}"
    END="${POSITIONAL[1]:?Usage: find-sessions.sh range YYYY_MM_DD YYYY_MM_DD}"
    # Convert underscored dates to comparable integers: 2026_02_03 -> 20260203
    start_int=$(echo "$START" | tr -d '_')
    end_int=$(echo "$END" | tr -d '_')
    find "$SEARCH_PATH" -maxdepth 1 -type d 2>/dev/null | while IFS= read -r dir; do
      dirname=$(basename "$dir")
      # Extract date prefix (first 10 chars: YYYY_MM_DD)
      date_part="${dirname:0:10}"
      date_int=$(echo "$date_part" | tr -d '_')
      # Check if it's a valid 8-digit number and within range
      if [[ "$date_int" =~ ^[0-9]{8}$ ]] && [[ "$date_int" -ge "$start_int" ]] && [[ "$date_int" -le "$end_int" ]]; then
        echo "$dir"
      fi
    done | sort | output_results
    ;;

  topic)
    PATTERN="${POSITIONAL[0]:?Usage: find-sessions.sh topic KEYWORD}"
    # Case-insensitive match on directory name
    find "$SEARCH_PATH" -maxdepth 1 -type d 2>/dev/null | grep -i "$PATTERN" | sort | output_results
    ;;

  tag)
    TAG="${POSITIONAL[0]:?Usage: find-sessions.sh tag '#tag-name'}"
    # Delegate to tag.sh find, then extract unique session dirs
    FILES=$(~/.claude/scripts/tag.sh find "$TAG" "$SEARCH_PATH" 2>/dev/null || true)
    if [[ -z "$FILES" ]]; then
      exit 0
    fi
    # Extract session dir from each file path (parent of the file)
    DIRS=$(echo "$FILES" | xargs -I{} dirname {} | sort -u)
    case "$MODE" in
      dirs)     echo "$DIRS" ;;
      files)    echo "$DIRS" | list_files_in_dirs ;;
      debriefs) echo "$DIRS" | list_debriefs_in_dirs ;;
    esac
    ;;

  active)
    # Sessions with any file modified in the last 24 hours
    EPOCH_START=$(date -v-24H +%s)
    dirs_with_files_in_window "$EPOCH_START" | output_results
    ;;

  since)
    TIMESTAMP="${POSITIONAL[0]:?Usage: find-sessions.sh since 'YYYY-MM-DD HH:MM'}"
    EPOCH_START=$(to_epoch "$TIMESTAMP")
    if [[ -z "$EPOCH_START" ]]; then
      echo "ERROR: Could not parse timestamp '$TIMESTAMP'. Use 'YYYY-MM-DD HH:MM' format." >&2
      exit 1
    fi
    dirs_with_files_in_window "$EPOCH_START" | output_results
    ;;

  window)
    TS_START="${POSITIONAL[0]:?Usage: find-sessions.sh window 'YYYY-MM-DD HH:MM' 'YYYY-MM-DD HH:MM'}"
    TS_END="${POSITIONAL[1]:?Usage: find-sessions.sh window 'YYYY-MM-DD HH:MM' 'YYYY-MM-DD HH:MM'}"
    EPOCH_START=$(to_epoch "$TS_START")
    EPOCH_END=$(to_epoch "$TS_END")
    if [[ -z "$EPOCH_START" ]] || [[ -z "$EPOCH_END" ]]; then
      echo "ERROR: Could not parse timestamps. Use 'YYYY-MM-DD HH:MM' format." >&2
      exit 1
    fi
    dirs_with_files_in_window "$EPOCH_START" "$EPOCH_END" | output_results
    ;;

  all)
    find "$SEARCH_PATH" -maxdepth 1 -type d ! -path "$SEARCH_PATH" 2>/dev/null | sort | output_results
    ;;

  *)
    echo "ERROR: Unknown subcommand '$SUBCMD'" >&2
    usage
    ;;
esac
