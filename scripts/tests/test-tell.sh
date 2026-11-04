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
  act 2007 idle 30; act 2002 busy 0; act 2003 busy 0
  MSG=$'stats schema moved\nsee the commit' PANE=%4 bc tell --to domain:stats --id a1
  assert_eq 0 "$RC" "align: exits 0"
  assert_has "tier: align" "$(rec a1)" "align: a --to across managers defaults to align"
  assert_has "notice: a1.align" "$(rec a1)" "align: the tell links its notice"
  assert_eq "domain:stats" "$(sed -n 's/^audience: //p' "$FIX/bc/a1.md")" "align: straight to the recipient"
  assert_file_exists "$FIX/bc/a1.align.md" "align: the managers' notice is written"
  assert_eq "manager:app manager:domain" "$(sed -n 's/^audience: //p' "$FIX/bc/a1.align.md")" "align: both managers"
  assert_has "tier: note" "$(rec a1.align)" "align: the notice is a note"
  assert_has "notice-of: a1" "$(rec a1.align)" "align: and points back at the tell"
  assert_has "subject: these two are talking: stats schema moved" "$(rec a1.align)" "align: the notice's subject"
  assert_eq "0" "$(sent_count)" "align: nobody is pushed, busy managers included"
  assert_file_exists "$FIX/bc/queued/manager:app/a1.align" "align: queued for the sender's manager"
  assert_file_exists "$FIX/bc/queued/manager:domain/a1.align" "align: and the recipient's"
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
  assert_has "told app:ui (it had acked)" "$OUT" "withdraw: the acked seat is told"
  assert_eq "1" "$(ls "$FIX/bc" | grep -c '^d4\.withdrawn\.md$' | tr -d ' ')" "withdraw: as its own tell record"
  assert_has "notice-of: d4" "$(rec d4.withdrawn)" "withdraw: which points back"
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

run_discovered_tests
exit_with_results
