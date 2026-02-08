#!/bin/bash
# ============================================================================
# test-setup-migrations.sh — Tests for setup-migrations.sh
# ============================================================================
# Tests each migration (fresh, idempotent, partial) and the runner.
# Pattern: temp dirs, no network, no GDrive.
# ============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MIGRATIONS_SH="$SCRIPT_DIR/../setup-migrations.sh"

# ---- Framework ----
PASS=0
FAIL=0

pass() { echo -e "\033[32mPASS\033[0m: $1"; PASS=$((PASS + 1)); }
fail() { echo -e "\033[31mFAIL\033[0m: $1 (expected: $2, got: $3)"; FAIL=$((FAIL + 1)); }

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
output=$(run_migrations "$TEST_DIR/claude" "$TEST_DIR/sessions" "$TEST_DIR/engine" 2>&1)
[ -f "$SETUP_MIGRATION_STATE" ] && pass "RUNNER-01: Creates state file" || fail "RUNNER-01" "state file" "missing"
count=$(wc -l < "$SETUP_MIGRATION_STATE" | tr -d ' ')
[ "$count" = "3" ] && pass "RUNNER-02: All 3 migrations recorded" || fail "RUNNER-02" "3" "$count"
[[ "$output" == *"Applied 3"* ]] && pass "RUNNER-03: Reports 3 applied" || fail "RUNNER-03" "Applied 3" "$output"
teardown

# Skips already-applied
setup
echo "001:perfile_scripts_hooks:1707000000" > "$SETUP_MIGRATION_STATE"
echo "002:perfile_skills:1707000001" >> "$SETUP_MIGRATION_STATE"
echo "003:state_json_rename:1707000002" >> "$SETUP_MIGRATION_STATE"
output=$(run_migrations "$TEST_DIR/claude" "$TEST_DIR/sessions" "$TEST_DIR/engine" 2>&1)
[[ "$output" == *"up to date"* ]] && pass "RUNNER-04: Skips all when up to date" || fail "RUNNER-04" "up to date" "$output"
teardown

# Runs only pending
setup
echo "001:perfile_scripts_hooks:1707000000" > "$SETUP_MIGRATION_STATE"
output=$(run_migrations "$TEST_DIR/claude" "$TEST_DIR/sessions" "$TEST_DIR/engine" 2>&1)
count=$(wc -l < "$SETUP_MIGRATION_STATE" | tr -d ' ')
[ "$count" = "3" ] && pass "RUNNER-05: Runs only pending (2 new + 1 existing)" || fail "RUNNER-05" "3" "$count"
[[ "$output" == *"Applied 2"* ]] && pass "RUNNER-06: Reports correct pending count" || fail "RUNNER-06" "Applied 2" "$output"
teardown

# ============================================================================
# pending_migrations tests
# ============================================================================
echo ""
echo "=== pending_migrations ==="

setup
result=$(pending_migrations "$TEST_DIR/nonexistent-state")
[ "$result" = "3" ] && pass "PENDING-01: All pending when no state file" || fail "PENDING-01" "3" "$result"
teardown

setup
echo "001:perfile_scripts_hooks:1707000000" > "$SETUP_MIGRATION_STATE"
result=$(pending_migrations "$SETUP_MIGRATION_STATE")
[ "$result" = "2" ] && pass "PENDING-02: Correct count with 1 applied" || fail "PENDING-02" "2" "$result"
teardown

setup
echo "001:perfile_scripts_hooks:1707000000" > "$SETUP_MIGRATION_STATE"
echo "002:perfile_skills:1707000001" >> "$SETUP_MIGRATION_STATE"
echo "003:state_json_rename:1707000002" >> "$SETUP_MIGRATION_STATE"
result=$(pending_migrations "$SETUP_MIGRATION_STATE")
[ "$result" = "0" ] && pass "PENDING-03: Zero pending when all applied" || fail "PENDING-03" "0" "$result"
teardown

# ============================================================================
# Results
# ============================================================================
echo ""
echo "======================================"
echo -e "Results: \033[32m${PASS} passed\033[0m, \033[31m${FAIL} failed\033[0m ($(( PASS + FAIL )) total)"
echo "======================================"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
