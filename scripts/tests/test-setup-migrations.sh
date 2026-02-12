#!/bin/bash
# ============================================================================
# test-setup-migrations.sh — Tests for setup-migrations.sh
# ============================================================================
# Tests each migration (fresh, idempotent, partial) and the runner.
# Pattern: temp dirs, no network, no GDrive.
# ============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MIGRATIONS_SH="$SCRIPT_DIR/../setup-migrations.sh"

# ---- Setup / Teardown ----
TEST_DIR=""

setup() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "$TEST_DIR/claude"
  mkdir -p "$TEST_DIR/engine"
  mkdir -p "$TEST_DIR/sessions"
  export SETUP_MIGRATION_STATE="$TEST_DIR/migration-state"
}

teardown() {
  [ -n "$TEST_DIR" ] && rm -rf "$TEST_DIR"
  unset SETUP_MIGRATION_STATE
}

# Source the migrations
source "$MIGRATIONS_SH"

# ============================================================================
# Migration 001: perfile_scripts_hooks
# ============================================================================
echo "=== Migration 001: perfile_scripts_hooks ==="

# Fresh: whole-dir symlink → per-file
setup
mkdir -p "$TEST_DIR/engine/scripts"
echo '#!/bin/bash' > "$TEST_DIR/engine/scripts/session.sh"
echo '#!/bin/bash' > "$TEST_DIR/engine/scripts/log.sh"
chmod +x "$TEST_DIR/engine/scripts/"*.sh
ln -s "$TEST_DIR/engine/scripts" "$TEST_DIR/claude/scripts"
migration_001_perfile_scripts_hooks "$TEST_DIR/claude" "$TEST_DIR/engine"
[ -d "$TEST_DIR/claude/scripts" ] && [ ! -L "$TEST_DIR/claude/scripts" ] && pass "M001-01: Converts whole-dir symlink to real dir" || fail "M001-01" "real dir" "symlink"
[ -L "$TEST_DIR/claude/scripts/session.sh" ] && pass "M001-02: Creates per-file symlinks" || fail "M001-02" "symlink" "not"
teardown

# Idempotent: already a real dir with per-file symlinks
setup
mkdir -p "$TEST_DIR/claude/scripts"
echo '#!/bin/bash' > "$TEST_DIR/engine/scripts/session.sh"
ln -s "$TEST_DIR/engine/scripts/session.sh" "$TEST_DIR/claude/scripts/session.sh"
migration_001_perfile_scripts_hooks "$TEST_DIR/claude" "$TEST_DIR/engine"
rc=$?
[ "$rc" -eq 0 ] && pass "M001-03: Idempotent — no-op when already per-file" || fail "M001-03" "exit 0" "exit $rc"
[ -L "$TEST_DIR/claude/scripts/session.sh" ] && pass "M001-04: Existing per-file symlinks preserved" || fail "M001-04" "symlink" "not"
teardown

# Hooks subdir too
setup
mkdir -p "$TEST_DIR/engine/hooks"
echo '#!/bin/bash' > "$TEST_DIR/engine/hooks/overflow.sh"
chmod +x "$TEST_DIR/engine/hooks/overflow.sh"
ln -s "$TEST_DIR/engine/hooks" "$TEST_DIR/claude/hooks"
migration_001_perfile_scripts_hooks "$TEST_DIR/claude" "$TEST_DIR/engine"
[ -d "$TEST_DIR/claude/hooks" ] && [ ! -L "$TEST_DIR/claude/hooks" ] && pass "M001-05: Hooks also migrated" || fail "M001-05" "real dir" "symlink"
teardown

# ============================================================================
# Migration 002: perfile_skills
# ============================================================================
echo ""
echo "=== Migration 002: perfile_skills ==="

# Fresh: whole-dir symlink → per-skill
setup
mkdir -p "$TEST_DIR/engine/skills/brainstorm" "$TEST_DIR/engine/skills/implement"
echo "# SKILL" > "$TEST_DIR/engine/skills/brainstorm/SKILL.md"
echo "# SKILL" > "$TEST_DIR/engine/skills/implement/SKILL.md"
ln -s "$TEST_DIR/engine/skills" "$TEST_DIR/claude/skills"
migration_002_perfile_skills "$TEST_DIR/claude" "$TEST_DIR/engine"
[ -d "$TEST_DIR/claude/skills" ] && [ ! -L "$TEST_DIR/claude/skills" ] && pass "M002-01: Converts whole-dir skills to real dir" || fail "M002-01" "real dir" "symlink"
[ -L "$TEST_DIR/claude/skills/brainstorm" ] && pass "M002-02: brainstorm skill symlinked" || fail "M002-02" "symlink" "not"
[ -L "$TEST_DIR/claude/skills/implement" ] && pass "M002-03: implement skill symlinked" || fail "M002-03" "symlink" "not"
teardown

