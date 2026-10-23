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
#   legacy  `<loom>.slots`               — key=value, the conductor's row: sessionDir, cap, liveLanes, heartbeat
#                                          (written with --heartbeat), plus claims (the claim commands).
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
#   engine loom-slots --heartbeat <sessionDir> [--cap N] [--lanes <id>,<id>...]
#                                                 Write this loom's row: session directory, cap, lanes,
#                                                 a fresh heartbeat. Keeps claims and anything else in
#                                                 the file; a cap or lane list not given is kept too.
#                                                 With no row yet, CREATES one at the generated name
#                                                 with an empty claims= line. The only way a conductor
#                                                 writes or creates its row
#   engine loom-slots --lane-alive <sessionDir> <laneTag>
#                                                 Refresh THIS lane's liveness file (what a lane calls)
#   engine loom-slots --lane-done  <sessionDir> <laneTag>
#                                                 Remove it (what a lane calls as it hands back)
#   engine loom-slots --dispatching <item>[,<item>...] [--self <sessionDir>] [--repo <dir>]
#                                                 Also warn (stderr, even with --quiet) when another
#                                                 loom claims a ticket key or an overlapping path
#   engine loom-slots --claim <sessionDir> <item>[,<item>...]...
#                                                 Claim tickets or paths for this loom, state `working`.
#                                                 Batch a dispatch's items into one call
#   engine loom-slots --claim-state <sessionDir> <item> working|done-uncommitted|landed
#                                                 Move a claim on; `landed` removes it. An item
#                                                 that is not claimed is refused (exit 1)
#   engine loom-slots --release <sessionDir> <item>...
#                                                 Drop a claim without landing it
#
# WORK CLAIMS
#   A `claims=` line in a loom's `.slots` file: `item|state|stampZ`, comma-separated, each item in
#   its claim_key form (below): a ticket key, or `<repo>::<path in repo>`. Relative paths resolve
#   against --repo, else the working directory's repository. A claim is NOT
#   a liveness signal and never expires: it is reported however stale the row is and however empty
#   its lanes, because a loom whose lanes have ended can still hold finished, uncommitted work. Only
#   `landed` or `--release` removes one. The claim commands rewrite only that line and keep the
#   file's mtime, so writing a claim never makes a dead row look live.
#
# Exit status (the idiom `engine lane-stall` and `engine sweep-check` already use):
#   0  under every cap, dispatching another lane is within budget; or a write succeeded
#   1  a write command refused its input: a bad item, state or cap, or an item that is not claimed
#   2  the directory could not be read: the caller must dispatch ONE lane at a time and say so,
#      never assume it is alone (`¶INV_SLOT_CAP_IS_GLOBAL`); also an unknown argument
#   3  AT or OVER a cap — the reading a refusal is built on
#   4  under cap, but --dispatching overlaps another loom's claim (3 wins when both hold)
#   5  a write failed (lock, temp file or rename): nothing was written
# (end of help)

set -uo pipefail

SLOTS_DIR="${LOOM_SLOTS_DIR:-$HOME/.claude/engine/.loom-slots}"
WINDOW_MIN=20
QUIET=false
MODE=report
SELF=""
REPO_ARG=""
REPO_BASE=""
HB_CAP=""; HB_SET_CAP=0; HB_LANES=""; HB_SET_LANES=0
DISPATCHING=""
CLAIM_SESSION=""; CLAIM_STATE=""; CLAIM_ITEMS=()

# take_items — the items after a claim command's sessionDir, up to the next --flag. Each argument
# may itself be a comma list, so one call can claim everything a dispatch takes.
take_items() {
  CLAIM_ITEMS=()
  local a part
  while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do
    a="$1"; shift
    IFS=',' read -r -a parts <<< "$a"
    for part in ${parts[@]+"${parts[@]}"}; do CLAIM_ITEMS+=("$part"); done
    TAKEN=$((TAKEN+1))
  done
}

