#!/bin/bash
# ============================================================================
# test-setup-lib.sh — Tests for setup-lib.sh pure functions
# ============================================================================
# Tests the extracted library functions with full filesystem isolation.
# Pattern: SETUP_* env vars + temp dirs, zero network/GDrive dependency.
# ============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../setup-lib.sh"

# ---- Framework ----
PASS=0
FAIL=0

pass() { echo -e "\033[32mPASS\033[0m: $1"; PASS=$((PASS + 1)); }
fail() { echo -e "\033[31mFAIL\033[0m: $1 (expected: $2, got: $3)"; FAIL=$((FAIL + 1)); }

# ---- Setup / Teardown ----
TEST_DIR=""

setup() {
  TEST_DIR=$(mktemp -d)
  export VERBOSE=false

  # Reset ACTIONS array (setup-lib.sh appends to it)
  ACTIONS=()

  # Create fake engine tree
  mkdir -p "$TEST_DIR/engine/scripts"
  mkdir -p "$TEST_DIR/engine/hooks"
  mkdir -p "$TEST_DIR/engine/skills/brainstorm"
  mkdir -p "$TEST_DIR/engine/skills/implement"
  mkdir -p "$TEST_DIR/engine/skills/test"
  mkdir -p "$TEST_DIR/engine/commands"
  mkdir -p "$TEST_DIR/engine/standards"
  mkdir -p "$TEST_DIR/engine/agents"

  # Create some fake scripts/hooks
  echo '#!/bin/bash' > "$TEST_DIR/engine/scripts/session.sh"
  echo '#!/bin/bash' > "$TEST_DIR/engine/scripts/log.sh"
  echo '#!/bin/bash' > "$TEST_DIR/engine/scripts/tag.sh"
  echo '#!/bin/bash' > "$TEST_DIR/engine/hooks/pre-tool-use-overflow.sh"
  echo '#!/bin/bash' > "$TEST_DIR/engine/hooks/heartbeat.sh"
  chmod +x "$TEST_DIR/engine/scripts/"*.sh "$TEST_DIR/engine/hooks/"*.sh

  # Create fake skill content
  echo "# SKILL.md" > "$TEST_DIR/engine/skills/brainstorm/SKILL.md"
  echo "# SKILL.md" > "$TEST_DIR/engine/skills/implement/SKILL.md"
  echo "# SKILL.md" > "$TEST_DIR/engine/skills/test/SKILL.md"

  # Create claude dir
  mkdir -p "$TEST_DIR/claude"

  # Create project dir
  mkdir -p "$TEST_DIR/project"
}

teardown() {
  [ -n "$TEST_DIR" ] && rm -rf "$TEST_DIR"
}

# Source the library
source "$LIB"

# ============================================================================
# current_mode tests
# ============================================================================
echo "=== current_mode ==="

setup
echo "local" > "$TEST_DIR/engine/.mode"
result=$(current_mode "$TEST_DIR/engine/.mode")
[ "$result" = "local" ] && pass "MODE-01: Returns 'local' when mode file says local" || fail "MODE-01" "local" "$result"
teardown

setup
echo "remote" > "$TEST_DIR/engine/.mode"
result=$(current_mode "$TEST_DIR/engine/.mode")
[ "$result" = "remote" ] && pass "MODE-02: Returns 'remote' when mode file says remote" || fail "MODE-02" "remote" "$result"
teardown

setup
result=$(current_mode "$TEST_DIR/nonexistent/.mode")
[ "$result" = "remote" ] && pass "MODE-03: Returns 'remote' when mode file missing (default)" || fail "MODE-03" "remote" "$result"
teardown

setup
echo "" > "$TEST_DIR/engine/.mode"
result=$(current_mode "$TEST_DIR/engine/.mode")
[ "$result" = "remote" ] && pass "MODE-04: Returns 'remote' when mode file empty" || fail "MODE-04" "remote" "$result"
teardown

# ============================================================================
# resolve_engine_dir tests
# ============================================================================
echo ""
echo "=== resolve_engine_dir ==="

setup
result=$(resolve_engine_dir "local" "$TEST_DIR/engine" "$TEST_DIR/gdrive" "$TEST_DIR/scripts")
[ "$result" = "$TEST_DIR/engine" ] && pass "RESOLVE-01: Local mode returns local engine" || fail "RESOLVE-01" "$TEST_DIR/engine" "$result"
teardown

