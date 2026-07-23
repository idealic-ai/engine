#!/bin/bash
# ~/.claude/scripts/log.sh — Append-only logging for workflow engine
#
# Related:
#   Docs: (~/.claude/docs/)
#     SESSION_LIFECYCLE.md — Log file lifecycle
#   Commands: (~/.claude/.directives/COMMANDS.md)
#     §CMD_APPEND_LOG — Primary usage pattern
#     §CMD_THINK_IN_LOG — Reasoning documentation
#     §CMD_LOG_INTERACTION — Q&A logging
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
#   ~/.claude/scripts/log.sh --reason section <file> <<'EOF'
#   ## Header  ->  ## [<ts>] «section» Header
#   EOF
#
# Behavior:
#   - Creates parent directories if they don't exist
#   - Default: Prepends a blank line and appends stdin to file
#   - With --overwrite: Replaces file content entirely (no blank line)
#   - With --reason <type>: append-only; injects «<type>» after the timestamp
#   - Produces no output (silent operation)

set -euo pipefail

# Closed reason vocabulary — single source of truth (piece 2 reuses this list).
VALID_REASONS="step section plan found-issue divergence interruption decision block"

OVERWRITE=false
REASON=""
FILE=""
# Position-tolerant: flags (--overwrite / --reason <type>) may appear before OR after
# the <file> positional, so the natural `engine log <file> --reason X` parses the flag
# too — matching the heartbeat hook, which reads --reason from anywhere in the command.
while [ $# -gt 0 ]; do
  case "$1" in
    --overwrite)
      OVERWRITE=true
      shift
      ;;
    --reason)
      shift
      REASON="${1:-}"
      if [ -z "$REASON" ]; then
        echo "ERROR: log.sh: --reason requires a value." >&2
        echo "  Valid: $VALID_REASONS" >&2
        exit 1
      fi
      shift
      ;;
    *)
      if [ -z "$FILE" ]; then
        FILE="$1"
        shift
      else
        echo "ERROR: log.sh: unexpected extra argument '$1'." >&2
        exit 1
      fi
      ;;
  esac
done

# Validate --reason: append-only, closed vocabulary.
if [ -n "$REASON" ]; then
  if [ "$OVERWRITE" = true ]; then
    echo "ERROR: log.sh: --reason is only valid in append mode (not with --overwrite)." >&2
    exit 1
  fi
  case " $VALID_REASONS " in
    *" $REASON "*) : ;;
    *)
      echo "ERROR: log.sh: invalid --reason '$REASON'." >&2
      echo "  Valid: $VALID_REASONS" >&2
      exit 1
      ;;
  esac
fi

if [ -z "$FILE" ]; then
  echo "Usage: log.sh [--overwrite] [--reason <type>] <file> (reads content from stdin)" >&2
  exit 1
fi

# No mkdir -p: if the directory doesn't exist, fail loudly.
# This prevents silent misdirection when CWD changes (e.g., agent runs cd).
if [ ! -d "$(dirname "$FILE")" ]; then
  echo "ERROR: log.sh: directory does not exist: $(dirname "$FILE")" >&2
  echo "  CWD: $(pwd)" >&2
  echo "  Hint: Use absolute path or ensure you're in the project root." >&2
  exit 1
fi

# Read all stdin into variable
CONTENT=$(cat)

if [ "$OVERWRITE" = true ]; then
  # Overwrite mode: replace file entirely, no timestamp injection
  printf '%s\n' "$CONTENT" > "$FILE"
else
  # Append mode: auto-inject timestamp into first ## heading

  # Check that content has a ## heading
  if ! printf '%s\n' "$CONTENT" | grep -q '^##'; then
    echo "ERROR: log.sh append mode requires a ## heading in the content." >&2
    echo "  Got:" >&2
    printf '%s\n' "$CONTENT" | head -3 >&2
    exit 1
  fi

  # Generate timestamp
  TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

  # Stamp = timestamp plus optional reason marker (after the timestamp so the
  # double-stamp guard, which tests the char after "## " for "[", still holds).
  STAMP="[${TIMESTAMP}]"
  if [ -n "$REASON" ]; then
    STAMP="${STAMP} «${REASON}»"
  fi

  # Inject timestamp into first ## line (only if not already timestamped)
  # Double-stamp guard: if char after "## " is "[", skip injection
  INJECTED=false
  RESULT=""
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$INJECTED" = false ] && [[ "$line" == "##"* ]]; then
      AFTER_HASH="${line#\#\# }"
      if [ "$line" = "##" ]; then
        # Bare ## heading (no text) — inject stamp only
        RESULT="${RESULT}## ${STAMP}"$'\n'
      elif [[ "$AFTER_HASH" == "["* ]]; then
        # Already has timestamp-like prefix — skip injection
        RESULT="${RESULT}${line}"$'\n'
      else
        # Inject stamp
        RESULT="${RESULT}## ${STAMP} ${AFTER_HASH}"$'\n'
      fi
      INJECTED=true
    else
      RESULT="${RESULT}${line}"$'\n'
    fi
  done <<< "$CONTENT"

  # Append: prepend newline for consistent spacing, then append
  printf '\n%s' "$RESULT" >> "$FILE"
fi
