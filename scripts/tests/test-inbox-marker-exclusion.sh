#!/bin/bash
# test-inbox-marker-exclusion.sh — every marker in the vocabulary is excluded BEHAVIOURALLY.
#
# The sibling suites check that the writer-side lists agree with the command's table, which is a
# string-membership check: it cannot tell a marker the filter actually drops from one that merely
# appears in a list. Measured against both existing corpora, only 5 of the 9 markers lead a comment
# body anywhere (`seems like`, `→`, `👀 claimed`, `filed as`, `⏳ marinating`); `candidate`,
# `🔎 needs-triage`, `✅ result` and `shipped in` were asserted by table membership alone. A
# differently-marked own reply is the failure the marker rule exists to stop, so each marker is
# planted as a reply and the drain is run over it.
#
# The table is read from the fence rather than restated, so a marker added there is covered here
# without an edit — and a marker added with no filter support fails this suite.

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

ENGINE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CMD_FILE="$ENGINE_DIR/.directives/commands/CMD_READ_INBOX_CHANNEL.md"
SNAPSHOT="$(dirname "$0")/fixtures/inbox-real/product-idea-fetch.json"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

extract_filter() {
  awk '
    $0 ~ /^```jq[[:space:]]+own-comment-filter[[:space:]]*$/ { inside = 1; next }
    inside && /^```[[:space:]]*$/ { exit }
    inside { print }
  ' "$CMD_FILE"
}

# Same program with the marker list emptied — the arm that must re-admit what the real one drops.
extract_emptied() {
  extract_filter | awk '
    /^def own_comment_markers:/ { inside = 1; print; next }
    inside && /^\];/            { inside = 0; print; next }
    inside && /^[[:space:]]*"/  { next }
    { print }
  '
}

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

# A ticket carrying one human root with two replies: the planted marker-led one, and a human
# sibling. Reproduces the leak's shape — a skill reply landing on somebody's drop.
plant() {
  jq --arg m "$1" '.tickets += [{
      identifier: "PLANT-1", title: "planted",
      comments: [{
        id: "plant-root", author: "human", createdAt: "2026-01-01T00:00:00Z",
        resolvedAt: null, quotedText: null, body: "Totals are wrong on the weekly report.",
        children: [
          { id: "plant-marked", author: "human", createdAt: "2026-01-02T00:00:00Z",
            resolvedAt: null, quotedText: null, body: ($m + " because the owner is away until May."),
            children: [] },
          { id: "plant-human", author: "human", createdAt: "2026-01-03T00:00:00Z",
            resolvedAt: null, quotedText: null, body: "Still happening on the Friday export.",
            children: [] }
        ]
      }]
    }]' "$SNAPSHOT"
}

# Ids the drain emits for a planted marker. $1 = marker, $2 = program file.
drained_ids() {
  plant "$1" | jq -c -f "$2" | jq -r '[.[].id] | join(" ")'
}

setup() {
  extract_filter  > "$TMP/real.jq"
  extract_emptied > "$TMP/empty.jq"
  canonical_markers > "$TMP/markers.txt"
}

test_00_instrument_is_live() {
  assert_file_exists "$SNAPSHOT" "the committed Product: Idea snapshot exists"
  assert_not_empty "$(cat "$TMP/real.jq")" "the shipped fence extracts"
  assert_gt "$(grep -c . "$TMP/markers.txt")" "0" "the canonical table extracts at least one marker"
  local n; n="$(grep -c '"' <(awk '/^def own_comment_markers:/{i=1;next} i&&/^\];/{exit} i' "$TMP/empty.jq"))"
  assert_eq "0" "$n" "the emptied program carries no markers (the control arm is a real change)"
}

test_01_every_canonical_marker_is_dropped() {
  local m got
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    got="$(drained_ids "$m" "$TMP/real.jq")"
    if [[ " $got " == *" plant-marked "* ]]; then
      fail "a reply leading with '$m' is excluded" "plant-marked absent" "drained: $got"
    else
      pass "a reply leading with '$m' is excluded from the drain"
    fi
  done < "$TMP/markers.txt"
}

# Without this arm the check above passes for a marker the filter never looks at, because the
# planted id would simply be missing from a drain that dropped it for some other reason.
test_02_control_each_marker_drains_when_the_table_is_empty() {
  local m got
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    got="$(drained_ids "$m" "$TMP/empty.jq")"
    if [[ " $got " == *" plant-marked "* ]]; then
      pass "control — with the table emptied, '$m' drains (so the drop above was the marker)"
    else
      fail "control — '$m' drains with the table emptied" "plant-marked present" "drained: $got"
    fi
  done < "$TMP/markers.txt"
}

