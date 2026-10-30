#!/bin/bash
# scripts/broadcast.sh — `engine broadcast`: send one piece of guidance to a set of live seats,
# with a durable record, receipts, and standing (sticky) guidance for sessions that start later.
#
#   engine broadcast [send] (--subtree SEAT | --children | --all) [--from SEAT] [--id SLUG]
#                    [--sticky [--expires YYYY-MM-DD[THH:MM:SSZ]]] [--all-live | --queue-idle]
#                    [--dry-run] <<'MSG'
#   <text>
#   MSG
#       Audience from the live tmux tree (@pane_parent chains):
#         --children      the --from seat's direct children
#         --subtree SEAT  every descendant of SEAT (not SEAT itself)
#         --all           every live seat whose pane holds an interactive Claude session,
#                         except --from and the sender (shell panes are skipped and listed)
#       --from (default: this seat) must be in the live tree. The record also names `sent-by`, the
#       caller's own seat resolved live by fleet_self (scripts/lib.sh). Every write — and pending
#       without --for — refuses an identity that is only the launch-time FLEET_PANE cache, or none
#       (outside tmux): there is no unseated send. --dry-run prints the audience and each seat's
#       binding; writes and sends nothing.
#       Live or queued (IDE-352): a seat is pushed live only when its session was active within
#       BROADCAST_LIVE_WINDOW minutes (default 60: a default threshold, a policy choice, not a
#       measured prompt-cache TTL): status "busy" in the seat's ~/.claude/sessions/<pid>.json, or a
#       newest user/assistant event that recent in its bound transcript (the session id's .jsonl,
#       found by lib.sh transcript_by_key; only its tail is read), or, when no transcript resolves
#       or it holds no such event, a statusUpdatedAt that recent. Any other bound seat is queued
#       ("queued <seat> pid=<pid> idle=<N>m", plus " status=<s>" when the reading is neither idle
#       nor empty, e.g. waiting: a seat blocked on a permission prompt needs the operator, not a
#       broadcast; then " via=transcript|status", the reading the idle time came from;
#       $BROADCAST_DIR/queued/<seat>/<id>) and
#       shown once at its next wake by `pending` (SessionStart, and `pending --queued` on each
#       prompt), which then records "delivered <seat> at-wake <time>". A session with no reading is
#       pushed live. --all-live pushes every audience seat whatever its activity (--all still means
#       the audience is every live seat). A queued seat is not a failure: it does not set exit 1.
#       --queue-idle states the default (queue the idle seats) explicitly; it changes nothing today.
#       With BROADCAST_QUEUE_NEEDS_CHOICE=1 a send that would queue any seat, given neither flag,
#       is refused (exit 2, naming the idle seats) before the record is written. Its default is 0
#       until the operator rules on the default (IDE-352 critique MUST-1).
#       exit 0 every seat accepted or queued (or dry run) · 1 record written, ≥1 seat undelivered ·
#       2 usage / identity / existing id · 3 seat not in the live tree · 4 live tree unreadable.
#
#   engine broadcast ack <id>                 this seat applied it (own seat only; must be in the
#                                             audience, or in a live sticky scope)
#   engine broadcast status <id>              per seat: delivered | queued | undelivered |
#                                             not-attempted, then acked | not-acked; complete marker
#   engine broadcast resend <id> [--undelivered] [--all-live | --queue-idle]   explicit retry (no
#                                             automatic one); an idle seat is queued again unless
#                                             --all-live, and a live push clears its queue entry
#   engine broadcast retract <id>             withdraw a sticky broadcast (its sender only)
#   engine broadcast pending [--for SEAT] [--limit N] [--queued]   first the broadcasts queued for
#                                             the seat (oldest first, each with its message; without
#                                             --for each is marked delivered as it is shown, so it
#                                             is shown once; an ack also clears it), then sticky
#                                             broadcasts that apply now
#                                             and are unacked, newest first; N (default 5, 0 = all)
#                                             bounds both together. --queued lists only the queue,
#                                             and exits 0 at once when no seat has one.
#                                             BROADCAST_WAKE_KEY (set by session-start-chunk.sh to
#                                             one SessionStart event's key) keeps what a marking
#                                             pending claimed, and a later pending with the same
#                                             key lists it again: a regenerated preload keeps it
#
#   Go requests (kit LANDING.md "Get the go"; IDE-350):
#   engine broadcast go-request --pr N [--rows ROW[,ROW…]] [--paths PATH[,PATH…]] [--repo PATH]
#                    [--commits RANGE] [--owners FILE] [--id SLUG] [--all-live] [--dry-run]
#       --rows, --paths or both; at least one. A --paths PATH goes straight to the owners map, as a
#       row's owner path does; the audience is the union of the rows' seats and the paths' seats,
#       and each seat's receipt covers all its paths from either flag.
#       ROW is a CONTRACTS.md registry anchor (#answer-envelope → answer-envelope). Its owner paths
#       are the backticked paths in that row's Owner cell, read from CONTRACTS.md at the range's tip
#       (`git rev-parse` of the range's end) AND at its base (the merge-base): a PR that repoints an
#       Owner cell still asks the owner it repoints away from. Each path's seat comes from the owners
#       map (FILE, else BROADCAST_OWNERS, else ~/.claude/data/yarik/owners.tsv: lines
#       "<path-glob> <seat>", a trailing / covers a tree; the pattern with the most /-separated
#       segments wins; at equal segments a pattern with no * or ? (a path or a dir/ prefix) beats
#       one holding either, so "resource-* A" plus "resource-kernel/ B" gives resource-kernel to B
#       and a catch-all "* S" is the default; two literals or two globs at equal segments that map
#       to different seats tie and refuse). Per owner and commit the receipt is
#       `git show --text <commit> -- <paths> | git patch-id --stable`; merge commits are skipped
#       (--no-merges). RANGE defaults to origin/main..HEAD; a rev without ".." is one commit. ONE
#       broadcast to exactly the owner seats; each seat's message carries only its own receipt lines
#       ("receipt path <seat> <commit> <id> -- <paths>"; "path" is the receipt kind). Paths and rows
#       are literal, never glob-expanded. Refuses, naming the row or path: an unknown row, no owner
#       path, a path no seat maps or two seats map equally, an owner seat not in the live tree
#       (exit 3), a row whose receipt is empty on every commit, an owner whose --paths give an empty
#       receipt on every commit (exit 2).
#   engine broadcast ack <id>                 on a go request: a GO, bound to the receipts sent
#   engine broadcast decline <id> --reason "<one line>"   on a go request only; a reason is required
#                                             One answer per seat, claimed atomically: a GO and a
#                                             decline do not replace each other (a changed change is
#                                             a new go-request).
#       A GO records attribution, not authentication: the answering seat is this pane's live label
#       (fleet_self, read from $TMUX_PANE), and any process can set TMUX_PANE to another seat's pane
#       and answer as that seat. It is cooperative bookkeeping, not a signature.
#   engine broadcast status <id>              on a go request: per owner GO <ids> | GO (no receipts)
#                                             | DECLINED <reason> | PENDING
#   engine broadcast go-check <id> --commits RANGE [--repo PATH]   recomputes the receipts on RANGE
#                                             in --repo, else in the cwd's git toplevel (the worktree
#                                             being landed; never the request's recorded repo):
#                                             0 only when every owner of the requested rows has a GO
#                                             whose ids are exactly RANGE's ids on that owner's paths
#                                             (matched by id, so a re-pick keeps its go); nothing
#                                             outside those paths is checked. 1 lists PENDING /
#                                             DECLINED / MOVED owners. MOVED means the diff text on
#                                             the owner's paths changed (patch-id --stable ignores
#                                             line numbers, so a re-pick that only shifts lines keeps
#                                             its id); a change only in context lines is covered by
#                                             LANDING.md step 4's judgement, anything else needs the
#                                             owner's fresh go. 2 usage.
#
# Delivery binds a seat by PANE, never by name alone: pane id → #{pane_pid} → the descendant
# process that has a ~/.claude/sessions/<pid>.json of kind "interactive". Exactly one such session, whose registered
# name equals the pane label (case-insensitive), is a target; none, several, or a different name
# is reported undelivered with the reason. The push itself is deliver.ts pushToSeat (the one
# module that knows the socket protocol), given a sessions dir holding only that pid's files, so
# it cannot pick another process. The message is the broadcast's text, cut past
# BROADCAST_INLINE_MAX characters (counted in UTF-8 whatever the caller's locale) with the record
# path for the rest, then one line naming the sender and the ack command:
# `ack (from <seat>): engine broadcast ack <id>` — the sent-by seat, or on a resend the resender's.
# The record stays the durable copy. "delivered" = the socket accepted the bytes (a stopped
# process still accepts); acks are the proof it was read.
#
# Files: $BROADCAST_DIR (default ~/.claude/data/yarik/broadcasts): <id>.md record,
#        <id>.acks.d/<seat> acks, sticky/<id> the sticky index. A go request's record adds the
#        headers kind: go-request, pr, rows and/or paths, repo, commits, and "receipt <kind> <seat> <commit> <id>
#        -- <paths>" / "untouched <kind> <seat> <commit> -- <paths>" lines in its text (round-1
#        records, without the kind, still read as kind "path"); a GO's ack file is
#        "<seat>\t<at>\tGO\t<ids>", a decline is <id>.declines.d/<seat> "<seat>\t<at>\t<reason>",
#        and <id>.answers.d/<seat> ("GO" | "DECLINED") claims the seat's one answer first.
# Env:   HOP_LIVE_PANES / HOP_TMUX_SOCKET — as hop.sh. BROADCAST_LIB — lib.sh for fleet_self.
#        ASK_SESSIONS_DIR — the session registry (shared with deliver.ts).
#        BROADCAST_INLINE_MAX — the cut, in characters (default 1500); anything but a positive
#        integer of at most 9 digits warns on stderr and falls back to 1500.
#        BROADCAST_LIVE_WINDOW — minutes a seat counts as active (default 60); anything but a
#        whole number of at most 6 digits warns and falls back to 60. 0 pushes only busy seats.
#        Test seams: BROADCAST_DELIVER (`<cmd> <seat> <pid> <message>`, exit 0 = delivered),
#        BROADCAST_PANE_PIDS ("<pane_id> <pid>" lines), BROADCAST_PS_FILE ("<pid> <ppid>" lines).
set -uo pipefail

