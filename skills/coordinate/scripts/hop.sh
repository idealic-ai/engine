#!/bin/bash
# skills/coordinate/scripts/hop.sh — the hop: where a manager's question goes next.
#
# /coordinate used to escalate only to the human. The hop lets a manager pass a question
# UP its parent chain and reach the operator only from a seat with no parent. This script
# holds the decisions that must not be left to judgement; SKILL.md Steps 0, 2, 3 and 5 hold
# the protocol around them. It schedules nothing: no timer, no clock, no polling (IDE-135,
# operator 23:05 "push is fine; timers aren't").
#
#   hop.sh target [--of SEAT] [--self SEAT] [--config F] [--chain-file F]
#       Print where a pass-up goes: "<window:label> <pane_id>", or "operator".
#       Without --of: this seat's LIVE @pane_parent. FLEET_PARENT is a launch-time cache: unset
#       or disagreeing, it draws a note on stderr and the live parent is used.
#       With --of: SEAT's parent (one level further up, for a deliberate re-pass).
#       exit 0  target on stdout.
#       exit 3  target on stdout, but a dead rung was skipped (its parent read from the chain
#               file); reason on stderr — record in the row the line naming the dead rung
#               ("'<seat>' names no live pane …"), not the identity notes (stale FLEET_PANE /
#               FLEET_PARENT, cache fallback) that can precede it. A dead top → "operator".
#       exit 2  usage or config error (missing/unparseable config, bad hop.parentFrom,
#               no identity for this seat). Nothing on stdout.
#       exit 4  live tree unreadable. Nothing on stdout.
#       exit 5  the live edge cannot be used: this seat is not in the live tree (FLEET_PARENT
#               would be the only source, and it is never used alone), or the live parent names
#               this seat or "operator". Nothing on stdout.
#
#   hop.sh chain [--self SEAT]
#       Print this seat's ancestry from the live tree, one "<seat> <pane> <parent|->" line per
#       rung up to the top. Setup saves it as the chain file, so a dead rung's own parent is
#       still known after its pane (and its @pane_parent) is gone.
#
#   hop.sh may-rule --class C --floor none|ITEM --raised-by SEAT --config F
#                   [--self SEAT] [--reserved-for operator]
#       Print "rule" (exit 0) or "pass-up: <reason>" (exit 1); floor and reserved results add a
#       second line "reserved-for: operator". Exit 2 on a usage or config error.
#       C is "orientation" or one uppercase letter A–H. All four of --class, --floor,
#       --raised-by and --config are required.
#
#   hop.sh ask-id --pane PANE --question TEXT
#       A deterministic id for a question raised in a pane, so a blocked worker that
#       await-next re-emits maps to the same ask and the same row.
#
#   hop.sh rowed --log F --id ID
#       Exit 0 if the 🪜 Escalations register in F already has a row naming ask:ID, else 1.
#
#   hop.sh inbox [--self SEAT]
#       The open /asks addressed to this seat: "<seat>/<id>\t<file>\t<mark>" per line.
#
#   hop.sh panes --log F [--manages LIST]
#       FLEET_MANAGES minus the panes whose question is passed up and unanswered — the
#       --panes list for await-next, so one blocked worker cannot spin the loop.
#
# Env: HOP_LIVE_PANES — a file in the live-tree shape, read instead of tmux (tests).
#      HOP_TMUX_SOCKET — tmux -L socket for the live read (default: the current server).
#      HOP_CHAIN_FILE  — default --chain-file.
# Live-tree line shape: "<window:label> <pane_id> <parent or ->", one pane per line.
set -uo pipefail

die() { local rc="$1"; shift; echo "hop: $*" >&2; exit "$rc"; }

# The IDE-135 hard floor: always reaches the operator.
FLOOR_ITEMS="cyclic-deadlock build-fails-after-retries blocking-critique thread-loopback"
# Reserved classes: E history others hold, F standing configuration, G outward obligations.
# Never a manager's ruling, whatever a config says. H is reserved unless the grant marks it.
RESERVED_CLASSES="E F G"

