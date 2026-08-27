#!/bin/bash
# ~/.claude/engine/scripts/tests/test-deploy-tombstones.sh — Tests for `engine deploy`
# skill protection, orphan adoption, and the tombstone list.
#
# The shared Google Drive engine copy is writable, so people author skills directly on it.
# `rsync -a --delete` from a clone that lacks such a skill used to destroy it silently.
# These tests pin the three behaviours that replaced that:
#
#   1. --delete never removes anything under skills/
#   2. a Drive-only path is reported, and offered for adoption into the local repo
#   3. a path listed in deploy-tombstones.txt is deleted anyway, and never offered
#
# Every case runs against fixture trees in mktemp via the LOCAL_ENGINE / GDRIVE_ENGINE env
# overrides. Nothing here touches the real Google Drive mount.
#
# Run: bash ~/.claude/engine/scripts/tests/test-deploy-tombstones.sh

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENGINE_SH="$HOME/.claude/engine/scripts/engine.sh"

TEST_DIR=""
FIX_LOCAL=""
FIX_GDRIVE=""

# ============================================================================
# Fixture
# ============================================================================

# A pair of trees standing in for the clone and the Drive copy:
#
#   both sides:   skills/build/SKILL.md, docs/README.md
#   drive only:   skills/email-qa/**            (a teammate authored it on the Drive)
#   drive only:   skills/inbox-triage/**        (retired — tombstoned)
#   drive only:   skills/inbox-triangulate/**  (retired — tombstoned only by the shipped file)
#   drive only:   docs/STALE.md                 (outside skills/ — normal --delete applies)
#   local only:   skills/triage/SKILL.md        (the rename the Drive has not seen)
make_fixture() {
  TEST_DIR=$(mktemp -d)
  FIX_LOCAL="$TEST_DIR/local"
  FIX_GDRIVE="$TEST_DIR/gdrive"

  mkdir -p "$FIX_LOCAL/skills/build" "$FIX_LOCAL/skills/triage" "$FIX_LOCAL/docs"
  echo "build skill" > "$FIX_LOCAL/skills/build/SKILL.md"
  echo "triage skill" > "$FIX_LOCAL/skills/triage/SKILL.md"
  echo "readme" > "$FIX_LOCAL/docs/README.md"

  mkdir -p "$FIX_GDRIVE/skills/build" "$FIX_GDRIVE/skills/email-qa" \
           "$FIX_GDRIVE/skills/inbox-triage" "$FIX_GDRIVE/docs"
  echo "build skill" > "$FIX_GDRIVE/skills/build/SKILL.md"
  echo "email qa skill" > "$FIX_GDRIVE/skills/email-qa/SKILL.md"
  echo "email qa asset" > "$FIX_GDRIVE/skills/email-qa/ASSET.md"
  echo "retired" > "$FIX_GDRIVE/skills/inbox-triage/SKILL.md"
  mkdir -p "$FIX_GDRIVE/skills/inbox-triangulate"
  echo "retired" > "$FIX_GDRIVE/skills/inbox-triangulate/SKILL.md"
  echo "readme" > "$FIX_GDRIVE/docs/README.md"
  echo "stale" > "$FIX_GDRIVE/docs/STALE.md"
}

write_tombstones() {
  cat > "$FIX_LOCAL/deploy-tombstones.txt"
}

# Makes the fixture local tree a git repo so adoption can stage what it copies.
make_fixture_git() {
  git -C "$FIX_LOCAL" init -q 2>/dev/null
  git -C "$FIX_LOCAL" config user.email test@example.com
  git -C "$FIX_LOCAL" config user.name Test
  git -C "$FIX_LOCAL" add skills docs >/dev/null 2>&1
  git -C "$FIX_LOCAL" commit -qm base >/dev/null 2>&1
}

# Runs the real deploy against the fixture. Extra args pass through to cmd_deploy.
# stdin is /dev/null so the interactive branch can never hang the suite.
run_deploy() {
  LOCAL_ENGINE="$FIX_LOCAL" GDRIVE_ENGINE="$FIX_GDRIVE" \
    bash "$ENGINE_SH" deploy "$@" </dev/null 2>&1
}

