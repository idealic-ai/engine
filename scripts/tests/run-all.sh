#!/bin/bash
# tests/run-all.sh — Run all engine test suites
#
# Usage: bash ~/.claude/engine/scripts/tests/run-all.sh          # quiet (failures only)
#        bash ~/.claude/engine/scripts/tests/run-all.sh -v        # verbose (all output)
#        bash ~/.claude/engine/scripts/tests/run-all.sh test-foo.sh        # single suite
#        bash ~/.claude/engine/scripts/tests/run-all.sh -v test-foo.sh     # single suite verbose

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
FAILED_NAMES=()
VERBOSE=0

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

run_suite() {
  local file="$1"
  local name
  name=$(basename "$file")
  TOTAL_SUITES=$((TOTAL_SUITES + 1))

  if [ "$VERBOSE" = "1" ]; then
    echo ""
    echo "━━━ $name ━━━"
    if bash "$file" 2>&1; then
      PASSED_SUITES=$((PASSED_SUITES + 1))
    else
      FAILED_SUITES=$((FAILED_SUITES + 1))
      FAILED_NAMES+=("$name")
    fi
  else
    # Quiet mode: capture output, only show on failure
    local output
    if output=$(bash "$file" 2>&1); then
      PASSED_SUITES=$((PASSED_SUITES + 1))
      # Extract pass count from "Results: N passed" line
      local count
      count=$(echo "$output" | grep -oE '[0-9]+ passed' | head -1 || echo "")
      echo -e "  ${GREEN}✓${RESET} $name ${count:+($count)}"
    else
      FAILED_SUITES=$((FAILED_SUITES + 1))
      FAILED_NAMES+=("$name")
      echo -e "  ${RED}✗${RESET} $name"
      # Show only FAIL lines + results summary
      echo "$output" | grep -E 'FAIL|Expected|Actual|Results:' | sed 's/^/    /'
    fi
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
echo "╚════════════════════════════════════════╝"

[ $FAILED_SUITES -eq 0 ] && exit 0 || exit 1
