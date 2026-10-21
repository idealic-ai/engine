#!/bin/bash
# tests/test-lane-stall-sh.sh — Tests for lane-stall.sh lane detection and log dating.
# Run: bash ~/.claude/engine/scripts/tests/run-all.sh test-lane-stall-sh.sh
#      bash ~/.claude/engine/scripts/tests/test-lane-stall-sh.sh
#
# The inputs are REAL transcripts and REAL session dirs on this machine, not fixtures this
# suite authored: a detector for "did a lane go quiet" can only be judged against briefs it
# did not write. Each corpus is checked for presence first and SKIPped when absent, so a
# fresh machine reports "no corpus" rather than a false green.
#
# Corpora, and what each one is here to catch:
#   KERNEL_SESSION   2026_09_16_KIT_UI_KERNEL — 28 subagent transcripts mention it, NONE of
#                    whose prompts open with "[TAG]". The anchored-prompt regex saw 0 lanes
#                    here and printed "no stale lanes" at exit 0; the spawn `description`
#                    names 24. This is the false clean.
#   SCOPE_SESSION    2026_10_12_SCOPE_LOOM_TREEPUBLISH — 1 log at the session root, 87 under
#                    builds/. Root-only log discovery dates 18 of its rows; walking the tree
#                    dates 73. Because `fresh` is a min over the readings that exist, a
#                    dropped log reading can only make a lane look staler than it is.
#   NEG_SESSION      2026_10_07_KIT_SUBSYSTEM_GAP_CHART — holds three real subagents that
#                    are NOT loom lanes (an HTML-page finisher, a /prove-visionary direction
#                    architect, a council panellist) whose prompts contain the literal
#                    "[MANDATORY]". The nearest legal neighbour: widening the tag scan to
#                    the whole prompt mints these as lanes.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

# LANE_STALL_SH points the suite at a modified copy, which is how each assertion below was
# watched going red before it was trusted. Two plants, both run against the real corpora:
#   resolve_tag's HEAD_TAG.match -> TAG.search over the whole prompt, desc source disabled
#     -> mints "STALE [MANDATORY]" from a real non-lane transcript (refusal test goes red)
#   the session walk pruned with dirs[:] = [] (the pre-fix root-only glob)
#     -> every log column reads "-" (log-discovery test goes red)
LANE_STALL="${LANE_STALL_SH:-$HOME/.claude/engine/scripts/lane-stall.sh}"
KERNEL_SESSION="$HOME/sessions/2026_09_16_KIT_UI_KERNEL"
NEG_SESSION="$HOME/Projects/finch/sessions/2026_10_07_KIT_SUBSYSTEM_GAP_CHART"
# The corpora are weeks old, so the default 12h window excludes them. Each window is the
# smallest that reaches its corpus: the candidate scan touches every transcript in the
# window, so a blanket 20000 would triple the suite's runtime for nothing. Both roots are
# local on purpose — the same session dir on a cloud-synced mount turns a 14s run into
# minutes, and once timed the walk out entirely.
SCOPE_SESSION="$HOME/Projects/kit/sessions/2026_10_12_SCOPE_LOOM_TREEPUBLISH"
KERNEL_HOURS=1000
NEG_HOURS=400
SCOPE_HOURS=400
ARCHIVE_HOURS="$KERNEL_HOURS"

TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Occurrences, not matching lines: `grep -c` would answer a narrower question than the
# callers below take it for.
count_occurrences() {
  grep -oF "$1" "$2" 2>/dev/null | wc -l | tr -d ' '
}

run_lane_stall() {
  local out="$1" session="$2" hours="${3:-$ARCHIVE_HOURS}"
  bash "$LANE_STALL" "$session" --all --since-hours "$hours" >"$out" 2>"$out.err"
  echo $?
}

test_lane_stall_script_exists() {
  assert_file_exists "$LANE_STALL" "lane-stall.sh is present"
}

# RED: with tag resolution limited to a bracket at offset 0 of the prompt, this prints
# "no stale lanes (threshold 30m, 0 lanes seen)" and exits 0 — a 24-lane weave reported
# clean, with the exit code agreeing.
test_lane_stall_sees_lanes_whose_brief_opens_with_prose() {
  if [ ! -d "$KERNEL_SESSION" ]; then
    skip "prose-opened lanes are seen" "no corpus at $KERNEL_SESSION"
    return 0
  fi
  local out="$TMP_DIR/kernel.txt"
  run_lane_stall "$out" "$KERNEL_SESSION" >/dev/null
  local rows
  rows=$(grep -c '^\(ok\|STALE\)' "$out" 2>/dev/null)
  assert_gt "$rows" 19 "KIT_UI_KERNEL: at least 20 lanes seen (got $rows)"
  assert_not_contains "0 lanes seen" "$(cat "$out")" \
    "KIT_UI_KERNEL: does not report a clean weave"
  # Three tags drawn from the session's own spawn descriptions, spot-checking that the rows
  # carry real lane names and not just a count.
  assert_contains "[KERNEL]" "$(cat "$out")" "KIT_UI_KERNEL: lane [KERNEL] resolved"
  assert_contains "[VIEWLEVELS]" "$(cat "$out")" "KIT_UI_KERNEL: lane [VIEWLEVELS] resolved"
  assert_contains "[JSLTFORM]" "$(cat "$out")" "KIT_UI_KERNEL: lane [JSLTFORM] resolved"
}

