#!/bin/bash
# tests/run-all.sh — Run all engine test suites
#
# Usage: bash ~/.claude/engine/scripts/tests/run-all.sh          # quiet (failures only)
#        bash ~/.claude/engine/scripts/tests/run-all.sh -v        # verbose (all output)
#        bash ~/.claude/engine/scripts/tests/run-all.sh test-foo.sh        # single suite
#        bash ~/.claude/engine/scripts/tests/run-all.sh -v test-foo.sh     # single suite verbose

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
FAILED_NAMES=()
VERBOSE=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Parse -v flag
ARGS=()
for arg in "$@"; do
  if [ "$arg" = "-v" ] || [ "$arg" = "--verbose" ]; then
    VERBOSE=1
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
      echo -e "  ${GREEN}✓${NC} $name ${count:+($count)}"
    else
      FAILED_SUITES=$((FAILED_SUITES + 1))
      FAILED_NAMES+=("$name")
      echo -e "  ${RED}✗${NC} $name"
      # Show only FAIL lines + results summary
      echo "$output" | grep -E 'FAIL|Expected|Actual|Results:' | sed 's/^/    /'
    fi
  fi
}

# Header
echo "╔════════════════════════════════════════╗"
echo "║     Engine Test Runner                 ║"
echo "╚════════════════════════════════════════╝"

# Run specific suite or all
if [ $# -gt 0 ]; then
  # Run specific suite(s)
  for arg in "$@"; do
    if [ -f "$TESTS_DIR/$arg" ]; then
      run_suite "$TESTS_DIR/$arg"
    elif [ -f "$arg" ]; then
      run_suite "$arg"
    else
      echo -e "${RED}NOT FOUND${NC}: $arg"
      FAILED_SUITES=$((FAILED_SUITES + 1))
      FAILED_NAMES+=("$arg")
    fi
  done
else
  # Run all test-*.sh files
  for file in "$TESTS_DIR"/test-*.sh; do
    [ -f "$file" ] || continue
    run_suite "$file"
  done
fi

# Summary
echo ""
echo "╔════════════════════════════════════════╗"
if [ $FAILED_SUITES -eq 0 ]; then
  echo -e "║  ${GREEN}ALL $TOTAL_SUITES SUITES PASSED${NC}                  ║"
else
  echo -e "║  ${RED}$FAILED_SUITES/$TOTAL_SUITES SUITES FAILED${NC}                  ║"
  for name in "${FAILED_NAMES[@]}"; do
    echo -e "║    ${RED}✗${NC} $name"
  done
fi
echo "╚════════════════════════════════════════╝"

[ $FAILED_SUITES -eq 0 ] && exit 0 || exit 1