die() { local rc="$1"; shift; echo "broadcast: $*" >&2; exit "$rc"; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# lib.sh beside this script first (a tree under test uses its own), then the installed one. An
# explicit BROADCAST_LIB is used as given: a missing one is an error, never a silent fallback.
if [ -n "${BROADCAST_LIB:-}" ]; then LIB_SH="$BROADCAST_LIB"
else LIB_SH="$HERE/lib.sh"; [ -f "$LIB_SH" ] || LIB_SH="$HOME/.claude/scripts/lib.sh"; fi
BDIR="${BROADCAST_DIR:-$HOME/.claude/data/yarik/broadcasts}"
SESS_DIR="${ASK_SESSIONS_DIR:-$HOME/.claude/sessions}"
DELIVER_TS="${BROADCAST_DELIVER_TS:-$HOME/.claude/engine/tools/ask-app/src/lib/deliver.ts}"
ID_RE='^[a-z0-9][a-z0-9._-]{0,63}$'

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
tm() { if [ -n "${HOP_TMUX_SOCKET:-}" ]; then tmux -L "$HOP_TMUX_SOCKET" "$@"; else tmux "$@"; fi; }

# need_val <flag> <argc> <next> — a value-taking flag must have a value that is not another flag.
need_val() { [ "$2" -ge 2 ] && [ -n "$3" ] && [[ "$3" != -* ]] || die 2 "$1 needs a value"; }
# A seat is one token: no whitespace (it would split the tree's columns or forge a header line),
# no '/' (it names an ack file), no leading '-'.
valid_seat() { [[ "$2" =~ ^[^[:space:]/-][^[:space:]/]*$ ]] || die 2 "$1 '$2' is not a seat name"; }
valid_id() { [[ "$1" =~ $ID_RE ]] || die 2 "bad id '$1' (lowercase, digits, . _ -; ≤64; no path)"; }

# The live tree, in hop.sh's shape "<window:label> <pane_id> <parent|->". hop.sh cannot be
# sourced (its dispatcher runs at load) and has no `tree` subcommand yet, so this body is a copy of
# hop.sh live_tree(); test-broadcast.sh test_tree_parity fails the moment the two differ.
live_tree() {
  if [ -n "${HOP_LIVE_PANES:-}" ]; then
    [ -r "$HOP_LIVE_PANES" ] || die 4 "cannot read the live tree: $HOP_LIVE_PANES is not readable"
    cat "$HOP_LIVE_PANES"
    return
  fi
  local out
  out=$(tm list-panes -a -F '#{window_name}:#{@pane_label} #{pane_id} #{?@pane_parent,#{@pane_parent},-}' 2>/dev/null) \
    || die 4 "cannot read the live tree: tmux list-panes failed"
  [ -n "$out" ] || die 4 "cannot read the live tree: tmux returned no panes"
  echo "$out"
}

# resolve_self — sets SELF and SELF_RC from lib.sh fleet_self (0 live · 3 FLEET_PANE cache only ·
# other: none). Its stderr (stale / cache notes) passes through to the caller.
SELF="" SELF_RC=0
resolve_self() {
  SELF_RC=0
  [ -f "$LIB_SH" ] || die 2 "the fleet identity rule's lib.sh is missing: $LIB_SH"
  SELF=$(FLEET_LIVE_PANES="${HOP_LIVE_PANES:-}" FLEET_TMUX_SOCKET="${HOP_TMUX_SOCKET:-}" \
    FLEET_WARN_PREFIX=broadcast bash -c 'source "$1" >/dev/null 2>&1 || exit 9; type fleet_self >/dev/null 2>&1 || exit 8; fleet_self' _ "$LIB_SH") \
    || SELF_RC=$?
  [ "$SELF_RC" = 9 ] && die 2 "cannot source the fleet identity rule from $LIB_SH"
  [ "$SELF_RC" = 8 ] && die 2 "$LIB_SH has no fleet_self (the live-first identity rule); this lib.sh predates it"
  return 0
}
# live_self — the identity a write (send, ack, resend, retract) or the sticky preload may carry:
# the live pane label only. A cache-only identity is refused (a stale FLEET_PANE names whichever
# seat now holds that label), and so is no identity at all — there is no unseated send.
live_self() {
  resolve_self
  case "$SELF_RC" in
    0) valid_seat "this seat" "$SELF"; echo "$SELF" ;;
    3) die 2 "this seat's identity is only the launch-time FLEET_PANE cache ('$SELF'); the live pane label cannot be read — refusing" ;;
    *) die 2 "cannot resolve this seat's identity (no live pane label); run from a labelled fleet pane" ;;
  esac
}

in_tree() { awk -v s="$2" '$1 == s { f = 1 } END { exit !f }' <<<"$1"; }
parent_of() { awk -v s="$2" '$1 == s { print $3; exit }' <<<"$1"; }
pane_of() { awk -v s="$2" '$1 == s { print $2; exit }' <<<"$1"; }
panes_named() { awk -v s="$2" '$1 == s { n++ } END { print n + 0 }' <<<"$1"; }
# Labelled seats only: "win:" (no @pane_label) is not addressable.
seats() { awk '$1 !~ /:$/ && !seen[$1]++ { print $1 }' <<<"$1"; }
children_of() { awk -v s="$2" '$3 == s && $1 !~ /:$/ && !seen[$1]++ { print $1 }' <<<"$1"; }

descendants_of() { # breadth-first; bounded against a looping tree
  local tree="$1" frontier="$2" out="" next c k n=0
  while [ -n "$frontier" ]; do
    n=$((n + 1)); [ "$n" -le 50 ] || die 4 "the parent chain loops under '$2'"
    next=""
    for c in $frontier; do
      while IFS= read -r k; do
        [ -n "$k" ] || continue
        case " $out " in *" $k "*) continue ;; esac
        out+="${out:+ }$k"; next+="${next:+ }$k"
      done < <(children_of "$tree" "$c")
    done
    frontier="$next"
  done
  echo "$out"
}

ancestors_of() {
  local tree="$1" seat="$2" p n=0
  while :; do
    p=$(parent_of "$tree" "$seat")
    [ -n "$p" ] && [ "$p" != "-" ] || break
    n=$((n + 1)); [ "$n" -le 50 ] || break
    echo "$p"; seat="$p"
  done
}

# ---- binding a seat to the one Claude session in its pane (M2) ----
PS_TABLE="" REGISTRY="" BIND_LOADED=0
load_bindings() {
  [ "$BIND_LOADED" = 1 ] && return 0
  if [ -n "${BROADCAST_PS_FILE:-}" ]; then PS_TABLE=$(cat "$BROADCAST_PS_FILE"); else PS_TABLE=$(ps -A -o pid=,ppid=); fi
  local f
  REGISTRY=""
  for f in "$SESS_DIR"/[0-9]*.json; do
    [ -r "$f" ] || continue
    # Interactive sessions only: a bg spare (kind "bg") carries a seat's name but is not the agent
    # in the pane, and the shared daemon that hosts spares sits under whichever pane spawned it.
    REGISTRY+=$(jq -r 'select(.messagingSocketPath and .kind == "interactive") | [(.pid|tostring), (.name // "")] | @tsv' "$f" 2>/dev/null)$'\n'
  done
  BIND_LOADED=1
}
pane_pid() {
  if [ -n "${BROADCAST_PANE_PIDS:-}" ]; then awk -v p="$1" '$1 == p { print $2; exit }' "$BROADCAST_PANE_PIDS"
  else tm display -p -t "$1" '#{pane_pid}' 2>/dev/null; fi
}
# bind <tree> <seat> → "ok <pid> <name>" | "no-session" | "mismatch <pid:name>" |
#                      "ambiguous <pid:name,…>" | "duplicate-label <n>" | "no-pane"
bind() {
  local tree="$1" seat="$2" pane root n
  n=$(panes_named "$tree" "$seat")
  [ "$n" -le 1 ] || { echo "duplicate-label $n"; return; }
  pane=$(pane_of "$tree" "$seat"); [ -n "$pane" ] || { echo no-pane; return; }
  root=$(pane_pid "$pane"); [ -n "$root" ] || { echo no-session; return; }
  load_bindings
  awk -v root="$root" -v seat="$seat" -F'\t' '
    FNR == NR { split($0, a, " "); if (a[1] != "") { alive[a[1]] = 1; kids[a[2]] = kids[a[2]] " " a[1] }; next }
    $1 != "" { reg[$1] = $2 }
    END {
      q[1] = root; h = 1; t = 1; seen[root] = 1
      while (h <= t) { p = q[h++]; m = split(kids[p], ks, " "); for (i = 1; i <= m; i++) if (!(ks[i] in seen)) { seen[ks[i]] = 1; q[++t] = ks[i] } }
      c = 0; list = ""
      for (i = 1; i <= t; i++) { p = q[i]; if ((p in reg) && (p in alive)) { c++; pid = p; nm = reg[p]; list = list (list == "" ? "" : ",") p ":" reg[p] } }
      if (c == 0) print "no-session"
      else if (c > 1) print "ambiguous " list
      else if (tolower(nm) != tolower(seat)) print "mismatch " list
      else print "ok " pid " " nm
    }' <(printf '%s\n' "$PS_TABLE") <(printf '%s' "$REGISTRY")
}

deliver() { # deliver <seat> <pid> <name> <message> → one status line; rc 0 = delivered
  if [ -n "${BROADCAST_DELIVER:-}" ]; then "$BROADCAST_DELIVER" "$1" "$2" "$4"; return; fi
  [ -r "$DELIVER_TS" ] || { echo "undelivered: $DELIVER_TS not found"; return 1; }
  local one rc f
  one=$(mktemp -d) || { echo "undelivered: mktemp failed"; return 1; }
  for f in "$SESS_DIR/$2.json" "$SESS_DIR/$2".*.key; do [ -e "$f" ] && ln -s "$f" "$one/"; done
  BC_NAME="$3" BC_MSG="$4" BC_MOD="$DELIVER_TS" BC_DIR="$one" node --no-warnings --input-type=module -e '
    import { pathToFileURL } from "node:url";
    const { pushToSeat } = await import(pathToFileURL(process.env.BC_MOD).href);
    const r = await pushToSeat(process.env.BC_NAME, process.env.BC_MSG, { sessionsDir: process.env.BC_DIR });
    console.log(r.status + (r.reason ? ": " + r.reason : ""));
    process.exit(r.status === "delivered" ? 0 : 1);' 2>&1
  rc=$?
  rm -rf "$one"
  return "$rc"
}

