#!/bin/bash
# ~/.claude/engine/scripts/tests/test-config-sh.sh — Deep coverage tests for config.sh
#
# Tests all 3 subcommands: get, set, list
# Covers: defaults, config.json creation, jq operations, error handling
#
# Run: bash ~/.claude/engine/scripts/tests/test-config-sh.sh

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

CONFIG_SH="$HOME/.claude/engine/scripts/config.sh"

TEST_DIR=""
ORIGINAL_HOME="$HOME"

setup() {
  TEST_DIR=$(mktemp -d)
  export HOME="$TEST_DIR/fake-home"
  mkdir -p "$HOME/.claude"
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

echo "=== config.sh Deep Coverage Tests ==="
echo ""

# ============================================================
# GET TESTS
# ============================================================
echo "--- Get: Defaults ---"

test_get_default_terminal_link_protocol() {
  # No config.json exists — should return default
  local output
  output=$(bash "$CONFIG_SH" get terminalLinkProtocol)

  if [[ "$output" == "cursor://file" ]]; then
    pass "GET-01: Returns default for terminalLinkProtocol"
  else
    fail "GET-01: Returns default for terminalLinkProtocol" \
      "cursor://file" "$output"
  fi
}
run_test test_get_default_terminal_link_protocol

test_get_default_unknown_key() {
  local output
  output=$(bash "$CONFIG_SH" get nonexistentKey)

  if [[ -z "$output" ]]; then
    pass "GET-02: Returns empty for unknown key with no default"
  else
    fail "GET-02: Returns empty for unknown key with no default" \
      "<empty>" "$output"
  fi
}
run_test test_get_default_unknown_key

test_get_creates_config_file() {
  # config.json shouldn't exist yet
  if [ -f "$HOME/.claude/config.json" ]; then
    fail "GET-03: Creates config.json on first access" \
      "No config.json before get" "File already exists"
    return
  fi

  bash "$CONFIG_SH" get terminalLinkProtocol > /dev/null

  if [ -f "$HOME/.claude/config.json" ]; then
    local content
    content=$(cat "$HOME/.claude/config.json")
    if [[ "$content" == "{}" ]]; then
      pass "GET-03: Creates empty config.json on first access"
    else
      fail "GET-03: Creates empty config.json on first access" \
        "{}" "$content"
    fi
  else
    fail "GET-03: Creates empty config.json on first access" \
      "File created" "File not created"
  fi
}
run_test test_get_creates_config_file

echo ""
echo "--- Get: From Config File ---"

test_get_from_config_file() {
  echo '{"terminalLinkProtocol":"vscode://file"}' > "$HOME/.claude/config.json"

  local output
  output=$(bash "$CONFIG_SH" get terminalLinkProtocol)

  if [[ "$output" == "vscode://file" ]]; then
    pass "GET-04: Returns value from config.json (overrides default)"
  else
    fail "GET-04: Returns value from config.json (overrides default)" \
      "vscode://file" "$output"
  fi
}
run_test test_get_from_config_file

test_get_custom_key_from_config() {
  echo '{"myCustomKey":"myValue"}' > "$HOME/.claude/config.json"

  local output
  output=$(bash "$CONFIG_SH" get myCustomKey)

  if [[ "$output" == "myValue" ]]; then
    pass "GET-05: Returns custom key from config.json"
  else
    fail "GET-05: Returns custom key from config.json" \
      "myValue" "$output"
  fi
}
run_test test_get_custom_key_from_config

# ============================================================
# SET TESTS
# ============================================================
echo ""
echo "--- Set ---"

test_set_creates_key() {
  bash "$CONFIG_SH" set myKey myValue > /dev/null

  local stored
  stored=$(jq -r '.myKey' "$HOME/.claude/config.json")
  if [[ "$stored" == "myValue" ]]; then
    pass "SET-01: Creates new key in config.json"
  else
    fail "SET-01: Creates new key in config.json" \
      "myValue" "$stored"
  fi
}
run_test test_set_creates_key

test_set_overwrites_existing() {
  echo '{"myKey":"oldValue"}' > "$HOME/.claude/config.json"

  bash "$CONFIG_SH" set myKey newValue > /dev/null

  local stored
  stored=$(jq -r '.myKey' "$HOME/.claude/config.json")
  if [[ "$stored" == "newValue" ]]; then
    pass "SET-02: Overwrites existing key"
  else
    fail "SET-02: Overwrites existing key" \
      "newValue" "$stored"
  fi
}
run_test test_set_overwrites_existing

test_set_preserves_other_keys() {
  echo '{"existingKey":"keepMe"}' > "$HOME/.claude/config.json"

  bash "$CONFIG_SH" set newKey newValue > /dev/null

  local existing
  existing=$(jq -r '.existingKey' "$HOME/.claude/config.json")
  local new_val
  new_val=$(jq -r '.newKey' "$HOME/.claude/config.json")
  if [[ "$existing" == "keepMe" ]] && [[ "$new_val" == "newValue" ]]; then
    pass "SET-03: Preserves existing keys when adding new"
  else
    fail "SET-03: Preserves existing keys when adding new" \
      "existingKey=keepMe, newKey=newValue" "existingKey=$existing, newKey=$new_val"
  fi
}
run_test test_set_preserves_other_keys

test_set_creates_config_if_missing() {
  # No config.json yet
  bash "$CONFIG_SH" set testKey testValue > /dev/null

  if [ -f "$HOME/.claude/config.json" ]; then
    local stored
    stored=$(jq -r '.testKey' "$HOME/.claude/config.json")
    if [[ "$stored" == "testValue" ]]; then
      pass "SET-04: Creates config.json if missing"
    else
      fail "SET-04: Creates config.json if missing" \
        "testValue" "$stored"
    fi
  else
    fail "SET-04: Creates config.json if missing" \
      "File created" "File not created"
  fi
}
run_test test_set_creates_config_if_missing

test_set_outputs_confirmation() {
  local output
  output=$(bash "$CONFIG_SH" set myKey myValue)

  if [[ "$output" == *"Set myKey"* ]] && [[ "$output" == *"myValue"* ]]; then
    pass "SET-05: Outputs confirmation message"
  else
    fail "SET-05: Outputs confirmation message" \
      "Set myKey = myValue" "$output"
  fi
}
run_test test_set_outputs_confirmation

# ============================================================
# LIST TESTS
# ============================================================
echo ""
echo "--- List ---"

test_list_shows_defaults() {
  local output
  output=$(bash "$CONFIG_SH" list)

  if [[ "$output" == *"terminalLinkProtocol"* ]] && [[ "$output" == *"cursor://file"* ]] && [[ "$output" == *"default"* ]]; then
    pass "LIST-01: Shows default values with (default) source"
  else
    fail "LIST-01: Shows default values with (default) source" \
      "terminalLinkProtocol = cursor://file (default)" "$output"
  fi
}
run_test test_list_shows_defaults

test_list_shows_config_values() {
  echo '{"myKey":"myValue"}' > "$HOME/.claude/config.json"

  local output
  output=$(bash "$CONFIG_SH" list)

  if [[ "$output" == *"myKey"* ]] && [[ "$output" == *"myValue"* ]] && [[ "$output" == *"config"* ]]; then
    pass "LIST-02: Shows config values with (config) source"
  else
    fail "LIST-02: Shows config values with (config) source" \
      "myKey = myValue (config)" "$output"
  fi
}
run_test test_list_shows_config_values

test_list_shows_both_config_and_defaults() {
  echo '{"customKey":"customValue"}' > "$HOME/.claude/config.json"

  local output
  output=$(bash "$CONFIG_SH" list)

  # Should have the custom key (config) AND the default key (default)
  if [[ "$output" == *"customKey"* ]] && [[ "$output" == *"terminalLinkProtocol"* ]]; then
    pass "LIST-03: Shows both config and default keys"
  else
    fail "LIST-03: Shows both config and default keys" \
      "Both customKey and terminalLinkProtocol" "$output"
  fi
}
run_test test_list_shows_both_config_and_defaults

test_list_config_overrides_default() {
  echo '{"terminalLinkProtocol":"vscode://file"}' > "$HOME/.claude/config.json"

  local output
  output=$(bash "$CONFIG_SH" list)

  if [[ "$output" == *"vscode://file"* ]] && [[ "$output" == *"config"* ]]; then
    pass "LIST-04: Config value overrides default in listing"
  else
    fail "LIST-04: Config value overrides default in listing" \
      "vscode://file (config)" "$output"
  fi
}
run_test test_list_config_overrides_default

# ============================================================
# ERROR HANDLING
# ============================================================
echo ""
echo "--- Error Handling ---"

test_no_args_errors() {
  local output
  output=$(bash "$CONFIG_SH" 2>&1)
  local rc=$?

  if [[ $rc -ne 0 ]] && [[ "$output" == *"Usage"* ]]; then
    pass "ERR-01: No arguments shows usage and exits 1"
  else
    fail "ERR-01: No arguments shows usage and exits 1" \
      "exit 1 + Usage" "rc=$rc, output=$output"
  fi
}
run_test test_no_args_errors

test_get_no_key_errors() {
  local output
  output=$(bash "$CONFIG_SH" get 2>&1)
  local rc=$?

  if [[ $rc -ne 0 ]] && [[ "$output" == *"Usage"* ]]; then
    pass "ERR-02: get without key shows usage"
  else
    fail "ERR-02: get without key shows usage" \
      "exit 1 + Usage" "rc=$rc, output=$output"
  fi
}
run_test test_get_no_key_errors

test_set_missing_value_errors() {
  local output
  output=$(bash "$CONFIG_SH" set keyOnly 2>&1)
  local rc=$?

  if [[ $rc -ne 0 ]] && [[ "$output" == *"Usage"* ]]; then
    pass "ERR-03: set without value shows usage"
  else
    fail "ERR-03: set without value shows usage" \
      "exit 1 + Usage" "rc=$rc, output=$output"
  fi
}
run_test test_set_missing_value_errors

test_unknown_action_errors() {
  local output
  output=$(bash "$CONFIG_SH" badcommand 2>&1)
  local rc=$?

  if [[ $rc -ne 0 ]] && [[ "$output" == *"Usage"* ]]; then
    pass "ERR-04: Unknown action shows usage"
  else
    fail "ERR-04: Unknown action shows usage" \
      "exit 1 + Usage" "rc=$rc, output=$output"
  fi
}
run_test test_unknown_action_errors

# ============================================================
# RESULTS
# ============================================================
exit_with_results
