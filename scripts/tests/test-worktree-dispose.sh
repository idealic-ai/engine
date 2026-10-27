#!/bin/bash
# test-worktree-dispose.sh — Tests for the worktree disposal ceremony.
#
# Every refusal the script makes is written as a PAIR of arms differing only in
# the guarded condition, so none of them can pass vacuously. Set
# WORKTREE_UNDER_TEST to a mutated copy to plant a broken guard and watch the
# matching arm redden.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SCRIPT="${WORKTREE_UNDER_TEST:-$HOME/.claude/engine/scripts/worktree.sh}"

# ── fixture ─────────────────────────────────────────────────────────────────
#
# One throwaway repo with six registered worktrees, one lookalike directory, and
# four shapes of install:
#
#   wt-clean    healthy, clean, REAL install (one file)
#   wt-dirty    healthy, one UNTRACKED file, install is a SYMLINK
#   wt-locked   healthy, locked
#   wt-broken   directory present, .git file removed            → broken
#   wt-gone     registered, directory removed                   → dangling
#   wt-skel     healthy, install is directories with no files   → skeleton
#   wt-farm     healthy, install is mostly symlinks             → farm
#   lookalike   an ordinary untracked directory, NOT registered

setup() {
  setup_test_env "test_worktree"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

  FIX="$(cd "$TMP_DIR" && pwd -P)/fix"
  mkdir -p "$FIX"
  REPO="$FIX/repo"

  git init -q "$REPO"
  printf 'node_modules/\n' > "$REPO/.gitignore"
  printf 'hello\n' > "$REPO/file.txt"
  git -C "$REPO" add -- .gitignore file.txt
  git -C "$REPO" commit -qm init

  local w
  for w in clean dirty locked broken gone skel farm; do
    git -C "$REPO" worktree add -q "$FIX/wt-$w" -b "b-$w" >/dev/null 2>&1
  done

  # wt-clean: a real install — >=10 top-level entries AND it holds files.
  # Fewer than 10 entries classifies as trivial, which is a different class.
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    mkdir -p "$FIX/wt-clean/node_modules/pkg$i"
    printf 'x\n' > "$FIX/wt-clean/node_modules/pkg$i/index.js"
  done

  # wt-dirty: untracked content, and an install that is a symlink
  printf 'unreviewed\n' > "$FIX/wt-dirty/scratch-notes.txt"
  mkdir -p "$FIX/store"
  printf 'y\n' > "$FIX/store/keep.js"
  ln -s "$FIX/store" "$FIX/wt-dirty/node_modules"

  # wt-skel: 20 directories, zero files
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    mkdir -p "$FIX/wt-skel/node_modules/d$i"
  done

  # wt-farm: 20 top-level entries, all symlinks
  mkdir -p "$FIX/wt-farm/node_modules"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    ln -s "$FIX/store" "$FIX/wt-farm/node_modules/l$i"
  done

  git -C "$REPO" worktree lock --reason "lane in progress" "$FIX/wt-locked" >/dev/null 2>&1

  # broken: the directory stays, its .git FILE goes
  rm -f "$FIX/wt-broken/.git"
  # dangling: the directory goes, the registration stays
  rm -rf "$FIX/wt-gone"

  mkdir -p "$FIX/lookalike"
  # The prefix trap: a sibling whose path begins with a registered path.
  mkdir -p "$FIX/wt-clean-extra"
}

teardown() { cleanup_test_env; }

# Runs the script against the fixture repo and echoes stdout+stderr.
#
# The exit code goes to a FILE, not a variable: every call site is itself a
# command substitution, so a variable set here dies with the subshell. Read it
# back with wt_rc. And a pipeline's $? is its LAST command's, so the capture is
# to a variable first — never through head/tail.
wt() {
  local out
  out=$(bash "$SCRIPT" --repo "$REPO" "$@" 2>&1)
  printf '%s' "$?" > "$FIX/.rc"
  printf '%s\n' "$out"
}

wt_rc() { cat "$FIX/.rc" 2>/dev/null || printf 'norc'; }

