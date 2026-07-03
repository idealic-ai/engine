#!/bin/bash
# test-find-project-root.sh — Repo-anchoring via the .claude/ marker.
#
# find_project_root walks up from a start dir to the nearest ancestor containing
# a .claude/ directory, so session resolution is stable regardless of the current
# subfolder (fixes `cd` into a subfolder breaking the statusline / forking a stray
# sessions/ dir). resolve_sessions_dir returns that root's sessions/, absolute.

set -uo pipefail

PASS=0; FAIL=0
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then PASS=$((PASS+1)); echo "  PASS: $label"
  else FAIL=$((FAIL+1)); echo "  FAIL: $label"; echo "    expected: $expected"; echo "    actual:   $actual"; fi
}

source "$HOME/.claude/engine/scripts/lib.sh"

SANDBOX=$(mktemp -d)
# Resolve symlinks (macOS /var -> /private/var) so comparisons match pwd -P output.
SANDBOX=$(cd "$SANDBOX" && pwd -P)
trap 'rm -rf "$SANDBOX"' EXIT

# Layout:
#   $SANDBOX/repo/.claude              (repo root marker)
#   $SANDBOX/repo/apps/api             (deep subfolder, no .claude)
#   $SANDBOX/repo/.worktrees/wt/.claude (worktree = its own root)
#   $SANDBOX/repo/.worktrees/wt/pkg    (subfolder inside worktree)
#   $SANDBOX/bare                      (no .claude anywhere above -> none)
mkdir -p "$SANDBOX/repo/.claude"
mkdir -p "$SANDBOX/repo/apps/api"
mkdir -p "$SANDBOX/repo/.worktrees/wt/.claude"
mkdir -p "$SANDBOX/repo/.worktrees/wt/pkg"
mkdir -p "$SANDBOX/bare/sub"

echo "=== F1: repo root resolves to itself ==="
assert_eq "F1: root -> root" "$SANDBOX/repo" "$(find_project_root "$SANDBOX/repo")"

echo "=== F2: deep subfolder walks up to repo root ==="
assert_eq "F2: apps/api -> repo" "$SANDBOX/repo" "$(find_project_root "$SANDBOX/repo/apps/api")"

echo "=== F3: worktree anchors to itself, not the parent repo ==="
assert_eq "F3: worktree root -> worktree" "$SANDBOX/repo/.worktrees/wt" "$(find_project_root "$SANDBOX/repo/.worktrees/wt")"
assert_eq "F3b: worktree subfolder -> worktree" "$SANDBOX/repo/.worktrees/wt" "$(find_project_root "$SANDBOX/repo/.worktrees/wt/pkg")"

echo "=== F4: no .claude marker -> returns 1 (caller falls back to PWD) ==="
if find_project_root "$SANDBOX/bare/sub" >/dev/null 2>&1; then RC=0; else RC=1; fi
assert_eq "F4: bare dir returns non-zero" "1" "$RC"

echo "=== F5: resolve_sessions_dir is the anchored root's sessions/ (absolute) ==="
assert_eq "F5: anchored sessions dir" "$SANDBOX/repo/sessions" "$(cd "$SANDBOX/repo/apps/api" && resolve_sessions_dir)"
assert_eq "F5b: worktree sessions dir" "$SANDBOX/repo/.worktrees/wt/sessions" "$(cd "$SANDBOX/repo/.worktrees/wt/pkg" && resolve_sessions_dir)"

echo "=== F6: no marker -> resolve_sessions_dir falls back to PWD/sessions ==="
assert_eq "F6: fallback sessions dir" "$SANDBOX/bare/sub/sessions" "$(cd "$SANDBOX/bare/sub" && resolve_sessions_dir)"

echo ""
echo "======================================="
echo "Results: $PASS passed, $FAIL failed"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