tm() { if [ -n "${HOP_TMUX_SOCKET:-}" ]; then tmux -L "$HOP_TMUX_SOCKET" "$@"; else tmux "$@"; fi; }

# The shared live-first identity rule (fleet_self / fleet_parent) lives in scripts/lib.sh. It is
# loaded on first use (hop_fleet), so ask-id, rowed, panes and may-rule never depend on it.
_HOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
_HOP_LIBS="$_HOP_DIR/../../../scripts/lib.sh $HOME/.claude/scripts/lib.sh"

# _hop_load_lib — this tree's scripts/lib.sh first (a tree under test uses its own), then
# ~/.claude/scripts/lib.sh. A candidate counts only if it defines fleet_self. An inherited
# _LIB_SH_LOADED (lib.sh's double-source guard) is cleared first: the functions are provably not
# in this shell, so the guard would only make the source a no-op.
_hop_load_lib() {
  declare -F fleet_self >/dev/null 2>&1 && return 0
  local c
  for c in $_HOP_LIBS; do
    [ -r "$c" ] || continue
    unset _LIB_SH_LOADED
    source "$c"
    declare -F fleet_self >/dev/null 2>&1 && return 0
  done
  return 1
}

# load_config <file or ""> <required 0|1> — validates; sets CFG to the path (or "").
CFG=""
load_config() {
  CFG="$1"
  if [ -z "$CFG" ]; then
    [ "$2" = 1 ] && die 2 "--config is required"
    return 0
  fi
  [ -r "$CFG" ] || die 2 "config not readable: $CFG"
  jq -e 'type == "object"' "$CFG" >/dev/null 2>&1 || die 2 "config does not parse: $CFG"
  local pf
  pf=$(jq -r '.hop.parentFrom // empty' "$CFG")
  if [ -n "$pf" ] && [ "$pf" != "FLEET_PARENT" ]; then
    die 2 "hop.parentFrom may only be FLEET_PARENT (got '$pf') — the route is not configurable"
  fi
}

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

col_of() { # col_of <text> <seat> <col> → that column of the seat's line, or nothing
  awk -v s="$2" -v c="$3" '$1 == s { print $c; exit }' <<<"$1"
}
seat_of_pane() { awk -v p="$2" '$2 == p { print $1; exit }' <<<"$1"; }

# resolve_self <explicit> → this seat's window:label, or die 2.
resolve_self() {
  local s="$1" rc=0 err="" ef=""
  [ -n "$s" ] && { echo "$s"; return 0; }
  # The live pane label wins over FLEET_PANE: run.sh caches FLEET_PANE at launch, so a seat
  # renamed since then still carries its old name there (domain:stats read "domain:domain").
  # fleet_self (scripts/lib.sh) holds the rule; exit 3 is its flagged cache fallback, used here
  # as before when the live label cannot be read. Its notes pass through on success; on failure
  # its reason is folded into the one die line.
  ef=$(mktemp "${TMPDIR:-/tmp}/hop-self.XXXXXX" 2>/dev/null) || ef=""
  if [ -n "$ef" ]; then
    s=$(hop_fleet fleet_self 2>"$ef") || rc=$?
    err=$(cat "$ef"); rm -f "$ef"
  else
    s=$(hop_fleet fleet_self) || rc=$?
  fi
  case "$rc" in
    0|3) [ -n "$err" ] && printf '%s\n' "$err" >&2 ;;
    *) s="" ;;
  esac
  [ -n "$s" ] || die 2 "cannot resolve this seat's identity: no --self, and fleet_self exit $rc (${err#hop: })"
  echo "$s"
}

