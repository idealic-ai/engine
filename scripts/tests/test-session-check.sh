#!/bin/bash
# ~/.claude/engine/scripts/tests/test-session-check.sh
# Tests for session.sh check subcommand and deactivate checklist gate (checkPassed flow)
#
# Tests: JSON input validation, strict text diff, branching validation,
# checkbox normalization, deactivate gate, edge cases.
#
# Run: bash ~/.claude/engine/scripts/tests/test-session-check.sh

# Don't use set -e globally — we need to handle return codes manually in tests
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SESSION_SH="$HOME/.claude/engine/scripts/session.sh"
LIB_SH="$HOME/.claude/scripts/lib.sh"

# Temp directory for test fixtures
TEST_DIR=""
SESSION_DIR=""
ORIGINAL_HOME=""
ORIGINAL_PATH="$PATH"

setup() {
  TEST_DIR=$(mktemp -d)
  ORIGINAL_HOME="$HOME"
  export HOME="$TEST_DIR/fake-home"
  mkdir -p "$HOME/.claude/scripts"
  mkdir -p "$HOME/.claude/tools/session-search"
  mkdir -p "$HOME/.claude/tools/doc-search"

  # Copy session.sh (NOT symlink — prevents mock overwrites from destroying real file)
  cp "$SESSION_SH" "$HOME/.claude/scripts/session.sh"
  chmod +x "$HOME/.claude/scripts/session.sh"
  ln -sf "$LIB_SH" "$HOME/.claude/scripts/lib.sh"

  # Create mock fleet.sh (no-op)
  cat > "$HOME/.claude/scripts/fleet.sh" <<'MOCK'
#!/bin/bash
case "${1:-}" in
  pane-id) echo ""; exit 0 ;;
  notify)  exit 0 ;;
  *)       exit 0 ;;
esac
MOCK
  chmod +x "$HOME/.claude/scripts/fleet.sh"

  # Create mock search tools (no-op)
  for tool in session-search doc-search; do
    cat > "$HOME/.claude/tools/$tool/$tool.sh" <<'MOCK'
#!/bin/bash
echo "(none)"
MOCK
    chmod +x "$HOME/.claude/tools/$tool/$tool.sh"
  done

  # Override CLAUDE_SUPERVISOR_PID to current PID (alive)
  export CLAUDE_SUPERVISOR_PID=$$

  # Create session directory
  SESSION_DIR="$TEST_DIR/sessions/test-session"
  mkdir -p "$SESSION_DIR"
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  export PATH="$ORIGINAL_PATH"
  unset CLAUDE_SUPERVISOR_PID
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# Helper: write a .state.json fixture
write_state() {
  echo "$1" > "$SESSION_DIR/.state.json"
}

# Helper: write a CHECKLIST.md file on disk (for strict diff to read)
write_checklist() {
  local path="$1"
  local content="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s' "$content" > "$path"
}

# Helper: build JSON stdin for check command
# Usage: build_json "/path" "content" ["/path2" "content2" ...]
build_json() {
  local json="{}"
  while [ $# -ge 2 ]; do
    json=$(echo "$json" | jq --arg k "$1" --arg v "$2" '. + {($k): $v}')
    shift 2
  done
  echo "$json"
}

# =============================================================================
# session.sh check — JSON INPUT VALIDATION
# =============================================================================

test_check_fails_no_stdin() {
  local test_name="check: fails when no stdin is provided"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  write_checklist "$checklist_path" "- [ ] Item one"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" < /dev/null 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"JSON format required"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions JSON format" "exit=$exit_code, output=$output"
  fi
}

test_check_fails_invalid_json() {
  local test_name="check: fails when stdin is not valid JSON"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  write_checklist "$checklist_path" "- [ ] Item one"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" <<'EOF' 2>&1
## CHECKLIST: /path/to/CHECKLIST.md
- [x] This is old format, not JSON
EOF
  ) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"Invalid JSON"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions Invalid JSON" "exit=$exit_code, output=$output"
  fi
}

test_check_fails_missing_key() {
  local test_name="check: fails when a discovered checklist path is missing from JSON keys"
  local path1="$TEST_DIR/checklists/CHECKLIST.md"
  local path2="$TEST_DIR/checklists/OTHER.md"
  write_checklist "$path1" "- [ ] Item one"
  write_checklist "$path2" "- [ ] Item two"

  write_state "$(jq -n --arg p1 "$path1" --arg p2 "$path2" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p1, $p2]
  }')"

  # Only provide one of the two discovered checklists
  local json
  json=$(build_json "$path1" "- [x] Item one")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"missing from JSON input"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions missing from JSON" "exit=$exit_code, output=$output"
  fi
}