# ---- who is pushed live, who is queued (IDE-352) ----
# A push wakes the seat, and a seat whose prompt cache has gone cold re-reads its whole context to
# take it. So a bound seat is pushed live only when its session was active within
# BROADCAST_LIVE_WINDOW minutes (default 60: a default threshold, chosen as policy; no TTL for these
# sessions' prompt cache has been confirmed); any other is queued and shown at its next wake by
# `pending`. The reading is the session registry file bind() already
# reads (~/.claude/sessions/<pid>.json, written by Claude Code itself): status "busy" is mid-turn,
# so active; otherwise statusUpdatedAt (epoch ms) is when the status last changed, which for an
# idle seat is the end of its last turn. A file with neither field gives no reading, and a seat
# with no reading is pushed live, as before this rule. --all-live pushes every seat.
# QUEUE_MODE is the sender's explicit choice: "" (none given), all-live or queue-idle. Only
# queue_choice_gate reads it; LIVE_ALL is what fan_out obeys.
LIVE_ALL=0
QUEUE_MODE=""
# set_queue_mode <all-live|queue-idle> — one choice per command.
set_queue_mode() {
  [ -z "$QUEUE_MODE" ] || [ "$QUEUE_MODE" = "$1" ] || die 2 "--all-live and --queue-idle contradict each other; give one"
  QUEUE_MODE="$1"; [ "$1" = all-live ] && LIVE_ALL=1
  return 0
}
BROADCAST_LIVE_WINDOW="${BROADCAST_LIVE_WINDOW:-60}"
if ! [[ "$BROADCAST_LIVE_WINDOW" =~ ^[0-9]{1,6}$ ]]; then
  echo "broadcast: BROADCAST_LIVE_WINDOW '$BROADCAST_LIVE_WINDOW' is not a whole number of minutes; using 60" >&2
  BROADCAST_LIVE_WINDOW=60
