#!/bin/bash
# tests/test-inheritance-sh.sh — Tests for inheritance.sh (print one loom's LOOM_INHERITANCE.md blocks).
# Run: bash ~/.claude/engine/scripts/tests/test-inheritance-sh.sh
#
# INHERITANCE_SH points the suite at a modified copy, which is how each assertion is watched going red.
# The fixture is SYNTHETIC: invented seats and sessions under /srv/demo, one block per heading shape
# that kit's shared file was measured to hold on 2026-10-30. Assertions are on owners and contents,
# never on the fixture's line numbers or length.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SCRIPTS="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$(cd "$SCRIPTS/.." && pwd)"
INH="${INHERITANCE_SH:-$SCRIPTS/inheritance.sh}"
LOG_SH="$SCRIPTS/log.sh"
FIX="$SCRIPTS/tests/fixtures/loom-inheritance/LOOM_INHERITANCE.md"
TPL="$ENGINE/skills/loom/assets/TEMPLATE_LOOM_INHERITANCE.md"
SKILL="$ENGINE/skills/loom/SKILL.md"
DEHY="$ENGINE/skills/dehydrate/SKILL.md"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# run <outfile> <args...> — echoes the exit code; stdout to <outfile>, stderr to <outfile>.err
run() {
  local out="$1"; shift
  bash "$INH" "$@" >"$out" 2>"$out.err"
  echo $?
}

# show <args...> — the raw rows only (no markers, no footers), for content assertions
show() { bash "$INH" show "$@" --raw --file "$FIX" 2>/dev/null; }

test_fixture_is_synthetic() {
  assert_eq "" "$(grep -n -e '/Users/' -e '@' "$FIX")" "the fixture names no local path and no address"
}

test_ownerless_first_block_and_its_ownerless_deltas() {
  # Cases 1 and 2: the first # block names its session only in its body; # ⏩ DELTA / # ⛔ CORRECTION continue.
  local o; o=$(show 2026_01_01_ORIGIN_LOOM)
  assert_contains "origin row" "$o" "the first block, owned by the session its body names"
  assert_contains "origin delta row" "$o" "the ownerless DELTA after it"
  assert_not_contains "tree row" "$o" "not the next loom's block"
  o=$(show lane:planner)
  assert_contains "tree correction row" "$o" "an ownerless CORRECTION continues the block above it"
}

test_by_one_seat_for_another_session_the_session_owns() {
  # Case 3: "by mgr:north, for sessions/…TREE_LOOM" and "by mgr:west on behalf of …PITCH_LOOM".
  local o out="$TMP_DIR/by.out" rc
  o=$(show 2026_01_02_TREE_LOOM)
  assert_contains "tree row" "$o" "the session after 'for' owns the block"
  rc=$(run "$out" show mgr:north --file "$FIX")
  assert_eq "2" "$rc" "the writer named after 'by' owns nothing, and is named, so it is not exit 3"
  o=$(show 2026_01_03_PITCH_LOOM)
  assert_contains "pitch arrangement row" "$o" "an addendum naming a counterparty after 'with' stays with its writer"
  assert_contains "pitch row" "$(show app:scribe)" "a seat after 'now' is the loom's new name, even across windows (R2-S1)"
  assert_eq "" "$(show app:scribe | grep 'mgr:west' | grep -v '^#')" "and the writer after 'by' is still not linked"
}

test_foreign_addendum_inside_a_section_and_the_plain_heading_after_it() {
  # Case 4: old:trade's ## addendum sits inside meta:alpha's # section; the plain ## after it is alpha's.
  local o out="$TMP_DIR/tr.out"
  o=$(show old:trade)
  assert_contains "trade block row" "$o" "the trade loom's block"
  assert_contains "trade addendum row" "$o" "and its addendum from inside alpha's section"
  assert_not_contains "alpha notes row" "$o" "the plain ## heading after the addendum is not the trade loom's"
  o=$(show meta:alpha)
  assert_contains "alpha notes row" "$o" "it returns to the enclosing section's owner"
  assert_contains "alpha row two, after three fences" "$o" "the section continues past its fences"
  assert_not_contains "trade addendum row" "$o" "and alpha does not get the trade addendum"
  run "$out" show old:trade --file "$FIX" >/dev/null
  assert_contains "==> note:" "$(cat "$out")" "show says a plain heading closed the delta into another owner"
  local rc; rc=$(run "$out" show new:trade --file "$FIX")
  assert_eq "2" "$rc" "a bare arrow in a heading that never says rename links nothing (R2-M1)"
}