# ── the registration check (¶PTF_AN_UNTRACKED_DIRECTORY_MAY_BE_A_WORKTREE) ──

test_check_pair_registered_vs_lookalike() {
  local a b
  a=$(wt check "$FIX/wt-clean"); local rc_a; rc_a=$(wt_rc)
  b=$(wt check "$FIX/lookalike"); local rc_b; rc_b=$(wt_rc)

  assert_contains "REGISTERED" "$a" "REG-01: a registered worktree reports REGISTERED"
  assert_eq "0" "$rc_a" "REG-02: check exits 0 on a registered path"
  assert_contains "not a registered worktree" "$b" \
    "REG-03: an ordinary untracked directory reports not-registered"
  assert_eq "1" "$rc_b" "REG-04: check exits 1 on an unregistered path"
}
run_test test_check_pair_registered_vs_lookalike

test_check_rejects_prefix_of_registered_path() {
  # $FIX/wt-cl is a strict PREFIX of the registered $FIX/wt-clean. A grep that
  # is not anchored whole-line matches the registered path's porcelain line and
  # declares this path registered — which is how a removal reaches a tree the
  # operator never named.
  local pre ext
  pre=$(wt check "$FIX/wt-cl")
  ext=$(wt check "$FIX/wt-clean-extra")
  assert_contains "not a registered worktree" "$pre" \
    "REG-05: a strict PREFIX of a registered path is not registered (whole-line fixed grep)"
  assert_contains "not a registered worktree" "$ext" \
    "REG-06: nor is a sibling whose name EXTENDS a registered one"
}
run_test test_check_rejects_prefix_of_registered_path

# ── dry run is the default ──────────────────────────────────────────────────

test_drop_install_dry_run_pair() {
  local out
  out=$(wt drop-install "$FIX/wt-clean")
  assert_contains "MiB" "$out" "DRY-00: a named path does report its size"
  assert_contains "would drop" "$out" "DRY-01: drop-install without --apply only says what it would do"
  assert_dir_exists "$FIX/wt-clean/node_modules" "DRY-02: and the install is still there"

  out=$(wt drop-install --apply "$FIX/wt-clean")
  assert_contains "dropped" "$out" "DRY-03: with --apply it drops"
  if [ -d "$FIX/wt-clean/node_modules" ]; then
    fail "DRY-04: --apply removes the install" "gone" "still present"
  else
    pass "DRY-04: --apply removes the install"
  fi
}
run_test test_drop_install_dry_run_pair

test_remove_tree_dry_run_pair() {
  local out
  out=$(wt remove-tree "$FIX/wt-clean")
  assert_contains "would remove" "$out" "DRY-05: remove-tree without --apply only says what it would do"
  assert_dir_exists "$FIX/wt-clean" "DRY-06: and the tree is still there"

  out=$(wt remove-tree --apply "$FIX/wt-clean")
  assert_contains "removed" "$out" "DRY-07: with --apply it removes"
  if [ -d "$FIX/wt-clean" ]; then
    fail "DRY-08: --apply removes the tree" "gone" "still present"
  else
    pass "DRY-08: --apply removes the tree"
  fi
}
run_test test_remove_tree_dry_run_pair

# ── remove-tree refuses uncommitted or untracked content ────────────────────
#
# The pair: wt-clean and wt-dirty are identical worktrees of the same repo. The
# only difference is one untracked file.

test_remove_tree_untracked_pair() {
  local clean dirty
  clean=$(wt remove-tree --apply "$FIX/wt-clean")
  dirty=$(wt remove-tree --apply "$FIX/wt-dirty"); local rc_dirty; rc_dirty=$(wt_rc)

  assert_contains "removed" "$clean" "TREE-01: the clean arm removes"
  assert_contains "REFUSED" "$dirty" "TREE-02: the arm that differs ONLY by an untracked file refuses"
  assert_contains "uncommitted or untracked" "$dirty" "TREE-03: and says why"
  assert_eq "2" "$rc_dirty" "TREE-04: a refusal exits 2"
  assert_dir_exists "$FIX/wt-dirty" "TREE-05: the refused tree is intact"
  assert_file_exists "$FIX/wt-dirty/scratch-notes.txt" "TREE-06: and so is its untracked file"
}
run_test test_remove_tree_untracked_pair

