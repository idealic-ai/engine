#!/bin/bash
# ~/.claude/engine/scripts/loom-slots.sh — the global live-lane count, COMPUTED rather than asserted.
#
# Related:
#   Skills: skills/loom/SKILL.md — `¶INV_SLOT_CAP_IS_GLOBAL`, the Setup slot ledger, the relay
#   Tests:  skills/loom/assets/__tests__/slot-cap.test.sh
#
# WHY THIS EXISTS
#   `¶INV_SLOT_CAP_IS_GLOBAL` puts the count in `~/.claude/engine/.loom-slots/`, one file per loom,
#   one writer per file. The directory works and is readable across processes. What is missing is
#   that nothing executable reads or writes it: the files are maintained BY HAND by the conductor,
#   which is the one party the cap constrains, and a record whose writer is the thing it limits
#   drifts in exactly the direction that lets more lanes run. A cap is enforced by a REFUSAL over a
#   count somebody else computed, not by a number its beneficiary keeps.
#
#   So this reads the directory and computes. It refuses nothing on its own — a reader cannot be a
#   gate — but it is the thing a gate, or a conductor, asks.
#
# TWO SCHEMAS, DELIBERATELY
#   legacy  `<loom>.slots`               — key=value, conductor-written: sessionDir, cap, liveLanes, heartbeat.
#                                          One heartbeat for the whole loom, so one forgotten rewrite
#                                          makes every lane in it stale or every ended lane live.
#   lane    `<loom>/<laneTag>.live`      — one file per LANE, refreshed by the lane itself. Liveness is
#                                          then asserted by the thing that is live, and a lane that
#                                          dies stops refreshing without anyone having to notice.
#                                          `--lane-alive` is that refresh, and `cap` still comes from
#                                          the loom's own `.slots` file because a cap is a disposition,
#                                          not a liveness signal.
#   Where a loom has lane files they WIN for that loom's count, and the legacy liveLanes list is
#   reported alongside as `asserted` so a disagreement is visible instead of silently resolved.
#
# AGES ARE COMPUTED, NEVER EYEBALLED
#   The stamps are `Z`. This machine is not. Reading a Z stamp against local time overstates an age
#   by the UTC offset — the mistake that reported a 2-minute-old loom as stale. Every age here comes
#   from epoch arithmetic.
#
# Usage:
#   engine loom-slots                             Report every loom, the global figure, and the verdict
#   engine loom-slots --minutes N                 Staleness window (default 20)
#   engine loom-slots --quiet                     Exit status only
#   engine loom-slots --lane-alive <sessionDir> <laneTag>
#                                                 Refresh THIS lane's liveness file (what a lane calls)
#   engine loom-slots --lane-done  <sessionDir> <laneTag>
#                                                 Remove it (what a lane calls as it hands back)
#   engine loom-slots --dispatching <item>[,<item>...] [--self <sessionDir>]
#                                                 Also warn (stderr, even with --quiet) when another
#                                                 loom claims a ticket key or an overlapping path
#   engine loom-slots --claim <sessionDir> <item>...
#                                                 Claim tickets or paths for this loom, state `working`
#   engine loom-slots --claim-state <sessionDir> <item> working|done-uncommitted|landed
#                                                 Move a claim on; `landed` removes it
#   engine loom-slots --release <sessionDir> <item>...
#                                                 Drop a claim without landing it
#
# WORK CLAIMS
#   A `claims=` line in a loom's `.slots` file: `item|state|stampZ`, comma-separated. A claim is NOT
#   a liveness signal and never expires: it is reported however stale the row is and however empty
#   its lanes, because a loom whose lanes have ended can still hold finished, uncommitted work. Only
#   `landed` or `--release` removes one. The claim commands rewrite only that line and keep the
#   file's mtime, so writing a claim never makes a dead row look live.
#
# Exit status (the idiom `engine lane-stall` and `engine sweep-check` already use):
#   0  under every cap, dispatching another lane is within budget
#   3  AT or OVER a cap — the reading a refusal is built on
#   2  the directory could not be read: the caller must dispatch ONE lane at a time and say so,
#      never assume it is alone (`¶INV_SLOT_CAP_IS_GLOBAL`)
#   4  under cap, but --dispatching overlaps another loom's claim (3 wins when both hold)

set -uo pipefail