while [ $# -gt 0 ]; do
  case "$1" in
    --minutes)    WINDOW_MIN="${2:?--minutes needs a number}"; shift 2 ;;
    --quiet)      QUIET=true; shift ;;
    --self)       SELF="${2:?--self needs <sessionDir>}"; shift 2 ;;
    --repo)       REPO_ARG="${2:?--repo needs <dir>}"; shift 2 ;;
    --dispatching) DISPATCHING="${DISPATCHING:+$DISPATCHING,}${2:?--dispatching needs <item>[,<item>...]}"; shift 2 ;;
    --claim|--release)
      MODE="${1#--}"; CLAIM_SESSION="${2:?$1 needs <sessionDir> <item>...}"; shift 2
      TAKEN=0; take_items "$@"; shift "$TAKEN"
      [ "${#CLAIM_ITEMS[@]}" -gt 0 ] || { printf 'loom-slots: --%s needs at least one item\n' "$MODE" >&2; exit 1; } ;;
    --heartbeat)  MODE=heartbeat; CLAIM_SESSION="${2:?--heartbeat needs <sessionDir>}"; shift 2 ;;
    --cap)        HB_CAP="${2:?--cap needs a number}"; HB_SET_CAP=1; shift 2 ;;
    --lanes)      HB_LANES="${2?--lanes needs a list (may be empty: --lanes '')}"; HB_SET_LANES=1; shift 2 ;;
    --claim-state)
      MODE=claim-state; CLAIM_SESSION="${2:?--claim-state needs <sessionDir> <item> <state>}"
      CLAIM_ITEMS=("${3:?--claim-state needs <sessionDir> <item> <state>}")
      CLAIM_STATE="${4:?--claim-state needs <sessionDir> <item> <state>}"; shift 4 ;;
    --lane-alive) MODE=alive; LANE_SESSION="${2:?--lane-alive needs <sessionDir> <laneTag>}"; LANE_TAG="${3:?--lane-alive needs <sessionDir> <laneTag>}"; shift 3 ;;
    --lane-done)  MODE=done;  LANE_SESSION="${2:?--lane-done needs <sessionDir> <laneTag>}";  LANE_TAG="${3:?--lane-done needs <sessionDir> <laneTag>}";  shift 3 ;;
    -h|--help)    sed -n '/^# Usage:/,/^# (end of help)$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# canon_session — one spelling per session directory: trailing slashes stripped and, when the
# directory exists, symlinks resolved. Two spellings of one loom must meet on one row.
canon_session() {
  local sd="$1" r
  while [ "${#sd}" -gt 1 ] && [ "${sd%/}" != "$sd" ]; do sd="${sd%/}"; done
  if [ -d "$sd" ] && r="$(cd "$sd" 2>/dev/null && pwd -P)"; then sd="$r"; fi
  printf '%s' "$sd"
}

[ -n "$SELF" ] && SELF="$(canon_session "$SELF")"
if [ -n "$REPO_ARG" ]; then
  REPO_BASE="$(git -C "$REPO_ARG" rev-parse --show-toplevel 2>/dev/null || (cd "$REPO_ARG" 2>/dev/null && pwd -P))" \
    || { printf 'loom-slots: --repo %s is not a directory\n' "$REPO_ARG" >&2; exit 1; }
fi
[ -n "$CLAIM_SESSION" ] && CLAIM_SESSION="$(canon_session "$CLAIM_SESSION")"
[ -n "${LANE_SESSION:-}" ] && LANE_SESSION="$(canon_session "$LANE_SESSION")"

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
# file_hb_epoch — a row's heartbeat as epoch seconds: its stanza stamp, else the file's mtime.
file_hb_epoch() {
  local f="$1" h e=""
  h="$(sed -n 's/^heartbeat=//p' "$f" | tail -1)"
  [ -n "$h" ] && e="$(iso_to_epoch "$h" || true)"
  [ -n "$e" ] || e="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)"
  printf '%s' "$e"
}

