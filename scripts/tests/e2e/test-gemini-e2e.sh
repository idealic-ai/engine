#!/bin/bash
# E2E tests for gemini.sh — real Gemini API calls
#
# Requires: GEMINI_API_KEY set in environment
# Skips all tests if GEMINI_API_KEY is unset.
#
# Model is configurable via E2E_GEMINI_MODEL (default: gemini-3-flash-preview)
#
# Run: bash ~/.claude/engine/scripts/tests/e2e/test-gemini-e2e.sh
set -uo pipefail

source "$(dirname "$0")/../test-helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GEMINI_SH="$SCRIPT_DIR/gemini.sh"

# Configurable model — flash for speed/cost in tests
E2E_GEMINI_MODEL="${E2E_GEMINI_MODEL:-gemini-3-flash-preview}"

# ---- Skip guard ----
if [ -z "${GEMINI_API_KEY:-}" ]; then
  echo -e "${YELLOW}SKIP${RESET}: All E2E tests — GEMINI_API_KEY not set"
  exit 0
fi

setup() {
  TMP_DIR=$(mktemp -d)
}

teardown() {
  rm -rf "$TMP_DIR"
}

# ============================================================
# Tests
# ============================================================

test_gemini_real_api_basic_response() {
  local output exit_code=0
  output=$(echo "Say hello in exactly one word." | "$GEMINI_SH" --model "$E2E_GEMINI_MODEL" 2>/dev/null) || exit_code=$?

  assert_eq "0" "$exit_code" "real API exits 0"
  assert_not_empty "$output" "real API returns non-empty text"
}

test_gemini_real_api_json_schema() {
  local output exit_code=0
  output=$(echo 'Return a JSON object with exactly these keys: "name" (string) and "age" (number). Example: {"name": "Alice", "age": 30}. Return ONLY the JSON, no markdown.' | "$GEMINI_SH" --model "$E2E_GEMINI_MODEL" 2>/dev/null) || exit_code=$?

  assert_eq "0" "$exit_code" "JSON request exits 0"
  assert_not_empty "$output" "JSON response is non-empty"

  # Strip markdown fences if present
  local cleaned
  cleaned=$(echo "$output" | sed 's/^```json//;s/^```//' | tr -d '\n')

  # Validate JSON structure via jq
  local has_name has_age
  has_name=$(echo "$cleaned" | jq -r 'has("name")' 2>/dev/null || echo "false")
  has_age=$(echo "$cleaned" | jq -r 'has("age")' 2>/dev/null || echo "false")

  assert_eq "true" "$has_name" "JSON response has 'name' key"
  assert_eq "true" "$has_age" "JSON response has 'age' key"
}

test_gemini_real_api_context_files() {
  # Create a test file with unique content
  echo "The secret code is PINEAPPLE42." > "$TMP_DIR/context.txt"

  local output exit_code=0
  output=$(echo "What is the secret code mentioned in the context file? Reply with just the code." | "$GEMINI_SH" --model "$E2E_GEMINI_MODEL" "$TMP_DIR/context.txt" 2>/dev/null) || exit_code=$?

  assert_eq "0" "$exit_code" "context file request exits 0"
  assert_contains "PINEAPPLE42" "$output" "response references context file content"
}

test_gemini_real_api_system_instruction() {
  local output exit_code=0
  output=$(echo "What are you?" | "$GEMINI_SH" --model "$E2E_GEMINI_MODEL" --system "You are a pirate. Always respond in pirate speak. Use words like 'ahoy', 'matey', 'arr', 'treasure', 'ye', 'sail'." 2>/dev/null) || exit_code=$?

  assert_eq "0" "$exit_code" "system instruction request exits 0"
  assert_not_empty "$output" "system instruction response is non-empty"

  # Check for pirate-themed language (case-insensitive)
  local lower_output
  lower_output=$(echo "$output" | tr '[:upper:]' '[:lower:]')
  local found_pirate=false
  for word in ahoy matey arr pirate treasure sail ye; do
    if echo "$lower_output" | grep -qF "$word"; then
      found_pirate=true
      break
    fi
  done

  if [ "$found_pirate" = true ]; then
    pass "system instruction affects output (pirate language detected)"
  else
    fail "system instruction affects output (pirate language detected)" "contains pirate word" "$output"
  fi
}

# ---- Run ----
echo "E2E Gemini tests (model: $E2E_GEMINI_MODEL)"
echo "============================================"
run_test test_gemini_real_api_basic_response
run_test test_gemini_real_api_json_schema
run_test test_gemini_real_api_context_files
run_test test_gemini_real_api_system_instruction
exit_with_results