SLOTS_DIR="${LOOM_SLOTS_DIR:-$HOME/.claude/engine/.loom-slots}"
WINDOW_MIN=20
QUIET=false
MODE=report
SELF=""
DISPATCHING=""
CLAIM_SESSION=""; CLAIM_STATE=""; CLAIM_ITEMS=()

# take_items — the items after a claim command's sessionDir, up to the next --flag.
take_items() {
  CLAIM_ITEMS=()
  while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do CLAIM_ITEMS+=("$1"); shift; done
}

while [ $# -gt 0 ]; do
  case "$1" in
    --minutes)    WINDOW_MIN="${2:?--minutes needs a number}"; shift 2 ;;
    --quiet)      QUIET=true; shift ;;
    --self)       SELF="${2:?--self needs <sessionDir>}"; shift 2 ;;
    --dispatching) DISPATCHING="${DISPATCHING:+$DISPATCHING,}${2:?--dispatching needs <item>[,<item>...]}"; shift 2 ;;
    --claim|--release)
      MODE="${1#--}"; CLAIM_SESSION="${2:?$1 needs <sessionDir> <item>...}"; shift 2
      take_items "$@"; shift "${#CLAIM_ITEMS[@]}"
      [ "${#CLAIM_ITEMS[@]}" -gt 0 ] || { printf 'loom-slots: --%s needs at least one item\n' "$MODE" >&2; exit 2; } ;;
    --claim-state)
      MODE=claim-state; CLAIM_SESSION="${2:?--claim-state needs <sessionDir> <item> <state>}"
      CLAIM_ITEMS=("${3:?--claim-state needs <sessionDir> <item> <state>}")
      CLAIM_STATE="${4:?--claim-state needs <sessionDir> <item> <state>}"; shift 4 ;;
    --lane-alive) MODE=alive; LANE_SESSION="${2:?--lane-alive needs <sessionDir> <laneTag>}"; LANE_TAG="${3:?--lane-alive needs <sessionDir> <laneTag>}"; shift 3 ;;
    --lane-done)  MODE=done;  LANE_SESSION="${2:?--lane-done needs <sessionDir> <laneTag>}";  LANE_TAG="${3:?--lane-done needs <sessionDir> <laneTag>}";  shift 3 ;;
    -h|--help)    sed -n '/^# Usage:/,/^#   4 /p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'loom-slots: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# slugify — the same spelling the skill uses for a loom's file name: the session directory with
# every non-alphanumeric run collapsed to a dash. One loom, one spelling, so two processes naming
# the same loom produce the same path.
slugify() { printf '%s' "$1" | sed 's/[^A-Za-z0-9@.]\{1,\}/-/g; s/^-//; s/-$//'; }

now_epoch() { date -u +%s; }

# iso_to_epoch — BSD date first (this machine), GNU date second, so the script is not pinned to one.
iso_to_epoch() {
  local s="$1" e=""
  e="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$s" +%s 2>/dev/null)" && { printf '%s' "$e"; return 0; }
  e="$(date -u -d "$s" +%s 2>/dev/null)" && { printf '%s' "$e"; return 0; }
  return 1
}

if [ "$MODE" = alive ] || [ "$MODE" = done ]; then
  d="$SLOTS_DIR/$(slugify "$LANE_SESSION")"
  f="$d/$(slugify "$LANE_TAG").live"
  if [ "$MODE" = done ]; then
    rm -f "$f"
    exit 0
  fi
  mkdir -p "$d" 2>/dev/null || { printf 'loom-slots: cannot create %s\n' "$d" >&2; exit 2; }
  # The CONTENT is for a human reading the directory; the MTIME is what the count uses, because a
  # touch cannot half-succeed the way a rewritten stanza can.
  printf 'lane=%s\nsessionDir=%s\nheartbeat=%s\n' "$LANE_TAG" "$LANE_SESSION" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$f"
  exit 0
fi