# Where two rows name one loom (a legacy hand-named file beside the generated one), writes go to
# the one with the freshest heartbeat — the same row the reader counts.
loom_file() {
  local sd="$1" f v best="" best_e=-1 e
  for f in "$SLOTS_DIR"/*.slots; do
    [ -f "$f" ] || continue
    v="$(sed -n 's/^sessionDir=//p' "$f" | tail -1)"
    [ -n "$v" ] || continue
    [ "$(canon_session "$v")" = "$sd" ] || continue
    e="$(file_hb_epoch "$f")"
    if [ "$e" -gt "$best_e" ]; then best="$f"; best_e="$e"; fi
  done
  if [ -n "$best" ]; then printf '%s' "$best"; return 0; fi
  printf '%s/%s.slots' "$SLOTS_DIR" "$(slugify "$sd")"
}

# claim_key — the one comparison form of an item, applied to what is claimed and to what is about
# to be dispatched, so a ticket or a path typed two ways still meets itself.
#   ticket  any item carrying a key — `FIN-3141`, a `fin-3141-fix-the-thing` branch, `[FIN-3141]`,
#           a Linear URL — becomes the upper-cased key.
#   path    made absolute (a relative path against --repo, else the git top level of the working
#           directory, else the working directory), `.`/`..`/`//` folded, symlinks resolved on the
#           part that exists, then written `<repo>::<path in repo>`. <repo> is the MAIN checkout
#           (from git's common directory), so worktrees of one repository meet and two
#           repositories never do. A path outside any repository stays absolute.
# A ticket and a path never match each other: claim both forms when a dispatch has both.
KEY_RE='[A-Za-z][A-Za-z0-9]*-[0-9]+'
is_ticket_key() { printf '%s' "$1" | grep -Eq "^$KEY_RE\$"; }
trim() { local x="$1"; x="${x#"${x%%[![:space:]]*}"}"; x="${x%"${x##*[![:space:]]}"}"; printf '%s' "$x"; }
upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

ticket_of() { # prints the key an item carries, or nothing
  local x="$1" seg k
  case "$x" in
    *'['*']'*) k="$(printf '%s' "$x" | sed -En "s/.*\[($KEY_RE)\].*/\1/p" | head -1)"
               [ -n "$k" ] && { upper "$k"; return; } ;;
  esac
  case "$x" in
    *://*) IFS='/' read -r -a segs <<< "${x%%[?#]*}"
           for seg in ${segs[@]+"${segs[@]}"}; do is_ticket_key "$seg" && k="$seg"; done
           [ -n "${k:-}" ] && upper "$k"; return ;;
    */*) return ;;
  esac
  k="$(printf '%s' "$x" | sed -En "s/^($KEY_RE)(-.*)?\$/\1/p")"
  [ -n "$k" ] && upper "$k"
}

fold_path() { # lexical: absolute in, absolute out, no ., .., or //
  local p="$1" out="" seg
  IFS='/' read -r -a segs <<< "$p"
  for seg in ${segs[@]+"${segs[@]}"}; do
    case "$seg" in
      ''|.) ;;
      ..) out="${out%/*}" ;;
      *)  out="$out/$seg" ;;
    esac
  done
  printf '%s' "${out:-/}"
}

path_key() {
  local x="$1" base abs anc rest top common root
  case "$x" in *::*) printf '%s' "$x"; return ;; esac
  if [ "${x#/}" = "$x" ]; then
    base="$REPO_BASE"
    [ -n "$base" ] || base="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
    x="$base/$x"
  fi
  abs="$(fold_path "$x")"
  anc="$abs"; rest=""
  while [ "$anc" != "/" ] && [ ! -d "$anc" ]; do rest="/${anc##*/}$rest"; anc="${anc%/*}"; [ -n "$anc" ] || anc="/"; done
  anc="$(cd "$anc" 2>/dev/null && pwd -P || printf '%s' "$anc")"
  abs="$(fold_path "$anc$rest")"
  top="$(git -C "$anc" rev-parse --show-toplevel 2>/dev/null)" || top=""
  if [ -z "$top" ]; then printf '%s' "$abs"; return; fi
  top="$(cd "$top" && pwd -P)"
  common="$(cd "$anc" && cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)" || common="$top/.git"
  case "$common" in */.git) root="${common%/.git}" ;; *) root="$common" ;; esac
  rest="${abs#"$top"}"; rest="${rest#/}"
  printf '%s::%s' "$root" "$rest"
}