# Idempotent: already per-skill
setup
mkdir -p "$TEST_DIR/claude/skills"
mkdir -p "$TEST_DIR/engine/skills/brainstorm"
ln -s "$TEST_DIR/engine/skills/brainstorm" "$TEST_DIR/claude/skills/brainstorm"
migration_002_perfile_skills "$TEST_DIR/claude" "$TEST_DIR/engine"
rc=$?
[ "$rc" -eq 0 ] && pass "M002-04: Idempotent — no-op when already per-skill" || fail "M002-04" "exit 0" "exit $rc"
teardown

# ============================================================================
# Migration 003: state_json_rename
# ============================================================================
echo ""
echo "=== Migration 003: state_json_rename ==="

# Fresh: .agent.json → .state.json
setup
mkdir -p "$TEST_DIR/sessions/2026_02_01_FOO"
echo '{"pid":123}' > "$TEST_DIR/sessions/2026_02_01_FOO/.agent.json"
migration_003_state_json_rename "$TEST_DIR/claude" "$TEST_DIR/sessions"
[ -f "$TEST_DIR/sessions/2026_02_01_FOO/.state.json" ] && pass "M003-01: Renames .agent.json to .state.json" || fail "M003-01" ".state.json" "missing"
[ ! -f "$TEST_DIR/sessions/2026_02_01_FOO/.agent.json" ] && pass "M003-02: .agent.json removed" || fail "M003-02" "removed" "still exists"
teardown

# Idempotent: .state.json already exists
setup
mkdir -p "$TEST_DIR/sessions/2026_02_01_FOO"
echo '{"pid":456}' > "$TEST_DIR/sessions/2026_02_01_FOO/.state.json"
echo '{"pid":123}' > "$TEST_DIR/sessions/2026_02_01_FOO/.agent.json"
migration_003_state_json_rename "$TEST_DIR/claude" "$TEST_DIR/sessions"
content=$(cat "$TEST_DIR/sessions/2026_02_01_FOO/.state.json")
[[ "$content" == *"456"* ]] && pass "M003-03: Preserves existing .state.json (doesn't overwrite)" || fail "M003-03" "pid:456" "$content"
teardown

# No sessions dir — should be a no-op
setup
migration_003_state_json_rename "$TEST_DIR/claude" ""
rc=$?
[ "$rc" -eq 0 ] && pass "M003-04: No-op when sessions dir empty" || fail "M003-04" "exit 0" "exit $rc"
teardown

# Multiple sessions
setup
mkdir -p "$TEST_DIR/sessions/2026_02_01_A" "$TEST_DIR/sessions/2026_02_02_B"
echo '{}' > "$TEST_DIR/sessions/2026_02_01_A/.agent.json"
echo '{}' > "$TEST_DIR/sessions/2026_02_02_B/.agent.json"
migration_003_state_json_rename "$TEST_DIR/claude" "$TEST_DIR/sessions"
[ -f "$TEST_DIR/sessions/2026_02_01_A/.state.json" ] && [ -f "$TEST_DIR/sessions/2026_02_02_B/.state.json" ] \
  && pass "M003-05: Renames across multiple sessions" || fail "M003-05" "both renamed" "not"
teardown

# ============================================================================
# Migration 004: remove_stale_skill_symlinks
# ============================================================================
echo ""
echo "=== Migration 004: remove_stale_skill_symlinks ==="

# Fresh: remove symlink pointing to empty dir (no SKILL.md)
setup
mkdir -p "$TEST_DIR/claude/skills"
mkdir -p "$TEST_DIR/engine/skills/critique"
# critique has no SKILL.md — it's deprecated
ln -s "$TEST_DIR/engine/skills/critique" "$TEST_DIR/claude/skills/critique"
# brainstorm has a SKILL.md — it's valid
mkdir -p "$TEST_DIR/engine/skills/brainstorm"
echo "---" > "$TEST_DIR/engine/skills/brainstorm/SKILL.md"
ln -s "$TEST_DIR/engine/skills/brainstorm" "$TEST_DIR/claude/skills/brainstorm"
migration_004_remove_stale_skill_symlinks "$TEST_DIR/claude"
[ ! -L "$TEST_DIR/claude/skills/critique" ] && pass "M004-01: Removes symlink to dir with no SKILL.md" || fail "M004-01" "removed" "still exists"
[ -L "$TEST_DIR/claude/skills/brainstorm" ] && pass "M004-02: Preserves symlink to dir WITH SKILL.md" || fail "M004-02" "symlink" "missing"
teardown

