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
#                           never-pushed "these two are talking: <subject>" note to both managers
#                 escalate  to your manager only (lazy); `for:` records who it was meant for
#                 wake      pushed to idle seats too; needs --wake-reason (the operator's order)
#       The subject defaults to the text's first line.
#   engine tell withdraw <id> --reason "<why>" [--by operator]
#                      the sender, its manager, or the operator (from a non-seat shell) takes it
#                      back: unseen queued copies are removed, a shown one is marked withdrawn, a
#                      seat that had acked it is told. No acknowledgement is asked.
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
