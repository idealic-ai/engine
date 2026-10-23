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
#
# Exit status (the idiom `engine lane-stall` and `engine sweep-check` already use):
#   0  under every cap, dispatching another lane is within budget
#   3  AT or OVER a cap — the reading a refusal is built on
#   2  the directory could not be read: the caller must dispatch ONE lane at a time and say so,
#      never assume it is alone (`¶INV_SLOT_CAP_IS_GLOBAL`)

set -uo pipefail

SLOTS_DIR="${LOOM_SLOTS_DIR:-$HOME/.claude/engine/.loom-slots}"
WINDOW_MIN=20
QUIET=false
MODE=report

while [ $# -gt 0 ]; do
  case "$1" in
    --minutes)    WINDOW_MIN="${2:?--minutes needs a number}"; shift 2 ;;
    --quiet)      QUIET=true; shift ;;
    --lane-alive) MODE=alive; LANE_SESSION="${2:?--lane-alive needs <sessionDir> <laneTag>}"; LANE_TAG="${3:?--lane-alive needs <sessionDir> <laneTag>}"; shift 3 ;;
    --lane-done)  MODE=done;  LANE_SESSION="${2:?--lane-done needs <sessionDir> <laneTag>}";  LANE_TAG="${3:?--lane-done needs <sessionDir> <laneTag>}";  shift 3 ;;
    -h|--help)    sed -n '/^# Usage:/,/^#   2 /p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

for f in "$SLOTS_DIR"/*.slots; do
  [ -f "$f" ] || continue
  sessionDir=""; cap=""; liveLanes=""; heartbeat=""
  while IFS='=' read -r k v; do
    case "$k" in
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

[ "$at_cap" = 1 ] && exit 3
exit 0