# Fail-closed guard. These tests invoke the REAL deploy, so if the env overrides ever stop
# taking effect the suite would rsync the working tree onto the shared Google Drive copy and
# blow away its backup. Refuse to run at all unless a --dry-run deploy reports the fixture as
# its target. Checked once, before any test.
assert_fixture_targeted() {
  make_fixture
  local out
  out=$(run_deploy --dry-run)
  if ! echo "$out" | grep -qF "$FIX_GDRIVE"; then
    echo "ABORT: deploy did not target the fixture. LOCAL_ENGINE/GDRIVE_ENGINE overrides are"
    echo "       not taking effect, and running these tests would hit the real Google Drive."
    echo "       Expected target: $FIX_GDRIVE"
    echo "--- deploy output ---"
    echo "$out"
    teardown
    exit 1
  fi
  if echo "$out" | grep -q "CloudStorage"; then
    echo "ABORT: deploy output mentions a CloudStorage path. Refusing to run."
    teardown
    exit 1
  fi
  teardown
  echo "Preflight: deploy targets the fixture, not the Drive."
}

setup() {
  make_fixture
  write_tombstones <<'EOF'
# a comment line
skills/inbox-triage  2026-08-27  Renamed to skills/triage.
EOF
}

teardown() {
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
  TEST_DIR=""
}

# ============================================================================
# 0. Control — prove the protect filter is what saves the skill
# ============================================================================

# A green protection test means nothing if this rsync build silently ignores --filter.
# Run the same transfer twice against identical trees, once without the protect rule and once
# with it, and require the two to disagree.
test_control_filter_is_load_bearing() {
  local a="$TEST_DIR/ctl-unprotected" b="$TEST_DIR/ctl-protected"
  mkdir -p "$a/skills/email-qa" "$b/skills/email-qa"
  echo x > "$a/skills/email-qa/SKILL.md"
  echo x > "$b/skills/email-qa/SKILL.md"

  rsync -a --delete "$FIX_LOCAL/" "$a/" >/dev/null 2>&1
  rsync -a --delete --filter='P skills/**' "$FIX_LOCAL/" "$b/" >/dev/null 2>&1

  if [ ! -e "$a/skills/email-qa" ]; then
    pass "Control: without the protect rule, --delete does destroy the Drive-only skill"
  else
    fail "Control: without the protect rule, --delete does destroy the Drive-only skill" \
         "skills/email-qa deleted" "survived — this rsync is not deleting, so the protection tests prove nothing"
  fi

  if [ -f "$b/skills/email-qa/SKILL.md" ]; then
    pass "Control: with the protect rule, the same skill survives"
  else
    fail "Control: with the protect rule, the same skill survives" "skills/email-qa present" "deleted — --filter is being ignored"
  fi
}

# Same idea for the risk rule: a tombstoned path must die where an untombstoned one lives.
test_control_risk_rule_is_load_bearing() {
  local b="$TEST_DIR/ctl-risk"
  mkdir -p "$b/skills/email-qa" "$b/skills/inbox-triage"
  echo x > "$b/skills/email-qa/SKILL.md"
  echo x > "$b/skills/inbox-triage/SKILL.md"

  rsync -a --delete \
    --filter='R skills/inbox-triage' --filter='R skills/inbox-triage/***' \
    --filter='P skills/**' \
    "$FIX_LOCAL/" "$b/" >/dev/null 2>&1

  if [ ! -e "$b/skills/inbox-triage" ] && [ -f "$b/skills/email-qa/SKILL.md" ]; then
    pass "Control: an R rule ahead of the P rule un-protects exactly one path"
  else
    fail "Control: an R rule ahead of the P rule un-protects exactly one path" \
         "inbox-triage gone, email-qa kept" \
         "inbox-triage=$([ -e "$b/skills/inbox-triage" ] && echo present || echo gone) email-qa=$([ -e "$b/skills/email-qa" ] && echo present || echo gone)"
  fi
}

# ============================================================================
# 1. --delete must not remove anything under skills/
# ============================================================================

test_drive_only_skill_survives() {
  run_deploy >/dev/null
  if [ -f "$FIX_GDRIVE/skills/email-qa/SKILL.md" ]; then
    pass "Drive-only skill survives the deploy"
  else
    fail "Drive-only skill survives the deploy" "skills/email-qa/SKILL.md present" "deleted"
  fi
}

test_drive_only_file_inside_shared_skill_survives() {
  echo "drive-authored" > "$FIX_GDRIVE/skills/build/EXTRA.md"
  run_deploy >/dev/null
  if [ -f "$FIX_GDRIVE/skills/build/EXTRA.md" ]; then
    pass "Drive-only file inside a shared skill survives"
  else
    fail "Drive-only file inside a shared skill survives" "skills/build/EXTRA.md present" "deleted"
  fi
}

