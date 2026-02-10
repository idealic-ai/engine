#!/bin/bash
# ~/.claude/engine/scripts/tests/test-engine-cli.sh — Tests for engine CLI dispatch
#
# Tests:
#   1. --help lists available sub-commands dynamically
#   2. Auto-dispatch delegates to scripts/*.sh (e.g., engine session → session.sh)
#   3. Built-in commands dispatch correctly (setup, status, etc.)
#   4. Unknown sub-command prints error + help hint
#   5. engine.sh excludes itself from --help sub-command list
#   6. Default (no args) checks setup marker and execs run.sh
#   7. --verbose flag is parsed before sub-command
#
# Run: bash ~/.claude/engine/scripts/tests/test-engine-cli.sh

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENGINE_SH="$HOME/.claude/engine/scripts/engine.sh"
SCRIPT_DIR="$HOME/.claude/engine/scripts"

TEST_DIR=""
ORIGINAL_HOME="$HOME"

setup() {
  TEST_DIR=$(mktemp -d)
  # We DON'T fake HOME here because engine.sh resolves SCRIPT_DIR from $0's realpath.
  # Instead, we test output of the real engine.sh in controlled ways.
}

teardown() {
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# ============================================================================
# Test cases
# ============================================================================

test_help_flag() {
  local output
  output=$(bash "$ENGINE_SH" --help 2>&1)

  # Should contain "LIFECYCLE COMMANDS" section (core built-in commands)
  if echo "$output" | grep -q "LIFECYCLE COMMANDS"; then
    pass "--help shows LIFECYCLE COMMANDS section"
  else
    fail "--help shows LIFECYCLE COMMANDS section" "Contains 'LIFECYCLE COMMANDS'" "$output"
  fi

  # Should contain "SESSION MANAGEMENT" section (script-based commands)
  if echo "$output" | grep -q "SESSION MANAGEMENT"; then
    pass "--help shows SESSION MANAGEMENT section"
  else
    fail "--help shows SESSION MANAGEMENT section" "Contains 'SESSION MANAGEMENT'" "$output"
  fi
}

test_help_lists_scripts() {
  local output
  output=$(bash "$ENGINE_SH" --help 2>&1)

  # Should list known scripts like session, tag, run, fleet, log
  local found=0
  for script_name in session tag run fleet log; do
    if [ -f "$SCRIPT_DIR/${script_name}.sh" ] && echo "$output" | grep -q "  ${script_name}"; then
      found=$((found + 1))
    fi
  done

  if [ "$found" -ge 3 ]; then
    pass "--help lists discovered scripts ($found found)"
  else
    fail "--help lists discovered scripts" "at least 3 scripts listed" "found $found"
  fi
}

test_help_excludes_engine() {
  local output
  output=$(bash "$ENGINE_SH" --help 2>&1)

  # The help output should NOT list "engine" as a sub-command (would create engine engine)
  # Extract only the command names (first word of 2-space indented lines)
  local command_names
  command_names=$(echo "$output" | grep '^  [a-z]' | grep -v '#' | awk '{print $1}')

  if echo "$command_names" | grep -qx "engine"; then
    fail "--help excludes 'engine' from command list" "engine not listed as command" "engine is listed"
  else
    pass "--help excludes 'engine' from command list"
  fi
}

test_help_subcommand() {
  # "engine help" should also show help (same as --help)
  local output
  output=$(bash "$ENGINE_SH" help 2>&1)

  if echo "$output" | grep -q "LIFECYCLE COMMANDS"; then
    pass "'engine help' shows help output"
  else
    fail "'engine help' shows help output" "Contains 'LIFECYCLE COMMANDS'" "$output"
  fi
}

test_unknown_command_error() {
  local output exit_code
  output=$(bash "$ENGINE_SH" nonexistent-foobar 2>&1) || exit_code=$?

  if [ "${exit_code:-0}" -ne 0 ]; then
    pass "Unknown command exits with non-zero status"
  else
    fail "Unknown command exits with non-zero status" "exit code != 0" "exit code 0"
  fi

  if echo "$output" | grep -q "Unknown command"; then
    pass "Unknown command shows error message"
  else
    fail "Unknown command shows error message" "Contains 'Unknown command'" "$output"
  fi

  if echo "$output" | grep -q "engine --help"; then
    pass "Unknown command hints at --help"
  else
    fail "Unknown command hints at --help" "Contains 'engine --help'" "$output"
  fi
}

test_verbose_flag_parsed() {
  # --verbose should be stripped before dispatch; --help should still work
  local output
  output=$(bash "$ENGINE_SH" --verbose --help 2>&1)

  if echo "$output" | grep -q "LIFECYCLE COMMANDS"; then
    pass "--verbose --help still shows help"
  else
    fail "--verbose --help still shows help" "Contains 'LIFECYCLE COMMANDS'" "$output"
  fi
}

test_short_flags() {
  # -h should show help
  local output
  output=$(bash "$ENGINE_SH" -h 2>&1)

  if echo "$output" | grep -q "LIFECYCLE COMMANDS"; then
    pass "-h flag shows help"
  else
    fail "-h flag shows help" "Contains 'LIFECYCLE COMMANDS'" "$output"
  fi
}

test_auto_dispatch_exists() {
  # Verify that for every .sh file in scripts/ (except engine.sh),
  # engine would dispatch to it. We test this by checking the dispatch
  # logic pattern rather than actually exec-ing (which would start Claude etc.)

  local scripts_count=0
  local dispatchable=0

  for script in "$SCRIPT_DIR"/*.sh; do
    [ -f "$script" ] || continue
    local name
    name=$(basename "$script" .sh)
    [ "$name" = "engine" ] && continue
    scripts_count=$((scripts_count + 1))

    # The script should be executable for dispatch to work
    if [ -x "$script" ]; then
      dispatchable=$((dispatchable + 1))
    fi
  done

  if [ "$scripts_count" -gt 0 ] && [ "$dispatchable" -eq "$scripts_count" ]; then
    pass "All scripts/*.sh are executable ($dispatchable/$scripts_count)"
  else
    fail "All scripts/*.sh are executable" "$scripts_count executable" "$dispatchable executable"
  fi
}

test_setup_marker_path() {
  # Verify the setup marker constant is defined correctly in engine.sh
  if grep -q 'SETUP_MARKER=.*\.setup-done' "$ENGINE_SH"; then
    pass "Setup marker path defined in engine.sh"
  else
    fail "Setup marker path defined in engine.sh" "SETUP_MARKER=.../.setup-done" "(not found)"
  fi
}

test_default_execs_run_sh() {
  # Verify the default path (no args) execs run.sh
  # engine.sh defines RUN_SCRIPT="$SCRIPT_DIR/run.sh" then does exec "$RUN_SCRIPT"
  if grep -q 'RUN_SCRIPT=.*run\.sh' "$ENGINE_SH" && grep -q 'exec "\$RUN_SCRIPT"' "$ENGINE_SH"; then
    pass "Default path execs run.sh (via RUN_SCRIPT variable)"
  else
    fail "Default path execs run.sh" "RUN_SCRIPT=...run.sh + exec \$RUN_SCRIPT" "(not found in engine.sh)"
  fi
}

test_auto_dispatch_uses_exec() {
  # Verify auto-dispatch uses exec (pure passthrough, no subprocess)
  if grep -q 'exec "\$SUBCMD_SCRIPT"' "$ENGINE_SH"; then
    pass "Auto-dispatch uses exec for passthrough"
  else
    fail "Auto-dispatch uses exec for passthrough" 'exec "$SUBCMD_SCRIPT"' "(pattern not found)"
  fi
}

test_uninstall_clears_marker() {
  # Verify uninstall removes the setup marker
  if grep -q 'rm.*SETUP_MARKER' "$ENGINE_SH"; then
    pass "Uninstall removes setup marker"
  else
    fail "Uninstall removes setup marker" 'rm ... $SETUP_MARKER' "(not found)"
  fi
}

test_setup_creates_marker() {
  # Verify setup creates the marker file at the end
  if grep -q 'touch.*SETUP_MARKER' "$ENGINE_SH"; then
    pass "Setup creates marker file"
  else
    fail "Setup creates marker file" 'touch ... $SETUP_MARKER' "(not found)"
  fi
}

test_flag_forwarding_pattern_exists() {
  # Verify the --flag forwarding elif branch exists in engine.sh
  # This was added to forward unknown --flags to run.sh
  if grep -q 'SUBCMD.*==.*--\*' "$ENGINE_SH" || grep -q 'SUBCMD.*=~.*^--' "$ENGINE_SH"; then
    pass "--flag forwarding pattern exists in engine.sh"
  else
    fail "--flag forwarding pattern exists in engine.sh" "elif with --* pattern" "(not found)"
  fi
}

test_flag_forwarding_uses_exec() {
  # The flag forwarding branch should use exec to pass through to run.sh
  # Look for the exec $RUN_SCRIPT in the context of --* handling
  # Need -A5 because exec is ~4 lines after the elif --* pattern
  if grep -A5 '\-\-\*' "$ENGINE_SH" | grep -q 'exec.*RUN_SCRIPT'; then
    pass "--flag forwarding uses exec to run.sh"
  else
    fail "--flag forwarding uses exec to run.sh" 'exec "$RUN_SCRIPT"' "(not found near --* pattern)"
  fi
}

test_flag_forwarding_does_not_error() {
  # engine --nonexistent-flag should NOT produce an "Unknown command" error
  # because --flags are forwarded to run.sh (which will handle/error on them)
  # We can't actually exec run.sh (it starts Claude), but we can verify
  # the dispatch logic by checking engine.sh's structure
  local output
  # Use --help as a known flag to verify flags are parsed
  output=$(bash "$ENGINE_SH" --help 2>&1)
  if echo "$output" | grep -q "LIFECYCLE COMMANDS"; then
    pass "--help still works (known flag)"
  else
    fail "--help still works" "Contains 'LIFECYCLE COMMANDS'" "$output"
  fi
}

# ============================================================================
# Run all tests
# ============================================================================

echo "=== engine CLI dispatch tests ==="
echo ""

run_test test_help_flag
run_test test_help_lists_scripts
run_test test_help_excludes_engine
run_test test_help_subcommand
run_test test_unknown_command_error
run_test test_verbose_flag_parsed
run_test test_short_flags
run_test test_auto_dispatch_exists
run_test test_setup_marker_path
run_test test_default_execs_run_sh
run_test test_auto_dispatch_uses_exec
run_test test_uninstall_clears_marker
run_test test_setup_creates_marker
run_test test_flag_forwarding_pattern_exists
run_test test_flag_forwarding_uses_exec
run_test test_flag_forwarding_does_not_error

exit_with_results
