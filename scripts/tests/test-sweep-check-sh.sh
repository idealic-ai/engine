#!/bin/bash
# tests/test-sweep-check-sh.sh — Tests for sweep-check.sh (decisions no register block was written after).
# Run: bash ~/.claude/engine/scripts/tests/run-all.sh test-sweep-check-sh.sh
#      bash ~/.claude/engine/scripts/tests/test-sweep-check-sh.sh
#
# The check is TEMPORAL: a decision is UNROWED when no register block was written after it, FOLLOWED
# otherwise. It compares no content. The tests pin that claim from both sides: ordering decides the
# verdict, and a row that names the decision but sits BEFORE it does not clear it.
#
# Two kinds of input:
#   SYNTHETIC   small logs written here, one behaviour each.
#   REAL        logs this suite did not write, each SKIPped when absent so a fresh machine reports
#               "no corpus" rather than a false green.
#                 FINISHED_LOG  a finished weave's LOOM_LOG.md (no longer written to): 61 decision
#                               headings, register blocks last written at L3021, none after.
#                 LIVE_LOG      the weave this check was built in; still written to, so floors only.
#
# SWEEP_CHECK_SH points the suite at a modified copy, which is how each assertion is watched going
# red before it is trusted. Mutants run against this suite (see the Build Report for results):
#   ordering inverted (register write BEFORE the decision clears it) -> the ordering tests go red
#   ordering ignored (any register write anywhere clears it)         -> the ordering tests go red
#   a content arm added (a row naming the decision clears it)         -> the no-content test goes red
#   fence toggled by an inline span again                             -> the fence tests go red
#   decision pattern anchored on the emoji                            -> the shape and real-log tests go red

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SWEEP_CHECK="${SWEEP_CHECK_SH:-$HOME/.claude/engine/scripts/sweep-check.sh}"
FINISHED_LOG="$HOME/Projects/finch/sessions/2026_09_09_IDEAS_EXAMPLE/LOOM_LOG.md"
LIVE_LOG="$HOME/Library/CloudStorage/GoogleDrive-yarik@finchclaims.com/Shared drives/finch-os/yarik/finch/sessions/2026_10_14_LAND_TREE_BRANCHES/LOOM_LOG.md"

TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Runs the check, writes stdout to $1, returns its exit status on stdout.
run_check() {
  local out="$1"; shift
  bash "$SWEEP_CHECK" "$@" >"$out" 2>"$out.err"
  echo $?
}

unrowed_count() { grep -c '^UNROWED ' "$1" || true; }

# Written with printf so the fixtures hold the same bytes `engine log` produces.
write_log() {
  local path="$1"; shift
  printf '%s\n' "$@" >"$path"
}

test_sweep_check_script_exists() {
  assert_file_exists "$SWEEP_CHECK" "sweep-check.sh is present"
}

# The ordering is the whole key. Same two lines, swapped: after clears, before does not.
test_a_register_write_after_the_decision_clears_it_and_before_does_not() {
  local log="$TMP_DIR/order.md" out="$TMP_DIR/order.out" rc
  write_log "$log" \
    '## 💡 Decision — the xylophone calibration is moved' '' \
    '## 🧵 Ledger (live)' '| THR-1 | an unrelated thread |'
  rc=$(run_check "$out" "$log" --all)
  assert_eq "0" "$rc" "a Ledger written after the decision leaves nothing certainly unrowed"
  assert_contains "FOLLOWED" "$(cat "$out")" "and the decision is reported FOLLOWED, not ROWED"
  assert_not_contains "UNROWED  L" "$(cat "$out")" "no decision line is called unrowed"
  write_log "$log" \
    '## 🧵 Ledger (live)' '| THR-1 | an unrelated thread |' '' \
    '## 💡 Decision — the xylophone calibration is moved'
  rc=$(run_check "$out" "$log")
  assert_eq "3" "$rc" "the same Ledger written BEFORE the decision does not clear it"
  assert_contains "xylophone" "$(grep '^UNROWED' "$out")" "the unrowed heading is named"
}

# No content arm: a row that names the decision exactly, written before it, still leaves it unrowed;
# an unrelated block written after it clears it. Either reintroduces a content comparison if it flips.
test_no_content_is_compared() {
  local log="$TMP_DIR/content.md" out="$TMP_DIR/content.out" rc
  write_log "$log" \
    '## 🧵 Ledger (live)' '| QZV-77 | the widget thread, goes ahead as scoped |' '' \
    '## 💡 Decision — QZV-77 goes ahead as scoped'
  rc=$(run_check "$out" "$log")
  assert_eq "3" "$rc" "a row naming the decision exactly, written before it, does not clear it"
  write_log "$log" \
    '## 💡 Decision — QZV-77 goes ahead as scoped' '' \
    '## 📚 Docs owed' '| nothing about the widget at all |'
  rc=$(run_check "$out" "$log")
  assert_eq "0" "$rc" "an unrelated block written after it leaves nothing certainly unrowed"
}

