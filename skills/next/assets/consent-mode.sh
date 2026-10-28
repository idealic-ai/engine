#!/bin/bash
# consent-mode.sh — decides, from the operator's literal /next argument text, whether this run
# asks (plain) or waives every confirm it can (`all`), and how each composed step is invoked.
# IDE-236.
#
# Usage — the argument text arrives on STDIN through a QUOTED heredoc, never on a shell line:
#
#   bash ~/.claude/engine/skills/next/assets/consent-mode.sh <<'NEXT_ARGS'
#   <the operator's argument text after /next, verbatim>
#   NEXT_ARGS
#
# Any command-line argument makes the run plain: an argument on a shell line has already been
# through quoting, splitting and expansion, so it is not what the operator typed.
#
# Prints key=value lines:
#   mode=plain|all
#   consent=asked|waived                    /next's own one AskUserQuestion
#   reason=exact-all|not-exact-all|argv|no-stdin|stdin-held-open
#   step.resume=in-consent|dispatch         a parked lane's resume (/next's own dispatch)
#   step.decide=own-confirm|decisions-asked+confirms-owed
#                                           /decide — decisions always asked; its confirms
#                                           (bucket batch, panel offer) have no waiver: owed
#   step.snapshot=own-confirm|--yes         /snapshot — its own waiver flag
#   step.groom=own-confirm|waiver-owed      /groom — has no waiver; named owed, still runs
#   step.sweep=own-confirm|nothing-to-waive /sweep — reports only, holds no confirm
#   step.inbox-next=not-reached-unless-asked|not-reached
#                                           the single pick — only an ask for one item
#   step.weave=loom-setting                 the weave /groom dispatches into runs under its
#                                           loom's own Interruption setting; `all` does not reach it
#   halt.snapshot=declined|commit-not-done
#                                           which /snapshot outcomes end the sequence: under
#                                           `all`, any commit outcome but done (skipped, failed,
#                                           aborted, a STOP) ends it
#   notice=none|<template>                  the one line an `all` run prints on EVERY exit
#
# ¶INV_NEXT_ALL_IS_THE_WORD_ONLY: the run is `all` only when stdin is exactly the three bytes
# `all`, optionally followed by the one newline a heredoc adds. Nothing else waives — not
# "do everything", not `ALL`, not `--all`, not `all` with anything after it, not `'all'`, not a
# leading space, not `all` as any other token, not a past run. When in doubt, it asks.
set -uo pipefail

MODE=plain
REASON=not-exact-all
if [ "$#" -gt 0 ]; then
  REASON=argv
elif [ ! -f /dev/stdin ] && [ ! -p /dev/stdin ]; then
  # A tty, /dev/null, or a socket held open (the Bash tool's stdin never closes): nothing to read
  # that is guaranteed to end. Reading it would block forever (§PTF_BLOCKING_CAT_ON_STDIN).
  REASON=no-stdin
else
  # A heredoc arrives as a regular file (bash 3.2, zsh) or a pipe (newer bash). A pipe can be held
  # open by its writer, so the read is bounded: at most 5 bytes, within STDIN_WAIT seconds, or
  # the run is plain (reason=stdin-held-open). Bytes go through od as hex: byte-exact and NUL-safe
  # (a command substitution drops NULs).
  TMP=$(mktemp "${TMPDIR:-/tmp}/consent-mode.XXXXXX")
  exec 3<&0                               # a background job's stdin is /dev/null otherwise
  head -c 5 <&3 >"$TMP" 3<&- &
  READER=$!
  ( sleep "${STDIN_WAIT:-1}" & S=$!; trap 'kill $S 2>/dev/null; exit 0' TERM; wait $S; kill $READER 2>/dev/null ) &
  WATCHDOG=$!
  if wait $READER 2>/dev/null; then
    HEX=$(od -An -tx1 <"$TMP" | tr -d ' \n')
  else
    HEX=""
    REASON=stdin-held-open
  fi
  kill $WATCHDOG 2>/dev/null; wait $WATCHDOG 2>/dev/null
  exec 3<&-
  rm -f "$TMP"
  case "$HEX" in
  616c6c|616c6c0a)
    MODE=all
    REASON=exact-all
    ;;
  esac
fi

if [ "$MODE" = "all" ]; then
  cat <<'EOF'
mode=all
consent=waived
reason=exact-all
step.resume=dispatch
step.decide=decisions-asked+confirms-owed
step.snapshot=--yes
step.groom=waiver-owed
step.sweep=nothing-to-waive
step.inbox-next=not-reached
step.weave=loom-setting
halt.snapshot=commit-not-done
notice=all: ran unconfirmed — <steps run in their waiver form, or none>; resumed unasked — <lanes, or none>; snapshot declined — <commit skipped: why | commit failed: why (e.g. branch creation on main failed) | description rewrite skipped | aborted or stopped: why | none>; posted anyway — <comment, status move | none>; waiver owed — <of: /groom and its /ticket and /inbox-post filings (to /groom's owner), /decide's confirms (to /decide's owner), the weave /groom dispatched into (its loom's setting governs)>; still asked (decisions) — <steps, or none>; stopped at — <step and why | none: reached new work>
EOF
else
  cat <<EOF
mode=plain
consent=asked
reason=$REASON
step.resume=in-consent
step.decide=own-confirm
step.snapshot=own-confirm
step.groom=own-confirm
step.sweep=own-confirm
step.inbox-next=not-reached-unless-asked
step.weave=loom-setting
halt.snapshot=declined
notice=none
EOF
fi
