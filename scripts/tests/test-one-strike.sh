#!/bin/bash
# tests/test-one-strike.sh — Tests for pre-tool-use-one-strike.sh hook
#
# Tests:
#   1.  Non-destructive Bash commands allowed (git status, ls -la, echo foo)
#   2.  Non-Bash tools always allowed (Edit, Write, Read)
#   3.  rm -rf denied on first attempt
#   4.  git push --force denied on first attempt
#   5.  git reset --hard denied on first attempt
#   6.  git clean -f denied on first attempt
#   7.  git checkout . denied on first attempt
#   8.  git restore . denied on first attempt
#   9.  git stash denied on first attempt
#  10.  Same pattern allowed on second attempt (warning file exists)
#  11.  Different pattern still denied after first pattern warned
#  12.  Empty command handled gracefully
#  13.  Warning files are PID-scoped (different PID -> different warning state)
#  14.  rm -r (without -f) also caught
#  15.  rm --recursive also caught
#  16.  rm --force also caught
#  17.  git push -f also caught
#  18.  git clean -fd also caught
#  19.  git stash pop also caught
#  H1-H6. Heredoc false-positive hardening; B1-B4. boundary hardening
#  G1.  git checkout [<rev>] -- <paths> denied (THE incident vector)
#  G2.  git restore forms (worktree denied, --staged-only allowed)
#  G3.  git reset --merge/--keep denied; bare/--mixed warned; --soft allowed
#  G4.  git clean -x/-d denied; -n (dry-run) allowed
#  G5.  git rm / git rm --cached denied
#  G6.  git branch -d/-D denied; create/--list allowed
#  G7.  git add -A/-u/./-p denied; git add -- <path> / add <path> allowed
#  G8.  git checkout -f / switch --force/--discard-changes denied; safe switch allowed
#  G9.  git stash list/show allowed (read-only inspection)
#  G10. read-only git (show/rev-parse/reflog/fsck/diff) allowed
#  G11. robust matching: git -C <dir>, cd && chain, env prefix
#  G12. deny message names command + safe alternative
#
# Run: bash ~/.claude/engine/scripts/tests/test-one-strike.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

HOOK="$HOME/.claude/engine/hooks/pre-tool-use-one-strike.sh"

TMP_DIR=$(mktemp -d)
WARNED_DIR="$TMP_DIR/warnings"
mkdir -p "$WARNED_DIR"

# Use a fixed PID for test isolation
export CLAUDE_SUPERVISOR_PID=88888888
export CLAUDE_HOOK_WARNED_DIR="$WARNED_DIR"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Run hook with given tool_name and optional tool_input
run_hook() {
  local tool_name="$1"
  local tool_input="${2:-\{\}}"
  printf '{"tool_name":"%s","tool_input":%s}\n' "$tool_name" "$tool_input" \
    | "$HOOK" 2>/dev/null
}

# Clear all warning files between test groups
clear_warnings() {
  rm -f "$WARNED_DIR"/claude-hook-warned-* 2>/dev/null || true
}

echo "======================================"
echo "One-Strike Warning Hook Tests"
echo "======================================"
echo ""

# --- 1. Non-destructive Bash commands allowed ---
echo "--- 1. Non-destructive Bash commands ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git status"}')
assert_contains '"allow"' "$OUT" "git status allowed"

OUT=$(run_hook "Bash" '{"command":"ls -la"}')
assert_contains '"allow"' "$OUT" "ls -la allowed"

OUT=$(run_hook "Bash" '{"command":"echo foo"}')
assert_contains '"allow"' "$OUT" "echo foo allowed"

OUT=$(run_hook "Bash" '{"command":"git log --oneline -5"}')
assert_contains '"allow"' "$OUT" "git log allowed"

OUT=$(run_hook "Bash" '{"command":"git diff HEAD"}')
assert_contains '"allow"' "$OUT" "git diff allowed"

OUT=$(run_hook "Bash" '{"command":"git push origin main"}')
assert_contains '"allow"' "$OUT" "git push (no force) allowed"