# hop_fleet <fn> [args…] — a lib.sh fleet identity call with hop's seam, socket and prefix.
hop_fleet() {
  _hop_load_lib || { echo "hop: no scripts/lib.sh defining fleet_self (tried: $_HOP_LIBS)" >&2; return 2; }
  FLEET_LIVE_PANES="${HOP_LIVE_PANES:-}" FLEET_TMUX_SOCKET="${HOP_TMUX_SOCKET:-}" FLEET_WARN_PREFIX=hop "$@"
}

# walk <tree> <chain> <seat> — print the first live rung from SEAT upward; exit 0, or 3 if any
# rung was skipped. SEAT "-" or "" means the top: operator.
walk() {
  local tree="$1" chain="$2" seat="$3" rc="${4:-0}" n=0 pane next
  while :; do
    if [ -z "$seat" ] || [ "$seat" = "-" ]; then echo operator; exit "$rc"; fi
    n=$((n + 1)); [ "$n" -le 20 ] || die 5 "the parent chain loops at '$seat'"
    pane=$(col_of "$tree" "$seat" 2)
    if [ -n "$pane" ]; then echo "$seat $pane"; exit "$rc"; fi
    rc=3
    next=$(col_of "$chain" "$seat" 3)
    if [ -z "$next" ]; then
      echo "hop: '$seat' names no live pane and its own parent is not on record — dead top of the known chain, routed to operator" >&2
      echo operator; exit 3
    fi
    echo "hop: '$seat' names no live pane — skipped one level up to '$next' (from the chain record)" >&2
    seat="$next"
  done
}

read_chain() {
  local f="$1"
  [ -z "$f" ] && return 0
  [ -r "$f" ] || die 2 "chain file not readable: $f"
  cat "$f"
}

cmd_target() {
  local of="" self_arg="" config="" chainf="${HOP_CHAIN_FILE:-}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --of) of="${2:-}"; shift 2 ;;
      --self) self_arg="${2:-}"; shift 2 ;;
      --config) config="${2:-}"; shift 2 ;;
      --chain-file) chainf="${2:-}"; shift 2 ;;
      *) die 2 "target: unknown argument $1" ;;
    esac
  done
  load_config "$config" 0
  local chain tree
  chain=$(read_chain "$chainf") || exit $?
  tree=$(live_tree) || exit $?

  if [ -n "$of" ]; then
    local p start=0
    p=$(col_of "$tree" "$of" 3)
    if [ -z "$p" ]; then
      p=$(col_of "$chain" "$of" 3)
      if [ -z "$p" ]; then
        echo "hop: seat '$of' is not in the live tree or the chain record — routed to operator" >&2
        echo operator; exit 3
      fi
      echo "hop: '$of' names no live pane — its parent '$p' read from the chain record" >&2
      start=3
    fi
    walk "$tree" "$chain" "$p" "$start"
  fi

  local self live env
  self=$(resolve_self "$self_arg") || exit $?
  live=$(col_of "$tree" "$self" 3)
  env="${FLEET_PARENT:-}"
  # The live edge cannot be read: FLEET_PARENT would be the only source, and it is a launch-time
  # cache, so it is not trusted alone (fleet_parent's exit-3 cache fallback is never taken here).
  [ -n "$live" ] || die 5 "this seat '$self' is not in the live tree — cannot read its edge (FLEET_PARENT='${env:-unset}' is not used alone)"
  # A readable live edge always wins. run.sh caches FLEET_PARENT at launch, so a seat reparented
  # since then disagrees with it (stats: FLEET_PARENT=manager:director, live manager:domain).
  # fleet_parent (scripts/lib.sh) applies that rule to the edge read from the tree: "-" is no
  # parent, a differing or unset FLEET_PARENT is named on stderr.
  live=$(hop_fleet fleet_parent --live "$live" --of "$self") || die 5 "the live edge of '$self' could not be applied"
  [ "$live" = "$self" ] && die 5 "the parent of '$self' is itself"
  [ "$live" = "operator" ] && die 5 "'operator' is not a seat; a seat with no parent reaches the operator by having no @pane_parent"
  walk "$tree" "$chain" "$live"
}

