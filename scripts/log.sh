#!/bin/bash
# ~/.claude/scripts/log.sh — Append-only logging for workflow engine
#
# Related:
#   Docs: (~/.claude/docs/)
#     SESSION_LIFECYCLE.md — Log file lifecycle
#   Commands: (~/.claude/directives/COMMANDS.md)
#     §CMD_APPEND_LOG_VIA_BASH_USING_TEMPLATE — Primary usage pattern
#     §CMD_THINK_IN_LOG — Reasoning documentation
#     §CMD_LOG_TO_DETAILS — Q&A logging
#
# Usage:
#   ~/.claude/scripts/log.sh <file> <<'EOF'
#   ## [2026-02-03 10:00:00] Header
#   *   **Key**: Value
#   EOF
#
#   ~/.claude/scripts/log.sh --overwrite <file> <<'EOF'
#   # Full file content here
#   EOF
#
# Behavior:
#   - Creates parent directories if they don't exist
#   - Default: Prepends a blank line and appends stdin to file
#   - With --overwrite: Replaces file content entirely (no blank line)
#   - Produces no output (silent operation)

set -euo pipefail

OVERWRITE=false
if [ "${1:-}" = "--overwrite" ]; then
  OVERWRITE=true
  shift
fi

FILE="${1:?Usage: log.sh [--overwrite] <file> (reads content from stdin)}"

mkdir -p "$(dirname "$FILE")"

# Read all stdin into variable
CONTENT=$(cat)

if [ "$OVERWRITE" = true ]; then
  # Overwrite mode: replace file entirely, no timestamp injection
  printf '%s\n' "$CONTENT" > "$FILE"
else
  # Append mode: auto-inject timestamp into first ## heading

  # Check that content has a ## heading
  if ! printf '%s\n' "$CONTENT" | grep -q '^## '; then
    echo "ERROR: log.sh append mode requires a ## heading in the content." >&2
    echo "  Got:" >&2
    printf '%s\n' "$CONTENT" | head -3 >&2
    exit 1
  fi

  # Generate timestamp
  TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

  # Inject timestamp into first ## line (only if not already timestamped)
  # Double-stamp guard: if char after "## " is "[", skip injection
  INJECTED=false
  RESULT=""
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$INJECTED" = false ] && [[ "$line" == "## "* ]]; then
      AFTER_HASH="${line#\#\# }"
      if [[ "$AFTER_HASH" == "["* ]]; then
        # Already has timestamp-like prefix — skip injection
        RESULT="${RESULT}${line}"$'\n'
      else
        # Inject timestamp
        RESULT="${RESULT}## [${TIMESTAMP}] ${AFTER_HASH}"$'\n'
      fi
      INJECTED=true
    else
      RESULT="${RESULT}${line}"$'\n'
    fi
  done <<< "$CONTENT"

  # Append: prepend newline for consistent spacing, then append
  printf '\n%s' "$RESULT" >> "$FILE"
fi