test_non_skills_deletion_still_happens() {
  run_deploy >/dev/null
  if [ ! -f "$FIX_GDRIVE/docs/STALE.md" ]; then
    pass "Outside skills/, --delete still removes Drive-only paths"
  else
    fail "Outside skills/, --delete still removes Drive-only paths" "docs/STALE.md deleted" "still present"
  fi
}

test_local_content_still_deploys() {
  run_deploy >/dev/null
  if [ -f "$FIX_GDRIVE/skills/triage/SKILL.md" ]; then
    pass "Local-only skill is still pushed to the Drive"
  else
    fail "Local-only skill is still pushed to the Drive" "skills/triage/SKILL.md present" "missing"
  fi
}

# ============================================================================
# 2. Tombstones delete, and are announced before the deletion
# ============================================================================

test_tombstoned_path_is_deleted() {
  run_deploy >/dev/null
  if [ ! -e "$FIX_GDRIVE/skills/inbox-triage" ]; then
    pass "Tombstoned path is deleted from the Drive despite skills/ protection"
  else
    fail "Tombstoned path is deleted from the Drive despite skills/ protection" \
         "skills/inbox-triage gone" "still present"
  fi
}

test_deletion_is_announced_before_it_happens() {
  local output
  output=$(run_deploy)

  if echo "$output" | grep -q "skills/inbox-triage"; then
    pass "Deletion output names the tombstoned path"
  else
    fail "Deletion output names the tombstoned path" "mentions skills/inbox-triage" "$output"
  fi

  # The announcement must precede the rsync, not follow it.
  local announce_line rsync_line
  announce_line=$(echo "$output" | grep -n "skills/inbox-triage" | head -1 | cut -d: -f1)
  rsync_line=$(echo "$output" | grep -n "Syncing local engine" | head -1 | cut -d: -f1)
  if [ -n "$announce_line" ] && [ -n "$rsync_line" ] && [ "$announce_line" -lt "$rsync_line" ]; then
    pass "Deletion is announced before the sync runs"
  else
    fail "Deletion is announced before the sync runs" \
         "announce line < sync line" "announce=$announce_line sync=$rsync_line"
  fi
}

test_tombstone_reason_is_shown() {
  local output
  output=$(run_deploy)
  if echo "$output" | grep -q "Renamed to skills/triage"; then
    pass "Tombstone reason is shown alongside the path"
  else
    fail "Tombstone reason is shown alongside the path" "reason text in output" "$output"
  fi
}

# ============================================================================
# 3. Tombstone parsing rejects anything it cannot trust
# ============================================================================

test_absolute_tombstone_path_rejected() {
  write_tombstones <<'EOF'
/etc  2026-08-27  absolute path, must be refused
EOF
  local output
  output=$(run_deploy)
  if echo "$output" | grep -qi "ignoring"; then
    pass "Absolute tombstone path is rejected with a warning"
  else
    fail "Absolute tombstone path is rejected with a warning" "warning in output" "$output"
  fi
}

test_traversal_tombstone_path_rejected() {
  write_tombstones <<'EOF'
skills/../../etc  2026-08-27  traversal, must be refused
EOF
  local output
  output=$(run_deploy)
  if echo "$output" | grep -qi "ignoring"; then
    pass "Tombstone path containing .. is rejected with a warning"
  else
    fail "Tombstone path containing .. is rejected with a warning" "warning in output" "$output"
  fi
}

test_undated_tombstone_rejected() {
  write_tombstones <<'EOF'
skills/inbox-triage  sometime  no real date
EOF
  run_deploy >/dev/null
  if [ -e "$FIX_GDRIVE/skills/inbox-triage" ]; then
    pass "Tombstone without a YYYY-MM-DD date has no effect"
  else
    fail "Tombstone without a YYYY-MM-DD date has no effect" \
         "skills/inbox-triage still present" "deleted by an unparseable line"
  fi
}

test_comments_and_blanks_ignored() {
  write_tombstones <<'EOF'
# skills/build  2026-08-27  commented out, must not apply

EOF
  run_deploy >/dev/null
  if [ -f "$FIX_GDRIVE/skills/build/SKILL.md" ]; then
    pass "Commented and blank tombstone lines are ignored"
  else
    fail "Commented and blank tombstone lines are ignored" "skills/build intact" "deleted"
  fi
}