cmd_chain() {
  local self_arg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --self) self_arg="${2:-}"; shift 2 ;;
      *) die 2 "chain: unknown argument $1" ;;
    esac
  done
  local tree self seat line n=0
  tree=$(live_tree) || exit $?
  self=$(resolve_self "$self_arg") || exit $?
  seat="$self"
  while [ -n "$seat" ] && [ "$seat" != "-" ]; do
    n=$((n + 1)); [ "$n" -le 20 ] || die 5 "the parent chain loops at '$seat'"
    line=$(awk -v s="$seat" '$1 == s { print $1, $2, ($3 == "" ? "-" : $3); exit }' <<<"$tree")
    [ -n "$line" ] || die 5 "'$seat' is not in the live tree — the chain cannot be recorded"
    echo "$line"
    seat=$(awk '{print $3}' <<<"$line")
  done
}

cmd_may_rule() {
  local class="" floor="" raised_by="" self_arg="" config="" reserved_for=""
  local have_floor=0 have_raised=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --class) class="${2:-}"; shift 2 ;;
      --floor) floor="${2:-}"; have_floor=1; shift 2 ;;
      --raised-by) raised_by="${2:-}"; have_raised=1; shift 2 ;;
      --self) self_arg="${2:-}"; shift 2 ;;
      --config) config="${2:-}"; shift 2 ;;
      --reserved-for) reserved_for="${2:-}"; shift 2 ;;
      *) die 2 "may-rule: unknown argument $1" ;;
    esac
  done
  case "$class" in
    orientation|A|B|C|D|E|F|G|H) ;;
    "") die 2 "may-rule: --class is required (orientation or A–H)" ;;
    *) die 2 "may-rule: class '$class' is not orientation or an uppercase A–H" ;;
  esac
  [ "$have_floor" = 1 ] || die 2 "may-rule: --floor is required (none, or one of: $FLOOR_ITEMS)"
  if [ "$floor" != "none" ] && ! [[ " $FLOOR_ITEMS " == *" $floor "* ]]; then
    die 2 "may-rule: unknown floor item '$floor' (none, or one of: $FLOOR_ITEMS)"
  fi
  [ "$have_raised" = 1 ] && [ -n "$raised_by" ] || die 2 "may-rule: --raised-by is required"
  if [ -n "$reserved_for" ] && [ "$reserved_for" != "operator" ]; then
    die 2 "may-rule: --reserved-for takes only 'operator'"
  fi
  load_config "$config" 1
  local self
  self=$(resolve_self "$self_arg") || exit $?
  if [[ "$raised_by" == %* ]]; then
    local tree name
    tree=$(live_tree) || exit $?
    name=$(seat_of_pane "$tree" "$raised_by")
    [ -n "$name" ] || die 2 "may-rule: --raised-by pane '$raised_by' is not in the live tree"
    raised_by="$name"
  fi

  # A rung that receives an ask already marked for the operator only forwards it.
  if [ "$reserved_for" = "operator" ]; then
    echo "pass-up: marked reserved-for operator upstream — forward only, never rule"
    echo "reserved-for: operator"; return 1
  fi
  # The mark is decided BEFORE own-fork, so a seat's own floor or reserved question still
  # goes up marked (re-review R1).
  local own=""
  [ "$raised_by" = "$self" ] && own=" (and own fork — $self raised it)"
  if [ "$floor" != "none" ]; then
    echo "pass-up: IDE-135 floor ($floor) — the operator's, recommendation attached$own"
    echo "reserved-for: operator"; return 1
  fi
  if [[ " $RESERVED_CLASSES " == *" $class "* ]]; then
    echo "pass-up: reserved class $class — never a manager's ruling, recommendation attached$own"
    echo "reserved-for: operator"; return 1
  fi

  # ── GRANT ───────────────────────────────────────────────────────────────────
  # The installed grant is config .grant.classes. Manager mode only (director ruling, R7):
  # coordinate.manager.config.json holds v1 (A–D); the example config's grant is empty.
  local granted is_granted=0 g
  granted=$(jq -r '(.grant.classes // [])[]' "$CFG" 2>/dev/null) || die 2 "config grant does not parse: $CFG"
  while IFS= read -r g; do [ "$g" = "$class" ] && is_granted=1; done <<<"$granted"
  if [ "$class" = "H" ] && [ "$is_granted" -eq 0 ]; then
    echo "pass-up: class H is reserved until the operator marks it$own"
    echo "reserved-for: operator"; return 1
  fi
  # IDE-135 non-goal: a manager never answers its own fork.
  if [ -n "$own" ]; then
    echo "pass-up: own fork — $self raised this question itself"; return 1
  fi
  if [ "$class" = "orientation" ]; then echo rule; return 0; fi
  if [ "$is_granted" -eq 0 ]; then
    echo "pass-up: class $class is not in the installed grant"; return 1
  fi
  echo rule
}