fi
# Since round 3 (operator ruling, IDE-352) the reading is the seat's bound transcript first: the
# newest user or assistant event's `timestamp` in ~/.claude/projects/*/<sessionId>.jsonl, found by
# lib.sh transcript_by_key (the rule Guard 3 of hooks/stop-auto-continue.sh uses), and read from the
# last BROADCAST_TRANSCRIPT_TAIL bytes only (default 1 MiB; a transcript can be large). A line that
# does not parse is skipped. statusUpdatedAt is the fallback when no transcript resolves or its tail
# holds no such event. A busy session is active whichever source is read.
BROADCAST_TRANSCRIPT_TAIL="${BROADCAST_TRANSCRIPT_TAIL:-1048576}"
[[ "$BROADCAST_TRANSCRIPT_TAIL" =~ ^[1-9][0-9]{0,9}$ ]] || BROADCAST_TRANSCRIPT_TAIL=1048576
# transcript_of <sessionId> <cwd> → the transcript path, by lib.sh's rule; rc 1 when none.
transcript_of() {
  [[ "$1" =~ ^[A-Za-z0-9_-]{1,128}$ ]] || return 1
  [ -f "$LIB_SH" ] || return 1
  bash -c 'source "$1" >/dev/null 2>&1 || exit 9; type transcript_by_key >/dev/null 2>&1 || exit 8; transcript_by_key "$2.jsonl" "$3" "$4"' \
    _ "$LIB_SH" "$1" "$2" "${BROADCAST_PROJECTS_DIR:-$HOME/.claude/projects}" 2>/dev/null
}
# transcript_ts <file> → epoch seconds of the newest user/assistant event in its tail; rc 1 when none.
# When the file is longer than the tail, the tail's first (partial) line is dropped.
transcript_ts() {
  local size out
  size=$(wc -c < "$1" 2>/dev/null | tr -d ' ') || return 1
  out=$(tail -c "$BROADCAST_TRANSCRIPT_TAIL" "$1" 2>/dev/null \
    | { if [ "${size:-0}" -gt "$BROADCAST_TRANSCRIPT_TAIL" ]; then sed 1d; else cat; fi; } \
    | jq -nR '[inputs | fromjson? | objects | select(.type == "user" or .type == "assistant")
              | .timestamp | strings | try (sub("\\.[0-9]+"; "") | fromdateiso8601) catch empty]
              | max // empty' 2>/dev/null) || return 1
  [[ "$out" =~ ^[0-9]{9,11}$ ]] || return 1
  echo "$out"
}
# idle_for <pid> → prints "<minutes idle> <status> <via>" (via: transcript | status) and returns 0
# when the seat is past the window; returns 1 (active, or no reading) otherwise.
idle_for() {
  local st t sid cwd f last="" via=status age
  # Joined on US (0x1f), not tab: tab is IFS whitespace, so an empty field would shift the rest.
  IFS=$'\x1f' read -r st t sid cwd < <(jq -r '[(.status // "" | tostring), (.statusUpdatedAt // "" | tostring),
      (.sessionId // "" | tostring), (.cwd // "" | tostring)] | map(gsub("[\u001f\n]"; " ")) | join("\u001f")' \
      "$SESS_DIR/$1.json" 2>/dev/null) || return 1
  [ "$st" != busy ] || return 1
  if [ -n "$sid" ] && f=$(transcript_of "$sid" "$cwd") && last=$(transcript_ts "$f"); then
    via=transcript
  elif [[ "$t" =~ ^[0-9]{10,16}$ ]]; then
    last=$(( t / 1000 ))
  else
    return 1
  fi
  age=$(( $(date +%s) - last ))
  [ "$age" -gt $(( BROADCAST_LIVE_WINDOW * 60 )) ] || return 1
  echo "$(( age / 60 )) ${st:-idle} $via"
}
# idle_words <idle_for output> → "idle=<N>m", plus " status=<s>" unless the status is idle, then
# " via=<transcript|status>": which reading the idle time came from.
idle_words() {
  local m st via; read -r m st via <<<"$1"
  printf 'idle=%sm' "$m"; [ "$st" = idle ] || printf ' status=%s' "$st"
  [ -z "$via" ] || printf ' via=%s' "$via"
}
queue_dir() { echo "$BDIR/queued/$(ack_key "$1")"; }
# bind_note <bind-result> — the dry run's "(queue: idle Nm)" for a bound seat that would be queued.
bind_note() {
  local m pid
  [ "$LIVE_ALL" = 0 ] && [ "${1%% *}" = ok ] || return 0
  read -r _ pid _ <<<"$1"
  m=$(idle_for "$pid") && echo " (queue: $(idle_words "$m"))"
  return 0
}

# queue_choice_gate <tree> <seats…> — the one place a send may refuse to queue silently (MUST-1).
# With BROADCAST_QUEUE_NEEDS_CHOICE=1 and no --all-live or --queue-idle, a send that would queue
# any seat is refused, exit 2, before its record is written, naming each idle seat. Its default is
# 0 until the operator rules on the default; making the refusal the default is that one value.
BROADCAST_QUEUE_NEEDS_CHOICE="${BROADCAST_QUEUE_NEEDS_CHOICE:-0}"
queue_choice_gate() {
  local tree="$1" s b pid m idle="" k=0 n=0; shift
  [ "$BROADCAST_QUEUE_NEEDS_CHOICE" = 1 ] && [ -z "$QUEUE_MODE" ] || return 0
  for s in "$@"; do
    n=$((n + 1)); b=$(bind "$tree" "$s")
    [ "${b%% *}" = ok ] || continue
    read -r _ pid _ <<<"$b"
    m=$(idle_for "$pid") || continue
    idle+="${idle:+, }$s ($(idle_words "$m"))"; k=$((k + 1))
  done
  [ "$k" = 0 ] || die 2 "$k of $n seats would be queued, not woken: $idle. Give --all-live to wake them, or --queue-idle to queue them until their next wake"
}

BROADCAST_INLINE_MAX="${BROADCAST_INLINE_MAX:-1500}"
if ! [[ "$BROADCAST_INLINE_MAX" =~ ^[1-9][0-9]{0,8}$ ]]; then
  echo "broadcast: BROADCAST_INLINE_MAX '$BROADCAST_INLINE_MAX' is not a positive integer; using 1500" >&2
  BROADCAST_INLINE_MAX=1500
fi

# message <id> <text> <record> <sender> — what reaches a seat: the broadcast's own text, then one
# line naming the sender and the ack command. Text past BROADCAST_INLINE_MAX characters is cut and
# the record path given for the rest. The locale is pinned so ${#…} and ${…:0:N} count characters,
# never bytes: launchd, cron and `env -i` start with no LANG, and a byte cut can split a character.
message() {
  local LC_ALL=en_US.UTF-8
  local text="$2"
  if [ "${#text}" -gt "$BROADCAST_INLINE_MAX" ]; then
    text="${text:0:$BROADCAST_INLINE_MAX}…"$'\n'"full text: $3"
  fi
  printf '%s\nack (from %s): engine broadcast ack %s' "$text" "$4" "$1"
}

# text_of <record> — the text exactly as cmd_send wrote it: from the first line that is exactly
# "## Text" to the LAST line that is exactly "## Delivery" (the writer emits it right after the
# text, and nothing later writes another), less the one blank line the writer puts on each side.
# The text itself may hold any "## " line, "## Text…" and "## Delivery" included.
text_of() {
  awk '{ l[NR] = $0 } $0 == "## Text" && !s { s = NR } $0 == "## Delivery" { e = NR }
    END { if (!s) exit; if (e <= s) e = NR + 1; a = s + 1; b = e - 1
          if (a <= b && l[a] == "") a++; if (a <= b && l[b] == "") b--
          for (i = a; i <= b; i++) print l[i] }' "$1"
}

header() { # header <record> <key> — value from the header block only (before "## Text")
  awk -v k="$2" '/^## Text/ { exit } index($0, k ": ") == 1 { print substr($0, length(k) + 3); exit }' "$1"
}
record_of() {
  [ -n "${1:-}" ] || die 2 "an id is required"
  valid_id "$1"
  [ -r "$BDIR/$1.md" ] || die 2 "no broadcast '$1' in $BDIR"
  echo "$BDIR/$1.md"
}
ack_key() { tr '[:upper:]' '[:lower:]' <<<"$1"; }
acked() { [ -e "$BDIR/$1.acks.d/$(ack_key "$2")" ]; }
retracted() { grep -q '^retracted: ' "$1"; }
expired() { local e; e=$(header "$1" expires); [ -n "$e" ] && [ "$e" != "-" ] && [[ "$(now)" > "$e" ]]; }

# write_record <rec> <id> <from> <sent_by> <scope> <sticky> <expires> <audience> <text> <extra>
# Created atomically (noclobber) and in full BEFORE any delivery: a second send with the same id
# fails here, and a fan-out that dies midway still leaves the guidance (status: not-attempted).
# <extra> is more header lines ("key: value\n"…) after audience; empty for an ordinary broadcast.
write_record() {
  local rec="$1"
  if ! ( set -C
         { printf '# Broadcast %s\n\nid: %s\nfrom: %s\nsent-by: %s\nat: %s\nscope: %s\nsticky: %s\nexpires: %s\naudience: %s\n%s\n## Text\n\n' \
             "$2" "$2" "$3" "$4" "$(now)" "$5" "$6" "$7" "$8" "${10}"
           printf '%s\n' "$9"
           printf '\n## Delivery\n\n'; } > "$rec" ) 2>/dev/null; then
    [ -e "$rec" ] && die 2 "broadcast '$2' already exists: $rec (never overwritten)"
    die 2 "cannot write $rec"
  fi
}

# SEAT_MSG — when set, the name of a function that prints the message for one seat (a go request
# gives each owner only its own receipt lines); otherwise every seat gets <message>.
SEAT_MSG=""
# fan_out <tree> <id> <rec> <message> <seats…> — deliver, append one line per seat, then done.
fan_out() {
  local tree="$1" id="$2" rec="$3" msg="$4" s b res m idle qd hold rc=0 ok=0 bad=0 q=0; shift 4
  for s in "$@"; do
    b=$(bind "$tree" "$s")
    if [ "${b%% *}" = ok ]; then
      local pid name
      read -r _ pid name <<<"$b"
      # An idle seat is queued, not pushed (IDE-352). A queue that cannot be written falls
      # through to the live push: a broadcast is never left neither pushed nor queued.
      qd=$(queue_dir "$s")
      # A re-queue keeps an existing entry as it is (its mtime is its place in the queue).
      if [ "$LIVE_ALL" = 0 ] && idle=$(idle_for "$pid") && mkdir -p "$qd" 2>/dev/null \
         && { [ -f "$qd/$id" ] || : > "$qd/$id"; } 2>/dev/null; then
        echo "queued $s pid=$pid $(idle_words "$idle")" | tee -a "$rec"; q=$((q + 1)); continue
      fi
      m="$msg"; [ -z "$SEAT_MSG" ] || m=$("$SEAT_MSG" "$s")
      # A queue entry is set aside BEFORE the push: the push fires the seat's UserPromptSubmit
      # hook, which would otherwise show the same item again from the queue. Dropped once the push
      # lands; put back when it fails, so the seat still sees it at its next wake.
      hold=""
      if [ -e "$qd/$id" ]; then hold="$qd/.$id.hold.$$"; mv -f "$qd/$id" "$hold" 2>/dev/null || hold=""; fi
      if res=$(deliver "$s" "$pid" "$name" "$m"); then
        [ -z "$hold" ] || rm -f "$hold"
        echo "delivered $s pid=$pid" | tee -a "$rec"; ok=$((ok + 1)); continue
      fi
      [ -z "$hold" ] || mv -f "$hold" "$qd/$id" 2>/dev/null || true
      b="${res:-no reason}"
    fi
    echo "undelivered $s — $b" | tee -a "$rec"; bad=$((bad + 1)); rc=1
  done
  local qn=""; [ "$q" = 0 ] || qn=" queued=$q"
  echo "done: rc=$rc delivered=$ok undelivered=$bad$qn at $(now)" >> "$rec"
  return "$rc"
}

cmd_send() {
  local scope="" target="" from="" id="" sticky=no expires="-" dry=0 n=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --subtree) need_val "$1" $# "${2:-}"; scope=subtree; target="$2"; n=$((n + 1)); shift 2 ;;
      --children) scope=children; n=$((n + 1)); shift ;;
      --all) scope=all; n=$((n + 1)); shift ;;
      --from) need_val "$1" $# "${2:-}"; from="$2"; shift 2 ;;
      --id) need_val "$1" $# "${2:-}"; id="$2"; shift 2 ;;
      --expires) need_val "$1" $# "${2:-}"; expires="$2"; shift 2 ;;
      --sticky) sticky=yes; shift ;;
      --all-live) set_queue_mode all-live; shift ;;
      --queue-idle) set_queue_mode queue-idle; shift ;;
      --dry-run) dry=1; shift ;;
      *) die 2 "unknown argument $1" ;;
    esac
  done
  [ "$n" = 1 ] || die 2 "give exactly one of --subtree SEAT, --children, --all"
  [ -z "$target" ] || valid_seat --subtree "$target"
  [ -z "$from" ] || valid_seat --from "$from"
  if [ "$expires" != "-" ]; then
    [ "$sticky" = yes ] || die 2 "--expires applies only to --sticky"
    [[ "$expires" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && expires="${expires}T23:59:59Z"
    [[ "$expires" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || die 2 "--expires takes YYYY-MM-DD or YYYY-MM-DDTHH:MM:SSZ"
  fi
  if [ -n "$id" ]; then valid_id "$id"
  else id="bc-$(date -u +%Y%m%dt%H%M%Sz)-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"; fi
  local text
  text=$(cat)
  [ -n "${text//[[:space:]]/}" ] || die 2 "empty message: pass the text on stdin"

  # The tree first: an unreadable tree is exit 4 whatever the identity read then says.
  local tree audience="" skipped="" s b sent_by
  tree=$(live_tree) || exit $?
  sent_by=$(live_self) || exit $?
  [ -n "$from" ] || from="$sent_by"
  in_tree "$tree" "$from" || die 3 "sender '$from' is not in the live tree"
  case "$scope" in
    children) audience=$(children_of "$tree" "$from" | tr '\n' ' '); scope="children:$from" ;;
    subtree)
      in_tree "$tree" "$target" || die 3 "seat '$target' is not in the live tree"
      audience=$(descendants_of "$tree" "$target"); scope="subtree:$target" ;;
    all)
      for s in $(seats "$tree"); do
        [ "$s" = "$from" ] || [ "$s" = "$sent_by" ] && continue
        if [ "$(bind "$tree" "$s")" = no-session ]; then skipped+="${skipped:+ }$s"; else audience+="${audience:+ }$s"; fi
      done ;;
  esac
  audience=$(tr -s ' \n' ' ' <<<"$audience" | sed 's/^ //; s/ $//')

  local rec="$BDIR/$id.md" msg
  msg=$(message "$id" "$text" "$rec" "$sent_by")
  printf 'id: %s\nfrom: %s\nsent-by: %s\nscope: %s\nsticky: %s\nexpires: %s\naudience: %s\n' \
    "$id" "$from" "$sent_by" "$scope" "$sticky" "$expires" "$audience"
  [ -z "$skipped" ] || echo "skipped (no Claude session in pane): $skipped"
  if [ "$dry" = 1 ]; then
    for s in $audience; do b=$(bind "$tree" "$s"); echo "binds $s → $b$(bind_note "$b")"; done
    echo "message: $msg"
    echo "dry-run: nothing written, nothing sent"
    return 0
  fi
  # shellcheck disable=SC2086
  queue_choice_gate "$tree" $audience
  mkdir -p "$BDIR" || die 2 "cannot create $BDIR"

  write_record "$rec" "$id" "$from" "$sent_by" "$scope" "$sticky" "$expires" "$audience" "$text" ""
  if [ "$sticky" = yes ]; then mkdir -p "$BDIR/sticky" && : > "$BDIR/sticky/$id"; fi

  local rc=0
  [ -n "$audience" ] || echo "(no seats in scope)" | tee -a "$rec"
  # shellcheck disable=SC2086
  fan_out "$tree" "$id" "$rec" "$msg" $audience || rc=$?
  echo "record: $rec"
  return "$rc"
}

# last_state <rec> <seat> → delivered | undelivered | queued | not-attempted. A queued seat reads
# delivered once `pending` has shown it ("delivered <seat> at-wake <time>").
last_state() {
  awk -v s="$2" '/^## Delivery/ { d = 1; next } d && ($1 == "delivered" || $1 == "undelivered" || $1 == "queued") && $2 == s { st = $1 }
    END { print (st == "" ? "not-attempted" : st) }' "$1"
}

cmd_resend() {
  local id="" only=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --undelivered) only=1; shift ;;
      --all-live) set_queue_mode all-live; shift ;;
      --queue-idle) set_queue_mode queue-idle; shift ;;
      -*) die 2 "resend: unknown argument $1" ;;
      *) [ -z "$id" ] || die 2 "resend: one id"; id="$1"; shift ;;
    esac
  done
  local rec by tree s seats=()
  rec=$(record_of "$id") || exit $?
  retracted "$rec" && die 2 "broadcast '$id' was retracted"
  by=$(live_self) || exit $?
  tree=$(live_tree) || exit $?
  for s in $(header "$rec" audience); do
    if [ "$only" = 1 ] && [ "$(last_state "$rec" "$s")" = delivered ]; then continue; fi
    seats+=("$s")
  done
  echo "resend: by $by at $(now) (${#seats[@]} seats)" | tee -a "$rec"
  if is_go "$rec"; then GO_ID="$id" GO_REC="$rec" GO_BY="$by" GO_TEXT=$(text_of "$rec"); SEAT_MSG=go_msg_for; fi
  fan_out "$tree" "$id" "$rec" "$(message "$id" "$(text_of "$rec")" "$rec" "$by")" "${seats[@]+"${seats[@]}"}"
}