# Disposition withholds the root but must not prune the subtree: the human sibling is live signal.
test_03_the_marked_reply_withholds_its_root_but_not_its_human_sibling() {
  local m got
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    got="$(drained_ids "$m" "$TMP/real.jq")"
    if [[ " $got " == *" plant-root "* ]]; then
      fail "'$m' under a root withholds that root" "plant-root absent" "drained: $got"
    elif [[ " $got " != *" plant-human "* ]]; then
      fail "the human sibling of a '$m' reply still drains" "plant-human present" "drained: $got"
    else
      pass "'$m' withholds its root, and the human sibling beside it still drains"
    fi
  done < "$TMP/markers.txt"
}

# The ticket's own acceptance signal, against the snapshot as committed.
test_04_no_marker_led_comment_survives_the_real_drain() {
  local markers_json survivors baseline
  markers_json="$(jq -R . "$TMP/markers.txt" | jq -s 'map(select(length>0))')"
  survivors="$(jq -c -f "$TMP/real.jq" "$SNAPSHOT" | jq --argjson m "$markers_json" \
    '[.[] | select((.body // "") | type == "string") | select(((.body | sub("^\\s+"; "")) as $b | $m | any(. as $k | $b | startswith($k))))] | length')"
  baseline="$(jq -c -f "$TMP/empty.jq" "$SNAPSHOT" | jq --argjson m "$markers_json" \
    '[.[] | select((.body // "") | type == "string") | select(((.body | sub("^\\s+"; "")) as $b | $m | any(. as $k | $b | startswith($k))))] | length')"
  assert_gt "$baseline" "0" "control — the snapshot really holds marker-led comments ($baseline found with the table emptied)"
  assert_eq "0" "$survivors" "no marker-led comment survives the real drain (of $baseline the emptied arm returns)"
}

# An emoji-led marker's sigil is the machine signature; the words after it are prose a writer
# re-phrases. Measured live on 2026-10-23: `/groom` posted `⏳ still marinating, second pass — …`
# onto IDE-35 and the drain returned it as fresh human signal, because the table carries the phrase
# `⏳ marinating` and the match was on the whole phrase. Table membership and writer-list agreement
# both read clean through that: the marker was in the table, and the reply was in the family.
variant_of() {
  local m="$1" sigil rest
  sigil="${m%% *}"; rest="${m#* }"
  [ "$sigil" != "$m" ] || return 1          # a bare-sigil marker has no words to re-phrase
  [ "$(printf '%s' "$sigil" | jq -Rr 'explode[0]')" -ge 128 ] || return 1
  printf '%s still %s' "$sigil" "$rest"
}

test_05_an_emoji_marker_variant_is_dropped() {
  local m v got seen=0
  while IFS= read -r m; do
    v="$(variant_of "$m")" || continue
    seen=$((seen + 1))
    got="$(drained_ids "$v" "$TMP/real.jq")"
    if [[ " $got " == *" plant-marked "* ]]; then
      fail "a reply leading with the variant '$v' is excluded" "plant-marked absent" "drained: $got"
    else
      pass "the variant '$v' is excluded (the sigil matches, not the phrase)"
    fi
  done < "$TMP/markers.txt"
  assert_gt "$seen" "0" "control — the table holds at least one emoji-led marker to vary"
}

test_06_control_a_variant_drains_when_the_table_is_empty() {
  local m v got
  while IFS= read -r m; do
    v="$(variant_of "$m")" || continue
    got="$(drained_ids "$v" "$TMP/empty.jq")"
    if [[ " $got " == *" plant-marked "* ]]; then
      pass "control — with the table emptied, '$v' drains (so the drop above was the sigil)"
    else
      fail "control — '$v' drains with the table emptied" "plant-marked present" "drained: $got"
    fi
  done < "$TMP/markers.txt"
}

# The live leak verbatim, kept as its own case so the regression has a name rather than riding a loop.
test_07_the_live_marinating_variant_is_dropped() {
  local lead="⏳ still marinating, second pass — Product: Idea groom of 2026-10-21, topic ACCEPTFILL."
  local got; got="$(drained_ids "$lead" "$TMP/real.jq")"
  if [[ " $got " == *" plant-marked "* ]]; then
    fail "the live '⏳ still marinating' reply does not return as fresh feedback" \
         "plant-marked absent" "drained: $got"
  else
    pass "the live '⏳ still marinating' reply does not return as fresh feedback"
  fi
  got="$(drained_ids "$lead" "$TMP/empty.jq")"
  assert_contains "plant-marked" "$got" \
    "control — that same reply drains with the table emptied"
}

# A word-led marker keeps its whole phrase: a sigil rule must not shrink `seems like` to `seems`,
# because a bare word is what the emoji-led markers exist to avoid colliding with.
test_08_a_word_led_marker_still_needs_its_whole_phrase() {
  local got
  got="$(drained_ids "seems unrelated to the export bug," "$TMP/real.jq")"
  assert_contains "plant-marked" "$got" \
    "a human reply opening 'seems unrelated…' still drains (only 'seems like' is a marker)"
  got="$(drained_ids "filed a complaint with the carrier," "$TMP/real.jq")"
  assert_contains "plant-marked" "$got" \
    "a human reply opening 'filed a…' still drains (only 'filed as' is a marker)"
}

run_discovered_tests
