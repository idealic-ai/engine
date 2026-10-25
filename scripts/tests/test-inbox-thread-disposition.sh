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

test_05_a_fully_groomed_snapshot_drains_nothing() {
  local unmarked
  unmarked="$(jq --argjson ch "$CHANNELS" '
    def ft: [ .[] | ., (.children // [] | ft[]) ];
    [ .tickets[] | select(.identifier|IN($ch[])) | .comments[]? | (.children // []) | ft[] ] | length' "$SNAPSHOT")"
  assert_gt "$unmarked" "0" "control — the channels carry $unmarked descendants for the drain to walk"
  assert_eq "0" "$(jq -c -f "$TMP/real.jq" "$SNAPSHOT" | jq length)" "the drain returns nothing on the frozen snapshot: zero of the 31 roots, zero of the 13 channel replies (each predates its thread's last marker), and no work-ticket comment"
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

# ------------------------------------------------------------------
# Echoes: a reply that predates its thread's latest marker reply was already in front of whoever
# dispositioned the thread, so it is not new signal. Measured on the committed Product: Handbook
# fetch (2026-10-25 18:05): five channel-ticket replies sit before their thread's last marker and
# the drain returned all five. A reply AFTER the last marker is live signal and still drains.
# ------------------------------------------------------------------
HANDBOOK="$(dirname "$0")/fixtures/inbox-real/product-handbook-fetch.json"

# The fence's own definitions (everything before the walk), so the test reuses the marker logic
# rather than restating it, followed by a query for echo ids on channel tickets.
echo_ids_program() {
  awk '/^\(\$ENV\.INBOX_WALK/ { exit } { print }' "$TMP/real.jq"
  cat <<'JQ'
([.structure.channels[]?.identifier]) as $ch
| [ .tickets[] | select(.identifier | IN($ch[])) | (.comments // [])[]
    | select(dispositioned)
    | ([(.children // []) | flatten_tree[] | select(leads_with_own_marker) | .createdAt] | max) as $last
    | (.children // []) | flatten_tree[] | select(leads_with_own_marker | not)
    | select(.createdAt <= $last) | .id ]
JQ
}

# Number of drained nodes from $2 (a payload) that are echoes, under program $1.
drained_echoes() {
  local echoes; echoes="$(jq -c -f "$TMP/echo.jq" "$2")"
  jq -c -f "$1" "$2" | jq --argjson e "$echoes" '[.[] | select(.id | IN($e[]))] | length'
}

test_08_echo_replies_before_the_last_marker_do_not_drain() {
  echo_ids_program > "$TMP/echo.jq"
  assert_file_exists "$HANDBOOK" "the committed Product: Handbook snapshot exists"
  assert_eq "5" "$(jq -c -f "$TMP/echo.jq" "$HANDBOOK" | jq length)" "control — the snapshot holds five replies that predate their thread's last marker"
  assert_eq "0" "$(drained_echoes "$TMP/real.jq" "$HANDBOOK")" "none of the five echo replies drains"
}

test_09_control_the_pre_fix_program_drains_all_five_echoes() {
  echo_ids_program > "$TMP/echo.jq"
  # The pre-fix program: every non-marker descendant of a dispositioned root is flattened in.
  sed 's/(\$root.children \/\/ \[\] | flatten_tree | after_last_marker(\$root))/($root.children \/\/ [] | flatten_tree)/' "$TMP/real.jq" > "$TMP/old.jq"
  assert_neq "$(cat "$TMP/real.jq")" "$(cat "$TMP/old.jq")" "the pre-fix program really differs from the shipped one"
  assert_eq "5" "$(drained_echoes "$TMP/old.jq" "$HANDBOOK")" "without the echo cut the same drain returns all five"
}

# A reply after the last marker is someone answering the disposition: it must still drain.
test_10_a_reply_after_the_last_marker_still_drains_and_one_before_does_not() {
  local plant got
  plant="$(jq '.tickets += [{ identifier: "IDE-34", title: "planted", comments: [{
      id: "p-root", author: "h", createdAt: "2026-01-01T00:00:00Z", resolvedAt: "2026-01-05T00:00:00Z",
      quotedText: null, body: "Totals are wrong on the weekly report.", children: [
        { id: "p-before", author: "h", createdAt: "2026-01-02T00:00:00Z", resolvedAt: null, quotedText: null,
          body: "Same on the Friday export.", children: [] },
        { id: "p-mark", author: "h", createdAt: "2026-01-03T00:00:00Z", resolvedAt: null, quotedText: null,
          body: "filed as IDE-999", children: [] },
        { id: "p-after", author: "h", createdAt: "2026-01-04T00:00:00Z", resolvedAt: null, quotedText: null,
          body: "That ticket is the wrong one, this is the export.", children: [] } ] }] }]' "$SNAPSHOT")"
  got="$(printf '%s' "$plant" | jq -c -f "$TMP/real.jq" | jq -r '[.[].id] | join(" ")')"
  assert_contains "p-after" "$got" "a reply after the last marker on a resolved thread drains (it corrects the disposition)"
  assert_not_contains "p-before" "$got" "a reply before the last marker does not drain (the disposition already answered it)"
  got="$(printf '%s' "$plant" | jq -c -f "$TMP/empty.jq" | jq -r '[.[].id] | join(" ")')"
  assert_contains "p-before" "$got" "control — with the table emptied the earlier reply drains, so its drop was the marker's doing"
}

# ------------------------------------------------------------------
# Scope: the fetch also carries comments on ordinary work tickets (project.sh says so), and the
# drain is a read of the INBOX. Measured on the Product: Handbook fetch: 37 of the 39 nodes drained
# sat on work tickets, none of them inbox signal; the open-threads walk was already scoped.
# ------------------------------------------------------------------
off_channel_drained() {
  jq -c -f "$1" "$2" | jq --argjson ch "$(jq -c '[.structure.channels[]?.identifier]' "$2")" \
    '[.[] | select(.channel | IN($ch[]) | not)] | length'
}

test_11_the_drain_reads_only_the_inbox_channels() {
  assert_eq "0" "$(off_channel_drained "$TMP/real.jq" "$HANDBOOK")" "no work-ticket comment drains from the Product: Handbook snapshot"
  assert_eq "0" "$(off_channel_drained "$TMP/real.jq" "$SNAPSHOT")" "no work-ticket comment drains from the Product: Idea snapshot"
  assert_eq "2" "$(jq -c -f "$TMP/real.jq" "$HANDBOOK" | jq length)" "the live inbox thread on IDE-53 (a root and its reply, no marker) still drains in full"
}

test_12_control_unscoped_the_same_drain_returns_the_work_ticket_comments() {
  # Swap the scope for identity (deleting the line would leave a dangling pipe).
  awk '/# new-signal scope$/ { print "        ."; next } { print }' "$TMP/real.jq" > "$TMP/unscoped.jq"
  assert_neq "$(cat "$TMP/real.jq")" "$(cat "$TMP/unscoped.jq")" "the unscoped program really differs from the shipped one"
  assert_eq "37" "$(off_channel_drained "$TMP/unscoped.jq" "$HANDBOOK")" "without the scope the Product: Handbook drain returns 37 work-ticket comments"
  assert_eq "26" "$(off_channel_drained "$TMP/unscoped.jq" "$SNAPSHOT")" "and the Product: Idea drain returns 26"
}

run_discovered_tests