test_deeper_delta_and_renamed_manager() {
  # Cases 5, 6, 7 and M1/M2: mgr:old → mgr:new deltas at ### and ##, a scheme block naming mgr:* as parent.
  local a b
  a=$(show mgr:new --latest); b=$(show mgr:old --latest)
  assert_eq "$a" "$b" "the renamed seat and its old name reach the same rows"
  assert_contains "mgr block row" "$a" "its block"
  assert_contains "mgr addendum row" "$a" "its ### addendum inside another loom's section"
  assert_contains "mgr addendum 3 row" "$a" "its addendum whose heading names no session and whose body does"
  assert_contains "mgr addendum 7 row" "$a" "its addendum written under the new name, 'formerly' the old"
  assert_not_contains "scheme row" "$a" "not the scheme loom whose heading names mgr:* as its parent (M1)"
  assert_not_contains "scheme addendum row" "$a" "nor the scheme addendum that names mgr:new as parent before its own seat"
  a=$(show pkg:scheme)
  assert_contains "scheme row" "$a" "the scheme loom's block"
  assert_contains "scheme addendum row" "$a" "and its own addendum"
  assert_not_contains "mgr addendum 7 row" "$a" "and not the manager's addendum 7 (M2)"
}

test_renamed_seat_both_names_one_session() {
  # Case 6: old:ops in an old block, new:ops (formerly old:ops) later, one session.
  local a b
  a=$(show old:ops); b=$(show new:ops)
  assert_eq "$a" "$b" "both names print the same rows"
  assert_contains "ci old row" "$a" "the old block"
  assert_contains "ci new row" "$a" "the new block"
  assert_not_contains "ci old row" "$(show new:ops --latest)" "--latest is the newer block only"
}

test_seat_only_owner_found_by_its_session_dir() {
  # Case 8 / M3: pkg:merge's heading names no session; its body does.
  local out="$TMP_DIR/mg.out" rc
  rc=$(run "$out" show /srv/demo/sessions/2026_01_10_MERGE_LOOM --file "$FIX")
  assert_eq "0" "$rc" "the session dir finds rows filed under the bare seat"
  assert_contains "merge row" "$(cat "$out")" "with its row"
  assert_eq "$(show pkg:merge)" "$(show 2026_01_10_MERGE_LOOM)" "seat and session print the same"
}

test_exit_3_only_when_the_file_never_names_the_subject() {
  local out="$TMP_DIR/x3.out" rc
  rc=$(run "$out" show /srv/demo/sessions/2026_01_13_FRESH_LOOM --file "$FIX")
  assert_eq "3" "$rc" "a fresh session dir the file never names exits 3"
  assert_contains "never names it" "$(cat "$out.err")" "and says so"
  rc=$(run "$out" show lane:stats --file "$FIX")
  assert_eq "2" "$rc" "a seat named only as a relation exits 2, not 3"
  assert_contains "names it at :" "$(cat "$out.err")" "naming the lines that mention it"
}

test_fences() {
  # Case 9 / M4: headings in ```, ```` (holding ```), and ~~~ fences are text; an unclosed fence is a fault.
  local out="$TMP_DIR/fe.out" rc f="$TMP_DIR/unclosed.md"
  for s in ghost:one ghost:two ghost:three; do
    rc=$(run "$out" show "$s" --file "$FIX")
    assert_eq "2" "$rc" "a heading inside a fence opens nothing ($s)"
  done
  printf '%s\n' \
    "# Inheritance — owner \`/srv/demo/sessions/2026_02_01_FOO\` (seat \`a:foo\`)" \
    "*   foo row" "    \`\`\`bash" "    echo never closed" \
    "# Inheritance — owner \`/srv/demo/sessions/2026_02_01_BAR\` (seat \`b:bar\`)" "*   bar row" >"$f"
  rc=$(run "$out" show b:bar --file "$f")
  assert_eq "2" "$rc" "a fence open at the end of the file is an instrument fault, not exit 3"
  assert_contains "unclosed.md:3:" "$(cat "$out.err")" "naming the line that opened it"
  rc=$(run "$out" show a:foo --file "$f")
  assert_eq "2" "$rc" "and the loom before it gets the fault too, not BAR's rows"
  rc=$(run "$out" list --file "$f")
  assert_eq "2" "$rc" "list faults as well"
}