# loom_file — the loom's own file: the one whose sessionDir line names it, else the slug. Found by
# content first because hand-written files exist whose names are not the slug.
loom_file() {
  local sd="$1" f
  for f in "$SLOTS_DIR"/*.slots; do
    [ -f "$f" ] || continue
    if grep -qxF "sessionDir=$sd" "$f"; then printf '%s' "$f"; return 0; fi
  done
  printf '%s/%s.slots' "$SLOTS_DIR" "$(slugify "$sd")"
}

# claim_key — the comparison form of an item: a ticket key upper-cased, a path without ./ or a
# trailing slash.
is_ticket_key() { printf '%s' "$1" | grep -Eq '^[A-Za-z][A-Za-z0-9]*-[0-9]+$'; }
claim_key() {
  local x="$1"
  if is_ticket_key "$x"; then printf '%s' "$x" | tr '[:lower:]' '[:upper:]'; return; fi
  x="${x#./}"; while [ "${x%/}" != "$x" ]; do x="${x%/}"; done
  printf '%s' "$x"
}

# items_overlap — same ticket key, or one path at or under the other at a path boundary.
items_overlap() {
  local a b; a="$(claim_key "$1")"; b="$(claim_key "$2")"
  [ -n "$a" ] && [ -n "$b" ] || return 1
  [ "$a" = "$b" ] && return 0
  if is_ticket_key "$a" || is_ticket_key "$b"; then return 1; fi
  case "$a" in "$b"/*) return 0 ;; esac
  case "$b" in "$a"/*) return 0 ;; esac
  return 1
}

if [ "$MODE" = claim ] || [ "$MODE" = release ] || [ "$MODE" = claim-state ]; then
  case "$MODE:$CLAIM_STATE" in
    claim-state:working|claim-state:done-uncommitted|claim-state:landed|claim:|release:) ;;
    *) printf 'loom-slots: state must be working, done-uncommitted or landed (got %s)\n' "$CLAIM_STATE" >&2; exit 2 ;;
  esac
  for it in "${CLAIM_ITEMS[@]}"; do
    case "$it" in
      ''|*,*|*'|'*|*$'\n'*) printf 'loom-slots: a claim item may not be empty or contain "," or "|": %s\n' "$it" >&2; exit 2 ;;
    esac
  done
  mkdir -p "$SLOTS_DIR" 2>/dev/null || { printf 'loom-slots: cannot create %s\n' "$SLOTS_DIR" >&2; exit 2; }
  f="$(loom_file "$CLAIM_SESSION")"
  current=""
  [ -f "$f" ] && current="$(sed -n 's/^claims=//p' "$f" | tail -1)"
  stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  next=""
  # Keep every existing claim except the ones this call names; then append the named ones in their
  # new state, unless that state removes them.
  IFS=',' read -r -a existing <<< "$current"
  for c in ${existing[@]+"${existing[@]}"}; do
    [ -n "$c" ] || continue
    ci="${c%%|*}"; hit=0
    for it in "${CLAIM_ITEMS[@]}"; do [ "$(claim_key "$ci")" = "$(claim_key "$it")" ] && hit=1; done
    if [ "$hit" = 1 ] && [ "$MODE" = claim-state ]; then
      [ "$CLAIM_STATE" = landed ] || next="${next:+$next,}$ci|$CLAIM_STATE|$stamp"
      continue
    fi
    [ "$hit" = 1 ] && continue
    next="${next:+$next,}$c"
  done
  if [ "$MODE" = claim ]; then
    for it in "${CLAIM_ITEMS[@]}"; do next="${next:+$next,}$it|working|$stamp"; done
  fi
  tmp="$(mktemp "$SLOTS_DIR/.claims.XXXXXX")" || exit 2
  if [ -f "$f" ]; then
    awk '!/^claims=/' "$f" > "$tmp"
  else
    printf 'sessionDir=%s\n' "$CLAIM_SESSION" > "$tmp"
  fi
  printf 'claims=%s\n' "$next" >> "$tmp"
  [ -f "$f" ] && touch -r "$f" "$tmp"
  mv "$tmp" "$f" || { rm -f "$tmp"; exit 2; }
  exit 0
fi

if [ ! -d "$SLOTS_DIR" ] || [ ! -r "$SLOTS_DIR" ]; then
  $QUIET || {
    printf '\nloom-slots: cannot read %s\n' "$SLOTS_DIR"
    printf '  A loom that cannot read the slot directory dispatches ONE lane at a time and SAYS SO.\n'
    printf '  It does not assume it is alone — a loom that believes it holds the whole budget is the\n'
    printf '  failure the directory exists to prevent.\n\n'
  }
  exit 2
fi

NOW="$(now_epoch)"
WINDOW_SEC=$((WINDOW_MIN * 60))

global_live=0
global_stale_looms=0
global_stale_lanes=0
at_cap=0
rows=""
claim_rows=""
overlaps=0
overlap_lines=""

for f in "$SLOTS_DIR"/*.slots; do
  [ -f "$f" ] || continue
  sessionDir=""; cap=""; liveLanes=""; heartbeat=""; claims=""
  while IFS='=' read -r k v; do
    case "$k" in
      claims)     claims="$v" ;;
      sessionDir) sessionDir="$v" ;;
      cap)        cap="$v" ;;
      liveLanes)  liveLanes="$v" ;;
      heartbeat)  heartbeat="$v" ;;
    esac
  done < "$f"

  name="$(basename "$f" .slots)"
  short="${sessionDir##*/}"; [ -n "$short" ] || short="$name"

  # Asserted lanes: the conductor's own list.
  asserted=0
  if [ -n "$liveLanes" ]; then
    asserted="$(printf '%s' "$liveLanes" | tr ',' '\n' | grep -c '[^[:space:]]')"
  fi

  # Observed lanes: per-lane files this loom's own lanes refreshed. Fresh ones count; aged ones are
  # NAMED, because a count that quietly discards rows cannot be told from one that found none.
  lane_dir="$SLOTS_DIR/$name"
  observed=0; observed_stale=0; observed_names=""; stale_names=""
  have_lane_files=0
  if [ -d "$lane_dir" ]; then
    for lf in "$lane_dir"/*.live; do
      [ -f "$lf" ] || continue
      have_lane_files=1
      lt="$(basename "$lf" .live)"
      m="$(stat -f %m "$lf" 2>/dev/null || stat -c %Y "$lf" 2>/dev/null || echo 0)"
      age=$(( (NOW - m) / 60 ))
      if [ "$age" -le "$WINDOW_MIN" ]; then
        observed=$((observed+1)); observed_names="${observed_names:+$observed_names,}$lt(${age}m)"
      else
        observed_stale=$((observed_stale+1)); stale_names="${stale_names:+$stale_names,}$lt(${age}m)"
      fi
    done
  fi

  # The loom's own heartbeat, from its stanza, with the file's mtime as a fallback so a stanza with
  # an unparseable stamp still yields an age rather than an unknown.
  hb_epoch=""; hb_src="stanza"
  if [ -n "$heartbeat" ]; then hb_epoch="$(iso_to_epoch "$heartbeat" || true)"; fi
  if [ -z "$hb_epoch" ]; then
    hb_epoch="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)"
    hb_src="file-mtime"
  fi
  loom_age=$(( (NOW - hb_epoch) / 60 ))
  loom_fresh=0
  [ "$loom_age" -le "$WINDOW_MIN" ] && loom_fresh=1

  # WHICH NUMBER COUNTS. Lane files, where they exist, because each one is refreshed by the lane it
  # describes. Otherwise the conductor's asserted list, gated on the loom's own heartbeat being
  # fresh — a stale loom row is reported and not counted.
  if [ "$have_lane_files" = 1 ]; then
    counted="$observed"; basis="observed"
  elif [ "$loom_fresh" = 1 ]; then
    counted="$asserted"; basis="asserted"
  else
    counted=0; basis="stale-not-counted"
    global_stale_looms=$((global_stale_looms+1))
  fi

  global_live=$((global_live + counted))
  global_stale_lanes=$((global_stale_lanes + observed_stale))

  capnum="${cap:-0}"
  case "$capnum" in ''|*[!0-9]*) capnum=0 ;; esac
  verdict="under"
  if [ "$capnum" -gt 0 ] && [ "$counted" -ge "$capnum" ]; then verdict="AT-CAP"; at_cap=1; fi
  [ "$basis" = "stale-not-counted" ] && verdict="stale"

  # The newline is appended OUTSIDE the substitution: `$( )` strips trailing newlines, so building
  # a table by `rows="$rows$(printf '...\n')"` silently runs every row into the previous one.
  rows="$rows$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "$short" "${cap:-?}" "$counted" "$basis" "${loom_age}m" "$hb_src" "$verdict" "${observed_names:-${liveLanes:-—}}")
"
  # Claims are read off EVERY row, counted or not: the row that is stale with no lanes is the one
  # whose finished-but-uncommitted work a second loom is about to redo.
  if [ -n "$claims" ]; then
    is_self=0
    [ -n "$SELF" ] && [ "$sessionDir" = "$SELF" ] && is_self=1
    rowstate="fresh"; [ "$loom_fresh" = 1 ] || rowstate="stale(${loom_age}m)"
    [ "$counted" -gt 0 ] || rowstate="$rowstate,no-live-lanes"
    IFS=',' read -r -a row_claims <<< "$claims"
    for c in ${row_claims[@]+"${row_claims[@]}"}; do
      [ -n "$c" ] || continue
      ci="${c%%|*}"; rest="${c#*|}"; cs="${rest%%|*}"; ct="${rest#*|}"
      cage="?"
      ce="$(iso_to_epoch "$ct" || true)"; [ -n "$ce" ] && cage="$(( (NOW - ce) / 60 ))m"
      who="$short"; [ "$is_self" = 1 ] && who="$short (this loom)"
      claim_rows="$claim_rows$(printf '%s\t%s\t%s\t%s\t%s' "$who" "$ci" "$cs" "$cage" "$rowstate")
"
      [ "$is_self" = 1 ] && continue
      if [ -n "$DISPATCHING" ]; then
        IFS=',' read -r -a want <<< "$DISPATCHING"
        for w in ${want[@]+"${want[@]}"}; do
          [ -n "$w" ] || continue
          if items_overlap "$w" "$ci"; then
            overlaps=$((overlaps+1))
            overlap_lines="$overlap_lines$(printf '  WARNING: dispatching %s overlaps %s, claimed %s by %s %s ago (row %s).' "$w" "$ci" "$cs" "$short" "$cage" "$rowstate")
"
          fi
        done
      fi
    done
  fi

  if [ -n "$stale_names" ]; then
    rows="$rows$(printf '  ↳\t\t%s\t%s\t\t\t%s\t%s' "$observed_stale" "stale-lane-files" "named" "$stale_names")
"
  fi
done

if [ -z "$rows" ]; then
  $QUIET || {
    printf '\nloom-slots: %s is readable and holds no loom files.\n' "$SLOTS_DIR"
    printf '  That is a reading, not a clean budget: it means no loom has registered, which on a\n'
    printf '  machine with live looms means they are not writing their files.\n\n'
  }
  exit 0
fi

if ! $QUIET; then
  printf '\n== Global live-lane budget (window %sm, computed from epoch — the stamps are Z, this machine is not) ==\n\n' "$WINDOW_MIN"
  { printf 'LOOM\tCAP\tLIVE\tBASIS\tAGE\tFROM\tVERDICT\tLANES\n'; printf '%s\n' "$rows"; } | column -t -s "$(printf '\t')"
  printf '\n  global live lanes : %s\n' "$global_live"
  printf '  stale loom rows   : %s (reported, not counted)\n' "$global_stale_looms"
  printf '  stale lane files  : %s (reported, not counted)\n' "$global_stale_lanes"
  if [ "$at_cap" = 1 ]; then
    printf '\n  VERDICT: a loom is AT or OVER its cap. A dispatch past it is the refusal this count exists for.\n\n'
  else
    printf '\n  VERDICT: every live loom is under its cap.\n'
    printf '  NOTE: each cap above is that loom'"'"'s OWN. There is no single machine-wide number here, so\n'
    printf '        %s lanes running under separate caps is not a cap violation and is not a global cap either.\n\n' "$global_live"
  fi
fi

if [ -n "$claim_rows" ] && ! $QUIET; then
  printf '== Work claims (kept until landed or released; a stale row with no lanes can still hold uncommitted work) ==\n\n'
  { printf 'LOOM\tITEM\tSTATE\tSINCE\tROW\n'; printf '%s' "$claim_rows"; } | column -t -s "$(printf '\t')"
  printf '\n'
fi

# Overlaps go to stderr so --quiet, which silences the table, cannot silence them.
if [ "$overlaps" -gt 0 ]; then
  {
    printf '\nloom-slots: %s overlap(s) with another loom'"'"'s work claims:\n' "$overlaps"
    printf '%s' "$overlap_lines"
    printf '  Ask that loom (or its session log) before dispatching into it: a claim on a stale row is\n'
    printf '  work nobody has landed yet, not work nobody owns.\n\n'
  } >&2
fi

[ "$at_cap" = 1 ] && exit 3
[ "$overlaps" -gt 0 ] && exit 4
exit 0
