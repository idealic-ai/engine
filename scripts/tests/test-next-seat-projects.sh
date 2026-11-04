#!/bin/bash
# test-next-seat-projects.sh — /next reads the seat's Linear project(s) from the director's
# seat→project table (TICKETFLOW Fix A).
#
# BEHAVIOUR arms run skills/next/assets/seat-projects.sh, the one place the table is read:
# which rows a seat gets, what a seat with no row hears, and that an unreadable table or a
# missing seat identity is reported as unread (exit 2), never as "no row".
# One LIVE-CONFIG arm reads the director's real table when it is on this machine, so the green
# says something about that file and not only about the fixtures here.
# TEXT arms hold skills/next/SKILL.md to calling the helper and saying when it found no row.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENGINE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL="$ENGINE_DIR/skills/next/SKILL.md"
HELPER="$ENGINE_DIR/skills/next/assets/seat-projects.sh"
LIVE_TABLE="/Users/invizko/Projects/kit/sessions/2026_10_28_DIRECTOR/builds/SEAT_PROJECTS.tsv"

setup() {
  TMP_DIR=$(mktemp -d)
  TABLE="$TMP_DIR/SEAT_PROJECTS.tsv"
  printf '%s\n' \
    "# seat	linear_project	role	(owned by the director)" \
    "app:writer	Product: Writer	primary" \
    "meta:engine	Product: Orchestration	primary" \
    "app:writer	Product: Editor	primary" \
    "app:writer-x	Product: Other	primary" \
    "meta:overseer	-	none" \
    "" > "$TABLE"
  unset NEXT_SEAT_PROJECTS 2>/dev/null || true
}

teardown() {
  rm -rf "$TMP_DIR"
}

test_seatprojects_rows_for_seat_in_file_order() {
  local out rc
  out=$(FLEET_PANE=app:writer bash "$HELPER" --file "$TABLE" 2>"$TMP_DIR/err"); rc=$?
  assert_eq "0" "$rc" "a seat with rows exits 0"
  assert_eq "Product: Writer	primary
Product: Editor	primary" "$out" "every row of the seat, in file order, project<TAB>role"
  assert_not_contains "Product: Other" "$out" "a seat whose name only starts the same is not matched"
}

test_seatprojects_no_row_says_so() {
  local out rc err
  out=$(FLEET_PANE=core:ui bash "$HELPER" --file "$TABLE" 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_eq "1" "$rc" "a seat with no row exits 1"
  assert_empty "$out" "no project printed"
  assert_contains "no row" "$err" "stderr says it found no row"
  assert_contains "core:ui" "$err" "stderr names the seat"
  assert_contains "$TABLE" "$err" "stderr names the table it read"
}

test_seatprojects_row_naming_no_project() {
  local out rc err
  out=$(FLEET_PANE=meta:overseer bash "$HELPER" --file "$TABLE" 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_eq "1" "$rc" "a seat mapped to '-' exits 1"
  assert_empty "$out" "no project printed"
  assert_contains "no project" "$err" "stderr says the row names no project"
}

test_seatprojects_seat_flag_overrides_env() {
  local out rc
  out=$(FLEET_PANE=app:writer bash "$HELPER" --seat meta:engine --file "$TABLE" 2>/dev/null); rc=$?
  assert_eq "0" "$rc" "--seat exits 0"
  assert_eq "Product: Orchestration	primary" "$out" "--seat picks the seat"
}

test_seatprojects_no_seat_is_unread() {
  local out rc err
  out=$(FLEET_PANE= bash "$HELPER" --file "$TABLE" 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_eq "2" "$rc" "empty FLEET_PANE and no --seat exits 2"
  assert_empty "$out" "nothing printed"
  assert_contains "FLEET_PANE" "$err" "stderr names the missing identity"
}

test_seatprojects_missing_table_is_unread_not_no_row() {
  local out rc err
  out=$(FLEET_PANE=app:writer bash "$HELPER" --file "$TMP_DIR/nope.tsv" 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_eq "2" "$rc" "a missing table exits 2"
  assert_contains "$TMP_DIR/nope.tsv" "$err" "stderr names the path"
  assert_not_contains "no row" "$err" "an unread table is never reported as no row"
}

test_seatprojects_table_with_no_rows_is_unread() {
  local out rc
  printf '# seat\tlinear_project\trole\n' > "$TMP_DIR/empty.tsv"
  out=$(FLEET_PANE=app:writer bash "$HELPER" --file "$TMP_DIR/empty.tsv" 2>"$TMP_DIR/err"); rc=$?
  assert_eq "2" "$rc" "a table with no data rows exits 2 (malformed, not an empty map)"
}

test_seatprojects_env_path() {
  local out rc
  out=$(NEXT_SEAT_PROJECTS="$TABLE" FLEET_PANE=meta:engine bash "$HELPER" 2>/dev/null); rc=$?
  assert_eq "0" "$rc" "NEXT_SEAT_PROJECTS names the table"
  assert_eq "Product: Orchestration	primary" "$out" "row read from the env path"
}

# The default path is the director's table under the MAIN checkout's sessions/, so a seat in a
# git worktree of the repository reads the same file in place.
test_seatprojects_default_path_from_a_worktree() {
  local repo="$TMP_DIR/repo" wt="$TMP_DIR/wt" out rc
  mkdir -p "$repo/sessions/2026_10_28_DIRECTOR/builds"
  cp "$TABLE" "$repo/sessions/2026_10_28_DIRECTOR/builds/SEAT_PROJECTS.tsv"
  git -C "$repo" init -q 2>/dev/null
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$repo" worktree add -q "$wt" 2>/dev/null
  out=$(cd "$wt" && FLEET_PANE=meta:engine bash "$HELPER" 2>"$TMP_DIR/err"); rc=$?
  assert_eq "0" "$rc" "default path resolves from a worktree"
  assert_eq "Product: Orchestration	primary" "$out" "read the main checkout's table in place"
  assert_contains "$(cd "$repo" && pwd -P)/sessions/2026_10_28_DIRECTOR/builds/SEAT_PROJECTS.tsv" "$(cat "$TMP_DIR/err")" "stderr names the table it read"
}

# LIVE CONFIG: the director's own file, read in place, when it exists on this machine.
test_seatprojects_live_table_reads() {
  if [ ! -f "$LIVE_TABLE" ]; then skip "director's SEAT_PROJECTS.tsv not on this machine"; return 0; fi
  local out rc
  out=$(FLEET_PANE=meta:engine bash "$HELPER" --file "$LIVE_TABLE" 2>/dev/null); rc=$?
  assert_eq "0" "$rc" "meta:engine has a row in the live table"
  assert_contains "Product: Orchestration" "$out" "the live row names its project"
}

test_seatprojects_skill_calls_the_helper() {
  assert_contains "assets/seat-projects.sh" "$(cat "$SKILL")" "SKILL.md calls the helper"
  assert_contains "no seat-projects row" "$(cat "$SKILL")" "SKILL.md says what a seat with no row reports"
  assert_contains "SEAT_PROJECTS.tsv" "$(cat "$SKILL")" "SKILL.md names the table"
}

run_discovered_tests