test_cannot_tombstone_a_protected_root() {
  # A single typo'd line must not be able to switch the whole protection off.
  write_tombstones <<'EOF'
skills  2026-08-27  oops, this would un-protect everything
EOF
  local output
  output=$(run_deploy)

  if echo "$output" | grep -qi "cannot retire the protected root"; then
    pass "Tombstoning a protected root is refused with a warning"
  else
    fail "Tombstoning a protected root is refused with a warning" "warning in output" "$output"
  fi

  if [ -f "$FIX_GDRIVE/skills/email-qa/SKILL.md" ]; then
    pass "Refusing that tombstone keeps skills/ protected"
  else
    fail "Refusing that tombstone keeps skills/ protected" "email-qa intact" "deleted"
  fi
}

test_indented_comment_ignored() {
  write_tombstones <<'EOF'
   # indented comment
	# tab-indented comment
skills/inbox-triage  2026-08-27  Renamed to skills/triage.
EOF
  local output
  output=$(run_deploy)
  if echo "$output" | grep -qi "ignoring"; then
    fail "Indented comment lines are ignored" "no warnings" "$output"
  else
    pass "Indented comment lines are ignored"
  fi
}

test_missing_tombstone_file_is_not_fatal() {
  rm -f "$FIX_LOCAL/deploy-tombstones.txt"
  local output rc
  output=$(run_deploy); rc=$?
  if [ "$rc" -eq 0 ] && [ -f "$FIX_GDRIVE/skills/email-qa/SKILL.md" ]; then
    pass "Missing tombstone file leaves everything protected and exits clean"
  else
    fail "Missing tombstone file leaves everything protected and exits clean" \
         "exit 0, email-qa intact" "rc=$rc"
  fi
}

# ============================================================================
# 4. Orphan reporting and adoption
# ============================================================================

test_orphan_reported_when_unattended() {
  local output
  output=$(run_deploy)
  if echo "$output" | grep -q "skills/email-qa"; then
    pass "Drive-only skill is reported by name"
  else
    fail "Drive-only skill is reported by name" "mentions skills/email-qa" "$output"
  fi
}

test_unattended_deploy_does_not_adopt() {
  run_deploy >/dev/null
  if [ ! -e "$FIX_LOCAL/skills/email-qa" ]; then
    pass "Unattended deploy does not write the orphan into the repo"
  else
    fail "Unattended deploy does not write the orphan into the repo" \
         "skills/email-qa absent locally" "adopted without being asked"
  fi
}

test_tombstoned_path_never_reported_as_orphan() {
  local output
  output=$(run_deploy)
  # inbox-triage is Drive-only, but it is retired: it must appear under deletions,
  # never in the keep/adopt list.
  if echo "$output" | grep -A4 "not in your clone" | grep -q "inbox-triage"; then
    fail "Tombstoned path is never offered for adoption" \
         "inbox-triage absent from the keep list" "$output"
  else
    pass "Tombstoned path is never offered for adoption"
  fi
}

test_adopt_flag_copies_and_stages() {
  make_fixture_git
  run_deploy --adopt >/dev/null

  if [ -f "$FIX_LOCAL/skills/email-qa/SKILL.md" ] && [ -f "$FIX_LOCAL/skills/email-qa/ASSET.md" ]; then
    pass "--adopt copies the whole orphan directory into the repo"
  else
    fail "--adopt copies the whole orphan directory into the repo" "both files copied" "missing"
  fi

  local staged
  staged=$(git -C "$FIX_LOCAL" diff --cached --name-only 2>/dev/null | grep -c 'skills/email-qa')
  if [ "$staged" -ge 1 ]; then
    pass "--adopt stages the adopted path in git"
  else
    fail "--adopt stages the adopted path in git" ">=1 staged path" "$staged"
  fi
}

test_adopt_does_not_adopt_tombstoned_path() {
  make_fixture_git
  run_deploy --adopt >/dev/null
  if [ ! -e "$FIX_LOCAL/skills/inbox-triage" ]; then
    pass "--adopt refuses to adopt a tombstoned path"
  else
    fail "--adopt refuses to adopt a tombstoned path" "skills/inbox-triage absent locally" "adopted"
  fi
}

test_adopt_leaves_drive_copy_intact() {
  make_fixture_git
  run_deploy --adopt >/dev/null
  if [ -f "$FIX_GDRIVE/skills/email-qa/SKILL.md" ]; then
    pass "Adoption leaves the Drive copy in place"
  else
    fail "Adoption leaves the Drive copy in place" "Drive copy present" "removed"
  fi
}

