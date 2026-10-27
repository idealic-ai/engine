#!/bin/bash
# ~/.claude/engine/scripts/tests/test-reap-stale-temps.sh — Unit tests for _reap_stale_temps
#
# The atomic write is `write FILE.tmp.$$` then `mv`. A writer SIGKILLed between the two
# leaves a COMPLETE temp behind; no failure-path `rm -f` and no EXIT trap reclaims it.
# _reap_stale_temps defers reclaim to the next writer under the lock: a temp whose pid
# is no longer alive has no writer left to mv it.
#
# Covers the reaper directly plus its two lib.sh call sites (safe_json_write,
# safe_json_update), and pins the `if`-form against a `set -e` caller.
#
# Liveness is NOT `kill -0`'s exit status: that fails with EPERM for a process that
# exists but belongs to another user, so a status-only check reads a live foreign-owned
# writer as dead. The EPERM section pins `_pid_is_alive` and its fail-safe.
#
# Run: bash ~/.claude/engine/scripts/tests/test-reap-stale-temps.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

# Captured at file scope, before any setup() runs. run_test() calls setup() itself AND
# each test calls it again (the house pattern in test-lib.sh), so a HOME read inside a
# test body is a fake home and $ORIGINAL_HOME is the OUTER fake home, not the real one.
REAL_HOME="$HOME"
LIB_SH="$REAL_HOME/.claude/scripts/lib.sh"
ENGINE_HOOKS="$REAL_HOME/.claude/engine/hooks"

# A pid above the darwin pid ceiling (99998) can never be live.
IMPOSSIBLE_PID=99999999

TEST_DIR=""
ORIGINAL_HOME=""
ALIVE_PID=""

setup() {
  TEST_DIR=$(mktemp -d)
  ORIGINAL_HOME="$HOME"
  export HOME="$TEST_DIR/fake-home"
  mkdir -p "$HOME/.claude/scripts"
  ln -sf "$LIB_SH" "$HOME/.claude/scripts/lib.sh"
  unset _LIB_SH_LOADED
  source "$HOME/.claude/scripts/lib.sh"
  ALIVE_PID=""
}

