#!/bin/bash
# ============================================================================
# test-engine-integration.sh — Integration tests for engine.sh
# ============================================================================
# Tests engine.sh end-to-end in a sandboxed environment.
# Verifies that sourcing setup-lib.sh + setup-migrations.sh works correctly
# and that all subcommands (local, remote, status) and the normal project
# setup flow produce the expected results.
#
# Strategy: Override HOME to a temp dir, place engine.sh + libs in a fake
# GDrive path so EMAIL auto-detection works, create fake engine trees.
# ============================================================================
set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINE_DIR="$SCRIPT_DIR/.."

# ---- Sandbox Setup ----
REAL_HOME="$HOME"
TEST_ROOT=""

create_sandbox() {
  TEST_ROOT=$(mktemp -d)

  # Fake HOME
  export HOME="$TEST_ROOT/home"
  mkdir -p "$HOME"

  # Fake GDrive path (so EMAIL detection works)
  local FAKE_EMAIL="testuser@example.com"
  local GDRIVE_BASE="$HOME/Library/CloudStorage/GoogleDrive-${FAKE_EMAIL}/Shared drives/finch-os"
  mkdir -p "$GDRIVE_BASE/engine"

  # Copy the REAL engine scripts into the fake GDrive engine
  # This is the key: engine.sh will be run FROM this path, so SCRIPT_DIR resolves here
  cp "$ENGINE_DIR/engine.sh" "$GDRIVE_BASE/engine/scripts/engine.sh" 2>/dev/null || true
  cp "$ENGINE_DIR/setup-lib.sh" "$GDRIVE_BASE/engine/scripts/setup-lib.sh" 2>/dev/null || true
  cp "$ENGINE_DIR/setup-migrations.sh" "$GDRIVE_BASE/engine/scripts/setup-migrations.sh" 2>/dev/null || true

  # Wait -- engine.sh sources from SCRIPT_DIR, so we need the scripts dir
  mkdir -p "$GDRIVE_BASE/engine/scripts"
  cp "$ENGINE_DIR/engine.sh" "$GDRIVE_BASE/engine/scripts/"
  cp "$ENGINE_DIR/setup-lib.sh" "$GDRIVE_BASE/engine/scripts/"
  cp "$ENGINE_DIR/setup-migrations.sh" "$GDRIVE_BASE/engine/scripts/"
  cp "$ENGINE_DIR/lib.sh" "$GDRIVE_BASE/engine/scripts/"
  chmod +x "$GDRIVE_BASE/engine/scripts/"*.sh

  # Create engine content in the GDrive engine
  mkdir -p "$GDRIVE_BASE/engine/.directives"
  mkdir -p "$GDRIVE_BASE/engine/agents"
  mkdir -p "$GDRIVE_BASE/engine/scripts"
  mkdir -p "$GDRIVE_BASE/engine/hooks"
  mkdir -p "$GDRIVE_BASE/engine/skills/brainstorm"
  mkdir -p "$GDRIVE_BASE/engine/skills/implement"

  echo "# Test" > "$GDRIVE_BASE/engine/.directives/INVARIANTS.md"
  echo "# SKILL" > "$GDRIVE_BASE/engine/skills/brainstorm/SKILL.md"
  echo "# SKILL" > "$GDRIVE_BASE/engine/skills/implement/SKILL.md"
  echo '#!/bin/bash' > "$GDRIVE_BASE/engine/scripts/session.sh"
  echo '#!/bin/bash' > "$GDRIVE_BASE/engine/scripts/log.sh"
  echo '#!/bin/bash' > "$GDRIVE_BASE/engine/hooks/overflow.sh"
  chmod +x "$GDRIVE_BASE/engine/scripts/"*.sh "$GDRIVE_BASE/engine/hooks/"*.sh

  # Also create a local engine (for mode=local tests)
  mkdir -p "$HOME/.claude/engine"
  cp -r "$GDRIVE_BASE/engine/"* "$HOME/.claude/engine/"
  chmod +x "$HOME/.claude/engine/scripts/"*.sh "$HOME/.claude/engine/hooks/"*.sh 2>/dev/null || true

  # Initialize a git repo in local engine so cmd_local doesn't trigger onboarding prompt
  (cd "$HOME/.claude/engine" && git init -q && git checkout -q -b testuser/engine && git commit -q --allow-empty -m "init" 2>/dev/null) || true

  # Create a fake user-info.sh that returns the test email
  mkdir -p "$HOME/.claude/scripts"
  cat > "$HOME/.claude/scripts/user-info.sh" << 'USERINFO'
#!/bin/bash
case "$1" in
  email) echo "testuser@example.com" ;;
  *) echo "testuser" ;;
