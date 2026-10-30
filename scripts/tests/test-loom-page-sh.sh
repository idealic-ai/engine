#!/bin/bash
# tests/test-loom-page-sh.sh — Tests for loom-page.sh (a loom log's present state, rendered).
# Run: bash ~/.claude/engine/scripts/tests/run-all.sh test-loom-page-sh.sh
#      bash ~/.claude/engine/scripts/tests/test-loom-page-sh.sh
#
# The script's claim has two halves and each is pinned from both sides here:
#   PRESENT STATE   a rewritten-in-place register is read at its LATEST occurrence, and an
#                   append-only event is COUNTED, never rendered. Reading either the other way
#                   produces a confidently wrong page, so every one of these tests asserts both
#                   what must appear AND what must not.
#   NOTHING SWALLOWED  a heading the renderer could not read as a block is output. An under-reading
#                   that renders as silence is indistinguishable from a healthy page.
#
# Two kinds of input:
#   SYNTHETIC   small logs written here, one behaviour each. Each carries a distinctive marker
#               (XYLOPHONE, ZEBRAFISH, …) so an assertion can say which occurrence was rendered
#               rather than only that something was.
#   REAL        the live loom log this renderer was built against, SKIPped when absent so a fresh
#               machine reports "no corpus" rather than a false green.
#
# LOOM_PAGE_SH points the suite at a modified copy, which is how each assertion was watched going
# red before it was trusted. Mutants run against this suite (results in the Build Report):
#   `occ[-1]` -> `occ[0]`            (register read oldest-first)  -> the latest-occurrence tests red
#   the drift bucket folded into plain                             -> the drift tests red
#   the instrument anchored on the glyph (`rx.match` -> startswith)-> the stamped-heading + real-log tests red
#   the event arm made to render its latest block                  -> the events-are-counted tests red
#   the glyph-only key (name dropped from the instrument)          -> the trap tests red
#   the missing-register warning removed                           -> the NOT FOUND tests red

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

LOOM_PAGE="${LOOM_PAGE_SH:-$HOME/.claude/engine/scripts/loom-page.sh}"
LIVE_LOG="$HOME/Library/CloudStorage/GoogleDrive-yarik@finchclaims.com/Shared drives/finch-os/yarik/finch/sessions/2026_10_14_LAND_TREE_BRANCHES/LOOM_LOG.md"

TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Written with printf so the fixtures hold the same bytes `engine log` produces.
write_log() {
  local path="$1"; shift
  printf '%s\n' "$@" >"$path"
}

# Runs --text, writes stdout to $1, echoes the exit status. The status is read from the command
# itself, never through a pipeline, where `$?` would report the last stage instead.
run_text() {
  local out="$1"; shift
  bash "$LOOM_PAGE" "$@" --text >"$out" 2>"$out.err"
  echo $?
}

# The `=== <label>` present-state section only. The distinction matters: a heading the renderer
# refused as a register MUST still appear on the page, in the drift or other-glyph list — so
# "not rendered as a register" is a claim about this section, never about the whole output.
register_section() {
  sed -n "/^=== $2/,/^$/p" "$1"
}

run_html() {
  local out="$1" log="$2"; shift 2
  bash "$LOOM_PAGE" "$log" --out "$out" >"$out.path" 2>"$out.err"
  echo $?
}