claim_key() {
  local x k; x="$(trim "$1")"
  [ -n "$x" ] || return 0
  k="$(ticket_of "$x")"
  if [ -n "$k" ]; then printf '%s' "$k"; return; fi
  path_key "$x"
}

# items_overlap — over claim_key forms: the same key, or one path at or under the other, inside one
# repository and at a path boundary.
items_overlap() {
  local a="$1" b="$2" ra=0 rb=0
  [ -n "$a" ] && [ -n "$b" ] || return 1
  [ "$a" = "$b" ] && return 0
  if is_ticket_key "$a" || is_ticket_key "$b"; then return 1; fi
  case "$a" in *::*) ra=1 ;; esac
  case "$b" in *::*) rb=1 ;; esac
  if [ "$ra" = 1 ] && [ "$rb" = 1 ]; then
    [ "${a%%::*}" = "${b%%::*}" ] || return 1
    a="${a#*::}"; b="${b#*::}"
    if [ -z "$a" ] || [ -z "$b" ]; then return 0; fi
  elif [ "$ra" != "$rb" ]; then
    return 1
  fi
  case "$a" in "$b"/*) return 0 ;; esac
  case "$b" in "$a"/*) return 0 ;; esac
  return 1
}

# with_lock — a mkdir lock around a read-modify-write of one loom's file. One conductor issuing
# several writes at once is the ordinary case, and a rename alone keeps each write whole without
# stopping two of them from each dropping the other's change. A lock older than 60s is a dead
# writer's and is broken.
LOCK=""
release_lock() { [ -n "$LOCK" ] && rmdir "$LOCK" 2>/dev/null; LOCK=""; }
take_lock() {
  local l="$1" i=0 m
  while ! mkdir "$l" 2>/dev/null; do
    [ -w "$(dirname "$l")" ] || return 1
    i=$((i+1))
    if [ $((i % 50)) -eq 0 ]; then
      m="$(stat -f %m "$l" 2>/dev/null || stat -c %Y "$l" 2>/dev/null || echo "")"
      [ -n "$m" ] && [ $(( $(now_epoch) - m )) -gt 60 ] && rmdir "$l" 2>/dev/null
    fi
    [ "$i" -ge 600 ] && return 1
    sleep 0.05
  done
  LOCK="$l"; trap release_lock EXIT
}

# write_fail — a write that did not happen. Its own exit code (5), so it is never read as exit 2's
# "the directory could not be read".
write_fail() { printf 'loom-slots: %s — nothing was written\n' "$1" >&2; release_lock; exit 5; }

# --heartbeat — the conductor's own write: session directory, cap, lanes and heartbeat, with every
# other line (claims above all) carried over unchanged. A cap or lane list not given is kept.
if [ "$MODE" = heartbeat ]; then
  if [ "$HB_SET_CAP" = 1 ]; then
    case "$HB_CAP" in ''|*[!0-9]*) printf 'loom-slots: --cap must be a whole number (got %s)\n' "$HB_CAP" >&2; exit 1 ;; esac
  fi
  case "$HB_LANES" in *$'\n'*) printf 'loom-slots: --lanes may not contain a newline\n' >&2; exit 1 ;; esac
  mkdir -p "$SLOTS_DIR" 2>/dev/null || write_fail "cannot create $SLOTS_DIR"
  f="$(loom_file "$CLAIM_SESSION")"
  take_lock "$SLOTS_DIR/.$(basename "$f").lock" || write_fail "could not take the lock on $f (held for 30s, or the directory is not writable)"
  old_cap=""; old_lanes=""
  if [ -f "$f" ]; then
    old_cap="$(sed -n 's/^cap=//p' "$f" | tail -1)"
    old_lanes="$(sed -n 's/^liveLanes=//p' "$f" | tail -1)"
  fi
  [ "$HB_SET_CAP" = 1 ] || HB_CAP="$old_cap"
  [ "$HB_SET_LANES" = 1 ] || HB_LANES="$old_lanes"
  tmp="$(mktemp "$SLOTS_DIR/.claims.XXXXXX")" || write_fail "cannot create a temporary file in $SLOTS_DIR"
  {
    printf 'sessionDir=%s\ncap=%s\nliveLanes=%s\nheartbeat=%s\n' \
      "$CLAIM_SESSION" "$HB_CAP" "$HB_LANES" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [ -f "$f" ]; then
      awk '!/^(sessionDir|cap|liveLanes|heartbeat)=/' "$f"
    else
      printf 'claims=\n'
    fi
  } > "$tmp" || { rm -f "$tmp"; write_fail "cannot copy $f"; }
  chmod 644 "$tmp"
  mv "$tmp" "$f" || { rm -f "$tmp"; write_fail "cannot replace $f"; }
  release_lock
  exit 0
fi

if [ "$MODE" = claim ] || [ "$MODE" = release ] || [ "$MODE" = claim-state ]; then
  case "$MODE:$CLAIM_STATE" in
    claim-state:working|claim-state:done-uncommitted|claim-state:landed|claim:|release:) ;;
    *) printf 'loom-slots: state must be working, done-uncommitted or landed (got %s)\n' "$CLAIM_STATE" >&2; exit 1 ;;
  esac
  norm=()
  for it in "${CLAIM_ITEMS[@]}"; do
    case "$it" in
      *'|'*|*$'\n'*) printf 'loom-slots: a claim item may not contain "|": [%s]\n' "$it" >&2; exit 1 ;;
    esac
    k="$(claim_key "$it")"
    [ -n "$k" ] || { printf 'loom-slots: a claim item may not be empty\n' >&2; exit 1; }
    norm+=("$k")
  done
  CLAIM_ITEMS=("${norm[@]}")
  mkdir -p "$SLOTS_DIR" 2>/dev/null || write_fail "cannot create $SLOTS_DIR"
  f="$(loom_file "$CLAIM_SESSION")"
  take_lock "$SLOTS_DIR/.$(basename "$f").lock" || write_fail "could not take the lock on $f (held for 30s, or the directory is not writable)"
  current=""
  [ -f "$f" ] && current="$(sed -n 's/^claims=//p' "$f" | tail -1)"
  IFS=',' read -r -a existing <<< "$current"

  # Moving or dropping a claim that is not there is refused: a conductor marking an item at
  # hand-back that it never claimed must learn it was never protected.
  if [ "$MODE" != claim ]; then
    for it in "${CLAIM_ITEMS[@]}"; do
      found=0
      for c in ${existing[@]+"${existing[@]}"}; do
        [ "$(claim_key "${c%%|*}")" = "$(claim_key "$it")" ] && found=1
      done
      if [ "$found" = 0 ]; then
        printf 'loom-slots: %s is not claimed by %s — claim it first (--claim); nothing was changed\n' "$it" "$CLAIM_SESSION" >&2
        release_lock; exit 1
      fi
    done
  fi

  stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  next=""
  # Keep every existing claim except the ones this call names; then append the named ones in their
  # new state, unless that state removes them.
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
    for it in "${CLAIM_ITEMS[@]}"; do
      dup=0; case ",$next," in *",$it|"*) dup=1 ;; esac
      [ "$dup" = 1 ] || next="${next:+$next,}$it|working|$stamp"
    done
  fi
  tmp="$(mktemp "$SLOTS_DIR/.claims.XXXXXX")" || write_fail "cannot create a temporary file in $SLOTS_DIR"
  if [ -f "$f" ]; then
    awk '!/^claims=/' "$f" > "$tmp" || { rm -f "$tmp"; write_fail "cannot copy $f"; }
  else
    printf 'sessionDir=%s\n' "$CLAIM_SESSION" > "$tmp"
  fi
  printf 'claims=%s\n' "$next" >> "$tmp"
  chmod 644 "$tmp"
  [ -f "$f" ] && touch -r "$f" "$tmp"
  mv "$tmp" "$f" || { rm -f "$tmp"; write_fail "cannot replace $f"; }
  release_lock
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

want_raw=(); want_key=()
if [ -n "$DISPATCHING" ]; then
  IFS=',' read -r -a dparts <<< "$DISPATCHING"
  for w in ${dparts[@]+"${dparts[@]}"}; do
    k="$(claim_key "$w")"; [ -n "$k" ] || continue
    want_raw+=("$(trim "$w")"); want_key+=("$k")
  done
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

# Pre-pass: every row's canonical session directory and heartbeat, so two rows naming one loom are
# counted once — from the freshest — and the other is reported as a duplicate by file name.
F_PATH=(); F_CANON=(); F_HB=()
for f in "$SLOTS_DIR"/*.slots; do
  [ -f "$f" ] || continue
  v="$(sed -n 's/^sessionDir=//p' "$f" | tail -1)"
  c="file:$f"; [ -n "$v" ] && c="$(canon_session "$v")"
  F_PATH+=("$f"); F_CANON+=("$c"); F_HB+=("$(file_hb_epoch "$f")")
done
global_dupes=0
dupe_lines=""
primary_of() { # index -> index of the freshest row with the same canonical session
  local i="$1" j best="$1"
  for j in ${F_PATH[@]+"${!F_PATH[@]}"}; do
    [ "${F_CANON[$j]}" = "${F_CANON[$i]}" ] || continue
    if [ "${F_HB[$j]}" -gt "${F_HB[$best]}" ]; then best="$j"; fi
  done
  printf '%s' "$best"
}

for fi_ in ${F_PATH[@]+"${!F_PATH[@]}"}; do
  f="${F_PATH[$fi_]}"
  pi="$(primary_of "$fi_")"
  is_dupe=0; [ "$pi" != "$fi_" ] && is_dupe=1
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
  if [ "$is_dupe" = 1 ]; then
    counted=0; basis="duplicate"; observed_stale=0; stale_names=""
    global_dupes=$((global_dupes+1))
    dupe_lines="$dupe_lines$(printf '    %s duplicates %s (same session %s; counted once, from the freshest heartbeat)' "$(basename "$f")" "$(basename "${F_PATH[$pi]}")" "${F_CANON[$fi_]}")
"
  elif [ "$have_lane_files" = 1 ]; then
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
  [ "$is_dupe" = 1 ] && verdict="duplicate"

  # The newline is appended OUTSIDE the substitution: `$( )` strips trailing newlines, so building
  # a table by `rows="$rows$(printf '...\n')"` silently runs every row into the previous one.
  rows="$rows$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "$short" "${cap:-?}" "$counted" "$basis" "${loom_age}m" "$hb_src" "$verdict" "$( [ "$is_dupe" = 1 ] && printf 'of %s' "$(basename "${F_PATH[$pi]}")" || printf '%s' "${observed_names:-${liveLanes:-—}}")")
"
  # Claims are read off EVERY row, counted or not: the row that is stale with no lanes is the one
  # whose finished-but-uncommitted work a second loom is about to redo.
  if [ -n "$claims" ]; then
    is_self=0
    [ -n "$SELF" ] && [ "$(canon_session "$sessionDir")" = "$SELF" ] && is_self=1
    rowstate="fresh"; [ "$loom_fresh" = 1 ] || rowstate="stale(${loom_age}m)"
    [ "$counted" -gt 0 ] || rowstate="$rowstate,no-live-lanes"
    [ "$is_dupe" = 1 ] && rowstate="duplicate-row:$(basename "$f")"
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
        cik="$(claim_key "$ci")"
        for wi in ${want_raw[@]+"${!want_raw[@]}"}; do
          w="${want_raw[$wi]}"
          if items_overlap "${want_key[$wi]}" "$cik"; then
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
  if [ "$global_dupes" -gt 0 ]; then
    printf '  duplicate rows    : %s (one loom under two file names; remove the stale one once its claims are moved)\n' "$global_dupes"
    printf '%s' "$dupe_lines"
  fi
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
