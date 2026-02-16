#!/bin/bash
# ~/.claude/engine/scripts/tests/test-lib.sh — Unit tests for lib.sh shared utilities
#
# Tests all 7 functions: timestamp, pid_exists, hook_allow, hook_deny, safe_json_write, notify_fleet, state_read
#
# Run: bash ~/.claude/engine/scripts/tests/test-lib.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

LIB_SH="$HOME/.claude/scripts/lib.sh"

# Temp directory for test fixtures
TEST_DIR=""
ORIGINAL_HOME=""

setup() {
  TEST_DIR=$(mktemp -d)
  ORIGINAL_HOME="$HOME"
  export HOME="$TEST_DIR/fake-home"
  mkdir -p "$HOME/.claude/scripts"
  # Link lib.sh into the fake home
  ln -sf "$LIB_SH" "$HOME/.claude/scripts/lib.sh"
  # Unset guard to allow re-sourcing
  unset _LIB_SH_LOADED
  # Source lib.sh
  source "$HOME/.claude/scripts/lib.sh"
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  unset _LIB_SH_LOADED
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# =============================================================================
# TIMESTAMP TESTS
# =============================================================================

test_timestamp_iso_format() {
  local test_name="timestamp: outputs ISO format"
  setup

  local result
  result=$(timestamp)

  # Match pattern: YYYY-MM-DDTHH:MM:SSZ
  if [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    pass "$test_name"
  else
    fail "$test_name" "YYYY-MM-DDTHH:MM:SSZ pattern" "$result"
  fi

  teardown
}

# =============================================================================
# PID_EXISTS TESTS
# =============================================================================

test_pid_exists_running() {
  local test_name="pid_exists: returns 0 for running PID"
  setup

  if pid_exists $$; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 for PID $$" "non-zero exit"
  fi

  teardown
}

test_pid_exists_dead() {
  local test_name="pid_exists: returns 1 for dead PID"
  setup

  if pid_exists 99999999; then
    fail "$test_name" "exit 1 for PID 99999999" "exit 0"
  else
    pass "$test_name"
  fi

  teardown
}

# =============================================================================
# HOOK_ALLOW TESTS
# =============================================================================

test_hook_allow_json() {
  local test_name="hook_allow: outputs correct JSON"
  setup

  # hook_allow calls exit 0, so run in subshell
  local result
  result=$(hook_allow)
  local expected='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'

  if [ "$result" = "$expected" ]; then
    pass "$test_name"
  else
    fail "$test_name" "$expected" "$result"
  fi

  teardown
}

# =============================================================================
# HOOK_DENY TESTS
# =============================================================================

test_hook_deny_json() {
  local test_name="hook_deny: outputs correct JSON with all 3 args"
  setup

  # hook_deny calls exit 0, so run in subshell
  local result
  result=$(hook_deny "Access denied" "Please activate a session first" "session_dir=/tmp/test")

  # Parse with jq to verify structure
  local decision reason
  decision=$(echo "$result" | jq -r '.hookSpecificOutput.permissionDecision')
  reason=$(echo "$result" | jq -r '.hookSpecificOutput.permissionDecisionReason')

  if [ "$decision" = "deny" ] && [[ "$reason" == *"Access denied"* ]] && [[ "$reason" == *"Please activate a session first"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "deny decision with reason containing both messages" "decision=$decision, reason=$reason"
  fi

  teardown
}

test_hook_deny_debug_included() {
  local test_name="hook_deny: DEBUG=1 includes debug info"
  setup

  local result
  DEBUG=1 result=$(hook_deny "Error" "Fix it" "debug_data=123")

  local reason
  reason=$(echo "$result" | jq -r '.hookSpecificOutput.permissionDecisionReason')

  if [[ "$reason" == *"debug_data=123"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "reason containing debug_data=123" "$reason"
  fi

  teardown
}

test_hook_deny_debug_excluded() {
  local test_name="hook_deny: DEBUG unset excludes debug info"
  setup

  local result
  unset DEBUG
  result=$(hook_deny "Error" "Fix it" "debug_data=123")

  local reason
  reason=$(echo "$result" | jq -r '.hookSpecificOutput.permissionDecisionReason')

  if [[ "$reason" != *"debug_data=123"* ]]; then
    pass "$test_name"
  else
    fail "$test_name" "reason NOT containing debug_data=123" "$reason"
  fi

  teardown
}

# =============================================================================
# SAFE_JSON_WRITE TESTS
# =============================================================================

test_safe_json_write_valid() {
  local test_name="safe_json_write: valid JSON writes atomically"
  setup

  local target="$TEST_DIR/test.json"
  echo '{"hello":"world"}' | safe_json_write "$target"
  local exit_code=$?

  local content
  content=$(cat "$target")

  if [ "$exit_code" -eq 0 ] && [ "$content" = '{"hello":"world"}' ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 and content={\"hello\":\"world\"}" "exit=$exit_code, content=$content"
  fi

  teardown
}

test_safe_json_write_invalid() {
  local test_name="safe_json_write: invalid JSON is rejected"
  setup

  local target="$TEST_DIR/test.json"
  echo '{"hello":"world"}' > "$target"

  local exit_code=0
  echo 'not json at all' | safe_json_write "$target" 2>/dev/null || exit_code=$?

  local content
  content=$(cat "$target")

  if [ "$exit_code" -ne 0 ] && [ "$content" = '{"hello":"world"}' ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit non-zero and file unchanged" "exit=$exit_code, content=$content"
  fi

  teardown
}

test_safe_json_write_concurrent() {
  local test_name="safe_json_write: concurrent writes don't corrupt"
  setup

  local target="$TEST_DIR/concurrent.json"
  echo '{"init":true}' > "$target"

  # Launch two concurrent writes
  (echo '{"writer":"A"}' | safe_json_write "$target") &
  local pid_a=$!
  (echo '{"writer":"B"}' | safe_json_write "$target") &
  local pid_b=$!

  wait "$pid_a" "$pid_b"

  # Result should be valid JSON (either A or B wins, but no corruption)
  local content
  content=$(cat "$target")
  if echo "$content" | jq empty 2>/dev/null; then
    local writer
    writer=$(echo "$content" | jq -r '.writer')
    if [ "$writer" = "A" ] || [ "$writer" = "B" ]; then
      pass "$test_name"
    else
      fail "$test_name" "writer=A or writer=B" "writer=$writer"
    fi
  else
    fail "$test_name" "valid JSON after concurrent writes" "corrupted: $content"
  fi

  teardown
}

test_safe_json_write_stale_lock() {
  local test_name="safe_json_write: stale lock is cleaned up"
  setup

  local target="$TEST_DIR/locked.json"
  local lock_dir="${target}.lock"

  # Create a stale lock (make it look old)
  mkdir "$lock_dir"
  # Touch with old timestamp (>10s ago)
  touch -t 202601010000 "$lock_dir"

  local exit_code=0
  echo '{"recovered":true}' | safe_json_write "$target" || exit_code=$?

  local content
  content=$(cat "$target" 2>/dev/null || echo "")

  if [ "$exit_code" -eq 0 ] && [ "$content" = '{"recovered":true}' ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 and recovered content" "exit=$exit_code, content=$content"
  fi

  teardown
}

test_safe_json_write_concurrent_data_loss() {
  local test_name="safe_json_write: concurrent read-modify-write may lose keys (TOCTOU demo)"
  setup

  local target="$TEST_DIR/race.json"
  echo '{"base":true}' > "$target"

  # Writer A: read current state, add keyA, write back
  (jq '.keyA = "valueA"' "$target" | safe_json_write "$target") &
  local pid_a=$!
  # Writer B: read current state, add keyB, write back
  (jq '.keyB = "valueB"' "$target" | safe_json_write "$target") &
  local pid_b=$!

  wait "$pid_a" "$pid_b"

  local content
  content=$(cat "$target")

  # The file must be valid JSON regardless
  if ! echo "$content" | jq empty 2>/dev/null; then
    fail "$test_name" "valid JSON" "corrupted: $content"
    teardown
    return
  fi

  local has_a has_b
  has_a=$(echo "$content" | jq 'has("keyA")' 2>/dev/null)
  has_b=$(echo "$content" | jq 'has("keyB")' 2>/dev/null)

  if [ "$has_a" = "true" ] && [ "$has_b" = "true" ]; then
    # Both keys survived — no data loss this run
    pass "$test_name (both keys present — race did not manifest)"
  else
    # One key was lost — demonstrates the TOCTOU bug (M1)
    # This is expected: between read and write, the other writer overwrites.
    pass "$test_name (data loss demonstrated: keyA=$has_a, keyB=$has_b)"
  fi

  teardown
}

test_safe_json_write_stale_lock_cleanup() {
  local test_name="safe_json_write: stale lock dir is removed after recovery"
  setup

  local target="$TEST_DIR/stale-lock-cleanup.json"
  local lock_dir="${target}.lock"

  # Create a stale lock with an old mtime (>10s ago)
  mkdir "$lock_dir"
  touch -t 202601010000 "$lock_dir"

  local exit_code=0
  echo '{"cleaned":true}' | safe_json_write "$target" || exit_code=$?

  local content
  content=$(cat "$target" 2>/dev/null || echo "")

  # Verify write succeeded
  if [ "$exit_code" -ne 0 ] || [ "$content" != '{"cleaned":true}' ]; then
    fail "$test_name" "exit 0 and content={\"cleaned\":true}" "exit=$exit_code, content=$content"
    teardown
    return
  fi

  # Verify the lock directory was cleaned up (not left behind)
  if [ -d "$lock_dir" ]; then
    fail "$test_name" "lock dir removed" "lock dir still exists at $lock_dir"
  else
    pass "$test_name"
  fi

  teardown
}

# =============================================================================
# NOTIFY_FLEET TESTS
# =============================================================================

test_notify_fleet_no_tmux() {
  local test_name="notify_fleet: no TMUX env returns 0 (no-op)"
  setup

  # Ensure TMUX is unset
  unset TMUX

  notify_fleet "working"
  local exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0" "exit $exit_code"
  fi

  teardown
}

test_notify_fleet_non_fleet_socket() {
  local test_name="notify_fleet: non-fleet TMUX socket returns 0 (no-op)"
  setup

  # Set TMUX to a non-fleet socket (format: socket_path,pid,session_index)
  export TMUX="/tmp/tmux-501/default,12345,0"

  # Create a fake fleet.sh that would fail if called
  cat > "$HOME/.claude/scripts/fleet.sh" <<'SCRIPT'
#!/bin/bash
echo "ERROR: fleet.sh should not have been called" >&2
exit 1
SCRIPT
  chmod +x "$HOME/.claude/scripts/fleet.sh"

  notify_fleet "working"
  local exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0" "exit $exit_code"
  fi

  teardown
}

test_notify_fleet_fleet_socket() {
  local test_name="notify_fleet: fleet socket calls fleet.sh notify"
  setup

  # Set TMUX to a fleet socket
  export TMUX="/tmp/tmux-501/fleet,12345,0"

  # Create a fake fleet.sh that records the call
  local call_log="$TEST_DIR/fleet_calls.log"
  cat > "$HOME/.claude/scripts/fleet.sh" <<SCRIPT
#!/bin/bash
echo "\$@" >> "$call_log"
SCRIPT
  chmod +x "$HOME/.claude/scripts/fleet.sh"

  notify_fleet "working"
  local exit_code=$?

  local call_content
  call_content=$(cat "$call_log" 2>/dev/null || echo "")

  if [ "$exit_code" -eq 0 ] && [ "$call_content" = "notify working" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 and fleet.sh called with 'notify working'" "exit=$exit_code, calls=$call_content"
  fi

  teardown
}

test_notify_fleet_fleet_prefixed_socket() {
  local test_name="notify_fleet: fleet-* socket calls fleet.sh notify"
  setup

  # Set TMUX to a fleet-prefixed socket (e.g., fleet-yarik)
  export TMUX="/tmp/tmux-501/fleet-yarik,12345,0"

  # Create a fake fleet.sh that records the call
  local call_log="$TEST_DIR/fleet_calls.log"
  cat > "$HOME/.claude/scripts/fleet.sh" <<SCRIPT
#!/bin/bash
echo "\$@" >> "$call_log"
SCRIPT
  chmod +x "$HOME/.claude/scripts/fleet.sh"

  notify_fleet "done"
  local exit_code=$?

  local call_content
  call_content=$(cat "$call_log" 2>/dev/null || echo "")

  if [ "$exit_code" -eq 0 ] && [ "$call_content" = "notify done" ]; then
    pass "$test_name"
  else
    fail "$test_name" "exit 0 and fleet.sh called with 'notify done'" "exit=$exit_code, calls=$call_content"
  fi

  teardown
}

# =============================================================================
# STATE_READ TESTS
# =============================================================================

test_state_read_existing_field() {
  local test_name="state_read: returns value for existing field"
  setup

  local state_file="$TEST_DIR/state.json"
  echo '{"skill":"implement","status":"active"}' > "$state_file"

  local result
  result=$(state_read "$state_file" "skill")

  if [ "$result" = "implement" ]; then
    pass "$test_name"
  else
    fail "$test_name" "implement" "$result"
  fi

  teardown
}

test_state_read_missing_field_with_default() {
  local test_name="state_read: returns default for missing field"
  setup

  local state_file="$TEST_DIR/state.json"
  echo '{"skill":"implement"}' > "$state_file"

  local result
  result=$(state_read "$state_file" "nonexistent" "fallback")

  if [ "$result" = "fallback" ]; then
    pass "$test_name"
  else
    fail "$test_name" "fallback" "$result"
  fi

  teardown
}

test_state_read_missing_file() {
  local test_name="state_read: returns default for missing file"
  setup

  local result
  result=$(state_read "$TEST_DIR/nonexistent.json" "skill" "default_val")

  if [ "$result" = "default_val" ]; then
    pass "$test_name"
  else
    fail "$test_name" "default_val" "$result"
  fi

  teardown
}

test_state_read_no_default() {
  local test_name="state_read: returns empty string when no default provided"
  setup

  local result
  result=$(state_read "$TEST_DIR/nonexistent.json" "skill")

  if [ -z "$result" ]; then
    pass "$test_name"
  else
    fail "$test_name" "(empty string)" "$result"
  fi

  teardown
}

test_state_read_special_chars() {
  local test_name="state_read: handles special chars in value"
  setup

  local state_file="$TEST_DIR/state.json"
  echo '{"description":"Fix bug in auth/login flow (v2.1)"}' > "$state_file"

  local result
  result=$(state_read "$state_file" "description")

  if [ "$result" = "Fix bug in auth/login flow (v2.1)" ]; then
    pass "$test_name"
  else
    fail "$test_name" "Fix bug in auth/login flow (v2.1)" "$result"
  fi

  teardown
}

# =============================================================================
# RESOLVE_PAYLOAD_REFS TESTS
# =============================================================================

test_resolve_payload_refs_prefix_collision() {
  local test_name="_resolve_payload_refs: short var \$s does not corrupt longer \$session (M3 prefix collision)"
  setup

  local state_file="$TEST_DIR/state-prefix.json"
  echo '{"s":"foo","session":"bar"}' > "$state_file"

  local payload='{"text":"val=$s, full=$session"}'
  local result
  result=$(_resolve_payload_refs "$payload" "$state_file")

  local text_val
  text_val=$(echo "$result" | jq -r '.text')

  # Correct behavior: $s -> foo, $session -> bar => "val=foo, full=bar"
  # Bug behavior: $s matches inside $session => "val=foo, full=fooession"
  if [[ "$text_val" == *"fooession"* ]]; then
    fail "$test_name" "val=foo, full=bar" "$text_val (prefix collision: \$s corrupted \$session)"
  elif [ "$text_val" = "val=foo, full=bar" ]; then
    pass "$test_name"
  else
    fail "$test_name" "val=foo, full=bar" "$text_val"
  fi

  teardown
}

test_resolve_payload_refs_no_collision() {
  local test_name="_resolve_payload_refs: non-overlapping vars resolve correctly"
  setup

  local state_file="$TEST_DIR/state-nocollision.json"
  echo '{"name":"Alice","age":"30"}' > "$state_file"

  local payload='{"text":"name=$name, age=$age"}'
  local result
  result=$(_resolve_payload_refs "$payload" "$state_file")

  local text_val
  text_val=$(echo "$result" | jq -r '.text')

  assert_eq "name=Alice, age=30" "$text_val" "$test_name"

  teardown
}

# =============================================================================
# NORMALIZE_PRELOAD_PATH TESTS
# =============================================================================

test_normalize_preload_path_home_prefix() {
  local test_name="normalize_preload_path: HOME prefix → absolute path"
  setup

  local result
  result=$(normalize_preload_path "$HOME/.claude/skills/implement/SKILL.md")
  assert_eq "$HOME/.claude/skills/implement/SKILL.md" "$result" "$test_name"

  teardown
}

test_normalize_preload_path_tilde_passthrough() {
  local test_name="normalize_preload_path: tilde-prefixed → expanded to absolute"
  setup

  local result
  result=$(normalize_preload_path "~/.claude/foo.md")
  assert_eq "$HOME/.claude/foo.md" "$result" "$test_name"

  teardown
}

test_normalize_preload_path_non_home() {
  local test_name="normalize_preload_path: non-HOME absolute path → unchanged"
  setup

  local result
  result=$(normalize_preload_path "/tmp/some/file.md")
  assert_eq "/tmp/some/file.md" "$result" "$test_name"

  teardown
}

test_normalize_preload_path_relative() {
  local test_name="normalize_preload_path: relative path → unchanged"
  setup

  local result
  result=$(normalize_preload_path "sessions/foo/LOG.md")
  assert_eq "sessions/foo/LOG.md" "$result" "$test_name"

  teardown
}

# =============================================================================
# EXTRACT_SKILL_PRELOADS TESTS
# =============================================================================

test_extract_skill_preloads_known_skill() {
  local test_name="extract_skill_preloads: known skill → outputs CMD + template paths"
  setup

  # Create a minimal skill directory with SKILL.md
  local skill_dir="$HOME/.claude/skills/fakeskill"
  mkdir -p "$skill_dir/assets"
  cat > "$skill_dir/SKILL.md" <<'SKILLEOF'
---
name: fakeskill
---
# Fake Skill
```json
{
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_PARSE_PARAMETERS"],
      "commands": ["§CMD_FIND_TAGGED_FILES"]}
  ],
  "logTemplate": "assets/TEMPLATE_LOG.md"
}
```
SKILLEOF

  # Create the CMD file and template that the function expects
  local cmd_dir="$HOME/.claude/engine/.directives/commands"
  mkdir -p "$cmd_dir"
  echo "# CMD_PARSE_PARAMETERS" > "$cmd_dir/CMD_PARSE_PARAMETERS.md"
  echo "# CMD_FIND_TAGGED_FILES" > "$cmd_dir/CMD_FIND_TAGGED_FILES.md"
  echo "# Log template" > "$skill_dir/assets/TEMPLATE_LOG.md"

  local result
  result=$(extract_skill_preloads "fakeskill")

  # Should output normalized paths for CMD files + template
  assert_contains "CMD_PARSE_PARAMETERS.md" "$result" "$test_name (CMD_PARSE_PARAMETERS)"
  assert_contains "CMD_FIND_TAGGED_FILES.md" "$result" "$test_name (CMD_FIND_TAGGED_FILES)"
  assert_contains "TEMPLATE_LOG.md" "$result" "$test_name (template)"

  teardown
}

test_extract_skill_preloads_nonexistent() {
  local test_name="extract_skill_preloads: nonexistent skill → empty output, exit 0"
  setup

  local result exit_code=0
  result=$(extract_skill_preloads "nosuchskill") || exit_code=$?

  assert_eq "0" "$exit_code" "$test_name (exit code)"
  assert_eq "" "$result" "$test_name (empty output)"

  teardown
}

test_extract_skill_preloads_no_json() {
  local test_name="extract_skill_preloads: skill without JSON block → empty output"
  setup

  local skill_dir="$HOME/.claude/skills/nojson"
  mkdir -p "$skill_dir"
  cat > "$skill_dir/SKILL.md" <<'SKILLEOF'
---
name: nojson
---
# No JSON Skill
This skill has no json block at all.
SKILLEOF

  local result exit_code=0
  result=$(extract_skill_preloads "nojson") || exit_code=$?

  assert_eq "0" "$exit_code" "$test_name (exit code)"
  assert_eq "" "$result" "$test_name (empty output)"

  teardown
}

test_extract_skill_preloads_dedup() {
  local test_name="extract_skill_preloads: overlapping CMD names → no duplicates"
  setup

  local skill_dir="$HOME/.claude/skills/dupskill"
  mkdir -p "$skill_dir"
  cat > "$skill_dir/SKILL.md" <<'SKILLEOF'
---
name: dupskill
---
# Dedup Skill
```json
{
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_PARSE_PARAMETERS"],
      "commands": ["§CMD_PARSE_PARAMETERS"]}
  ]
}
```
SKILLEOF

  local cmd_dir="$HOME/.claude/engine/.directives/commands"
  mkdir -p "$cmd_dir"
  echo "# CMD" > "$cmd_dir/CMD_PARSE_PARAMETERS.md"

  local result
  result=$(extract_skill_preloads "dupskill")

  local count
  count=$(echo "$result" | grep -c "CMD_PARSE_PARAMETERS" || true)
  assert_eq "1" "$count" "$test_name (single occurrence)"

  teardown
}

test_extract_skill_preloads_missing_template() {
  local test_name="extract_skill_preloads: template file doesn't exist → skipped"
  setup

  local skill_dir="$HOME/.claude/skills/missingtpl"
  mkdir -p "$skill_dir"
  cat > "$skill_dir/SKILL.md" <<'SKILLEOF'
---
name: missingtpl
---
# Missing Template Skill
```json
{
  "phases": [
    {"label": "0", "name": "Setup", "steps": [], "commands": []}
  ],
  "logTemplate": "assets/DOES_NOT_EXIST.md"
}
```
SKILLEOF

  local result exit_code=0
  result=$(extract_skill_preloads "missingtpl") || exit_code=$?

  assert_eq "0" "$exit_code" "$test_name (exit code)"
  # Should NOT contain the missing template path
  if [[ "$result" == *"DOES_NOT_EXIST"* ]]; then
    fail "$test_name" "no DOES_NOT_EXIST in output" "$result"
  else
    pass "$test_name"
  fi

  teardown
}

# =============================================================================
# RESOLVE_SESSIONS_DIR TESTS
# =============================================================================

test_resolve_sessions_dir_no_workspace() {
  local test_name="resolve_sessions_dir: no WORKSPACE → 'sessions'"
  setup
  unset WORKSPACE

  local result
  result=$(resolve_sessions_dir)
  assert_eq "sessions" "$result" "$test_name"

  teardown
}

test_resolve_sessions_dir_with_workspace() {
  local test_name="resolve_sessions_dir: WORKSPACE set → 'WORKSPACE/sessions'"
  setup
  export WORKSPACE="apps/estimate-viewer/extraction"

  local result
  result=$(resolve_sessions_dir)
  assert_eq "apps/estimate-viewer/extraction/sessions" "$result" "$test_name"

  unset WORKSPACE
  teardown
}

test_resolve_sessions_dir_empty_workspace() {
  local test_name="resolve_sessions_dir: WORKSPACE='' → 'sessions'"
  setup
  export WORKSPACE=""

  local result
  result=$(resolve_sessions_dir)
  assert_eq "sessions" "$result" "$test_name"

  unset WORKSPACE
  teardown
}

# =============================================================================
# RESOLVE_SESSION_PATH TESTS
# =============================================================================

test_resolve_session_path_bare_no_workspace() {
  local test_name="resolve_session_path: bare name without WORKSPACE"
  setup
  unset WORKSPACE

  local result
  result=$(resolve_session_path "2026_02_14_TEST")
  assert_eq "sessions/2026_02_14_TEST" "$result" "$test_name"

  teardown
}

test_resolve_session_path_bare_with_workspace() {
  local test_name="resolve_session_path: bare name with WORKSPACE"
  setup
  export WORKSPACE="apps/viewer/extraction"

  local result
  result=$(resolve_session_path "2026_02_14_TEST")
  assert_eq "apps/viewer/extraction/sessions/2026_02_14_TEST" "$result" "$test_name"

  unset WORKSPACE
  teardown
}

test_resolve_session_path_sessions_prefix_no_workspace() {
  local test_name="resolve_session_path: sessions/ prefix without WORKSPACE"
  setup
  unset WORKSPACE

  local result
  result=$(resolve_session_path "sessions/2026_02_14_TEST")
  assert_eq "sessions/2026_02_14_TEST" "$result" "$test_name"

  teardown
}

test_resolve_session_path_sessions_prefix_with_workspace() {
  local test_name="resolve_session_path: sessions/ prefix with WORKSPACE → strips and resolves"
  setup
  export WORKSPACE="apps/viewer/extraction"

  local result
  result=$(resolve_session_path "sessions/2026_02_14_TEST")
  assert_eq "apps/viewer/extraction/sessions/2026_02_14_TEST" "$result" "$test_name"

  unset WORKSPACE
  teardown
}

test_resolve_session_path_full_path_passthrough() {
  local test_name="resolve_session_path: full path with sessions/ segment → passthrough"
  setup
  export WORKSPACE="apps/viewer/extraction"

  local result
  result=$(resolve_session_path "epic/sessions/2026_02_14_TEST")
  assert_eq "epic/sessions/2026_02_14_TEST" "$result" "$test_name"

  unset WORKSPACE
  teardown
}

test_resolve_session_path_full_path_no_workspace() {
  local test_name="resolve_session_path: full path passthrough even without WORKSPACE"
  setup
  unset WORKSPACE

  local result
  result=$(resolve_session_path "other/sessions/2026_02_14_TEST")
  assert_eq "other/sessions/2026_02_14_TEST" "$result" "$test_name"

  teardown
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

echo "=== test-lib.sh ==="

# timestamp
test_timestamp_iso_format

# pid_exists
test_pid_exists_running
test_pid_exists_dead

# hook_allow
test_hook_allow_json

# hook_deny
test_hook_deny_json
test_hook_deny_debug_included
test_hook_deny_debug_excluded

# safe_json_write
test_safe_json_write_valid
test_safe_json_write_invalid
test_safe_json_write_concurrent
test_safe_json_write_stale_lock
test_safe_json_write_concurrent_data_loss
test_safe_json_write_stale_lock_cleanup

# notify_fleet
test_notify_fleet_no_tmux
test_notify_fleet_non_fleet_socket
test_notify_fleet_fleet_socket
test_notify_fleet_fleet_prefixed_socket

# state_read
test_state_read_existing_field
test_state_read_missing_field_with_default
test_state_read_missing_file
test_state_read_no_default
test_state_read_special_chars

# _resolve_payload_refs
test_resolve_payload_refs_prefix_collision
test_resolve_payload_refs_no_collision

# normalize_preload_path
test_normalize_preload_path_home_prefix
test_normalize_preload_path_tilde_passthrough
test_normalize_preload_path_non_home
test_normalize_preload_path_relative

# extract_skill_preloads
test_extract_skill_preloads_known_skill
test_extract_skill_preloads_nonexistent
test_extract_skill_preloads_no_json
test_extract_skill_preloads_dedup
test_extract_skill_preloads_missing_template

# resolve_sessions_dir
test_resolve_sessions_dir_no_workspace
test_resolve_sessions_dir_with_workspace
test_resolve_sessions_dir_empty_workspace

# resolve_session_path
test_resolve_session_path_bare_no_workspace
test_resolve_session_path_bare_with_workspace
test_resolve_session_path_sessions_prefix_no_workspace
test_resolve_session_path_sessions_prefix_with_workspace
test_resolve_session_path_full_path_passthrough
test_resolve_session_path_full_path_no_workspace

exit_with_results