# A full seven-register log, every heading STAMPED exactly as `engine log` writes it. The stamp is
# the point: an instrument anchored on the glyph sees none of these.
write_full_log() {
  local path="$1"
  write_log "$path" \
    '# LOOM LOG' '' \
    '## [2026-01-01 10:00:00] 🧵 Ledger — the FIRST ledger, XYLOPHONE' '' \
    '| threadId | status |' \
    '|---|---|' \
    '| THR-1 | XYLOPHONE |' '' \
    '## [2026-01-01 10:05:00] 💡 Decision — the first decision, AARDVARK' '' \
    '*   **Ruled**: AARDVARK' '' \
    '## [2026-01-01 10:10:00] 📡 Relay — the first relay, BADGER' '' \
    '## [2026-01-01 10:15:00] 💡 Decision — the second decision, CAPYBARA' '' \
    '## [2026-01-01 11:00:00] 🧵 Ledger — the LATEST ledger, ZEBRAFISH' '' \
    '| threadId | status |' \
    '|---|---|' \
    '| THR-1 | ZEBRAFISH |' '' \
    '*   **Tree**: ZEBRAFISH at `abc1234`' '' \
    '## [2026-01-01 11:05:00] 🗳️ Boards — BOARDMARK' '' \
    '## [2026-01-01 11:06:00] 📚 Docs owed — DOCSMARK' '' \
    '## [2026-01-01 11:07:00] ⚖️ Rules owed — RULESMARK' '' \
    '## [2026-01-01 11:08:00] 🔓 Open claims — CLAIMSMARK' '' \
    '## [2026-01-01 11:09:00] 🅿️ Parked — PARKEDMARK' '' \
    '## [2026-01-01 11:10:00] 🌊 Wave — WAVEMARK' ''
}

test_loom_page_script_exists() {
  assert_file_exists "$LOOM_PAGE" "loom-page.sh is present"
}

test_loom_page_usage_without_a_log() {
  local out="$TMP_DIR/usage.out" rc
  bash "$LOOM_PAGE" >"$out" 2>&1
  rc=$?
  assert_gt "$rc" "0" "a missing log file argument is a usage error"
}

test_loom_page_unreadable_log_is_an_instrument_fault() {
  local out="$TMP_DIR/nolog.out" rc
  rc=$(run_text "$out" "$TMP_DIR/does-not-exist.md")
  assert_eq "2" "$rc" "a log that cannot be read exits 2, an instrument fault"
}

# ---------------------------------------------------------------------------------------------
# The two kinds of block. This is the distinction the whole design rests on.
# ---------------------------------------------------------------------------------------------

# A rewritten register has ONE current value: the latest. Rendering the first, or rendering every
# occurrence, reports a weave's history as its present state.
test_a_rewritten_register_renders_its_latest_occurrence_and_not_an_earlier_one() {
  local log="$TMP_DIR/two-ledgers.md" out="$TMP_DIR/two-ledgers.out" rc
  write_full_log "$log"
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  assert_contains "ZEBRAFISH" "$txt" "the LATEST ledger's body is rendered"
  assert_not_contains "XYLOPHONE" "$txt" "the FIRST ledger's body is NOT rendered — latest, not all"
  assert_contains "latest of 2" "$txt" "and the page says how many occurrences it chose from"
}

# An append-only event has no current value. A 'latest' reading would show one of many as the
# record; the body of any single event must not reach the page at all.
test_append_only_events_are_counted_and_never_rendered() {
  local log="$TMP_DIR/events.md" out="$TMP_DIR/events.out" rc
  write_full_log "$log"
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  assert_contains "EVENT Decision: 2 occurrences" "$txt" "both decisions are counted"
  assert_contains "EVENT Relay: 1 occurrences" "$txt" "the relay is counted"
  assert_not_contains "AARDVARK" "$txt" "no decision BODY reaches the page (the first)"
  assert_not_contains "CAPYBARA" "$txt" "no decision BODY reaches the page (the latest)"
  assert_not_contains "BADGER" "$txt" "no relay BODY reaches the page"
  assert_contains "not a timeline" "$txt" "and the page says why it only counts them"
}

# Same log, both claims at once: a register section exists and an event section does not.
test_registers_get_sections_and_events_do_not() {
  local log="$TMP_DIR/sections.md" out="$TMP_DIR/sections.out" rc
  write_full_log "$log"
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  assert_contains "=== Ledger — latest of 2" "$txt" "Ledger renders as a present-state section"
  assert_not_contains "=== Decision" "$txt" "Decision gets no present-state section"
  assert_not_contains "=== Relay" "$txt" "Relay gets no present-state section"
}

