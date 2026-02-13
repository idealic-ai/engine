#!/bin/bash
# test-helpers.sh — Shared test infrastructure for engine tests
#
# Usage: source "$(dirname "$0")/test-helpers.sh"
#
# Provides: colors, counters, pass/fail, assertions, run_test(), summary,
#           and opt-in mock infrastructure for integration tests.

# Prevent double-sourcing
[ -n "${_TEST_HELPERS_LOADED:-}" ] && return 0
_TEST_HELPERS_LOADED=1

# ============================================================
# Colors
# ============================================================
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

# ============================================================
# Counters
# ============================================================
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================
# Core Functions
# ============================================================

pass() {
  echo -e "${GREEN}PASS${RESET}: $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
}

fail() {
  echo -e "${RED}FAIL${RESET}: $1"
  [ -n "${2:-}" ] && echo "  Expected: $2"
  [ -n "${3:-}" ] && echo "  Got: $3"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
}

skip() {
  echo -e "${YELLOW}SKIP${RESET}: $1${2:+ — $2}"
}

# ============================================================
# Assertions
# ============================================================

assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$msg"
  else
    fail "$msg" "$expected" "$actual"
  fi
}

assert_contains() {
  local pattern="$1" actual="$2" msg="$3"
  if echo "$actual" | grep -qF "$pattern" 2>/dev/null || echo "$actual" | grep -q "$pattern" 2>/dev/null; then
    pass "$msg"
  else
    fail "$msg" "contains '$pattern'" "$actual"
  fi
}

assert_not_contains() {
  local pattern="$1" actual="$2" msg="$3"
  if echo "$actual" | grep -qF "$pattern" 2>/dev/null; then
    fail "$msg" "NOT contains '$pattern'" "$actual"
  else
    pass "$msg"
  fi
}

assert_empty() {
  local actual="$1" msg="$2"
  if [ -z "$actual" ]; then
    pass "$msg"
  else
    fail "$msg" "(empty)" "$actual"
  fi
}

assert_not_empty() {
  local actual="$1" msg="$2"
  if [ -n "$actual" ]; then
    pass "$msg"
  else
    fail "$msg" "(non-empty)" "(empty)"
  fi
}

assert_json() {
  local file="$1" field="$2" expected="$3" msg="$4"
  local actual
  actual=$(jq -r "$field" "$file" 2>/dev/null || echo "ERROR")
  if [ "$actual" = "$expected" ]; then
    pass "$msg"
  else
    fail "$msg" "$expected" "$actual"
  fi
}

assert_file_exists() {
  local path="$1" msg="$2"
  if [ -f "$path" ]; then
    pass "$msg"
  else
    fail "$msg" "file exists" "missing: $path"
  fi
}

assert_dir_exists() {
  local path="$1" msg="$2"
  if [ -d "$path" ]; then
    pass "$msg"
  else
    fail "$msg" "dir exists" "missing: $path"
  fi
}

assert_file_not_exists() {
  local path="$1" msg="$2"
  if [ ! -f "$path" ]; then
    pass "$msg"
  else
    fail "$msg" "file not exists" "exists: $path"
  fi
}

assert_symlink() {
  local path="$1" msg="$2"
  if [ -L "$path" ]; then
    pass "$msg"
  else
    fail "$msg" "symlink" "not a symlink: $path"
  fi
}

assert_not_symlink() {
  local path="$1" msg="$2"
  if [ ! -L "$path" ]; then
    pass "$msg"
  else
    fail "$msg" "not a symlink" "is a symlink: $path"
  fi
}

assert_gt() {
  local a="$1" b="$2" msg="$3"
  if [ "$a" -gt "$b" ] 2>/dev/null; then
    pass "$msg"
  else
    fail "$msg" "$a > $b" "$a <= $b"
  fi
}

assert_ok() {
  local desc="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc" "exit 0" "command failed"
  fi
}

assert_fail() {
  local desc="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    fail "$desc" "non-zero exit" "command succeeded"
  else
    pass "$desc"
  fi
}

# ============================================================
# Test Runner
# ============================================================

# Wraps a test function with setup/teardown calls.
# Tests that define setup() and teardown() get them called automatically.
run_test() {
  local name="$1"
  if type setup &>/dev/null; then
    setup
  fi
  eval "$name"
  if type teardown &>/dev/null; then
    teardown
  fi
}

# ============================================================
# Summary / Results
# ============================================================

print_results() {
  echo ""
  echo "======================================"
  echo -e "Results: ${GREEN}${TESTS_PASSED} passed${RESET}, ${RED}${TESTS_FAILED} failed${RESET} (${TESTS_RUN} total)"
  echo "======================================"
}

exit_with_results() {
  print_results
  [ "$TESTS_FAILED" -eq 0 ] && exit 0 || exit 1
}

# ============================================================
# Mock Infrastructure (opt-in)
# ============================================================