OUT=$(run_hook "Bash" '{"command":"git checkout feature-branch"}')
assert_contains '"allow"' "$OUT" "git checkout branch-name allowed"

OUT=$(run_hook "Bash" '{"command":"git restore --staged file.txt"}')
assert_contains '"allow"' "$OUT" "git restore --staged file allowed"

OUT=$(run_hook "Bash" '{"command":"rm file.txt"}')
assert_contains '"allow"' "$OUT" "rm without flags allowed"

echo ""

# --- 2. Non-Bash tools always allowed ---
echo "--- 2. Non-Bash tools ---"
clear_warnings

OUT=$(run_hook "Edit" '{"file_path":"/tmp/x","old_string":"a","new_string":"b"}')
assert_contains '"allow"' "$OUT" "Edit always allowed"

OUT=$(run_hook "Write" '{"file_path":"/tmp/x","content":"hello"}')
assert_contains '"allow"' "$OUT" "Write always allowed"

OUT=$(run_hook "Read" '{"file_path":"/tmp/x"}')
assert_contains '"allow"' "$OUT" "Read always allowed"

OUT=$(run_hook "Grep" '{"pattern":"foo","path":"/tmp"}')
assert_contains '"allow"' "$OUT" "Grep always allowed"

echo ""

# --- 3. rm -rf denied on first attempt ---
echo "--- 3. rm -rf denied first attempt ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"rm -rf /tmp/foo"}')
assert_contains '"deny"' "$OUT" "rm -rf denied on first attempt"
assert_contains 'one-strike' "$OUT" "deny message contains one-strike guard name"
assert_contains 'recursive/force' "$OUT" "deny message mentions recursive/force"

echo ""

# --- 4. git push --force denied on first attempt ---
echo "--- 4. git push --force denied ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git push --force origin main"}')
assert_contains '"deny"' "$OUT" "git push --force denied on first attempt"
assert_contains 'INV_NO_DESTRUCTIVE_GIT' "$OUT" "deny mentions invariant"

echo ""

# --- 5. git reset --hard denied on first attempt ---
echo "--- 5. git reset --hard denied ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git reset --hard HEAD~1"}')
assert_contains '"deny"' "$OUT" "git reset --hard denied on first attempt"
assert_contains 'INV_NO_DESTRUCTIVE_GIT' "$OUT" "deny mentions invariant"

echo ""

# --- 6. git clean -f denied on first attempt ---
echo "--- 6. git clean -f denied ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git clean -f"}')
assert_contains '"deny"' "$OUT" "git clean -f denied on first attempt"
assert_contains 'INV_NO_DESTRUCTIVE_GIT' "$OUT" "deny mentions invariant"

echo ""

# --- 7. git checkout . denied on first attempt ---
echo "--- 7. git checkout . denied ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git checkout ."}')
assert_contains '"deny"' "$OUT" "git checkout . denied on first attempt"
assert_contains 'INV_NO_DESTRUCTIVE_GIT' "$OUT" "deny mentions invariant"

echo ""

# --- 8. git restore . denied on first attempt ---
echo "--- 8. git restore . denied ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git restore ."}')
assert_contains '"deny"' "$OUT" "git restore . denied on first attempt"
assert_contains 'INV_NO_DESTRUCTIVE_GIT' "$OUT" "deny mentions invariant"

echo ""

# --- 9. git stash denied on first attempt ---
echo "--- 9. git stash denied ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git stash"}')
assert_contains '"deny"' "$OUT" "git stash denied on first attempt"
assert_contains 'INV_NO_DESTRUCTIVE_GIT' "$OUT" "deny mentions invariant"

echo ""

# --- 10. Same pattern allowed on second attempt ---
echo "--- 10. Same pattern allowed on retry ---"
clear_warnings

# First attempt — denied
OUT=$(run_hook "Bash" '{"command":"rm -rf /tmp/foo"}')
assert_contains '"deny"' "$OUT" "rm -rf denied first time"