test_all_seven_registers_are_read_and_the_log_exits_clean() {
  local log="$TMP_DIR/seven.md" out="$TMP_DIR/seven.out" rc
  write_full_log "$log"
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  assert_eq "0" "$rc" "every register present and no drift exits 0"
  for mark in BOARDMARK DOCSMARK RULESMARK CLAIMSMARK PARKEDMARK WAVEMARK ZEBRAFISH; do
    assert_contains "$mark" "$txt" "the $mark register block is rendered"
  done
  assert_not_contains "NOT FOUND" "$txt" "nothing is reported missing"
}

# ---------------------------------------------------------------------------------------------
# The stamp. `engine log` injects it between `## ` and the glyph, so an anchored pattern sees only
# the unstamped minority. Every heading in write_full_log is stamped, so an anchored instrument
# finds nothing at all and renders a page that looks healthy.
# ---------------------------------------------------------------------------------------------

test_a_stamped_heading_is_read_and_the_anchored_reading_is_reported_as_worse() {
  local log="$TMP_DIR/stamped.md" out="$TMP_DIR/stamped.out" rc
  write_full_log "$log"
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  assert_contains "Ledger       register instrument=  2" "$txt" "the instrument reads both stamped ledgers"
  assert_contains "naive=  0" "$txt" "and reports that the anchored pattern would have found none"
  assert_contains "anchored reading would see" "$txt" "the gap between the two is stated, not merely avoided"
}

test_an_unstamped_heading_is_read_the_same_as_a_stamped_one() {
  local log="$TMP_DIR/mixed.md" out="$TMP_DIR/mixed.out" rc
  write_log "$log" \
    '## 🧵 Ledger — unstamped, EARLIEST' '' \
    '## [2026-01-01 10:00:00] 🧵 Ledger — stamped, MIDDLE' '' \
    '## 🧵 Ledger — unstamped, NEWEST' ''
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  assert_contains "instrument=  3" "$txt" "all three are read, stamped or not"
  assert_contains "latest of 3" "$txt" "and the newest wins regardless of whether it carries a stamp"
  assert_contains "NEWEST" "$txt" "the newest heading is the one rendered"
}

test_case_does_not_change_the_reading() {
  local log="$TMP_DIR/case.md" out="$TMP_DIR/case.out" rc
  write_log "$log" \
    '## [2026-01-01 10:00:00] 🧵 LEDGER — shouted, ALPACA' '' \
    '## [2026-01-01 11:00:00] 🧵 ledger — whispered, OCELOT' ''
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  assert_contains "instrument=  2" "$txt" "LEDGER and ledger are the same register"
  assert_contains "OCELOT" "$txt" "the latest of the two is rendered"
}

# ---------------------------------------------------------------------------------------------
# The glyph alone is not the key. These two shapes both carry a register's glyph as a substring and
# neither is a register write.
# ---------------------------------------------------------------------------------------------

test_a_composed_emoji_containing_a_register_glyph_is_not_a_register() {
  local log="$TMP_DIR/judge.md" out="$TMP_DIR/judge.out" rc
  # 🧑‍⚖️ is U+1F9D1 ZWJ U+2696 U+FE0F, so it CONTAINS the ⚖️ of `⚖️ Rules owed`.
  write_log "$log" \
    '## [2026-01-01 10:00:00] 🧑‍⚖️ Rules owed — a judge, not the register, WRONGMARK' '' \
    '## [2026-01-01 11:00:00] ⚖️ Rules owed — the real register, RIGHTMARK' ''
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  assert_contains "Rules owed   register instrument=  1" "$txt" "only the ⚖️ heading counts as the register"
  assert_contains "RIGHTMARK" "$(register_section "$out" "Rules owed")" "the real register block is rendered"
  assert_not_contains "WRONGMARK" "$(register_section "$out" "Rules owed")" \
    "the judge-emoji heading is not rendered as the register"
  assert_contains "WRONGMARK" "$txt" "but it IS reported — refused is not the same as swallowed"
}

