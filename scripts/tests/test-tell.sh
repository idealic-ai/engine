#!/bin/bash
# test-tell.sh — Tests for `engine tell` (scripts/tell.sh → scripts/broadcast.sh tell|withdraw|landed).
# A tell is a broadcast record with tell header lines, so this reuses test-broadcast.sh's fixtures:
# a HOP_LIVE_PANES tree, a fixture process table and session registry, a temp BROADCAST_DIR and a
# stub delivery that appends to a file. No live tmux, no socket, no fleet message.
#
# Fixture tree (test-broadcast.sh setup): manager:director → manager:app, manager:domain;
# manager:app → app:ask (%4), app:ui (%5); app:ask → ask:helper; manager:domain → domain:stats (%7).
#
#   tiers    — note queues every seat and pushes none; lazy pushes a busy seat and queues an idle
#              one; wake needs --wake-reason; escalate goes to the sender's manager with `for:`;
#              align goes straight to the recipient plus a never-pushed notice to both managers.
#   default  — a --to across managers defaults to align; inside one manager to lazy.
#   audience — --to, --peers, --parent (tell and broadcast send).
#   withdraw — sender, its manager or the operator; a queued copy is removed; an acked seat is told;
#              pending stops listing it; anyone else is refused.
#   landed   — a lazy tell to the peers and the manager naming repo, sha and subject.
#
# Plant a defect: BROADCAST_SH=<mutated copy> bash test-tell.sh — it must go red.

set -uo pipefail
HERE_T="$(cd "$(dirname "$0")" && pwd)"
BROADCAST_SH="${BROADCAST_SH:-$HERE_T/../broadcast.sh}"
TELL_SH="${TELL_SH:-$HERE_T/../tell.sh}"
# The tree under test's own lib.sh and hop.sh, never the live engine's (test-broadcast.sh's defaults).
BROADCAST_LIB="${BROADCAST_LIB:-$HERE_T/../lib.sh}"
HOP_SH="${HOP_SH:-$HERE_T/../../skills/coordinate/scripts/hop.sh}"
BROADCAST_HARNESS_ONLY=1
# shellcheck source=test-broadcast.sh
source "$HERE_T/test-broadcast.sh"
# Only this file's tests run: drop the broadcast suite's own.
for f in $(declare -F | awk '{print $3}' | grep '^test_'); do unset -f "$f"; done

sent_to() { cut -d'|' -f1 "$FIX/sent.log" | sort | tr '\n' ' ' | sed 's/ $//'; }
rec() { cat "$FIX/bc/$1.md"; }

# ---------------------------------------------------------------- tiers
test_note_queues_every_seat_and_pushes_none() {
  act 2004 busy 0; act 2005 idle 60
  MSG="lease is free" PANE=%2 bc tell --children --tier note --id n1
  assert_eq 0 "$RC" "note: exits 0"
  assert_eq "0" "$(sent_count)" "note: nothing is pushed, not even to a busy seat"
  assert_file_exists "$FIX/bc/queued/app:ask/n1" "note: the busy seat is queued"
  assert_file_exists "$FIX/bc/queued/app:ui/n1" "note: the idle seat is queued"
  assert_has "message: tell" "$(rec n1)" "note: the record is a tell"
  assert_has "tier: note" "$(rec n1)" "note: with its tier"
  assert_has "subject: lease is free" "$(rec n1)" "note: the subject defaults to the first line"
  assert_has "queued app:ask pid=2004 tier=note" "$(rec n1)" "note: the delivery line says why it was queued"
}

test_lazy_is_the_default_and_wakes_nobody() {
  act 2005 idle 60
  MSG="done with the parser" PANE=%4 bc tell --to app:ui --id l1
  assert_eq 0 "$RC" "lazy: exits 0"
  assert_has "tier: lazy" "$(rec l1)" "lazy: a --to inside one manager defaults to lazy"
  assert_eq "0" "$(sent_count)" "lazy: an idle seat is not pushed"
  assert_file_exists "$FIX/bc/queued/app:ui/l1" "lazy: it is queued for the idle seat"
  : > "$FIX/sent.log"; act 2005 busy 0
  MSG="second" PANE=%4 bc tell --to app:ui --id l2
  assert_eq "app:ui" "$(sent_to)" "lazy: a busy seat is pushed (already awake)"
  assert_has "[tell · lazy from app:ask] second" "$(cat "$FIX/msg.app:ui")" "lazy: the pushed text leads with tier, sender and subject"
  assert_hasnt "ack (from" "$(cat "$FIX/msg.app:ui")" "lazy: no ack is asked (S3)"
}

