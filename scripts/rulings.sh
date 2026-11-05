#!/bin/bash
# rulings.sh — the fleet rulings file: `engine rulings <subcommand>` (IDE-233).
#
# A ruling is a manager's decision under its grant, kept as precedent so the same question gets
# the same answer next time. Each manager writes one section file; the director writes fleet.md;
# every seat reads the sections on its own live ancestor chain. The format is the one this
# header describes: a section file opens with "# Rulings: <section>" and "owner: <seat>", then
# one block per ruling, "## <section>#<n>" followed by key: value lines; a later
# "## <section>#<n> superseded" or "## <section>#<n> withdrawn" block retires a ruling.
#
# Usage:
#   engine rulings live --seat <seat> [--unread]
#       The live rulings that bind <seat>, one per line, tab-separated:
#         section  id  at  scope  class  question  ruling  read|unread
#       fleet.md first, then each section on the seat's live ancestor chain from the top down,
#       ending with the seat's own section when it has one; oldest first within a section. A
#       superseded or withdrawn ruling is left out. On a conflict the FIRST row for a question
#       wins (the higher rung). --unread prints only the rows <seat> has not marked read.
#   engine rulings unread --seat <seat>
#       The same as live --unread.
#   engine rulings mark-read --seat <seat> [--through <section>=<n>[,<section>=<n>…]]
#       Advance <seat>'s read cursor (.reads/<seat>.tsv). With --through, to exactly the rows the
#       caller printed (what /next should pass, so a ruling written after it printed stays
#       unread), and an <n> past that section's newest ruling is refused; without it, to the
#       newest ruling now on disk in each section on the chain. A cursor never moves back.
#       Only the seat itself may run it (live fleet_self must be <seat>).
#   engine rulings write [--section <seat>|fleet]  < fields
#       Append one ruling (or a supersession, or a withdrawal) to a section the caller owns. The
#       caller is the live fleet_self; the section defaults to the caller's own. Fields on stdin,
#       one "key: value" per line:
#         question, ruling, source      required for a ruling
#         scope                         subtree (default) | fleet (fleet.md only, its default)
#         class                         A | B | C | D | orientation; then condition and reversal
#         condition, reversal, detail   optional single lines
#         supersedes: <section>#<n>     replaces ONE live ruling of the same section
#         withdraws: <section>#<n>      withdraws ONE live ruling, with a reason: line
#       A caller who does not own the section writes nothing, exits 4, and gets the proposal on
#       stdout as a ready ask for the /ask skill (spec §5): a "to:" line naming its live manager,
#       an "ask:" line, then "body:" and the body, whose first line is
#       `proposes-ruling: <section>`. A seat with no manager gets "to: none" and no ask line.
#   engine rulings init <section>
#       Create a section's two header lines, under the same ownership rules as write.
#   engine rulings verify
#       Lint: name every block whose by: seat is not its section's owner (a hand-typed write),
#       and every block the parser withholds.
#
# Exit: 0 done · 1 usage or a refused field · 2 "unknown": the tree, the rulings folder or a
#       section file cannot be read, or a helper program failed (stdout is the word "unknown",
#       never an empty or short list), or the caller's identity is only the launch-time cache ·
#       3 (live, unread) partial: a section holds a block the parser cannot read; every row
#       printed is valid, the ids that block names are withheld, stdout ends with the trailer
#       line "# partial: <withheld ids>" (or "-" when the bad heading named none), and stderr
#       names the block ·
#       4 the seat is carried by two panes, or (write, init, mark-read) the caller does not own
#       what it tried to write · 5 no pane carries the seat.
#
# Files: <fleet data dir>/rulings/ — the fleet data dir resolved as fleet.sh's get_fleet_base
#        does (user-info.sh data-root, then username, then assets/fleet). One <section>.md per
#        section, named for the seat in lower case (fleet.md for the director's); .reads/<seat>.tsv
#        each seat's cursor ("section<TAB>n", the highest n read); .lock/<section>/ the mkdir lock
#        a write holds while it appends, with an "owner" file ("<pid> <process start time>",
#        the start time read in the C locale and UTC, so holder and waiter agree whatever
#        zone or locale each runs in).
# Env:   Test seams, each honoured ONLY with FLEET_TEST_SEAM=1 (like lib.sh's FLEET_LIVE_PANES)
#        and otherwise ignored with a stderr line:
#        RULINGS_DIR — the rulings folder.
#        RULINGS_LIB — the lib.sh to source (default: beside this script).
#        RULINGS_LOCK_TRIES — lock attempts, 50 ms apart (default 400).
#
# Rules the format fixes:
#   - Append-only. A write appends one block (and its supersession marker) with one >> under the
#     section's lock and never rewrites a byte. A tab or a multi-line value is refused.
#   - A ruling is live while no "## <id> superseded" or "## <id> withdrawn" block names it.
#   - A block the parser cannot read (a bad heading, a repeated id, a ruling with no question)
#     withholds every id it names and nothing else: the section's other rulings are still served
#     (exit 3), because those ids are all the damage can reach. A section FILE that cannot be read,
#     or has no owner line, names no ids to withhold, so it is "unknown" (exit 2).
#   - On a conflict the higher rung wins: fleet.md, then the top manager, down the chain. A write
#     that repeats a live question an ancestor section already ruled prints a warning.
#   - The lock: mkdir takes it; the holder's pid and start time go in atomically. A lock is broken
#     only when its recorded holder is dead (or it has no owner file and is older than 10 s), and
#     only under a second mkdir mutex after re-reading the same owner; nothing removes a lock it
#     did not take on any other ground. The next id is read under the lock.
#   - Unread rulings are information, not obligations: nothing here touches /next's brake.
#   - Seat rename: rename the section file (and .reads/<seat>.tsv) to the new seat and change
#     its owner: line; old ids stay exactly as written, so citations of them still resolve by grep.
#   - Reserved, not built: a recall push (an `engine broadcast --subtree <owner>` naming a new id).
#
# Bash 3.2 safe (§PTF_BASH32_COMPATIBILITY): no arrays, no associative arrays, no ${v,,}.