# Second attempt (same pattern, different args) — allowed
OUT=$(run_hook "Bash" '{"command":"rm -rf /tmp/bar"}')
assert_contains '"allow"' "$OUT" "rm -rf allowed on retry (same pattern)"

# Same for git stash
OUT=$(run_hook "Bash" '{"command":"git stash"}')
assert_contains '"deny"' "$OUT" "git stash denied first time"

OUT=$(run_hook "Bash" '{"command":"git stash save \"my changes\""}')
assert_contains '"allow"' "$OUT" "git stash save allowed on retry"

echo ""

# --- 11. Different pattern still denied after first warned ---
echo "--- 11. Cross-pattern isolation ---"
clear_warnings

# Warn on rm -rf (pattern 0)
OUT=$(run_hook "Bash" '{"command":"rm -rf /tmp/foo"}')
assert_contains '"deny"' "$OUT" "rm -rf denied (pattern 0)"

# git reset --hard (pattern 2) should STILL be denied
OUT=$(run_hook "Bash" '{"command":"git reset --hard"}')
assert_contains '"deny"' "$OUT" "git reset --hard still denied (pattern 2, not warned yet)"

# rm -rf should now be allowed (pattern 0 was warned)
OUT=$(run_hook "Bash" '{"command":"rm -rf /tmp/baz"}')
assert_contains '"allow"' "$OUT" "rm -rf allowed after warning"

# git reset --hard should now be allowed (pattern 2 was warned)
OUT=$(run_hook "Bash" '{"command":"git reset --hard HEAD"}')
assert_contains '"allow"' "$OUT" "git reset --hard allowed after warning"

echo ""

# --- 12. Empty command handled gracefully ---
echo "--- 12. Empty command ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":""}')
assert_contains '"allow"' "$OUT" "empty command allowed"

OUT=$(run_hook "Bash" '{}')
assert_contains '"allow"' "$OUT" "missing command field allowed"

echo ""

# --- 13. PID-scoped warnings ---
echo "--- 13. PID-scoped warnings ---"
clear_warnings

# Warn with PID 88888888 (current)
OUT=$(run_hook "Bash" '{"command":"rm -rf /tmp/foo"}')
assert_contains '"deny"' "$OUT" "rm -rf denied for PID 88888888"

# Retry with same PID — allowed
OUT=$(run_hook "Bash" '{"command":"rm -rf /tmp/bar"}')
assert_contains '"allow"' "$OUT" "rm -rf allowed on retry for PID 88888888"

# Switch to different PID — should be denied again
export CLAUDE_SUPERVISOR_PID=77777777

OUT=$(run_hook "Bash" '{"command":"rm -rf /tmp/baz"}')
assert_contains '"deny"' "$OUT" "rm -rf denied for different PID 77777777"

# Retry with new PID — now allowed
OUT=$(run_hook "Bash" '{"command":"rm -rf /tmp/qux"}')
assert_contains '"allow"' "$OUT" "rm -rf allowed on retry for PID 77777777"

# Restore PID
export CLAUDE_SUPERVISOR_PID=88888888

echo ""

# --- 14. rm variant flags ---
echo "--- 14. rm variant flags ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"rm -r /tmp/foo"}')
assert_contains '"deny"' "$OUT" "rm -r (no -f) denied"

clear_warnings

OUT=$(run_hook "Bash" '{"command":"rm --recursive /tmp/foo"}')
assert_contains '"deny"' "$OUT" "rm --recursive denied"

clear_warnings

OUT=$(run_hook "Bash" '{"command":"rm --force /tmp/foo"}')
assert_contains '"deny"' "$OUT" "rm --force denied"

clear_warnings

OUT=$(run_hook "Bash" '{"command":"rm -f /tmp/foo"}')
assert_contains '"deny"' "$OUT" "rm -f denied"

echo ""

# --- 15. git push -f variant ---
echo "--- 15. git push -f variant ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git push -f origin main"}')
assert_contains '"deny"' "$OUT" "git push -f denied"