test_a_register_name_quoted_mid_heading_is_not_a_register() {
  local log="$TMP_DIR/midline.md" out="$TMP_DIR/midline.out" rc
  write_log "$log" \
    '## ⭐ A finding on the way past — `⚖️ Rules owed` is invisible to the sweep, QUOTEDMARK' '' \
    '## [2026-01-01 11:00:00] ⚖️ Rules owed — the real one, REALMARK' ''
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  assert_contains "Rules owed   register instrument=  1" "$txt" "the mid-heading quotation does not count"
  assert_contains "REALMARK" "$(register_section "$out" "Rules owed")" "the real register is rendered"
  assert_not_contains "QUOTEDMARK" "$(register_section "$out" "Rules owed")" \
    "free prose cannot precede the glyph, so the quotation is not the register"
  assert_contains "QUOTEDMARK" "$txt" "and it is still reported, under the glyph it does carry"
}

test_a_known_mark_may_sit_around_the_glyph() {
  local log="$TMP_DIR/marks.md" out="$TMP_DIR/marks.out" rc
  write_log "$log" \
    '## [2026-01-01 10:00:00] 🧵⭐⭐⭐ Ledger — starred, STARMARK' '' \
    '## [2026-01-01 11:00:00] [THR-9] 🧵 Ledger — thread-prefixed, PREFIXMARK' ''
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  assert_contains "instrument=  2" "$txt" "stars after the glyph and a bracket prefix before it both read"
  assert_contains "PREFIXMARK" "$txt" "the latest is rendered"
}

test_a_glyph_without_its_register_name_is_not_a_register() {
  local log="$TMP_DIR/othername.md" out="$TMP_DIR/othername.out" rc
  write_log "$log" \
    '## [2026-01-01 10:00:00] 🧵 Thread opened — THREADMARK' '' \
    '## [2026-01-01 10:30:00] 🅿️ Standing — STANDINGMARK' '' \
    '## [2026-01-01 11:00:00] 🧵 Ledger — LEDGERMARK' ''
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  assert_contains "Ledger       register instrument=  1" "$txt" "🧵 Thread opened is not a Ledger"
  assert_contains "Parked       register instrument=  0" "$txt" "🅿️ Standing is not Parked"
  assert_contains "LEDGERMARK" "$(register_section "$out" "Ledger")" "the one real register renders"
  assert_not_contains "THREADMARK" "$(register_section "$out" "Ledger")" \
    "the thread-opened block is not rendered as the Ledger"
  assert_contains "OTHER-GLYPH — 2 headings" "$txt" "both are reported as glyph-bearing non-blocks"
  assert_contains "THREADMARK" "$txt" "and each is named in that list"
  assert_contains "STANDINGMARK" "$txt" "including the 🅿️ Standing one"
}

# ---------------------------------------------------------------------------------------------
# Nothing swallowed. A heading the renderer could not read as a block must appear in the output.
# ---------------------------------------------------------------------------------------------

test_a_heading_naming_a_register_without_its_glyph_is_reported_as_drift() {
  local log="$TMP_DIR/drift.md" out="$TMP_DIR/drift.out" rc
  write_log "$log" \
    '## [2026-01-01 10:00:00] Ledger updated and dehydration brief rewritten, NOGLYPHMARK' '' \
    '## [2026-01-01 10:30:00] 📒 Ledger brought current, WRONGGLYPHMARK' '' \
    '## [2026-01-01 11:00:00] 🧵 Ledger — the real register, GOODMARK' ''
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  assert_eq "3" "$rc" "drift is a finding: exit 3"
  assert_contains "DRIFT — 2 headings" "$txt" "both drifted headings are reported"
  assert_contains "NOGLYPHMARK" "$txt" "the glyph-less heading is named, with its line"
  assert_contains "WRONGGLYPHMARK" "$txt" "the wrong-glyph heading is named too"
  assert_contains "Ledger       register instrument=  1 control=  3" "$txt" \
    "the glyph-agnostic control finds 3 where the instrument finds 1, and both are printed"
  assert_contains "GOODMARK" "$txt" "the real register still renders"
  assert_not_contains "NOGLYPHMARK" "$(register_section "$out" "Ledger")" \
    "but a drifted heading is never rendered AS the register"
}