test_wake_needs_a_reason() {
  act 2005 idle 60
  MSG="x" PANE=%4 bc tell --to app:ui --tier wake --id w0
  assert_eq 2 "$RC" "wake: refused without --wake-reason"
  assert_has "wake-reason" "$OUT" "wake: and says what is missing"
  assert_file_not_exists "$FIX/bc/w0.md" "wake: nothing written"
  MSG="resume" PANE=%4 bc tell --to app:ui --tier wake --wake-reason "operator: resume" --id w1
  assert_eq 0 "$RC" "wake: with a reason exits 0"
  assert_eq "app:ui" "$(sent_to)" "wake: the idle seat is pushed"
  assert_has "kind: wake" "$(rec w1)" "wake: recorded as a wake"
  assert_has "tier: wake" "$(rec w1)" "wake: with its tier"
  MSG="x" PANE=%4 bc tell --to app:ui --tier note --wake-reason "y" --id w2
  assert_eq 2 "$RC" "wake: --wake-reason is refused on a note"
}

test_escalate_goes_to_the_manager_first() {
  MSG="need a call on the parser" PANE=%4 bc tell --to domain:stats --tier escalate --id e1
  assert_eq 0 "$RC" "escalate: exits 0"
  assert_eq "manager:app" "$(sed -n 's/^audience: //p' "$FIX/bc/e1.md")" "escalate: the audience is the sender's manager only"
  assert_has "for: domain:stats" "$(rec e1)" "escalate: the intended seat is recorded"
  assert_has "tier: escalate" "$(rec e1)" "escalate: with its tier"
  assert_file_not_exists "$FIX/bc/queued/domain:stats/e1" "escalate: the peer gets nothing"
  MSG="x" PANE=%1 bc tell --tier escalate --id e2
  assert_eq 3 "$RC" "escalate: a seat with no manager is refused (3)"
}

test_align_goes_direct_and_tells_both_managers_without_waking() {
  act 2007 idle 30; act 2002 busy 0; act 2003 idle 30
  MSG=$'stats schema moved\nsee the commit' PANE=%4 bc tell --to domain:stats --id a1
  assert_eq 0 "$RC" "align: exits 0"
  assert_has "tier: align" "$(rec a1)" "align: a --to across managers defaults to align"
  assert_has "notice: a1.align" "$(rec a1)" "align: the tell links its notice"
  assert_eq "domain:stats" "$(sed -n 's/^audience: //p' "$FIX/bc/a1.md")" "align: straight to the recipient"
  assert_file_exists "$FIX/bc/a1.align.md" "align: the managers' notice is written"
  assert_eq "manager:app manager:domain" "$(sed -n 's/^audience: //p' "$FIX/bc/a1.align.md")" "align: both managers"
  assert_has "tier: lazy" "$(rec a1.align)" "align: the notice is lazy (the operator's ALIGN ruling)"
  assert_has "notice-of: a1" "$(rec a1.align)" "align: and points back at the tell"
  assert_has "subject: these two are talking: stats schema moved" "$(rec a1.align)" "align: the notice's subject"
  assert_eq "manager:app" "$(sent_to)" "align: only the busy manager is pushed (already awake)"
  assert_file_exists "$FIX/bc/queued/manager:domain/a1.align" "align: the idle manager is queued"
  assert_file_not_exists "$FIX/bc/queued/domain:stats/a1.align" "align: the recipient gets no notice"
}