# in_live_scope <tree> <seat> <scope>
in_live_scope() {
  case "$3" in
    all) in_tree "$1" "$2" ;;
    children:*) [ "$(parent_of "$1" "$2")" = "${3#children:}" ] ;;
    subtree:*) case " $(ancestors_of "$1" "$2" | tr '\n' ' ') " in *" ${3#subtree:} "*) return 0 ;; *) return 1 ;; esac ;;
    *) return 1 ;;
  esac
}

cmd_ack() {
  local id="${1:-}"; [ $# -le 1 ] || die 2 "ack takes one id (an ack is always this seat's own)"
  local rec seat
  rec=$(record_of "$id") || exit $?
  seat=$(live_self) || exit $?
  if ! grep -qxF -- "$seat" <<<"$(tr ' ' '\n' <<<"$(header "$rec" audience)")"; then
    local tree
    [ "$(header "$rec" sticky)" = yes ] && ! retracted "$rec" || die 2 "'$seat' is not in the audience of '$id'"
    tree=$(live_tree) || exit $?
    in_live_scope "$tree" "$seat" "$(header "$rec" scope)" || die 2 "'$seat' is not in the audience or the live scope of '$id'"
  fi
  mkdir -p "$BDIR/$id.acks.d" || die 2 "cannot create the ack dir"
  # An acked item is not shown again at the seat's next wake (go_ack dies on a refusal, so the
  # entry is cleared only once the answer stands).
  if is_go "$rec"; then go_ack "$id" "$rec" "$seat"; rm -f "$(queue_dir "$seat")/$id"; return 0; fi
  if ( set -C; printf '%s\t%s\n' "$seat" "$(now)" > "$BDIR/$id.acks.d/$(ack_key "$seat")" ) 2>/dev/null; then
    echo "acked: $seat"
  else
    echo "already acked: $seat"
  fi
  rm -f "$(queue_dir "$seat")/$id"
}

cmd_status() {
  local id="${1:-}" rec s aud f
  rec=$(record_of "$id") || exit $?
  if is_go "$rec"; then go_status "$id" "$rec"; return 0; fi
  aud=" $(header "$rec" audience) "
  for s in $aud; do
    printf '%s\t%s\t%s\n' "$s" "$(last_state "$rec" "$s")" "$(acked "$id" "$s" && echo acked || echo not-acked)"
  done
  if [ -d "$BDIR/$id.acks.d" ]; then
    for f in "$BDIR/$id.acks.d"/*; do
      [ -r "$f" ] || continue
      s=$(cut -f1 "$f")
      grep -qixF -- "$s" <<<"$(tr ' ' '\n' <<<"$aud")" || printf '%s\t%s\t%s\n' "$s" "joined-later" acked
    done
  fi
  if grep -q '^done: ' "$rec"; then echo "complete: yes ($(grep '^done: ' "$rec" | tail -n 1))"
  else echo "complete: no — the fan-out did not finish; see resend"; fi
  if retracted "$rec"; then grep '^retracted: ' "$rec"; fi
  return 0
}

cmd_retract() {
  local id="${1:-}"; [ $# -le 1 ] || die 2 "retract takes one id"
  local rec by
  rec=$(record_of "$id") || exit $?
  [ "$(header "$rec" sticky)" = yes ] || die 2 "'$id' is not sticky; there is nothing standing to retract"
  by=$(live_self) || exit $?
  [ "$by" = "$(header "$rec" sent-by)" ] || [ "$by" = "$(header "$rec" from)" ] \
    || die 2 "only its sender may retract '$id' (sent-by $(header "$rec" sent-by))"
  retracted "$rec" && { echo "already retracted: $id"; return 0; }
  rm -f "$BDIR/sticky/$id"
  printf '\n## Retracted\n\nretracted: by %s at %s\n' "$by" "$(now)" >> "$rec"
  echo "retracted: $id"
}

# any_queued — is any seat's queue non-empty? Read before an identity, so the per-prompt hook
# costs one glob when nothing is queued anywhere.
any_queued() { local f; for f in "$BDIR"/queued/*/*; do [ -e "$f" ] && return 0; done; return 1; }

# wake_message <id> <rec> <seat> — what the live push would have carried to that seat.
wake_message() {
  local by text; by=$(header "$2" sent-by); text=$(text_of "$2")
  if is_go "$2"; then GO_ID="$1" GO_REC="$2" GO_BY="$by" GO_TEXT="$text"; go_msg_for "$3"
  else message "$1" "$text" "$2" "$by"; fi
}

cmd_pending() {
  local seat="" limit=5 qonly=0 mark=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --for) need_val "$1" $# "${2:-}"; seat="$2"; shift 2 ;;
      --limit) need_val "$1" $# "${2:-}"; limit="$2"; shift 2 ;;
      --queued) qonly=1; shift ;;
      *) die 2 "pending: unknown argument $1" ;;
    esac
  done
  [[ "$limit" =~ ^[0-9]+$ ]] || die 2 "--limit takes a number"
  [ "$qonly" = 0 ] || any_queued || return 0
  # Without --for, the seat is this pane's LIVE label: a cache-only identity would hand this
  # session another seat's standing guidance, which it could then never ack. Refused, loudly.
  # Only then is a queued broadcast marked delivered: --for is a read, never a delivery.
  if [ -z "$seat" ]; then seat=$(live_self) || exit $?; mark=1; fi
  valid_seat --for "$seat"
  local tree id rec shown=0 more=0 qmore=0 qids=" " qd claim wk="" f
  # Queued broadcasts first (IDE-352), oldest first: each is shown once, with the message the
  # live push would have carried, and claimed by an atomic rename so two hooks firing together
  # cannot both show it. A retracted or expired one is dropped unshown.
  qd=$(queue_dir "$seat")
  if [ "$mark" = 1 ] && [ -n "${BROADCAST_WAKE_KEY:-}" ]; then
    [[ "$BROADCAST_WAKE_KEY" =~ ^[A-Za-z0-9._-]{1,200}$ ]] || die 2 "BROADCAST_WAKE_KEY '$BROADCAST_WAKE_KEY' is not a key ([A-Za-z0-9._-], at most 200)"
    wk="$qd/.wake.$BROADCAST_WAKE_KEY"
  fi
  if [ -d "$qd" ]; then
    if [ "$mark" = 1 ]; then
      # A claim or a pre-push hold (.<id>.claim.<pid>, .<id>.hold.<pid>) whose process is gone
      # (a killed hook, a killed send) goes back in the queue. Its mtime is the entry's own, kept
      # by the rename, so age cannot tell a dead claim from a live one; the pid can. A wake key's
      # record of what it showed is dropped after 30 minutes.
      local cp
      while IFS= read -r f; do
        cp=${f##*.}; [[ "$cp" =~ ^[0-9]+$ ]] || continue
        ! kill -0 "$cp" 2>/dev/null || continue
        id=${f##*/}; id=${id#.}; id=${id%.*}; id=${id%.*}
        [[ "$id" =~ $ID_RE ]] && [ ! -e "$qd/$id" ] && mv "$f" "$qd/$id" 2>/dev/null || rm -f "$f"
      done < <(find "$qd" -maxdepth 1 -type f \( -name '.*.claim.*' -o -name '.*.hold.*' \) 2>/dev/null)
      find "$qd" -maxdepth 1 -type d -name '.wake.*' -mmin +30 -exec rm -rf {} + 2>/dev/null || true
    fi
    # Already shown to this wake (a regenerated SessionStart preload): listed again, not re-marked.
    if [ -n "$wk" ] && [ -d "$wk" ]; then
      while IFS= read -r id <&3; do
        [[ "$id" =~ $ID_RE ]] && [ -r "$BDIR/$id.md" ] || continue
        rec="$BDIR/$id.md"; qids+="$id "
        retracted "$rec" || expired "$rec" && continue
        printf '%s\t%s\tqueued\t%s\n%s\n' "$id" "$(header "$rec" sent-by)" "$rec" "$(wake_message "$id" "$rec" "$seat")"
        shown=$((shown + 1))
      done 3< <(ls -tr "$wk" 2>/dev/null)
    fi
    # Names are checked against ID_RE before use, so reading ls line by line is safe here.
    while IFS= read -r id <&3; do
      [[ "$id" =~ $ID_RE ]] || continue
      case "$qids" in *" $id "*) rm -f "$qd/$id"; continue ;; esac   # shown to this wake above
      rec="$BDIR/$id.md"
      if [ ! -r "$rec" ] || retracted "$rec" || expired "$rec"; then rm -f "$qd/$id"; continue; fi
      qids+="$id "
      if [ "$limit" != 0 ] && [ "$shown" -ge "$limit" ]; then qmore=$((qmore + 1)); continue; fi
      if [ "$mark" = 1 ]; then
        claim="$qd/.$id.claim.$$"
        mv "$qd/$id" "$claim" 2>/dev/null || continue
      fi
      printf '%s\t%s\tqueued\t%s\n%s\n' "$id" "$(header "$rec" sent-by)" "$rec" "$(wake_message "$id" "$rec" "$seat")"
      shown=$((shown + 1))
      if [ "$mark" = 1 ]; then
        echo "delivered $seat at-wake $(now)" >> "$rec"
        if [ -n "$wk" ] && mkdir -p "$wk" 2>/dev/null && mv -f "$claim" "$wk/$id" 2>/dev/null; then :; else rm -f "$claim"; fi
      fi
    done 3< <(ls -tr "$qd" 2>/dev/null)
  fi
  [ "$qmore" = 0 ] || echo "+$qmore more queued: shown at the next wake"
  [ "$qonly" = 0 ] || return 0
  [ -d "$BDIR/sticky" ] || return 0
  tree=$(live_tree) || exit $?
  for id in $(ls -t "$BDIR/sticky" 2>/dev/null); do
    [[ "$id" =~ $ID_RE ]] || continue
    case "$qids" in *" $id "*) continue ;; esac   # listed (or still queued) above
    rec="$BDIR/$id.md"
    [ -r "$rec" ] || continue
    retracted "$rec" && continue
    if expired "$rec"; then rm -f "$BDIR/sticky/$id"; continue; fi
    [ "$(header "$rec" sent-by)" = "$seat" ] && continue
    [ "$(header "$rec" from)" = "$seat" ] && continue
    in_live_scope "$tree" "$seat" "$(header "$rec" scope)" || continue
    acked "$id" "$seat" && continue
    if [ "$limit" = 0 ] || [ "$shown" -lt "$limit" ]; then
      printf '%s\t%s\t%s\t%s\n' "$id" "$(header "$rec" sent-by)" "$(header "$rec" scope)" "$rec"
      shown=$((shown + 1))
    else
      more=$((more + 1))
    fi
  done
  [ "$more" = 0 ] || echo "+$more more: engine broadcast pending --for $seat --limit 0"
}