test_no_adopt_flag_skips_adoption() {
  make_fixture_git
  run_deploy --no-adopt >/dev/null
  if [ ! -e "$FIX_LOCAL/skills/email-qa" ]; then
    pass "--no-adopt leaves the orphan unadopted"
  else
    fail "--no-adopt leaves the orphan unadopted" "skills/email-qa absent locally" "adopted anyway"
  fi
}

test_adoption_never_overwrites_local() {
  make_fixture_git
  mkdir -p "$FIX_LOCAL/skills/email-qa"
  echo "mine, do not clobber" > "$FIX_LOCAL/skills/email-qa/SKILL.md"
  run_deploy --adopt >/dev/null
  local content
  content=$(cat "$FIX_LOCAL/skills/email-qa/SKILL.md")
  assert_eq "mine, do not clobber" "$content" "Adoption never overwrites an existing local path"
}

# ============================================================================
# 4b. The interactive path — adoption asks, and honours the answer
# ============================================================================

# Runs deploy under a pseudo-terminal so `[ -t 0 ]` is true and the prompt branch is taken.
# $1 is fed as the answer. The sleeps matter: the pty drops input written before the child
# starts reading, so a bare `printf y |` silently exercises the EOF path instead.
run_deploy_interactive() {
  local answer="$1"
  { sleep 2; printf '%s\n' "$answer"; sleep 2; } \
    | script -q /dev/null env LOCAL_ENGINE="$FIX_LOCAL" GDRIVE_ENGINE="$FIX_GDRIVE" \
        bash "$ENGINE_SH" deploy 2>&1
}

pty_available() {
  case "$(uname -s)" in
    Darwin|*BSD) command -v script >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

test_interactive_yes_adopts() {
  if ! pty_available; then
    skip "Interactive adoption" "BSD-style script(1) not available"
    return
  fi
  make_fixture_git
  local output
  output=$(run_deploy_interactive y)

  if echo "$output" | grep -q "Adopt skills/email-qa into"; then
    pass "Interactive deploy asks before adopting"
  else
    fail "Interactive deploy asks before adopting" "an Adopt ...? prompt" "$output"
  fi

  if [ -f "$FIX_LOCAL/skills/email-qa/SKILL.md" ]; then
    pass "Answering y adopts the orphan"
  else
    fail "Answering y adopts the orphan" "skills/email-qa copied locally" "not copied"
  fi
}

test_interactive_no_declines() {
  if ! pty_available; then
    skip "Interactive decline" "BSD-style script(1) not available"
    return
  fi
  make_fixture_git
  local output
  output=$(run_deploy_interactive n)

  if [ ! -e "$FIX_LOCAL/skills/email-qa" ]; then
    pass "Answering n leaves the orphan unadopted"
  else
    fail "Answering n leaves the orphan unadopted" "skills/email-qa absent locally" "adopted anyway"
  fi

  if [ -f "$FIX_GDRIVE/skills/email-qa/SKILL.md" ]; then
    pass "Declining adoption still leaves the Drive copy intact"
  else
    fail "Declining adoption still leaves the Drive copy intact" "Drive copy present" "deleted"
  fi
}

# ============================================================================
# 5. Existing guarantees that must not regress
# ============================================================================

test_backup_still_taken() {
  run_deploy >/dev/null
  if [ -f "${FIX_GDRIVE}.bak/skills/email-qa/SKILL.md" ]; then
    pass "GDrive backup is still taken before the sync"
  else
    fail "GDrive backup is still taken before the sync" "${FIX_GDRIVE}.bak populated" "missing"
  fi
}

test_failed_backup_keeps_the_old_one() {
  # The previous backup must survive a copy that fails or is interrupted. It did not before:
  # the step wiped .bak and then spent minutes on a cp that could be killed at any point.
  mkdir -p "${FIX_GDRIVE}.bak"
  echo "the previous backup" > "${FIX_GDRIVE}.bak/MARKER"

  chmod 555 "$TEST_DIR"
  local rc=0
  run_deploy >/dev/null || rc=$?
  chmod 755 "$TEST_DIR"

  if [ "$rc" -ne 0 ] && [ -f "${FIX_GDRIVE}.bak/MARKER" ]; then
    pass "A failed backup aborts the deploy and leaves the previous backup intact"
  else
    fail "A failed backup aborts the deploy and leaves the previous backup intact" \
         "non-zero exit, MARKER still present" \
         "rc=$rc marker=$([ -f "${FIX_GDRIVE}.bak/MARKER" ] && echo present || echo GONE)"
  fi
}