echo ""

# --- 16. git clean -fd variant ---
echo "--- 16. git clean -fd variant ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git clean -fd"}')
assert_contains '"deny"' "$OUT" "git clean -fd denied"

clear_warnings

OUT=$(run_hook "Bash" '{"command":"git clean -fx"}')
assert_contains '"deny"' "$OUT" "git clean -fx denied"

echo ""

# --- 17. git stash pop variant ---
echo "--- 17. git stash pop variant ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git stash pop"}')
assert_contains '"deny"' "$OUT" "git stash pop denied"

clear_warnings

OUT=$(run_hook "Bash" '{"command":"git stash drop"}')
assert_contains '"deny"' "$OUT" "git stash drop denied"

echo ""

# --- 18. Retry message mentions retrying ---
echo "--- 18. Deny message quality ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"rm -rf /tmp/foo"}')
assert_contains 'Retry' "$OUT" "deny message mentions retry will be allowed"

echo ""

# ============================================
# HARDENING TESTS — Heredoc False-Positive Fix
# ============================================

# Helper: create properly escaped JSON for multi-line commands using jq
make_bash_json() {
  jq -n --arg cmd "$1" '{"tool_name":"Bash","tool_input":{"command":$cmd}}'
}

# --- H1. Heredoc with "force-pushing" text should NOT trigger ---
echo "--- H1. Heredoc body with force-pushing text ---"
clear_warnings

# Real-world case: engine log with heredoc body mentioning destructive concepts
HEREDOC_CMD="$(printf 'engine log sessions/test/LOG.md <<'\''EOF'\''\n## Force Push Discussion\nForce-pushing overwrites remote history. git push --force is dangerous.\nEOF')"
OUT=$(make_bash_json "$HEREDOC_CMD" | "$HOOK" 2>/dev/null)
assert_contains '"allow"' "$OUT" "heredoc body with force-pushing text -> allowed"

echo ""

# --- H2. Heredoc with "rm -rf" in text content ---
echo "--- H2. Heredoc body with rm -rf text ---"
clear_warnings

HEREDOC_CMD="$(printf 'engine log sessions/test/LOG.md <<'\''EOF'\''\n## Cleanup Notes\nUse rm -rf to clean temp directories. Be careful with rm --recursive.\nEOF')"
OUT=$(make_bash_json "$HEREDOC_CMD" | "$HOOK" 2>/dev/null)
assert_contains '"allow"' "$OUT" "heredoc body with rm -rf text -> allowed"

echo ""

# --- H3. Heredoc with "git reset --hard" in text content ---
echo "--- H3. Heredoc body with git reset --hard text ---"
clear_warnings

HEREDOC_CMD="$(printf 'engine log sessions/test/LOG.md <<'\''EOF'\''\ngit reset --hard discards all uncommitted changes.\nEOF')"
OUT=$(make_bash_json "$HEREDOC_CMD" | "$HOOK" 2>/dev/null)
assert_contains '"allow"' "$OUT" "heredoc body with git reset --hard text -> allowed"

echo ""

# --- H4. Heredoc with "git stash" in text content ---
echo "--- H4. Heredoc body with git stash text ---"
clear_warnings

HEREDOC_CMD="$(printf 'engine log sessions/test/LOG.md <<'\''EOF'\''\ngit stash moves uncommitted changes off the working tree.\nEOF')"
OUT=$(make_bash_json "$HEREDOC_CMD" | "$HOOK" 2>/dev/null)
assert_contains '"allow"' "$OUT" "heredoc body with git stash text -> allowed"

echo ""

# --- H5. Real rm -rf BEFORE heredoc still denied ---
echo "--- H5. Destructive command before heredoc ---"
clear_warnings

HEREDOC_CMD="$(printf 'rm -rf /tmp/foo && cat <<'\''EOF'\''\nsome text\nEOF')"
OUT=$(make_bash_json "$HEREDOC_CMD" | "$HOOK" 2>/dev/null)
assert_contains '"deny"' "$OUT" "rm -rf before heredoc -> denied"