# Guard: an imported (exported) shell function, or a BASH_ENV file, can shadow every command
# and builtin this script calls, `unset` and `builtin` included, so no line inside the script
# can undo it. Keywords and absolute paths cannot be shadowed. So when /usr/bin/env shows an
# imported function or BASH_ENV, the script runs itself again in a bash without them, and the
# body below runs only in such a bash. (Where /usr/bin/env, /usr/bin/grep or /usr/bin/sed is
# missing the check cannot run, and the body runs unguarded.)
# It relaunches at most once. /usr/bin/env prints a multi-line value one line per line, so a
# value holding a line that starts BASH_FUNC_ or BASH_ENV= matches the check, and env -u cannot
# remove a variable that does not exist. The relaunch therefore sets RULINGS_GUARD_RAN=1, and a
# bash that still matches with the marker set refuses with exit 2 ("unknown") instead of
# relaunching again. The relaunch is a child rather than `exec`, because `exec` is a builtin an
# imported function can shadow; the script's status is the child's, since nothing follows the
# if/else. The body unsets the marker, so a script it runs gets its own one relaunch.
if /usr/bin/env | /usr/bin/grep -Eq '^(BASH_FUNC_|BASH_ENV=)'; then
  case "${RULINGS_GUARD_RAN:-}" in
    1) /usr/bin/printf '%s\n' "rulings: the environment still shows an imported function or BASH_ENV after one clean relaunch (a variable's value may hold a line starting BASH_FUNC_ or BASH_ENV=); refusing" >&2
       /usr/bin/printf 'unknown\n'
       /usr/bin/env -i /bin/sh -c 'exit 2' ;;
    *) /usr/bin/env -u BASH_ENV $(/usr/bin/env | /usr/bin/sed -n 's/^\(BASH_FUNC_[^=]*\)=.*/-u \1/p') RULINGS_GUARD_RAN=1 "$BASH" "${BASH_SOURCE[0]}" "$@" ;;
  esac
else
unset RULINGS_GUARD_RAN

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULINGS_LIB_FILE="$SCRIPT_DIR/lib.sh"
if [ -n "${RULINGS_LIB:-}" ]; then
  if [ "${FLEET_TEST_SEAM:-}" = 1 ]; then
    RULINGS_LIB_FILE="$RULINGS_LIB"
  else
    echo "rulings: ignoring a test seam (RULINGS_LIB) because FLEET_TEST_SEAM=1 is not set; loading $SCRIPT_DIR/lib.sh" >&2
  fi
fi
unset RULINGS_LIB
# An inherited _LIB_SH_LOADED would make lib.sh return before defining anything (exit 127 on the
# first fleet_* call), so it is dropped before the source.
unset _LIB_SH_LOADED
# shellcheck source=/dev/null
source "$RULINGS_LIB_FILE" || { echo "rulings: cannot load $RULINGS_LIB_FILE" >&2; echo unknown; exit 2; }
export FLEET_WARN_PREFIX=rulings

# A stub tree is honoured only with the marker. lib.sh's fleet_self reads FLEET_LIVE_PANES
# without that check, so the seam is dropped here, once, for every fleet_* call below.
if [ -n "${FLEET_LIVE_PANES:-}" ] && ! _fleet_test_seam "$FLEET_LIVE_PANES" FLEET_LIVE_PANES; then
  unset FLEET_LIVE_PANES
fi

LOCK_TRIES=400
if [ -n "${RULINGS_LOCK_TRIES:-}" ]; then
  if [ "${FLEET_TEST_SEAM:-}" = 1 ]; then LOCK_TRIES="$RULINGS_LOCK_TRIES"
  else echo "rulings: ignoring a test seam (RULINGS_LOCK_TRIES) because FLEET_TEST_SEAM=1 is not set" >&2; fi
fi

TAB=$(printf '\t')
NL='
'
lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
die() { echo "rulings: $2" >&2; exit "$1"; }
unknown() { echo "rulings: $1" >&2; echo unknown; exit 2; }
usage() { sed -n '/^# Usage:/,/^# Exit:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 1; }

# rulings_dir — the rulings folder on stdout; exit 2 when it cannot be resolved.
rulings_dir() {
  local ui="" root="" user=""
  if [ -n "${RULINGS_DIR:-}" ]; then
    if [ "${FLEET_TEST_SEAM:-}" = 1 ]; then printf '%s\n' "$RULINGS_DIR"; return 0; fi
    echo "rulings: ignoring a test seam (RULINGS_DIR) because FLEET_TEST_SEAM=1 is not set; using the fleet data dir" >&2
  fi
  ui="$SCRIPT_DIR/user-info.sh"
  [ -x "$ui" ] || ui="$HOME/.claude/scripts/user-info.sh"
  root=$("$ui" data-root 2>/dev/null) || root=""
  user=$("$ui" username 2>/dev/null) || user=""
  if [ -z "$root" ] || [ -z "$user" ] || [ "$user" = unknown ]; then
    echo "rulings: cannot resolve the fleet data dir (user-info.sh data-root / username)" >&2
    return 2
  fi
  printf '%s\n' "$root/$user/assets/fleet/rulings"
}

# valid_section <name> — "fleet", or one window:label in lower case. Anchored with case, so a
# value holding a newline or a slash never passes.
valid_section() {
  case "$1" in fleet) return 0 ;; ""|*[!a-z0-9._:-]*) return 1 ;; esac
  case "$1" in *:*:*|:*|*:) return 1 ;; *:*) return 0 ;; esac
  return 1
}

