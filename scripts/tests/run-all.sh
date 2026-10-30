#!/bin/bash
# tests/run-all.sh — Run all engine test suites
#
# Usage: bash ~/.claude/engine/scripts/tests/run-all.sh          # quiet (failures only)
#        bash ~/.claude/engine/scripts/tests/run-all.sh -v        # verbose (all output)
#        bash ~/.claude/engine/scripts/tests/run-all.sh test-foo.sh        # single suite
#        bash ~/.claude/engine/scripts/tests/run-all.sh -v test-foo.sh     # single suite verbose
#
# A SUITE'S EXIT STATUS IS NOT ITS VERDICT. A suite that prints "FAIL ... is BROKEN" and
# "Results: 1 passed, 1 failed" and then exits 0 — a stray `|| true`, a `set -e` that never
# armed, an `exit` in a subshell — was read as a pass, and the decorative pass count was
# scraped off the very line that declared the failure, so the false green arrived with a
# denominator. Three readings now have to agree before a suite gets a tick:
#   status    the suite's own exit code, read from a BARE command, never through a pipeline
#   markers   any line whose FIRST token is FAIL/FAILED, which is how every suite in this tree
#             prints a failure. ANCHORED TO THE FIRST TOKEN ON PURPOSE: a suite legitimately
#             naming a failure in a test NAME prints "PASS: ... FAIL ..." and must not be
#             condemned by the word appearing mid-line. The anchor is what discriminates.
#   tally     the suite's own results line, which must exist and must report at least one case.
#             A suite that ran zero cases has not passed anything; "0 passed" is a tick whose
#             text would be identical had the check never executed. Suppressed under
#             TEST_FILTER, where running no case is the expected outcome.
# A suite is a pass only when all three agree. Any disagreement is a FAIL and the reason is
# named in the row, so the three states (red, text-red-at-exit-0, no cases) never read alike.
#
# A suite that ran no case because every case SKIPped (a dependency this machine lacks) is a
# pass WITH A NOTE saying nothing ran here, not a red: a red that follows the machine rather than
# the code teaches a reader to ignore red rows.
#
# The per-suite timeout is OPT-IN: ENGINE_TEST_TIMEOUT=<seconds> bounds each suite, unset or 0
# runs every suite unbounded. A default budget turned honest suites red on a loaded machine
# (test-session-start-restore.sh passed in 258 s at load ~400), so the runner does not guess one.
# With a budget set, a hung suite is killed (TERM, then KILL 10 s later) and the glob goes on, so
# the suites after it are still run and counted. A TIMEOUT row prints the elapsed time and the
# load, so it is never read as a test failure. LIMIT: a grandchild that detaches into its own
# session and keeps the suite's stdout open is outside the killed process group, and the runner
# still waits on it.
#
# Every suite runs in its own process group, and INT/TERM to the runner kill that group, so
# Ctrl-C stops the running suite instead of leaving it to run on, orphaned.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"

# Pre-flight: verify test-helpers.sh exists
if [ ! -f "$TESTS_DIR/test-helpers.sh" ]; then
  echo "ERROR: test-helpers.sh not found in $TESTS_DIR"
  echo "All test files depend on this shared library."
  exit 1
fi

TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
NOTHING_RAN_SUITES=0
FAILED_NAMES=()
VERBOSE=0

# Per-suite wall-clock budget, opt-in (see the header). Resolved once: GNU timeout is `timeout`
# on Linux, `gtimeout` from coreutils on macOS, /opt/homebrew/bin/timeout where brew put it.
# Whatever the outcome, the header says it, so an unbounded run is never mistaken for a bounded one.
SUITE_TIMEOUT="${ENGINE_TEST_TIMEOUT:-0}"
TIMEOUT_KILL_AFTER=10
TIMEOUT_BIN=""
for _cand in timeout gtimeout /opt/homebrew/bin/timeout; do
  if command -v "$_cand" >/dev/null 2>&1; then TIMEOUT_BIN="$_cand"; break; fi
done
if [ "$SUITE_TIMEOUT" = "0" ]; then
  TIMEOUT_NOTE="per-suite timeout off (set ENGINE_TEST_TIMEOUT=<seconds> to bound each suite)"
elif [ -z "$TIMEOUT_BIN" ]; then
  TIMEOUT_NOTE="WARNING: ENGINE_TEST_TIMEOUT=$SUITE_TIMEOUT but no timeout(1)/gtimeout on PATH — suites run UNBOUNDED"
  SUITE_TIMEOUT=0
else
  TIMEOUT_NOTE="per-suite timeout ${SUITE_TIMEOUT}s (ENGINE_TEST_TIMEOUT), KILL ${TIMEOUT_KILL_AFTER}s after TERM"
