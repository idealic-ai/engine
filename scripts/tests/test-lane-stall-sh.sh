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
# The corpora are weeks old, so each run pins an explicit window rather than relying on the
# default. Each is the smallest that reaches its corpus — but NOT because width is expensive:
# measured 2026-10-21 on one corpus, 12h/400h/2000h/20000h came in at 0.95s/9.10s/12.24s/9.87s,
# so cost plateaus once the window clears the recent transcripts and a wider one is free.
# (An earlier note here claimed a blanket 20000 would triple the runtime; that is falsified.)
# They stay pinned so each assertion names the window it is judging. Both roots are
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

# The ONE way this suite reads the logpath field, and the one the consumer-facing
# instructions name: everything after "logpath=" to end of line. `awk '{print $NF}'` and a
# `logpath=/[^ ]*` regex both truncate a path containing a space, which the session
# directories this sweep runs on routinely have, and a truncated path still looks like one.
logpath_values() {
  grep '^\(ok\|STALE\)' "$1" 2>/dev/null | sed 's/.*logpath=//'
}

# Per-row audit of the logpath field, because every count-of-kinds over it has been falsified
# once already: a floor on "rows that look right" is cleared by the rows a mutation left
# alone. Prints six counts: rows badshape badprov badtilde exact approx.
#   badshape  a path that is not a *_LOG.md          (RED: log_path[tag] = session_dir)
#   badprov   an exact reading whose own file holds no heading at that timestamp
#                                                     (RED: assign the path outside the max guard)
#   badtilde  a "~" reading whose file does have stamped headings, so it was not mtime-dated
#                                                     (RED: drop log_approx.discard)
audit_logpath_rows() {
  python3 - "$1" <<'PY'
import os, re, sys, time
from datetime import datetime
TS = re.compile(r"^## \[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\]")
ROW = re.compile(r"^(?:ok|STALE)\s+\[([A-Z0-9_-]+)\].*?\blog=\s*(\S+)\s.*?\blogpath=(.*)$")
now = time.time()
rows = badshape = badprov = badtilde = exact = approx = 0
stamps = {}
def heading_stamps(p):
    if p not in stamps:
        out = []
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    m = TS.match(line)
                    if m:
                        out.append(datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S").timestamp())
        except OSError:
            pass
        stamps[p] = out
    return stamps[p]
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    m = ROW.match(line.rstrip("\n"))
    if not m:
        continue
    rows += 1
    reading, path = m.group(2), m.group(3)
    if path == "none":
        continue
    if not path.endswith("_LOG.md"):
        badshape += 1
        continue
    if reading == "-":
        continue
    age = int(reading.rstrip("m~"))
    if reading.endswith("~"):
        approx += 1
        if heading_stamps(path):
            badtilde += 1
    else:
        exact += 1
        # Tolerance absorbs the seconds between the sweep's clock and this one, and the
        # row's rounding to whole minutes. Ages on these corpora are in the thousands.
        if not any(abs((now - t) / 60 - age) <= 2 for t in heading_stamps(path)):
            badprov += 1
print(rows, badshape, badprov, badtilde, exact, approx)
PY
}

run_lane_stall() {
  local out="$1" session="$2" hours="${3:-$ARCHIVE_HOURS}"
  bash "$LANE_STALL" "$session" --all --since-hours "$hours" >"$out" 2>"$out.err"
  echo $?
}

# No --since-hours, so the window is whatever the script resolves for itself.
run_lane_stall_default_window() {
  local out="$1" session="$2"
  bash "$LANE_STALL" "$session" --all >"$out" 2>"$out.err"
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

# Every consumer of this sweep is required to hand over a lane's LOG PATH and forbidden to
# hand over anything else (`§INV_LOOM_HANDS_OVER_A_PATH_NOT_AN_ID`), so the sweep owes them
# that field. It used to print the agent transcript instead and each caller re-derived the
# log by hand, which is a rule with no check behind it.
# RED: drop log_path from the row and print lane["path"] alone, as before.
test_lane_stall_prints_the_lanes_log_path() {
  if [ ! -d "$SCOPE_SESSION" ]; then
    skip "rows carry a log path" "no corpus at $SCOPE_SESSION"
    return 0
  fi
  local out="$TMP_DIR/scope-logpath.txt"
  run_lane_stall "$out" "$SCOPE_SESSION" "$SCOPE_HOURS" >/dev/null
  local rows pathed
  rows=$(grep -c '^\(ok\|STALE\)' "$out" 2>/dev/null)
  # The positive control for the count below, in the SAME invocation.
  assert_gt "$rows" 99 "SCOPE_LOOM: the run found lanes, so the log-path count means something (got $rows)"
  pathed=$(logpath_values "$out" | grep -c '^/.*_LOG\.md$')
  assert_gt "$pathed" 39 "SCOPE_LOOM: rows resolve a real *_LOG.md log path (got $pathed)"
}

# A lane with no log is a DIFFERENT hand-over from a lane with one, so the two readings may
# not print alike. Both arms must appear in one invocation — each is the other's control.
# RED: print an empty string, or the transcript path, where no log was found.
test_lane_stall_distinguishes_a_lane_with_no_log() {
  if [ ! -d "$SCOPE_SESSION" ]; then
    skip "a lane with no log is marked" "no corpus at $SCOPE_SESSION"
    return 0
  fi
  local out="$TMP_DIR/scope-nolog.txt"
  run_lane_stall "$out" "$SCOPE_SESSION" "$SCOPE_HOURS" >/dev/null
  local none some
  none=$(grep -cE 'logpath=none' "$out" 2>/dev/null)
  some=$(grep -cE 'logpath=/' "$out" 2>/dev/null)
  assert_gt "$none" 0 "SCOPE_LOOM: a lane with no log reads logpath=none (got $none)"
  assert_gt "$some" 0 "SCOPE_LOOM: a lane with a log reads a real path (got $some)"
}

# The invariant underneath the two tests above, and the one that covers BOTH dating branches:
# if the sweep dated a lane from a log, it knows which log, so a dated reading with no path is
# the sweep withholding something it holds. Counting kinds instead of pairing them is too
# loose to catch one branch — measured: dropping the path from the stamped-heading branch
# alone left 55 mtime-dated paths standing, which cleared a "more than 39" threshold.
#
# Pairing alone is still too loose, and was falsified a second time: a pairing that only asks
# whether the field starts with "/" is satisfied by handing over the SESSION DIRECTORY, and a
# pairing that does not ask WHICH log is satisfied by the last file to mention the tag rather
# than the one that dated it. So the field is audited PER ROW, with the row count as the
# positive control, and never as a floor on how many rows look right.
# RED: drop `log_path[tag] = log` from EITHER the stamped-heading branch or the mtime fallback;
#      assign `session_dir` instead of `log`; move the assignment outside the `last_ts >` guard;
#      drop the `log_approx.discard`.
test_lane_stall_pairs_every_dated_reading_with_its_log_path() {
  if [ ! -d "$SCOPE_SESSION" ]; then
    skip "a dated reading carries its log path" "no corpus at $SCOPE_SESSION"
    return 0
  fi
  local out="$TMP_DIR/scope-pair.txt"
  run_lane_stall "$out" "$SCOPE_SESSION" "$SCOPE_HOURS" >/dev/null
  local body="$TMP_DIR/scope-pair-body.txt"
  grep '^\(ok\|STALE\)' "$out" > "$body" 2>/dev/null
  # Both dating branches must be exercised, or this test proves nothing about the one that
  # is missing: an exact reading comes from a stamped heading, a "~" reading from the file's
  # mtime. These two counts are the positive controls for the pairings below.
  local exact approx
  exact=$(grep -cE 'log= *[0-9]+m ' "$body" 2>/dev/null)
  approx=$(grep -cE 'log= *[0-9]+m~ ' "$body" 2>/dev/null)
  assert_gt "$exact" 0 "SCOPE_LOOM: the stamped-heading branch is exercised (got $exact)"
  assert_gt "$approx" 0 "SCOPE_LOOM: the mtime-fallback branch is exercised (got $approx)"

  local dated dated_pathed
  dated=$(grep -cE 'log= *[0-9]+m~? ' "$body" 2>/dev/null)
  dated_pathed=$(grep -E 'log= *[0-9]+m~? ' "$body" | grep -c 'logpath=/' 2>/dev/null)
  assert_eq "$dated" "$dated_pathed" \
    "every dated log reading carries the path it was read from ($dated dated, $dated_pathed pathed)"

  # The converse, so the pairing cannot be satisfied by pointing every row at some log.
  local undated undated_none
  undated=$(grep -cE 'log= *- ' "$body" 2>/dev/null)
  undated_none=$(grep -E 'log= *- ' "$body" | grep -c 'logpath=none' 2>/dev/null)
  assert_gt "$undated" 0 "SCOPE_LOOM: some lane is undated, so the converse means something (got $undated)"
  assert_eq "$undated" "$undated_none" \
    "every undated lane reads logpath=none ($undated undated, $undated_none none)"

  # Per-row, not per-kind. Three claims the field makes about itself, each with its own
  # positive control in this same invocation.
  local a_rows a_shape a_prov a_tilde a_exact a_approx
  read -r a_rows a_shape a_prov a_tilde a_exact a_approx < <(audit_logpath_rows "$out")
  assert_gt "$a_rows" 99 "SCOPE_LOOM: the audit parsed rows, so its zeros mean something (got $a_rows)"
  assert_eq "0" "$a_shape" "every handed-over path is a *_LOG.md, not a directory ($a_shape of $a_rows are not)"
  assert_gt "$a_exact" 0 "SCOPE_LOOM: exact readings exist, so the provenance zero means something (got $a_exact)"
  assert_eq "0" "$a_prov" \
    "every exact reading's own log holds a heading at that timestamp ($a_prov of $a_exact do not)"
  assert_gt "$a_approx" 0 "SCOPE_LOOM: \"~\" readings exist, so the marker zero means something (got $a_approx)"
  assert_eq "0" "$a_tilde" \
    "every \"~\" reading points at a log with no stamped heading ($a_tilde of $a_approx do not)"
}

# The transcript path is the handle the hand-over rule forbids, and the last field of a row is
# what a reader copies. Keeping it visible is fine; leaving it in the copy-the-tail position
# is the affordance that produced the workaround in the first place.
# RED: move the transcript back to the end of the row.
test_lane_stall_does_not_end_a_row_with_the_forbidden_handle() {
  if [ ! -d "$SCOPE_SESSION" ]; then
    skip "no row ends in a transcript path" "no corpus at $SCOPE_SESSION"
    return 0
  fi
  local out="$TMP_DIR/scope-tail.txt"
  run_lane_stall "$out" "$SCOPE_SESSION" "$SCOPE_HOURS" >/dev/null
  local rows tail_jsonl
  rows=$(grep -c '^\(ok\|STALE\)' "$out" 2>/dev/null)
  assert_gt "$rows" 99 "SCOPE_LOOM: there are rows to inspect (got $rows)"
  tail_jsonl=$(grep '^\(ok\|STALE\)' "$out" | awk '{print $NF}' | grep -c '\.jsonl$')
  assert_eq "0" "$tail_jsonl" "no row's final field is an agent transcript (got $tail_jsonl)"
}

# The corpus-free tests below. Everything above needs a live unversioned session on this
# machine and SKIPs without one, and `skip` scores nothing — a corpus that moves reads as
# green with a smaller total rather than as lost coverage. These two plant their own.
#
# $1 projects dir · $2 session dir · $3 tag · $4 the log's contents ("" writes no log)
plant_synthetic_lane() {
  local projects="$1" session="$2" tag="$3" body="$4"
  mkdir -p "$session/builds" "$projects/proj/sess/subagents"
  [ -n "$body" ] && printf '%s\n' "$body" > "$session/builds/${tag}_LOG.md"
  # A lane is claimed by the session's PARENT/NAME pair, which is what the brief must name.
  local key
  key="$(basename "$(dirname "$session")")/$(basename "$session")"
  printf '{"message":{"role":"user","content":[{"type":"text","text":"[%s] thread brief, session %s"}]}}\n' \
    "$tag" "$key" > "$projects/proj/sess/subagents/agent-${tag}.jsonl"
}

# A session directory on a shared drive routinely holds a space — this weave's own does
# ("…/Shared drives/…") — and the three consumer-facing instructions told readers to take the
# row's last whitespace field. That yields a truncated path that still looks like a path.
# RED: read the field with `awk '{print $NF}'` (the second assertion is that control).
test_lane_stall_logpath_survives_a_space_in_the_session_path() {
  local session="$TMP_DIR/space dir/2026_10_12_SPACETEST"
  local projects="$TMP_DIR/projects-space"
  plant_synthetic_lane "$projects" "$session" "SPACELANE" \
    "## [2026-10-20 10:00:00] [SPACELANE] work"
  local out="$TMP_DIR/space.txt"
  CLAUDE_PROJECTS_DIR="$projects" bash "$LANE_STALL" "$session" --all >"$out" 2>"$out.err"
  assert_contains "[SPACELANE]" "$(cat "$out")" \
    "a session path containing a space still yields a lane"
  assert_eq "$session/builds/SPACELANE_LOG.md" "$(logpath_values "$out")" \
    "the documented reader recovers the whole path across the space"
  assert_neq "$session/builds/SPACELANE_LOG.md" \
    "$(grep '^\(ok\|STALE\)' "$out" | awk '{print $NF}')" \
    "the control: the last whitespace field truncates it, which is why nothing says to read it that way"
}

# A lane that stamps its headings and does not repeat its tag fell through both dating
# branches and read logpath=none while its log sat at builds/<TAG>_LOG.md — a FALSE reading
# in the one field a successor is told to trust. Its guard is in the same test: a log whose
# stamped headings belong to a DIFFERENT tag is not claimed by its filename, because dating
# it from another lane's entries would report a stale lane as fresh.
# RED: drop the LOGNAME_TAG branch (first pair); widen its guard to ignore seen_tags (second).
test_lane_stall_dates_a_log_whose_headings_are_stamped_but_untagged() {
  local session="$TMP_DIR/untagged/2026_10_12_UNTAGGED"
  local projects="$TMP_DIR/projects-untagged"
  plant_synthetic_lane "$projects" "$session" "UNTAGLANE" \
    "## [2026-10-20 10:00:00] Start
## [2026-10-20 10:05:00] Done"
  plant_synthetic_lane "$projects" "$session" "OTHERLANE" \
    "## [2026-10-20 11:00:00] [SOMEONEELSE] a later lane reused this file"
  local out="$TMP_DIR/untagged.txt"
  CLAUDE_PROJECTS_DIR="$projects" bash "$LANE_STALL" "$session" --all >"$out" 2>"$out.err"
  local dated
  dated=$(grep '\[UNTAGLANE\]' "$out" | grep -cE 'log= *[0-9]+m ')
  assert_eq "1" "$dated" "a stamped-but-untagged log dates its own lane (got $dated)"
  assert_eq "$session/builds/UNTAGLANE_LOG.md" \
    "$(grep '\[UNTAGLANE\]' "$out" | sed 's/.*logpath=//')" \
    "and hands over that log, not none"
  assert_eq "none" "$(grep '\[OTHERLANE\]' "$out" | sed 's/.*logpath=//')" \
    "a log whose stamps carry another lane's tag is not claimed by its filename"
}

# A reading whose horizon is unstated cannot be judged. "0 lanes seen" over 12 hours and over
# the session's whole life are different claims that printed identically. The whole line is
# pinned, not just `window=`: `lanes=` is the count a reader quotes and `threshold=` is what
# makes a STALE reading interpretable, and both were droppable with the suite green.
# `retired=` is pinned here for a reason of its own: a retired lane drops out of the default
# stale-only output, so without a count on this line a drained backlog and a marker that
# silently stopped matching read identically (¶INV_RETIRED_IS_NOT_SILENCED).
# RED: drop the window from the verdict line, or drop threshold=, lanes= or retired= from it.
test_lane_stall_states_the_window_it_searched() {
  local empty="$TMP_DIR/window-empty"
  mkdir -p "$empty"
  local out="$TMP_DIR/window.txt"
  run_lane_stall "$out" "$empty" 12 >/dev/null
  assert_eq "window=12h  threshold=30m  lanes=0  retired=0" "$(head -1 "$out")" \
    "the verdict line states the window, the threshold, the lane count and the retired count"
}

# A loom that runs longer than the old 12h default lost its own early lanes, silently. The
# window now sizes itself to the session directory's age.
# Measured 2026-10-21 on SCOPE_LOOM (92.6h old): 12h saw 13 lanes, the session's own age saw
# 137. Window width is not what this scan costs — 12h/400h/2000h/20000h measured
# 0.95s/9.10s/12.24s/9.87s, flat past the first — so there is no ceiling to trade against.
# RED: restore SINCE_HOURS=12 as the default.
test_lane_stall_default_window_covers_the_whole_session() {
  if [ ! -d "$SCOPE_SESSION" ]; then
    skip "the default window covers the session" "no corpus at $SCOPE_SESSION"
    return 0
  fi
  local narrow="$TMP_DIR/narrow.txt" auto="$TMP_DIR/auto.txt"
  run_lane_stall "$narrow" "$SCOPE_SESSION" 12 >/dev/null
  run_lane_stall_default_window "$auto" "$SCOPE_SESSION" >/dev/null
  local n_narrow n_auto
  n_narrow=$(grep -c '^\(ok\|STALE\)' "$narrow" 2>/dev/null)
  n_auto=$(grep -c '^\(ok\|STALE\)' "$auto" 2>/dev/null)
  # The control: a 12h window on this corpus really does see only a fraction, so the
  # comparison below is measuring the default and not an empty corpus.
  assert_gt "$n_narrow" 0 "SCOPE_LOOM: the 12h window sees something to improve on (got $n_narrow)"
  assert_gt "$n_auto" "$n_narrow" \
    "SCOPE_LOOM: the default window sees more lanes than 12h did ($n_auto vs $n_narrow)"
  assert_gt "$n_auto" 99 "SCOPE_LOOM: the default window reaches the session's early lanes (got $n_auto)"
}

# A session dir too young or unreadable to date falls back to the old default rather than to
# a zero-width window, which would report every weave clean.
test_lane_stall_default_window_has_a_floor() {
  local fresh="$TMP_DIR/fresh-session"
  mkdir -p "$fresh"
  local out="$TMP_DIR/fresh.txt"
  run_lane_stall_default_window "$out" "$fresh" >/dev/null
  assert_contains "window=12h" "$(cat "$out")" \
    "a just-created session dir floors the window at 12h, never 0"
}

# A lane that has ENDED and a lane that has DIED read the same on this sweep, because the one
# column that would separate them is unreachable: state=done fires only on a SubagentHandback
# call in the transcript tail, and whether a lane is granted that tool is a property of the
# session that dispatched it. Measured 2026-10-23 over the 47 sessions holding a lane since
# 2026-10-20: 33 granted it to every lane, 13 to none, 1 mixed, with identical SDK cliPrefix,
# agent types and dispatch shape on both sides — and 0 of 300 sampled main-loop transcripts
# define it at all, against a Bash control of 279. So a weave in the deny group reads done=0
# for every lane it will ever run. The lanes below therefore carry an explicit marker, and
# these tests exist to prove the marker and not the freshness bump is what produces the green.
#
# $1 projects dir · $2 session dir · $3 tag · $4 the log's contents
# Plants a lane whose transcript ENDS PARKED — an assistant turn with no tool_use and
# stop_reason end_turn, which is what a landed lane actually leaves behind here. The plain
# helper above leaves state=running, which cannot exercise the parked path these tests are about.
plant_parked_lane() {
  local projects="$1" session="$2" tag="$3" body="$4"
  mkdir -p "$session/builds" "$projects/proj/sess/subagents"
  [ -n "$body" ] && printf '%s\n' "$body" > "$session/builds/${tag}_LOG.md"
  local key
  key="$(basename "$(dirname "$session")")/$(basename "$session")"
  local t="$projects/proj/sess/subagents/agent-${tag}.jsonl"
  printf '{"message":{"role":"user","content":[{"type":"text","text":"[%s] thread brief, session %s"}]}}\n' \
    "$tag" "$key" > "$t"
  printf '{"message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"done, handing back in prose"}]}}\n' \
    >> "$t"
  # Backdated so the lane is stale on FRESHNESS, which is the only way the marker's effect can
  # be told apart from a fresh transcript's. A synthetic lane's transcript is otherwise seconds
  # old and reads ok no matter what the marker says.
  touch -t 202610201000 "$t"
}

# ACCEPTANCE 8, and the point of this file's retirement coverage. Two lanes identical in every
# input the sweep reads — same session, same parked transcript, same backdated mtime, same
# heading timestamp — differing ONLY in whether the heading carries a terminal token. If both
# arms behaved the same, the freshness bump would be producing the green and the marker would
# be doing nothing.
# RED: make is_stale ignore the disposition; or let a retirement work by bumping log_last.
test_lane_stall_retirement_marker_against_its_negative_control() {
  local session="$TMP_DIR/retire/2026_10_12_RETIRETEST"
  local projects="$TMP_DIR/projects-retire"
  plant_parked_lane "$projects" "$session" "CONTROLLANE" \
    "## [2026-10-20 10:00:00] [CONTROLLANE] wrapped up, see you"
  plant_parked_lane "$projects" "$session" "RETIREDLANE" \
    "## [2026-10-20 10:00:00] [RETIREDLANE] wrapped up, retired=landed"
  local out="$TMP_DIR/retire.txt"
  CLAUDE_PROJECTS_DIR="$projects" bash "$LANE_STALL" "$session" --all >"$out" 2>"$out.err"
  local rc_all=$?

  # The control arm: a tagged heading with no token leaves the lane exactly as it was.
  local ctl
  ctl=$(grep '\[CONTROLLANE\]' "$out")
  assert_contains "STALE" "$ctl" "the untokened control lane is still STALE"
  assert_contains "state=parked" "$ctl" "the untokened control lane still reads state=parked"
  assert_contains "retired=no" "$ctl" "the untokened control lane carries no disposition"

  # The subject arm: same inputs, one token.
  local ret
  ret=$(grep '\[RETIREDLANE\]' "$out")
  assert_contains "RETIRED" "$ret" "the tokened lane reads retired"
  assert_not_contains "STALE" "$ret" "the tokened lane is no longer STALE"
  assert_contains "retired=landed" "$ret" "the tokened lane carries its disposition"
  # It is still PRINTED, with its state intact: retirement answers a different question from
  # state, and hiding the row would hide the lane that died too (¶INV_RETIRED_IS_NOT_SILENCED).
  assert_contains "state=parked" "$ret" "a retired lane still reports the state it ended in"

  assert_eq "1" "$(grep -c '^RETIRED' "$out")" "exactly one row reads RETIRED"
  assert_contains "retired=1" "$(head -1 "$out")" "the verdict line counts the retirement"

  # The default (stale-only) output is where the backlog actually drains: the retired lane is
  # gone from it and the control lane is not.
  local plain="$TMP_DIR/retire-plain.txt"
  CLAUDE_PROJECTS_DIR="$projects" bash "$LANE_STALL" "$session" >"$plain" 2>"$plain.err"
  local rc_plain=$?
  assert_contains "[CONTROLLANE]" "$(cat "$plain")" \
    "the un-retired lane still appears in the default output"
  assert_not_contains "[RETIREDLANE]" "$(cat "$plain")" \
    "the retired lane has dropped out of the default output"
  assert_eq "3" "$rc_plain" "one lane still stale, so the bare exit status is still 3"
  assert_eq "3" "$rc_all" "--all reports the same verdict"

  # And once the control lane is retired too, the sweep goes clean — by the marker, with no
  # threshold, window or age touched.
  printf '## [2026-10-20 10:30:00] [CONTROLLANE] retired=abandoned\n' \
    >> "$session/builds/CONTROLLANE_LOG.md"
  local drained="$TMP_DIR/retire-drained.txt"
  CLAUDE_PROJECTS_DIR="$projects" bash "$LANE_STALL" "$session" >"$drained" 2>"$drained.err"
  local rc_drained=$?
  assert_eq "0" "$rc_drained" "with both lanes retired the bare exit status is 0"
  assert_contains "retired=2" "$(cat "$drained")" \
    "the drained sweep still states how many lanes it retired, rather than falling silent"
}

# The freshness half of acceptance 8, isolated: an untokened heading written NOW really does
# turn a stale lane green, which is why the test above holds freshness fixed. This arm proves
# that green is worth exactly one threshold — the same lane, judged against a 0m threshold it
# can no longer satisfy, is STALE again, while a retired lane is unaffected by any threshold.
# RED: implement retirement as a log_last bump.
test_lane_stall_a_log_write_buys_only_one_thresholds_worth_of_freshness() {
  local session="$TMP_DIR/freshbump/2026_10_12_FRESHBUMP"
  local projects="$TMP_DIR/projects-freshbump"
  plant_parked_lane "$projects" "$session" "BUMPLANE" ""
  plant_parked_lane "$projects" "$session" "TOKENLANE" ""
  # Both get a heading stamped NOW. Only one carries a token.
  local stamp
  stamp=$(date '+%Y-%m-%d %H:%M:%S')
  printf '## [%s] [BUMPLANE] still going\n' "$stamp" > "$session/builds/BUMPLANE_LOG.md"
  printf '## [%s] [TOKENLANE] retired=landed\n' "$stamp" > "$session/builds/TOKENLANE_LOG.md"

  local wide="$TMP_DIR/bump-wide.txt"
  CLAUDE_PROJECTS_DIR="$projects" bash "$LANE_STALL" "$session" --minutes 30 --all >"$wide" 2>"$wide.err"
  assert_contains "ok" "$(grep '\[BUMPLANE\]' "$wide")" \
    "a heading written now turns the untokened lane green on freshness alone"
  assert_contains "RETIRED" "$(grep '\[TOKENLANE\]' "$wide")" \
    "the tokened lane reads retired in the same run"

  # Now judge the identical fixture against a threshold its fresh heading cannot clear. This
  # is the "and then returns" half, without waiting 30 minutes for it.
  local tight="$TMP_DIR/bump-tight.txt"
  CLAUDE_PROJECTS_DIR="$projects" bash "$LANE_STALL" "$session" --minutes 0 --all >"$tight" 2>"$tight.err"
  assert_contains "STALE" "$(grep '\[BUMPLANE\]' "$tight")" \
    "the freshness-only lane returns to STALE once the threshold passes"
  assert_contains "state=parked" "$(grep '\[BUMPLANE\]' "$tight")" \
    "and it returns to state=parked specifically"
  assert_contains "RETIRED" "$(grep '\[TOKENLANE\]' "$tight")" \
    "the retired lane is unmoved by the threshold, because no threshold produced its green"
  assert_not_contains "STALE" "$(grep '\[TOKENLANE\]' "$tight")" \
    "a retirement is read, not computed from an age"
}

# The disposition is a CLOSED set, and a bare "retired" is not a marker. A close-out consumes
# it in the order marker -> ticket -> worktree; a lane that ended without landing is the one
# whose tree may still hold uncommitted work, so one undifferentiated token is what makes a
# close-out delete it. Each accepted word is asserted, because a typo'd regex alternative
# would otherwise sit green behind the one word the tests above happen to use.
# RED: relax the pattern to \bretired\b, or drop an alternative from the closed set.
test_lane_stall_retirement_disposition_is_a_closed_set() {
  local session="$TMP_DIR/disp/2026_10_12_DISPTEST"
  local projects="$TMP_DIR/projects-disp"
  plant_parked_lane "$projects" "$session" "LANDEDONE" \
    "## [2026-10-20 10:00:00] [LANDEDONE] retired=landed"
  plant_parked_lane "$projects" "$session" "NOTHINGONE" \
    "## [2026-10-20 10:00:00] [NOTHINGONE] retired=ended-nothing-to-land"
  plant_parked_lane "$projects" "$session" "ABANDONONE" \
    "## [2026-10-20 10:00:00] [ABANDONONE] retired=abandoned"
  plant_parked_lane "$projects" "$session" "BARELANE" \
    "## [2026-10-20 10:00:00] [BARELANE] retired"
  plant_parked_lane "$projects" "$session" "MADEUPLANE" \
    "## [2026-10-20 10:00:00] [MADEUPLANE] retired=finished"
  local out="$TMP_DIR/disp.txt"
  CLAUDE_PROJECTS_DIR="$projects" bash "$LANE_STALL" "$session" --all >"$out" 2>"$out.err"

  assert_contains "retired=landed" "$(grep '\[LANDEDONE\]' "$out")" "landed is a disposition"
  assert_contains "retired=ended-nothing-to-land" "$(grep '\[NOTHINGONE\]' "$out")" \
    "ended-nothing-to-land is a disposition"
  assert_contains "retired=abandoned" "$(grep '\[ABANDONONE\]' "$out")" "abandoned is a disposition"
  # The two refusals. A conductor who writes a bare token has not said what to do with the
  # tree, so the lane stays on the sweep rather than quietly retiring under a default.
  assert_contains "STALE" "$(grep '\[BARELANE\]' "$out")" \
    "a bare 'retired' with no disposition does not retire a lane"
  assert_contains "STALE" "$(grep '\[MADEUPLANE\]' "$out")" \
    "a disposition outside the closed set does not retire a lane"
  assert_eq "3" "$(grep -c '^RETIRED' "$out")" "exactly the three valid dispositions retired"
}

# 45 of 117 lanes on one measured weave had no log of their own, so a mechanism that needs an
# existing log to retire into covers 72 of 117. Such a lane is GIVEN builds/<TAG>_LOG.md
# holding only its retirement — a create, so no evidence is rewritten — and the sweep already
# dates a tagless log from its own filename. The heading must declare its own poverty, because
# logpath then points at a file that briefs a successor on nothing
# (¶INV_LOOM_HANDS_OVER_A_PATH_NOT_AN_ID), and the test pins that wording is carried through.
# RED: bind the retirement only inside the tagged branch, skipping the LOGNAME_TAG path.
test_lane_stall_retires_a_lane_that_never_wrote_a_log() {
  local session="$TMP_DIR/nolog/2026_10_12_NOLOGTEST"
  local projects="$TMP_DIR/projects-nolog"
  plant_parked_lane "$projects" "$session" "NEVERLOGGED" ""
  plant_parked_lane "$projects" "$session" "STILLOPEN" ""
  # The whole file, created for this purpose, naming no tag in its heading.
  printf '## retired=ended-nothing-to-land — no own log; this line is the whole record\n' \
    > "$session/builds/NEVERLOGGED_LOG.md"
  local out="$TMP_DIR/nolog.txt"
  CLAUDE_PROJECTS_DIR="$projects" bash "$LANE_STALL" "$session" --all >"$out" 2>"$out.err"

  local row
  row=$(grep '\[NEVERLOGGED\]' "$out")
  assert_contains "RETIRED" "$row" "a lane with no log of its own retires from a given one"
  assert_contains "retired=ended-nothing-to-land" "$row" "and carries the disposition it was given"
  assert_eq "$session/builds/NEVERLOGGED_LOG.md" "$(printf '%s' "$row" | sed 's/.*logpath=//')" \
    "and hands over that file as its path"
  assert_contains "no own log" "$(cat "$session/builds/NEVERLOGGED_LOG.md")" \
    "the control: the given heading declares its own poverty, since the path briefs on nothing else"
  # The control that the create retired one lane and not the session.
  assert_contains "STALE" "$(grep '\[STILLOPEN\]' "$out")" \
    "the lane that was given nothing is untouched"
}

# An untimestamped heading still retires its lane. `engine log` strips the timestamp from any
# heading opening with "[", which is every heading a lane writes under
# ¶INV_LOOM_AGENTS_NAMED_BY_THREAD — so a marker that needed a stamp would be rejected in the
# form a lane actually writes it.
# RED: bind the retirement after the `if last_ts is None: continue` branch.
test_lane_stall_retires_on_an_unstamped_heading() {
  local session="$TMP_DIR/unstamped/2026_10_12_UNSTAMPEDTEST"
  local projects="$TMP_DIR/projects-unstamped"
  plant_parked_lane "$projects" "$session" "UNSTAMPED" \
    "## [UNSTAMPED] wrapped up, retired=landed"
  local out="$TMP_DIR/unstamped.txt"
  CLAUDE_PROJECTS_DIR="$projects" bash "$LANE_STALL" "$session" --all >"$out" 2>"$out.err"
  assert_contains "retired=landed" "$(grep '\[UNSTAMPED\]' "$out")" \
    "a heading with no timestamp of its own still retires its lane"
  assert_not_contains "STALE" "$(grep '\[UNSTAMPED\]' "$out")" \
    "and the lane leaves the stale set"
}

# The sweep stays READ-ONLY: it is specified never to touch a lane, a transcript or the log,
# and retirement must not make it a writer. Pinned as a mtime+content comparison across a run
# that retires a lane, because a writer would be an easy and invisible way to implement this.
# RED: have the sweep stamp, rewrite or normalise the marker it just read.
test_lane_stall_retirement_leaves_the_log_untouched() {
  local session="$TMP_DIR/readonly/2026_10_12_READONLYTEST"
  local projects="$TMP_DIR/projects-readonly"
  plant_parked_lane "$projects" "$session" "RODLANE" \
    "## [2026-10-20 10:00:00] [RODLANE] retired=landed"
  local log="$session/builds/RODLANE_LOG.md"
  local before_sum before_mtime
  before_sum=$(shasum "$log" | awk '{print $1}')
  before_mtime=$(stat -f %m "$log")
  local out="$TMP_DIR/readonly.txt"
  CLAUDE_PROJECTS_DIR="$projects" bash "$LANE_STALL" "$session" --all >"$out" 2>"$out.err"
  # The control: the run really did read the marker, so the untouched file below is evidence
  # about a run that acted on it rather than about a run that did nothing.
  assert_contains "RETIRED" "$(grep '\[RODLANE\]' "$out")" \
    "the control: this run did retire the lane"
  assert_eq "$before_sum" "$(shasum "$log" | awk '{print $1}')" \
    "the log's contents are unchanged by the sweep"
  assert_eq "$before_mtime" "$(stat -f %m "$log")" \
    "and its mtime is unchanged, so nothing was rewritten in place"
}

# A retirement is a lane declaring ITS OWN end, bound to the heading's leading tag only. Most
# retirement headings land in a SHARED log, where a lane routinely names another one in the
# same heading ("handing [OTHER] the rest"), and binding to every tag on the line would let one
# lane's retirement silently retire a lane that is still running — or one that died, which is
# the row this sweep exists to show. Over-retiring is the one error it cannot afford.
# RED: bind the retirement to every tag in heading_tags instead of the leading one.
test_lane_stall_retirement_binds_only_to_the_heading_it_opens() {
  local session="$TMP_DIR/mention/2026_10_12_MENTIONTEST"
  local projects="$TMP_DIR/projects-mention"
  plant_parked_lane "$projects" "$session" "DECLARER" ""
  plant_parked_lane "$projects" "$session" "MENTIONED" ""
  # One shared log, one heading, two tags — and only the first one is retiring.
  printf '## [2026-10-20 10:00:00] [DECLARER] handing [MENTIONED] the rest, retired=landed\n' \
    > "$session/builds/SHARED_LOG.md"
  local out="$TMP_DIR/mention.txt"
  CLAUDE_PROJECTS_DIR="$projects" bash "$LANE_STALL" "$session" --all >"$out" 2>"$out.err"
  assert_contains "retired=landed" "$(grep '\[DECLARER\]' "$out")" \
    "the lane whose heading it is retires"
  # The control, and the whole point: the lane that was merely named does NOT.
  assert_contains "STALE" "$(grep '\[MENTIONED\]' "$out")" \
    "a lane merely NAMED in another lane's retirement heading is not retired"
  assert_contains "retired=no" "$(grep '\[MENTIONED\]' "$out")" \
    "and it carries no disposition it never declared"
  assert_eq "1" "$(grep -c '^RETIRED' "$out")" "one heading retired one lane, not two"
}

# The conductor's log at the session root names every lane, and its unstamped headings inherit
# the previous stamp. Newest-mention-wins let a conductor note about a lane outrank the lane's
# own log, so the row handed a successor the conductor's whole log and dated the lane by the
# conductor's clock. Three layouts of a lane's own log, each one older than the conductor's
# mention of it and than a shared builds/ log's, plus a lane the conductor alone mentions.
# RED: rank a dating by its timestamp alone (the shared log wins); let a session-root log date
# a lane (the conductor's log wins, and becomes the orphan's logpath).
test_lane_stall_prefers_the_lanes_own_log_over_the_conductors() {
  local session="$TMP_DIR/ownlog/2026_10_12_OWNLOG"
  local projects="$TMP_DIR/projects-ownlog"
  plant_synthetic_lane "$projects" "$session" "FLATLANE" \
    "## [2026-10-20 10:20:00] [FLATLANE] docker build running"
  plant_synthetic_lane "$projects" "$session" "BUILDLANE" ""
  plant_synthetic_lane "$projects" "$session" "SUBDIRLANE" ""
  plant_synthetic_lane "$projects" "$session" "ORPHANLANE" ""
  printf '## [2026-10-20 10:20:00] [BUILDLANE] docker build running\n' \
    > "$session/builds/BUILDLANE_BUILD_LOG.md"
  mkdir -p "$session/builds/subdirlane"
  printf '## [2026-10-20 10:20:00] [SUBDIRLANE] docker build running\n' \
    > "$session/builds/subdirlane/SUBDIRLANE_BUILD_LOG.md"
  printf '%s\n' \
    "## [2026-10-20 10:30:00] Overseer poll answered" \
    "## [FLATLANE] [BUILDLANE] [SUBDIRLANE] still building, per their logs" \
    "## [2026-10-20 10:31:00] dispatched [ORPHANLANE]" \
    > "$session/LOOM_LOG.md"
  printf '## [2026-10-20 10:40:00] wave notes: [FLATLANE] and [BUILDLANE] share a fixture\n' \
    > "$session/builds/WAVE_LOG.md"
  local out="$TMP_DIR/ownlog.txt"
  CLAUDE_PROJECTS_DIR="$projects" bash "$LANE_STALL" "$session" --all >"$out" 2>"$out.err"
  local own_age
  own_age=$(python3 -c 'import time,datetime;print(round((time.time()-datetime.datetime(2026,10,20,10,20).timestamp())/60))')
  local tag want row got_age
  for tag in FLATLANE BUILDLANE SUBDIRLANE; do
    case "$tag" in
      FLATLANE) want="$session/builds/FLATLANE_LOG.md" ;;
      BUILDLANE) want="$session/builds/BUILDLANE_BUILD_LOG.md" ;;
      SUBDIRLANE) want="$session/builds/subdirlane/SUBDIRLANE_BUILD_LOG.md" ;;
    esac
    row=$(grep "\[$tag\]" "$out")
    assert_eq "$want" "$(printf '%s' "$row" | sed 's/.*logpath=//')" \
      "$tag: the lane's own log is handed over, not the conductor's"
    got_age=$(printf '%s' "$row" | sed -E 's/.* log= *([0-9]+)m.*/\1/')
    assert_eq "1" "$(( got_age - own_age <= 1 && own_age - got_age <= 1 ))" \
      "$tag: the log age is read from that same log (got ${got_age}m, own log ${own_age}m)"
  done
  assert_eq "0" "$(logpath_values "$out" | grep -c '/LOOM_LOG\.md$')" \
    "the conductor's log is never any lane's logpath"
  assert_eq "none" "$(grep '\[ORPHANLANE\]' "$out" | sed 's/.*logpath=//')" \
    "a lane only the conductor mentions has no log of its own"
}

