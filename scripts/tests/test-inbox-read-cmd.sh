#!/bin/bash
# test-inbox-read-cmd.sh — ¶CMD_READ_INBOX_CHANNEL: the own-comment exclusion, by construction.
#
# The exclusion vocabulary used to be one list written five times across two skills. Two of the
# copies disagreed: `/groom` posts a `⏳ marinating` reply and `/intake`'s filter did not list the
# marker, so groom's own replies drained back as fresh human feedback. These checks assert the
# vocabulary now exists exactly ONCE, that the one copy is the one that RUNS, and that neither
# caller can read an inbox channel around it.
#
# The filter program is extracted from the command file and executed, so a check here fails when
# the shipped program is wrong — not when a prose paraphrase of it is.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENGINE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CMD_FILE="$ENGINE_DIR/.directives/commands/CMD_READ_INBOX_CHANNEL.md"
INDEX_FILE="$ENGINE_DIR/.directives/COMMANDS.md"
GROOM="$ENGINE_DIR/skills/groom/SKILL.md"
INTAKE="$ENGINE_DIR/skills/intake/SKILL.md"

FENCE_TAG='own-comment-filter'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ------------------------------------------------------------------
# The fixture: an `engine project fetch --out` payload, shaped from
# scripts/linear-lib.sh (comment TREES with `children`) rather than guessed.
#
# Survivors by design: c3, c8, c10, c12, c13. Each is a named divergence input —
#   c3  fails this suite if the filter PRUNES a subtree instead of flattening it
#   c8  fails it if a reply-less human root is over-dropped (a sibling of c1/c4/c5/c7)
#   c10 fails it if the marker search stops at direct children: c9's only marker (c11) sits under
#       the human reply c10, so c9 is withheld and c10 survives
#   c12 fails it if any root with any reply is withheld: c12's replies are all human, so c12 and
#       c13 survive
#   c14 pins the accepted cost: its human reply c15 opens with the marker word `→`, so the whole
#       thread is withheld and nothing from it drains
# Withheld roots by design: c9 and c14 (above) and c1 and c5, which are human drops whose thread carries a marker-led reply
#   (c2, c6), so the thread is dispositioned and the root is not new signal.
# Exclusions by design: c2 (the live leak), c4, c6, c7, c11, c15.
# ------------------------------------------------------------------
write_payload() {
  cat > "$TMP/payload.json" <<'JSON'
{
  "project": { "name": "Product: Intake System" },
  "structure": { "channels": [ { "identifier": "ENG-9001" } ] },
  "tickets": [
    {
      "identifier": "ENG-9001",
      "title": "Observed problems",
      "comments": [
        {
          "id": "c1", "author": "Dana", "createdAt": "2026-10-18T09:00:00Z",
          "quotedText": null, "resolvedAt": null,
          "body": "The Policies tab shows the wrong carrier on claim 4821.",
          "children": [
            {
              "id": "c2", "author": "Yarik", "createdAt": "2026-10-19T09:00:00Z",
              "quotedText": null, "resolvedAt": null,
              "body": "⏳ marinating — real, not yet a chunk worth tracking; one report, no second sighting.",
              "children": [
                {
                  "id": "c3", "author": "Dana", "createdAt": "2026-10-20T08:00:00Z",
                  "quotedText": null, "resolvedAt": null,
                  "body": "Still happening this morning, two more claims.",
                  "children": []
                }
              ]
            }
          ]
        },
        {
          "id": "c4", "author": "Yarik", "createdAt": "2026-10-19T10:00:00Z",
          "quotedText": null, "resolvedAt": null,
          "body": "filed as ENG-4412",
          "children": []
        },
        {
          "id": "c5", "author": "Rob", "createdAt": "2026-10-18T11:00:00Z",
          "quotedText": null, "resolvedAt": null,
          "body": "Export button does nothing in Safari.",
          "children": [
            {
              "id": "c6", "author": "Yarik", "createdAt": "2026-10-19T11:00:00Z",
              "quotedText": null, "resolvedAt": null,
              "body": "👀 claimed by Rob",
              "children": []
            }
          ]
        },
        {
          "id": "c7", "author": "Dana", "createdAt": "2026-10-18T12:00:00Z",
          "quotedText": "the quoted description text", "resolvedAt": null,
          "body": "This line is wrong.",
          "children": []
        },
        {
          "id": "c8", "author": "Dana", "createdAt": "2026-10-18T13:00:00Z",
          "quotedText": null, "resolvedAt": null,
          "body": "Dashboard totals are off by one on the Tuesday report.",
          "children": []
        },
        {
          "id": "c9", "author": "Dana", "createdAt": "2026-10-18T14:00:00Z",
          "quotedText": null, "resolvedAt": null,
          "body": "Claim list pagination skips page 3.",
          "children": [
            {
              "id": "c10", "author": "Rob", "createdAt": "2026-10-18T15:00:00Z",
              "quotedText": null, "resolvedAt": null,
              "body": "Same here, page 3 is empty for me too.",
              "children": [
                {
                  "id": "c11", "author": "Yarik", "createdAt": "2026-10-19T14:00:00Z",
                  "quotedText": null, "resolvedAt": null,
                  "body": "⏳ marinating — two sightings, still no repro.",
                  "children": []
                }
              ]
            }
          ]
        },
        {
          "id": "c12", "author": "Dana", "createdAt": "2026-10-18T16:00:00Z",
          "quotedText": null, "resolvedAt": null,
          "body": "Search ignores the date filter.",
          "children": [
            {
              "id": "c13", "author": "Rob", "createdAt": "2026-10-18T17:00:00Z",
              "quotedText": null, "resolvedAt": null,
              "body": "Confirmed on staging as well.",
              "children": []
            }
          ]
        },
        {
          "id": "c14", "author": "Dana", "createdAt": "2026-10-18T18:00:00Z",
          "quotedText": null, "resolvedAt": null,
          "body": "Totals wrong on report",
          "children": [
            {
              "id": "c15", "author": "Rob", "createdAt": "2026-10-18T19:00:00Z",
              "quotedText": null, "resolvedAt": null,
              "body": "→ same thing on the Friday export, attaching a screenshot.",
              "children": []
            }
          ]
        }
      ]
    }
  ]
}
JSON
}