fi

load_avg() { sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}' || cut -d' ' -f1 /proc/loadavg 2>/dev/null; }

# Strips ANSI SGR sequences, so every text rule below reads the same whether the suite coloured
# its output or not. `fail()` in test-helpers.sh wraps the word FAIL in a colour escape, which is
# why a rule anchored on the start of the line has to see through them.
strip_ansi() { sed 's/'$'\x1b''\[[0-9;]*[A-Za-z]//g'; }

# A failure marker is a line whose FIRST token is FAIL or FAILED, with an optional "=== " banner
# and an optional trailing colon. THE ANCHOR IS THE WHOLE RULE. Every suite in this tree prints
# its failures that way — "FAIL: <label>", "  FAIL <label>", "=== FAIL" — and several print the
# word legitimately inside a test NAME on a passing line ("PASS: Bad JSON produces FAIL",
# "PASS: a FAILED setup still re-checks"). Measured over the captured output of this tree's
# suites: 7 such lines, every one of them a PASS, and the anchor excludes all 7 while matching
# every real failure line. An unanchored grep would condemn the suites that test failure
# handling — the ones most worth keeping.
FAILURE_MARKER_RE='^[[:space:]]*(=== )?(FAIL|FAILED)([[:space:]]|:|$)'

# The suite's own results line, in the five shapes this tree writes:
#   "Results: N passed, M failed (T total)" · "=== Results: N passed, M failed ==="
#   "passed N    failed M" · "N ok, M FAIL" · bare "N passed, M failed" (the loom-slots,
#   prove-family and publish-seat suites, read off a full run on 2026-10-30)
RESULTS_LINE_RE='^[[:space:]]*(=== )?(Results:|passed[[:space:]]+[0-9]+[[:space:]]+failed|[0-9]+[[:space:]]+ok,|[0-9]+[[:space:]]+passed,[[:space:]]+[0-9]+[[:space:]]+failed)'

# A skip line: first token SKIP, as test-helpers.sh's skip() prints it.
SKIP_MARKER_RE='^[[:space:]]*SKIP([[:space:]]|:|$)'

# suite_verdict <rc> <elapsed_s> <<<output  ->  prints "pass:<note>" | "fail:<reason>"
# Three readings must agree. Prints the reason so the row can name it: a red exit, a red text at
# exit 0, a tally that could not be read, and a suite that ran no cases are four different
# things and only an output that says which is any use.
suite_verdict() {
  local rc="$1" elapsed="${2:-0}" text
  text=$(cat | strip_ansi)

  # 124/137 is timeout(1)'s mark only when a budget was set and the suite used it up. A suite
  # that exits 124 itself (one that wraps timeout, or is OOM-killed) is an ordinary red exit.
  if { [ "$rc" = "124" ] || [ "$rc" = "137" ]; } && [ "$SUITE_TIMEOUT" != "0" ] \
     && [ "$elapsed" -ge "$SUITE_TIMEOUT" ]; then
    echo "fail:TIMEOUT after ${elapsed}s (budget ${SUITE_TIMEOUT}s, load $(load_avg)); killed, its remaining cases never ran"
    return
  fi

  local markers
  markers=$(printf '%s\n' "$text" | grep -acE "$FAILURE_MARKER_RE" || true)
  [ -n "$markers" ] || markers=0

  local results_line
  results_line=$(printf '%s\n' "$text" | grep -aE "$RESULTS_LINE_RE" | tail -1 || true)

  # Skips: the tally's "N skipped" when it has one (test-helpers.sh prints it), else the count of
  # SKIP lines. Counted with grep -c, never probed with grep -q in a pipe: under pipefail grep -q's
  # early exit SIGPIPEs the producer once the output outgrows the pipe buffer, and the probe
  # reads false on a large output alone.
  local n_skip n_total=""
  n_skip=$(printf '%s\n' "$results_line" | grep -aoE '[0-9]+ skipped' | grep -aoE '[0-9]+' | head -1 || true)
  [ -n "$n_skip" ] || n_skip=$(printf '%s\n' "$text" | grep -acE "$SKIP_MARKER_RE" || true)
  [ -n "$n_skip" ] || n_skip=0
  n_total=$(printf '%s\n' "$results_line" | grep -aoE '\([0-9]+ total\)' | grep -aoE '[0-9]+' | head -1 || true)

  local n_pass="" n_fail=""
  if [ -n "$results_line" ]; then
    n_pass=$(printf '%s\n' "$results_line" | grep -aoE '[0-9]+ (passed|ok)|passed[[:space:]]+[0-9]+' | head -1 | grep -aoE '[0-9]+' | head -1)
    n_fail=$(printf '%s\n' "$results_line" | grep -aoE '[0-9]+ (failed|FAIL)|failed[[:space:]]+[0-9]+' | head -1 | grep -aoE '[0-9]+' | head -1)
  fi

  if [ "$rc" != "0" ]; then
    echo "fail:exit $rc"
  elif [ "$markers" -gt 0 ]; then
    # The defect this rule exists for: the suite said it failed and exited 0 anyway.
    echo "fail:exit 0 but $markers failure line(s) in its output"
  elif [ -n "${n_fail:-}" ] && [ "$n_fail" -gt 0 ]; then
    echo "fail:exit 0 but its own tally reports $n_fail failed"
  elif [ -z "$results_line" ]; then
    echo "fail:exit 0 with no results line — its tally could not be read, so the tick would be unearned"
  elif [ -z "${n_pass:-}" ]; then
    echo "fail:exit 0 with an unreadable pass count in '$(printf '%s' "$results_line" | tr -s ' ' | cut -c1-60)'"
  elif [ "$n_pass" -eq 0 ] && [ -z "${TEST_FILTER:-}" ] && [ "$n_skip" -gt 0 ] \
       && [ -n "$n_total" ] && [ "$n_skip" -eq "$n_total" ]; then
    # Green only when EVERY case skipped: skipped == total, both read off the suite's own tally.
    echo "pass:0 passed, $n_skip skipped — NOTE: nothing ran on this machine"
  elif [ "$n_pass" -eq 0 ] && [ -z "${TEST_FILTER:-}" ] && [ "$n_skip" -gt 0 ]; then
    echo "fail:exit 0, 0 passed and $n_skip of ${n_total:-an unstated number of} cases skipped — the rest ran nothing"
  elif [ "$n_pass" -eq 0 ] && [ -z "${TEST_FILTER:-}" ]; then
    # ¶PTF_PROVE_THE_INSTRUMENT_RAN: a tick whose text would be identical had the check never
    # executed. Under TEST_FILTER running no case is the expected outcome, so the rule lifts.
    echo "fail:exit 0 but ran 0 cases — nothing was checked"
  else
    echo "pass:$n_pass passed"
  fi
}

