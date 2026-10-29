#!/bin/bash
# scripts/broadcast.sh — `engine broadcast`: send one piece of guidance to a set of live seats,
# with a durable record, receipts, and standing (sticky) guidance for sessions that start later.
#
#   engine broadcast [send] (--subtree SEAT | --children | --all) [--from SEAT] [--id SLUG]
#                    [--sticky [--expires YYYY-MM-DD[THH:MM:SSZ]]] [--dry-run] <<'MSG'
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
#       exit 0 every seat accepted (or dry run) · 1 record written, ≥1 seat undelivered ·
#       2 usage / identity / existing id · 3 seat not in the live tree · 4 live tree unreadable.
#
#   engine broadcast ack <id>                 this seat applied it (own seat only; must be in the
#                                             audience, or in a live sticky scope)
#   engine broadcast status <id>              per seat: delivery state + ack; complete marker
#   engine broadcast resend <id> [--undelivered]   explicit retry (there is no automatic one)
#   engine broadcast retract <id>             withdraw a sticky broadcast (its sender only)
#   engine broadcast pending [--for SEAT] [--limit N]   sticky broadcasts that apply now and are
#                                             unacked, newest first; N defaults to 5, 0 = all
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
#        <id>.acks.d/<seat> acks, sticky/<id> the sticky index.
# Env:   HOP_LIVE_PANES / HOP_TMUX_SOCKET — as hop.sh. BROADCAST_LIB — lib.sh for fleet_self.
#        ASK_SESSIONS_DIR — the session registry (shared with deliver.ts).
#        BROADCAST_INLINE_MAX — the cut, in characters (default 1500); anything but a positive
#        integer of at most 9 digits warns on stderr and falls back to 1500.
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

# fan_out <tree> <id> <rec> <message> <seats…> — deliver, append one line per seat, then done.
fan_out() {
  local tree="$1" id="$2" rec="$3" msg="$4" s b res rc=0 ok=0 bad=0; shift 4
  for s in "$@"; do
    b=$(bind "$tree" "$s")
    if [ "${b%% *}" = ok ]; then
      local pid name
      read -r _ pid name <<<"$b"
      if res=$(deliver "$s" "$pid" "$name" "$msg"); then
        echo "delivered $s pid=$pid" | tee -a "$rec"; ok=$((ok + 1)); continue
      fi
      b="${res:-no reason}"
    fi
    echo "undelivered $s — $b" | tee -a "$rec"; bad=$((bad + 1)); rc=1
  done
  echo "done: rc=$rc delivered=$ok undelivered=$bad at $(now)" >> "$rec"
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
  local tree audience="" skipped="" s sent_by
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
    for s in $audience; do echo "binds $s → $(bind "$tree" "$s")"; done
    echo "message: $msg"
    echo "dry-run: nothing written, nothing sent"
    return 0
  fi
  mkdir -p "$BDIR" || die 2 "cannot create $BDIR"

  # Created atomically (noclobber) and in full BEFORE any delivery: a second send with the same id
  # fails here, and a fan-out that dies midway still leaves the guidance (status: not-attempted).
  if ! ( set -C
         { printf '# Broadcast %s\n\nid: %s\nfrom: %s\nsent-by: %s\nat: %s\nscope: %s\nsticky: %s\nexpires: %s\naudience: %s\n\n## Text\n\n' \
             "$id" "$id" "$from" "$sent_by" "$(now)" "$scope" "$sticky" "$expires" "$audience"
           printf '%s\n' "$text"
           printf '\n## Delivery\n\n'; } > "$rec" ) 2>/dev/null; then
    [ -e "$rec" ] && die 2 "broadcast '$id' already exists: $rec (never overwritten)"
    die 2 "cannot write $rec"
  fi
  if [ "$sticky" = yes ]; then mkdir -p "$BDIR/sticky" && : > "$BDIR/sticky/$id"; fi

  local rc=0
  [ -n "$audience" ] || echo "(no seats in scope)" | tee -a "$rec"
  # shellcheck disable=SC2086
  fan_out "$tree" "$id" "$rec" "$msg" $audience || rc=$?
  echo "record: $rec"
  return "$rc"
}

# last_state <rec> <seat> → delivered | undelivered | not-attempted
last_state() {
  awk -v s="$2" '/^## Delivery/ { d = 1; next } d && ($1 == "delivered" || $1 == "undelivered") && $2 == s { st = $1 }
    END { print (st == "" ? "not-attempted" : st) }' "$1"
}

cmd_resend() {
  local id="" only=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --undelivered) only=1; shift ;;
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
  if ( set -C; printf '%s\t%s\n' "$seat" "$(now)" > "$BDIR/$id.acks.d/$(ack_key "$seat")" ) 2>/dev/null; then
    echo "acked: $seat"
  else
    echo "already acked: $seat"
  fi
}

cmd_status() {
  local id="${1:-}" rec s aud f
  rec=$(record_of "$id") || exit $?
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

cmd_pending() {
  local seat="" limit=5
  while [ $# -gt 0 ]; do
    case "$1" in
      --for) need_val "$1" $# "${2:-}"; seat="$2"; shift 2 ;;
      --limit) need_val "$1" $# "${2:-}"; limit="$2"; shift 2 ;;
      *) die 2 "pending: unknown argument $1" ;;
    esac
  done
  [[ "$limit" =~ ^[0-9]+$ ]] || die 2 "--limit takes a number"
  # Without --for, the seat is this pane's LIVE label: a cache-only identity would hand this
  # session another seat's standing guidance, which it could then never ack. Refused, loudly.
  [ -n "$seat" ] || seat=$(live_self) || exit $?
  valid_seat --for "$seat"
  [ -d "$BDIR/sticky" ] || return 0
  local tree id rec shown=0 more=0
  tree=$(live_tree) || exit $?
  for id in $(ls -t "$BDIR/sticky" 2>/dev/null); do
    [[ "$id" =~ $ID_RE ]] || continue
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

sub="${1:-}"
case "$sub" in
  ack) shift; cmd_ack "$@" ;;
  status) shift; cmd_status "$@" ;;
  resend) shift; cmd_resend "$@" ;;
  retract) shift; cmd_retract "$@" ;;
  pending) shift; cmd_pending "$@" ;;
  send) shift; cmd_send "$@" ;;
  -h|--help|help|"") sed -n '2,48p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  *) cmd_send "$@" ;;
esac