# Each of the five register blocks counts, with and without the variation selector; a heading that
# only mentions a register, or a register glyph in a body line, does not.
test_each_register_block_counts_and_mentions_do_not() {
  local log="$TMP_DIR/regs.md" out="$TMP_DIR/regs.out" rc head
  for head in '🧵 Ledger' '🗳️ Asks' '🗳 Asks' '🗳️ Boards' '🗳 Boards' '📚 Docs owed' '🔓 Open claims' '🅿️ Parked' '🅿 Parked'; do
    write_log "$log" '## 💡 Decision — a plain decision' '' "## $head — rewritten"
    rc=$(run_check "$out" "$log")
    assert_eq "0" "$rc" "a '$head' heading written after the decision counts"
  done
  write_log "$log" '## 💡 Decision — a plain decision' '' '## 🔧 Progress — the Ledger was updated' '🧵 Ledger in a body line'
  rc=$(run_check "$out" "$log")
  assert_eq "3" "$rc" "a heading that mentions a register, and a glyph in prose, are not register writes"
}

# An event heading named after the asks-read trigger is not a write of the Asks register (LOOMASK
# round 2, S1). The register's name ends at a separator or the end of the heading; `Asks read`
# continues it, so a decision followed only by that event is UNROWED. The critic's probe/read.md shape.
test_an_asks_read_event_heading_is_not_the_register() {
  local log="$TMP_DIR/asksread.md" out="$TMP_DIR/asksread.out" rc head
  write_log "$log" '## 🧵 Ledger' '' '## 🗳️ Asks' '* seat/a1 — open — to manager:x since gate 2' '' \
    '## 📚 Docs owed' '' '## 🔓 Open claims' '' '## 🅿️ Parked' '' '## 💡 Decision — d1' '' \
    '## [2026-10-30 03:00:00] 🗳️ Asks read — gate 3: seat/a1 still open'
  rc=$(run_check "$out" "$log")
  assert_eq "3" "$rc" "a '🗳️ Asks read — …' event heading after the decision is not a register write"
  for head in '🗳️ Asks' '🗳️ Asks (live)' '🗳️ Asks: none open' '[2026-10-30 03:00:00] 🗳️ Asks — rewritten' '🗳️ Boards at 22:2x' '🗳️ Boards: none'; do
    write_log "$log" '## 💡 Decision — a plain decision' '' "## $head"
    rc=$(run_check "$out" "$log")
    assert_eq "0" "$rc" "control: '$head' still counts as the register"
  done
}

# Both heading shapes are decisions. The anchored pattern sees one of these two.
test_stamped_and_unstamped_headings_are_both_found() {
  local log="$TMP_DIR/shapes.md" out="$TMP_DIR/shapes.out" anchored
  write_log "$log" \
    '## 💡 Decision — alpha plain' '' \
    '## [2026-10-21 14:09:47] 💡 Decision — beta stamped' '' \
    '## [IDE-155] 💡 Decision — gamma bracketed lane'
  run_check "$out" "$log" >/dev/null
  assert_contains "decision headings: 3 (stamped 1, unstamped 2" "$(cat "$out")" "all three shapes are counted"
  anchored=$(grep -c '^## 💡 Decision' "$log")
  assert_eq "1" "$anchored" "control: the anchored pattern sees only 1 of the 3"
}

# The widened pattern, proved against shapes the old one could not see, plus the ones it must refuse.
test_widened_decision_shapes_and_the_refusals() {
  local log="$TMP_DIR/wide.md" out="$TMP_DIR/wide.out"
  write_log "$log" \
    '## [2026-10-18 17:29:34] Decision - no glyph, plain hyphen' '' \
    '## [2026-10-20 13:16:01] ⭐ Decision resolved — a different glyph' '' \
    '## [2026-10-16 03:21:00] 💡 Decisions + landings — operator round' '' \
    '## 💡 FOUR DECISIONS — mid-heading, not counted' '' \
    '## 🔧 Progress — both decisions resolve sharper' '' \
    '## 🔧 Progress — a decision came up'
  run_check "$out" "$log" >/dev/null
  assert_contains "decision headings: 3 (" "$(cat "$out")" "the three widened shapes are counted, the mid-heading ones are not"
  assert_contains "3 other headings mention 'decision' mid-heading" "$(cat "$out")" "the uncounted mentions are reported, not silent"
  assert_contains "Decisions + landings" "$(cat "$out")" "a plural heading prints whole, not mangled"
  assert_not_contains " s + landings" "$(cat "$out")" "and without the stripped prefix"
}