# valid_id <section> <id> — exactly "<section>#<n>", n a positive integer with no leading zero.
valid_id() {
  local n="${2#"$1#"}"
  [ "$n" != "$2" ] || return 1
  case "$n" in ""|0*|*[!0-9]*) return 1 ;; esac
  return 0
}

# section_read <file> <section> <mode> [id] — the one parser of a section file.
#   mode live    "id<TAB>at<TAB>scope<TAB>class<TAB>question<TAB>ruling<TAB>n" per live ruling,
#                plus "BAD<TAB><what>" per block it cannot read
#   mode owner   the owner: line's value
#   mode maxn    the highest n any heading names (0 when none) — a bad heading's ids included,
#                so no id is ever handed out twice
#   mode status  live | superseded | withdrawn | withheld | absent, for [id]
#   mode verify  "id<TAB>by" per block whose by: seat is not the owner, and the BAD lines
# A block it cannot read (a heading not "<section>#<n>[ superseded|withdrawn]", a ruling id
# that appears twice, a ruling with no question or ruling, a line holding a tab or a carriage
# return, which would shift the reader's tab-separated columns) WITHHOLDS every id it names:
# none of them is live. exit 3 ("ERR <why>") only for a file with no owner line; any other
# non-zero is awk itself failing, which every caller reads as unknown.
section_read() {
  awk -v sec="$2" -v mode="$3" -v want="${4:-}" '
    function ids_in(h, out,   p, r, d, c, cnt) {   # every "<sec>#<digits>" token in h
      cnt = 0; r = h
      while ((p = index(r, sec "#")) > 0) {
        r = substr(r, p + length(sec) + 1); d = ""
        while (length(r) > 0) { c = substr(r, 1, 1); if (c !~ /[0-9]/) break; d = d c; r = substr(r, 2) }
        if (d != "") { cnt++; out[cnt] = d + 0 }
      }
      return cnt
    }
    function withhold(id, why) { held[id] = 1; nbad++; badl[nbad] = why }
    function flush() {
      if (cur == "") return
      if (ctl) { withhold(cur, "block " cur (kind == "r" ? "" : " " kind) " holds a tab or a carriage return"); cur = ""; return }
      if (kind == "r") {
        if (cur in N) withhold(cur, "ruling id " cur " appears twice")
        else if (q == "" || ru == "") withhold(cur, "block " cur " has no question or ruling")
        else { nid++; ids[nid] = cur; A[cur] = at; S[cur] = sc; C[cur] = cl; Q[cur] = q; R[cur] = ru; B[cur] = by }
        N[cur] = num
      } else { if (!(cur in dead)) dead[cur] = kind; nm++; MID[nm] = cur; MK[nm] = kind; MBY[nm] = by }
      cur = ""
    }
    BEGIN { tb = sprintf("%c", 9); cr = sprintf("%c", 13) }
    NR <= 3 && /^owner: / { owner = substr($0, 8); next }
    /^## / {
      flush()
      h = substr($0, 4); kind = "r"
      k = ids_in(h, tok); for (i = 1; i <= k; i++) if (tok[i] > maxn) maxn = tok[i]
      if (h ~ / superseded$/) { kind = "superseded"; sub(/ superseded$/, "", h) }
      else if (h ~ / withdrawn$/) { kind = "withdrawn"; sub(/ withdrawn$/, "", h) }
      if (index(h, sec "#") != 1 || substr(h, length(sec) + 2) !~ /^[1-9][0-9]*$/) {
        for (i = 1; i <= k; i++) held[sec "#" tok[i]] = 1
        nbad++; badl[nbad] = "unreadable heading \"" $0 "\" (withholds" (k ? "" : " nothing")
        for (i = 1; i <= k; i++) badl[nbad] = badl[nbad] " " sec "#" tok[i]
        badl[nbad] = badl[nbad] ")"
        next
      }
      cur = h; num = substr(h, length(sec) + 2) + 0
      at = ""; sc = ""; cl = ""; q = ""; ru = ""; by = ""; ctl = 0
      next
    }
    cur != "" && (index($0, tb) || index($0, cr)) { ctl = 1; next }
    cur != "" && /^[a-z-]+: / {
      key = $0; sub(/: .*/, "", key); v = substr($0, length(key) + 3)
      if (key == "at") at = v; else if (key == "scope") sc = v; else if (key == "class") cl = v
      else if (key == "question") q = v; else if (key == "ruling") ru = v; else if (key == "by") by = v
    }
    END {
      flush()
      if (owner == "") { print "ERR no owner: line"; exit 3 }
      if (mode == "owner") { print owner; exit 0 }
      if (mode == "maxn") { print maxn + 0; exit 0 }
      if (mode == "status") {
        if (want in held) print "withheld"; else if (want in dead) print dead[want]
        else if (want in N) print "live"; else print "absent"
        exit 0
      }
      for (i = 1; i <= nid; i++) {
        id = ids[i]
        if (id in held) continue
        if (mode == "live" && !(id in dead))
          print id "\t" A[id] "\t" S[id] "\t" (C[id] == "" ? "-" : C[id]) "\t" Q[id] "\t" R[id] "\t" N[id]
        if (mode == "verify") { split(B[id], w, " "); if (tolower(w[1]) != tolower(owner)) print id "\t" B[id] }
      }
      if (mode == "verify") for (j = 1; j <= nm; j++) {
        split(MBY[j], w, " ")
        if (MBY[j] == "") print MID[j] " " MK[j] "\t(no by: line)"
        else if (tolower(w[1]) != tolower(owner)) print MID[j] " " MK[j] "\t" MBY[j]
      }
      for (i = 1; i <= nbad; i++) print "BAD\t" badl[i]
      if (mode == "live") for (id in held) print "HELD\t" id
    }' "$1"
}