RED='\033[31m'
GREEN='\033[32m'
RESET='\033[0m'

# Parse flags
ARGS=()
GREP_NEXT=0
for arg in "$@"; do
  if [ "$GREP_NEXT" = "1" ]; then
    export TEST_FILTER="$arg"
    GREP_NEXT=0
  elif [ "$arg" = "-v" ] || [ "$arg" = "--verbose" ]; then
    VERBOSE=1
  elif [ "$arg" = "--grep" ] || [ "$arg" = "-g" ]; then
    GREP_NEXT=1
  else
    ARGS+=("$arg")
  fi
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

# The suite in flight, so the INT/TERM trap can stop it. SUITE_PGID is both the launched pid and
# its process group: timeout(1) puts itself in a new group (it is not run with --foreground), and
# the unbounded path does the same with perl's setpgrp before exec'ing bash.
SUITE_PGID=""
TAIL_PID=""
on_interrupt() {
  [ -n "$SUITE_PGID" ] && kill -TERM -- "-$SUITE_PGID" 2>/dev/null
  [ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null
  echo "" >&2
  echo "run-all: interrupted; stopped the running suite (process group $SUITE_PGID)" >&2
  exit 130
}
trap on_interrupt INT TERM

# Runs one suite in the background in its own process group, output to <outfile>, and waits for
# it. Sets RC to the suite's own status (timeout(1)'s 124/137 on expiry) and ELAPSED in seconds.
# Backgrounded so `wait` can be interrupted by the trap; a foreground child would defer it.
run_bounded() {
  local file="$1" outfile="$2" start
  start=$(date +%s)
  if [ "$SUITE_TIMEOUT" != "0" ]; then
    "$TIMEOUT_BIN" -k "$TIMEOUT_KILL_AFTER" "$SUITE_TIMEOUT" bash "$file" >"$outfile" 2>&1 &
  else
    perl -e 'setpgrp(0,0); exec @ARGV or die "exec: $!"' bash "$file" >"$outfile" 2>&1 &
  fi
  SUITE_PGID=$!
  wait "$SUITE_PGID"
  RC=$?
  SUITE_PGID=""
  ELAPSED=$(( $(date +%s) - start ))
}

run_suite() {
  local file="$1"
  local name
  name=$(basename "$file")
  TOTAL_SUITES=$((TOTAL_SUITES + 1))

  local output verdict tmp_out
  tmp_out=$(mktemp)
  if [ "$VERBOSE" = "1" ]; then
    echo ""
    echo "━━━ $name ━━━"
    # The suite writes to a file (so its status is its own, not a pipeline's) and a tail streams
    # that file live; the tail is a pid this runner started, stopped by pid when the suite ends.
    tail -n +1 -f "$tmp_out" & TAIL_PID=$!
    run_bounded "$file" "$tmp_out"
    sleep 0.2; kill "$TAIL_PID" 2>/dev/null; wait "$TAIL_PID" 2>/dev/null; TAIL_PID=""
  else
    # Quiet mode: capture output, only show on failure
    run_bounded "$file" "$tmp_out"
  fi
  output=$(cat "$tmp_out")
  rm -f "$tmp_out"

  verdict=$(printf '%s\n' "$output" | suite_verdict "$RC" "$ELAPSED")

  if [ "${verdict%%:*}" = "pass" ]; then
    PASSED_SUITES=$((PASSED_SUITES + 1))
    case "$verdict" in *"nothing ran on this machine"*) NOTHING_RAN_SUITES=$((NOTHING_RAN_SUITES + 1)) ;; esac
    [ "$VERBOSE" = "1" ] || echo -e "  ${GREEN}✓${RESET} $name (${verdict#*:})"
  else
    FAILED_SUITES=$((FAILED_SUITES + 1))
    FAILED_NAMES+=("$name — ${verdict#*:}")
    # The reason rides the row. A suite that exited non-zero, one that printed a failure and
    # exited 0, one whose tally was unreadable and one that ran nothing are four different
    # defects, and a bare ✗ for all four is what sent a reader back to re-run them one at a time.
    echo -e "  ${RED}✗${RESET} $name — ${verdict#*:}"
    [ "$VERBOSE" = "1" ] || printf '%s\n' "$output" | strip_ansi \
      | grep -aE "$FAILURE_MARKER_RE|Expected|Actual|$RESULTS_LINE_RE" | sed 's/^/    /'
  fi
}