test_align_explicit_inside_one_manager_writes_no_notice() {
  MSG="x" PANE=%4 bc tell --to app:ui --tier align --id a2
  assert_eq 0 "$RC" "align: inside one manager exits 0"
  assert_has "notice: -" "$(rec a2)" "align: no manager outside the pair, no notice"
  assert_file_not_exists "$FIX/bc/a2.align.md" "align: and none written"
}

# ---------------------------------------------------------------- audience
test_peers_and_parent_selectors() {
  MSG="x" PANE=%4 bc tell --peers --id p1 --dry-run
  assert_eq 0 "$RC" "peers: exits 0"
  assert_eq "app:ui" "$(audience)" "peers: siblings under the same manager, not the sender"
  MSG="x" PANE=%4 bc tell --parent --id p2 --dry-run
  assert_eq "manager:app" "$(audience)" "parent: the sender's manager"
  MSG="x" PANE=%4 bc send --peers --dry-run
  assert_eq "app:ui" "$(audience)" "broadcast send takes --peers too"
  MSG="x" PANE=%4 bc send --to app:ui,domain:stats --dry-run
  assert_eq "app:ui domain:stats" "$(audience)" "broadcast send takes a --to list"
  MSG="x" PANE=%4 bc tell --to nobody:here --id p3
  assert_eq 3 "$RC" "to: a seat not in the tree is refused (3)"
}

test_tell_wrapper_dispatches() {
  local keep="$BROADCAST_SH"; BROADCAST_SH="$TELL_SH"
  MSG="via the wrapper" PANE=%4 bc --to app:ui --id t1
  assert_eq 0 "$RC" "wrapper: engine tell --to … sends a tell"
  assert_has "message: tell" "$(rec t1)" "wrapper: it is a tell record"
  PANE=%4 bc status t1
  assert_has "app:ui" "$OUT" "wrapper: engine tell status reads it"
  BROADCAST_SH="$keep"
}

# ---------------------------------------------------------------- withdraw
test_withdraw_by_sender_unqueues_and_marks() {
  act 2005 idle 60
  MSG="ignore me" PANE=%4 bc tell --to app:ui --id d1
  assert_file_exists "$FIX/bc/queued/app:ui/d1" "withdraw: queued first"
  PANE=%4 bc withdraw d1 --reason "sent to the wrong seat"
  assert_eq 0 "$RC" "withdraw: the sender may"
  assert_file_not_exists "$FIX/bc/queued/app:ui/d1" "withdraw: the unseen copy leaves the queue"
  assert_has "withdrawn: by app:ask at " "$(rec d1)" "withdraw: the record says who"
  assert_has "— sent to the wrong seat" "$(rec d1)" "withdraw: and why"
  PANE=%5 bc pending
  assert_hasnt "d1" "$OUT" "withdraw: pending no longer lists it"
  PANE=%4 bc status d1
  assert_has "withdrawn: by app:ask" "$OUT" "withdraw: status shows it"
  PANE=%4 bc withdraw d1 --reason again
  assert_eq 0 "$RC" "withdraw: a second withdraw is a no-op"
  assert_has "already withdrawn" "$OUT" "withdraw: and says so"
}

test_withdraw_who_may() {
  MSG="x" PANE=%4 bc tell --to app:ui --id d2
  PANE=%5 bc withdraw d2 --reason "not mine"
  assert_eq 2 "$RC" "withdraw: the recipient may not"
  PANE=%7 bc withdraw d2 --reason "not mine"
  assert_eq 2 "$RC" "withdraw: another manager's seat may not"
  PANE=%2 bc withdraw d2 --reason "the manager pulls it"
  assert_eq 0 "$RC" "withdraw: the sender's manager may"
  assert_has "withdrawn: by manager:app" "$(rec d2)" "withdraw: recorded under the manager"
  MSG="x" PANE=%4 bc tell --to app:ui --id d3
  PANE=%4 bc withdraw d3 --reason x --by operator
  assert_eq 2 "$RC" "withdraw: a seat may not claim the operator"
  PANE=none bc withdraw d3 --reason "operator pulls it" --by operator
  assert_eq 0 "$RC" "withdraw: the operator, from a bare shell, may"
  assert_has "withdrawn: by operator" "$(rec d3)" "withdraw: recorded under the operator"
  PANE=%4 bc withdraw d3
  assert_eq 2 "$RC" "withdraw: --reason is required"
}