# Idempotent: already cleaned
setup
mkdir -p "$TEST_DIR/claude/skills"
mkdir -p "$TEST_DIR/engine/skills/brainstorm"
echo "---" > "$TEST_DIR/engine/skills/brainstorm/SKILL.md"
ln -s "$TEST_DIR/engine/skills/brainstorm" "$TEST_DIR/claude/skills/brainstorm"
migration_004_remove_stale_skill_symlinks "$TEST_DIR/claude"
rc=$?
[ "$rc" -eq 0 ] && pass "M004-03: Idempotent — no-op when all symlinks valid" || fail "M004-03" "exit 0" "exit $rc"
[ -L "$TEST_DIR/claude/skills/brainstorm" ] && pass "M004-04: Valid symlinks preserved" || fail "M004-04" "symlink" "missing"
teardown

# Real directory (local override) not touched
setup
mkdir -p "$TEST_DIR/claude/skills/custom-skill"
# custom-skill is a real dir (local override), no SKILL.md — should NOT be removed
migration_004_remove_stale_skill_symlinks "$TEST_DIR/claude"
[ -d "$TEST_DIR/claude/skills/custom-skill" ] && pass "M004-05: Real directories not removed (local overrides)" || fail "M004-05" "exists" "removed"
teardown

# No skills dir — no-op
setup
migration_004_remove_stale_skill_symlinks "$TEST_DIR/claude"
rc=$?
[ "$rc" -eq 0 ] && pass "M004-06: No-op when skills dir missing" || fail "M004-06" "exit 0" "exit $rc"
teardown

# ============================================================================
# Migration 005: add_hooks_to_settings
# ============================================================================
echo ""
echo "=== Migration 005: add_hooks_to_settings ==="

# Fresh: adds hooks to settings with existing PreToolUse
setup
cat > "$TEST_DIR/claude/settings.json" << 'SETTINGS'
{
  "permissions": {"allow": []},
  "hooks": {
    "PreToolUse": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "~/.claude/hooks/pre-tool-use-overflow.sh"}]}
    ]
  }
}
SETTINGS
migration_005_add_hooks_to_settings "$TEST_DIR/claude"
# Check new hooks were added
heartbeat=$(jq '[.hooks.PreToolUse[] | select(.hooks[0].command == "~/.claude/hooks/pre-tool-use-heartbeat.sh")] | length' "$TEST_DIR/claude/settings.json")
session_gate=$(jq '[.hooks.PreToolUse[] | select(.hooks[0].command == "~/.claude/hooks/pre-tool-use-session-gate.sh")] | length' "$TEST_DIR/claude/settings.json")
submit_gate=$(jq '[.hooks.UserPromptSubmit[] | select(.hooks[0].command == "~/.claude/hooks/user-prompt-submit-session-gate.sh")] | length' "$TEST_DIR/claude/settings.json")
[ "$heartbeat" = "1" ] && pass "M005-01: Adds heartbeat hook" || fail "M005-01" "1" "$heartbeat"
[ "$session_gate" = "1" ] && pass "M005-02: Adds session-gate hook" || fail "M005-02" "1" "$session_gate"
# M005-03 (discovery hook) removed — discovery moved to PreToolUse
[ "$submit_gate" = "1" ] && pass "M005-04: Adds user-prompt-submit session-gate" || fail "M005-04" "1" "$submit_gate"
# Check existing overflow hook preserved
overflow=$(jq '[.hooks.PreToolUse[] | select(.hooks[0].command == "~/.claude/hooks/pre-tool-use-overflow.sh")] | length' "$TEST_DIR/claude/settings.json")
[ "$overflow" = "1" ] && pass "M005-05: Preserves existing overflow hook" || fail "M005-05" "1" "$overflow"
teardown

# Idempotent: run twice — no duplicates
setup
cat > "$TEST_DIR/claude/settings.json" << 'SETTINGS'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "~/.claude/hooks/pre-tool-use-overflow.sh"}]}
    ]
  }
}
SETTINGS
migration_005_add_hooks_to_settings "$TEST_DIR/claude"
migration_005_add_hooks_to_settings "$TEST_DIR/claude"
heartbeat_count=$(jq '[.hooks.PreToolUse[] | select(.hooks[0].command == "~/.claude/hooks/pre-tool-use-heartbeat.sh")] | length' "$TEST_DIR/claude/settings.json")
[ "$heartbeat_count" = "1" ] && pass "M005-06: Idempotent — no duplicates after second run" || fail "M005-06" "1" "$heartbeat_count"
teardown

