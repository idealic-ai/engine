#!/bin/bash
# PreToolUse hook: One-strike warning for destructive commands
# Blocks destructive Bash commands on first attempt with educational message.
# Allows on retry (same pattern type) within same Claude session.
#
# State: PID-scoped temp files at $WARNED_DIR/claude-hook-warned-$SUPERVISOR_PID-pattern-$INDEX
# The SUPERVISOR_PID is the Claude Code process PID (from CLAUDE_SUPERVISOR_PID env var,
# set by run.sh, or fallback to PPID).
#
# Patterns detected:
#   0: rm with -r or -f flags (rm -rf, rm -r, rm -f, rm --recursive, rm --force)
#   1: git push --force (or -f after push)
#   2: git reset --hard
#   3: git clean -f (or -fd, -fx, etc.)
#   4: git checkout . (dot - resets working tree)
#   5: git restore . (dot - resets working tree)
#   6: git stash (any form)
#
# Related:
#   Invariants: (~/.claude/standards/INVARIANTS.md)
#     ¶INV_NO_GIT_STATE_COMMANDS — Multi-agent safety: no git state modifications

set -euo pipefail

# Source shared utilities
source "$HOME/.claude/scripts/lib.sh"

# Read hook input from stdin
INPUT=$(cat)

# Parse tool info
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

# Only fire for Bash tool; allow everything else immediately
if [ "$TOOL_NAME" != "Bash" ]; then
  hook_allow
fi

# Parse command
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

# Handle empty command gracefully
if [ -z "$CMD" ]; then
  hook_allow
fi

# Strip heredoc bodies before pattern matching.
# Heredocs (<<EOF ... EOF) contain text content, not commands.
# Without stripping, text like "force-pushing overwrites history" in a
# log heredoc would false-positive on the git push --force pattern.
CMD="${CMD%%<<*}"

# After stripping, re-check for empty
if [ -z "$CMD" ]; then
  hook_allow
fi

# PID for scoping warning files
SUPERVISOR_PID="${CLAUDE_SUPERVISOR_PID:-$PPID}"

# Directory for warning files (overridable for testing)
WARNED_DIR="${CLAUDE_HOOK_WARNED_DIR:-/tmp}"

# check_warned INDEX — returns 0 if already warned for this pattern
check_warned() {
  local idx="$1"
  [ -f "${WARNED_DIR}/claude-hook-warned-${SUPERVISOR_PID}-pattern-${idx}" ]
}

# set_warned INDEX — create warning file for this pattern
set_warned() {
  local idx="$1"
  touch "${WARNED_DIR}/claude-hook-warned-${SUPERVISOR_PID}-pattern-${idx}"
}

# deny_destructive INDEX DESCRIPTION EXPLANATION
# If already warned, allow. Otherwise, warn and deny.
deny_destructive() {
  local idx="$1"
  local desc="$2"
  local explanation="$3"

  if check_warned "$idx"; then
    hook_allow
  fi

  set_warned "$idx"

  hook_deny \
    "[block: one-strike] §CMD_CONFIRM_DESTRUCTIVE — ${desc}" \
    "${explanation} Retry to allow." \
    ""
}

# --- Pattern matching ---

# Pattern 0: rm with -r or -f flags
if [[ "$CMD" =~ (^|[[:space:]|;&])rm[[:space:]] ]]; then
  if [[ "$CMD" =~ (^|[[:space:]|;&])rm[[:space:]].*(-[[:alnum:]]*[rf]|--recursive|--force) ]]; then
    deny_destructive 0 \
      "rm with recursive/force flags" \
      "This command uses rm with -r/-f/--recursive/--force flags, which permanently deletes files without confirmation. Data loss is irreversible."
  fi
fi

# Pattern 1: git push --force (or -f after push)
if [[ "$CMD" =~ (^|[[:space:]|;&])git[[:space:]]+push[[:space:]] ]]; then
  if [[ "$CMD" =~ (^|[[:space:]|;&])git[[:space:]]+push[[:space:]].*(--force|-f) ]]; then
    deny_destructive 1 \
      "git push --force" \
      "Force-pushing overwrites remote history, potentially destroying other developers' commits. Ref: ¶INV_NO_GIT_STATE_COMMANDS."
  fi
fi

# Pattern 2: git reset --hard
if [[ "$CMD" =~ (^|[[:space:]|;&])git[[:space:]]+reset[[:space:]]+--hard ]]; then
  deny_destructive 2 \
    "git reset --hard" \
    "git reset --hard discards ALL uncommitted changes (staged and unstaged) permanently. Ref: ¶INV_NO_GIT_STATE_COMMANDS."
fi

# Pattern 3: git clean -f (or -fd, -fx, etc.)
if [[ "$CMD" =~ (^|[[:space:]|;&])git[[:space:]]+clean[[:space:]]+-[[:alnum:]]*f ]]; then
  deny_destructive 3 \
    "git clean -f" \
    "git clean -f permanently removes untracked files from the working tree. These files are NOT recoverable. Ref: ¶INV_NO_GIT_STATE_COMMANDS."
fi

# Pattern 4: git checkout . (dot — resets working tree)
if [[ "$CMD" =~ (^|[[:space:]|;&])git[[:space:]]+checkout[[:space:]]+\. ]]; then
  deny_destructive 4 \
    "git checkout ." \
    "git checkout . discards ALL unstaged changes in the working tree. In a multi-agent repo this destroys other agents' in-flight work. Ref: ¶INV_NO_GIT_STATE_COMMANDS."
fi

# Pattern 5: git restore . (dot — resets working tree)
if [[ "$CMD" =~ (^|[[:space:]|;&])git[[:space:]]+restore[[:space:]]+\. ]]; then
  deny_destructive 5 \
    "git restore ." \
    "git restore . discards ALL unstaged changes in the working tree. In a multi-agent repo this destroys other agents' in-flight work. Ref: ¶INV_NO_GIT_STATE_COMMANDS."
fi

# Pattern 6: git stash (any form)
if [[ "$CMD" =~ (^|[[:space:]|;&])git[[:space:]]+stash($|[[:space:]]) ]]; then
  deny_destructive 6 \
    "git stash" \
    "git stash moves uncommitted changes off the working tree. In a multi-agent repo this disrupts other agents' in-flight work. Ref: ¶INV_NO_GIT_STATE_COMMANDS."
fi

# Not destructive — allow
hook_allow
exit 0