# Create a fake HOME for isolated session.sh testing.
# Usage: setup_fake_home "$TMP_DIR"
# Sets: FAKE_HOME, ORIGINAL_HOME; exports HOME=$FAKE_HOME
setup_fake_home() {
  local tmp_dir="$1"
  ORIGINAL_HOME="${HOME:-}"
  FAKE_HOME="$tmp_dir/fake-home"

  mkdir -p "$FAKE_HOME/.claude/scripts"
  mkdir -p "$FAKE_HOME/.claude/hooks"
  mkdir -p "$FAKE_HOME/.claude/tools/session-search"
  mkdir -p "$FAKE_HOME/.claude/tools/doc-search"

  export HOME="$FAKE_HOME"
}

# Restore original HOME after testing.
teardown_fake_home() {
  if [ -n "${ORIGINAL_HOME:-}" ]; then
    export HOME="$ORIGINAL_HOME"
  fi
}

# Create a no-op fleet.sh stub in the given home directory.
# Usage: mock_fleet_sh "$FAKE_HOME"  (or no arg → uses $HOME)
mock_fleet_sh() {
  local home="${1:-$HOME}"
  mkdir -p "$home/.claude/scripts"
  cat > "$home/.claude/scripts/fleet.sh" <<'MOCK'
#!/bin/bash
case "${1:-}" in
  pane-id) echo ""; exit 0 ;;
  *)       exit 0 ;;
esac
MOCK
  chmod +x "$home/.claude/scripts/fleet.sh"
}

# Create no-op session-search and doc-search stubs.
# Usage: mock_search_tools "$FAKE_HOME"  (or no arg → uses $HOME)
mock_search_tools() {
  local home="${1:-$HOME}"
  for tool in session-search doc-search; do
    mkdir -p "$home/.claude/tools/$tool"
    cat > "$home/.claude/tools/$tool/$tool.sh" <<'MOCK'
#!/bin/bash
echo "(none)"
MOCK
    chmod +x "$home/.claude/tools/$tool/$tool.sh"
  done
}

# Disable fleet/tmux detection for isolated testing.
disable_fleet_tmux() {
  unset TMUX 2>/dev/null || true
  unset TMUX_PANE 2>/dev/null || true
  export FLEET_SETUP_DONE=1
}

# setup_test_env SESSION_NAME
# One-shot test environment setup — combines the 8-step boilerplate.
#
# Sets these globals (for caller use):
#   TMP_DIR          — Temp directory (cleaned up by cleanup_test_env)
#   TEST_SESSION     — $TMP_DIR/sessions/$SESSION_NAME
#   FAKE_HOME        — (from setup_fake_home)
#   ORIGINAL_HOME    — (from setup_fake_home)
#   REAL_SCRIPTS_DIR — Original ~/.claude/scripts/ (for extra symlinks)
#   REAL_ENGINE_DIR  — Original ~/.claude/engine/ (for extra symlinks)
#   REAL_HOOKS_DIR   — Original ~/.claude/hooks/ (for extra symlinks)
#
# After calling, add test-specific symlinks:
#   ln -sf "$REAL_HOOKS_DIR/my-hook.sh" "$FAKE_HOME/.claude/hooks/my-hook.sh"
#   ln -sf "$REAL_ENGINE_DIR/config.sh" "$FAKE_HOME/.claude/engine/config.sh"
setup_test_env() {
  local session_name="${1:-test_session}"

  TMP_DIR=$(mktemp -d)
  export CLAUDE_SUPERVISOR_PID=99999999

  # Capture real paths before HOME switch
  REAL_SCRIPTS_DIR="$HOME/.claude/scripts"
  REAL_ENGINE_DIR="$HOME/.claude/engine"
  REAL_HOOKS_DIR="$HOME/.claude/hooks"

  setup_fake_home "$TMP_DIR"
  disable_fleet_tmux

  # Copy session.sh (NOT symlink) — prevents `cat > $HOME/.claude/scripts/session.sh`
  # in mock-writing tests from following a symlink and destroying the real file.
  # session.sh uses $HOME-based paths, not dirname $0, so a copy works identically.
  cp "$REAL_ENGINE_DIR/scripts/session.sh" "$FAKE_HOME/.claude/scripts/session.sh"
  chmod +x "$FAKE_HOME/.claude/scripts/session.sh"
  # lib.sh is read-only (sourced, never overwritten) — symlink is safe
  ln -sf "$REAL_SCRIPTS_DIR/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"

  # Stub fleet and search tools
  mock_fleet_sh "$FAKE_HOME"
  mock_search_tools "$FAKE_HOME"

  # Work in TMP_DIR so session.sh find scans our test sessions
  cd "$TMP_DIR"

  # Create test session directory
  TEST_SESSION="$TMP_DIR/sessions/$session_name"
  mkdir -p "$TEST_SESSION"
}

# cleanup_test_env — Restores HOME and removes temp directory.
# Usage: trap cleanup_test_env EXIT
cleanup_test_env() {
  teardown_fake_home
  rm -rf "${TMP_DIR:-}"
}