cmd_ask_id() {
  local pane="" q="" have_q=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --pane) pane="${2:-}"; shift 2 ;;
      --question) q="${2:-}"; have_q=1; shift 2 ;;
      *) die 2 "ask-id: unknown argument $1" ;;
    esac
  done
  [ -n "$pane" ] && [ "$have_q" = 1 ] && [ -n "$q" ] || die 2 "ask-id: --pane and --question are required"
  local norm h
  norm=$(printf '%s' "$q" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
  h=$(printf '%s\n%s' "$pane" "$norm" | shasum -a 256 | cut -c1-10)
  echo "hop-${pane#%}-$h"
}

cmd_rowed() {
  local log="" id=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --log) log="${2:-}"; shift 2 ;;
      --id) id="${2:-}"; shift 2 ;;
      *) die 2 "rowed: unknown argument $1" ;;
    esac
  done
  [ -n "$log" ] && [ -n "$id" ] || die 2 "rowed: --log and --id are required"
  [ -e "$log" ] || return 1
  [ -r "$log" ] || die 2 "rowed: log not readable: $log"
  awk -v id="ask:$id" '
    /^## / { inreg = ($0 ~ /🪜 Escalations/) }
    inreg && /^\|/ && index($0, id) { found = 1 }
    END { exit found ? 0 : 1 }' "$log"
}

# inbox — the open asks addressed to this seat (the receiving half of the hop, R2).
# Prints "<seat>/<id>\t<file>\t<reserved-for:operator|->" per ask. Uses `engine ask list --to`
# (HOP_ASK_CLI, default "engine ask"); when that is unavailable, or HOP_ASK_CLI=none, it reads
# the headers under ASK_ROOT directly. Exit 2 when neither works.
cmd_inbox() {
  local self_arg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --self) self_arg="${2:-}"; shift 2 ;;
      *) die 2 "inbox: unknown argument $1" ;;
    esac
  done
  local self root ids="" cli="${HOP_ASK_CLI-engine ask}"
  self=$(resolve_self "$self_arg") || exit $?
  root="${ASK_ROOT:-$HOME/.claude/data/yarik/asks}"
  if [ "$cli" != "none" ]; then
    local out
    # shellcheck disable=SC2086
    if out=$($cli list --status open --to "$self" 2>/dev/null); then
      ids=$(awk -F'\t' 'NF >= 2 { print $2 }' <<<"$out")
    else
      cli=none
    fi
  fi
  if [ "$cli" = "none" ]; then
    [ -d "$root" ] || die 2 "inbox: no ask CLI and no ask root at $root"
    local f
    while IFS= read -r f; do
      awk -v me="$self" '
        NR == 1 && $0 != "---" { exit 1 }
        NR > 1 && $0 == "---" { exit !(to == me && st == "open") }
        /^to: / { to = substr($0, 5) } /^status: / { st = substr($0, 9) }' "$f" \
        && ids+="$(basename "$(dirname "$f")")/$(basename "$f" .md)"$'\n'
    done < <(find "$root" -mindepth 2 -maxdepth 2 -name '*.md' 2>/dev/null | sort)
  fi
  local id file mark
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    file="$root/$id.md"
    mark=$(awk 'NR > 1 && $0 == "---" { exit } /^reserved-for: operator *$/ { print "reserved-for:operator"; exit }' "$file" 2>/dev/null)
    printf '%s\t%s\t%s\n' "$id" "$file" "${mark:--}"
  done <<<"$ids"
}