test_register_headings_never_open_a_chunk() {
  # Case 11 / S1: "## Seat handovers open: lane:stats …, mgr:dom …" is a register of the director's block.
  local o out="$TMP_DIR/s1.out"
  o=$(show lane:dir --latest)
  assert_contains "dir handover row" "$o" "the register stays in its block"
  assert_contains "dir standing row" "$o" "and the block is not split around it"
  run "$out" show lane:dir --latest --file "$FIX" >/dev/null
  assert_eq "1" "$(grep -c '^==> LOOM_INHERITANCE.md:' "$out")" "one run of lines, no '(continued)'"
}

test_a_heading_naming_a_session_opens_a_chunk() {
  # Case 11 / S2: "## 2026_01_08_STORE_TAKEOVER (lane:store) — handed over …" uses no cue word.
  local o
  o=$(show lane:store)
  assert_contains "store row" "$o" "the store loom's block"
  assert_contains "store thread row" "$o" "with its ### register"
  assert_not_contains "store row" "$(show lane:dir)" "and the director does not get it"
}

test_named_elsewhere_footer() {
  # Case 11 / S3: lane:paint's newest state is a bullet inside the runner loom's block.
  local out="$TMP_DIR/s3.out"
  run "$out" show lane:paint --file "$FIX" >/dev/null
  assert_not_contains "Addendum 15:21 (lane:paint" "$(grep -v '^  ' "$out")" "the bullet is not one of paint's chunks"
  assert_contains "==> named elsewhere:" "$(cat "$out")" "show ends with a named-elsewhere footer"
  assert_contains "[2026_01_10_RUNNER_LOOM] *   **Addendum 15:21 (lane:paint" "$(cat "$out")" "that lists the bullet and whose chunk holds it"
  assert_not_contains "named elsewhere" "$(bash "$INH" show lane:paint --raw --file "$FIX")" "--raw drops it"
}

test_newest_pairing_wins() {
  # S5: lane:dir is named with OLDDIR_LOOM in two headings and DIR_LOOM in one; --latest is the newer loom.
  local o
  o=$(show lane:dir --latest)
  assert_contains "dir row" "$o" "the newest block"
  assert_not_contains "olddir" "$o" "not the older loom's block or delta"
  assert_contains "olddir row" "$(show lane:dir)" "the full show still has the older loom's history"
}

test_delta_registers_at_level_2_stay_in_the_delta() {
  # S6: meta:alpha's ## delta inside the runner section writes its register at ##.
  local o
  o=$(show meta:alpha --latest)
  assert_contains "alpha delta thread row" "$o" "the ## 🧵 register after a ## delta stays with it"
  assert_not_contains "alpha delta thread row" "$(show lane:world)" "and does not go to the enclosing section"
}

test_an_arrow_is_a_rename_only_where_the_heading_says_so() {
  # R2-M1: a register "Asks relayed: A → B" between two managers merged their looms, and --latest
  # printed the other manager's newer block with exit 0.
  local f="$TMP_DIR/arrow.md" out="$TMP_DIR/ar.out" rc
  printf '%s\n' \
    "# Inheritance — owner \`/srv/demo/sessions/2026_03_01_DOMMGR\` (seat \`mgr:dom\`), written 2026-03-01 10:00" \
    "## 🧵 Threads" "*   dommgr row OLD" \
    "# Inheritance — owner \`/srv/demo/sessions/2026_03_01_DIRECTOR\` (seat \`mgr:dir\`), written 2026-03-01 10:05" \
    "## 🧵 Threads" "*   director row" \
    "## Asks relayed: mgr:dom → mgr:dir (all forwarded)" "*   ask x" \
    "# Inheritance — owner \`/srv/demo/sessions/2026_03_01_DOMMGR\` (seat \`mgr:dom\`), written 2026-03-01 11:00" \
    "## 🧵 Threads" "*   dommgr row NEW" \
    "# Inheritance — owner \`/srv/demo/sessions/2026_03_02_STUDIO\` (seat \`lane:studio\`), written 2026-03-02 09:00" \
    "*   studio row OLD" \
    "# Inheritance — owner \`/srv/demo/sessions/2026_03_02_STUDIO\` (seat \`app:writer\`, formerly \`lane:studio\`), written 2026-03-02 12:00" \
    "*   writer row NEW" \
    "## [2026-03-03 09:00:00] core:paint → core:brush hand-over (2026_03_03_PAINT_LOOM), written for the fleet rename" \
    "*   paint row" \
    "## [2026-03-03 10:00:00] core:brush addendum: one more row" "*   brush row" >"$f"
  rc=$(run "$out" show mgr:dir --latest --file "$f")
  assert_eq "0" "$rc" "the director's --latest exits 0"
  assert_contains "director row" "$(cat "$out")" "with the director's own block"
  assert_not_contains "dommgr row" "$(cat "$out")" "and not the domain manager's newer block"
  assert_not_contains "DIRECTOR" "$(bash "$INH" show mgr:dom --raw --file "$f")" "the domain manager does not get the director's rows"
  run "$out" show app:writer --latest --file "$f" >/dev/null
  assert_contains "writer row NEW" "$(cat "$out")" "'formerly' links two seats that share no part"
  assert_not_contains "studio row OLD" "$(cat "$out")" "and --latest is the newer block"
  assert_contains "studio row OLD" "$(bash "$INH" show lane:studio --raw --file "$f")" "the old name reaches the loom's history"
  assert_contains "brush row" "$(bash "$INH" show core:paint --raw --file "$f")" "an arrow in a heading that says rename is a rename"
}