# Older looms kept a lane's log at the session root as <TAG>_LOG.md, beside the conductor's.
# Skipping every root log blanked those lanes to logpath=none while their logs existed. A root
# log the lane owns by name dates it; the conductor's log there still dates nobody.
# RED: skip every log at the session root, own or not.
test_lane_stall_dates_a_lanes_own_log_at_the_session_root() {
  local session="$TMP_DIR/rootlog/2026_10_07_ROOTLOG"
  local projects="$TMP_DIR/projects-rootlog"
  plant_synthetic_lane "$projects" "$session" "ROOTLANE" ""
  plant_synthetic_lane "$projects" "$session" "ROOTMTIME" ""
  printf '## [2026-10-20 10:20:00] [ROOTLANE] work\n' > "$session/ROOTLANE_LOG.md"
  printf '## [ROOTMTIME] work\n' > "$session/ROOTMTIME_LOG.md"
  printf '## [2026-10-20 10:30:00] [ROOTLANE] [ROOTMTIME] noted by the conductor\n' \
    > "$session/LOOM_LOG.md"
  local out="$TMP_DIR/rootlog.txt"
  CLAUDE_PROJECTS_DIR="$projects" bash "$LANE_STALL" "$session" --all >"$out" 2>"$out.err"
  assert_eq "$session/ROOTLANE_LOG.md" "$(grep '\[ROOTLANE\]' "$out" | sed 's/.*logpath=//')" \
    "a stamped root <TAG>_LOG.md is the lane's own log"
  assert_eq "$session/ROOTMTIME_LOG.md" "$(grep '\[ROOTMTIME\]' "$out" | sed 's/.*logpath=//')" \
    "an unstamped root <TAG>_LOG.md still dates its lane from its mtime"
  assert_contains "m~" "$(grep '\[ROOTMTIME\]' "$out" | sed 's/.* log= *//')" \
    "and that reading is marked approximate"
  assert_eq "0" "$(logpath_values "$out" | grep -c '/LOOM_LOG\.md$')" \
    "the conductor's root log is still nobody's logpath"
}

run_discovered_tests