# chain_of <seat> — sets CHAIN (lines "<seat> <pane>", top down) or exits with the chain's code.
chain_of() {
  local rc=0
  CHAIN=$(fleet_live_chain "$1") || rc=$?
  if [ "$rc" != 0 ] || [ -z "$CHAIN" ]; then echo unknown; exit "$([ "$rc" = 0 ] && echo 2 || echo "$rc")"; fi
}

# rows_for <seat> — the reader: sets ROWS ("section<TAB>" + section_read's live row), SECTIONS
# (the sections read, in order), SEAT, DIR, and PARTIAL=1 when a block was withheld.
rows_for() {
  local seat="$1" dir="" s="" f="" out="" rc=0 st="" pn="" last="" bad="" rows=""
  chain_of "$seat"
  last="${CHAIN##*"$NL"}"
  SEAT="${last%% *}"
  [ -n "$SEAT" ] && [ "$SEAT" != "$last" ] || unknown "the chain for '$seat' is malformed"
  dir=$(rulings_dir) || unknown "the rulings folder cannot be resolved"
  [ -d "$dir" ] && [ -r "$dir" ] && [ -x "$dir" ] || unknown "the rulings folder cannot be read: $dir"
  DIR="$dir"
  SECTIONS="fleet"
  while read -r st pn; do
    [ -n "$st" ] || continue
    s=$(lc "$st") || unknown "cannot fold '$st'"
    valid_section "$s" || unknown "the chain names '$st', which is not a seat name a section can carry"
    case " $SECTIONS " in *" $s "*) ;; *) SECTIONS="$SECTIONS $s" ;; esac
  done <<EOF
$CHAIN
EOF
  ROWS=""
  PARTIAL=0
  HELD=""
  for s in $SECTIONS; do
    f="$dir/$s.md"
    [ -e "$f" ] || continue
    [ -r "$f" ] || unknown "section $s cannot be read: $f"
    rc=0
    out=$(section_read "$f" "$s" live) || rc=$?
    [ "$rc" = 0 ] || unknown "section $s cannot be read: ${out#ERR }"
    rows=""; bad=""
    while IFS= read -r line; do
      case "$line" in
        "") ;;
        "BAD$TAB"*) bad="$bad${line#BAD"$TAB"}; " ;;
        "HELD$TAB"*) HELD="$HELD ${line#HELD"$TAB"}" ;;
        *) rows="$rows$s$TAB$line$NL" ;;
      esac
    done <<EOF
$out
EOF
    if [ -n "$bad" ]; then
      PARTIAL=1
      echo "rulings: section $s: ${bad%; } — those ids are withheld; the section's other rulings are listed" >&2
    fi
    ROWS="$ROWS$rows"
  done
}

cursor_file() { printf '%s/.reads/%s.tsv\n' "$DIR" "$(lc "$SEAT")"; }

# emit_rows <filter: all|unread> — ROWS with the read state from the seat's cursor. The cursor
# is read as awk's first file, told apart by FILENAME (BSD awk refuses a newline in a -v value,
# and FNR==NR misfires on an empty cursor). A failed awk is "unknown", never a short list.
emit_rows() {
  local cf="" src="/dev/null" out="" rc=0
  cf=$(cursor_file)
  if [ -e "$cf" ]; then
    [ -r "$cf" ] || unknown "the read cursor cannot be read: $cf"
    src="$cf"
  fi
  out=$(printf '%s' "$ROWS" | awk -F'\t' -v OFS='\t' -v only="$1" -v cf="$src" '
    FILENAME == cf { if ($1 != "") seen[$1] = $2 + 0; next }
    NF >= 8 {
      st = (($1 in seen) && $8 + 0 <= seen[$1]) ? "read" : "unread"
      if (only == "unread" && st == "read") next
      print $1, $2, $3, $4, $5, $6, $7, st
    }
    END { print "END" }' "$src" -) || rc=$?
  if [ "$rc" != 0 ] || { [ "$out" != END ] && [ "${out##*"$NL"}" != END ]; }; then
    unknown "the rows could not be assembled (awk exit $rc)"
  fi
  out="${out%END}"
  [ -n "$out" ] && printf '%s' "$out"
  return 0
}

SEAT_ARG=""
ONLY=all
THROUGH=""
seat_arg() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --seat) SEAT_ARG="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
      --unread) ONLY=unread; shift ;;
      --through) THROUGH="${2:-}"; [ -n "$THROUGH" ] || usage; shift; [ $# -gt 0 ] && shift ;;
      *) echo "rulings: unknown argument $1" >&2; usage ;;
    esac
  done
  [ -n "$SEAT_ARG" ] || usage
}