test_latest_stays_in_the_subjects_session_chain() {
  # R2-M1: a loom spanning several sessions keeps --latest to the subject's own, or exits 2.
  local f="$TMP_DIR/chain.md" out="$TMP_DIR/ch.out" rc
  printf '%s\n' \
    "# Inheritance — owner \`/srv/demo/sessions/2026_04_01_ONE\` (seat \`lane:one\`), written 2026-04-01" "*   one row" \
    "# Inheritance — owner \`/srv/demo/sessions/2026_04_02_TWO\` (seat \`lane:two\`, formerly \`lane:one\`)" "*   two row" >"$f"
  rc=$(run "$out" show lane:one --latest --file "$f")
  assert_eq "0" "$rc" "the old seat's --latest exits 0"
  assert_contains "one row" "$(cat "$out")" "and stays in the session the old seat headed"
  assert_not_contains "two row" "$(cat "$out")" "rather than jumping to the renamed seat's session"
  assert_contains "newer block" "$(cat "$out.err")" "and says a newer block exists elsewhere in the loom"
  rc=$(run "$out" show 2026_04_02_TWO --latest --file "$f")
  assert_contains "two row" "$(cat "$out")" "a session subject keeps to that session"
  printf '%s\n' "## [2026-04-03 09:00:00] lane:three hand-over delta" "*   three row" \
    "# Inheritance — owner \`/srv/demo/sessions/2026_04_03_FOUR\` (seat \`lane:four\`), formerly lane:three" "*   four row" >>"$f"
  printf '%s\n' "# Inheritance — owner \`/srv/demo/sessions/2026_04_05_FIVE\` (seat \`lane:three\`, formerly \`lane:two\`)" "*   five row" >>"$f"
  rc=$(run "$out" show lane:three --latest --file "$f")
  assert_eq "0" "$rc" "a seat that headed one session of a multi-session loom is still answered"
  rc=$(run "$out" show 2026_04_01_ONE --latest --file "$f")
  assert_contains "one row" "$(cat "$out")" "a session subject is answered from that session"
  printf '%s\n' \
    "# Inheritance — owner \`/srv/demo/sessions/2026_04_06_SIX\` (seat \`lane:six\`, formerly \`lane:gone\`)" "*   six row" \
    "# Inheritance — owner \`/srv/demo/sessions/2026_04_07_SEVEN\` (seat \`lane:seven\`, formerly \`lane:gone\`)" "*   seven row" >>"$f"
  rc=$(run "$out" show lane:gone --latest --file "$f")
  assert_eq "2" "$rc" "a seat reaching several sessions only through renames cannot choose, so it exits 2"
  assert_contains "only through renames" "$(cat "$out.err")" "and says so"
}

test_markers_name_session_and_seat() {
  # R2-N1
  local out="$TMP_DIR/n1.out"
  run "$out" show mgr:new --file "$FIX" >/dev/null
  assert_contains "· session=2026_01_05_MGR_LOOM seat=mgr:old" "$(cat "$out")" "a marker names both the chunk's session and its seat"
}