test_withdraw_tells_a_seat_that_acted() {
  act 2005 busy 0
  MSG="use branch b" PANE=%4 bc tell --to app:ui --id d4
  PANE=%5 bc ack d4
  assert_eq 0 "$RC" "withdraw: the recipient acked first"
  : > "$FIX/sent.log"
  PANE=%4 bc withdraw d4 --reason "branch b is wrong"
  assert_eq 0 "$RC" "withdraw: exits 0"
  assert_has "told app:ui (it had acked; delivered, d4.withdrawn)" "$OUT" "withdraw: the acked seat is told, after the send"
  assert_eq "1" "$(ls "$FIX/bc" | grep -c '^d4\.withdrawn\.md$' | tr -d ' ')" "withdraw: as its own tell record"
  assert_has "notice-of: d4" "$(rec d4.withdrawn)" "withdraw: which points back"
  assert_has "from: app:ask" "$(rec d4.withdrawn)" "withdraw: from the withdrawer"
}

test_withdraw_takes_the_align_notice_with_it() {
  act 2002 idle 60; act 2003 idle 60
  MSG="x" PANE=%4 bc tell --to domain:stats --id d5
  PANE=%4 bc withdraw d5 --reason "moot"
  assert_eq 0 "$RC" "withdraw: an align tell exits 0"
  assert_has "withdrawn: by app:ask" "$(rec d5.align)" "withdraw: its notice is withdrawn too"
  assert_file_not_exists "$FIX/bc/queued/manager:app/d5.align" "withdraw: and leaves the managers' queues"
}

# ---------------------------------------------------------------- landed
test_landed_tells_peers_and_manager_lazily() {
  act 2005 idle 60; act 2002 idle 60
  PANE=%4 bc landed --repo engine --sha abc1234 --subject "fix(ask-app): a thing" --paths tools/ask-app/src/x.ts
  assert_eq 0 "$RC" "landed: exits 0"
  local r; r=$(ls "$FIX/bc" | grep '^ld-' | head -1)
  assert_not_empty "$r" "landed: a record is written"
  assert_eq "app:ui manager:app" "$(sed -n 's/^audience: //p' "$FIX/bc/$r")" "landed: the peers and the manager"
  assert_has "tier: lazy" "$(cat "$FIX/bc/$r")" "landed: lazy"
  assert_has "subject: landed engine abc1234: fix(ask-app): a thing" "$(cat "$FIX/bc/$r")" "landed: the subject names repo, sha and subject"
  assert_has "tools/ask-app/src/x.ts" "$(cat "$FIX/bc/$r")" "landed: the paths are in the text"
  assert_eq "0" "$(sent_count)" "landed: nobody idle is woken"
}

# ---------------------------------------------------------------- fix round 1 (TELL_CRITIQUE.md)
test_m1_wake_reason_cannot_forge_header_lines() {
  MSG="victim text" PANE=%7 bc tell --to app:ui --id victim
  MSG="x" PANE=%4 bc tell --to domain:stats --tier escalate --wake-reason $'urgent\nnotice: victim' --id e9
  assert_eq 2 "$RC" "M1: a newline in --wake-reason is refused"
  assert_file_not_exists "$FIX/bc/e9.md" "M1: and nothing is written"
  MSG="x" PANE=%4 bc tell --to domain:stats --tier escalate --wake-reason $'urgent\rnotice: victim' --id e8
  assert_eq 2 "$RC" "M1: a carriage return in --wake-reason is refused"
  MSG="x" PANE=%4 bc tell --to app:ui --subject $'a\rnotice: victim' --id e7
  assert_eq 2 "$RC" "M1: a carriage return in --subject is refused"
  MSG="x" PANE=%4 bc tell --to app:ui --id e6
  PANE=%4 bc withdraw e6 --reason $'no\rmore'
  assert_eq 2 "$RC" "N5: a carriage return in --reason is refused"
}