cmd_live() {
  local out="" rc=0
  seat_arg "$@"
  rows_for "$SEAT_ARG"
  out=$(emit_rows "$ONLY") || rc=$?
  [ "$rc" = 0 ] || { echo unknown; exit "$rc"; }
  [ -n "$out" ] && printf '%s\n' "$out"
  if [ "$PARTIAL" = 1 ]; then
    # The trailer: a consumer reading stdout alone still sees that the list is not whole.
    printf '# partial: %s\n' "$(printf '%s\n' $HELD | sort -u | tr '\n' ' ' | sed 's/ $//;s/^$/-/')"
    exit 3
  fi
  exit 0
}

# live_self — sets SELF from the live pane; the launch-time cache alone is refused.
live_self() {
  local rc=0
  SELF=$(fleet_self) || rc=$?
  case "$rc" in
    0) ;;
    3) echo unknown; die 2 "refused: this seat's identity is only the launch-time FLEET_PANE cache; a write needs the live pane" ;;
    *) echo unknown; die 2 "refused: this seat's identity cannot be read" ;;
  esac
}

cmd_mark_read() {
  local cf="" s="" m="" tmp="" old="" new="" rc=0 pair="" want="" top=""
  seat_arg "$@"
  live_self
  rows_for "$SEAT_ARG"
  [ "$(lc "$SELF")" = "$(lc "$SEAT")" ] || die 4 "refused: '$SELF' may advance only its own read cursor, not '$SEAT's"
  if [ -n "$THROUGH" ]; then
    for pair in $(printf '%s' "$THROUGH" | tr ',' ' '); do
      s="${pair%%=*}"; m="${pair#*=}"
      valid_section "$s" && [ "$s" != "$pair" ] || die 1 "refused: --through takes <section>=<n>, not '$pair'"
      case "$m" in ""|*[!0-9]*) die 1 "refused: --through takes <section>=<n>, not '$pair'" ;; esac
      case " $SECTIONS " in *" $s "*) ;; *) die 1 "refused: $s is not on $SEAT's chain" ;; esac
      want="$want$s=$m "
    done
  fi
  cf=$(cursor_file)
  mkdir -p "$DIR/.reads" || unknown "cannot create $DIR/.reads"
  old=""
  [ -e "$cf" ] && { old=$(cat "$cf") || unknown "the read cursor cannot be read: $cf"; }
  new="$old"
  for s in $SECTIONS; do
    if [ -n "$THROUGH" ]; then
      m=""
      for pair in $want; do [ "${pair%%=*}" = "$s" ] && m="${pair#*=}"; done
      [ -n "$m" ] || continue
      # A cursor past the newest id would mark rulings not yet written as read.
      top=0
      if [ -e "$DIR/$s.md" ]; then
        rc=0
        top=$(section_read "$DIR/$s.md" "$s" maxn) || rc=$?
        [ "$rc" = 0 ] || unknown "section $s cannot be read: ${top#ERR }"
      fi
      case "$m" in 0*) m=$(printf '%s' "$m" | sed 's/^0*//'); m="${m:-0}" ;; esac
      [ "${#m}" -le 9 ] && [ "$m" -le "$top" ] || die 1 "refused: --through $s=$m is past the newest ruling in $s ($s#$top)"
    else
      [ -e "$DIR/$s.md" ] || continue
      rc=0
      m=$(section_read "$DIR/$s.md" "$s" maxn) || rc=$?
      [ "$rc" = 0 ] || unknown "section $s cannot be read: ${m#ERR }"
    fi
    rc=0
    new=$(printf '%s\n' "$new" | awk -F'\t' -v OFS='\t' -v s="$s" -v m="$m" '
      $1 == s { if ($2 + 0 > m + 0) m = $2; next } NF { print } END { print s, m + 0 }') || rc=$?
    [ "$rc" = 0 ] || unknown "the cursor could not be computed (awk exit $rc)"
  done
  tmp="$cf.tmp.$$"
  { printf '%s\n' "$new" | awk 'NF' > "$tmp" && mv "$tmp" "$cf"; } || { rm -f "$tmp"; unknown "cannot write $cf"; }
  while IFS="$TAB" read -r s m; do [ -n "$s" ] && echo "marked $s $m"; done < "$cf"
  exit 0
}

# ---------------------------------------------------------------- the lock