setup
# Create fake GDrive engine with required dirs
mkdir -p "$TEST_DIR/gdrive/commands" "$TEST_DIR/gdrive/skills"
result=$(resolve_engine_dir "remote" "$TEST_DIR/engine" "$TEST_DIR/gdrive" "$TEST_DIR/scripts")
[ "$result" = "$TEST_DIR/gdrive" ] && pass "RESOLVE-02: Remote mode returns GDrive engine when dirs exist" || fail "RESOLVE-02" "$TEST_DIR/gdrive" "$result"
teardown

setup
# No GDrive, no script_dir parent — should return empty
result=$(resolve_engine_dir "remote" "$TEST_DIR/engine" "$TEST_DIR/nonexistent" "$TEST_DIR/empty")
[ -z "$result" ] && pass "RESOLVE-03: Returns empty when no engine found" || fail "RESOLVE-03" "" "$result"
teardown

setup
# Fallback: script_dir/../ has commands/ and skills/
mkdir -p "$TEST_DIR/parent/commands" "$TEST_DIR/parent/skills" "$TEST_DIR/parent/scripts"
result=$(resolve_engine_dir "remote" "$TEST_DIR/engine" "$TEST_DIR/nonexistent" "$TEST_DIR/parent/scripts")
expected=$(cd "$TEST_DIR/parent" && pwd)
[ "$result" = "$expected" ] && pass "RESOLVE-04: Fallback to script_dir parent when GDrive missing" || fail "RESOLVE-04" "$expected" "$result"
teardown

# ============================================================================
# link_if_needed tests
# ============================================================================
echo ""
echo "=== link_if_needed ==="

setup
link_if_needed "$TEST_DIR/engine/scripts" "$TEST_DIR/claude/scripts-link" "test-link" "0"
[ -L "$TEST_DIR/claude/scripts-link" ] && pass "LINK-01: Creates new symlink" || fail "LINK-01" "symlink" "not a symlink"
teardown