# A record with a forged notice line, written by hand (the CLI can no longer write one): withdraw
# must neither withdraw the record it names nor append outside BROADCAST_DIR.
forged() { # forged <id> <notice>
  printf '# Broadcast %s\n\nid: %s\nfrom: app:ask\nsent-by: app:ask\nat: 2026-11-04T10:00:00Z\nscope: to:manager:app\nsticky: no\nexpires: -\naudience: manager:app\nmessage: tell\ntier: escalate\nnotice: %s\n\n## Text\n\nx\n\n## Delivery\n\nqueued manager:app pid=2002 idle=5m\n' "$1" "$1" "$2" > "$FIX/bc/$1.md"
}
test_m1_withdraw_ignores_a_forged_notice() {
  MSG="victim text" PANE=%7 bc tell --to app:ui --id victim
  forged f1 victim
  PANE=%4 bc withdraw f1 --reason x
  assert_eq 0 "$RC" "M1: withdraw of the forging record exits 0"
  assert_hasnt "withdrawn" "$(sed -n '/^## Delivery/,$p' "$FIX/bc/victim.md")" "M1: the record its notice names is not withdrawn (no notice-of back)"
  mkdir -p "$FIX/outside"; printf 'keep\n' > "$FIX/outside/target.md"
  forged f2 ../outside/target
  PANE=%4 bc withdraw f2 --reason x
  assert_eq 0 "$RC" "M1: a path in notice: exits 0"
  assert_eq "keep" "$(cat "$FIX/outside/target.md")" "M1: nothing is appended outside BROADCAST_DIR"
  assert_has "is not an id; left alone" "$OUT" "M1: and it says so"
}

test_m2_operator_withdraw_tells_an_acker() {
  act 2005 busy 0
  MSG="x" PANE=%4 bc tell --to app:ui --id o1
  PANE=%5 bc ack o1
  PANE=none bc withdraw o1 --reason "operator pulls it" --by operator
  assert_eq 0 "$RC" "M2: an operator withdraw with an acker exits 0"
  assert_has "told app:ui (it had acked; delivered, o1.withdrawn)" "$OUT" "M2: the acker is told"
  assert_has "sent-by: operator" "$(rec o1.withdrawn)" "M2: the notice is sent by the operator"
  assert_has "from: operator" "$(rec o1.withdrawn)" "M2: and from the operator"
}

test_m3_an_acker_gone_from_the_tree_is_reported_not_fatal() {
  act 2005 busy 0
  MSG="x" PANE=%4 bc tell --to app:ui --id g1
  PANE=%5 bc ack g1
  sed -i '' '/^app:ui /d' "$FIX/live.txt"
  PANE=%4 bc withdraw g1 --reason "moot"
  assert_eq 0 "$RC" "M3: exits 0 with an acker gone"
  assert_has "withdrawn: g1" "$OUT" "M3: the withdrawal is recorded"
  assert_has "not told app:ui (it had acked, but has left the live tree)" "$OUT" "M3: the gone acker is reported"
  assert_file_not_exists "$FIX/bc/g1.withdrawn.md" "M3: no notice to nobody"
}

test_m3_manager_withdraws_after_the_sender_left() {
  act 2005 busy 0
  MSG="x" PANE=%4 bc tell --to app:ui --id g2
  PANE=%5 bc ack g2
  sed -i '' '/^app:ask /d; /^ask:helper /d' "$FIX/live.txt"
  PANE=%7 bc withdraw g2 --reason "not mine"
  assert_eq 2 "$RC" "M3: another manager's seat is still refused once the sender left"
  PANE=%2 bc withdraw g2 --reason "the seat is gone"
  assert_eq 0 "$RC" "M3: the manager withdraws after the sender left"
  assert_has "told app:ui (it had acked; delivered" "$OUT" "M3: the acker is told"
  assert_has "from: manager:app" "$(rec g2.withdrawn)" "M3: from the withdrawer, not the gone sender"
}