# ---- go requests (IDE-350): a landing seat asks every CONTRACTS row owner for its go ----
# A go request is an ordinary record with more header lines (kind: go-request, pr, rows and/or
# paths — each only when given, so a rows-only record reads as before — repo, commits) and receipt lines in its text. Each line carries a receipt KIND, so a later receipt that
# is not path-scoped (a row's own lines, say) is a new kind, not a new format:
#   receipt <kind> <seat> <commit> <patch-id> -- <path>…   one per commit that touches the paths
#   untouched <kind> <seat> <commit> -- <path>…            a commit that does not touch them
# The one kind today is "path" (LANDING.md step 2). Round-1 records have no kind field
# ("receipt <seat> <commit> <id> -- …"); they read as kind "path".
# A GO is <id>.acks.d/<seat> = "<seat>\t<at>\tGO\t<patch-id> <patch-id>…" (the ids it was sent);
# a decline is <id>.declines.d/<seat> = "<seat>\t<at>\t<reason>". Before either is written, the
# seat's one answer is claimed in <id>.answers.d/<seat> ("GO" | "DECLINED", noclobber), so a GO and
# a decline from one seat cannot both land.
#
# Paths, rows and seats are kept in arrays and never expanded unquoted: an Owner cell, a --rows or
# a --paths value holding * is that literal string, never file names from the caller's cwd.
OWNERS_MAP="${BROADCAST_OWNERS:-$HOME/.claude/data/yarik/owners.tsv}"
is_go() { [ "$(header "$1" kind)" = go-request ]; }
declined() { [ -e "$BDIR/$1.declines.d/$(ack_key "$2")" ]; }

# range_ends <repo> <range> → "<tip> <base>". The tip is `git rev-parse` of the range's end (never
# whichever commit rev-list prints last); the base is the merge-base of its start and end, or the
# tip's first parent for a single rev, "-" when there is none.
range_ends() {
  local repo="$1" range="$2" start end tip base=""
  case "$range" in
    *..*)
      start=${range%%..*}; end=${range##*..}
      [ -n "$start" ] || start=HEAD; [ -n "$end" ] || end=HEAD
      tip=$(git -C "$repo" rev-parse --verify --quiet "$end^{commit}") || return 1
      start=$(git -C "$repo" rev-parse --verify --quiet "$start^{commit}") || return 1
      base=$(git -C "$repo" merge-base "$start" "$tip" 2>/dev/null) || base="" ;;
    *)
      tip=$(git -C "$repo" rev-parse --verify --quiet "$range^{commit}") || return 1
      base=$(git -C "$repo" rev-parse --verify --quiet "$tip^1^{commit}") || base="" ;;
  esac
  echo "$tip ${base:--}"
}

# commits_of <repo> <range> → one sha per line, oldest first, merge commits skipped (--no-merges:
# LANDING.md computes receipts on lane commits). A rev without ".." is that one commit.
commits_of() {
  case "$2" in
    *..*) git -C "$1" rev-list --no-merges --reverse "$2" -- 2>/dev/null || return 1 ;;
    *) local c; c=$(git -C "$1" rev-parse --verify --quiet "$2^{commit}") || return 1
       git -C "$1" rev-list --no-merges "$c^!" -- 2>/dev/null || return 1 ;;
  esac
}

# receipt_id <repo> <commit> <path>… — LANDING.md step 2, the paths passed as separate words.
receipt_id() {
  local repo="$1" c="$2"; shift 2
  git -C "$repo" --literal-pathspecs show --text "$c" -- "$@" | git patch-id --stable | cut -d' ' -f1
}

# row_owner_paths <contracts-text> <row> → the backticked paths in that registry row's Owner cell
# (none for an Owner cell like "none"); rc 1 when no registry row links to #<row>.
row_owner_paths() {
  local cell
  cell=$(awk -F'|' -v r="$2" '/^\|/ && index($2, "](#" r ")") { print $4; f = 1; exit } END { exit !f }' <<<"$1") || return 1
  { grep -o '`[^`]*`' <<<"$cell" || true; } | tr -d '`'
}