LOCKD=""
TOKEN=""
proc_start() { LC_ALL=C LANG=C TZ=UTC0 ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //;s/ $//'; }
# holder_state <owner content> — alive | dead | unsure. A pid that answers kill -0 but whose
# start time ps cannot read is UNSURE, never dead: a lock is not broken on "cannot tell".
holder_state() {
  local pid="${1%% *}" st="${1#* }" now=""
  case "$pid" in ""|*[!0-9]*) echo dead; return 0 ;; esac
  kill -0 "$pid" 2>/dev/null || { echo dead; return 0; }
  now=$(proc_start "$pid")
  if [ -z "$now" ]; then echo unsure; elif [ "$now" = "$st" ]; then echo alive; else echo dead; fi
}
age_of() {   # seconds since $1's mtime; exit 1 when it is gone
  local m=""
  m=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null) || return 1
  [ -n "$m" ] || return 1
  echo $(( $(date +%s) - m ))
}
release_lock() {
  [ -n "$LOCKD" ] || return 0
  [ "$(cat "$LOCKD/owner" 2>/dev/null)" = "$TOKEN" ] && rm -rf "$LOCKD"
  LOCKD=""
}
# maybe_break — break $LOCKD only when its holder is provably gone, re-checked under a mutex.
#   dead holder: after 1 s · no owner file: after 10 s · unsure holder (ps cannot read it):
#   only after UNSURE_AGE s, far longer than any write holds the lock.
UNSURE_AGE=600
stale_enough() {   # <owner content> <age>
  local state=""
  if [ -z "$1" ]; then [ "$2" -ge 10 ]; return; fi
  state=$(holder_state "$1")
  case "$state" in
    dead) [ "$2" -ge 1 ] ;;
    unsure) [ "$2" -ge "$UNSURE_AGE" ] ;;
    *) return 1 ;;
  esac
}
maybe_break() {
  local own="" own2="" age="" brk="$LOCKD.break" bage=""
  own=$(cat "$LOCKD/owner" 2>/dev/null) || own=""
  age=$(age_of "$LOCKD") || return 0
  stale_enough "$own" "$age" || return 0
  if ! mkdir "$brk" 2>/dev/null; then
    bage=$(age_of "$brk") && [ "$bage" -ge 30 ] && rmdir "$brk" 2>/dev/null
    return 0
  fi
  own2=$(cat "$LOCKD/owner" 2>/dev/null) || own2=""
  age=$(age_of "$LOCKD") || age=0
  if [ "$own2" = "$own" ] && stale_enough "$own2" "$age"; then
    echo "rulings: breaking a stale lock on $(basename "$LOCKD") (holder: ${own2:-none recorded}, ${age}s old)" >&2
    rm -rf "$LOCKD"
  fi
  rmdir "$brk" 2>/dev/null
  return 0
}
take_lock() {
  local sec="$1" tries=0 st=""
  mkdir -p "$DIR/.lock" || unknown "cannot create $DIR/.lock"
  st=$(proc_start "$$")
  [ -n "$st" ] || unknown "cannot read this process's start time for the lock"
  TOKEN="$$ $st"
  LOCKD="$DIR/.lock/$sec"
  while :; do
    if mkdir "$LOCKD" 2>/dev/null; then
      trap release_lock EXIT
      trap 'exit 130' INT TERM
      { printf '%s\n' "$TOKEN" > "$LOCKD/owner.tmp.$$" && mv "$LOCKD/owner.tmp.$$" "$LOCKD/owner"; } \
        || unknown "cannot record the lock's holder in $LOCKD"
      return 0
    fi
    maybe_break
    tries=$((tries + 1))
    if [ "$tries" -gt "$LOCK_TRIES" ]; then
      LOCKD=""
      unknown "section $sec is locked by $(cat "$DIR/.lock/$sec/owner" 2>/dev/null || echo 'another writer'); try again"
    fi
    sleep 0.05
  done
}

# ---------------------------------------------------------------- write / init

# resolve_self — SELF, SELFPANE, PARENT ("-" for none) from the one pane carrying this seat.
# A parent with no pane does not stop this: a worker under a restarting manager can still be
# refused and handed its proposal.
resolve_self() {
  local row="" rc=0 rest=""
  live_self
  row=$(fleet_live_seat "$SELF") || rc=$?
  [ "$rc" = 0 ] || { echo unknown; exit "$rc"; }
  SELF="${row%% *}"; rest="${row#* }"; SELFPANE="${rest%% *}"; PARENT="${rest#* }"
  [ -n "$SELF" ] && [ -n "$SELFPANE" ] && [ -n "$PARENT" ] || unknown "cannot read this seat's row in the live tree"
}

