#!/bin/bash
# Tests for gemini.sh — generic Gemini API wrapper
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Capture real paths before HOME switch
GEMINI_SH="$SCRIPT_DIR/gemini.sh"
LIB_SH="$SCRIPT_DIR/lib.sh"

setup() {
  TMP_DIR=$(mktemp -d)
  setup_fake_home "$TMP_DIR"
  mock_fleet_sh "$FAKE_HOME"
  disable_fleet_tmux

  # Symlink gemini.sh and lib.sh into fake home
  ln -sf "$GEMINI_SH" "$FAKE_HOME/.claude/scripts/gemini.sh"
  ln -sf "$LIB_SH" "$FAKE_HOME/.claude/scripts/lib.sh"

  export PROJECT_ROOT="$TMP_DIR/project"
  mkdir -p "$PROJECT_ROOT"

  # Set a fake API key
  export GEMINI_API_KEY="test-key-12345"
}

teardown() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}

# ---- Helper: create a mock curl that returns a canned response ----
install_mock_curl() {
  local response_text="${1:-Hello from Gemini}"
  cat > "$TMP_DIR/curl" <<MOCK
#!/bin/bash
# Mock curl — returns a canned Gemini response
cat <<'JSON'
{
  "candidates": [{
    "content": {
      "parts": [{ "text": "${response_text}" }]
    }
  }]
}
JSON
MOCK
  chmod +x "$TMP_DIR/curl"
  export PATH="$TMP_DIR:$PATH"
}

# ---- Helper: create a mock curl that returns an error ----
install_mock_curl_error() {
  local error_msg="${1:-Rate limit exceeded}"
  cat > "$TMP_DIR/curl" <<MOCK
#!/bin/bash
cat <<'JSON'
{
  "error": {
    "message": "${error_msg}"
  }
}
JSON
MOCK
  chmod +x "$TMP_DIR/curl"
  export PATH="$TMP_DIR:$PATH"
}

# ---- Helper: create a mock curl that captures the request body ----
install_mock_curl_capture() {
  local response_text="${1:-captured}"
  cat > "$TMP_DIR/curl" <<'MOCK'
#!/bin/bash
# Capture the -d argument (request body) to a file
for arg in "$@"; do
  PREV="${CURRENT:-}"
  CURRENT="$arg"
  if [ "$PREV" = "-d" ]; then
    echo "$arg" > /tmp/gemini-test-captured-body.json
  fi
done
cat <<'JSON'
{
  "candidates": [{
    "content": {
      "parts": [{ "text": "captured" }]
    }
  }]
}
JSON
MOCK
  chmod +x "$TMP_DIR/curl"
  export PATH="$TMP_DIR:$PATH"
}

# ============================================================
# Tests
# ============================================================

test_gemini_help() {
  local output
  output=$("$GEMINI_SH" --help 2>&1)
  assert_contains "Usage: engine gemini" "$output" "help shows usage"
  assert_contains "temperature" "$output" "help mentions temperature flag"
  assert_contains "model" "$output" "help mentions model flag"
  assert_contains "system" "$output" "help mentions system flag"
}

test_gemini_basic_prompt() {
  install_mock_curl "Hello world"
  local output
  output=$(echo "Say hello" | "$GEMINI_SH" 2>/dev/null)
  assert_eq "Hello world" "$output" "basic prompt returns Gemini response on stdout"
}

test_gemini_stderr_status() {
  install_mock_curl "test"
  local stderr_output
  stderr_output=$(echo "Say hello" | "$GEMINI_SH" 2>&1 >/dev/null)
  assert_contains "Calling Gemini" "$stderr_output" "status message on stderr"
  assert_contains "gemini-3-pro-preview" "$stderr_output" "default model in status"
}

test_gemini_no_prompt_fails() {
  install_mock_curl "test"
  local output
  output=$(echo "" | "$GEMINI_SH" 2>&1) || true
  assert_contains "No prompt provided" "$output" "fails on empty stdin"
}