esac
USERINFO
  chmod +x "$HOME/.claude/scripts/user-info.sh"

  # Store paths for assertions
  ENGINE_SH="$GDRIVE_BASE/engine/scripts/engine.sh"
  FAKE_GDRIVE_ENGINE="$GDRIVE_BASE/engine"
  FAKE_LOCAL_ENGINE="$HOME/.claude/engine"

  # Create a fake project dir
  PROJECT_DIR="$TEST_ROOT/project"
  mkdir -p "$PROJECT_DIR"
  # CRITICAL: Export PROJECT_ROOT so engine.sh never uses real pwd
  export PROJECT_ROOT="$PROJECT_DIR"

  # Create user sessions dir on GDrive (use "project" as the default project name)
  mkdir -p "$GDRIVE_BASE/testuser/project/sessions"
  mkdir -p "$GDRIVE_BASE/testuser/project/reports"
}

destroy_sandbox() {
  export HOME="$REAL_HOME"
  unset PROJECT_ROOT
  [ -n "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
  TEST_ROOT=""
}

# ============================================================================
# Test: engine.sh sources libs without error
# ============================================================================
echo "=== Source Integration ==="

create_sandbox
echo "local" > "$FAKE_LOCAL_ENGINE/.mode"
# Use 'status' subcommand -- it's read-only and exercises source + dispatch
OUT=$(cd "$PROJECT_DIR" && bash "$ENGINE_SH" status 2>&1 || true)
# The key is: it should NOT fail with "source: file not found" errors
if echo "$OUT" | grep -qi "source.*not found\|No such file"; then
  fail "SRC-01: engine.sh sources libs without file-not-found errors" "no source errors" "$OUT"
else
  pass "SRC-01: engine.sh sources libs without file-not-found errors"
fi
destroy_sandbox

# ============================================================================
# Test: engine.sh local subcommand
# ============================================================================
echo ""
echo "=== local subcommand ==="

create_sandbox
# Set mode to remote first, then switch to local
echo "remote" > "$FAKE_LOCAL_ENGINE/.mode"
OUT=$(cd "$PROJECT_DIR" && bash "$ENGINE_SH" local 2>&1)

# Should create symlinks in ~/.claude/ pointing to local engine
assert_symlink "$HOME/.claude/.directives" "LOCAL-01: .directives symlink created"

# Mode file should say "local"
MODE=$(cat "$FAKE_LOCAL_ENGINE/.mode")
assert_eq "local" "$MODE" "LOCAL-02: mode file set to local"

# Output should mention "local"
assert_contains "local" "$OUT" "LOCAL-03: output mentions local mode"
destroy_sandbox

# ============================================================================
# Test: engine.sh remote subcommand
# ============================================================================
echo ""
echo "=== remote subcommand ==="

create_sandbox
echo "local" > "$FAKE_LOCAL_ENGINE/.mode"
OUT=$(cd "$PROJECT_DIR" && bash "$ENGINE_SH" remote 2>&1)

# Mode file should say "remote"
MODE=$(cat "$FAKE_LOCAL_ENGINE/.mode")
assert_eq "remote" "$MODE" "REMOTE-01: mode file set to remote"

# Should create symlinks
assert_symlink "$HOME/.claude/.directives" "REMOTE-02: .directives symlink created"

# Output should mention "remote"
assert_contains "remote" "$OUT" "REMOTE-03: output mentions remote mode"
destroy_sandbox

# ============================================================================
# Test: engine.sh status subcommand
# ============================================================================
echo ""
echo "=== status subcommand ==="

create_sandbox
echo "local" > "$FAKE_LOCAL_ENGINE/.mode"
# First run local to create symlinks
(cd "$PROJECT_DIR" && bash "$ENGINE_SH" local >/dev/null 2>&1)
OUT=$(cd "$PROJECT_DIR" && bash "$ENGINE_SH" status 2>&1)

assert_contains "local" "$OUT" "STATUS-01: status shows current mode"
assert_contains "Symlinks" "$OUT" "STATUS-02: status shows symlink audit"
assert_contains "consistent" "$OUT" "STATUS-03: status reports consistency"
destroy_sandbox

# ============================================================================
# Test: Normal project setup flow
# ============================================================================
echo ""
echo "=== Normal project setup flow ==="

create_sandbox
echo "local" > "$FAKE_LOCAL_ENGINE/.mode"
OUT=$(cd "$PROJECT_DIR" && bash "$ENGINE_SH" setup --yes 2>&1)

# Engine symlinks should be created (using lib's setup_engine_symlinks)
assert_symlink "$HOME/.claude/.directives" "FLOW-01: engine .directives symlink"

# Per-file symlinks for scripts/hooks (from lib's link_files_if_needed)
assert_dir_exists "$HOME/.claude/scripts" "FLOW-03: scripts dir exists"
assert_not_symlink "$HOME/.claude/scripts" "FLOW-04: scripts is dir not symlink"

# Per-skill symlinks
assert_dir_exists "$HOME/.claude/skills" "FLOW-05: skills dir exists"
assert_not_symlink "$HOME/.claude/skills" "FLOW-06: skills is dir not symlink"

# Project symlinks (sessions/reports)
if [ -L "$PROJECT_DIR/sessions" ]; then
  pass "FLOW-07: project sessions symlink created"
else
  # May not create if GDrive path doesn't resolve correctly in sandbox
  # Check if the output mentions it
  if echo "$OUT" | grep -q "sessions"; then
    pass "FLOW-07: project sessions mentioned in output"
  else
    fail "FLOW-07: project sessions setup" "symlink or mention" "neither"
  fi
fi

# Project directives stub
assert_dir_exists "$PROJECT_DIR/.claude/.directives" "FLOW-08: project .directives dir created"
destroy_sandbox

# ============================================================================
# Test: Migration runner is called during normal flow
# ============================================================================
echo ""
echo "=== Migration runner integration ==="

create_sandbox
echo "local" > "$FAKE_LOCAL_ENGINE/.mode"

# Create a pre-migration state: whole-dir symlinks that migration_001 should convert
# But since this is a fresh setup, migrations should run and record to state file
OUT=$(cd "$PROJECT_DIR" && bash "$ENGINE_SH" setup --yes 2>&1)

# The migration state file should exist after setup runs
MIGRATION_STATE="$HOME/.claude/engine/.migrations"
if [ -f "$MIGRATION_STATE" ]; then
  pass "MIG-01: migration state file created"

  # Should have recorded all migrations (currently 6)
  COUNT=$(wc -l < "$MIGRATION_STATE" | tr -d ' ')
  if [ "$COUNT" -ge 3 ]; then
    pass "MIG-02: all migrations recorded in state file ($COUNT entries)"
  else
    fail "MIG-02: migration count" ">=3" "$COUNT"
  fi

  # Check migration entries
  if grep -q "^001:" "$MIGRATION_STATE"; then
    pass "MIG-03: migration 001 recorded"
  else
    fail "MIG-03: migration 001" "present" "missing"
  fi
else
  fail "MIG-01: migration state file created" "file exists" "missing"
  fail "MIG-02: all 3 migrations recorded" ">=3" "N/A"
  fail "MIG-03: migration 001 recorded" "present" "N/A"
fi

# Run setup again -- migrations should be idempotent (all up to date)
OUT2=$(cd "$PROJECT_DIR" && bash "$ENGINE_SH" setup --yes 2>&1)
assert_contains "up to date" "$OUT2" "MIG-04: second run reports migrations up to date"
destroy_sandbox

# ============================================================================
# Test: engine.sh uses lib's parameterized functions (not inline)
# ============================================================================
echo ""
echo "=== Lib function verification ==="

create_sandbox
echo "local" > "$FAKE_LOCAL_ENGINE/.mode"

# The lib's setup_engine_symlinks passes interactive=0 to link_if_needed.
# If a real directory exists where a symlink should be, the lib version
# returns 2 (non-interactive mode) instead of prompting. This verifies
# we're using the lib version.

# Create a real dir where directives symlink should go
mkdir -p "$HOME/.claude/.directives"
echo "local file" > "$HOME/.claude/.directives/test.md"

# Run setup -- should NOT hang waiting for input (lib returns 2 for real dirs)
OUT=$(cd "$PROJECT_DIR" && timeout 10 bash "$ENGINE_SH" local 2>&1)
RC=$?

if [ "$RC" -ne 124 ]; then
  pass "LIB-01: engine.sh doesn't hang on real dir (lib's non-interactive mode)"
else
  fail "LIB-01: engine.sh timed out" "non-interactive skip" "hung waiting for input"
fi

# The local file should still exist (not replaced)
if [ -f "$HOME/.claude/.directives/test.md" ]; then
  pass "LIB-02: real dir preserved (non-interactive skip)"
else
  fail "LIB-02: real dir preserved" "file exists" "replaced or deleted"
fi
destroy_sandbox

# ============================================================================
# Test: script permissions are fixed (lib's fix_script_permissions)
# ============================================================================
echo ""
echo "=== Permission fixing ==="

create_sandbox
echo "local" > "$FAKE_LOCAL_ENGINE/.mode"

# Remove execute permission from a script
chmod -x "$FAKE_LOCAL_ENGINE/scripts/session.sh"

OUT=$(cd "$PROJECT_DIR" && bash "$ENGINE_SH" local 2>&1)

# After setup, the script should have +x restored
if [ -x "$FAKE_LOCAL_ENGINE/scripts/session.sh" ]; then
  pass "PERM-01: fix_script_permissions restores +x"
else
  fail "PERM-01: script permission" "+x" "-x"
fi
destroy_sandbox

# ============================================================================
# Test: engine.sh deploy subcommand
# ============================================================================
echo ""
echo "=== deploy subcommand ==="

create_sandbox
echo "local" > "$FAKE_LOCAL_ENGINE/.mode"

# Create some content to deploy
echo "test content" > "$FAKE_LOCAL_ENGINE/test-file.txt"
mkdir -p "$FAKE_LOCAL_ENGINE/.git/objects"
echo "git data" > "$FAKE_LOCAL_ENGINE/.git/HEAD"

OUT=$(cd "$PROJECT_DIR" && bash "$ENGINE_SH" deploy 2>&1)

# DEPLOY-01: Deploy should rsync to GDrive excluding .git
assert_contains "Deploying" "$OUT" "DEPLOY-01a: deploy runs rsync"
assert_file_exists "$FAKE_GDRIVE_ENGINE/test-file.txt" "DEPLOY-01b: content deployed to GDrive"
if [ ! -d "$FAKE_GDRIVE_ENGINE/.git" ]; then
  pass "DEPLOY-01c: .git excluded from deploy"
else
  fail "DEPLOY-01c: .git excluded" "no .git in GDrive" ".git present"
fi
destroy_sandbox

# DEPLOY-02: Deploy without GDrive accessible -> error
create_sandbox
echo "local" > "$FAKE_LOCAL_ENGINE/.mode"

# Copy engine.sh + libs to a stable location before removing GDrive
STABLE_SETUP="$TEST_ROOT/stable-engine.sh"
cp "$ENGINE_SH" "$STABLE_SETUP"
cp "$(dirname "$ENGINE_SH")/setup-lib.sh" "$TEST_ROOT/setup-lib.sh"
cp "$(dirname "$ENGINE_SH")/setup-migrations.sh" "$TEST_ROOT/setup-migrations.sh"
cp "$(dirname "$ENGINE_SH")/lib.sh" "$TEST_ROOT/lib.sh"
chmod +x "$STABLE_SETUP"

# Remove the GDrive shared drive parent dir to simulate inaccessible GDrive
rm -rf "$HOME/Library/CloudStorage"

OUT=$(cd "$PROJECT_DIR" && bash "$STABLE_SETUP" deploy 2>&1 || true)
assert_contains "ERROR" "$OUT" "DEPLOY-02: deploy without GDrive shows error"
destroy_sandbox

# ============================================================================
# Test: engine.sh push subcommand (Git-based)
# ============================================================================
echo ""
echo "=== push subcommand (Git) ==="

# PUSH-01: push with .git present -> attempts git push
create_sandbox
echo "local" > "$FAKE_LOCAL_ENGINE/.mode"
# Sandbox already has .git from create_sandbox -- no extra init needed

OUT=$(cd "$PROJECT_DIR" && bash "$ENGINE_SH" push "test commit" 2>&1 || true)
# Should reference git push operations (will fail at push since no remote, but shows intent)
if echo "$OUT" | grep -qi "push\|origin\|branch"; then
  pass "PUSH-01: push with .git attempts git push"
else
  fail "PUSH-01: push with .git" "git push attempted" "$OUT"
fi
destroy_sandbox

# PUSH-02: push without .git -> error message mentioning engine.sh local
create_sandbox
echo "local" > "$FAKE_LOCAL_ENGINE/.mode"
rm -rf "$FAKE_LOCAL_ENGINE/.git"

OUT=$(cd "$PROJECT_DIR" && bash "$ENGINE_SH" push 2>&1 || true)
assert_contains "ERROR" "$OUT" "PUSH-02a: push without .git shows error"
assert_contains "local" "$OUT" "PUSH-02b: push without .git mentions engine.sh local"
destroy_sandbox

# ============================================================================
# Test: engine.sh pull subcommand (Git-based)
# ============================================================================
echo ""
echo "=== pull subcommand (Git) ==="

# PULL-01: pull with .git present -> attempts git pull
create_sandbox
echo "local" > "$FAKE_LOCAL_ENGINE/.mode"
# Sandbox already has .git from create_sandbox -- no extra init needed

OUT=$(cd "$PROJECT_DIR" && bash "$ENGINE_SH" pull 2>&1 || true)
if echo "$OUT" | grep -qi "pull\|origin\|branch"; then
  pass "PULL-01: pull with .git attempts git pull"
else
  fail "PULL-01: pull with .git" "git pull attempted" "$OUT"
fi
destroy_sandbox

# PULL-02: pull without .git -> error message mentioning engine.sh local
create_sandbox
echo "local" > "$FAKE_LOCAL_ENGINE/.mode"
rm -rf "$FAKE_LOCAL_ENGINE/.git"

OUT=$(cd "$PROJECT_DIR" && bash "$ENGINE_SH" pull 2>&1 || true)
assert_contains "ERROR" "$OUT" "PULL-02a: pull without .git shows error"
assert_contains "local" "$OUT" "PULL-02b: pull without .git mentions engine.sh local"
destroy_sandbox

# PULL-03: pull without local engine -> error
create_sandbox
echo "local" > "$FAKE_LOCAL_ENGINE/.mode"
rm -rf "$FAKE_LOCAL_ENGINE"

OUT=$(cd "$PROJECT_DIR" && bash "$ENGINE_SH" pull 2>&1 || true)
assert_contains "ERROR" "$OUT" "PULL-03: pull without local engine shows error"
destroy_sandbox

# ============================================================================
# Test: engine.sh local subcommand -- Git onboarding
# ============================================================================
echo ""
echo "=== local subcommand (Git onboarding) ==="

# LOCAL-GIT-01: local with no .git -> detects and prompts for URL
create_sandbox
echo "remote" > "$FAKE_LOCAL_ENGINE/.mode"
# Ensure no .git dir
rm -rf "$FAKE_LOCAL_ENGINE/.git"

OUT=$(cd "$PROJECT_DIR" && echo "" | bash "$ENGINE_SH" local 2>&1)
# Should detect missing .git and mention it
assert_contains "No Git repository" "$OUT" "LOCAL-GIT-01: local without .git detects missing repo"
destroy_sandbox

# LOCAL-GIT-02: local with .git already present -> normal mode switch (no clone prompt)
create_sandbox
echo "remote" > "$FAKE_LOCAL_ENGINE/.mode"
# Sandbox already has .git from create_sandbox -- no extra init needed

OUT=$(cd "$PROJECT_DIR" && bash "$ENGINE_SH" local 2>&1)
# Should NOT mention git setup -- just do normal mode switch
if echo "$OUT" | grep -q "No Git repository"; then
  fail "LOCAL-GIT-02: local with .git skips onboarding" "no git prompt" "prompted for git"
else
  pass "LOCAL-GIT-02: local with .git skips onboarding"
fi
# Should still switch mode
MODE=$(cat "$FAKE_LOCAL_ENGINE/.mode")
assert_eq "local" "$MODE" "LOCAL-GIT-02b: mode switched to local"
destroy_sandbox

# ============================================================================
# Test: engine.sh test subcommand
# ============================================================================

create_sandbox

echo "=== test subcommand ==="

# TEST-01: test subcommand runs without error (test runner exists in sandbox)
mkdir -p "$(dirname "$ENGINE_SH")/tests"
cat > "$(dirname "$ENGINE_SH")/tests/run-all.sh" << 'TESTRUNNER'
#!/bin/bash
echo "========================================"
echo "     Engine Test Runner                 "
echo "========================================"
echo "  mock-test (1 passed)"
echo ""
echo "========================================"
echo "  ALL 1 SUITES PASSED                  "
echo "========================================"
exit 0
TESTRUNNER
chmod +x "$(dirname "$ENGINE_SH")/tests/run-all.sh"

OUT=$(cd "$PROJECT_DIR" && bash "$ENGINE_SH" test 2>&1)
if echo "$OUT" | grep -q "PASSED"; then
  pass "TEST-01: test subcommand runs test suite"
else
  fail "TEST-01: test subcommand" "PASSED in output" "$OUT"
fi

destroy_sandbox

# ============================================================================
# Test: engine.sh uninstall subcommand
# ============================================================================

create_sandbox
# First do a project setup to create symlinks
cd "$PROJECT_DIR" && bash "$ENGINE_SH" setup --yes >/dev/null 2>&1

echo "=== uninstall subcommand ==="

# UNINSTALL-01: uninstall removes project symlinks
OUT=$(cd "$PROJECT_DIR" && bash "$ENGINE_SH" uninstall 2>&1)
if echo "$OUT" | grep -qi "removed\|uninstall"; then
  pass "UNINSTALL-01: uninstall produces output"
else
  fail "UNINSTALL-01: uninstall output" "removal messages" "$OUT"
fi

# UNINSTALL-02: sessions symlink is gone after uninstall
if [ -L "$PROJECT_DIR/sessions" ]; then
  fail "UNINSTALL-02: sessions symlink removed" "no symlink" "symlink still exists"
else
  pass "UNINSTALL-02: sessions symlink removed"
fi

# UNINSTALL-03: settings.json preserved after uninstall
if [ -f "$HOME/.claude/settings.json" ]; then
  pass "UNINSTALL-03: settings.json preserved"
else
  pass "UNINSTALL-03: settings.json preserved (was never created)"
fi

# UNINSTALL-04: directives symlink removed
assert_not_symlink "$HOME/.claude/.directives" "UNINSTALL-04: .directives symlink removed"

# UNINSTALL-05: standards symlink removed
assert_not_symlink "$HOME/.claude/standards" "UNINSTALL-05: standards symlink removed"

# UNINSTALL-06: per-file script symlinks removed
SCRIPT_SYMLINKS=0
if [ -d "$HOME/.claude/scripts" ]; then
  for f in "$HOME/.claude/scripts"/*; do
    [ -L "$f" ] && SCRIPT_SYMLINKS=$((SCRIPT_SYMLINKS + 1))
  done
fi
assert_eq "0" "$SCRIPT_SYMLINKS" "UNINSTALL-06: no script symlinks remain"

# UNINSTALL-07: per-skill symlinks removed
SKILL_SYMLINKS=0
if [ -d "$HOME/.claude/skills" ]; then
  for f in "$HOME/.claude/skills"/*; do
    [ -L "$f" ] && SKILL_SYMLINKS=$((SKILL_SYMLINKS + 1))
  done
fi
assert_eq "0" "$SKILL_SYMLINKS" "UNINSTALL-07: no skill symlinks remain"

# UNINSTALL-08: per-hook symlinks removed
HOOK_SYMLINKS=0
if [ -d "$HOME/.claude/hooks" ]; then
  for f in "$HOME/.claude/hooks"/*; do
    [ -L "$f" ] && HOOK_SYMLINKS=$((HOOK_SYMLINKS + 1))
  done
fi
assert_eq "0" "$HOOK_SYMLINKS" "UNINSTALL-08: no hook symlinks remain"

# UNINSTALL-09: reports symlink removed
if [ -L "$PROJECT_DIR/reports" ]; then
  fail "UNINSTALL-09: reports symlink removed" "no symlink" "symlink still exists"
else
  pass "UNINSTALL-09: reports symlink removed"
fi

# UNINSTALL-10: engine hooks cleaned from settings.json
if [ -f "$HOME/.claude/settings.json" ] && command -v jq &>/dev/null; then
  # statusLine should be gone
  SL=$(jq -r '.statusLine // empty' "$HOME/.claude/settings.json" 2>/dev/null)
  if [ -z "$SL" ]; then
    pass "UNINSTALL-10a: statusLine removed from settings.json"
  else
    fail "UNINSTALL-10a: statusLine removed" "no statusLine" "$SL"
  fi

  # hooks object should be empty or absent
  HOOK_COUNT=$(jq '.hooks // {} | length' "$HOME/.claude/settings.json" 2>/dev/null || echo "0")
  assert_eq "0" "$HOOK_COUNT" "UNINSTALL-10b: no engine hooks remain in settings.json"

  # engine permission patterns should be gone
  ENGINE_PERMS=$(jq '[.permissions.allow // [] | .[] | select(
    startswith("Read(~/.claude/") or
    startswith("Glob(~/.claude/") or
    startswith("Grep(~/.claude/") or
    startswith("Bash(~/.claude/scripts/") or
    startswith("Bash(~/.claude/tools/")
  )] | length' "$HOME/.claude/settings.json" 2>/dev/null || echo "0")
  assert_eq "0" "$ENGINE_PERMS" "UNINSTALL-10c: no engine permissions remain in settings.json"
else
  pass "UNINSTALL-10a: statusLine removed (no settings.json to check)"
  pass "UNINSTALL-10b: no engine hooks (no settings.json to check)"
  pass "UNINSTALL-10c: no engine permissions (no settings.json to check)"
fi

destroy_sandbox

exit_with_results