setup
ln -s "$TEST_DIR/engine/scripts" "$TEST_DIR/claude/scripts-link"
link_if_needed "$TEST_DIR/engine/scripts" "$TEST_DIR/claude/scripts-link" "test-link" "0"
actual=$(readlink "$TEST_DIR/claude/scripts-link")
[ "$actual" = "$TEST_DIR/engine/scripts" ] && pass "LINK-02: Idempotent — no change when already correct" || fail "LINK-02" "$TEST_DIR/engine/scripts" "$actual"
[ ${#ACTIONS[@]} -eq 0 ] && pass "LINK-03: No ACTIONS logged for idempotent" || fail "LINK-03" "0 actions" "${#ACTIONS[@]} actions"
teardown

setup
ln -s "$TEST_DIR/old-target" "$TEST_DIR/claude/scripts-link"
link_if_needed "$TEST_DIR/engine/scripts" "$TEST_DIR/claude/scripts-link" "test-link" "0"
actual=$(readlink "$TEST_DIR/claude/scripts-link")
[ "$actual" = "$TEST_DIR/engine/scripts" ] && pass "LINK-04: Updates symlink when target differs" || fail "LINK-04" "$TEST_DIR/engine/scripts" "$actual"
[[ "${ACTIONS[0]}" == *"Updated"* ]] && pass "LINK-05: ACTIONS logs update" || fail "LINK-05" "Updated..." "${ACTIONS[0]:-empty}"
teardown

setup
mkdir -p "$TEST_DIR/claude/real-dir"
link_if_needed "$TEST_DIR/engine/scripts" "$TEST_DIR/claude/real-dir" "test-link" "0"
rc=$?
[ "$rc" -eq 2 ] && pass "LINK-06: Returns 2 for real dir in non-interactive mode" || fail "LINK-06" "exit 2" "exit $rc"
[ -d "$TEST_DIR/claude/real-dir" ] && pass "LINK-07: Real dir preserved (not deleted)" || fail "LINK-07" "dir exists" "dir gone"
teardown

setup
# Broken symlink (target doesn't exist) — treated as "not a symlink, not a dir" → creates new
ln -s "$TEST_DIR/nonexistent" "$TEST_DIR/claude/broken-link"
# link_if_needed sees -L true, readlink returns old target, but target != new target → updates
link_if_needed "$TEST_DIR/engine/scripts" "$TEST_DIR/claude/broken-link" "test-link" "0"
actual=$(readlink "$TEST_DIR/claude/broken-link")
[ "$actual" = "$TEST_DIR/engine/scripts" ] && pass "LINK-08: Replaces broken symlink with correct one" || fail "LINK-08" "$TEST_DIR/engine/scripts" "$actual"
teardown

# ============================================================================
# link_files_if_needed tests
# ============================================================================
echo ""
echo "=== link_files_if_needed ==="

setup
link_files_if_needed "$TEST_DIR/engine/scripts" "$TEST_DIR/claude/scripts" "scripts"
# Should have created per-file symlinks
[ -L "$TEST_DIR/claude/scripts/session.sh" ] && pass "FILES-01: Creates per-file symlinks" || fail "FILES-01" "symlink" "not symlink"
actual=$(readlink "$TEST_DIR/claude/scripts/session.sh")
[ "$actual" = "$TEST_DIR/engine/scripts/session.sh" ] && pass "FILES-02: Symlink points to correct source" || fail "FILES-02" "$TEST_DIR/engine/scripts/session.sh" "$actual"
count=$(ls -1 "$TEST_DIR/claude/scripts/" | wc -l | tr -d ' ')
[ "$count" = "3" ] && pass "FILES-03: All 3 scripts linked" || fail "FILES-03" "3" "$count"
teardown

setup
# Create whole-dir symlink first, then migrate
ln -s "$TEST_DIR/engine/scripts" "$TEST_DIR/claude/scripts"
link_files_if_needed "$TEST_DIR/engine/scripts" "$TEST_DIR/claude/scripts" "scripts"
[ -d "$TEST_DIR/claude/scripts" ] && [ ! -L "$TEST_DIR/claude/scripts" ] && pass "FILES-04: Migrates whole-dir symlink to real dir" || fail "FILES-04" "real dir" "symlink"
[ -L "$TEST_DIR/claude/scripts/session.sh" ] && pass "FILES-05: Per-file symlinks created after migration" || fail "FILES-05" "symlink" "not symlink"
teardown

setup
# Local override: real file in dest should NOT be replaced
link_files_if_needed "$TEST_DIR/engine/scripts" "$TEST_DIR/claude/scripts" "scripts"
# Now create a local override
echo "# local version" > "$TEST_DIR/claude/scripts/session.sh"
rm -f "$TEST_DIR/claude/scripts/session.sh"  # remove the symlink
echo "# local version" > "$TEST_DIR/claude/scripts/session.sh"  # create real file
ACTIONS=()
link_files_if_needed "$TEST_DIR/engine/scripts" "$TEST_DIR/claude/scripts" "scripts"
[ ! -L "$TEST_DIR/claude/scripts/session.sh" ] && pass "FILES-06: Preserves local override (real file not replaced)" || fail "FILES-06" "real file" "symlink"
teardown

setup
# Idempotent — second run creates no new links
link_files_if_needed "$TEST_DIR/engine/scripts" "$TEST_DIR/claude/scripts" "scripts"
ACTIONS=()
link_files_if_needed "$TEST_DIR/engine/scripts" "$TEST_DIR/claude/scripts" "scripts"
[ ${#ACTIONS[@]} -eq 0 ] && pass "FILES-07: Idempotent — no ACTIONS on re-run" || fail "FILES-07" "0 actions" "${#ACTIONS[@]} actions"
teardown

setup
# Empty source dir
mkdir -p "$TEST_DIR/empty-src"
link_files_if_needed "$TEST_DIR/empty-src" "$TEST_DIR/claude/empty-dest" "empty"
[ -d "$TEST_DIR/claude/empty-dest" ] && pass "FILES-08: Creates dest dir even with empty source" || fail "FILES-08" "dir exists" "missing"
count=$(ls -1A "$TEST_DIR/claude/empty-dest/" 2>/dev/null | wc -l | tr -d ' ')
[ "$count" = "0" ] && pass "FILES-09: Empty source produces empty dest" || fail "FILES-09" "0" "$count"
teardown

# ============================================================================
# setup_engine_symlinks tests
# ============================================================================
echo ""
echo "=== setup_engine_symlinks ==="

setup
setup_engine_symlinks "$TEST_DIR/engine" "$TEST_DIR/claude"
# Check whole-dir symlinks
[ -L "$TEST_DIR/claude/commands" ] && pass "ENGINE-01: commands/ symlinked" || fail "ENGINE-01" "symlink" "not"
[ -L "$TEST_DIR/claude/standards" ] && pass "ENGINE-02: standards/ symlinked" || fail "ENGINE-02" "symlink" "not"
[ -L "$TEST_DIR/claude/agents" ] && pass "ENGINE-03: agents/ symlinked" || fail "ENGINE-03" "symlink" "not"
# Check per-file symlinks
[ -L "$TEST_DIR/claude/scripts/session.sh" ] && pass "ENGINE-04: scripts/ has per-file symlinks" || fail "ENGINE-04" "symlink" "not"
[ -L "$TEST_DIR/claude/hooks/pre-tool-use-overflow.sh" ] && pass "ENGINE-05: hooks/ has per-file symlinks" || fail "ENGINE-05" "symlink" "not"
# Check per-skill symlinks
[ -L "$TEST_DIR/claude/skills/brainstorm" ] && pass "ENGINE-06: skills/brainstorm symlinked" || fail "ENGINE-06" "symlink" "not"
[ -L "$TEST_DIR/claude/skills/implement" ] && pass "ENGINE-07: skills/implement symlinked" || fail "ENGINE-07" "symlink" "not"
[ -L "$TEST_DIR/claude/skills/test" ] && pass "ENGINE-08: skills/test symlinked" || fail "ENGINE-08" "symlink" "not"
teardown

setup
# Test permission fixing
chmod -x "$TEST_DIR/engine/scripts/session.sh"
setup_engine_symlinks "$TEST_DIR/engine" "$TEST_DIR/claude"
[ -x "$TEST_DIR/engine/scripts/session.sh" ] && pass "ENGINE-09: Fixed +x on non-executable script" || fail "ENGINE-09" "executable" "not executable"
teardown

setup
# Test with tools
mkdir -p "$TEST_DIR/engine/tools/session-search"
echo '#!/bin/bash' > "$TEST_DIR/engine/tools/session-search/session-search.sh"
chmod +x "$TEST_DIR/engine/tools/session-search/session-search.sh"
setup_engine_symlinks "$TEST_DIR/engine" "$TEST_DIR/claude"
[ -L "$TEST_DIR/claude/tools" ] && pass "ENGINE-10: tools/ symlinked" || fail "ENGINE-10" "symlink" "not"
[ -L "$TEST_DIR/claude/scripts/session-search.sh" ] && pass "ENGINE-11: tool script linked into scripts/" || fail "ENGINE-11" "symlink" "not"
teardown

setup
# Idempotent
setup_engine_symlinks "$TEST_DIR/engine" "$TEST_DIR/claude"
ACTIONS=()
setup_engine_symlinks "$TEST_DIR/engine" "$TEST_DIR/claude"
[ ${#ACTIONS[@]} -eq 0 ] && pass "ENGINE-12: Idempotent — no ACTIONS on re-run" || fail "ENGINE-12" "0 actions" "${#ACTIONS[@]} actions"
teardown

# ============================================================================
# merge_permissions tests
# ============================================================================
echo ""
echo "=== merge_permissions ==="

setup
perms='{"permissions":{"allow":["Read(foo)","Write(bar)"]}}'
merge_permissions "$TEST_DIR/claude/settings.json" "$perms"
[ -f "$TEST_DIR/claude/settings.json" ] && pass "PERMS-01: Creates settings.json from scratch" || fail "PERMS-01" "file exists" "missing"
count=$(jq '.permissions.allow | length' "$TEST_DIR/claude/settings.json")
[ "$count" = "2" ] && pass "PERMS-02: Has 2 permission rules" || fail "PERMS-02" "2" "$count"
teardown

setup
echo '{"permissions":{"allow":["Read(foo)"]}}' > "$TEST_DIR/claude/settings.json"
perms='{"permissions":{"allow":["Read(foo)","Write(bar)"]}}'
merge_permissions "$TEST_DIR/claude/settings.json" "$perms"
count=$(jq '.permissions.allow | length' "$TEST_DIR/claude/settings.json")
[ "$count" = "2" ] && pass "PERMS-03: Deduplicates on merge" || fail "PERMS-03" "2" "$count"
teardown

setup
echo '{"permissions":{"allow":["Read(foo)"]},"customKey":"preserved"}' > "$TEST_DIR/claude/settings.json"
perms='{"permissions":{"allow":["Write(bar)"]}}'
merge_permissions "$TEST_DIR/claude/settings.json" "$perms"
custom=$(jq -r '.customKey' "$TEST_DIR/claude/settings.json")
[ "$custom" = "preserved" ] && pass "PERMS-04: Preserves non-permission settings" || fail "PERMS-04" "preserved" "$custom"
teardown

setup
echo '{}' > "$TEST_DIR/claude/settings.json"
perms='{"permissions":{"allow":["Read(foo)"]}}'
merge_permissions "$TEST_DIR/claude/settings.json" "$perms"
count=$(jq '.permissions.allow | length' "$TEST_DIR/claude/settings.json")
[ "$count" = "1" ] && pass "PERMS-05: Merges into empty object" || fail "PERMS-05" "1" "$count"
teardown

# ============================================================================
# configure_statusline tests
# ============================================================================
echo ""
echo "=== configure_statusline ==="

setup
echo '{}' > "$TEST_DIR/claude/settings.json"
configure_statusline "$TEST_DIR/claude/settings.json"
sl=$(jq -r '.statusLine.command' "$TEST_DIR/claude/settings.json")
[[ "$sl" == *"statusline.sh"* ]] && pass "SL-01: Adds statusLine hook" || fail "SL-01" "statusline.sh" "$sl"
teardown

setup
echo '{"statusLine":{"type":"command","command":"~/.claude/tools/statusline.sh"}}' > "$TEST_DIR/claude/settings.json"
ACTIONS=()
configure_statusline "$TEST_DIR/claude/settings.json"
[ ${#ACTIONS[@]} -eq 0 ] && pass "SL-02: Idempotent — no change when already configured" || fail "SL-02" "0 actions" "${#ACTIONS[@]} actions"
teardown

setup
echo '{"statusLine":{"type":"command","command":"input=$(cat);echo done"}}' > "$TEST_DIR/claude/settings.json"
configure_statusline "$TEST_DIR/claude/settings.json"
sl=$(jq -r '.statusLine.command' "$TEST_DIR/claude/settings.json")
[[ "$sl" == *"statusline.sh"* ]] && pass "SL-03: Replaces non-engine statusLine" || fail "SL-03" "statusline.sh" "$sl"
[[ "${ACTIONS[0]}" == *"Replaced"* ]] && pass "SL-04: ACTIONS logs replacement" || fail "SL-04" "Replaced..." "${ACTIONS[0]:-empty}"
teardown

# ============================================================================
# configure_hooks tests
# ============================================================================
echo ""
echo "=== configure_hooks ==="

setup
echo '{}' > "$TEST_DIR/claude/settings.json"
configure_hooks "$TEST_DIR/claude/settings.json"
jq -e '.hooks.Notification' "$TEST_DIR/claude/settings.json" >/dev/null 2>&1 && pass "HOOKS-01: Adds Notification hooks" || fail "HOOKS-01" "present" "missing"
jq -e '.hooks.PreToolUse' "$TEST_DIR/claude/settings.json" >/dev/null 2>&1 && pass "HOOKS-02: Adds PreToolUse hooks" || fail "HOOKS-02" "present" "missing"
teardown

setup
echo '{"hooks":{"Notification":[{"matcher":"test"}]}}' > "$TEST_DIR/claude/settings.json"
ACTIONS=()
configure_hooks "$TEST_DIR/claude/settings.json"
[ ${#ACTIONS[@]} -eq 0 ] && pass "HOOKS-03: Idempotent — no change when Notification exists" || fail "HOOKS-03" "0 actions" "${#ACTIONS[@]} actions"
teardown

# ============================================================================
# link_project_dir tests
# ============================================================================
echo ""
echo "=== link_project_dir ==="

setup
mkdir -p "$TEST_DIR/gdrive/sessions"
link_project_dir "$TEST_DIR/gdrive/sessions" "$TEST_DIR/project/sessions" "./sessions"
[ -L "$TEST_DIR/project/sessions" ] && pass "PROJ-01: Creates project symlink" || fail "PROJ-01" "symlink" "not"
actual=$(readlink "$TEST_DIR/project/sessions")
[ "$actual" = "$TEST_DIR/gdrive/sessions" ] && pass "PROJ-02: Points to correct target" || fail "PROJ-02" "$TEST_DIR/gdrive/sessions" "$actual"
teardown

setup
mkdir -p "$TEST_DIR/gdrive/sessions"
ln -s "$TEST_DIR/gdrive/sessions" "$TEST_DIR/project/sessions"
ACTIONS=()
link_project_dir "$TEST_DIR/gdrive/sessions" "$TEST_DIR/project/sessions" "./sessions"
[ ${#ACTIONS[@]} -eq 0 ] && pass "PROJ-03: Idempotent — correct symlink unchanged" || fail "PROJ-03" "0 actions" "${#ACTIONS[@]} actions"
teardown

setup
mkdir -p "$TEST_DIR/project/sessions"
echo "data" > "$TEST_DIR/project/sessions/file.txt"
link_project_dir "$TEST_DIR/gdrive/sessions" "$TEST_DIR/project/sessions" "./sessions"
rc=$?
[ "$rc" -eq 2 ] && pass "PROJ-04: Returns 2 for existing real directory" || fail "PROJ-04" "exit 2" "exit $rc"
[ -f "$TEST_DIR/project/sessions/file.txt" ] && pass "PROJ-05: Real dir content preserved" || fail "PROJ-05" "file exists" "missing"
teardown

# ============================================================================
# ensure_project_standards tests
# ============================================================================
echo ""
echo "=== ensure_project_standards ==="

setup
ensure_project_standards "$TEST_DIR/project"
[ -f "$TEST_DIR/project/.claude/standards/INVARIANTS.md" ] && pass "STD-01: Creates INVARIANTS.md" || fail "STD-01" "file exists" "missing"
teardown

setup
mkdir -p "$TEST_DIR/project/.claude/standards"
echo "# Custom" > "$TEST_DIR/project/.claude/standards/INVARIANTS.md"
ACTIONS=()
ensure_project_standards "$TEST_DIR/project"
content=$(cat "$TEST_DIR/project/.claude/standards/INVARIANTS.md")
[ "$content" = "# Custom" ] && pass "STD-02: Preserves existing INVARIANTS.md" || fail "STD-02" "# Custom" "$content"
[ ${#ACTIONS[@]} -eq 0 ] && pass "STD-03: No ACTIONS when file exists" || fail "STD-03" "0 actions" "${#ACTIONS[@]} actions"
teardown

# ============================================================================
# update_gitignore tests
# ============================================================================
echo ""
echo "=== update_gitignore ==="

setup
update_gitignore "$TEST_DIR/project" "sessions" "reports"
[ -f "$TEST_DIR/project/.gitignore" ] && pass "GIT-01: Creates .gitignore when missing" || fail "GIT-01" "file exists" "missing"
grep -q "sessions" "$TEST_DIR/project/.gitignore" && pass "GIT-02: Contains 'sessions'" || fail "GIT-02" "sessions" "missing"
grep -q "reports" "$TEST_DIR/project/.gitignore" && pass "GIT-03: Contains 'reports'" || fail "GIT-03" "reports" "missing"
teardown

setup
echo "node_modules" > "$TEST_DIR/project/.gitignore"
update_gitignore "$TEST_DIR/project" "sessions" "reports"
grep -q "node_modules" "$TEST_DIR/project/.gitignore" && pass "GIT-04: Preserves existing entries" || fail "GIT-04" "node_modules" "missing"
grep -q "sessions" "$TEST_DIR/project/.gitignore" && pass "GIT-05: Adds new entries" || fail "GIT-05" "sessions" "missing"
teardown

setup
printf 'sessions\nreports\n' > "$TEST_DIR/project/.gitignore"
ACTIONS=()
update_gitignore "$TEST_DIR/project" "sessions" "reports"
[ ${#ACTIONS[@]} -eq 0 ] && pass "GIT-06: Idempotent — no duplicate entries" || fail "GIT-06" "0 actions" "${#ACTIONS[@]} actions"
teardown

setup
printf 'sessions/\n' > "$TEST_DIR/project/.gitignore"
ACTIONS=()
update_gitignore "$TEST_DIR/project" "sessions"
[ ${#ACTIONS[@]} -eq 0 ] && pass "GIT-07: Recognizes entry with trailing slash" || fail "GIT-07" "0 actions" "${#ACTIONS[@]} actions"
teardown

# ============================================================================
# Results
# ============================================================================
echo ""
echo "======================================"
echo -e "Results: \033[32m${PASS} passed\033[0m, \033[31m${FAIL} failed\033[0m ($(( PASS + FAIL )) total)"
echo "======================================"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