echo ""

# --- H6. Standalone destructive commands still work (regression) ---
echo "--- H6. Regression: standalone rm -rf still denied ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"rm -rf /tmp/foo"}')
assert_contains '"deny"' "$OUT" "standalone rm -rf still denied (regression check)"

clear_warnings

OUT=$(run_hook "Bash" '{"command":"git push --force origin main"}')
assert_contains '"deny"' "$OUT" "standalone git push --force still denied (regression check)"

clear_warnings

OUT=$(run_hook "Bash" '{"command":"git stash"}')
assert_contains '"deny"' "$OUT" "standalone git stash still denied (regression check)"

echo ""

# ============================================
# BOUNDARY HARDENING TESTS
# ============================================

# --- B1. Very long command (>4KB) ---
echo "--- B1. Very long command ---"
clear_warnings

LONG_CMD="echo $(printf 'x%.0s' $(seq 1 5000))"
OUT=$(make_bash_json "$LONG_CMD" | "$HOOK" 2>/dev/null)
assert_contains '"allow"' "$OUT" "5KB non-destructive command -> allowed"

echo ""

# --- B2. Quoted rm -rf in echo (actually allowed — rm preceded by " not a word boundary) ---
echo "--- B2. Quoted destructive pattern in echo ---"
clear_warnings

OUT=$(make_bash_json 'echo "rm -rf" | wc -l' | "$HOOK" 2>/dev/null)
assert_contains '"allow"' "$OUT" "echo with quoted rm -rf -> allowed (rm not at word boundary)"

# But piped rm IS caught (rm at word boundary after |)
OUT=$(make_bash_json 'echo foo | rm -rf /tmp/bar' | "$HOOK" 2>/dev/null)
assert_contains '"deny"' "$OUT" "piped rm -rf -> denied (rm at word boundary after pipe)"

echo ""

# --- B3. Malformed JSON gracefully handled ---
echo "--- B3. Malformed JSON input ---"
clear_warnings

OUT=$(echo "not json at all" | "$HOOK" 2>/dev/null || echo '{"decision":"allow"}')
assert_contains '"allow"' "$OUT" "malformed JSON -> allowed (fail-open)"

OUT=$(echo '{"tool_name":"Bash"' | "$HOOK" 2>/dev/null || echo '{"decision":"allow"}')
assert_contains '"allow"' "$OUT" "truncated JSON -> allowed (fail-open)"

echo ""

# --- B4. Multi-line command with destructive pattern ---
echo "--- B4. Multi-line command with destructive pattern ---"
clear_warnings

# newline in the command field — properly encoded
MULTI_CMD="$(printf 'echo foo\ngit reset --hard')"
OUT=$(make_bash_json "$MULTI_CMD" | "$HOOK" 2>/dev/null)
assert_contains '"deny"' "$OUT" "multi-line command with git reset --hard -> denied"

echo ""

# ============================================
# DESTRUCTIVE-GIT FAMILY — extended coverage (¶INV_NO_DESTRUCTIVE_GIT)
# ============================================

# --- G1. git checkout [<rev>] -- <paths> (THE incident vector) ---
echo "--- G1. git checkout -- <paths> ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git checkout HEAD -- foo.ts bar.ts"}')
assert_contains '"deny"' "$OUT" "git checkout HEAD -- <paths> denied (incident vector)"
assert_contains 'INV_NO_DESTRUCTIVE_GIT' "$OUT" "incident deny mentions invariant"
assert_contains 'checkout -- <paths>' "$OUT" "deny names the offending command"

clear_warnings
OUT=$(run_hook "Bash" '{"command":"git checkout -- foo.ts"}')
assert_contains '"deny"' "$OUT" "git checkout -- <path> denied"

clear_warnings
OUT=$(run_hook "Bash" '{"command":"git checkout abc123 -- src/"}')
assert_contains '"deny"' "$OUT" "git checkout <rev> -- <path> denied"