# seat_of_path <path> → the seat whose map pattern matches most specifically. Specificity is the
# number of /-separated segments in the pattern (a trailing / adds none): kern/a.ts (2) beats kern/
# (1), and */schemas/*.ts (3) beats resource-kernel/ (1) whatever their lengths in characters. At
# equal segments a literal (no * or ?: a path, or a dir/ prefix) beats a glob: resource-kernel/
# beats resource-*, kern/ beats a catch-all *, kern/a.ts beats kern/*.ts. A pattern ending in /
# covers everything under it; any other pattern is a shell glob, whose * also matches /. Two
# different seats at the same rank (two literals, or two globs, at equal segments) are a tie.
# rc 1 none · 2 a tie.
seat_of_path() {
  local p="$1" pat seat best="" bseg=-1 tie=0 seg t
  while read -r pat seat _; do
    case "$pat" in ''|'#'*) continue ;; esac
    [ -n "$seat" ] || continue
    case "$pat" in
      */) [[ "$p" == "$pat"* ]] || continue ;;
      *)
        # shellcheck disable=SC2053 # $pat is a glob on purpose
        [[ "$p" == $pat ]] || continue ;;
    esac
    t="${pat%/}"; t="${t//[!\/]/}"; seg=$(( (${#t} + 1) * 2 ))
    case "$pat" in *'*'*|*'?'*) ;; *) seg=$(( seg + 1 )) ;; esac   # literal beats glob at equal depth
    if [ "$seg" -gt "$bseg" ]; then best="$seat"; bseg="$seg"; tie=0
    elif [ "$seg" = "$bseg" ] && [ "$seat" != "$best" ]; then tie=1; fi
  done < "$OWNERS_MAP"
  [ -n "$best" ] || return 1
  [ "$tie" = 0 ] || return 2
  echo "$best"
}

# receipts_text <repo> <commits> <seat> <path>… → "path"-kind receipt / untouched lines for one owner.
receipts_text() {
  local repo="$1" commits="$2" seat="$3" c pid; shift 3
  [ $# -gt 0 ] || return 1   # no paths would be the whole commit, never a receipt
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    pid=$(receipt_id "$repo" "$c" "$@")
    if [ -n "$pid" ]; then echo "receipt path $seat $c $pid -- $*"; else echo "untouched path $seat $c -- $*"; fi
  done <<<"$commits"
}

# RL_AWK — awk functions that read a receipt line in either form. rl() is 2 for round 2
# (with a kind), 1 for round 1 (no kind, read as "path"), 0 for any other line.
RL_AWK='
function rl() {
  if ($1 == "receipt") return ($6 == "--") ? 2 : (($5 == "--") ? 1 : 0)
  if ($1 == "untouched") return ($5 == "--") ? 2 : (($4 == "--") ? 1 : 0)
  return 0
}
function rl_seat(v) { return v == 1 ? $2 : $3 }
function rl_kind(v) { return v == 1 ? "path" : $2 }
function rl_id(v) { return v == 1 ? $4 : $5 }
'
# go_text_for <text> <seat> — the request text with only that seat's receipt lines.
go_text_for() { awk -v s="$2" "$RL_AWK"'{ v = rl() } v && rl_seat(v) != s { next } { print }' <<<"$1"; }
GO_ID="" GO_TEXT="" GO_REC="" GO_BY=""
go_msg_for() { message "$GO_ID" "$(go_text_for "$GO_TEXT" "$1")" "$GO_REC" "$GO_BY"; }

# owner_paths_of <text> <seat> → that seat's "path"-kind paths, one per line.
owner_paths_of() {
  awk -v s="$2" "$RL_AWK"'{ v = rl() } v && rl_seat(v) == s && rl_kind(v) == "path" { sub(/^.* -- /, ""); n = split($0, a, " "); for (i = 1; i <= n; i++) print a[i]; exit }' <<<"$1"
}
# kinds_of <text> <seat> → the receipt kinds that seat was sent, one per line.
kinds_of() { awk -v s="$2" "$RL_AWK"'{ v = rl() } v && rl_seat(v) == s && !k[rl_kind(v)]++ { print rl_kind(v) }' <<<"$1"; }
# sent_ids_of <text> <seat> → the patch-ids the seat was sent (every kind), sorted, one line.
sent_ids_of() { awk -v s="$2" "$RL_AWK"'$1 == "receipt" { v = rl() } $1 == "receipt" && v && rl_seat(v) == s { print rl_id(v) }' <<<"$1" | sort | tr '\n' ' ' | sed 's/ $//'; }

# go_covers <rec> [<sep>] → "rows R", "paths P" or "rows R<sep>paths P" (sep defaults to " and "),
# from the record's headers; a record from before --paths has no paths header and reads "rows R".
go_covers() {
  local r p; r=$(header "$1" rows); p=$(header "$1" paths)
  if [ -n "$r" ] && [ -n "$p" ]; then echo "rows $r${2:- and }paths $p"
  elif [ -n "$p" ]; then echo "paths $p"
  else echo "rows $r"; fi
}

cmd_go_request() {
  local pr="" rows="" paths="" repo="" range="origin/main..HEAD" id="" dry=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --pr) need_val "$1" $# "${2:-}"; pr="$2"; shift 2 ;;
      --rows) need_val "$1" $# "${2:-}"; rows="$rows ${2//,/ }"; shift 2 ;;
      --paths) need_val "$1" $# "${2:-}"; paths="$paths ${2//,/ }"; shift 2 ;;
      --repo) need_val "$1" $# "${2:-}"; repo="$2"; shift 2 ;;
      --commits) need_val "$1" $# "${2:-}"; range="$2"; shift 2 ;;
      --owners) need_val "$1" $# "${2:-}"; OWNERS_MAP="$2"; shift 2 ;;
      --id) need_val "$1" $# "${2:-}"; id="$2"; shift 2 ;;
      --all-live) LIVE_ALL=1; shift ;;
      --dry-run) dry=1; shift ;;
      *) die 2 "go-request: unknown argument $1" ;;
    esac
  done
  [[ "$pr" =~ ^[0-9]+$ ]] || die 2 "go-request: --pr takes a PR number"
  rows=$(tr -s ' ' '\n' <<<"$rows" | awk 'NF && !seen[$0]++' | tr '\n' ' ' | sed 's/ $//')
  paths=$(tr -s ' ' '\n' <<<"$paths" | awk 'NF && !seen[$0]++' | tr '\n' ' ' | sed 's/ $//')
  [ -n "$rows" ] || [ -n "$paths" ] || die 2 "go-request: --rows (CONTRACTS.md row ids, their #anchors) or --paths (repo paths) names at least one row or path"
  local -a row_arr=() path_arr=() seat_arr=() parr=()
  read -ra row_arr <<<"$rows"
  read -ra path_arr <<<"$paths"
  if [ -n "$id" ]; then valid_id "$id"
  else id="go-pr$pr-$(date -u +%Y%m%dt%H%M%Sz)-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"; fi
  [ -n "$repo" ] || repo=$(git rev-parse --show-toplevel 2>/dev/null) || die 2 "go-request: not in a git repo; pass --repo"
  repo=$(cd "$repo" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || die 2 "go-request: '$repo' is not a git repo"
  [ -r "$OWNERS_MAP" ] || die 2 "go-request: no owners map at $OWNERS_MAP (lines '<path-glob> <seat>'; --owners FILE or BROADCAST_OWNERS)"

  local ends tip base commits contracts cbase=""
  ends=$(range_ends "$repo" "$range") || die 2 "go-request: '$range' is not a commit range in $repo"
  read -r tip base <<<"$ends"
  commits=$(commits_of "$repo" "$range") || die 2 "go-request: '$range' is not a commit range in $repo"
  [ -n "$commits" ] || die 2 "go-request: '$range' holds no commits (merge commits are skipped)"
  # CONTRACTS.md as the range's tip has it (the rows this PR lands) AND as its base has it (the
  # owners it would land over), never a working-tree copy. A row's owners are the union of both, so
  # a PR that repoints an Owner cell still asks the owner it repoints away from.
  if [ "${#row_arr[@]}" -gt 0 ]; then
    contracts=$(git -C "$repo" show "$tip:CONTRACTS.md" 2>/dev/null) || die 2 "go-request: no CONTRACTS.md at $tip"
    [ "$base" = - ] || cbase=$(git -C "$repo" show "$base:CONTRACTS.md" 2>/dev/null) || cbase=""
  fi

  # Row → owner paths → seat. Each refusal names the row; nothing is guessed.
  local r p seat src srcb found rc pairs="" ppairs="" bad=""
  for r in ${row_arr[@]+"${row_arr[@]}"}; do
    found=0 src="" srcb=""
    if src=$(row_owner_paths "$contracts" "$r"); then found=1; fi
    if [ -n "$cbase" ] && srcb=$(row_owner_paths "$cbase" "$r"); then found=1; fi
    [ "$found" = 1 ] || { bad+="row '$r' is not in CONTRACTS.md's registry; "; continue; }
    src=$(printf '%s\n%s\n' "$src" "$srcb" | awk 'NF && !seen[$0]++')
    [ -n "$src" ] || { bad+="row '$r' has no owner path; "; continue; }
    while IFS= read -r p; do
      [[ "$p" =~ ^[^[:space:]]+$ ]] || { bad+="row '$r' owner path '$p' is not one path; "; continue; }
      rc=0; seat=$(seat_of_path "$p") || rc=$?
      case "$rc" in
        1) bad+="row '$r' owner path '$p' maps to no seat in $OWNERS_MAP; "; continue ;;
        2) bad+="row '$r' owner path '$p' maps to two seats equally in $OWNERS_MAP; "; continue ;;
      esac
      valid_seat "owner of row '$r'" "$seat"
      pairs+="$seat $p $r"$'\n'
      case " ${seat_arr[*]-} " in *" $seat "*) ;; *) seat_arr+=("$seat") ;; esac
    done <<<"$src"
  done
  # --paths: each given path → seat through the same map. ppairs holds "<seat> <path>".
  for p in ${path_arr[@]+"${path_arr[@]}"}; do
    rc=0; seat=$(seat_of_path "$p") || rc=$?
    case "$rc" in
      1) bad+="path '$p' maps to no seat in $OWNERS_MAP; "; continue ;;
      2) bad+="path '$p' maps to two seats equally in $OWNERS_MAP; "; continue ;;
    esac
    valid_seat "owner of path '$p'" "$seat"
    ppairs+="$seat $p"$'\n'
    case " ${seat_arr[*]-} " in *" $seat "*) ;; *) seat_arr+=("$seat") ;; esac
  done
  [ -z "$bad" ] || die 2 "go-request refused: ${bad%; }"

  local tree sent_by
  tree=$(live_tree) || exit $?
  sent_by=$(live_self) || exit $?
  local of ofr ofp
  for seat in "${seat_arr[@]}"; do
    in_tree "$tree" "$seat" && continue
    ofr=$(awk -v s="$seat" '$1 == s { print $3 }' <<<"$pairs" | sort -u | tr '\n' ' ' | sed 's/ $//')
    ofp=$(awk -v s="$seat" '$1 == s { print $2 }' <<<"$ppairs" | sort -u | tr '\n' ' ' | sed 's/ $//')
    of="${ofr:+row(s) $ofr}"; [ -z "$ofp" ] || of+="${of:+ and }path(s) $ofp"
    bad+="owner '$seat' of $of is not a live seat; "
  done
  [ -z "$bad" ] || die 3 "go-request refused: ${bad%; }"

  # A row whose owner paths give an empty id on every commit is a receipt for nothing (a misspelt
  # path, or a row this range does not touch): refused per row and owner, so another row of the
  # same owner cannot hide it.
  local receipts="" lines
  for r in ${row_arr[@]+"${row_arr[@]}"}; do
    for seat in "${seat_arr[@]}"; do
      parr=()
      while IFS= read -r p; do [ -z "$p" ] || parr+=("$p"); done < <(awk -v s="$seat" -v r="$r" '$1 == s && $3 == r { print $2 }' <<<"$pairs")
      [ "${#parr[@]}" -gt 0 ] || continue
      # A here-string, not a pipe: grep -q exits on the first match and pipefail would count the
      # writer's SIGPIPE as a failure.
      grep -q '^receipt ' <<<"$(receipts_text "$repo" "$commits" "$seat" "${parr[@]}")" \
        || bad+="row '$r': the receipt for owner '$seat' is empty on every commit in $range (paths: ${parr[*]}); "
    done
  done
  # The same per owner over its --paths: a misspelt path is not hidden by the owner's other paths.
  for seat in "${seat_arr[@]}"; do
    parr=()
    while IFS= read -r p; do [ -z "$p" ] || parr+=("$p"); done < <(awk -v s="$seat" '$1 == s { print $2 }' <<<"$ppairs")
    [ "${#parr[@]}" -gt 0 ] || continue
    grep -q '^receipt ' <<<"$(receipts_text "$repo" "$commits" "$seat" "${parr[@]}")" \
      || bad+="--paths: the receipt for owner '$seat' is empty on every commit in $range (paths: ${parr[*]}); "
  done
  [ -z "$bad" ] || die 2 "go-request refused: ${bad%; }"
  # Each seat's receipt covers its paths from rows and from --paths, each path once.
  for seat in "${seat_arr[@]}"; do
    parr=()
    while IFS= read -r p; do [ -z "$p" ] || parr+=("$p"); done < <({ awk -v s="$seat" '$1 == s { print $2 }' <<<"$pairs"; awk -v s="$seat" '$1 == s { print $2 }' <<<"$ppairs"; } | awk '!seen[$0]++')
    lines=$(receipts_text "$repo" "$commits" "$seat" "${parr[@]}")
    receipts+="$lines"$'\n'
  done

  local text n b oseats="${seat_arr[*]}"
  n=$(grep -c . <<<"$commits" | tr -d ' ')
  local covers="" owners_line=""
  [ -z "$rows" ] || { covers+="rows: $rows"$'\n'; owners_line+="Owners are read from CONTRACTS.md at the tip $tip and the base $base; both are asked."$'\n'; }
  [ -z "$paths" ] || { covers+="paths: $paths"$'\n'; owners_line+="Each --paths path is asked of its owner in the owners map."$'\n'; }
  text=$(printf 'GO request: PR %s\n%scommits: %s (%s, in %s; merge commits skipped)\n%sEach receipt is a --text, path-scoped `git patch-id --stable` id per commit (LANDING.md step 2).\nAnswer without prose. GO: engine broadcast ack %s  ·  decline: engine broadcast decline %s --reason "<one line>"\n\n%s' \
    "$pr" "$covers" "$range" "$n commits" "$repo" "$owners_line" "$id" "$id" "${receipts%$'\n'}")
  local rec="$BDIR/$id.md" extra
  extra=$(printf 'kind: go-request\npr: %s\n%srepo: %s\ncommits: %s' "$pr" "$covers" "$repo" "$range")$'\n'
  printf 'id: %s\nfrom: %s\nsent-by: %s\nscope: go-request\naudience: %s\n%s' "$id" "$sent_by" "$sent_by" "$oseats" "$extra"
  GO_ID="$id" GO_TEXT="$text" GO_REC="$rec" GO_BY="$sent_by"
  if [ "$dry" = 1 ]; then
    for seat in "${seat_arr[@]}"; do b=$(bind "$tree" "$seat"); echo "binds $seat → $b$(bind_note "$b")"; echo "message to $seat: $(go_msg_for "$seat")"; done
    echo "dry-run: nothing written, nothing sent"
    return 0
  fi
  mkdir -p "$BDIR" || die 2 "cannot create $BDIR"
  write_record "$rec" "$id" "$sent_by" "$sent_by" go-request no - "$oseats" "$text" "$extra"
  local rc=0
  SEAT_MSG=go_msg_for
  fan_out "$tree" "$id" "$rec" "" "${seat_arr[@]}" || rc=$?
  echo "record: $rec"
  return "$rc"
}