test_s1_a_tell_never_pushes_an_idle_seat() {
  act 2005 idle 60
  MSG="x" DRAIN_HOOK=/nonexistent/hook PANE=%4 bc tell --to app:ui --id s1
  assert_eq 1 "$RC" "S1: an idle seat that cannot drain is undelivered (rc 1)"
  assert_eq "0" "$(sent_count)" "S1: and not pushed"
  assert_has "a tell is never pushed to an idle seat" "$(rec s1)" "S1: the record says why"
  : > "$FIX/sent.log"
  MSG="x" PANE=%4 bc tell --to app:ask --tier lazy --id s1b
  MSG="x" PANE=%4 bc tell --to app:ui --id s1c
  act 2005 busy 0
  MSG="x" PANE=%7 bc tell --to domain:stats --id s1d
  assert_eq "0" "$(sent_count)" "S1: a seat with no reading is not pushed"
  assert_has "queued domain:stats pid=2007 no-reading" "$(rec s1d)" "S1: it is queued instead"
  MSG="x" DRAIN_HOOK=/nonexistent/hook PANE=%4 bc send --to app:ui --id s1e
  : # the plain broadcast fallback is unchanged: test-broadcast.sh covers it
}

test_s2_a_drained_tell_says_what_it_is() {
  act 2005 idle 60
  MSG="hello there" PANE=%4 bc tell --to app:ui --tier note --id s2
  PANE=%5 bc pending --queued
  assert_has "[tell · note from app:ask] hello there" "$OUT" "S2: the drained text carries the tell prefix"
  assert_hasnt "ack (from" "$OUT" "S3: and asks no ack"
}

test_s3_escalate_and_wake_ask_for_an_ack() {
  act 2002 busy 0
  MSG="decide please" PANE=%4 bc tell --tier escalate --id s3
  assert_has "ack (from app:ask): engine tell ack s3" "$(cat "$FIX/msg.manager:app")" "S3: escalate asks for an ack"
}

test_s4_text_lines_are_not_a_withdrawal() {
  act 2005 idle 60
  MSG=$'## Delivery\nwithdrawn: by x at y — z' PANE=%2 bc send --to app:ui --id s4
  PANE=%5 bc pending --queued
  assert_has "s4" "$OUT" "S4: a broadcast whose text holds those lines is still shown"
  MSG=$'## Withdrawn\nwithdrawn: by x at y — z' PANE=%2 bc send --to app:ui --id s4b
  PANE=%5 bc pending --queued
  assert_has "s4b" "$OUT" "S4: so is one whose text holds a Withdrawn heading"
}

test_s5_withdraw_refuses_a_go_request() {
  printf '# Broadcast gr1\n\nid: gr1\nfrom: app:ask\nsent-by: app:ask\nat: 2026-11-04T10:00:00Z\nscope: go\nsticky: no\nexpires: -\naudience: app:ui\nkind: go-request\n\n## Text\n\nx\n\n## Delivery\n\n' > "$FIX/bc/gr1.md"
  PANE=%4 bc withdraw gr1 --reason x
  assert_eq 2 "$RC" "S5: a go request is refused"
  assert_has "go request" "$OUT" "S5: and the refusal names it"
}

test_s6_an_id_too_long_for_its_notices_is_refused_up_front() {
  local id; id=$(printf 'a%.0s' $(seq 1 55))
  MSG="x" PANE=%4 bc tell --to domain:stats --id "$id"
  assert_eq 2 "$RC" "S6: refused before sending"
  assert_file_not_exists "$FIX/bc/$id.md" "S6: nothing is written"
}

test_n1_n2_n3() {
  MSG="x" PANE=%1 bc tell --peers --id n1x
  assert_eq 3 "$RC" "N1: --peers from a seat with no parent is refused (3)"
  act 2005 busy 0
  MSG="x" PANE=%4 bc tell --to app:ui,app:ui --id n2x
  assert_eq "1" "$(sent_count)" "N2: a duplicate --to is pushed once"
  MSG="x" PANE=%3 bc tell --children --tier escalate --id n3x
  assert_has "for: domain:stats" "$(rec n3x)" "N3: escalate's for: names seats, not the selector"
}

run_discovered_tests
exit_with_results