echo ""

# --- G2. git restore forms ---
echo "--- G2. git restore forms ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git restore foo.ts"}')
assert_contains '"deny"' "$OUT" "git restore <path> (worktree) denied"

clear_warnings
OUT=$(run_hook "Bash" '{"command":"git restore ."}')
assert_contains '"deny"' "$OUT" "git restore . denied"

clear_warnings
OUT=$(run_hook "Bash" '{"command":"git restore --staged --worktree foo.ts"}')
assert_contains '"deny"' "$OUT" "git restore --staged --worktree denied (touches worktree)"

clear_warnings
OUT=$(run_hook "Bash" '{"command":"git restore -W foo.ts"}')
assert_contains '"deny"' "$OUT" "git restore -W denied"

# --staged-only unstage stays allowed
OUT=$(run_hook "Bash" '{"command":"git restore --staged bar.ts"}')
assert_contains '"allow"' "$OUT" "git restore --staged <path> allowed (index-only)"

echo ""

# --- G3. git reset extended (--merge/--keep block, bare/--mixed warn, --soft allow) ---
echo "--- G3. git reset extended ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git reset --merge"}')
assert_contains '"deny"' "$OUT" "git reset --merge denied"

clear_warnings
OUT=$(run_hook "Bash" '{"command":"git reset --keep HEAD"}')
assert_contains '"deny"' "$OUT" "git reset --keep denied"

clear_warnings
OUT=$(run_hook "Bash" '{"command":"git reset"}')
assert_contains '"deny"' "$OUT" "bare git reset warned (risky index move)"

clear_warnings
OUT=$(run_hook "Bash" '{"command":"git reset --mixed HEAD~1"}')
assert_contains '"deny"' "$OUT" "git reset --mixed warned"

# --soft is safe (moves HEAD only) — allowed
OUT=$(run_hook "Bash" '{"command":"git reset --soft HEAD~1"}')
assert_contains '"allow"' "$OUT" "git reset --soft allowed"

echo ""

# --- G4. git clean -x / -d variants + dry-run allowed ---
echo "--- G4. git clean variants ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git clean -x"}')
assert_contains '"deny"' "$OUT" "git clean -x denied"

clear_warnings
OUT=$(run_hook "Bash" '{"command":"git clean -d"}')
assert_contains '"deny"' "$OUT" "git clean -d denied"

# dry-run preview is safe — allowed
OUT=$(run_hook "Bash" '{"command":"git clean -n"}')
assert_contains '"allow"' "$OUT" "git clean -n (dry-run) allowed"

echo ""

# --- G5. git rm ---
echo "--- G5. git rm ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git rm foo.ts"}')
assert_contains '"deny"' "$OUT" "git rm denied"

clear_warnings
OUT=$(run_hook "Bash" '{"command":"git rm --cached foo.ts"}')
assert_contains '"deny"' "$OUT" "git rm --cached denied"

echo ""

# --- G6. git branch -d/-D (deletion) ---
echo "--- G6. git branch deletion ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git branch -D feature"}')
assert_contains '"deny"' "$OUT" "git branch -D denied"

clear_warnings
OUT=$(run_hook "Bash" '{"command":"git branch -d old-branch"}')
assert_contains '"deny"' "$OUT" "git branch -d denied"

# branch create / list stay allowed
OUT=$(run_hook "Bash" '{"command":"git branch feature"}')
assert_contains '"allow"' "$OUT" "git branch <name> (create) allowed"

OUT=$(run_hook "Bash" '{"command":"git branch --list"}')
assert_contains '"allow"' "$OUT" "git branch --list allowed"

echo ""

# --- G7. git add sweep forms blocked; git add -- <path> allowed ---
echo "--- G7. git add forms ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git add -A"}')
assert_contains '"deny"' "$OUT" "git add -A denied"

clear_warnings
OUT=$(run_hook "Bash" '{"command":"git add -u"}')
assert_contains '"deny"' "$OUT" "git add -u denied"