# Every row must say which source named the lane, so a reader can tell an authoritative
# reading from a heuristic one.
test_lane_stall_reports_tag_provenance() {
  if [ ! -d "$KERNEL_SESSION" ]; then
    skip "tag provenance is reported" "no corpus at $KERNEL_SESSION"
    return 0
  fi
  local out="$TMP_DIR/kernel-via.txt"
  run_lane_stall "$out" "$KERNEL_SESSION" >/dev/null
  local rows vias
  rows=$(grep -c '^\(ok\|STALE\)' "$out" 2>/dev/null)
  vias=$(grep -oE 'via=(desc|head|thread)' "$out" 2>/dev/null | wc -l | tr -d ' ')
  assert_eq "$rows" "$vias" "every row carries a via= source ($rows rows, $vias sources)"
}

# RED: resolving the tag with a bracket scan over the whole prompt (TAG.search instead of a
# match at offset 0) mints [MANDATORY] from the three non-lane transcripts in this session.
test_lane_stall_refuses_quoted_protocol_tokens() {
  if [ ! -d "$NEG_SESSION" ]; then
    skip "quoted protocol tokens are refused" "no corpus at $NEG_SESSION"
    return 0
  fi
  local out="$TMP_DIR/neg.txt"
  run_lane_stall "$out" "$NEG_SESSION" "$NEG_HOURS" >/dev/null
  # The positive control for the zeros below, in the SAME invocation: a run that found no
  # lanes at all would report twelve zeros while proving nothing.
  local rows
  rows=$(grep -c '^\(ok\|STALE\)' "$out" 2>/dev/null)
  assert_gt "$rows" 9 "GAP_CHART: the run did find lanes, so the zeros below mean refusal (got $rows)"
  local token
  for token in MANDATORY OFFERED NEXT KEEP VIEW BACK HOLD SWAP REDO JUMP TAG A-Z; do
    assert_eq "0" "$(count_occurrences "[$token]" "$out")" \
      "protocol token [$token] is not minted as a lane"
  done
}

# A lane logs to <sessionDir>/builds/<lane>_BUILD_LOG.md. The non-recursive glob reached only
# the session root, so every dispatched lane's log age read "-" — and because `fresh` is a min
# over the readings that exist, a dropped reading can only make a lane look staler.
# RED: drop the "**" from the log glob and every builds/ log disappears from discovery.
test_lane_stall_discovers_logs_below_the_session_root() {
  if [ ! -d "$SCOPE_SESSION" ]; then
    skip "lane logs below the root are read" "no corpus at $SCOPE_SESSION"
    return 0
  fi
  local out="$TMP_DIR/scope.txt"
  run_lane_stall "$out" "$SCOPE_SESSION" "$SCOPE_HOURS" >/dev/null
  local rows dated
  rows=$(grep -c '^\(ok\|STALE\)' "$out" 2>/dev/null)
  dated=$(grep -cE 'log= *[0-9]' "$out" 2>/dev/null)
  assert_gt "$rows" 99 "SCOPE_LOOM: lanes are seen at all (got $rows)"
  # This session keeps 1 log at its root and 87 under builds/. Root-only discovery dates 18
  # of these rows; walking the tree dates 73. The floor sits between the two.
  assert_gt "$dated" 39 "SCOPE_LOOM: lane logs under builds/ date their lanes (got $dated)"
}

# `engine log` leaves a heading unstamped when it opens with a bracket that is not a date.
# Lane logs written before that was fixed stay unstamped forever, so the only reading left
# for them is the file's own mtime. Without the fallback those lanes read log="-".
test_lane_stall_dates_unstamped_lane_logs_from_mtime() {
  assert_contains "MTIME_FALLBACK_MAX_TAGS" "$(cat "$LANE_STALL")" \
    "an mtime fallback exists for unstamped lane logs"
  # Capped, so a shared conductor log cannot date a lane it merely mentions.
  assert_contains "MTIME_FALLBACK_MAX_TAGS = 2" "$(cat "$LANE_STALL")" \
    "the mtime fallback is capped at two tags per file"
}

# A session dir on a cloud-synced mount can time the walk out. That used to abort the run with
# a traceback and zero rows — indistinguishable, to a caller reading stdout, from a clean weave.
test_lane_stall_survives_an_unreadable_session_dir() {
  local missing="$TMP_DIR/does-not-exist"
  local out="$TMP_DIR/missing.txt"
  local rc
  rc=$(run_lane_stall "$out" "$missing")
  assert_contains "lanes seen" "$(cat "$out")" \
    "a missing session dir still produces a verdict line, not a traceback"
  assert_not_contains "Traceback" "$(cat "$out.err")" \
    "a missing session dir raises no traceback"
}