test_a_clean_log_says_drift_none_rather_than_staying_silent() {
  local log="$TMP_DIR/nodrift.md" out="$TMP_DIR/nodrift.out" rc
  write_full_log "$log"
  rc=$(run_text "$out" "$log")
  assert_contains "DRIFT — none." "$(cat "$out")" "a clean log states the absence rather than omitting the section"
}

test_a_register_with_no_occurrence_is_reported_loudly_and_exits_three() {
  local log="$TMP_DIR/missing.md" out="$TMP_DIR/missing.out" rc
  write_log "$log" \
    '## [2026-01-01 11:00:00] 🧵 Ledger — the only register here, SOLOMARK' ''
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  assert_eq "3" "$rc" "a missing register is a finding: exit 3"
  assert_contains "Wave: NOT FOUND" "$txt" "the Wave register is named as not found"
  assert_contains "Asks: NOT FOUND" "$txt" "so is Asks"
  assert_contains "This is output, not an absent section" "$txt" \
    "and the page says why it prints the absence"
  assert_contains "SOLOMARK" "$txt" "the register that does exist still renders"
}

test_the_buckets_reconcile_against_the_heading_count() {
  local log="$TMP_DIR/buckets.md" out="$TMP_DIR/buckets.out" rc
  write_full_log "$log"
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  # 7 registers + 1 superseded ledger + 2 decisions + 1 relay = 11 recognised, 0 drift, 0 other, 0 plain.
  assert_contains "buckets: 11 recognised + 0 drift + 0 other-glyph + 0 plain = 11 of 11" "$txt" \
    "every heading lands in exactly one bucket and the buckets sum to the total"
}

# ---------------------------------------------------------------------------------------------
# Code fences. A heading inside one is not a heading; a fence left open would swallow the rest of
# the log and render as a tidy, empty page.
# ---------------------------------------------------------------------------------------------

test_a_heading_inside_a_code_fence_is_not_read_as_a_block() {
  local log="$TMP_DIR/fenced.md" out="$TMP_DIR/fenced.out" rc
  write_log "$log" \
    '## [2026-01-01 10:00:00] 🧵 Ledger — the real one, OUTSIDEMARK' '' \
    '```' \
    '## [2026-01-01 12:00:00] 🧵 Ledger — inside a fence, INSIDEMARK' \
    '```' ''
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  assert_contains "1 fenced headings excluded" "$txt" "the fenced heading is counted as excluded, not ignored"
  assert_contains "Ledger       register instrument=  1" "$txt" "only the real heading is a register"
  assert_contains "OUTSIDEMARK" "$txt" "the real register renders"
}

test_an_unclosed_code_fence_is_an_instrument_fault_not_an_empty_page() {
  local log="$TMP_DIR/openfence.md" out="$TMP_DIR/openfence.out" rc
  write_log "$log" \
    '## [2026-01-01 10:00:00] 🧵 Ledger — OPENFENCEMARK' '' \
    '```' \
    'the fence is never closed, so everything after this is unread' ''
  rc=$(run_text "$out" "$log")
  assert_eq "2" "$rc" "an unclosed fence exits 2 rather than rendering a page from a partial read"
  assert_contains "never closed" "$(cat "$out.err")" "and says which fence and how many lines went unread"
}