# A fence line that closes on its own line (an inline span) must not swallow the rest of the log.
test_inline_fence_span_does_not_swallow_the_log() {
  local log="$TMP_DIR/inline.md" out="$TMP_DIR/inline.out" rc
  write_log "$log" \
    '## 🧵 Ledger' '| QZV-77 | w |' '' \
    '## 🔧 Progress' '```code``` inline mention' '' \
    '## [2026-10-21 14:09:47] 💡 Decision — xylophone MARMOT-9 unrowed'
  rc=$(run_check "$out" "$log")
  assert_eq "3" "$rc" "a decision after an inline triple-backtick span is still read"
  assert_contains "MARMOT-9" "$(grep '^UNROWED' "$out")" "and named"
}

# A real fenced block in the middle: the heading inside is documentation, both neighbours count.
test_fenced_block_mid_log() {
  local log="$TMP_DIR/mid.md" out="$TMP_DIR/mid.out" rc
  write_log "$log" \
    '## 💡 Decision — before the block FIRSTONE' '' \
    '```' '## 💡 Decision — an example inside a fence NOPE-1' '## 🧵 Ledger — also an example' '```' '' \
    '## 💡 Decision — after the block SECONDONE'
  rc=$(run_check "$out" "$log")
  assert_eq "3" "$rc" "the decisions either side of a fenced block are both read"
  assert_contains "FIRSTONE" "$(grep '^UNROWED' "$out")" "the one before the block is named"
  assert_contains "SECONDONE" "$(grep '^UNROWED' "$out")" "the one after the block is named"
  assert_not_contains "NOPE-1" "$(cat "$out")" "the fenced one is not reported as a decision"
  assert_contains "fenced 1 excluded" "$(cat "$out")" "and the exclusion is counted"
  assert_contains "2 fenced lines" "$(cat "$out")" "with the number of lines inside fences shown"
}

# A fence never closed would read as '0 decisions, exit 0'. It is an instrument fault.
test_unclosed_fence_is_an_instrument_fault() {
  local log="$TMP_DIR/open.md" out="$TMP_DIR/open.out" rc
  write_log "$log" \
    '## 💡 Decision — read before the fence OPENONE' '' \
    '```' '## 💡 Decision — swallowed by an unclosed fence'
  rc=$(run_check "$out" "$log")
  assert_eq "2" "$rc" "an unclosed fence exits 2, not 0"
  assert_contains "never closed" "$(cat "$out.err")" "and says why on stderr"
}

# No register block at all must not read as clean, and a log with no decisions must say so.
test_missing_registers_and_empty_logs_are_not_silently_clean() {
  local log="$TMP_DIR/bare.md" out="$TMP_DIR/bare.out" rc
  write_log "$log" '## 💡 Decision — the only decision'
  rc=$(run_check "$out" "$log")
  assert_eq "3" "$rc" "a decision with no register block anywhere is unrowed"
  assert_contains "Ledger none" "$(cat "$out")" "absent registers are named as absent"
  assert_contains "no register block in the log" "$(cat "$out")" "and the line says there is no block at all"
  write_log "$log" '## 🔧 Progress — nothing decided'
  rc=$(run_check "$out" "$log")
  assert_eq "0" "$rc" "no decisions exits 0"
  assert_contains "0 decision headings seen" "$(cat "$out")" "and says what it recognised"
}

test_the_weaker_claim_is_in_the_output() {
  local log="$TMP_DIR/claim.md" out="$TMP_DIR/claim.out"
  write_log "$log" '## 💡 Decision — x' '' '## 🧵 Ledger'
  run_check "$out" "$log" >/dev/null
  assert_contains "does NOT show the decision was rowed" "$(cat "$out")" "the output states what FOLLOWED does not mean"
  assert_contains "not shown to be rowed" "$(cat "$out")" "and the summary line repeats it"
}

test_unreadable_log_exits_two() {
  local out="$TMP_DIR/missing.out" rc
  rc=$(run_check "$out" "$TMP_DIR/no-such-log.md")
  assert_eq "2" "$rc" "an unreadable log exits 2, not 0"
}

test_check_never_writes_the_log() {
  local log="$TMP_DIR/ro.md" out="$TMP_DIR/ro.out" before after
  write_log "$log" '## 💡 Decision — read only please'
  before=$(shasum "$log")
  run_check "$out" "$log" >/dev/null
  after=$(shasum "$log")
  assert_eq "$before" "$after" "the log is byte-identical after a run"
}

