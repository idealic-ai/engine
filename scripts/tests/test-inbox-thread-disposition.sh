#!/bin/bash
# test-inbox-thread-disposition.sh — disposition is a property of a thread, not of a comment.
#
# A groom pass disposes an item by REPLYING; the reply leads with a marker and is excluded, which
# used to admit the reply's parent (the original drop) as new signal, so a fully-groomed inbox
# drained as a full one. These checks run the shipped fence over a real Product: Idea payload and
# pair every zero with a run that returns the full count when the marker set is emptied.

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

ENGINE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CMD_FILE="$ENGINE_DIR/.directives/commands/CMD_READ_INBOX_CHANNEL.md"
SNAPSHOT="$(dirname "$0")/fixtures/inbox-real/product-idea-fetch.json"
CHANNELS='["IDE-34","IDE-35","IDE-37","IDE-38","IDE-39","IDE-40","IDE-41","IDE-126"]'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

extract_filter() {
  awk '
    $0 ~ /^```jq[[:space:]]+own-comment-filter[[:space:]]*$/ { inside = 1; next }
    inside && /^```[[:space:]]*$/ { exit }
    inside { print }
  ' "$CMD_FILE"
}

# Same program with the marker list emptied (the quoted entries removed; glyph-free).
extract_emptied() {
  extract_filter | awk '
    /^def own_comment_markers:/ { inside = 1; print; next }
    inside && /^\];/            { inside = 0; print; next }
    inside && /^[[:space:]]*"/  { next }
    { print }
  '
}

# Depth-0 ids in the channel tickets (the "roots").
roots_json() { jq -c --argjson ch "$CHANNELS" '[.tickets[] | select(.identifier|IN($ch[])) | .comments[]? | .id]' "$SNAPSHOT"; }

# Number of drained nodes that are roots. $1 = program file, $2 = walk.
drained_roots() {
  INBOX_WALK="${2:-new-signal}" jq -c -f "$1" "$SNAPSHOT" 2>"$TMP/err" \
    | jq --argjson roots "$(roots_json)" '[.[] | select(.id|IN($roots[]))] | length'
}

setup() {
  extract_filter > "$TMP/real.jq"; extract_emptied > "$TMP/empty.jq"
}

test_00_programs_extract() {
  assert_file_exists "$SNAPSHOT" "the committed Product: Idea snapshot exists"
  assert_not_empty "$(cat "$TMP/real.jq")" "the shipped fence extracts"
  local n; n="$(grep -c '"' <(awk '/^def own_comment_markers:/{i=1;next} i&&/^\];/{exit} i' "$TMP/empty.jq"))"
  assert_eq "0" "$n" "the emptied program carries no markers (control is a real change)"
}

test_01_snapshot_has_31_roots() {
  assert_eq "31" "$(roots_json | jq length)" "31 root comments across the eight channels"
}

test_02_real_markers_drain_zero_roots() {
  assert_eq "0" "$(drained_roots "$TMP/real.jq")" "dispositioned roots are not new signal (real vocabulary)"
}

test_03_emptied_markers_drain_all_31_roots() {
  assert_eq "31" "$(drained_roots "$TMP/empty.jq")" "with the marker set emptied the same drain returns all 31 roots"
}

test_04_old_behaviour_would_fail_this_check() {
  # The pre-fix program: roots admitted regardless of descendants. Proves the zero above can go red.
  sed 's/if (\$root | dispositioned) then \[\] else \[\$root\] end/[$root]/' "$TMP/real.jq" > "$TMP/old.jq"
  assert_eq "31" "$(drained_roots "$TMP/old.jq")" "removing the root suppression re-admits 31 roots"
}

test_05_flatten_kept_unmarked_descendants_still_drain() {
  local total unmarked
  total="$(jq -c -f "$TMP/real.jq" "$SNAPSHOT" | jq length)"
  unmarked="$(jq --argjson ch "$CHANNELS" '
    def ft: [ .[] | ., (.children // [] | ft[]) ];
    [ .tickets[] | select(.identifier|IN($ch[])) | .comments[]? | (.children // []) | ft[] ] | length' "$SNAPSHOT")"
  assert_eq "39" "$total" "the drain still returns 39 nodes on the frozen snapshot: zero of the 31 roots, but the other nodes (13 on channel tickets, 26 on non-channel tickets) still drain"
  assert_gt "$total" "0" "unmarked replies under machine replies still drain ($total emitted in all tickets; $unmarked channel descendants walked)"
}

test_06_open_threads_are_listable() {
  local out
  out="$(INBOX_WALK=open-threads jq -c -f "$TMP/real.jq" "$SNAPSHOT")"
  assert_eq "11" "$(echo "$out" | jq length)" "the open-threads query lists the 11 unresolved roots"
  assert_eq "11" "$(echo "$out" | jq '[.[]|select(.dispositioned)]|length')" "all 11 are dispositioned (so suppressed from the drain, yet reachable)"
  assert_eq "0" "$(echo "$out" | jq --argjson r "$(jq -c '[.. | objects | select(has("resolvedAt")) | select(.resolvedAt != null) | .id]' "$SNAPSHOT")" '[.[]|select(.id|IN($r[]))]|length')" "no resolved root leaks into the open list"
}

test_07_open_listing_control_nonvacuous() {
  assert_eq "0" "$(drained_roots "$TMP/real.jq" new-signal)" "open threads are absent from the drain"
  assert_eq "11" "$(INBOX_WALK=open-threads jq -c -f "$TMP/real.jq" "$SNAPSHOT" | jq length)" "yet present in the open-threads walk"
}

run_discovered_tests