test_an_inline_span_does_not_open_a_fence() {
  local log="$TMP_DIR/inline.md" out="$TMP_DIR/inline.out" rc
  write_log "$log" \
    '## [2026-01-01 10:00:00] 🧵 Ledger — INLINEMARK' '' \
    '*   a line mentioning ```three backticks``` inline, which opens nothing' '' \
    '## [2026-01-01 11:00:00] 🌊 Wave — WAVEAFTERMARK' ''
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  assert_contains "WAVEAFTERMARK" "$txt" "the heading after an inline span is still read"
  assert_contains "0 fenced headings excluded" "$txt" "no fence was considered open"
}

# ---------------------------------------------------------------------------------------------
# The block body is passed through, not re-interpreted. That is what makes the page unable to
# disagree with the rows it came from.
# ---------------------------------------------------------------------------------------------

test_the_block_body_is_reproduced_verbatim_in_the_text_reading() {
  local log="$TMP_DIR/verbatim.md" out="$TMP_DIR/verbatim.out" rc
  write_log "$log" \
    '## [2026-01-01 11:00:00] 🧵 Ledger — VERBATIMMARK' '' \
    '| threadId | status |' \
    '|----------|--------|' \
    '| THR-7 | **landed** · `abc1234` |' '' \
    '*   **Tree**: 226 dirty, index empty' ''
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  assert_contains '| THR-7 | **landed** · `abc1234` |' "$txt" "the table row appears exactly as written"
  assert_contains '*   **Tree**: 226 dirty, index empty' "$txt" "so does the bullet, markdown intact"
}

test_a_block_ends_at_the_next_heading_and_does_not_swallow_it() {
  local log="$TMP_DIR/bounds.md" out="$TMP_DIR/bounds.out" rc
  write_log "$log" \
    '## [2026-01-01 11:00:00] 🌊 Wave — WAVEBODYMARK' '' \
    '*   two lanes out' '' \
    '## [2026-01-01 11:30:00] ♻️ Session Resume — NEXTBLOCKMARK' '' \
    '*   resumed from the dehydration' ''
  rc=$(run_text "$out" "$log")
  local wave; wave=$(sed -n '/^=== Wave/,$p' "$out" | sed -n '1,8p')
  assert_contains "WAVEBODYMARK" "$wave" "the Wave block renders its own heading"
  assert_contains "two lanes out" "$wave" "and its own body"
  assert_not_contains "NEXTBLOCKMARK" "$wave" "but stops at the next heading rather than swallowing it"
}

test_a_subheading_inside_a_block_stays_in_the_block() {
  local log="$TMP_DIR/sub.md" out="$TMP_DIR/sub.out" rc
  write_log "$log" \
    '## [2026-01-01 11:00:00] 🧵 Ledger — SUBPARENTMARK' '' \
    '### Rows' '' \
    '*   SUBCHILDMARK' ''
  rc=$(run_text "$out" "$log")
  local txt; txt=$(cat "$out")
  assert_contains "SUBCHILDMARK" "$txt" "a ### subheading does not end the block"
  assert_contains "### Rows" "$txt" "and the subheading itself is kept"
}

# ---------------------------------------------------------------------------------------------
# The HTML page.
# ---------------------------------------------------------------------------------------------

test_the_html_page_is_written_and_is_self_contained() {
  local log="$TMP_DIR/page.md" out="$TMP_DIR/page.html" rc
  write_full_log "$log"
  rc=$(run_html "$out" "$log")
  assert_eq "0" "$rc" "a clean log renders and exits 0"
  assert_file_exists "$out" "the html file is written"
  local html; html=$(cat "$out")
  assert_contains "<!doctype html>" "$html" "it is a document, not a fragment"
  assert_contains "ZEBRAFISH" "$html" "the latest ledger reaches the page"
  assert_not_contains "XYLOPHONE" "$html" "the superseded ledger does not"
  assert_not_contains "<script src" "$html" "no external script: the page must render with no network"
  assert_not_contains "<link rel=\"stylesheet\"" "$html" "no external stylesheet either"
  assert_contains "prefers-color-scheme" "$html" "it defines a dark mode"
  assert_contains "font-variant-ligatures:none" "$html" "code fonts have ligatures off"
  assert_contains "width=device-width" "$html" "and it declares a viewport for phone width"
}