test_gemini_no_api_key_fails() {
  unset GEMINI_API_KEY
  # Also prevent .env fallback by cd-ing into a dir with no .env
  local output
  output=$(cd "$TMP_DIR" && echo "hello" | "$GEMINI_SH" 2>&1) || true
  assert_contains "GEMINI_API_KEY" "$output" "fails without API key"
}

test_gemini_api_error() {
  install_mock_curl_error "Rate limit exceeded"
  local output exit_code
  output=$(echo "hello" | "$GEMINI_SH" 2>&1) || exit_code=$?
  assert_contains "Rate limit exceeded" "$output" "shows API error message"
  assert_neq "0" "${exit_code:-0}" "exits non-zero on API error"
}

test_gemini_context_files() {
  install_mock_curl_capture
  # Create context files
  echo "File one content" > "$TMP_DIR/file1.md"
  echo "File two content" > "$TMP_DIR/file2.md"

  local output
  output=$(echo "Summarize these" | "$GEMINI_SH" "$TMP_DIR/file1.md" "$TMP_DIR/file2.md" 2>/dev/null)
  assert_eq "captured" "$output" "returns response with context files"

  # Check the captured request body contains file content
  local body
  body=$(cat /tmp/gemini-test-captured-body.json 2>/dev/null || echo "")
  assert_contains "file1.md" "$body" "request body includes file1 name"
  assert_contains "file2.md" "$body" "request body includes file2 name"
  assert_contains "File one content" "$body" "request body includes file1 content"
  assert_contains "File two content" "$body" "request body includes file2 content"
  rm -f /tmp/gemini-test-captured-body.json
}

test_gemini_missing_context_file_warns() {
  install_mock_curl "ok"
  local stderr_output
  stderr_output=$(echo "hello" | "$GEMINI_SH" "/nonexistent/file.md" 2>&1 >/dev/null)
  assert_contains "WARNING" "$stderr_output" "warns about missing context file"
  assert_contains "skipping" "$stderr_output" "mentions skipping"
}

test_gemini_system_instruction() {
  install_mock_curl_capture
  echo "hello" | "$GEMINI_SH" --system "You are a helpful assistant" 2>/dev/null

  local body
  body=$(cat /tmp/gemini-test-captured-body.json 2>/dev/null || echo "")
  assert_contains "systemInstruction" "$body" "request includes system instruction"
  assert_contains "You are a helpful assistant" "$body" "system instruction text is included"
  rm -f /tmp/gemini-test-captured-body.json
}

test_gemini_no_system_instruction() {
  install_mock_curl_capture
  echo "hello" | "$GEMINI_SH" 2>/dev/null

  local body
  body=$(cat /tmp/gemini-test-captured-body.json 2>/dev/null || echo "")
  assert_not_contains "systemInstruction" "$body" "no system instruction when not specified"
  rm -f /tmp/gemini-test-captured-body.json
}

test_gemini_unknown_option_fails() {
  install_mock_curl "test"
  local output
  output=$(echo "hello" | "$GEMINI_SH" --unknown-flag 2>&1) || true
  assert_contains "Unknown option" "$output" "rejects unknown flags"
}

test_gemini_no_context_files() {
  install_mock_curl_capture
  echo "just a prompt" | "$GEMINI_SH" 2>/dev/null

  local body
  body=$(cat /tmp/gemini-test-captured-body.json 2>/dev/null || echo "")
  assert_not_contains "CONTEXT FILES" "$body" "no context section when no files given"
  rm -f /tmp/gemini-test-captured-body.json
}

# ---- Run ----
run_test test_gemini_help
run_test test_gemini_basic_prompt
run_test test_gemini_stderr_status
run_test test_gemini_no_prompt_fails
run_test test_gemini_no_api_key_fails
run_test test_gemini_api_error
run_test test_gemini_context_files
run_test test_gemini_missing_context_file_warns
run_test test_gemini_system_instruction
run_test test_gemini_no_system_instruction
run_test test_gemini_unknown_option_fails
run_test test_gemini_no_context_files
exit_with_results
