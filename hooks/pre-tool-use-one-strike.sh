#!/bin/bash
# PreToolUse hook: One-strike warning for destructive commands
# Blocks destructive Bash commands on first attempt with educational message.
# Allows on retry (same pattern type) within same Claude session.
#
# State: PID-scoped temp files at $WARNED_DIR/claude-hook-warned-$SUPERVISOR_PID-pattern-$INDEX
# The SUPERVISOR_PID is the Claude Code process PID (from CLAUDE_SUPERVISOR_PID env var,
# set by run.sh, or fallback to PPID).
#
# Patterns detected (tree/index-destructive family — see ¶INV_NO_DESTRUCTIVE_GIT):
#    0: rm with -r or -f flags (rm -rf, rm -r, rm -f, rm --recursive, rm --force)
#    1: git push --force (or -f after push)
#    2: git reset --hard / --merge / --keep
#    3: git clean with force/dir/ignored (-f, -fd, -fx, -d, -x, -X)
#    4: git checkout . (dot — resets working tree)
#    5: git restore (working-tree forms; --staged-only is allowed)
#    6: git stash (any mutating subcommand; list/show allowed)
#    7: git checkout [<rev>] -- <paths> (working-tree overwrite — THE incident vector)
#    8: git checkout -f / git switch -f/--force/--discard-changes (force switch clobbers dirty tree)
#    9: git reset (bare / --mixed) — risky index move, warn-then-allow
#   10: git rm (removes tracked files / working copy)
#   11: git branch -d / -D (branch deletion)
#   12: git add -A / -u / . / -p / -i (sweeps a dirty multi-agent tree; add -- <path> is allowed)
#
# Allowed (never blocked): read-only git (status, log, diff, show, rev-parse, fsck,
# reflog, stash list/show, branch --list), and the ONE safe write `git add -- <explicit path>`.
#
# Robustness: the git-subcommand scan tolerates leading env vars, `cd … &&` / `;` / `&&`
# chains, `$(…)` command substitution, and a leading `git -C <dir>` / `-c <cfg>` prefix.
# It biases toward NOT false-positiving on read-only git.
#
# Related:
#   Invariants (~/.claude/.directives/INVARIANTS.md):
#     ¶INV_NO_DESTRUCTIVE_GIT — no tree/index-destructive git in a dirty multi-agent tree
#     ¶INV_NO_GIT_STATE_COMMANDS — multi-agent git-state safety (superseded/implemented by the above)

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

# Shared educational guidance for the tree/index-destructive git family.
# Names the WHY + the safe alternatives + the one authorized write.
GIT_GUIDANCE="The working tree is ALWAYS dirty with parallel-agent churn, so this can silently destroy another agent's uncommitted work with NO git-recoverable trace (no stash, no commit). NEVER stash/checkout/reset/restore/clean to 'clean up' or capture a baseline. To read a committed version use 'git show HEAD:<path>'; to read the working file, open it by explicit path. The only allowed tree/index write is 'git add -- <explicit path>'. If you genuinely believe you must run this, STOP and ask the user — only the user can authorize it. Ref: ¶INV_NO_DESTRUCTIVE_GIT."

# --- Reusable git-subcommand prefix ---
# Matches `git` at a word/statement boundary (start, whitespace, ; & | or `$(`),
# tolerating an optional leading `git -C <dir>` / `-c <cfg>` global-option prefix,
# up to the whitespace before the subcommand.
GITP='(^|[[:space:]|;&(])git([[:space:]]+-C[[:space:]]+[^[:space:]]+|[[:space:]]+-c[[:space:]]+[^[:space:]]+)*[[:space:]]+'

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
if [[ "$CMD" =~ ${GITP}push[[:space:]] ]]; then
  if [[ "$CMD" =~ ${GITP}push[[:space:]].*(--force|-f) ]]; then
    deny_destructive 1 \
      "git push --force" \
      "Force-pushing overwrites remote history, potentially destroying other developers' commits. ${GIT_GUIDANCE}"
  fi
fi

# Pattern 2: git reset --hard / --merge / --keep (working-tree/index data loss)
if [[ "$CMD" =~ ${GITP}reset[[:space:]]+(--hard|--merge|--keep) ]]; then
  deny_destructive 2 \
    "git reset --hard/--merge/--keep" \
    "git reset --hard/--merge/--keep discards uncommitted changes (staged and/or unstaged) permanently. ${GIT_GUIDANCE}"
fi

# Pattern 9: git reset (bare / --mixed / path unstage) — risky, warn-then-allow.
# --soft is safe (moves HEAD only); --hard/--merge/--keep handled by Pattern 2.
if [[ "$CMD" =~ ${GITP}reset($|[[:space:]]) ]]; then
  if [[ ! "$CMD" =~ ${GITP}reset[[:space:]]+(--hard|--merge|--keep) ]] \
     && [[ ! "$CMD" =~ [[:space:]]--soft($|[[:space:]]) ]]; then
    deny_destructive 9 \
      "git reset (bare/--mixed)" \
      "git reset (bare or --mixed) moves HEAD and unstages the index — in a dirty multi-agent tree this can bury or confuse another agent's staged work. ${GIT_GUIDANCE}"
  fi
fi