# owner_check <section> — sets OWNS=1 when SELF owns <section> (or may create it), else 0.
owner_check() {
  local sec="$1" f="$DIR/$1.md" owner="" kids="" rc=0 tree="" roots=""
  OWNS=0
  if [ -e "$f" ]; then
    [ -r "$f" ] || unknown "section $sec cannot be read: $f"
    owner=$(section_read "$f" "$sec" owner) || unknown "section $sec cannot be read: ${owner#ERR }"
    [ "$(lc "$owner")" = "$(lc "$SELF")" ] && OWNS=1
    OWNER="$owner"
    return 0
  fi
  OWNER="(no section yet)"
  # A new section only for a seat that manages someone; fleet.md only for the ONE root that does.
  if [ "$sec" = fleet ]; then
    [ "$PARENT" = "-" ] || return 0
    tree=$(fleet_live_tree) || unknown "the live tree cannot be read"
    roots=$(printf '%s\n' "$tree" | awk '
      NF >= 2 { k = tolower($1); p = (NF >= 3 ? tolower($3) : "-"); if (p == "-") root[k] = 1; else kid[p] = 1 }
      END { c = 0; for (k in root) if (k in kid) c++; print c; print "END" }') || unknown "the tree's roots could not be counted"
    [ "${roots##*"$NL"}" = END ] || unknown "the tree's roots could not be counted"
    if [ "${roots%%"$NL"*}" != 1 ]; then
      echo "rulings: ${roots%%"$NL"*} top-of-tree seats manage someone, so none of them may create fleet.md" >&2
      OWNER="(no section yet; the top of the tree is ambiguous)"
      return 0
    fi
  else
    [ "$sec" = "$(lc "$SELF")" ] || return 0
  fi
  kids=$(fleet_live_children "$SELF" 2>/dev/null) || rc=$?
  [ "$rc" = 0 ] || unknown "cannot tell whether '$SELF' manages anyone (fleet_live_children exit $rc); refusing rather than guessing"
  [ -n "$kids" ] && OWNS=1
  return 0
}

ensure_header() {
  local f="$DIR/$1.md"
  [ -e "$f" ] && return 0
  printf '%s\n' "# Rulings: $1" "owner: $(lc "$SELF")" > "$f" || unknown "cannot create $f"
}

# The fields, read by the parse loop in cmd_write (no awk: a failed helper cannot drop one).
F_scope=""; F_class=""; F_question=""; F_ruling=""; F_condition=""; F_reversal=""
F_source=""; F_detail=""; F_supersedes=""; F_withdraws=""; F_reason=""

propose() {
  local psec="$1" k="" v=""
  echo "rulings: refused: '$SELF' does not own section '$2' (owner: $OWNER); nothing was written. Send the proposal below with the ask skill." >&2
  echo "proposal: nothing was written"
  if [ "$PARENT" = "-" ]; then
    echo "rulings: '$SELF' has no manager above it, so there is no one to propose to; raise it with the operator directly" >&2
    echo "to: none"
  else
    echo "to: $PARENT"
    echo "ask: Skill(ask, \"${F_question:-$F_withdraws} (proposes a ruling for $psec) --to $PARENT\")"
  fi
  echo "body:"
  echo "proposes-ruling: $psec"
  printf '%s' "$FIELDS"
  exit 4
}

cmd_write() {
  local sec="" input="" line="" k="" v="" keys="" scope="" f="" n="" at="" by="" block="" st=""
  local psec="" rc=0 a="" out="" id=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --section) sec=$(lc "${2:-}"); shift; [ $# -gt 0 ] && shift ;;
      *) echo "rulings: unknown argument $1" >&2; usage ;;
    esac
  done
  [ -t 0 ] && die 1 "write takes its fields on stdin (key: value lines)"
  input=$(cat)
  case "$input" in *"$TAB"*) die 1 "refused: a field holds a tab; values are single lines without tabs" ;; esac
  case "$input" in *$'\r'*) die 1 "refused: a field holds a carriage return" ;; esac
  FIELDS=""
  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    case "$line" in
      [a-z]*": "*) k="${line%%: *}"; v="${line#*: }" ;;
      *) die 1 "refused: '$line' is not a key: value line (a value may not span lines)" ;;
    esac
    case " $keys " in *" $k "*) die 1 "refused: field '$k' given twice" ;; esac
    keys="$keys $k"
    case "$k" in
      scope) F_scope="$v" ;; class) F_class="$v" ;; question) F_question="$v" ;; ruling) F_ruling="$v" ;;
      condition) F_condition="$v" ;; reversal) F_reversal="$v" ;; source) F_source="$v" ;;
      detail) F_detail="$v" ;; supersedes) F_supersedes="$v" ;; withdraws) F_withdraws="$v" ;;
      reason) F_reason="$v" ;;
      *) die 1 "refused: unknown field '$k'" ;;
    esac
    FIELDS="$FIELDS$line$NL"
  done <<EOF
