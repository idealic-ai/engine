#!/bin/bash
# test-reap-stray-sessions.sh — the stray-sessions reaper.

set -uo pipefail
PASS=0; FAIL=0
assert_eq() { local l="$1" e="$2" a="$3"; if [ "$e" = "$a" ]; then PASS=$((PASS+1)); echo "  PASS: $l"; else FAIL=$((FAIL+1)); echo "  FAIL: $l"; echo "    expected: $e"; echo "    actual:   $a"; fi; }
assert_dir()   { [ -d "$2" ] && { PASS=$((PASS+1)); echo "  PASS: $1"; } || { FAIL=$((FAIL+1)); echo "  FAIL: $1 (missing $2)"; }; }
assert_nodir() { [ ! -e "$2" ] && { PASS=$((PASS+1)); echo "  PASS: $1"; } || { FAIL=$((FAIL+1)); echo "  FAIL: $1 (still exists $2)"; }; }

REAPER="$HOME/.claude/engine/scripts/reap-stray-sessions.sh"
S=$(mktemp -d); S=$(cd "$S" && pwd -P); trap 'rm -rf "$S"' EXIT
AUDIT="$S/audit"; mkdir -p "$AUDIT"

# --- Layout ---
R="$S/repo"; mkdir -p "$R/.claude/x" "$R/sessions"
# legit root session (must be untouched)
mkdir -p "$R/sessions/keep_root"; echo '{}' > "$R/sessions/keep_root/.state.json"
# stray in a subfolder (no .claude) -> merges to root
mkdir -p "$R/apps/api/sessions/only_stray"; echo '{}' > "$R/apps/api/sessions/only_stray/.state.json"
# collision: same name in stray and root
mkdir -p "$R/apps/web/sessions/dup"; echo '{}' > "$R/apps/web/sessions/dup/.state.json"
mkdir -p "$R/sessions/dup"; echo '{}' > "$R/sessions/dup/.state.json"
# make the STRAY dup newer than the root dup
touch -t 202001010000 "$R/sessions/dup/.state.json"
touch -t 203001010000 "$R/apps/web/sessions/dup/.state.json"
# collision where ROOT is newer -> stray dropped
mkdir -p "$R/apps/api/sessions/older"; echo '{}' > "$R/apps/api/sessions/older/.state.json"
mkdir -p "$R/sessions/older"; echo '{}' > "$R/sessions/older/.state.json"
touch -t 202001010000 "$R/apps/api/sessions/older/.state.json"   # stray older
touch -t 203001010000 "$R/sessions/older/.state.json"            # root newer
# worktree: its own .claude + a stray inside it -> merges into the worktree, NOT root
mkdir -p "$R/.worktrees/wt/.claude" "$R/.worktrees/wt/sessions"
mkdir -p "$R/.worktrees/wt/pkg/sessions/wt_only"; echo '{}' > "$R/.worktrees/wt/pkg/sessions/wt_only/.state.json"
# SAME name in TWO strays, neither in root -> chained collision at apply; keep newer
mkdir -p "$R/apps/a1/sessions/shared"; echo '{}' > "$R/apps/a1/sessions/shared/.state.json"
mkdir -p "$R/apps/a2/sessions/shared"; echo '{}' > "$R/apps/a2/sessions/shared/.state.json"
touch -t 202001010000 "$R/apps/a1/sessions/shared/.state.json"   # older
touch -t 203001010000 "$R/apps/a2/sessions/shared/.state.json"   # newer -> must win

# --- T1: dry-run changes nothing ---
echo "=== T1: dry-run is read-only ==="
"$REAPER" --root "$R" >/dev/null 2>&1
assert_dir  "T1: stray still present after dry-run" "$R/apps/api/sessions/only_stray"

# --- Apply ---
echo "=== apply ==="
"$REAPER" --root "$R" --apply --yes --audit-dir "$AUDIT" >/dev/null 2>&1

echo "=== T2: legit root + worktree sessions untouched ==="
assert_dir   "T2: root keep_root untouched" "$R/sessions/keep_root"
assert_dir   "T2b: worktree own sessions dir intact" "$R/.worktrees/wt/sessions"

echo "=== T3: simple stray moved to root, stray dir removed ==="
assert_dir   "T3: only_stray now at root" "$R/sessions/only_stray"
assert_nodir "T3b: apps/api/sessions removed" "$R/apps/api/sessions"

echo "=== T4: collision, stray newer -> replaced root copy ==="
assert_dir   "T4: dup at root" "$R/sessions/dup"
# root dup should now be the (newer) stray's — verify by mtime year 2030
Y=$(stat -f %Sm -t %Y "$R/sessions/dup/.state.json" 2>/dev/null || date -r "$(stat -c %Y "$R/sessions/dup/.state.json")" +%Y)
assert_eq    "T4b: root dup replaced with newer stray (2030)" "2030" "$Y"
assert_nodir "T4c: apps/web/sessions removed" "$R/apps/web/sessions"

echo "=== T5: collision, target newer -> stray dropped, root kept ==="
Y2=$(stat -f %Sm -t %Y "$R/sessions/older/.state.json" 2>/dev/null || date -r "$(stat -c %Y "$R/sessions/older/.state.json")" +%Y)
assert_eq    "T5: root 'older' kept (2030, newer)" "2030" "$Y2"

echo "=== T6: worktree stray merges into the worktree, not the main root ==="
assert_dir   "T6: wt_only in worktree sessions" "$R/.worktrees/wt/sessions/wt_only"
assert_nodir "T6b: wt_only NOT in main root" "$R/sessions/wt_only"
assert_nodir "T6c: worktree subfolder sessions removed" "$R/.worktrees/wt/pkg/sessions"

echo "=== T8: two strays same name (none in root) -> newer wins, no collision ==="
assert_dir "T8: shared landed at root" "$R/sessions/shared"
Y3=$(stat -f %Sm -t %Y "$R/sessions/shared/.state.json" 2>/dev/null || date -r "$(stat -c %Y "$R/sessions/shared/.state.json")" +%Y)
assert_eq  "T8b: newer stray (2030) won the chained collision" "2030" "$Y3"
assert_nodir "T8c: apps/a1/sessions removed" "$R/apps/a1/sessions"
assert_nodir "T8d: apps/a2/sessions removed" "$R/apps/a2/sessions"

echo "=== T7: audit written ==="
assert_eq    "T7: audit jsonl has entries" "yes" "$([ -s "$AUDIT"/reap-stray-sessions-*.jsonl ] && echo yes || echo no)"

echo ""
echo "======================================="
echo "Results: $PASS passed, $FAIL failed"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