# Pattern 3: git clean with force/dir/ignored flags (skip pure dry-run -n)
if [[ "$CMD" =~ ${GITP}clean[[:space:]]+-[[:alnum:]]*[fdxX] ]]; then
  if [[ ! "$CMD" =~ (--dry-run|(^|[[:space:]])-[[:alnum:]]*n([[:space:]]|$)) ]]; then
    deny_destructive 3 \
      "git clean -f/-d/-x" \
      "git clean permanently removes untracked (and with -x, ignored) files from the working tree. These files are NOT recoverable. ${GIT_GUIDANCE}"
  fi
fi

# Pattern 4: git checkout . (dot — resets entire working tree)
if [[ "$CMD" =~ ${GITP}checkout[[:space:]]+\. ]]; then
  deny_destructive 4 \
    "git checkout ." \
    "git checkout . discards ALL unstaged changes in the working tree. In a multi-agent repo this destroys other agents' in-flight work. ${GIT_GUIDANCE}"
fi

# Pattern 7: git checkout [<rev>] -- <paths> (working-tree overwrite — THE incident).
# `git checkout HEAD -- foo`, `git checkout -- foo`, `git checkout <branch> -- foo`.
if [[ "$CMD" =~ ${GITP}checkout[[:space:]]+([^;\&|]*[[:space:]])?--([[:space:]]|$) ]]; then
  deny_destructive 7 \
    "git checkout -- <paths>" \
    "git checkout [<rev>] -- <paths> force-overwrites those working-tree files with the committed/indexed version — the exact command that silently reverted 8 off-lane files with no git trace. ${GIT_GUIDANCE}"
fi

# Pattern 8: git checkout -f / git switch -f/--force/--discard-changes (force switch clobbers).
# Plain `git checkout <branch>` / `git switch <branch>` are NOT blocked — git refuses to
# clobber a dirty tree on a non-force switch, so those are safe.
if [[ "$CMD" =~ ${GITP}checkout[[:space:]]+([^;\&|]*[[:space:]])?(-f|--force)([[:space:]]|$) ]] \
   || [[ "$CMD" =~ ${GITP}switch[[:space:]]+([^;\&|]*[[:space:]])?(-f|--force|--discard-changes)([[:space:]]|$) ]]; then
  deny_destructive 8 \
    "git checkout -f / git switch --force" \
    "A forced branch switch (checkout -f / switch --force / --discard-changes) throws away uncommitted changes in the working tree. ${GIT_GUIDANCE}"
fi

# Pattern 5: git restore — working-tree forms. `git restore --staged <path>` (index-only,
# no --worktree/-W) is allowed; everything else overwrites the working tree.
if [[ "$CMD" =~ ${GITP}restore($|[[:space:]]) ]]; then
  if [[ "$CMD" =~ [[:space:]]--staged($|[[:space:]]) ]] \
     && [[ ! "$CMD" =~ [[:space:]](--worktree|-W)($|[[:space:]]) ]]; then
    : # index-only unstage — non-destructive, allow
  else
    deny_destructive 5 \
      "git restore <paths>" \
      "git restore (without --staged, or with --worktree/-W) discards unstaged changes in the named working-tree files. In a multi-agent repo this destroys other agents' in-flight work. ${GIT_GUIDANCE}"
  fi
fi

# Pattern 6: git stash — any mutating subcommand. `git stash list` / `git stash show`
# are read-only inspections and are allowed.
if [[ "$CMD" =~ ${GITP}stash($|[[:space:]]) ]]; then
  if [[ "$CMD" =~ ${GITP}stash[[:space:]]+(list|show)($|[[:space:]]) ]]; then
    : # read-only stash inspection — allow
  else
    deny_destructive 6 \
      "git stash" \
      "git stash (push/pop/apply/drop/clear/save) moves uncommitted changes off the working tree; a bare 'pop' can also collide with an unrelated stash. In a multi-agent repo this disrupts other agents' in-flight work. ${GIT_GUIDANCE}"
  fi
fi

# Pattern 10: git rm (removes tracked files, deletes the working copy)
if [[ "$CMD" =~ ${GITP}rm($|[[:space:]]) ]]; then
  deny_destructive 10 \
    "git rm" \
    "git rm deletes tracked files from the index and (without --cached) the working tree. In a multi-agent repo this can remove another agent's file. ${GIT_GUIDANCE}"
fi

# Pattern 11: git branch -d / -D / --delete (branch deletion)
if [[ "$CMD" =~ ${GITP}branch[[:space:]]+([^;\&|]*[[:space:]])?(-d|-D|--delete)($|[[:space:]]) ]]; then
  deny_destructive 11 \
    "git branch -d/-D" \
    "git branch -d/-D deletes a branch ref; -D force-deletes even unmerged work, which can orphan commits. ${GIT_GUIDANCE}"
fi

# Pattern 12: git add sweep forms (-A / -u / . / -p / -i). `git add -- <path>` and a plain
# `git add <path>` are the allowed targeted writes and are NOT blocked here.
if [[ "$CMD" =~ ${GITP}add[[:space:]] ]]; then
  if [[ "$CMD" =~ ${GITP}add[[:space:]]+([^;\&|]*[[:space:]])?(-A|--all|-u|--update|-p|--patch|-i|--interactive)($|[[:space:]]) ]] \
     || [[ "$CMD" =~ ${GITP}add[[:space:]]+\.($|[[:space:]]) ]]; then
    deny_destructive 12 \
      "git add -A/-u/./-p" \
      "git add -A/-u/./-p/-i sweeps the whole dirty tree into the index, capturing other agents' parallel work into your commit. Stage only what you own: 'git add -- <explicit path>'. ${GIT_GUIDANCE}"
  fi
fi

# Not destructive — allow
hook_allow
exit 0
