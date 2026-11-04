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
  unset NEXT_SEAT_PROJECTS FLEET_LIVE_PANES FLEET_WARN_ONCE_DIR TMUX TMUX_PANE 2>/dev/null || true
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
  assert_contains "temporary" "$(cat "$TMP_DIR/err")" "stderr labels the hardcoded default as temporary"
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

# ---- Fix round (F3 SEATPATH, F4 live seat, F5) ----

# mk_kit DIR [tracker-line] — a main checkout with a committed CLAUDE.md § Tracker and the table
# under a gitignored-style sessions/ that exists only in the main checkout.
mk_kit() {
  local repo="$1" line="${2:-}"
  mkdir -p "$repo/sessions/x/builds"
  cp "$TABLE" "$repo/sessions/x/builds/SEATS.tsv"
  git -C "$repo" init -q 2>/dev/null
  printf '%s\n' '## Tracker' '' '- **Tracker**: Linear' '- **Issue-key prefix**: `IDE`' > "$repo/CLAUDE.md"
  [ -n "$line" ] && printf '%s\n' "$line" >> "$repo/CLAUDE.md"
  printf 'sessions/\n' > "$repo/.gitignore"
  git -C "$repo" add CLAUDE.md .gitignore
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m init
}

test_seatprojects_tracker_line_names_the_table() {
  local repo="$TMP_DIR/kit" out rc err
  mk_kit "$repo" '- **Seat projects**: `sessions/x/builds/SEATS.tsv`'
  out=$(cd "$repo" && FLEET_PANE=meta:engine bash "$HELPER" 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_eq "0" "$rc" "§ Tracker Seat projects line is read"
  assert_eq "Product: Orchestration	primary" "$out" "row from the table the line names"
  assert_contains "§ Tracker" "$err" "stderr names § Tracker as the source"
  assert_not_contains "temporary" "$err" "the hardcoded default is not used"
}

# A worktree carries CLAUDE.md (tracked) but not sessions/ (ignored): resolve against the main checkout.
test_seatprojects_tracker_line_from_a_worktree() {
  local repo="$TMP_DIR/kit" wt="$TMP_DIR/kitwt" out rc
  mk_kit "$repo" '- **Seat projects**: sessions/x/builds/SEATS.tsv'
  git -C "$repo" worktree add -q "$wt" 2>/dev/null
  out=$(cd "$wt" && FLEET_PANE=meta:engine bash "$HELPER" 2>"$TMP_DIR/err"); rc=$?
  assert_eq "0" "$rc" "worktree resolves the line against the main checkout"
  assert_eq "Product: Orchestration	primary" "$out" "row read from the main checkout's sessions/"
}

test_seatprojects_tracker_line_missing_path_is_unread() {
  local repo="$TMP_DIR/kit" out rc err
  mk_kit "$repo" '- **Seat projects**: sessions/x/builds/NOPE.tsv'
  out=$(cd "$repo" && FLEET_PANE=meta:engine bash "$HELPER" 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_eq "2" "$rc" "a § Tracker line naming a missing path exits 2"
  assert_contains "NOPE.tsv" "$err" "stderr names the path"
  assert_contains "§ Tracker" "$err" "stderr names the source"
  assert_not_contains "temporary" "$err" "no fallback to the hardcoded default"
}

test_seatprojects_env_beats_tracker_line_and_file_beats_env() {
  local repo="$TMP_DIR/kit" out rc
  mk_kit "$repo" '- **Seat projects**: sessions/x/builds/NOPE.tsv'
  out=$(cd "$repo" && NEXT_SEAT_PROJECTS="$TABLE" FLEET_PANE=meta:engine bash "$HELPER" 2>"$TMP_DIR/err"); rc=$?
  assert_eq "0" "$rc" "NEXT_SEAT_PROJECTS wins over the § Tracker line"
  assert_contains "NEXT_SEAT_PROJECTS" "$(cat "$TMP_DIR/err")" "stderr names the env source"
  out=$(cd "$repo" && NEXT_SEAT_PROJECTS="$TMP_DIR/nope.tsv" FLEET_PANE=meta:engine bash "$HELPER" --file "$TABLE" 2>"$TMP_DIR/err"); rc=$?
  assert_eq "0" "$rc" "--file wins over NEXT_SEAT_PROJECTS"
  assert_contains "--file" "$(cat "$TMP_DIR/err")" "stderr names --file as the source"
}

# F4: the seat is read live from tmux (here through FLEET_LIVE_PANES), FLEET_PANE is the cache.
test_seatprojects_live_seat_wins_and_warns() {
  local out rc err
  printf 'meta:engine %%9 manager:meta\n' > "$TMP_DIR/panes"
  out=$(TMUX_PANE=%9 FLEET_LIVE_PANES="$TMP_DIR/panes" FLEET_PANE=app:writer bash "$HELPER" --file "$TABLE" 2>"$TMP_DIR/err"); rc=$?
  err=$(cat "$TMP_DIR/err")
  assert_eq "0" "$rc" "live seat read"
  assert_eq "Product: Orchestration	primary" "$out" "rows of the live seat, not the cached one"
  assert_contains "FLEET_PANE 'app:writer'" "$err" "stderr warns that the cached FLEET_PANE differs"
  assert_contains "stale" "$err" "the warning says the cache is stale"
}

test_seatprojects_falls_back_to_fleet_pane_when_live_unreadable() {
  local out rc
  out=$(TMUX_PANE=%9 FLEET_LIVE_PANES="$TMP_DIR/no-such-panes" FLEET_PANE=app:writer bash "$HELPER" --file "$TABLE" 2>"$TMP_DIR/err"); rc=$?
  assert_eq "0" "$rc" "cache used when tmux cannot be read"
  assert_eq "Product: Writer	primary
Product: Editor	primary" "$out" "rows of FLEET_PANE"
}

# F5: CRLF rows lose their CR; an uncommented header row is not data.
test_seatprojects_crlf_rows_are_stripped() {
  local out rc
  printf 'meta:engine\tProduct: Orchestration\tprimary\r\n' > "$TMP_DIR/crlf.tsv"
  out=$(FLEET_PANE=meta:engine bash "$HELPER" --file "$TMP_DIR/crlf.tsv" 2>/dev/null); rc=$?
  assert_eq "0" "$rc" "CRLF table read"
  assert_eq "Product: Orchestration	primary" "$out" "no carriage return in the role"
  assert_eq "0" "$(printf '%s' "$out" | tr -cd '\r' | wc -c | tr -d ' ')" "no CR byte in the output"
}

test_seatprojects_uncommented_header_only_is_unread() {
  local rc
  printf 'seat\tlinear_project\trole\n' > "$TMP_DIR/hdr.tsv"
  FLEET_PANE=app:writer bash "$HELPER" --file "$TMP_DIR/hdr.tsv" >/dev/null 2>"$TMP_DIR/err"; rc=$?
  assert_eq "2" "$rc" "a header-only table exits 2, not 1"
}

run_discovered_tests