test_check_passes_no_checklists() {
  local test_name="check: passes trivially when no checklists are discovered"

  write_state '{
    "pid": 99999,
    "skill": "test",
    "lifecycle": "active"
  }'

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" < /dev/null 2>&1) || exit_code=$?

  local check_passed
  check_passed=$(jq -r '.checkPassed' "$SESSION_DIR/.state.json" 2>/dev/null || echo "false")

  if [ "$exit_code" -eq 0 ] && [ "$check_passed" = "true" ] && [[ "$output" == *"trivially"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, checkPassed=true, output contains trivially" "exit=$exit_code, checkPassed=$check_passed, output=$output"
  fi
}

# =============================================================================
# session.sh check — STRICT DIFF TESTS
# =============================================================================

test_diff_passes_happy_path() {
  local test_name="diff: passes when agent correctly reproduces checklist with [x] filled"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  local original="- [ ] Item one
- [ ] Item two
- [ ] Item three"
  write_checklist "$checklist_path" "$original"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  local agent_content="- [x] Item one
- [x] Item two
- [ ] Item three"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  local check_passed
  check_passed=$(jq -r '.checkPassed' "$SESSION_DIR/.state.json" 2>/dev/null || echo "false")

  if [ "$exit_code" -eq 0 ] && [ "$check_passed" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, checkPassed=true" "exit=$exit_code, checkPassed=$check_passed, output=$output"
  fi
}

test_diff_passes_multiple_checklists() {
  local test_name="diff: passes with multiple checklists all matching"
  local path1="$TEST_DIR/checklists/CHECKLIST.md"
  local path2="$TEST_DIR/checklists/OTHER.md"
  write_checklist "$path1" "- [ ] First item"
  write_checklist "$path2" "- [ ] Second item"

  write_state "$(jq -n --arg p1 "$path1" --arg p2 "$path2" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p1, $p2]
  }')"

  local json
  json=$(build_json "$path1" "- [x] First item" "$path2" "- [x] Second item")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  local check_passed
  check_passed=$(jq -r '.checkPassed' "$SESSION_DIR/.state.json" 2>/dev/null || echo "false")

  if [ "$exit_code" -eq 0 ] && [ "$check_passed" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, checkPassed=true" "exit=$exit_code, checkPassed=$check_passed, output=$output"
  fi
}

test_diff_fails_when_agent_modifies_text() {
  local test_name="diff: fails when agent modifies checklist item text"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  write_checklist "$checklist_path" "- [ ] Run all unit tests
- [ ] Update documentation"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  # Agent changes "unit tests" to "tests"
  local agent_content="- [x] Run all tests
- [x] Update documentation"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"content mismatch"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions content mismatch" "exit=$exit_code, output=$output"
  fi
}

test_diff_fails_when_agent_omits_items() {
  local test_name="diff: fails when agent omits checklist items"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  write_checklist "$checklist_path" "- [ ] Item one
- [ ] Item two
- [ ] Item three"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  # Agent only sends 2 of 3 items
  local agent_content="- [x] Item one
- [x] Item two"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"content mismatch"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions content mismatch" "exit=$exit_code, output=$output"
  fi
}

test_diff_fails_when_agent_adds_items() {
  local test_name="diff: fails when agent adds fabricated items"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  write_checklist "$checklist_path" "- [ ] Item one"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  # Agent adds an extra item
  local agent_content="- [x] Item one
- [x] Fabricated item"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"content mismatch"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions content mismatch" "exit=$exit_code, output=$output"
  fi
}

test_diff_normalizes_checkbox_variants() {
  local test_name="diff: normalizes [X] vs [x] — both treated as checked"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  # Original has [ ] (unchecked)
  write_checklist "$checklist_path" "- [ ] Item one
- [ ] Item two"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  # Agent uses [X] (uppercase) — should still pass since checkboxes are normalized
  local agent_content="- [X] Item one
- [x] Item two"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  local check_passed
  check_passed=$(jq -r '.checkPassed' "$SESSION_DIR/.state.json" 2>/dev/null || echo "false")

  if [ "$exit_code" -eq 0 ] && [ "$check_passed" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, checkPassed=true" "exit=$exit_code, checkPassed=$check_passed, output=$output"
  fi
}

test_diff_normalizes_trailing_whitespace() {
  local test_name="diff: trailing whitespace differences don't cause false failures"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  # Original has trailing spaces on some lines
  write_checklist "$checklist_path" "- [ ] Item one
- [ ] Item two  "

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  # Agent's version has no trailing spaces
  local agent_content="- [x] Item one
- [x] Item two"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  local check_passed
  check_passed=$(jq -r '.checkPassed' "$SESSION_DIR/.state.json" 2>/dev/null || echo "false")

  if [ "$exit_code" -eq 0 ] && [ "$check_passed" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, checkPassed=true" "exit=$exit_code, checkPassed=$check_passed, output=$output"
  fi
}

# =============================================================================
# session.sh check — BRANCHING VALIDATION (JSON format)
# =============================================================================

test_branching_one_branch_checked_passes() {
  local test_name="branching: one branch checked with all children checked — passes"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  local content="- [ ] I DID update the docs
  - [ ] README updated
  - [ ] CHANGELOG updated
- [ ] I DID NOT update the docs
  - [ ] Reason documented"
  write_checklist "$checklist_path" "$content"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  local agent_content="- [x] I DID update the docs
  - [x] README updated
  - [x] CHANGELOG updated
- [ ] I DID NOT update the docs
  - [ ] Reason documented"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0" "exit=$exit_code, output=$output"
  fi
}

test_branching_zero_branches_checked_fails() {
  local test_name="branching: zero branches checked — fails"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  local content="- [ ] I DID update the docs
  - [ ] README updated
- [ ] I DID NOT update the docs
  - [ ] Reason documented"
  write_checklist "$checklist_path" "$content"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  # Agent sends it back unchanged — no branch checked
  local json
  json=$(build_json "$checklist_path" "$content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"no branch parent checked"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions 'no branch parent checked'" "exit=$exit_code, output=$output"
  fi
}

test_branching_both_branches_checked_fails() {
  local test_name="branching: both branches checked — fails"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  local content="- [ ] I DID update the docs
  - [ ] README updated
- [ ] I DID NOT update the docs
  - [ ] Reason documented"
  write_checklist "$checklist_path" "$content"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  local agent_content="- [x] I DID update the docs
  - [x] README updated
- [x] I DID NOT update the docs
  - [x] Reason documented"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"branch parents checked"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions multiple parents checked" "exit=$exit_code, output=$output"
  fi
}

test_branching_unchecked_child_fails() {
  local test_name="branching: checked parent with unchecked child — fails"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  local content="- [ ] I DID update the docs
  - [ ] README updated
  - [ ] CHANGELOG updated
- [ ] I DID NOT update the docs
  - [ ] Reason documented"
  write_checklist "$checklist_path" "$content"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  local agent_content="- [x] I DID update the docs
  - [x] README updated
  - [ ] CHANGELOG updated
- [ ] I DID NOT update the docs
  - [ ] Reason documented"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"unchecked child"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions 'unchecked child'" "exit=$exit_code, output=$output"
  fi
}

test_flat_checklist_still_works() {
  local test_name="flat: checklist without nesting — passes"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  local content="- [ ] Item one
- [ ] Item two
- [ ] Item three"
  write_checklist "$checklist_path" "$content"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  local agent_content="- [x] Item one
- [ ] Item two
- [x] Item three"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0" "exit=$exit_code, output=$output"
  fi
}

test_branching_did_not_branch_passes() {
  local test_name="branching: DID NOT branch checked with all children — passes"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  local content="- [ ] I DID update the docs
  - [ ] README updated
  - [ ] CHANGELOG updated
- [ ] I DID NOT update the docs
  - [ ] Not applicable — no code changes"
  write_checklist "$checklist_path" "$content"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  local agent_content="- [ ] I DID update the docs
  - [ ] README updated
  - [ ] CHANGELOG updated
- [x] I DID NOT update the docs
  - [x] Not applicable — no code changes"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0" "exit=$exit_code, output=$output"
  fi
}

# =============================================================================
# session.sh deactivate — CHECKLIST GATE TESTS
# =============================================================================

test_deactivate_blocks_no_checkpassed() {
  local test_name="deactivate: blocks when checkPassed is not set but checklists discovered"

  write_state '{
    "pid": 99999,
    "skill": "test",
    "lifecycle": "active",
    "currentPhase": "4: Synthesis",
    "discoveredChecklists": ["/path/to/CHECKLIST.md"]
  }'

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" deactivate "$SESSION_DIR" <<'EOF' 2>&1
Test session deactivation attempt
EOF
  ) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"INV_CHECKLIST_BEFORE_CLOSE"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, output references INV_CHECKLIST_BEFORE_CLOSE" "exit=$exit_code, output=$output"
  fi
}

test_deactivate_allows_with_checkpassed() {
  local test_name="deactivate: allows when checkPassed is true"

  write_state '{
    "pid": 99999,
    "skill": "test",
    "lifecycle": "active",
    "discoveredChecklists": ["/path/to/CHECKLIST.md"],
    "checkPassed": true
  }'

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" deactivate "$SESSION_DIR" <<'EOF' 2>&1
Test session deactivation with checkPassed
EOF
  ) || exit_code=$?

  local lifecycle
  lifecycle=$(jq -r '.lifecycle' "$SESSION_DIR/.state.json" 2>/dev/null || echo "unknown")

  if [ "$exit_code" -eq 0 ] && [ "$lifecycle" = "completed" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, lifecycle=completed" "exit=$exit_code, lifecycle=$lifecycle, output=$output"
  fi
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

test_check_handles_paths_with_spaces() {
  local test_name="check: handles paths with spaces in checklist paths"
  local checklist_path="$TEST_DIR/checklists/with spaces/CHECKLIST.md"
  local content="- [ ] Item verified despite spaces in path"
  write_checklist "$checklist_path" "$content"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  local agent_content="- [x] Item verified despite spaces in path"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  local check_passed
  check_passed=$(jq -r '.checkPassed' "$SESSION_DIR/.state.json" 2>/dev/null || echo "false")

  if [ "$exit_code" -eq 0 ] && [ "$check_passed" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, checkPassed=true" "exit=$exit_code, checkPassed=$check_passed, output=$output"
  fi
}

test_check_fails_original_not_on_disk() {
  local test_name="check: fails when original checklist file doesn't exist on disk"
  local nonexistent_path="$TEST_DIR/checklists/MISSING.md"

  write_state "$(jq -n --arg p "$nonexistent_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  local json
  json=$(build_json "$nonexistent_path" "- [x] Item one")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"not found on disk"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions not found on disk" "exit=$exit_code, output=$output"
  fi
}

# =============================================================================
# CATEGORY A: V2 HARDENING — JSON INPUT EDGE CASES
# =============================================================================

test_check_fails_json_array() {
  local test_name="check: fails when JSON is an array instead of object"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  write_checklist "$checklist_path" "- [ ] Item one"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  local output exit_code=0
  output=$(echo '["not", "an", "object"]' | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"Expected JSON object"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions Expected JSON object" "exit=$exit_code, output=$output"
  fi
}

test_check_fails_null_value() {
  local test_name="check: fails when JSON value for checklist key is null"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  write_checklist "$checklist_path" "- [ ] Item one"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  local json
  json=$(jq -n --arg k "$checklist_path" '{($k): null}')

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"content mismatch"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions content mismatch" "exit=$exit_code, output=$output"
  fi
}

test_check_fails_empty_string_value() {
  local test_name="check: fails when JSON value is empty string"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  write_checklist "$checklist_path" "- [ ] Item one"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  local json
  json=$(build_json "$checklist_path" "")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"content mismatch"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions content mismatch" "exit=$exit_code, output=$output"
  fi
}

test_check_ignores_extra_json_keys() {
  local test_name="check: extra keys in JSON beyond discoveredChecklists are silently ignored"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  write_checklist "$checklist_path" "- [ ] Item one"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  # JSON has the discovered path + an extra undiscovered path
  local json
  json=$(jq -n --arg k "$checklist_path" --arg v "- [x] Item one" --arg extra "/fake/EXTRA.md" --arg ev "- [x] Extra" \
    '{($k): $v, ($extra): $ev}')

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  local check_passed
  check_passed=$(jq -r '.checkPassed' "$SESSION_DIR/.state.json" 2>/dev/null || echo "false")

  if [ "$exit_code" -eq 0 ] && [ "$check_passed" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, checkPassed=true" "exit=$exit_code, checkPassed=$check_passed, output=$output"
  fi
}

# =============================================================================
# CATEGORY B: V2 HARDENING — NORMALIZATION BOUNDARIES
# =============================================================================

test_diff_normalizes_crlf_in_original() {
  local test_name="diff: CRLF line endings in original don't cause false failure"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  # Write original with CRLF line endings
  mkdir -p "$(dirname "$checklist_path")"
  printf '%s\r\n%s\r\n' '- [ ] Item one' '- [ ] Item two' > "$checklist_path"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  # Agent sends with LF only
  local agent_content="- [x] Item one
- [x] Item two"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  local check_passed
  check_passed=$(jq -r '.checkPassed' "$SESSION_DIR/.state.json" 2>/dev/null || echo "false")

  if [ "$exit_code" -eq 0 ] && [ "$check_passed" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, checkPassed=true" "exit=$exit_code, checkPassed=$check_passed, output=$output"
  fi
}

test_diff_normalizes_crlf_in_agent() {
  local test_name="diff: CRLF line endings in agent content don't cause false failure"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  write_checklist "$checklist_path" "- [ ] Item one
- [ ] Item two"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  # Agent sends with CRLF
  local agent_content
  agent_content=$(printf '%s\r\n%s' '- [x] Item one' '- [x] Item two')
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  local check_passed
  check_passed=$(jq -r '.checkPassed' "$SESSION_DIR/.state.json" 2>/dev/null || echo "false")

  if [ "$exit_code" -eq 0 ] && [ "$check_passed" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, checkPassed=true" "exit=$exit_code, checkPassed=$check_passed, output=$output"
  fi
}

test_diff_handles_special_characters() {
  local test_name="diff: checklist with special characters (quotes, ampersands, backticks)"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  local content='- [ ] Check "quoted" value
- [ ] Verify & validate
- [ ] Run `test` command'
  write_checklist "$checklist_path" "$content"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  local agent_content='- [x] Check "quoted" value
- [x] Verify & validate
- [x] Run `test` command'
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  local check_passed
  check_passed=$(jq -r '.checkPassed' "$SESSION_DIR/.state.json" 2>/dev/null || echo "false")

  if [ "$exit_code" -eq 0 ] && [ "$check_passed" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, checkPassed=true" "exit=$exit_code, checkPassed=$check_passed, output=$output"
  fi
}

# =============================================================================
# CATEGORY C: V2 HARDENING — BRANCHING EDGE CASES
# =============================================================================

test_branching_mixed_flat_and_nested() {
  local test_name="branching: mixed flat + nested — checking flat item and branch parent fails"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  local content="- [ ] Simple standalone item
- [ ] I DID update the docs
  - [ ] README updated
- [ ] I DID NOT update the docs
  - [ ] Reason documented"
  write_checklist "$checklist_path" "$content"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  # Check both the flat item and one branch parent — should fail (2 parents checked)
  local agent_content="- [x] Simple standalone item
- [x] I DID update the docs
  - [x] README updated
- [ ] I DID NOT update the docs
  - [ ] Reason documented"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"branch parents checked"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions branch parents checked" "exit=$exit_code, output=$output"
  fi
}

test_diff_empty_original_file() {
  local test_name="diff: empty original file on disk — empty agent content passes"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  write_checklist "$checklist_path" ""

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  local json
  json=$(build_json "$checklist_path" "")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  local check_passed
  check_passed=$(jq -r '.checkPassed' "$SESSION_DIR/.state.json" 2>/dev/null || echo "false")

  if [ "$exit_code" -eq 0 ] && [ "$check_passed" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, checkPassed=true" "exit=$exit_code, checkPassed=$check_passed, output=$output"
  fi
}

# =============================================================================
# CATEGORY G: MULTI-SECTION BRANCHING
# =============================================================================

test_branching_multi_section_one_per_section_passes() {
  local test_name="branching: multi-section checklist with one branch checked per section — passes"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  local content="# Checklist

## Structure

- [ ] I DID create SKILL.md
  - [ ] Frontmatter valid
- [ ] I DID NOT create SKILL.md
  - [ ] Confirmed no changes

## Modes

- [ ] I DID create mode files
  - [ ] 3 named modes + custom
- [ ] I DID NOT create mode files
  - [ ] Confirmed no mode changes"
  write_checklist "$checklist_path" "$content"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  # Check one branch per section — should pass
  local agent_content="# Checklist

## Structure

- [x] I DID create SKILL.md
  - [x] Frontmatter valid
- [ ] I DID NOT create SKILL.md
  - [ ] Confirmed no changes

## Modes

- [ ] I DID create mode files
  - [ ] 3 named modes + custom
- [x] I DID NOT create mode files
  - [x] Confirmed no mode changes"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  local check_passed
  check_passed=$(jq -r '.checkPassed' "$SESSION_DIR/.state.json" 2>/dev/null || echo "false")

  if [ "$exit_code" -eq 0 ] && [ "$check_passed" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, checkPassed=true" "exit=$exit_code, checkPassed=$check_passed, output=$output"
  fi
}

test_branching_multi_section_zero_in_one_section_fails() {
  local test_name="branching: multi-section with zero branches checked in one section — fails"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  local content="# Checklist

## Structure

- [ ] I DID create SKILL.md
  - [ ] Frontmatter valid
- [ ] I DID NOT create SKILL.md
  - [ ] Confirmed no changes

## Modes

- [ ] I DID create mode files
  - [ ] 3 named modes + custom
- [ ] I DID NOT create mode files
  - [ ] Confirmed no mode changes"
  write_checklist "$checklist_path" "$content"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  # Structure section has one branch checked, but Modes section has zero
  local agent_content="# Checklist

## Structure

- [x] I DID create SKILL.md
  - [x] Frontmatter valid
- [ ] I DID NOT create SKILL.md
  - [ ] Confirmed no changes

## Modes

- [ ] I DID create mode files
  - [ ] 3 named modes + custom
- [ ] I DID NOT create mode files
  - [ ] Confirmed no mode changes"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"no branch parent checked"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions no branch parent checked" "exit=$exit_code, output=$output"
  fi
}

test_branching_multi_section_both_in_one_section_fails() {
  local test_name="branching: multi-section with both branches checked in one section — fails"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  local content="# Checklist

## Structure

- [ ] I DID create SKILL.md
  - [ ] Frontmatter valid
- [ ] I DID NOT create SKILL.md
  - [ ] Confirmed no changes

## Modes

- [ ] I DID create mode files
  - [ ] 3 named modes + custom
- [ ] I DID NOT create mode files
  - [ ] Confirmed no mode changes"
  write_checklist "$checklist_path" "$content"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  # Structure section correct, Modes section has both branches checked
  local agent_content="# Checklist

## Structure

- [x] I DID create SKILL.md
  - [x] Frontmatter valid
- [ ] I DID NOT create SKILL.md
  - [ ] Confirmed no changes

## Modes

- [x] I DID create mode files
  - [x] 3 named modes + custom
- [x] I DID NOT create mode files
  - [x] Confirmed no mode changes"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"branch parents checked"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions branch parents checked" "exit=$exit_code, output=$output"
  fi
}

test_branching_single_section_still_works() {
  local test_name="branching: single-section checklist still works (regression guard)"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  local content="- [ ] I DID update the docs
  - [ ] README updated
  - [ ] CHANGELOG updated
- [ ] I DID NOT update the docs
  - [ ] Reason documented"
  write_checklist "$checklist_path" "$content"

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  local agent_content="- [x] I DID update the docs
  - [x] README updated
  - [x] CHANGELOG updated
- [ ] I DID NOT update the docs
  - [ ] Reason documented"
  local json
  json=$(build_json "$checklist_path" "$agent_content")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0" "exit=$exit_code, output=$output"
  fi
}

# =============================================================================
# CATEGORY D: V1 — TAG SCAN BASIC COVERAGE
# =============================================================================

# Helper: write an .md file in the session directory
write_session_md() {
  local filename="$1"
  local content="$2"
  printf '%s' "$content" > "$SESSION_DIR/$filename"
}

test_tag_scan_passes_clean_files() {
  local test_name="tag scan: passes when no bare lifecycle tags in session .md files"

  write_state '{
    "pid": 99999,
    "skill": "test",
    "lifecycle": "active"
  }'

  # Create a clean .md file with no lifecycle tags
  write_session_md "NOTES.md" "# Notes
Some content without any tags."

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" < /dev/null 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ] && [[ "$output" == *"Tag scan passed"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, mentions Tag scan passed" "exit=$exit_code, output=$output"
  fi
}

test_tag_scan_fails_bare_inline_tag() {
  local test_name="tag scan: fails when bare #needs-implementation tag found inline"

  write_state '{
    "pid": 99999,
    "skill": "test",
    "lifecycle": "active"
  }'

  write_session_md "PLAN.md" "# Plan
## Step 1
This step #needs-implementation before we can proceed."

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" < /dev/null 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"Bare inline lifecycle tags"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions Bare inline lifecycle tags" "exit=$exit_code, output=$output"
  fi
}

test_tag_scan_ignores_backtick_escaped() {
  local test_name="tag scan: ignores backtick-escaped tags"

  write_state '{
    "pid": 99999,
    "skill": "test",
    "lifecycle": "active"
  }'

  write_session_md "LOG.md" '# Log
The `#needs-implementation` tag was processed.'

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" < /dev/null 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ] && [[ "$output" == *"Tag scan passed"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, mentions Tag scan passed" "exit=$exit_code, output=$output"
  fi
}

test_tag_scan_ignores_tags_line() {
  local test_name="tag scan: ignores tags on the **Tags**: line"

  write_state '{
    "pid": 99999,
    "skill": "test",
    "lifecycle": "active"
  }'

  write_session_md "DEBRIEF.md" '# Debrief
**Tags**: #needs-review
All work completed.'

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" < /dev/null 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ] && [[ "$output" == *"Tag scan passed"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, mentions Tag scan passed" "exit=$exit_code, output=$output"
  fi
}

test_tag_scan_skips_when_already_passed() {
  local test_name="tag scan: skips when tagCheckPassed is already true"

  write_state '{
    "pid": 99999,
    "skill": "test",
    "lifecycle": "active",
    "tagCheckPassed": true
  }'

  # Even with bare tags, should skip
  write_session_md "PLAN.md" "# Plan
This has #needs-implementation bare."

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" < /dev/null 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ] && [[ "$output" == *"already passed"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, mentions already passed" "exit=$exit_code, output=$output"
  fi
}

# =============================================================================
# CATEGORY E: V3 — REQUEST FILES BASIC COVERAGE
# =============================================================================

test_request_files_passes_none_declared() {
  local test_name="request files: passes when no request files declared"

  write_state '{
    "pid": 99999,
    "skill": "test",
    "lifecycle": "active",
    "tagCheckPassed": true
  }'

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" < /dev/null 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ] && [[ "$output" == *"No request files"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, mentions No request files" "exit=$exit_code, output=$output"
  fi
}

test_request_files_fails_missing_file() {
  local test_name="request files: fails when declared file doesn't exist"

  write_state "$(jq -n '{
    pid: 99999, skill: "test", lifecycle: "active",
    tagCheckPassed: true,
    requestFiles: ["/nonexistent/REQUEST_TEST.md"]
  }')"

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" < /dev/null 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"file not found"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions file not found" "exit=$exit_code, output=$output"
  fi
}

test_request_files_formal_fails_no_response() {
  local test_name="request files: formal REQUEST file fails without ## Response section"
  local req_file="$SESSION_DIR/REQUEST_TEST.md"

  printf '# Request\n**Tags**: \nPlease implement this feature.\n' > "$req_file"

  write_state "$(jq -n --arg f "$req_file" '{
    pid: 99999, skill: "test", lifecycle: "active",
    tagCheckPassed: true,
    requestFiles: [$f]
  }')"

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" < /dev/null 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"missing ## Response"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions missing ## Response" "exit=$exit_code, output=$output"
  fi
}

test_request_files_fails_bare_needs_tag() {
  local test_name="request files: fails when bare #needs-* tag found in file"
  local req_file="$SESSION_DIR/NOTES.md"

  printf '# Notes\nThis has #needs-brainstorm inline.\n' > "$req_file"

  write_state "$(jq -n --arg f "$req_file" '{
    pid: 99999, skill: "test", lifecycle: "active",
    tagCheckPassed: true,
    requestFiles: [$f]
  }')"

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" < /dev/null 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ] && [[ "$output" == *"bare #needs-* tags remain"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero, mentions bare #needs-* tags remain" "exit=$exit_code, output=$output"
  fi
}

test_request_files_skips_when_already_passed() {
  local test_name="request files: skips when requestCheckPassed is already true"

  write_state "$(jq -n '{
    pid: 99999, skill: "test", lifecycle: "active",
    tagCheckPassed: true,
    requestCheckPassed: true,
    requestFiles: ["/nonexistent/should-be-skipped.md"]
  }')"

  local output exit_code=0
  output=$("$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" < /dev/null 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ] && [[ "$output" == *"already passed"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, mentions already passed" "exit=$exit_code, output=$output"
  fi
}

# =============================================================================
# CATEGORY F: INTEGRATION
# =============================================================================

test_integration_all_three_pass() {
  local test_name="integration: all three validations pass together — checkPassed=true"
  local checklist_path="$TEST_DIR/checklists/CHECKLIST.md"
  write_checklist "$checklist_path" "- [ ] Item verified"

  # Clean session .md file (no bare tags)
  write_session_md "NOTES.md" "# Notes
Work completed successfully."

  write_state "$(jq -n --arg p "$checklist_path" '{
    pid: 99999, skill: "test", lifecycle: "active",
    discoveredChecklists: [$p]
  }')"

  local json
  json=$(build_json "$checklist_path" "- [x] Item verified")

  local output exit_code=0
  output=$(echo "$json" | "$HOME/.claude/scripts/session.sh" check "$SESSION_DIR" 2>&1) || exit_code=$?

  local check_passed tag_check_passed
  check_passed=$(jq -r '.checkPassed' "$SESSION_DIR/.state.json" 2>/dev/null || echo "false")
  tag_check_passed=$(jq -r '.tagCheckPassed' "$SESSION_DIR/.state.json" 2>/dev/null || echo "false")

  if [ "$exit_code" -eq 0 ] && [ "$check_passed" = "true" ] && [ "$tag_check_passed" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0, checkPassed=true, tagCheckPassed=true" "exit=$exit_code, checkPassed=$check_passed, tagCheckPassed=$tag_check_passed, output=$output"
  fi
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

echo "=== test-session-check.sh ==="

# JSON input validation
run_test test_check_fails_no_stdin
run_test test_check_fails_invalid_json
run_test test_check_fails_missing_key
run_test test_check_passes_no_checklists

# Strict diff
run_test test_diff_passes_happy_path
run_test test_diff_passes_multiple_checklists
run_test test_diff_fails_when_agent_modifies_text
run_test test_diff_fails_when_agent_omits_items
run_test test_diff_fails_when_agent_adds_items
run_test test_diff_normalizes_checkbox_variants
run_test test_diff_normalizes_trailing_whitespace

# Branching validation (JSON format)
run_test test_branching_one_branch_checked_passes
run_test test_branching_zero_branches_checked_fails
run_test test_branching_both_branches_checked_fails
run_test test_branching_unchecked_child_fails
run_test test_flat_checklist_still_works
run_test test_branching_did_not_branch_passes

# Deactivate gate
run_test test_deactivate_blocks_no_checkpassed
run_test test_deactivate_allows_with_checkpassed

# Edge cases
run_test test_check_handles_paths_with_spaces
run_test test_check_fails_original_not_on_disk

# Category A: V2 Hardening — JSON input edge cases
run_test test_check_fails_json_array
run_test test_check_fails_null_value
run_test test_check_fails_empty_string_value
run_test test_check_ignores_extra_json_keys

# Category B: V2 Hardening — Normalization boundaries
run_test test_diff_normalizes_crlf_in_original
run_test test_diff_normalizes_crlf_in_agent
run_test test_diff_handles_special_characters

# Category C: V2 Hardening — Branching edge cases
run_test test_branching_mixed_flat_and_nested
run_test test_diff_empty_original_file

# Category G: Multi-section branching
run_test test_branching_multi_section_one_per_section_passes
run_test test_branching_multi_section_zero_in_one_section_fails
run_test test_branching_multi_section_both_in_one_section_fails
run_test test_branching_single_section_still_works

# Category D: V1 — Tag scan basic coverage
run_test test_tag_scan_passes_clean_files
run_test test_tag_scan_fails_bare_inline_tag
run_test test_tag_scan_ignores_backtick_escaped
run_test test_tag_scan_ignores_tags_line
run_test test_tag_scan_skips_when_already_passed

# Category E: V3 — Request files basic coverage
run_test test_request_files_passes_none_declared
run_test test_request_files_fails_missing_file
run_test test_request_files_formal_fails_no_response
run_test test_request_files_fails_bare_needs_tag
run_test test_request_files_skips_when_already_passed

# Category F: Integration
run_test test_integration_all_three_pass

# Summary
exit_with_results