# claim_answer <id> <seat> <GO|DECLINED> — claim the seat's one answer atomically (noclobber).
# rc 0 when this answer holds the claim (now or from before); 1, printing the other answer, when
# the other one does.
claim_answer() {
  local d="$BDIR/$1.answers.d" f have
  mkdir -p "$d" || die 2 "cannot create the answers dir"
  f="$d/$(ack_key "$2")"
  ( set -C; printf '%s\n' "$3" > "$f" ) 2>/dev/null && return 0
  have=$(head -n 1 "$f" 2>/dev/null)
  [ "$have" = "$3" ] && return 0
  echo "${have:-an unreadable answer}"
  return 1
}

# go_ack <id> <rec> <seat> — a GO on a go request, bound to the patch-ids that seat was sent.
go_ack() {
  local id="$1" rec="$2" seat="$3" ids f other
  declined "$id" "$seat" && die 2 "'$seat' declined '$id' ($(cut -f3 "$BDIR/$id.declines.d/$(ack_key "$seat")")); a changed change needs a new go-request"
  ids=$(sent_ids_of "$(text_of "$rec")" "$seat")
  [ -n "$ids" ] || die 2 "'$id' carries no receipt for '$seat'"
  other=$(claim_answer "$id" "$seat" GO) || die 2 "'$seat' already answered '$id' with $other; one answer per seat (a changed change needs a new go-request)"
  f="$BDIR/$id.acks.d/$(ack_key "$seat")"
  if ( set -C; printf '%s\t%s\tGO\t%s\n' "$seat" "$(now)" "$ids" > "$f" ) 2>/dev/null; then
    echo "GO: $seat (receipts: $ids)"
  else
    echo "already GO: $seat"
  fi
}

cmd_decline() {
  local id="" reason="" have=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason) [ $# -ge 2 ] || die 2 "decline: --reason needs a value"; reason="$2"; have=1; shift 2 ;;
      -*) die 2 "decline: unknown argument $1" ;;
      *) [ -z "$id" ] || die 2 "decline: one id"; id="$1"; shift ;;
    esac
  done
  local rec seat other
  rec=$(record_of "$id") || exit $?
  is_go "$rec" || die 2 "'$id' is not a go request; only a go request takes a decline"
  [ "$have" = 1 ] || die 2 "decline needs --reason \"<one line>\""
  [ -n "${reason//[[:space:]]/}" ] || die 2 "decline: the reason is blank"
  case "$reason" in *$'\n'*|*$'\r'*) die 2 "decline: the reason is one line" ;; esac
  seat=$(live_self) || exit $?
  grep -qxF -- "$seat" <<<"$(tr ' ' '\n' <<<"$(header "$rec" audience)")" || die 2 "'$seat' is not an owner in the audience of '$id'"
  acked "$id" "$seat" && die 2 "'$seat' already gave its GO on '$id'; a GO is not withdrawn by a decline"
  other=$(claim_answer "$id" "$seat" DECLINED) || die 2 "'$seat' already answered '$id' with $other; a GO is not withdrawn by a decline"
  mkdir -p "$BDIR/$id.declines.d" || die 2 "cannot create the decline dir"
  if ( set -C; printf '%s\t%s\t%s\n' "$seat" "$(now)" "$reason" > "$BDIR/$id.declines.d/$(ack_key "$seat")" ) 2>/dev/null; then
    echo "DECLINED: $seat ($reason)"
  else
    echo "already declined: $seat"
  fi
}

# go_answer <id> <seat> → "GO\t<ids>" | "GO-NO-RECEIPTS" (an ack file without ids: a plain
# two-field ack, from before go requests or written by hand) | "DECLINED\t<reason>" | "PENDING"
go_answer() {
  local k f; k=$(ack_key "$2"); f="$BDIR/$1.acks.d/$k"
  if [ -r "$f" ]; then
    if [ "$(cut -f3 "$f")" = GO ] && [ -n "$(cut -f4 "$f")" ]; then printf 'GO\t%s\n' "$(cut -f4 "$f")"
    else echo GO-NO-RECEIPTS; fi
  elif [ -r "$BDIR/$1.declines.d/$k" ]; then printf 'DECLINED\t%s\n' "$(cut -f3- "$BDIR/$1.declines.d/$k")"
  else echo PENDING; fi
}

go_status() {
  local id="$1" rec="$2" s ans
  local -a aud=()
  echo "go-request: PR $(header "$rec" pr) · $(go_covers "$rec" ' · ') · commits $(header "$rec" commits)"
  read -ra aud <<<"$(header "$rec" audience)"
  for s in ${aud[@]+"${aud[@]}"}; do
    ans=$(go_answer "$id" "$s")
    [ "$ans" = GO-NO-RECEIPTS ] && ans="GO (no receipts)"
    printf '%s\t%s\t%s\n' "$s" "$(last_state "$rec" "$s")" "$ans"
  done
  if grep -q '^done: ' "$rec"; then echo "complete: yes ($(grep '^done: ' "$rec" | tail -n 1))"
  else echo "complete: no — the fan-out did not finish; see resend"; fi
}

# go-check <id> --commits <range> [--repo P] — exit 0 only when every owner of the requested rows
# has a GO whose receipts are exactly the ones these commits give now on that owner's paths
# (matched by patch-id, so a re-picked commit whose id did not move keeps its go). The repo is
# --repo, else the git toplevel of the cwd (the worktree being landed), never the request's
# recorded repo. 1 otherwise, naming who is missing and whose receipt moved. MOVED means the diff
# text changed: patch-id --stable ignores line numbers, so a pure line shift keeps its id; a change
# only in context lines is the lander's judgement under LANDING.md step 4, anything else needs the
# owner's fresh go.
cmd_go_check() {
  local id="" range="" repo=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --commits) need_val "$1" $# "${2:-}"; range="$2"; shift 2 ;;
      --repo) need_val "$1" $# "${2:-}"; repo="$2"; shift 2 ;;
      -*) die 2 "go-check: unknown argument $1" ;;
      *) [ -z "$id" ] || die 2 "go-check: one id"; id="$1"; shift ;;
    esac
  done
  local rec text commits s now sent ans k unknown recrepo fail=0
  local -a aud=() parr=()
  rec=$(record_of "$id") || exit $?
  is_go "$rec" || die 2 "'$id' is not a go request"
  [ -n "$range" ] || die 2 "go-check: --commits <range> is required (the commits about to land)"
  if [ -z "$repo" ]; then
    repo=$(git rev-parse --show-toplevel 2>/dev/null) || die 2 "go-check: not in a git repo; run it in the worktree being landed, or pass --repo"
  else
    repo=$(cd "$repo" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || die 2 "go-check: '$repo' is not a git repo"
  fi
  echo "go-check: repo $repo"
  recrepo=$(header "$rec" repo)
  [ "$recrepo" = "$repo" ] || echo "go-check: (the request was made in $recrepo)"
  commits=$(commits_of "$repo" "$range") || die 2 "go-check: '$range' is not a commit range in $repo"
  [ -n "$commits" ] || die 2 "go-check: '$range' holds no commits (merge commits are skipped)"
  text=$(text_of "$rec")
  read -ra aud <<<"$(header "$rec" audience)"
  for s in ${aud[@]+"${aud[@]}"}; do
    ans=$(go_answer "$id" "$s")
    case "$ans" in
      PENDING) echo "PENDING $s"; fail=1; continue ;;
      DECLINED*) echo "DECLINED $s: ${ans#DECLINED$'\t'}"; fail=1; continue ;;
      GO-NO-RECEIPTS) echo "NO-RECEIPTS $s: its GO carries no receipt ids; ask again"; fail=1; continue ;;
    esac
    unknown=""
    while IFS= read -r k; do [ -z "$k" ] || [ "$k" = path ] || unknown+="${unknown:+, }'$k'"; done < <(kinds_of "$text" "$s")
    if [ -n "$unknown" ]; then echo "UNKNOWN $s: receipt kind $unknown is not one this go-check can recompute"; fail=1; continue; fi
    sent=${ans#GO$'\t'}
    parr=()
    while IFS= read -r k; do [ -z "$k" ] || parr+=("$k"); done < <(owner_paths_of "$text" "$s")
    if [ "${#parr[@]}" = 0 ]; then echo "MOVED $s: the request records no paths for it"; fail=1; continue; fi
    now=$(receipts_text "$repo" "$commits" "$s" "${parr[@]}" | awk '$1 == "receipt" { print $5 }' | sort | tr '\n' ' ' | sed 's/ $//')
    if [ "$now" = "$sent" ]; then echo "GO $s: receipts match"
    else
      echo "MOVED $s: the go covers [$sent]; $range gives [$now] for ${parr[*]}"; fail=1
    fi
  done
  if [ "$fail" = 0 ]; then
    echo "go-check: PASS in $repo — each owner of $(go_covers "$rec") has a GO whose receipts match $range on that owner's paths; nothing outside those paths was checked"
    return 0
  fi
  echo "go-check: FAIL in $repo — MOVED means the diff text on that owner's paths changed (git patch-id --stable ignores line numbers, so a re-pick that only shifts lines keeps its id). A change only in context lines is covered by LANDING.md step 4's judgement; anything else needs the owner's fresh go (a new go-request). PENDING: wait for the owner's answer"
  return 1
}

sub="${1:-}"
case "$sub" in
  ack) shift; cmd_ack "$@" ;;
  status) shift; cmd_status "$@" ;;
  resend) shift; cmd_resend "$@" ;;
  retract) shift; cmd_retract "$@" ;;
  pending) shift; cmd_pending "$@" ;;
  go-request) shift; cmd_go_request "$@" ;;
  decline) shift; cmd_decline "$@" ;;
  go-check) shift; cmd_go_check "$@" ;;
  send) shift; cmd_send "$@" ;;
  -h|--help|help|"") awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0" >&2; exit 2 ;;
  *) cmd_send "$@" ;;
esac