teardown() {
  if [ -n "$ALIVE_PID" ]; then
    kill "$ALIVE_PID" 2>/dev/null || true
    wait "$ALIVE_PID" 2>/dev/null || true
    ALIVE_PID=""
  fi
  export HOME="$ORIGINAL_HOME"
  unset _LIB_SH_LOADED
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# Spawn a real sleeping process; its pid lands in $ALIVE_PID (also used by teardown).
# Must NOT be called via $(...): a background child started inside a command-substitution
# subshell is reaped when that subshell exits, so the pid would be dead immediately.
spawn_alive() {
  sleep 30 &
  ALIVE_PID=$!
}

# A pid that genuinely existed and has been reaped — the realistic dead-writer case.
# The command-substitution subshell reaping its own child is what makes this reliable.
reaped_pid() {
  local p
  ( exit 0 ) &
  p=$!
  wait "$p" 2>/dev/null || true
  echo "$p"
}

# =============================================================================
# DEAD PID — REAPED
# =============================================================================

test_reap_dead_pid_impossible() {
  local test_name="_reap_stale_temps: temp with an impossible pid is reaped"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  local orphan="$target.tmp.$IMPOSSIBLE_PID"
  echo '{"orphan":true}' > "$orphan"

  _reap_stale_temps "$target"

  assert_file_not_exists "$orphan" "$test_name"

  teardown
}

test_reap_dead_pid_reaped_child() {
  local test_name="_reap_stale_temps: temp whose writer has exited is reaped"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  local pid
  pid=$(reaped_pid)

  if kill -0 "$pid" 2>/dev/null; then
    # pid was recycled between wait and here — the precondition is gone, not a code fault.
    skip "$test_name" "pid $pid was recycled"
    teardown
    return 0
  fi

  local orphan="$target.tmp.$pid"
  echo '{"orphan":true}' > "$orphan"

  _reap_stale_temps "$target"

  assert_file_not_exists "$orphan" "$test_name"

  teardown
}

test_reap_multiple_dead_in_one_pass() {
  local test_name="_reap_stale_temps: every dead temp goes in a single pass"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  echo 'a' > "$target.tmp.99999991"
  echo 'b' > "$target.tmp.99999992"
  echo 'c' > "$target.tmp.99999993"

  _reap_stale_temps "$target"

  # ls -A, not ls: the fixtures are dotfiles and a bare ls would never see them,
  # which would make this assertion pass against any implementation.
  local remaining
  remaining=$(ls -A "$TEST_DIR" | grep -c 'tmp\.' || true)
  assert_eq "0" "$remaining" "$test_name"

  teardown
}

# =============================================================================
# LIVE PID — LEFT ALONE
# =============================================================================

test_keep_live_pid() {
  local test_name="_reap_stale_temps: temp with a LIVE pid is left alone"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  spawn_alive
  local inflight="$target.tmp.$ALIVE_PID"
  echo '{"inflight":true}' > "$inflight"

  if ! kill -0 "$ALIVE_PID" 2>/dev/null; then
    fail "$test_name" "fixture pid $ALIVE_PID alive" "fixture process died before the reap"
    teardown
    return 0
  fi

  _reap_stale_temps "$target"

  assert_file_exists "$inflight" "$test_name"

  teardown
}

test_keep_own_pid() {
  local test_name="_reap_stale_temps: temp named with the caller's own \$\$ is left alone"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  local mine="$target.tmp.$$"
  echo '{"mine":true}' > "$mine"

  _reap_stale_temps "$target"

  assert_file_exists "$mine" "$test_name"

  teardown
}

test_mixed_live_and_dead() {
  local test_name="_reap_stale_temps: dead goes, live stays, in the same pass"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  spawn_alive
  echo 'dead' > "$target.tmp.$IMPOSSIBLE_PID"
  echo 'alive' > "$target.tmp.$ALIVE_PID"

  _reap_stale_temps "$target"

  if [ ! -f "$target.tmp.$IMPOSSIBLE_PID" ] && [ -f "$target.tmp.$ALIVE_PID" ]; then
    pass "$test_name"
  else
    fail "$test_name" "dead removed, live kept" "$(ls -A "$TEST_DIR" | tr '\n' ' ')"
  fi

  teardown
}

# =============================================================================
# EPERM — A LIVE PROCESS WE MAY NOT SIGNAL IS STILL LIVE
# =============================================================================
# `kill -0` fails with EPERM when the process EXISTS but belongs to another user, and
# only ESRCH means gone. Both are exit 1, so a status-only check reads a live
# foreign-owned writer as dead and deletes its in-flight temp. pid 1 (launchd) is the
# canonical EPERM here: root-owned, always present, never ours.

# True when pid 1 reproduces the EPERM shape: exists, but we may not signal it.
# A root session (or a platform where kill -0 1 succeeds) has no EPERM to simulate.
eperm_pid_available() {
  ps -p 1 >/dev/null 2>&1 || return 1
  kill -0 1 2>/dev/null && return 1
  return 0
}

test_keep_eperm_pid_foreign_owner() {
  local test_name="_reap_stale_temps: temp whose pid is live but UNSIGNALLABLE (EPERM) is left alone"
  setup

  if ! eperm_pid_available; then
    skip "$test_name" "no EPERM pid available (running as root, or kill -0 1 succeeds here)"
    teardown
    return 0
  fi

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  # pid 1 exists and is root-owned: `kill -0 1` returns 1 with EPERM, not ESRCH.
  local inflight="$target.tmp.1"
  echo '{"inflight":true}' > "$inflight"

  _reap_stale_temps "$target"

  assert_file_exists "$inflight" "$test_name"

  teardown
}

test_pid_is_alive_discriminates_eperm_from_esrch() {
  local test_name="_pid_is_alive: EPERM reads alive, ESRCH reads dead, own \$\$ reads alive"
  setup

  if ! eperm_pid_available; then
    skip "$test_name" "no EPERM pid available (running as root, or kill -0 1 succeeds here)"
    teardown
    return 0
  fi

  local eperm_rc=0 esrch_rc=0 self_rc=0
  _pid_is_alive 1 || eperm_rc=$?
  _pid_is_alive "$IMPOSSIBLE_PID" || esrch_rc=$?
  _pid_is_alive "$$" || self_rc=$?

  if [ "$eperm_rc" -eq 0 ] && [ "$esrch_rc" -ne 0 ] && [ "$self_rc" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "eperm=0, esrch!=0, self=0" \
      "eperm=$eperm_rc, esrch=$esrch_rc, self=$self_rc"
  fi

  teardown
}

test_mixed_dead_and_eperm() {
  local test_name="_reap_stale_temps: dead goes, EPERM-live stays, in the same pass"
  setup

  if ! eperm_pid_available; then
    skip "$test_name" "no EPERM pid available (running as root, or kill -0 1 succeeds here)"
    teardown
    return 0
  fi

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  echo 'dead' > "$target.tmp.$IMPOSSIBLE_PID"
  echo 'eperm' > "$target.tmp.1"

  _reap_stale_temps "$target"

  if [ ! -f "$target.tmp.$IMPOSSIBLE_PID" ] && [ -f "$target.tmp.1" ]; then
    pass "$test_name"
  else
    fail "$test_name" "dead removed, EPERM temp kept" "$(ls -A "$TEST_DIR" | tr '\n' ' ')"
  fi

  teardown
}

test_safe_json_write_keeps_eperm_orphan() {
  local test_name="safe_json_write: an EPERM-live writer's temp survives the reap AND the write lands"
  setup

  if ! eperm_pid_available; then
    skip "$test_name" "no EPERM pid available (running as root, or kill -0 1 succeeds here)"
    teardown
    return 0
  fi

  local target="$TEST_DIR/.state.json"
  echo '{"before":true}' > "$target"
  local inflight="$target.tmp.1"
  echo '{"inflight":true}' > "$inflight"

  local rc=0
  echo '{"after":true}' | safe_json_write "$target" || rc=$?

  local content
  content=$(cat "$target" 2>/dev/null)

  if [ "$rc" -eq 0 ] && [ -f "$inflight" ] && [ "$content" = '{"after":true}' ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, EPERM temp kept, content={\"after\":true}" \
      "rc=$rc, inflight=$([ -f "$inflight" ] && echo present || echo gone), content=$content"
  fi

  teardown
}

test_unknown_liveness_keeps_the_temp() {
  local test_name="_reap_stale_temps: when liveness is UNKNOWABLE the temp is kept (fail safe)"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  local orphan="$target.tmp.$IMPOSSIBLE_PID"
  echo 'dead-but-unverifiable' > "$orphan"

  # Shadow `ps` with the 127 a missing binary returns, inside a subshell so the
  # shadow cannot leak into later tests. A status that is neither 0 nor 1 means the
  # probe itself failed, which is not evidence of death — the temp must survive.
  ( ps() { return 127; }; _reap_stale_temps "$target" )

  assert_file_exists "$orphan" "$test_name"

  teardown
}

test_set_e_caller_survives_eperm_branch() {
  local test_name="set -e caller: survives the EPERM branch (no early exit)"
  setup

  if ! eperm_pid_available; then
    skip "$test_name" "no EPERM pid available (running as root, or kill -0 1 succeeds here)"
    teardown
    return 0
  fi

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  local inflight="$target.tmp.1"
  echo 'eperm' > "$inflight"

  local script="$TEST_DIR/caller-eperm.sh"
  cat > "$script" <<CALLER
#!/bin/bash
set -euo pipefail
source "$LIB_SH"
_reap_stale_temps "$target"
echo "SURVIVED"
CALLER
  chmod +x "$script"

  local out rc=0
  out=$(bash "$script" 2>&1) || rc=$?

  if [ "$rc" -eq 0 ] && [ "$out" = "SURVIVED" ] && [ -f "$inflight" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, output 'SURVIVED', EPERM temp kept" \
      "rc=$rc, out='$out', inflight=$([ -f "$inflight" ] && echo present || echo gone)"
  fi

  teardown
}

# =============================================================================
# NON-NUMERIC SUFFIXES — NEVER TOUCHED, NEVER FATAL
# =============================================================================

test_keep_alpha_suffix() {
  local test_name="_reap_stale_temps: .tmp.abc suffix is left alone"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  local weird="$target.tmp.abc"
  echo 'not-a-pid' > "$weird"

  _reap_stale_temps "$target"
  local rc=$?

  if [ -f "$weird" ] && [ "$rc" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "file kept, exit 0" "exists=$([ -f "$weird" ] && echo yes || echo no), rc=$rc"
  fi

  teardown
}

test_keep_empty_suffix() {
  local test_name="_reap_stale_temps: empty .tmp. suffix is left alone"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  local weird="$target.tmp."
  echo 'no-suffix' > "$weird"

  _reap_stale_temps "$target"
  local rc=$?

  if [ -f "$weird" ] && [ "$rc" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "file kept, exit 0" "exists=$([ -f "$weird" ] && echo yes || echo no), rc=$rc"
  fi

  teardown
}

test_mixed_suffix_does_not_abort_loop() {
  local test_name="_reap_stale_temps: a non-numeric suffix does not stop later reaps"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  # 'abc' sorts before the numeric suffix, so the dead temp is only reached
  # if the bad suffix was skipped rather than aborting the loop.
  echo 'bad' > "$target.tmp.abc"
  echo 'dead' > "$target.tmp.$IMPOSSIBLE_PID"

  _reap_stale_temps "$target"

  if [ -f "$target.tmp.abc" ] && [ ! -f "$target.tmp.$IMPOSSIBLE_PID" ]; then
    pass "$test_name"
  else
    fail "$test_name" "abc kept, dead pid removed" "$(ls "$TEST_DIR" | tr '\n' ' ')"
  fi

  teardown
}

# =============================================================================
# NO MATCH — THE UNEXPANDED GLOB IS NOT A FILE
# =============================================================================

test_no_match_is_a_noop() {
  local test_name="_reap_stale_temps: no temps at all — nothing created, nothing removed, exit 0, no stderr"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"

  local before after stderr rc
  before=$(ls -A "$TEST_DIR" | sort)
  stderr=$(_reap_stale_temps "$target" 2>&1 >/dev/null)
  rc=$?
  after=$(ls -A "$TEST_DIR" | sort)

  if [ "$before" = "$after" ] && [ "$rc" -eq 0 ] && [ -z "$stderr" ]; then
    pass "$test_name"
  else
    fail "$test_name" "dir unchanged, exit 0, empty stderr" "rc=$rc, stderr='$stderr', before='$before', after='$after'"
  fi

  teardown
}

test_no_match_does_not_create_literal_glob_file() {
  local test_name="_reap_stale_temps: no temps — the literal '.tmp.*' name is never created"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"

  _reap_stale_temps "$target"

  # A literal-name check, not a glob: [ -f "$target.tmp.*" ] would glob in some shells.
  local literal_count
  literal_count=$(ls -A "$TEST_DIR" | grep -c '^\.state\.json\.tmp\.\*$' || true)
  assert_eq "0" "$literal_count" "$test_name"

  teardown
}

test_non_regular_entry_is_left_alone() {
  local test_name="_reap_stale_temps: a dangling symlink at a dead-pid temp name is left alone"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  # Numeric suffix, dead pid — only the `-f` regular-file guard keeps this.
  # A non-regular entry at that name is not a temp any writer of ours made.
  local dangling="$target.tmp.99999997"
  ln -s "$TEST_DIR/does-not-exist" "$dangling"

  _reap_stale_temps "$target"

  assert_symlink "$dangling" "$test_name"

  teardown
}

test_glob_scope_is_the_named_file_only() {
  local test_name="_reap_stale_temps: a sibling file's dead temp is NOT reaped"
  setup

  echo '{"a":1}' > "$TEST_DIR/.state.json"
  echo '{"b":1}' > "$TEST_DIR/other.json"
  local sibling_orphan="$TEST_DIR/other.json.tmp.$IMPOSSIBLE_PID"
  echo 'dead' > "$sibling_orphan"

  _reap_stale_temps "$TEST_DIR/.state.json"

  assert_file_exists "$sibling_orphan" "$test_name"

  teardown
}

# =============================================================================
# THE REAL FILE IS NEVER TOUCHED
# =============================================================================

test_real_state_file_untouched() {
  local test_name="_reap_stale_temps: the real .state.json is byte-identical afterwards"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"session":"keep-me"}' > "$target"
  local before_hash
  before_hash=$(shasum "$target" | awk '{print $1}')
  echo 'dead' > "$target.tmp.$IMPOSSIBLE_PID"
  spawn_alive
  echo 'alive' > "$target.tmp.$ALIVE_PID"
  echo 'weird' > "$target.tmp.abc"

  _reap_stale_temps "$target"

  local after_hash
  after_hash=$(shasum "$target" 2>/dev/null | awk '{print $1}')
  assert_eq "$before_hash" "$after_hash" "$test_name"

  teardown
}

test_lock_dir_untouched() {
  local test_name="_reap_stale_temps: the sibling .lock dir is not removed"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  mkdir -p "$target.lock"
  echo 'dead' > "$target.tmp.$IMPOSSIBLE_PID"

  _reap_stale_temps "$target"

  assert_dir_exists "$target.lock" "$test_name"

  teardown
}

# =============================================================================
# CALL SITES — safe_json_write / safe_json_update STILL WRITE
# =============================================================================

test_safe_json_write_reaps_and_writes() {
  local test_name="safe_json_write: reaps a planted dead-pid orphan AND still writes"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"before":true}' > "$target"
  local orphan="$target.tmp.$IMPOSSIBLE_PID"
  echo '{"orphan":true}' > "$orphan"

  local rc=0
  echo '{"after":true}' | safe_json_write "$target" || rc=$?

  local content
  content=$(cat "$target" 2>/dev/null)

  if [ "$rc" -eq 0 ] && [ ! -f "$orphan" ] && [ "$content" = '{"after":true}' ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, orphan gone, content={\"after\":true}" \
      "rc=$rc, orphan=$([ -f "$orphan" ] && echo present || echo gone), content=$content"
  fi

  teardown
}

test_safe_json_write_leaves_no_temp_of_its_own() {
  local test_name="safe_json_write: leaves no temp behind on the success path"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"before":true}' | safe_json_write "$target"

  local leftovers
  leftovers=$(ls -A "$TEST_DIR" | grep -c 'tmp\.' || true)
  assert_eq "0" "$leftovers" "$test_name"

  teardown
}

test_safe_json_write_keeps_live_orphan() {
  local test_name="safe_json_write: a concurrent writer's live temp survives the reap"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"before":true}' > "$target"
  spawn_alive
  local inflight="$target.tmp.$ALIVE_PID"
  echo '{"inflight":true}' > "$inflight"

  echo '{"after":true}' | safe_json_write "$target"

  assert_file_exists "$inflight" "$test_name"

  teardown
}

test_safe_json_update_reaps_and_writes() {
  local test_name="safe_json_update: reaps a planted dead-pid orphan AND still writes"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"count":1}' > "$target"
  local orphan="$target.tmp.$IMPOSSIBLE_PID"
  echo '{"orphan":true}' > "$orphan"

  local rc=0
  safe_json_update "$target" '.count = 2' || rc=$?

  local count
  count=$(jq -r '.count' "$target" 2>/dev/null)

  if [ "$rc" -eq 0 ] && [ ! -f "$orphan" ] && [ "$count" = "2" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, orphan gone, .count=2" \
      "rc=$rc, orphan=$([ -f "$orphan" ] && echo present || echo gone), count=$count"
  fi

  teardown
}

test_safe_json_update_invalid_filter_still_reaped() {
  local test_name="safe_json_update: orphan is reaped even when the jq transform then fails"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"count":1}' > "$target"
  local orphan="$target.tmp.$IMPOSSIBLE_PID"
  echo '{"orphan":true}' > "$orphan"

  local rc=0
  safe_json_update "$target" 'this is not jq' 2>/dev/null || rc=$?

  # The reap happens right after the lock, before the transform — a failing
  # update must not strand the reclaim it had already earned.
  if [ "$rc" -ne 0 ] && [ ! -f "$orphan" ]; then
    pass "$test_name"
  else
    fail "$test_name" "non-zero exit, orphan gone" \
      "rc=$rc, orphan=$([ -f "$orphan" ] && echo present || echo gone)"
  fi

  teardown
}

test_safe_json_write_releases_lock_after_reap() {
  local test_name="safe_json_write: lock dir is released after a reaping write"
  setup

  local target="$TEST_DIR/.state.json"
  echo 'dead' > "$target.tmp.$IMPOSSIBLE_PID"
  echo '{"after":true}' | safe_json_write "$target"

  assert_file_not_exists "$target.lock/pid" "$test_name"

  teardown
}

# =============================================================================
# set -e CALLER — THE `if`-FORM HAZARD
# =============================================================================
# One caller (hooks/pre-tool-use-overflow-v2.sh) runs under `set -e`. The hazard is a
# BARE failing simple command in the loop body: `&&`/`||` operands and `!`-prefixed
# pipelines are exempt from `set -e`, so an `&&`-list rewrite is NOT what breaks this.
# The `if` form is what holds, because an `if` compound returns 0 when its condition is
# false, so the body's last command always succeeds. A rewrite that leaves a bare
# `kill -0` or `! kill -0` in the body turns these red.

test_set_e_caller_survives_live_pid_branch() {
  local test_name="set -e caller: survives the LIVE-pid branch (no early exit)"
  setup

  sleep 30 &
  ALIVE_PID=$!

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  echo 'alive' > "$target.tmp.$ALIVE_PID"

  local script="$TEST_DIR/caller.sh"
  cat > "$script" <<CALLER
#!/bin/bash
set -euo pipefail
source "$LIB_SH"
_reap_stale_temps "$target"
echo "SURVIVED"
CALLER
  chmod +x "$script"

  local out rc=0
  out=$(bash "$script" 2>&1) || rc=$?

  if [ "$rc" -eq 0 ] && [ "$out" = "SURVIVED" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 and output 'SURVIVED'" "rc=$rc, out='$out'"
  fi

  teardown
}

test_set_e_caller_survives_dead_pid_branch() {
  local test_name="set -e caller: survives the DEAD-pid branch and still reaps"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  local orphan="$target.tmp.$IMPOSSIBLE_PID"
  echo 'dead' > "$orphan"

  local script="$TEST_DIR/caller-dead.sh"
  cat > "$script" <<CALLER
#!/bin/bash
set -euo pipefail
source "$LIB_SH"
_reap_stale_temps "$target"
echo "SURVIVED"
CALLER
  chmod +x "$script"

  local out rc=0
  out=$(bash "$script" 2>&1) || rc=$?

  if [ "$rc" -eq 0 ] && [ "$out" = "SURVIVED" ] && [ ! -f "$orphan" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, output 'SURVIVED', orphan gone" \
      "rc=$rc, out='$out', orphan=$([ -f "$orphan" ] && echo present || echo gone)"
  fi

  teardown
}

test_set_e_caller_survives_own_pid_branch() {
  local test_name="set -e caller: survives the own-\$\$ branch (no early exit)"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"

  local script="$TEST_DIR/caller-self.sh"
  cat > "$script" <<CALLER
#!/bin/bash
set -euo pipefail
source "$LIB_SH"
echo 'mine' > "$target.tmp.\$\$"
_reap_stale_temps "$target"
echo "SURVIVED"
CALLER
  chmod +x "$script"

  local out rc=0
  out=$(bash "$script" 2>&1) || rc=$?

  if [ "$rc" -eq 0 ] && [ "$out" = "SURVIVED" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 and output 'SURVIVED'" "rc=$rc, out='$out'"
  fi

  teardown
}

test_set_e_caller_survives_non_numeric_branch() {
  local test_name="set -e caller: survives the non-numeric-suffix branch (no early exit)"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"
  echo 'bad' > "$target.tmp.abc"

  local script="$TEST_DIR/caller-abc.sh"
  cat > "$script" <<CALLER
#!/bin/bash
set -euo pipefail
source "$LIB_SH"
_reap_stale_temps "$target"
echo "SURVIVED"
CALLER
  chmod +x "$script"

  local out rc=0
  out=$(bash "$script" 2>&1) || rc=$?

  if [ "$rc" -eq 0 ] && [ "$out" = "SURVIVED" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 and output 'SURVIVED'" "rc=$rc, out='$out'"
  fi

  teardown
}

test_set_e_caller_survives_no_match_branch() {
  local test_name="set -e caller: survives the no-match (unexpanded glob) branch"
  setup

  local target="$TEST_DIR/.state.json"
  echo '{"live":true}' > "$target"

  local script="$TEST_DIR/caller-empty.sh"
  cat > "$script" <<CALLER
#!/bin/bash
set -euo pipefail
source "$LIB_SH"
_reap_stale_temps "$target"
echo "SURVIVED"
CALLER
  chmod +x "$script"

  local out rc=0
  out=$(bash "$script" 2>&1) || rc=$?

  if [ "$rc" -eq 0 ] && [ "$out" = "SURVIVED" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 and output 'SURVIVED'" "rc=$rc, out='$out'"
  fi

  teardown
}

# =============================================================================
# HOOK CALL SITES — the two hooks that write a temp inline
# =============================================================================

test_hooks_call_reaper_before_their_tmp_assignment() {
  local test_name="hooks: both inline-temp writers call the reaper and rm -f their own temp"
  setup

  local ok=1 detail=""
  local hook
  for hook in "$ENGINE_HOOKS/post-tool-use-injections.sh" \
              "$ENGINE_HOOKS/pre-tool-use-overflow-v2.sh"; do
    if [ ! -f "$hook" ]; then
      ok=0; detail="$detail missing:$(basename "$hook")"
      continue
    fi
    if ! grep -q '_reap_stale_temps' "$hook"; then
      ok=0; detail="$detail no-reap:$(basename "$hook")"
    fi
    # The mv is &&-chained with the redirect and a trailing rm -f follows it:
    # that pair covers the failure path the reaper deliberately does not.
    if ! grep -Eq 'rm -f "\$(tmp_file|claim_tmp)"' "$hook"; then
      ok=0; detail="$detail no-rm:$(basename "$hook")"
    fi
    if ! grep -Eq '> "\$(tmp_file|claim_tmp)" && mv "\$(tmp_file|claim_tmp)"' "$hook"; then
      ok=0; detail="$detail no-and-chain:$(basename "$hook")"
    fi
  done

  if [ "$ok" -eq 1 ]; then
    pass "$test_name"
  else
    fail "$test_name" "both hooks reap + rm -f" "$detail"
  fi

  teardown
}

# =============================================================================
# RUN
# =============================================================================

run_test test_reap_dead_pid_impossible
run_test test_reap_dead_pid_reaped_child
run_test test_reap_multiple_dead_in_one_pass

run_test test_keep_live_pid
run_test test_keep_own_pid
run_test test_mixed_live_and_dead

run_test test_keep_eperm_pid_foreign_owner
run_test test_pid_is_alive_discriminates_eperm_from_esrch
run_test test_mixed_dead_and_eperm
run_test test_safe_json_write_keeps_eperm_orphan
run_test test_unknown_liveness_keeps_the_temp
run_test test_set_e_caller_survives_eperm_branch

run_test test_keep_alpha_suffix
run_test test_keep_empty_suffix
run_test test_mixed_suffix_does_not_abort_loop

run_test test_no_match_is_a_noop
run_test test_no_match_does_not_create_literal_glob_file
run_test test_non_regular_entry_is_left_alone
run_test test_glob_scope_is_the_named_file_only

run_test test_real_state_file_untouched
run_test test_lock_dir_untouched

run_test test_safe_json_write_reaps_and_writes
run_test test_safe_json_write_leaves_no_temp_of_its_own
run_test test_safe_json_write_keeps_live_orphan
run_test test_safe_json_update_reaps_and_writes
run_test test_safe_json_update_invalid_filter_still_reaped
run_test test_safe_json_write_releases_lock_after_reap

run_test test_set_e_caller_survives_live_pid_branch
run_test test_set_e_caller_survives_dead_pid_branch
run_test test_set_e_caller_survives_own_pid_branch
run_test test_set_e_caller_survives_non_numeric_branch
run_test test_set_e_caller_survives_no_match_branch

run_test test_hooks_call_reaper_before_their_tmp_assignment

exit_with_results