test_remove_tree_tracked_modification_refuses() {
  printf 'edited\n' > "$FIX/wt-clean/file.txt"
  local out
  out=$(wt remove-tree --apply "$FIX/wt-clean")
  assert_contains "REFUSED" "$out" "TREE-07: a tracked modification refuses too"
  assert_dir_exists "$FIX/wt-clean" "TREE-08: and the tree survives"
}
run_test test_remove_tree_tracked_modification_refuses

# ── remove-tree refuses a locked tree ──────────────────────────────────────

test_remove_tree_locked_pair() {
  local unlocked locked
  unlocked=$(wt remove-tree --apply "$FIX/wt-clean")
  locked=$(wt remove-tree --apply "$FIX/wt-locked")

  assert_contains "removed" "$unlocked" "LOCK-01: the unlocked arm removes"
  # "REFUSED" and even the word "locked" also appear when git's OWN guard fires,
  # so this must assert the wording only our check produces.
  assert_contains "unlock deliberately first" "$locked" \
    "LOCK-02: the arm that differs ONLY by a lock refuses, in our own words"
  assert_not_contains "worktree remove failed" "$locked" \
    "LOCK-03: and refuses before git is reached at all"
  assert_dir_exists "$FIX/wt-locked" "LOCK-04: the locked tree is intact"
}
run_test test_remove_tree_locked_pair

# ── remove-tree refuses an unregistered path and the main worktree ──────────

test_remove_tree_refuses_unregistered() {
  local out
  out=$(wt remove-tree --apply "$FIX/lookalike")
  # Same trap: git also fails on a path it does not know. Assert our wording.
  assert_contains "not a registered worktree" "$out" \
    "UNREG-01: remove-tree refuses a path that is not a registered worktree"
  assert_not_contains "worktree remove failed" "$out" \
    "UNREG-03: and refuses before git is reached at all"
  assert_dir_exists "$FIX/lookalike" "UNREG-02: and leaves the directory alone"
}
run_test test_remove_tree_refuses_unregistered

test_refuses_main_worktree() {
  local rt di
  rt=$(wt remove-tree --apply "$REPO")
  di=$(wt drop-install --apply "$REPO")
  assert_contains "MAIN worktree" "$rt" "MAIN-01: remove-tree refuses the main worktree"
  assert_contains "MAIN worktree" "$di" "MAIN-02: drop-install refuses the main worktree"
  assert_dir_exists "$REPO" "MAIN-03: the main clone is intact"
}
run_test test_refuses_main_worktree

# ── remove-tree refuses a broken registration ──────────────────────────────

test_remove_tree_broken_pair() {
  local healthy broken
  healthy=$(wt remove-tree --apply "$FIX/wt-clean")
  broken=$(wt remove-tree --apply "$FIX/wt-broken")

  assert_contains "removed" "$healthy" "BROK-01: the healthy arm removes"
  assert_contains "REFUSED" "$broken" "BROK-02: the arm whose .git FILE is gone refuses"
  assert_contains "repair" "$broken" "BROK-03: and points at repair"
  assert_dir_exists "$FIX/wt-broken" "BROK-04: the broken tree's contents are intact"
}
run_test test_remove_tree_broken_pair

test_remove_tree_refuses_dangling() {
  local out
  out=$(wt remove-tree --apply "$FIX/wt-gone")
  assert_contains "REFUSED" "$out" "DANG-01: remove-tree refuses a dangling registration"
  assert_contains "dangling" "$out" "DANG-02: and names it as dangling, not broken"
}
run_test test_remove_tree_refuses_dangling

# ── drop-install refuses a symlinked install ───────────────────────────────