# REAL: a finished weave. Figures computed here by a differently-shaped route (grep + awk), then
# compared to the script's.
test_real_finished_log_agrees_with_an_independent_computation() {
  if [ ! -f "$FINISHED_LOG" ]; then
    skip "real finished log is read" "no corpus at $FINISHED_LOG"
    return 0
  fi
  local out="$TMP_DIR/finished.out" rc found anchored last expect u f
  rc=$(run_check "$out" "$FINISHED_LOG" --all)
  found=$(sed -n 's/^decision headings: \([0-9]*\) .*/\1/p' "$out")
  anchored=$(grep -c '^## 💡 Decision' "$FINISHED_LOG")
  assert_eq "$(grep -cE '^## (\[[^]]*\] )*[^A-Za-z0-9]*[Dd]ecision' "$FINISHED_LOG")" "$found" "decision count equals the differently-shaped grep"
  assert_gt "$found" "$((anchored * 5))" "and is more than 5x what the anchored pattern sees ($anchored)"
  last=$(grep -nE '^## (\[[^]]*\] )*[^A-Za-z0-9]*(Ledger|Asks|Boards|Docs owed|Open claims|Parked)' "$FINISHED_LOG" | tail -1 | cut -d: -f1)
  expect=$(grep -nE '^## (\[[^]]*\] )*[^A-Za-z0-9]*[Dd]ecision' "$FINISHED_LOG" | awk -F: -v l="$last" '$1 > l' | wc -l | tr -d ' ')
  u=$(unrowed_count "$out"); f=$(grep -c '^FOLLOWED ' "$out" || true)
  assert_eq "$expect" "$u" "decisions after the last register write ($last) equal the script's UNROWED"
  assert_eq "$found" "$((u + f))" "every decision is reported either UNROWED or FOLLOWED"
  assert_eq "3" "$rc" "unrowed decisions exit 3"
}

# REAL: decisions a content match got wrong on this log. The five it called rowed with no row behind
# them are written after the last register write and must be UNROWED; the five it called rowed
# correctly are written before it and must stay FOLLOWED.
test_real_finished_log_known_decisions() {
  if [ ! -f "$FINISHED_LOG" ]; then
    skip "known decisions on the finished log" "no corpus at $FINISHED_LOG"
    return 0
  fi
  local out="$TMP_DIR/known.out" n
  run_check "$out" "$FINISHED_LOG" --all >/dev/null
  for n in 3057 3285 3341 3999 4106; do
    assert_contains "UNROWED  L$n " "$(cat "$out")" "L$n (no row could account for it) is UNROWED"
  done
  for n in 2874 2910 2939 2957 2980; do
    assert_contains "FOLLOWED L$n " "$(cat "$out")" "L$n (a later Ledger exists) stays FOLLOWED"
  done
}

# REAL + PLANT: append an invented decision to a COPY of a real log. Red; then a register write
# after it makes it FOLLOWED.
test_planted_decision_on_a_real_log_turns_it_red() {
  if [ ! -f "$FINISHED_LOG" ]; then
    skip "plant on a real log" "no corpus at $FINISHED_LOG"
    return 0
  fi
  local copy="$TMP_DIR/real-copy.md" base="$TMP_DIR/real-base.out" red="$TMP_DIR/real-red.out" green="$TMP_DIR/real-green.out"
  local nonce="ZQXJ$$K" b r
  cp "$FINISHED_LOG" "$copy"
  run_check "$base" "$copy" >/dev/null
  b=$(unrowed_count "$base")
  printf '\n## [2099-01-01 00:00:00] 💡 Decision — the %s subsystem is reorganised\n*   body\n' "$nonce" >>"$copy"
  r=$(run_check "$red" "$copy")
  assert_eq "3" "$r" "the plant makes the real log exit 3"
  assert_eq "$((b + 1))" "$(unrowed_count "$red")" "exactly one more UNROWED than the baseline"
  assert_contains "$nonce" "$(grep '^UNROWED' "$red")" "and it is the plant that is named"
  printf '\n## 🧵 Ledger — written after the plant\n| nothing about it |\n' >>"$copy"
  run_check "$green" "$copy" >/dev/null
  assert_not_contains "$nonce" "$(grep '^UNROWED' "$green")" "a register write after the plant clears it"
  assert_eq "0" "$(unrowed_count "$green")" "and, with a Ledger last, nothing on the log is certainly unrowed"
}

# REAL, LIVE: only floors. The log is append-only and being written to, so the count can only grow.
test_real_live_log_floor_and_the_anchor_trap() {
  if [ ! -f "$LIVE_LOG" ]; then
    skip "live log is read" "no corpus at $LIVE_LOG"
    return 0
  fi
  local snap="$TMP_DIR/live.md" out="$TMP_DIR/live.out" found anchored
  cp "$LIVE_LOG" "$snap"
  run_check "$out" "$snap" >/dev/null
  found=$(sed -n 's/^decision headings: \([0-9]*\) .*/\1/p' "$out")
  anchored=$(grep -c '^## 💡 Decision' "$snap")
  assert_gt "$found" "45" "at least the decisions measured on 2026-10-21 are found ($found)"
  assert_gt "$found" "$((anchored * 3))" "and well above the anchored pattern's reading ($anchored)"
}

run_discovered_tests