$input
EOF

  resolve_self
  by="$SELF $SELFPANE"
  [ -n "$sec" ] || sec=$(lc "$SELF")
  valid_section "$sec" || die 1 "refused: '$sec' is not a section name (a seat window:label, or fleet)"
  DIR=$(rulings_dir) || unknown "the rulings folder cannot be resolved"

  # supersedes/withdraws name exactly one id of this section: no spaces, no second id, no glob.
  for a in supersedes withdraws; do
    [ "$a" = supersedes ] && id="$F_supersedes" || id="$F_withdraws"
    [ -n "$id" ] || continue
    valid_id "$sec" "$id" || die 1 "refused: $a must be exactly one id of $sec, like $sec#3, not '$id'"
  done
  if [ -n "$F_withdraws" ]; then
    [ -n "$F_reason" ] || die 1 "refused: withdraws needs a reason: line"
    [ -z "$F_question$F_ruling$F_supersedes$F_source$F_detail$F_scope$F_class$F_condition$F_reversal" ] \
      || die 1 "refused: a withdrawal carries withdraws and reason only"
  else
    [ -n "$F_question" ] && [ -n "$F_ruling" ] && [ -n "$F_source" ] || die 1 "refused: question, ruling and source are required"
    [ -z "$F_reason" ] || die 1 "refused: reason: belongs to a withdrawal (withdraws:), not to a ruling"
    scope="$F_scope"
    [ -n "$scope" ] || { [ "$sec" = fleet ] && scope=fleet || scope=subtree; }
    case "$scope" in
      subtree) ;;
      fleet) [ "$sec" = fleet ] || die 1 "refused: scope fleet is legal only in fleet.md" ;;
      *) die 1 "refused: scope '$scope' (only subtree, or fleet in fleet.md)" ;;
    esac
    if [ -n "$F_class" ]; then
      case "$F_class" in A|B|C|D|orientation) ;; *) die 1 "refused: class '$F_class' (A-D or orientation)" ;; esac
      [ -n "$F_condition" ] && [ -n "$F_reversal" ] || die 1 "refused: a classed ruling needs condition and reversal"
    fi
  fi

  [ -d "$DIR" ] || mkdir -p "$DIR" 2>/dev/null || unknown "the rulings folder cannot be created: $DIR"
  owner_check "$sec"
  if [ "$OWNS" != 1 ]; then
    psec="$sec"
    if [ "$sec" = "$(lc "$SELF")" ]; then
      if [ "$PARENT" = "-" ]; then psec=fleet; else psec=$(lc "$PARENT"); fi
    fi
    propose "$psec" "$sec"
  fi

  # Q1: the higher rung wins; say so when a live ancestor ruling already holds this question.
  if [ -z "$F_withdraws" ] && [ "$sec" != fleet ]; then
    rc=0; CHAIN=$(fleet_live_chain "$SELF" 2>/dev/null) || rc=$?
    if [ "$rc" != 0 ]; then
      echo "rulings: warning: this seat's chain cannot be read, so ancestor rulings on this question were not checked" >&2
    else
      for a in fleet $(printf '%s\n' "$CHAIN" | awk -v s="$sec" 'tolower($1) == s { exit } { print tolower($1) }'); do
        [ -r "$DIR/$a.md" ] || continue
        out=$(section_read "$DIR/$a.md" "$a" live 2>/dev/null) || continue
        printf '%s\n' "$out" | awk -F'\t' -v q="$F_question" '
          function norm(x) { x = tolower(x); gsub(/[ \t]+/, " ", x); sub(/^ /, "", x); sub(/ $/, "", x); return x }
          $1 != "BAD" && NF >= 6 && norm($5) == norm(q) { print $1 }' | while IFS= read -r id; do
            echo "rulings: warning: $id, in an ancestor section, already rules this question; on a conflict the higher rung wins" >&2
          done
      done
    fi
  fi

  take_lock "$sec"
  # Re-check ownership under the lock: two creators racing must not both pass.
  owner_check "$sec"
  [ "$OWNS" = 1 ] || die 4 "refused: '$SELF' no longer owns section '$sec' (owner: $OWNER); nothing was written"
  ensure_header "$sec"
  f="$DIR/$sec.md"
  for a in "$F_supersedes" "$F_withdraws"; do
    [ -n "$a" ] || continue
    st=$(section_read "$f" "$sec" status "$a") || unknown "section $sec cannot be read: ${st#ERR }"
    [ "$st" = live ] || die 1 "refused: $a is $st in $sec; only a live ruling of this section can be replaced or withdrawn"
  done
  n=$(section_read "$f" "$sec" maxn) || unknown "section $sec cannot be read: ${n#ERR }"
  case "$n" in ""|*[!0-9]*) unknown "section $sec: cannot read its last id" ;; esac
  at=$(date -u +%Y-%m-%dT%H:%M:%SZ) || unknown "cannot read the clock"
  if [ -n "$F_withdraws" ]; then
    block="$NL## $F_withdraws withdrawn${NL}at: $at${NL}by: $by${NL}reason: $F_reason"
    printf '%s\n' "$block" >> "$f" || unknown "cannot append to $f"
    echo "$F_withdraws withdrawn"
    exit 0
  fi
  n=$((n + 1))
  block="$NL## $sec#$n${NL}at: $at${NL}by: $by${NL}scope: $scope"
  [ -n "$F_class" ] && block="$block${NL}class: $F_class"
  block="$block${NL}question: $F_question${NL}ruling: $F_ruling"
  [ -n "$F_detail" ] && block="$block${NL}detail: $F_detail"
  [ -n "$F_condition" ] && block="$block${NL}condition: $F_condition"
  [ -n "$F_reversal" ] && block="$block${NL}reversal: $F_reversal"
  block="$block${NL}source: $F_source"
  if [ -n "$F_supersedes" ]; then
    block="$block${NL}supersedes: $F_supersedes${NL}${NL}## $F_supersedes superseded${NL}at: $at${NL}by: $by${NL}superseded-by: $sec#$n"
  fi
  printf '%s\n' "$block" >> "$f" || unknown "cannot append to $f"
  echo "$sec#$n"
  exit 0
}

cmd_init() {
  local sec=""
  [ $# -eq 1 ] || usage
  sec=$(lc "$1")
  valid_section "$sec" || die 1 "refused: '$sec' is not a section name"
  resolve_self
  DIR=$(rulings_dir) || unknown "the rulings folder cannot be resolved"
  [ -d "$DIR" ] || mkdir -p "$DIR" 2>/dev/null || unknown "the rulings folder cannot be created: $DIR"
  owner_check "$sec"
  [ "$OWNS" = 1 ] || die 4 "refused: '$SELF' does not own section '$sec' (owner: $OWNER)"
  take_lock "$sec"
  owner_check "$sec"
  [ "$OWNS" = 1 ] || die 4 "refused: '$SELF' does not own section '$sec' (owner: $OWNER)"
  ensure_header "$sec"
  echo "$DIR/$sec.md"
  exit 0
}

cmd_verify() {
  local f="" s="" out="" bad=0 rc=0 line=""
  DIR=$(rulings_dir) || unknown "the rulings folder cannot be resolved"
  [ -d "$DIR" ] && [ -r "$DIR" ] || unknown "the rulings folder cannot be read: $DIR"
  for f in "$DIR"/*.md; do
    [ -e "$f" ] || continue
    s=$(basename "$f" .md); rc=0
    out=$(section_read "$f" "$s" verify) || rc=$?
    [ "$rc" = 0 ] || { echo "MALFORMED $s ${out#ERR }"; bad=1; continue; }
    while IFS= read -r line; do
      case "$line" in
        "") ;;
        "BAD$TAB"*) echo "MALFORMED $s ${line#BAD"$TAB"}"; bad=1 ;;
        *) echo "NOT-OWNER $s $line"; bad=1 ;;
      esac
    done <<EOF
$out
EOF
  done
  exit "$bad"
}

sub="${1:-}"
[ $# -gt 0 ] && shift
case "$sub" in
  live) cmd_live "$@" ;;
  unread) ONLY=unread; cmd_live "$@" ;;
  mark-read) cmd_mark_read "$@" ;;
  write) cmd_write "$@" ;;
  init) cmd_init "$@" ;;
  verify) cmd_verify "$@" ;;
  ""|-h|--help|help) usage ;;
  *) echo "rulings: unknown subcommand '$sub'" >&2; usage ;;
esac

fi