test_the_html_page_opens_with_its_scope() {
  local log="$TMP_DIR/scope.md" out="$TMP_DIR/scope.html" rc
  write_full_log "$log"
  rc=$(run_html "$out" "$log")
  local html; html=$(cat "$out")
  assert_contains "What this is" "$html" "the page says what it is"
  assert_contains "What it is not" "$html" "and what it is not"
  assert_contains "Who it is for" "$html" "and who it is for"
  assert_contains "Not the event timeline" "$html" "naming the ruling it was built under"
}

test_the_html_page_renders_a_table_as_a_table() {
  local log="$TMP_DIR/tbl.md" out="$TMP_DIR/tbl.html" rc
  write_log "$log" \
    '## [2026-01-01 11:00:00] 🧵 Ledger — TABLEMARK' '' \
    '| threadId | status |' \
    '|----------|--------|' \
    '| THR-7 | **landed** |' ''
  rc=$(run_html "$out" "$log")
  local html; html=$(cat "$out")
  assert_contains "<th>threadId</th>" "$html" "the header row becomes th cells"
  assert_contains "<td>THR-7</td>" "$html" "the body row becomes td cells"
  assert_contains "<strong>landed</strong>" "$html" "inline bold is rendered"
}

# The log wraps a path in bold-around-code constantly (`**`skills/intake/SKILL.md:264`**`). Rendering
# each backtick segment separately splits the `**` pair across two segments and the page shows the
# literal asterisks — which it did, until a real render was looked at.
test_the_html_page_renders_emphasis_that_wraps_a_code_span() {
  local log="$TMP_DIR/boldcode.md" out="$TMP_DIR/boldcode.html" rc
  write_log "$log" \
    '## [2026-01-01 11:00:00] 📚 Docs owed — BOLDCODEMARK' '' \
    '*   **`skills/intake/SKILL.md:264`** still tells the orchestrator to hand-roll it' '' \
    '*   and an italic wrapping code: (*"or descend `children` yourself"*)' ''
  rc=$(run_html "$out" "$log")
  local html; html=$(cat "$out")
  assert_contains "<strong><code>skills/intake/SKILL.md:264</code></strong>" "$html" \
    "bold wrapping a code span renders as bold, not as literal asterisks"
  assert_contains "<code>children</code>" "$html" "and the code span inside an italic survives"
  assert_not_contains "**<code>" "$html" "no literal ** reaches the page"
  assert_not_contains "</code>**" "$html" "from either side of the pair"
}

test_the_html_page_escapes_markup_in_the_log() {
  local log="$TMP_DIR/esc.md" out="$TMP_DIR/esc.html" rc
  write_log "$log" \
    '## [2026-01-01 11:00:00] 🧵 Ledger — ESCAPEMARK' '' \
    '*   a row mentioning <script>alert(1)</script> and A & B' ''
  rc=$(run_html "$out" "$log")
  local html; html=$(cat "$out")
  assert_contains "&lt;script&gt;" "$html" "a tag in the log is escaped, not emitted"
  assert_not_contains "<script>alert(1)</script>" "$html" "the raw tag never reaches the page"
  assert_contains "A &amp; B" "$html" "an ampersand is escaped too"
}

test_the_html_page_reports_a_missing_register_rather_than_omitting_it() {
  local log="$TMP_DIR/htmlmissing.md" out="$TMP_DIR/htmlmissing.html" rc
  write_log "$log" '## [2026-01-01 11:00:00] 🧵 Ledger — ONLYMARK' ''
  rc=$(run_html "$out" "$log")
  assert_eq "3" "$rc" "the page still renders, and exits 3 as a finding"
  local html; html=$(cat "$out")
  assert_contains "NOT FOUND" "$html" "the missing registers are named on the page"
  assert_contains "registers not found in this log" "$html" "with a count in the warning"
}