# No settings.json — no-op
setup
migration_005_add_hooks_to_settings "$TEST_DIR/claude"
rc=$?
[ "$rc" -eq 0 ] && pass "M005-07: No-op when no settings.json" || fail "M005-07" "exit 0" "exit $rc"
teardown

# ============================================================================
# Migration 006: hooks_to_project_local
# ============================================================================
echo ""
echo "=== Migration 006: hooks_to_project_local ==="

# Fresh: strips hooks, statusLine, and engine permissions from global settings
setup
cat > "$TEST_DIR/claude/settings.json" << 'SETTINGS'
{
  "permissions": {
    "allow": [
      "Bash(engine *)",
      "Bash(~/.claude/scripts/*)",
      "Glob(~/.claude/**)",
      "Read(~/.claude/skills/**)",
      "Read(sessions/**)",
      "Bash(custom-user-thing)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "~/.claude/hooks/pre-tool-use-heartbeat.sh"}]}
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "~/.claude/tools/statusline.sh"
  }
}
SETTINGS
migration_006_hooks_to_project_local "$TEST_DIR/claude"
has_hooks=$(jq 'has("hooks")' "$TEST_DIR/claude/settings.json")
has_sl=$(jq 'has("statusLine")' "$TEST_DIR/claude/settings.json")
[ "$has_hooks" = "false" ] && pass "M006-01: Strips hooks section" || fail "M006-01" "false" "$has_hooks"
[ "$has_sl" = "false" ] && pass "M006-02: Strips statusLine section" || fail "M006-02" "false" "$has_sl"
# Engine permissions removed but user custom permission preserved
engine_perm=$(jq '[.permissions.allow[] | select(. == "Bash(engine *)")] | length' "$TEST_DIR/claude/settings.json")
user_perm=$(jq '[.permissions.allow[] | select(. == "Bash(custom-user-thing)")] | length' "$TEST_DIR/claude/settings.json")
[ "$engine_perm" = "0" ] && pass "M006-03: Removes engine permissions" || fail "M006-03" "0" "$engine_perm"
[ "$user_perm" = "1" ] && pass "M006-04: Preserves user-custom permissions" || fail "M006-04" "1" "$user_perm"
teardown

# Idempotent: already clean — no hooks, no statusLine
setup
cat > "$TEST_DIR/claude/settings.json" << 'SETTINGS'
{
  "permissions": {"allow": ["Bash(custom-user-thing)"]}
}
SETTINGS
migration_006_hooks_to_project_local "$TEST_DIR/claude"
rc=$?
user_perm=$(jq '[.permissions.allow[] | select(. == "Bash(custom-user-thing)")] | length' "$TEST_DIR/claude/settings.json")
[ "$rc" -eq 0 ] && pass "M006-05: Idempotent — no-op when already clean" || fail "M006-05" "exit 0" "exit $rc"
[ "$user_perm" = "1" ] && pass "M006-06: Preserves user permissions on idempotent run" || fail "M006-06" "1" "$user_perm"
teardown

# No settings.json — no-op
setup
migration_006_hooks_to_project_local "$TEST_DIR/claude"
rc=$?
[ "$rc" -eq 0 ] && pass "M006-07: No-op when no settings.json" || fail "M006-07" "exit 0" "exit $rc"
teardown

# All engine perms removed — permissions section cleaned up
setup
cat > "$TEST_DIR/claude/settings.json" << 'SETTINGS'
{
  "permissions": {
    "allow": [
      "Bash(engine *)",
      "Bash(~/.claude/scripts/*)",
      "Glob(~/.claude/**)"
    ]
  },
  "hooks": {}
}
SETTINGS
migration_006_hooks_to_project_local "$TEST_DIR/claude"
has_perms=$(jq 'has("permissions")' "$TEST_DIR/claude/settings.json")
[ "$has_perms" = "false" ] && pass "M006-08: Removes empty permissions section" || fail "M006-08" "false" "$has_perms"
teardown

# ============================================================================
# Migration runner tests
# ============================================================================
echo ""
echo "=== run_migrations ==="

# Runs all pending
setup
# Create state that migration 001 can act on
mkdir -p "$TEST_DIR/engine/scripts"
echo '#!/bin/bash' > "$TEST_DIR/engine/scripts/test.sh"
chmod +x "$TEST_DIR/engine/scripts/test.sh"
ln -s "$TEST_DIR/engine/scripts" "$TEST_DIR/claude/scripts"
mkdir -p "$TEST_DIR/engine/skills/foo"
ln -s "$TEST_DIR/engine/skills" "$TEST_DIR/claude/skills"
cat > "$TEST_DIR/claude/settings.json" << 'JSON'
{"hooks":{}}
JSON
output=$(run_migrations "$TEST_DIR/claude" "$TEST_DIR/sessions" "$TEST_DIR/engine" 2>&1)
[ -f "$SETUP_MIGRATION_STATE" ] && pass "RUNNER-01: Creates state file" || fail "RUNNER-01" "state file" "missing"
count=$(wc -l < "$SETUP_MIGRATION_STATE" | tr -d ' ')
[ "$count" = "6" ] && pass "RUNNER-02: All 6 migrations recorded" || fail "RUNNER-02" "6" "$count"
[[ "$output" == *"Applied 6"* ]] && pass "RUNNER-03: Reports 6 applied" || fail "RUNNER-03" "Applied 6" "$output"
teardown

# Skips already-applied
setup
echo "001:perfile_scripts_hooks:1707000000" > "$SETUP_MIGRATION_STATE"
echo "002:perfile_skills:1707000001" >> "$SETUP_MIGRATION_STATE"
echo "003:state_json_rename:1707000002" >> "$SETUP_MIGRATION_STATE"
echo "004:remove_stale_skill_symlinks:1707000003" >> "$SETUP_MIGRATION_STATE"
echo "005:add_hooks_to_settings:1707000004" >> "$SETUP_MIGRATION_STATE"
echo "006:hooks_to_project_local:1707000005" >> "$SETUP_MIGRATION_STATE"
output=$(run_migrations "$TEST_DIR/claude" "$TEST_DIR/sessions" "$TEST_DIR/engine" 2>&1)
[[ "$output" == *"up to date"* ]] && pass "RUNNER-04: Skips all when up to date" || fail "RUNNER-04" "up to date" "$output"
teardown

# Runs only pending
setup
echo "001:perfile_scripts_hooks:1707000000" > "$SETUP_MIGRATION_STATE"
echo "002:perfile_skills:1707000001" >> "$SETUP_MIGRATION_STATE"
echo "003:state_json_rename:1707000002" >> "$SETUP_MIGRATION_STATE"
echo "004:remove_stale_skill_symlinks:1707000003" >> "$SETUP_MIGRATION_STATE"
cat > "$TEST_DIR/claude/settings.json" << 'JSON'
{"hooks":{}}
JSON
output=$(run_migrations "$TEST_DIR/claude" "$TEST_DIR/sessions" "$TEST_DIR/engine" 2>&1)
count=$(wc -l < "$SETUP_MIGRATION_STATE" | tr -d ' ')
[ "$count" = "6" ] && pass "RUNNER-05: Runs only pending (2 new + 4 existing)" || fail "RUNNER-05" "6" "$count"
[[ "$output" == *"Applied 2"* ]] && pass "RUNNER-06: Reports correct pending count" || fail "RUNNER-06" "Applied 2" "$output"
teardown

# ============================================================================
# pending_migrations tests
# ============================================================================
echo ""
echo "=== pending_migrations ==="

setup
result=$(pending_migrations "$TEST_DIR/nonexistent-state")
[ "$result" = "6" ] && pass "PENDING-01: All pending when no state file" || fail "PENDING-01" "6" "$result"
teardown

setup
echo "001:perfile_scripts_hooks:1707000000" > "$SETUP_MIGRATION_STATE"
result=$(pending_migrations "$SETUP_MIGRATION_STATE")
[ "$result" = "5" ] && pass "PENDING-02: Correct count with 1 applied" || fail "PENDING-02" "5" "$result"
teardown

setup
echo "001:perfile_scripts_hooks:1707000000" > "$SETUP_MIGRATION_STATE"
echo "002:perfile_skills:1707000001" >> "$SETUP_MIGRATION_STATE"
echo "003:state_json_rename:1707000002" >> "$SETUP_MIGRATION_STATE"
echo "004:remove_stale_skill_symlinks:1707000003" >> "$SETUP_MIGRATION_STATE"
echo "005:add_hooks_to_settings:1707000004" >> "$SETUP_MIGRATION_STATE"
echo "006:hooks_to_project_local:1707000005" >> "$SETUP_MIGRATION_STATE"
result=$(pending_migrations "$SETUP_MIGRATION_STATE")
[ "$result" = "0" ] && pass "PENDING-03: Zero pending when all applied" || fail "PENDING-03" "0" "$result"
teardown

# ============================================================================
# Results
# ============================================================================

exit_with_results