# Pre-filter: when TEST_FILTER is set, skip files with no matching test functions or filename
file_matches_filter() {
  local file="$1"
  [ -z "${TEST_FILTER:-}" ] && return 0  # no filter — match all
  # Match filename
  case "$(basename "$file")" in
    *"$TEST_FILTER"*) return 0 ;;
  esac
  # Match function names inside the file
  grep -q "^test_.*${TEST_FILTER}" "$file" 2>/dev/null && return 0
  grep -q "test_.*${TEST_FILTER}" "$file" 2>/dev/null && return 0
  return 1
}

# Header
echo "╔════════════════════════════════════════╗"
echo "║     Engine Test Runner                 ║"
[ -n "${TEST_FILTER:-}" ] && echo "║     Filter: ${TEST_FILTER}$(printf '%*s' $((26 - ${#TEST_FILTER})) '')║"
echo "╚════════════════════════════════════════╝"
echo "  $TIMEOUT_NOTE"

# Run specific suite or all
if [ $# -gt 0 ]; then
  # Run specific suite(s)
  for arg in "$@"; do
    if [ -f "$TESTS_DIR/$arg" ]; then
      file_matches_filter "$TESTS_DIR/$arg" && run_suite "$TESTS_DIR/$arg"
    elif [ -f "$arg" ]; then
      file_matches_filter "$arg" && run_suite "$arg"
    else
      echo -e "${RED}NOT FOUND${RESET}: $arg"
      FAILED_SUITES=$((FAILED_SUITES + 1))
      FAILED_NAMES+=("$arg")
    fi
  done
else
  # Run all test-*.sh files (skip test-helpers.sh — it's a library, not a suite)
  for file in "$TESTS_DIR"/test-*.sh; do
    [ -f "$file" ] || continue
    [ "$(basename "$file")" = "test-helpers.sh" ] && continue
    file_matches_filter "$file" || continue
    run_suite "$file"
  done
fi

# Summary
echo ""
echo "╔════════════════════════════════════════╗"
if [ $FAILED_SUITES -eq 0 ]; then
  echo -e "║  ${GREEN}ALL $TOTAL_SUITES SUITES PASSED${RESET}                  ║"
else
  echo -e "║  ${RED}$FAILED_SUITES/$TOTAL_SUITES SUITES FAILED${RESET}                  ║"
  for name in "${FAILED_NAMES[@]}"; do
    echo -e "║    ${RED}✗${RESET} $name"
  done
fi
# A green that ran nothing is still a green, so the banner says how many there were: a summary
# that reads "ALL PASSED" alone would make an all-skip run and a full run look the same.
[ "$NOTHING_RAN_SUITES" -gt 0 ] \
  && echo "║  NOTE: $NOTHING_RAN_SUITES suite(s) ran nothing on this machine (every case skipped)"
echo "╚════════════════════════════════════════╝"

[ $FAILED_SUITES -eq 0 ] && exit 0 || exit 1