# Extract the one shipped filter program from the command file's tagged fence.
extract_filter() {
  [ -f "$CMD_FILE" ] || return 1
  awk -v tag="$FENCE_TAG" '
    $0 ~ ("^```jq[[:space:]]+" tag "[[:space:]]*$") { inside = 1; next }
    inside && /^```[[:space:]]*$/ { exit }
    inside { print }
  ' "$CMD_FILE"
}

# Run the shipped filter over the fixture; prints surviving comment ids, one per line.
# Exit status is the filter's own, read directly (never through a pipe).
run_filter() {
  local prog="$TMP/filter.jq" out="$TMP/out.json" rc
  extract_filter > "$prog" 2>/dev/null
  if [ ! -s "$prog" ]; then
    echo "__NO_FILTER__"
    return 1
  fi
  write_payload
  jq -f "$prog" "$TMP/payload.json" > "$out" 2>"$TMP/err.txt"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "__FILTER_ERROR__ $(head -3 "$TMP/err.txt" | tr '\n' ' ')"
    return "$rc"
  fi
  jq -r '.[].id' "$out"
}

# ============================================================
# The command exists and its program runs
# ============================================================

test_01_command_file_exists() {
  assert_file_exists "$CMD_FILE" "¶CMD_READ_INBOX_CHANNEL command file exists"
}

test_02_filter_program_is_extractable_and_runs() {
  local prog
  prog="$(extract_filter 2>/dev/null)"
  assert_not_empty "$prog" "the command ships a runnable jq fence tagged '$FENCE_TAG'"
}

# An absent or erroring filter prints a sentinel. Every exclusion check below asserts the
# instrument RAN before it reads an absence from it — otherwise "c2 is not in the output"
# is satisfied by there being no output, and the assertion's two sides cannot diverge.
assert_filter_ran() {
  local ids="$1" msg="$2"
  case "$ids" in
    __NO_FILTER__*|__FILTER_ERROR__*)
      fail "$msg — the filter did not run" "a filter run" "$ids"
      return 1
      ;;
  esac
  return 0
}

# ============================================================
# The live leak
# ============================================================

test_03_marinating_reply_is_excluded() {
  local ids
  ids="$(run_filter)"
  assert_filter_ran "$ids" "a '⏳ marinating' reply is excluded from the drained signal" || return
  assert_not_contains "c2" "$ids" "a '⏳ marinating' reply is excluded from the drained signal"
}

test_04_markers_the_intake_filter_already_knew_are_still_excluded() {
  local ids
  ids="$(run_filter)"
  assert_filter_ran "$ids" "markers intake already knew are excluded" || return
  assert_not_contains "c4" "$ids" "a 'filed as …' reply is excluded"
  assert_not_contains "c6" "$ids" "a '👀 claimed …' reply is excluded at depth"
}

test_05_anchored_comment_is_excluded() {
  local ids
  ids="$(run_filter)"
  assert_filter_ran "$ids" "an anchored comment is excluded" || return
  assert_not_contains "c7" "$ids" "an anchored comment (quotedText != null) is excluded"
}

# ============================================================
# The divergence inputs — what makes the checks above able to fail
# ============================================================

test_06_reply_less_human_root_survives_and_marked_thread_root_is_withheld() {
  local ids
  ids="$(run_filter)"
  assert_contains "c8" "$ids" "a plain human root with no replies survives the filter"
  assert_eq "0" "$(printf '%s\n' "$ids" | grep -cx 'c1')" "a human root whose thread carries a marker-led reply is withheld (disposition is a thread property; exact-id match, c1 is a prefix of c10-c15)"
}

test_07_human_reply_under_an_own_comment_survives() {
  local ids
  ids="$(run_filter)"
  assert_contains "c3" "$ids" "a human reply nested UNDER an own-comment survives (flatten, never prune)"
}

test_08_root_whose_only_reply_is_an_own_comment_is_withheld() {
  local ids
  ids="$(run_filter)"
  assert_not_contains "c5" "$ids" "a human root whose only reply is an own-comment is withheld, and its reply is excluded"
  assert_not_contains "c6" "$ids" "the own-comment reply under c5 stays excluded"
}

test_09_exactly_the_five_human_nodes_survive() {
  local n
  n="$(run_filter | grep -c '^c[0-9]*$')"
  assert_eq "5" "$n" "exactly five nodes survive (c3, c8, c10, c12, c13) — no over-drop, no under-drop"
}

test_09a_marker_under_a_human_reply_withholds_the_root() {
  local ids
  ids="$(run_filter)"
  assert_filter_ran "$ids" "a marker at depth 2 withholds its root" || return
  assert_not_contains "c9" "$ids" "a root whose only marker sits under a human reply is withheld (whole subtree, not direct children)"
  assert_contains "c10" "$ids" "the human reply that carries the nested marker still drains"
}

test_09b_root_with_only_human_replies_survives() {
  local ids
  ids="$(run_filter)"
  assert_filter_ran "$ids" "a root with only human replies survives" || return
  assert_contains "c12" "$ids" "a root whose replies are all human is not withheld"
  assert_contains "c13" "$ids" "its human reply drains too"
}

test_09c_human_reply_opening_with_a_marker_word_withholds_its_whole_thread() {
  local ids
  ids="$(run_filter)"
  assert_filter_ran "$ids" "the accepted cost is pinned" || return
  assert_not_contains "c14" "$ids" "the root of a thread whose human reply opens with '→' is withheld"
  assert_not_contains "c15" "$ids" "the human reply opening with '→' is itself excluded"
}

test_09d_open_threads_flags_dispositioned_both_ways() {
  local out
  extract_filter > "$TMP/filter.jq"; write_payload
  out="$(INBOX_WALK=open-threads jq -c -f "$TMP/filter.jq" "$TMP/payload.json")"
  assert_eq "false" "$(echo "$out" | jq -r '.[]|select(.id=="c12").dispositioned')" "an undispositioned open root is listed with dispositioned=false"
  assert_eq "true" "$(echo "$out" | jq -r '.[]|select(.id=="c9").dispositioned')" "a root with a nested marker is listed with dispositioned=true"
  assert_eq "true" "$(echo "$out" | jq -r '.[]|select(.id=="c14").dispositioned')" "the withheld '→'-reply thread is listed dispositioned=true (reads as groomed though a human wrote it)"
}

# ============================================================
# Single-sourcing
# ============================================================

# Two contracts share one vocabulary, and only one of them may exist twice over.
#
#   THE READER-SIDE RULE — what a read must not count. It exists as the tagged jq fence,
#   so the detector is the fence opener, and exactly one file may carry it.
#
#   THE WRITER-SIDE LISTS — what each skill stamps. These are deliberately PRESERVED in
#   their skills; collapsing them into the reader-side rule destroys the declaration the
#   leak fix depends on. What is checked is that they AGREE with the vocabulary the fence
#   defines, not that they are absent.
#
# So a skill naming a marker at the point it posts it is correct and is not flagged.
# `→` and `candidate` are outside the scan tokens — both saturate ordinary prose. Scope is
# the engine; `~/.claude/data/*/sessions` holds historical run logs, not the system.

# Files carrying the executable set.
find_fence_files() {
  grep -rlF '```jq own-comment-filter' "$ENGINE_DIR" --include="*.md" 2>/dev/null
}

# The vocabulary the command defines, read from the program that applies it rather than
# from a second list written here — a copy in this test would be the same defect.
canonical_markers() {
  extract_filter | awk '
    /^def own_comment_markers:/ { inside = 1; next }
    inside && /^\];/            { exit }
    inside && /^[[:space:]]*"/ {
      line = $0
      sub(/^[^"]*"/, "", line)
      sub(/".*$/, "", line)
      print line
    }
  '
}

# Marker strings a skill STAMPS, taken from its writer-side lists. The shape is a
# backticked marker at the head of its own value: `filed as ENG-XXX`, `⏳ marinating`.
# Only the distinctive tokens are scanned; `→` and `candidate` saturate ordinary prose.
writer_side_markers() {
  local f="$1" m
  for m in '👀 claimed' '🔎 needs-triage' '✅ result' '⏳ marinating' 'shipped in' 'filed as' 'seems like'; do
    grep -qF "\`$m" "$f" && echo "$m"
  done
}

test_10_the_executable_set_exists_in_exactly_one_file() {
  local files n
  files="$(find_fence_files)"
  # Positive control, same invocation: the detector must find the command file.
  assert_contains "$(basename "$CMD_FILE")" "$files" \
    "positive control — the fence detector finds the command file"
  n="$(printf '%s\n' "$files" | grep -c .)"
  assert_eq "1" "$n" "the filter program exists in exactly one file (found: $(printf '%s' "$files" | tr '\n' ' '))"
}

# The writer-side marker lists are a SEPARATE contract from the reader-side exclusion and
# are deliberately preserved, not merged — one declares what a skill stamps, the other what
# a read must not count. What they must share is the vocabulary, so the check is agreement
# with the command's table, never the absence of a writer-side list.
# The one comparison, so the real check and its positive control run the SAME code.
# $1 = the table to compare against (newline-separated). Reads the writer sites from
# $GROOM and $INTAKE. Prints each stamped marker the table does not carry.
markers_missing_from_table() {
  local table="$1" m
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    printf '%s\n' "$table" | grep -qF "$m" || printf '%s\n' "$m"
  done < <({ writer_side_markers "$GROOM"; writer_side_markers "$INTAKE"; } | sort -u)
}

test_11_every_writer_side_marker_is_in_the_canonical_table() {
  local canon missing
  canon="$(canonical_markers)"

  # The table must parse and be non-empty, or every comparison below is vacuous.
  assert_contains "⏳ marinating" "$canon" \
    "positive control — the canonical table parses and carries '⏳ marinating'"
  assert_not_empty "$canon" "the canonical table is non-empty"

  missing="$(markers_missing_from_table "$canon" | tr '\n' ' ')"
  assert_eq "" "${missing% }" "every marker /groom and /intake stamp is in the canonical table"
}

# The positive control for test_11, running the SAME comparison against a DEFICIENT table.
#
# This is the divergence input named and executed rather than described: strip the marker
# that actually leaked out of the table, and the comparison must name it. Without this, a
# comparison that silently found nothing would read identically to one that found nothing
# because everything agrees — which is how the original defect survived two skills.
test_12_the_comparison_catches_a_marker_the_table_lacks() {
  local deficient missing
  deficient="$(canonical_markers | grep -vF '⏳ marinating')"

  assert_not_contains "⏳ marinating" "$deficient" "the deficient table really lacks the marker"
  assert_not_empty "$deficient" "the deficient table still carries the other markers"

  missing="$(markers_missing_from_table "$deficient")"
  assert_contains "⏳ marinating" "$missing" \
    "positive control — the comparison names '⏳ marinating' when the table lacks it"
}

test_13_neither_caller_carries_the_filter_program() {
  local fences
  fences="$(find_fence_files)"
  assert_not_contains "skills/groom/SKILL.md" "$fences" "/groom does not carry the filter program"
  assert_not_contains "skills/intake/SKILL.md" "$fences" "/intake does not carry the filter program"
}

# ============================================================
# Bypass — can a caller read a channel without the command?
# ============================================================

test_14_neither_caller_fetches_without_citing_the_command() {
  local f
  for f in "$GROOM" "$INTAKE"; do
    if grep -qF 'engine project fetch' "$f"; then
      if grep -qF 'CMD_READ_INBOX_CHANNEL' "$f"; then
        pass "$(basename "$(dirname "$f")") fetches a channel and cites ¶CMD_READ_INBOX_CHANNEL"
      else
        fail "$(basename "$(dirname "$f")") names 'engine project fetch' without citing ¶CMD_READ_INBOX_CHANNEL" \
          "a citation" "none"
      fi
    else
      pass "$(basename "$(dirname "$f")") names no raw channel fetch"
    fi
  done
}

test_15_command_is_registered_in_the_index() {
  if grep -qF 'commands/CMD_READ_INBOX_CHANNEL.md' "$INDEX_FILE"; then
    pass "the command is registered in .directives/COMMANDS.md"
  else
    fail "the command is registered in .directives/COMMANDS.md" "a linked heading" "absent"
  fi
}

# ============================================================
# The boundary the chapter did not carry
# ============================================================

# intake/SKILL.md's Slack clause is explicit that the marker-prefix rule must NOT be
# ported to Slack: Slack gives the bot its own user id, so an author check there is both
# stronger and free of the marker rule's cost (it would drop a human reply that happens
# to open with a marker word). Converting intake without carrying that boundary into the
# command would hand the marker rule to the one transport measured not to want it.
test_16_command_scopes_the_rule_to_linear_and_says_slack_is_out() {
  if [ ! -f "$CMD_FILE" ]; then
    fail "the command states the Slack carve-out" "a Slack clause" "no command file"
    return
  fi
  if grep -qiF 'slack' "$CMD_FILE"; then
    pass "the command states the Slack carve-out (author check there, not markers)"
  else
    fail "the command states the Slack carve-out" "a Slack clause" "absent"
  fi
}

# ============================================================
# Neither caller reads a channel without the command
# ============================================================

# The offending set is SCANNED, never listed. A hand-written list of call sites goes stale in
# silence because nothing executes a comment, and a list that has drifted sizes the remaining
# work wrongly — the previous one named three files when two were offending.
# `grep -rl` is what makes the scan safe: it emits one PATH per line, so nothing filters a
# source line that merely mentions the fetch.
offending_call_sites() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -qF 'engine project fetch' "$f" && ! grep -qF 'CMD_READ_INBOX_CHANNEL' "$f"; then
      basename "$f"
    fi
  done < <(grep -rlF 'engine project fetch' "$@" 2>/dev/null | sort)
}

test_17_no_caller_reads_a_channel_without_the_command() {
  local scanned control_dir control offenders

  # Without this the check passes when the scan matches nothing at all.
  scanned="$(grep -rlF 'engine project fetch' "$ENGINE_DIR/skills/intake" "$ENGINE_DIR/skills/groom" 2>/dev/null | grep -c .)"
  assert_gt "$scanned" "0" \
    "positive control — the scan reaches the callers' channel-read call sites ($scanned files name the fetch)"

  # And without this it passes when the detector has stopped being able to see an offender.
  control_dir="$(mktemp -d)"
  printf 'Phase 1 runs `engine project fetch` and points at nothing.\n' > "$control_dir/planted-offender.md"
  control="$(offending_call_sites "$control_dir")"
  rm -rf "$control_dir"
  assert_eq "planted-offender.md" "$control" \
    "positive control — the detector flags a planted file that names the fetch and cites nothing"

  offenders="$(offending_call_sites "$ENGINE_DIR/skills/intake" "$ENGINE_DIR/skills/groom")"
  if [ -z "$offenders" ]; then
    pass "every channel-read call site in /intake and /groom cites ¶CMD_READ_INBOX_CHANNEL"
  else
    fail "every channel-read call site cites ¶CMD_READ_INBOX_CHANNEL" \
      "no offender" "$(printf '%s' "$offenders" | tr '\n' ' ')"
  fi
}

run_discovered_tests
