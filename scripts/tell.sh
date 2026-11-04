#!/bin/bash
# scripts/tell.sh — `engine tell`: a statement from one seat to others, the twin of `engine ask`.
# A tell is a broadcast record with tell header lines, so it rides the same per-seat queue and the
# same delivery rule as `engine broadcast`; this script is only the entry point.
#
#   engine tell [send] <audience> [--tier note|lazy|align|escalate|wake] [--subject "<line>"]
#                      [--wake-reason "<why>"] [--from SEAT] [--id SLUG] [--dry-run] <<'MSG'
#   <text>
#   MSG
#       audience: --to SEAT[,SEAT…] · --peers (siblings under your manager) · --parent ·
#                 --children · --subtree SEAT · --all
#       tiers:    note      queued for every seat, never pushed; withdrawable
#                 lazy      the default: pushed only to a seat busy right now, queued otherwise
#                 align     the default for a --to across managers: lazy to the recipient, and a
#                           lazy "these two are talking: <subject>" notice to both managers (lazy
#                           by the operator's ALIGN ruling). A mixed --to list is one tell with
#                           one tier: any recipient across managers makes the whole tell align.
#                 escalate  to your manager only (lazy); `for:` names the seats it was meant for,
#                           and the manager forwards by hand
#                 wake      pushed to idle seats too; needs --wake-reason (the operator's order)
#       No tier but wake (or escalate with --wake-reason) is ever pushed to an idle seat: a seat
#       that is idle or gives no busy reading is queued, or left undelivered when it cannot drain
#       a queue. Only escalate and wake ask for an ack; any seat may still `engine tell ack <id>`,
#       and a withdraw tells the seats that acked.
#       The subject defaults to the text's first line. A tell's id is at most 49 characters.
#       Sticky guidance and retract stay on `engine broadcast` for now.
#   engine tell withdraw <id> --reason "<why>" [--by operator]
#                      the sender, its manager, or the operator (from a non-seat shell) takes it
#                      back. "Its manager" is the sender's live parent in the tmux tree (or, once
#                      the sender has left it, the manager recorded at send time); `engine ask
#                      withdraw` reads FLEET_MANAGES instead, so the two can disagree.
#                      A plain broadcast records no sender-manager, so once its sender has left
#                      the tree only the operator can withdraw it.
#                      Unseen queued copies are removed, a shown one is marked withdrawn, and each
#                      seat that had acked it and is still live gets a lazy tell from you. No
#                      acknowledgement is asked. A go request cannot be withdrawn.
#   engine tell landed --repo R --sha S --subject "<line>" [--paths P…]
#                      a lazy tell to your peers and your manager that a commit landed
#   engine tell status|ack|pending|resend …   as `engine broadcast`
#
# exit codes as `engine broadcast`: 0 ok · 1 written, a seat undelivered · 2 usage/identity ·
# 3 seat not in the live tree · 4 live tree unreadable.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
B="$HERE/broadcast.sh"
case "${1:-}" in
  -h|--help|help|"") awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0" >&2; exit 2 ;;
  send) shift; exec bash "$B" tell "$@" ;;
  withdraw|landed|status|ack|pending|resend) exec bash "$B" "$@" ;;
  *) exec bash "$B" tell "$@" ;;
esac