test_drop_install_symlink_pair() {
  local real sym
  real=$(wt drop-install --apply "$FIX/wt-clean")
  sym=$(wt drop-install --apply "$FIX/wt-dirty")

  assert_contains "dropped" "$real" "SYM-01: a real install drops"
  assert_contains "REFUSED" "$sym" "SYM-02: the arm whose node_modules is a SYMLINK refuses"
  assert_symlink "$FIX/wt-dirty/node_modules" "SYM-03: the symlink is intact"
  assert_file_exists "$FIX/store/keep.js" "SYM-04: and the store it points at was never reached"
}
run_test test_drop_install_symlink_pair

# ── repair before prune ─────────────────────────────────────────────────────

test_prune_refuses_while_broken_then_allows_after_repair() {
  local before
  before=$(wt prune --apply); local rc_before; rc_before=$(wt_rc)
  assert_contains "REFUSED" "$before" "ORDER-01: prune refuses while a broken registration exists"
  assert_contains "DEREGISTER" "$before" "ORDER-02: and says what prune would have done to it"
  assert_eq "2" "$rc_before" "ORDER-03: that refusal exits 2"

  # The broken arm is still registered — prune did not run.
  local still
  still=$(git -C "$REPO" worktree list --porcelain | grep -cxF "worktree $FIX/wt-broken" || true)
  assert_eq "1" "$(printf '%s' "$still" | head -1)" \
    "ORDER-04: the broken registration survived the refused prune"

  wt repair --apply > /dev/null

  local after
  after=$(wt prune --apply); local rc_after; rc_after=$(wt_rc)
  assert_contains "No broken registrations" "$after" "ORDER-05: after repair, prune is allowed"
  assert_eq "0" "$rc_after" "ORDER-06: and exits 0"

  # And the dangling one is what prune cleared.
  local gone
  gone=$(git -C "$REPO" worktree list --porcelain | grep -cxF "worktree $FIX/wt-gone" || true)
  assert_eq "0" "$(printf '%s' "$gone" | head -1)" \
    "ORDER-07: the DANGLING registration is the one prune cleared"
}
run_test test_prune_refuses_while_broken_then_allows_after_repair

test_repair_is_dry_run_by_default() {
  local out
  out=$(wt repair)
  assert_contains "Dry run" "$out" "ORDER-08: repair without --apply is a dry run"
  local out2
  out2=$(wt prune --apply)
  assert_contains "REFUSED" "$out2" "ORDER-09: and the broken registration is still broken afterwards"
}
run_test test_repair_is_dry_run_by_default

# ── census ──────────────────────────────────────────────────────────────────

test_census_counts_health_classes() {
  local out
  out=$(wt census)
  # 1 main + 7 added - 0 removed = 8 registrations; wt-gone dangling, wt-broken broken.
  assert_contains "Registrations: 8" "$out" "CEN-01: census counts every registration"
  assert_contains "dangling      1" "$out" "CEN-02: the absent path counts as dangling"
  assert_contains "broken        1" "$out" "CEN-03: the present-but-.git-less path counts as broken"
  assert_contains "healthy       6" "$out" "CEN-04: the rest are healthy"
  assert_contains "locked        1" "$out" "CEN-05: and the lock is reported separately, not as a guard"
  # The hazard, live: one path is absent and one is merely .git-less, and git
  # calls BOTH prunable. That gap is the whole reason prune is gated on repair.
  assert_contains "prunable      2" "$out" \
    "CEN-12: git reports 2 prunable against 1 dangling — it counts the broken one too"
}
run_test test_census_counts_health_classes

test_census_separates_install_classes() {
  local out
  out=$(wt census)
  assert_contains "real             1" "$out" "CEN-06: an install holding a file is real"
  assert_contains "skeleton         1" "$out" "CEN-07: directories with no files are a skeleton, not an install"
  assert_contains "symlink-farm     1" "$out" "CEN-08: a mostly-symlink install is a farm"
  assert_contains "EXTRAPOLATED" "$out" "CEN-09: the reclaimable figure says it is extrapolated"
  assert_not_contains "node_modules directories" "$out" \
    "CEN-10: and it is never framed as a count of node_modules"
}
run_test test_census_separates_install_classes