# An unreadable path must not be swallowed either: a silent skip reads as "no lanes", which is
# the same false clean by another route. Both arms are exercised — a log file that cannot be
# opened, and a directory os.walk cannot descend.
# RED: drop either `except OSError` and the run dies with a traceback and no verdict line.
test_lane_stall_warns_rather_than_swallowing_an_unreadable_path() {
  local session="$TMP_DIR/unreadable"
  mkdir -p "$session/builds"
  printf '## [NOBODY] heading\n' > "$session/builds/x_LOG.md"

  chmod 000 "$session/builds/x_LOG.md"
  local out="$TMP_DIR/unreadable-file.txt"
  run_lane_stall "$out" "$session" 12 >/dev/null
  chmod 644 "$session/builds/x_LOG.md"
  assert_contains "lanes seen" "$(cat "$out")" "an unreadable log file still yields a verdict line"
  assert_contains "unreadable; counts above are a floor" "$(cat "$out.err")" \
    "an unreadable log file is reported, not swallowed"
  assert_not_contains "Traceback" "$(cat "$out.err")" "an unreadable log file raises no traceback"

  chmod 000 "$session/builds"
  local out2="$TMP_DIR/unreadable-dir.txt"
  run_lane_stall "$out2" "$session" 12 >/dev/null
  chmod 755 "$session/builds"
  assert_contains "unreadable; counts above are a floor" "$(cat "$out2.err")" \
    "a directory the walk cannot descend is reported, not swallowed"
  assert_not_contains "Traceback" "$(cat "$out2.err")" \
    "a directory the walk cannot descend raises no traceback"
}

# The session identity test is a substring match against a whole dispatch prompt, so matching
# on the directory's name alone harvests other weaves' lanes whenever that name is an ordinary
# word. RED: restore `session_dir.rstrip("/").split("/")[-1]` and an empty dir named "empty"
# reports seven lanes from six unrelated transcript directories at exit 3.
test_lane_stall_does_not_claim_other_weaves_lanes() {
  local common="$TMP_DIR/empty"
  mkdir -p "$common"
  local out="$TMP_DIR/common.txt" rc
  rc=$(run_lane_stall "$out" "$common" 12)
  local rows
  rows=$(grep -c '^\(ok\|STALE\)' "$out" 2>/dev/null)
  assert_eq "0" "$rows" "an empty dir named 'empty' claims no lanes (got $rows)"
  assert_eq "0" "$rc" "an empty dir named 'empty' exits 0, not 3"
}

# The nearest legal neighbour for that rule: not a nonsense name, but a DIFFERENT session at
# the SAME root, where the parent component is identical and only the name differs. The two
# lane sets must stay essentially disjoint.
test_lane_stall_separates_sibling_sessions_at_one_root() {
  local sibling="$HOME/sessions/2026_09_18_IDEAS_GRANTS_LOOM"
  if [ ! -d "$KERNEL_SESSION" ] || [ ! -d "$sibling" ]; then
    skip "sibling sessions at one root stay separate" "no corpus"
    return 0
  fi
  local a="$TMP_DIR/sib-a.txt" b="$TMP_DIR/sib-b.txt"
  run_lane_stall "$a" "$KERNEL_SESSION" "$KERNEL_HOURS" >/dev/null
  run_lane_stall "$b" "$sibling" "$KERNEL_HOURS" >/dev/null
  local na nb shared
  na=$(grep -oE '\[[A-Z0-9_-]+\]' "$a" | sort -u | wc -l | tr -d ' ')
  nb=$(grep -oE '\[[A-Z0-9_-]+\]' "$b" | sort -u | wc -l | tr -d ' ')
  shared=$(comm -12 <(grep -oE '\[[A-Z0-9_-]+\]' "$a" | sort -u) \
                    <(grep -oE '\[[A-Z0-9_-]+\]' "$b" | sort -u) | wc -l | tr -d ' ')
  assert_gt "$na" 19 "sibling test: the first session has lanes to confuse ($na)"
  assert_gt "$nb" 4  "sibling test: the second session has lanes to confuse ($nb)"
  # Two tags overlap and both are explained, not tolerated: [SNAPSHOT] is a different
  # transcript in each weave (a common lane name, correctly attributed twice), and [ORDERBY]
  # is one transcript whose brief genuinely names BOTH sessions. A third would be a defect.
  if [ "$shared" -le 2 ]; then
    pass "sibling sessions at one root share at most the 2 explained tags (got $shared)"
  else
    fail "sibling sessions at one root share at most the 2 explained tags" "<= 2" "$shared"
  fi
}

test_lane_stall_exit_code_distinguishes_stale_from_clean() {
  if [ ! -d "$KERNEL_SESSION" ]; then
    skip "exit 3 on stale lanes" "no corpus at $KERNEL_SESSION"
    return 0
  fi
  local out="$TMP_DIR/exit.txt" rc
  rc=$(run_lane_stall "$out" "$KERNEL_SESSION")
  assert_eq "3" "$rc" "a weave of long-quiet lanes exits 3"
}

run_discovered_tests