# panes — the managed panes await-next should sweep: FLEET_MANAGES (or --manages) minus every
# pane whose question is passed up and still unanswered in the register (M3 residual). A pane
# comes back only when its sent row's ack reads `taken …` or `already done …`; a decline (including
# a non-operator answer on a marked ask) keeps it held. Prints a comma-separated list.
cmd_panes() {
  local log="" manages="${FLEET_MANAGES:-}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --log) log="${2:-}"; shift 2 ;;
      --manages) manages="${2:-}"; shift 2 ;;
      *) die 2 "panes: unknown argument $1" ;;
    esac
  done
  [ -n "$log" ] || die 2 "panes: --log is required"
  [ -n "$manages" ] || die 2 "panes: no managed panes (FLEET_MANAGES or --manages)"
  local held=""
  if [ -e "$log" ]; then
    [ -r "$log" ] || die 2 "panes: log not readable: $log"
    held=$(awk -F'|' '
      function trim(x) { gsub(/^[ \t`]+|[ \t`]+$/, "", x); return x }
      /^## / { inreg = ($0 ~ /🪜 Escalations/); next }
      !inreg || $0 !~ /^\|/ || NF < 9 { next }
      {
        dir = trim($2); if (dir != "received" && dir != "sent") next
        if (!match($5, /ask:[^ ·|`]+/)) next
        id = substr($5, RSTART + 4, RLENGTH - 4)
        if (dir == "received") { seat[id] = trim($3); disp[id] = trim($8) }
        else { ack[id] = trim($7) }
      }
      END {
        for (id in seat) {
          if (disp[id] != "passed up") continue
          # Release only on an answer that closes the question. A decline - "not the operator answer"
          # on a marked ask, or any other decline, leaves it still up (RR2).
          if ((id in ack) && (ack[id] ~ /^taken/ || ack[id] ~ /^already done/)) continue
          # The template writes each part in its own backticks: `seat` · `%id` (RR1).
          split(seat[id], parts, " · "); name = parts[1]; pane = parts[2]
          gsub(/[`[:space:]]/, "", name); gsub(/[`[:space:]]/, "", pane)
          if (pane == "" && match(id, /^hop-[0-9]+-/)) pane = "%" substr(id, 5, RLENGTH - 5)
          n = split(name, wl, ":"); print name; print wl[n]; if (pane != "") print pane
        }
      }' "$log")
  fi
  local out="" m
  IFS=',' read -r -a arr <<<"$manages"
  for m in "${arr[@]}"; do
    m="${m// /}"; [ -n "$m" ] || continue
    if grep -qxF -- "$m" <<<"$held"; then continue; fi
    out+="${out:+,}$m"
  done
  # await-next reads an EMPTY --panes as "all of FLEET_MANAGES", so "every pane held" is
  # printed as "-", a name that matches no pane.
  echo "${out:--}"
}

sub="${1:-}"; [ $# -gt 0 ] && shift
case "$sub" in
  target) cmd_target "$@" ;;
  chain) cmd_chain "$@" ;;
  may-rule) cmd_may_rule "$@" ;;
  ask-id) cmd_ask_id "$@" ;;
  rowed) cmd_rowed "$@" ;;
  inbox) cmd_inbox "$@" ;;
  panes) cmd_panes "$@" ;;
  *) sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