test_census_is_the_default_action() {
  local out
  out=$(wt)
  assert_contains "Registrations:" "$out" "CEN-11: the bare command runs the read-only census"
}
run_test test_census_is_the_default_action

test_census_counts_zero_without_the_grep_c_trap() {
  # A repo with no locked and no prunable worktrees: `grep -c` prints 0 and
  # EXITS 1 there, and an unguarded capture yields "0\n0" that breaks the next
  # arithmetic test. This arm exists to make that regression loud.
  local bare="$FIX/bare"
  git init -q "$bare"
  printf 'x\n' > "$bare/f"
  git -C "$bare" add -- f
  git -C "$bare" commit -qm init
  local out
  out=$(bash "$SCRIPT" --repo "$bare" census 2>&1); local rc=$?
  assert_eq "0" "$rc" "GREPC-01: census over a repo with zero locked/prunable exits 0"
  assert_contains "locked        0" "$out" "GREPC-02: and prints a single 0 for locked"
  assert_contains "prunable      0" "$out" "GREPC-03: and a single 0 for prunable"
  # The one assertion that can SEE the pathology. `grep -c x || echo 0` yields a
  # two-line "0\n0", and the formatted line still prints "locked 0" — the only
  # trace is printf rejecting the value on stderr.
  assert_not_contains "invalid number" "$out" \
    "GREPC-04: and the count reaching printf is a single number, not \"0\\n0\""
}
run_test test_census_counts_zero_without_the_grep_c_trap

# ── drop-install refuses a locked worktree ─────────────────────────────────
#
# The pair: wt-clean and wt-locked differ only in the lock. Both are healthy
# worktrees of the same repo. A lock does not protect against prune, but it is a
# claim on the tree — dropping the install under a running lane breaks its build.

test_drop_install_locked_pair() {
  mkdir -p "$FIX/wt-locked/node_modules/pkg1"
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    mkdir -p "$FIX/wt-locked/node_modules/pkg$i"
    printf 'x\n' > "$FIX/wt-locked/node_modules/pkg$i/index.js"
  done

  local unlocked locked
  unlocked=$(wt drop-install --apply "$FIX/wt-clean")
  locked=$(wt drop-install --apply "$FIX/wt-locked")

  assert_contains "dropped" "$unlocked" "DILOCK-01: the unlocked arm drops"
  assert_contains "REFUSED" "$locked" "DILOCK-02: the arm that differs ONLY by a lock refuses"
  assert_contains "mid-run" "$locked" "DILOCK-03: and says a lane may be mid-run"
  assert_dir_exists "$FIX/wt-locked/node_modules" "DILOCK-04: the locked install is intact"

  local forced
  forced=$(wt drop-install --apply --include-locked "$FIX/wt-locked")
  assert_contains "dropped" "$forced" "DILOCK-05: --include-locked overrides it deliberately"
}
run_test test_drop_install_locked_pair

# ── --all targets the real installs and nothing else ───────────────────────

test_drop_install_all_selects_only_real_unlocked() {
  local out
  out=$(wt drop-install --all)
  # The pattern must not start with "-": assert_contains hands it to grep -qF
  # without a "--" terminator, so a leading dash is parsed as a flag.
  assert_contains "selected 1 worktree(s) whose install holds files" "$out" \
    "ALL-01: --all picks the one real, unlocked, non-main install"
  assert_contains "would drop" "$out" "ALL-02: and is still a dry run"
  assert_dir_exists "$FIX/wt-clean/node_modules" "ALL-03: nothing was removed"
  assert_dir_exists "$FIX/wt-skel/node_modules" "ALL-04: the skeleton was not selected"
  assert_symlink "$FIX/wt-dirty/node_modules" "ALL-05: nor the symlinked install"

  # A locked tree with a real install is not SELECTED, not merely refused:
  # selecting it would make --all --apply exit 2 on a fleet where most
  # worktrees carry a lane's lock.
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    mkdir -p "$FIX/wt-locked/node_modules/pkg$i"
    printf 'x\n' > "$FIX/wt-locked/node_modules/pkg$i/index.js"
  done
  local still forced
  still=$(wt drop-install --all)
  assert_contains "selected 1 worktree(s)" "$still" \
    "ALL-06: a locked worktree with a real install is not selected"
  forced=$(wt drop-install --all --include-locked)
  assert_contains "selected 2 worktree(s)" "$forced" \
    "ALL-07: and --include-locked brings it in"

  # du over the real population is slow, so --all does not measure per path.
  assert_contains "size unmeasured" "$still" \
    "ALL-08: and --all does not du every target"
  local measured
  measured=$(wt drop-install --all --measure)
  assert_contains "MiB" "$measured" "ALL-09: unless --measure asks it to"
}
run_test test_drop_install_all_selects_only_real_unlocked