clear_warnings
OUT=$(run_hook "Bash" '{"command":"git add ."}')
assert_contains '"deny"' "$OUT" "git add . denied"

clear_warnings
OUT=$(run_hook "Bash" '{"command":"git add -p"}')
assert_contains '"deny"' "$OUT" "git add -p denied"

# The ONE allowed write, plus a plain targeted add
OUT=$(run_hook "Bash" '{"command":"git add -- src/foo.ts"}')
assert_contains '"allow"' "$OUT" "git add -- <path> allowed (the one safe write)"

OUT=$(run_hook "Bash" '{"command":"git add -- src/a.ts src/b.ts"}')
assert_contains '"allow"' "$OUT" "git add -- <multiple paths> allowed"

OUT=$(run_hook "Bash" '{"command":"git add src/foo.ts"}')
assert_contains '"allow"' "$OUT" "git add <path> (targeted, no sweep flag) allowed"

echo ""

# --- G8. force branch switch blocked; safe switch allowed ---
echo "--- G8. checkout -f / switch --force ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git checkout -f main"}')
assert_contains '"deny"' "$OUT" "git checkout -f denied"

clear_warnings
OUT=$(run_hook "Bash" '{"command":"git switch --force main"}')
assert_contains '"deny"' "$OUT" "git switch --force denied"

clear_warnings
OUT=$(run_hook "Bash" '{"command":"git switch --discard-changes"}')
assert_contains '"deny"' "$OUT" "git switch --discard-changes denied"

# Safe (non-force) switches: git refuses to clobber a dirty tree, so allow
OUT=$(run_hook "Bash" '{"command":"git switch main"}')
assert_contains '"allow"' "$OUT" "git switch <branch> (safe) allowed"

echo ""

# --- G9. git stash list/show read-only inspection allowed ---
echo "--- G9. git stash inspection ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git stash list"}')
assert_contains '"allow"' "$OUT" "git stash list allowed (read-only)"

OUT=$(run_hook "Bash" '{"command":"git stash show -p"}')
assert_contains '"allow"' "$OUT" "git stash show allowed (read-only)"

echo ""

# --- G10. Read-only git never blocked ---
echo "--- G10. read-only git allowed ---"
clear_warnings

for cmd in "git show HEAD:src/foo.ts" "git rev-parse HEAD" "git reflog" "git fsck" "git diff --stat"; do
  OUT=$(make_bash_json "$cmd" | "$HOOK" 2>/dev/null)
  assert_contains '"allow"' "$OUT" "read-only '$cmd' allowed"
done

echo ""

# --- G11. Robust matching: git -C <dir>, cd && chain, env prefix ---
echo "--- G11. robust prefix/chain matching ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git -C /repo checkout HEAD -- foo.ts"}')
assert_contains '"deny"' "$OUT" "git -C <dir> checkout -- <path> denied"

clear_warnings
OUT=$(make_bash_json 'cd /repo && git checkout -- foo.ts' | "$HOOK" 2>/dev/null)
assert_contains '"deny"' "$OUT" "cd && git checkout -- <path> denied"

clear_warnings
OUT=$(run_hook "Bash" '{"command":"env FOO=1 git reset --hard"}')
assert_contains '"deny"' "$OUT" "env-prefixed git reset --hard denied"

# git -C <dir> status must still pass (read-only, not false-positive)
OUT=$(run_hook "Bash" '{"command":"git -C /repo status"}')
assert_contains '"allow"' "$OUT" "git -C <dir> status allowed (read-only)"

echo ""

# --- G12. Deny message names the specific command + safe alternative ---
echo "--- G12. deny message quality ---"
clear_warnings

OUT=$(run_hook "Bash" '{"command":"git stash push -m wip"}')
assert_contains 'git show HEAD' "$OUT" "deny points to git show HEAD:<path> for baselines"
assert_contains 'git add -- ' "$OUT" "deny points to git add -- <path> as the only write"

echo ""

exit_with_results