# ---------------------------------------------------------------------------------------------
# The real log. A renderer that passes every synthetic test and misreports the live log is not done.
# ---------------------------------------------------------------------------------------------

test_the_live_loom_log_is_read_with_every_register_found() {
  if [[ ! -f "$LIVE_LOG" ]]; then
    skip "the live loom log is read" "no corpus at $LIVE_LOG"
    return
  fi
  local out="$TMP_DIR/live.out" rc
  rc=$(run_text "$out" "$LIVE_LOG")
  local txt; txt=$(cat "$out")
  # Floors, not exact counts: the log is still being written to, so a figure from a minute ago
  # may already be false. The claim pinned here is that each register is FOUND at all.
  for reg in Ledger Asks "Docs owed" "Rules owed" "Open claims" Parked Wave; do
    assert_not_contains "$reg: NOT FOUND" "$txt" "the live log's $reg register is found"
  done
  assert_contains "=== Ledger — latest of" "$txt" "and the Ledger renders a present-state section"
}

test_the_live_log_shows_the_anchored_reading_losing_most_of_the_wave_register() {
  if [[ ! -f "$LIVE_LOG" ]]; then
    skip "the live loom log is read" "no corpus at $LIVE_LOG"
    return
  fi
  local out="$TMP_DIR/live2.out" rc
  rc=$(run_text "$out" "$LIVE_LOG")
  local txt; txt=$(cat "$out")
  # The trap at its worst: every 🌊 Wave heading in this log is stamped, so the anchored pattern
  # finds none and would render no Wave section while looking perfectly healthy.
  local wave; wave=$(grep '^  Wave ' "$out")
  assert_contains "naive=  0" "$wave" "the anchored reading of 🌊 Wave is zero on the live log"
  assert_not_contains "instrument=  0" "$wave" "while the instrument finds some"
  assert_contains "anchored reading would see 0 of" "$wave" "and the page states the gap"
}

test_the_live_log_buckets_reconcile() {
  if [[ ! -f "$LIVE_LOG" ]]; then
    skip "the live loom log is read" "no corpus at $LIVE_LOG"
    return
  fi
  local out="$TMP_DIR/live3.out" rc
  rc=$(run_text "$out" "$LIVE_LOG")
  assert_gt "$rc" "1" "the live log is a finding (drift and/or a missing register), not a fault"
  assert_contains "buckets:" "$(cat "$out")" "the bucket partition is printed"
  # The conservation law is enforced inside the script: a partition that does not sum exits 2.
  # So any exit other than 2 is the law holding on a 8000-line real log.
  if [[ "$rc" == "2" ]]; then
    fail "the live log's buckets did not sum" "not 2" "$rc"
  else
    pass "the live log's heading partition sums (exit $rc, not an instrument fault)"
  fi
}

test_the_live_log_reports_the_drift_it_finds() {
  if [[ ! -f "$LIVE_LOG" ]]; then
    skip "the live loom log is read" "no corpus at $LIVE_LOG"
    return
  fi
  local out="$TMP_DIR/live4.out" rc
  rc=$(run_text "$out" "$LIVE_LOG")
  local txt; txt=$(cat "$out")
  # This log contains `Relay - …` headings with no glyph at all. The claim is that whatever drift
  # exists is NAMED — never that the count is a particular number.
  assert_contains "DRIFT" "$txt" "the drift section is present either way"
  if grep -q '^DRIFT — none' "$out"; then
    pass "the live log currently carries no drift (and says so)"
  else
    assert_contains "Not rendered as registers" "$txt" "and drifted headings are explicitly not rendered as registers"
  fi
}

run_discovered_tests