test_backup_leaves_no_scratch_dir() {
  run_deploy >/dev/null
  if [ ! -e "${FIX_GDRIVE}.bak.new" ]; then
    pass "Backup leaves no .bak.new scratch directory behind"
  else
    fail "Backup leaves no .bak.new scratch directory behind" "absent" "still present"
  fi
}

test_dry_run_changes_nothing() {
  run_deploy --dry-run >/dev/null
  local ok=true
  [ -e "$FIX_GDRIVE/skills/inbox-triage" ] || ok=false
  [ -f "$FIX_GDRIVE/docs/STALE.md" ] || ok=false
  [ -e "$FIX_LOCAL/skills/email-qa" ] && ok=false
  if [ "$ok" = true ]; then
    pass "--dry-run deletes nothing and adopts nothing"
  else
    fail "--dry-run deletes nothing and adopts nothing" "fixture unchanged" "fixture mutated"
  fi
}

test_dry_run_still_reports() {
  local output
  output=$(run_deploy --dry-run)
  if echo "$output" | grep -q "skills/inbox-triage" && echo "$output" | grep -q "skills/email-qa"; then
    pass "--dry-run still reports the deletion and the orphan"
  else
    fail "--dry-run still reports the deletion and the orphan" "both paths named" "$output"
  fi
}

# ============================================================================
# 6. The shipped tombstone file
# ============================================================================

test_shipped_tombstone_file_parses() {
  local shipped="$HOME/.claude/engine/deploy-tombstones.txt"
  if [ ! -f "$shipped" ]; then
    fail "Shipped deploy-tombstones.txt exists" "$shipped" "missing"
    return
  fi
  pass "Shipped deploy-tombstones.txt exists"

  cp "$shipped" "$FIX_LOCAL/deploy-tombstones.txt"
  local output
  output=$(run_deploy)

  if echo "$output" | grep -qi "ignoring"; then
    fail "Shipped tombstone file parses without warnings" "no 'ignoring' lines" "$output"
  else
    pass "Shipped tombstone file parses without warnings"
  fi

  if [ ! -e "$FIX_GDRIVE/skills/inbox-triage" ]; then
    pass "Shipped tombstone file retires skills/inbox-triage"
  else
    fail "Shipped tombstone file retires skills/inbox-triage" "deleted" "still present"
  fi

  if [ ! -e "$FIX_GDRIVE/skills/inbox-triangulate" ]; then
    pass "Shipped tombstone file also retires skills/inbox-triangulate"
  else
    fail "Shipped tombstone file also retires skills/inbox-triangulate" "deleted" "still present"
  fi
}

# ============================================================================
# Runner
# ============================================================================

echo "Running deploy tombstone/protection tests..."
assert_fixture_targeted
echo ""

for t in \
  test_control_filter_is_load_bearing \
  test_control_risk_rule_is_load_bearing \
  test_drive_only_skill_survives \
  test_drive_only_file_inside_shared_skill_survives \
  test_non_skills_deletion_still_happens \
  test_local_content_still_deploys \
  test_tombstoned_path_is_deleted \
  test_deletion_is_announced_before_it_happens \
  test_tombstone_reason_is_shown \
  test_absolute_tombstone_path_rejected \
  test_traversal_tombstone_path_rejected \
  test_undated_tombstone_rejected \
  test_comments_and_blanks_ignored \
  test_cannot_tombstone_a_protected_root \
  test_indented_comment_ignored \
  test_missing_tombstone_file_is_not_fatal \
  test_orphan_reported_when_unattended \
  test_unattended_deploy_does_not_adopt \
  test_tombstoned_path_never_reported_as_orphan \
  test_adopt_flag_copies_and_stages \
  test_adopt_does_not_adopt_tombstoned_path \
  test_adopt_leaves_drive_copy_intact \
  test_no_adopt_flag_skips_adoption \
  test_adoption_never_overwrites_local \
  test_interactive_yes_adopts \
  test_interactive_no_declines \
  test_backup_still_taken \
  test_failed_backup_keeps_the_old_one \
  test_backup_leaves_no_scratch_dir \
  test_dry_run_changes_nothing \
  test_dry_run_still_reports \
  test_shipped_tombstone_file_parses \
; do
  setup
  "$t"
  teardown
done

echo ""
exit_with_results
