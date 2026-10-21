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

# No mkdir -p: if the directory doesn't exist, fail loudly.
# This prevents silent misdirection when CWD changes (e.g., agent runs cd).
if [ ! -d "$(dirname "$FILE")" ]; then
  echo "ERROR: log.sh: directory does not exist: $(dirname "$FILE")" >&2
  echo "  CWD: $(pwd)" >&2
  echo "  Hint: Use absolute path or ensure you're in the project root." >&2
  exit 1
fi

# ── Which sessions root? ──────────────────────────────────────────────────────
#
# A relative `sessions/<name>/...` resolves against the CWD, and a project's `sessions/` is a
# SYMLINK into a local data root. That is the right destination only when the session actually
# lives there: a session keeping its artifacts elsewhere gets its stanza written into a parallel
# tree of the same name, at exit 0, with nothing reporting it. The dir-exists check above cannot
# catch it — a stale tree has the directory.
#
# `session.sh find` is the resolver that OWNS the answer (the same one credentials anchor on), so
# asking it cannot produce a second disagreeing opinion. The comparison is PHYSICAL: the project
# path and the data root are two spellings of one directory, and refusing on the spelling would
# fire on every correct relative write.
#
# Gated on a relative path carrying a `sessions/` segment, so no other write pays for the lookup.
# Fails OPEN: a log write is how an agent reports, and a guard that blocks writes whenever session
# discovery is unavailable silences the reporting channel.
# ENGINE_LOG_ALLOW_FOREIGN_SESSION=1 waives the refusal — and still names the root it used, since
# a silent waiver is the original defect with a flag on it.
_log_session_guard() {
  local file="$1"
  case "$file" in /*) return 0 ;; esac
  case "$file" in sessions/*|*/sessions/*) ;; *) return 0 ;; esac

  local scripts="" cand sess destdir rootphys tail corrected
  for cand in "${ENGINE_SCRIPTS:-}" "$(cd "$(dirname "$0")" 2>/dev/null && pwd)" "$HOME/.claude/engine/scripts"; do
    if [ -n "$cand" ] && [ -x "$cand/session.sh" ]; then scripts="$cand"; break; fi
  done
  [ -n "$scripts" ] || return 0
  sess="$("$scripts/session.sh" find 2>/dev/null)" || sess=""
  [ -n "$sess" ] && [ -d "$sess" ] || return 0

  destdir="$(cd "$(dirname "$file")" 2>/dev/null && pwd -P)" || return 0
  rootphys="$(cd "$sess" 2>/dev/null && pwd -P)" || return 0
  [ -n "$destdir" ] && [ -n "$rootphys" ] || return 0
  [ "$destdir" = "$rootphys" ] && return 0
  case "$destdir/" in "$rootphys"/*) return 0 ;; esac

  tail="${file#*sessions/}"
  case "$tail" in */*) tail="${tail#*/}" ;; esac
  corrected="$rootphys/$tail"

  if [ -n "${ENGINE_LOG_ALLOW_FOREIGN_SESSION:-}" ]; then
    echo "log.sh: writing OUTSIDE the live session, as waived: $destdir/$(basename "$file")" >&2
    echo "  live session: $rootphys" >&2
    return 0
  fi

  echo "ERROR: log.sh: this relative path resolves to a DIFFERENT sessions root." >&2
  echo "  you wrote:    $file" >&2
  echo "  CWD:          $(pwd)" >&2
  echo "  would land:   $destdir/$(basename "$file")" >&2
  echo "  live session: $rootphys" >&2
  echo "  Nothing was written. Use the absolute path:" >&2
  echo "    $corrected" >&2
  echo "  (ENGINE_LOG_ALLOW_FOREIGN_SESSION=1 waives this if the other root is what you meant.)" >&2
  return 1
}
_log_session_guard "$FILE" || exit 1

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

  # Inject timestamp into first ## line (only if not already timestamped)
  # Double-stamp guard: skip only when the bracket holds a YYYY-MM-DD date. Guarding on a
  # bare "[" turned the injector off for every heading a loom lane writes (¶INV_LOOM_AGENTS
  # _NAMED_BY_THREAD mandates "## [TAG] ..."), and for ticket-key headings like "## [FIN-1]".
  INJECTED=false
  RESULT=""
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$INJECTED" = false ] && [[ "$line" == "##"* ]]; then
      AFTER_HASH="${line#\#\# }"
      if [ "$line" = "##" ]; then
        # Bare ## heading (no text) — inject timestamp only
        RESULT="${RESULT}## [${TIMESTAMP}]"$'\n'
      elif [[ "$AFTER_HASH" =~ ^\[[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
        # Already dated — skip injection
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