test_census_offers_the_install_drop() {
  local out
  out=$(wt census)
  assert_contains "drop-install --all" "$out" \
    "OFFER-01: census ends by naming the safe disposal as a runnable command"
  assert_contains "The safe disposal is the install, not the tree" "$out" \
    "OFFER-02: and says which disposal it is offering"
  assert_not_contains "remove-tree --all" "$out" \
    "OFFER-03: census never offers a population-wide tree removal"
}
run_test test_census_offers_the_install_drop

# ── a guard must not read its answer from a pipeline's status ──────────────
#
# This is the bug an 8-worktree fixture CANNOT reproduce: `grep -q` exits on its
# first match, and once the listing exceeds the pipe buffer the writer is still
# writing, takes SIGPIPE, dies 141, and pipefail hands that back as the answer.
# An early match then reads as "no match" while a late one works. Found by
# running the real thing against a 345-worktree clone, where it refused 136 of
# 171 registered paths.

test_a_guard_never_reads_a_pipelines_status() {
  local big="$FIX/big-porcelain.txt"
  awk 'BEGIN{for(i=0;i<1500;i++) printf "worktree /p/w%06d\nHEAD 0123456789abcdef\nbranch refs/heads/b%06d\n\n", i, i}' > "$big"
  assert_gt "$(wc -c < "$big" | tr -d ' ')" 65536 "PIPE-01: the fixture listing exceeds the pipe buffer"

  # The shape that was in the script: status read through an early-exiting grep.
  local bad
  bad=$(bash -c 'set -o pipefail; cat "$1" | grep -qxF "worktree /p/w000000"; echo $?' _ "$big")
  assert_neq "0" "$bad" \
    "PIPE-02: the grep -q shape reports failure for a match that IS present"

  # The shape the script uses now: capture, then test for emptiness.
  local good
  good=$(bash -c 'set -o pipefail; o=$(cat "$1" | grep -xF "worktree /p/w000000"); [ -n "$o" ]; echo $?' _ "$big")
  assert_eq "0" "$good" "PIPE-03: the capture-and-test shape answers from the data"

  # And the script must not contain the bad shape anywhere.
  local code
  code=$(sed 's/[[:space:]]*#.*$//' "$SCRIPT")
  assert_not_contains "grep -q" "$code" \
    "PIPE-04: no guard in the script reads its answer through grep -q"
}
run_test test_a_guard_never_reads_a_pipelines_status

# ── the tree is never removed with rm -rf ───────────────────────────────────

test_remove_tree_uses_git_worktree_remove() {
  local body
  # Comments stripped first: a comment that NAMES rm -rf is not an rm -rf, and a
  # text pattern over raw source cannot tell the difference.
  body=$(awk '/^cmd_remove_tree\(\)/{inside=1} inside{print} inside && /^}$/{exit}' "$SCRIPT" \
         | sed 's/[[:space:]]*#.*$//')
  assert_contains "git -C \"\$REPO\" worktree remove" "$body" \
    "RMRF-01: remove-tree removes through git worktree remove"
  assert_not_contains "rm -rf" "$body" \
    "RMRF-02: and the remove-tree path contains no rm -rf"
}
run_test test_remove_tree_uses_git_worktree_remove

exit_with_results