test_list_reports_figures_that_can_be_nonzero() {
  # S4: no "attributed N of N"; figures that a bad shape moves.
  local out="$TMP_DIR/ls.out" rc
  rc=$(run "$out" list --file "$FIX")
  assert_eq "0" "$rc" "list exits 0"
  assert_not_contains "attributed" "$(cat "$out")" "the figure that could not fail is gone"
  assert_contains "owners: 14" "$(cat "$out")" "fourteen owners"
  assert_contains "owners over more than one session: 1 (2026_01_07_DIR_LOOM)" "$(cat "$out")" "the seat that ran two looms"
  assert_contains "deltas closed into another owner by a plain heading: 1" "$(cat "$out")" "the trade addendum closed by a plain heading"
  assert_contains "owners with no session: 0" "$(cat "$out")" "every owner resolved to a session"
  assert_contains "owner 2026_01_05_MGR_LOOM  sessions=2026_01_05_MGR_LOOM  seats=mgr:new,mgr:old" "$(cat "$out")" "a renamed seat lists both names"
}

test_new_format_block_and_delta_appended_with_engine_log() {
  # Case 10.
  local d="$TMP_DIR/sessions" f out="$TMP_DIR/nf.out" rc
  mkdir -p "$d/2026_11_01_FOO" "$d/2026_11_01_BAR"
  f="$d/LOOM_INHERITANCE.md"
  printf '%s\n' \
    "# Inheritance — owner \`$d/2026_11_01_FOO\` (seat \`a:foo\`), written 2026-11-01 10:00" \
    "## 🧵 Threads" "| foo row |" \
    "## 📨 Seat handovers (all with b:bar)" "| sent to b:bar |" \
    "# Inheritance — owner \`$d/2026_11_01_BAR\` (seat \`b:bar\`), written 2026-11-01 10:05" \
    "## 🧵 Threads" "| bar row |" >"$f"
  bash "$LOG_SH" "$f" >/dev/null <<EOF
## Inheritance delta — owner \`$d/2026_11_01_FOO\` (seat \`a:foo\`)
### 🧵 Threads
*   foo delta row
EOF
  rc=$(run "$out" show "$d/2026_11_01_FOO")
  assert_eq "0" "$rc" "the file is found beside the session dir with no --file"
  assert_contains "foo row" "$(cat "$out")" "the block"
  assert_contains "sent to b:bar" "$(cat "$out")" "a register naming another seat stays in the block"
  assert_contains "foo delta row" "$(cat "$out")" "the delta appended by engine log, with its ### register"
  assert_not_contains "bar row" "$(cat "$out")" "not the other loom's block"
  run "$out" show b:bar --file "$f" >/dev/null
  assert_not_contains "foo delta row" "$(cat "$out")" "the delta after bar's block is not bar's"
  rc=$(run "$out" show a:foo --latest --file "$f")
  assert_contains "foo row" "$(cat "$out")" "--latest keeps the newest block"
  assert_contains "foo delta row" "$(cat "$out")" "and the delta after it"
}

test_show_marks_each_chunk() {
  local out="$TMP_DIR/mk.out" rc
  rc=$(run "$out" show mgr:new --file "$FIX")
  assert_eq "0" "$rc" "show exits 0"
  assert_contains "==> LOOM_INHERITANCE.md:" "$(cat "$out")" "a marker names the source lines"
  assert_contains " delta · " "$(cat "$out")" "and says delta for a delta"
  assert_contains "seats=mgr:new,mgr:old" "$(cat "$out")" "the closing line names every seat the loom was linked to"
}

test_faults() {
  local out="$TMP_DIR/fx.out" rc
  rc=$(run "$out" show meta:alpha --file "$TMP_DIR/missing.md")
  assert_eq "2" "$rc" "a missing file exits 2"
  rc=$(run "$out" show)
  assert_eq "2" "$rc" "show with no subject exits 2"
  rc=$(run "$out" frobnicate)
  assert_eq "2" "$rc" "an unknown verb exits 2"
}

test_template_and_skills_send_a_successor_to_the_command() {
  assert_contains "engine inheritance show" "$(cat "$TPL")" "the template names the read command"
  assert_contains "Inheritance delta — owner" "$(cat "$TPL")" "the template gives the delta heading the command finds"
  assert_not_contains "attributed" "$(cat "$TPL")" "the template no longer cites the vacuous figure"
  assert_contains "engine inheritance show" "$(cat "$SKILL")" "the loom skill's inheritance step runs it"
  assert_contains "the predecessor's seat" "$(cat "$SKILL")" "Setup passes the predecessor's key, not its own new session dir"
  assert_contains "engine inheritance show" "$(cat "$DEHY")" "the dehydrate skill's inheritance step runs it"
}

run_discovered_tests
