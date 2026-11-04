#!/bin/bash
# lease.sh — the landing lease (v2): a short, self-expiring lease on a trunk, held for one PUSH.
#
# Usage:
#   engine lease show [--repo R] [--branch B]
#   engine lease take <seat> [--repo R] [--branch B] [--what "one line"] [--queue]
#                                  --queue: if refused, join R/B's waiting list (as `wait` does)
#   engine lease wait <seat> --repo R --branch B [--what "one line"]
#                                  join R/B's FIFO waiting list (a second wait keeps the first place); prints the
#                                  position. When the lease frees, the head of the list has a short turn (120 s,
#                                  LANDING_LEASE_GRACE) in which only it may take; it takes with `take`, as before
#   engine lease leave <seat> --repo R --branch B
#                                  leave R/B's waiting list (a head that leaves passes its turn on at once)
#   engine lease release <seat> [--repo R] [--branch B]
#   engine lease check <seat> [--repo R] [--branch B]
#                                  who holds R's B now? 0 with "lease: free" on stdout (nobody holds a live lease
#                                  that covers it) or "lease: held by …, so <seat> may push" (<seat> does); 3 when
#                                  another seat holds one (the holder and its time left go to stderr). Exit 0 is
#                                  not a permit: only the "held by" line means <seat> holds the lease, and a push
#                                  needs that (core:ops/leasegate-holder). A lease covers R/B when its repo= is
#                                  empty or R, and its branch= is empty or B; a check that names no --repo (or
#                                  --branch) counts every lease.
#                                  Repo is matched case-folded (Kit is kit) and branch without refs/heads/, on
#                                  take and on check alike. check reads no waiting list: during a head's turn it
#                                  answers exit 3 to every seat, the head included (see "The waiting list").
#
# The lease is per (repo, branch): take refuses only while a live lease's scope overlaps the taker's, that is the
# same repo or either names none, and the same branch or either names none. So an engine/main lease does not stop a
# kit/main take, while a lease taken with no --repo (or a lease file from before scopes, which has no repo=/branch=
# lines) covers every trunk until it expires, exactly as check counts it. A seat holds at most one lease per scope;
# release with a scope removes that one, and with none every lease the seat holds.
#
# The protocol is kit sessions/2026_10_14_LAND_TREE_BRANCHES/builds/LANDING_LEASE_DRAFT.md (in force by the
# operator's ruling of 2026-10-28; made blocking by the ruling of 2026-10-30, leasegate). This script carries out
# its mechanics and nothing more:
#   - one file per seat and scope under $LANDING_LEASE_DIR (default ~/.claude/engine/.landing-lease/):
#     <seat>@<repo>@<branch>.lease, or <seat>.lease for a take with no --repo and no --branch; a writer writes
#     only its own files and reads everyone's
#   - taken=/expires= are UTC with a trailing Z; expires is taken + 10 minutes, absolute, never renewed
#   - a row whose expires= has passed is not a lease; nothing reaps it. The ceiling is enforced on read too:
#     a taken= in the future (a local-time stamp written as Z) or an expires= past taken + 10 minutes is not
#     trusted
#   - of two live rows whose scopes overlap the EARLIER taken= holds; a later taker deletes its own file and waits.
#     Takes through this command serialise per scope on a mkdir lock, and the re-read after the write catches a
#     hand-written file and a take of an overlapping scope that held another lock
#   - `take` creates the directory (and says so, for the landing record); `show` reports what is on disk at
#     read time: ABSENT says nothing about who holds a lease, EMPTY says nobody does
#   - $LEASE_DIR/history.log is the lease's holder history, append-only, one line per event. Fields are separated
#     by one TAB (shown here as \t); the first is the UTC Z time, the second the event, and each after that is
#     key=value. No value holds a control byte: TAB, CR, LF, ESC and the rest are folded to a space before the
#     line is written, and so are U+0085, U+2028 and U+2029, so a reader that splits lines on those too (Python's
#     splitlines(), JS) sees the same lines. A reader splits the line on TAB and each field on its first `=`:
#       <UTC Z>\ttake\tseat=S\trepo=R\tbranch=B\texpires=<UTC Z>\twhat=TEXT     (a take that won)
#       <UTC Z>\trelease\tseat=S                                             (a release that removed a file)
#       <UTC Z>\toverride\tseat=S\trepo=R\tbranch=B\tsha=SHA\twhy=TEXT\treason=TEXT
#     The override line is written by kit's .husky/pre-push, not by this script: when a seat sets
#     KIT_LEASE_CHECK_OVERRIDE and the hook could not ask the lease, the hook appends it here, once the rest of
#     the hook has passed, or refuses the push. take/release append best-effort (a failed append never fails
#     them); nothing here truncates or reads it back, and `show` does not report it as a stray file
# It blocks through kit's pre-push hook, not through this script. By the operator's ruling of 2026-10-30
# (leasegate, reversing the 2026-10-28 "advisory" ruling), kit's .husky/pre-push runs
# `engine lease check <seat> --repo kit --branch main` on a push to refs/heads/main. By the operator's ruling of
# 2026-10-31 00:21 (ask core:ops/leasegate-holder), a push needs the pushing seat to HOLD the lease: a free lease
# does not permit a push, so the hook refuses on exit 3 and on "lease: free" alike, and lets the push through only
# on "lease: held by …, so <seat> may push". The hook reads check's stdout to tell those apart, so that wording is
# an interface (pinned by test-lease-sh.sh L48); a reword here breaks the hook closed.
# `check` itself stays read-only: it reads the lease files and writes nothing, so it neither takes nor renews a
# lease. Where a seat is named and this script cannot answer (any exit but 0 or 3, or `engine` off PATH), the hook
# refuses with exit 2 unless KIT_LEASE_CHECK_OVERRIDE carries a reason it can append to history.log; a pusher with
# no seat (a person or CI) is not checked. The seat is a name, not an identity: every seat runs as the same OS
# user, so the lease orders pushes between cooperating seats and grants nothing. Release after the remote-side
# verification, never on the push's exit code.
#
# The waiting list (LEASEQ). Without it the lease went to whoever polled fastest once it freed. A seat joins a trunk's
# FIFO list with `wait` (or `take --queue`); the list is $LEASE_DIR/<repo>@<branch>.queue (repo=, branch=, turn=
# lines, then one `entry\t<joined Z>\t<seat>\t<what>` line per waiter, oldest first), written only under that trunk's
# take lock. Nothing here runs on a timer, a daemon or a poll (operator ruling: "push is fine; timers aren't"): every
# hand-off and drop is computed by the next lease command (`queue_settle`), from the stamps on disk.
#   - The head's TURN is an ordinary lease file: when the trunk is free and the list is not empty, the next take, wait,
#     leave or release writes reserved-for_<head>@<repo>@<branch>.lease (seat=reserved-for:<head>, reserved=<head>),
#     taken= when the turn began (the release, the lease's expiry, or the head's joining, whichever is latest) and
#     expires= GRACE seconds later. During the turn only the head's `take` succeeds (it replaces the reservation with
#     its own lease and leaves the list); any other take is refused naming the head and when its turn ends.
#   - `check` is unchanged and reads no list: it sees the reservation as a live lease held by a seat that is not the
#     pusher, so every seat, the head included, gets its existing exit 3 and refusal line, and kit's pre-push hook
#     refuses with the wording it already knows. Outside a turn the store holds exactly what it held before, so check's
#     stdout, stderr and exit are what they were in every existing state (L48, L58).
#   - An older lease.sh fails safe on a turn: it reads the reservation as a live lease and refuses every take and push
#     until it ends. It does not see the list itself, so after a lease EXPIRES (no release) an older take can win before
#     any newer command has written the turn, and a release by an older engine writes no turn.
#   - A head that lets its turn pass is dropped by the next command and the turn moves on; a turn ended that way
#     needs no command, since the reservation expires on its own. No notice is pushed to the head: release prints the
#     hand-off ("turn passes to <head> until <Z>") for the releasing seat to relay.
#   - history.log gains wait, leave, turn and drop lines in the same TAB format (seat=, repo=, branch=, and until= or
#     at=).
#
# Exit: 0 ok · 1 refused (another seat holds a live lease, this seat already holds one, or a release names a
# seat whose name maps to another seat's file) · 2 usage/IO error (including no HOME and no LANDING_LEASE_DIR) ·
# 3 `check` only: another seat holds a live lease that covers the asked trunk. `show` exits 0 whether or not the lease is
# held; its text is the interface.

set -uo pipefail

LEASE_DIR="${LANDING_LEASE_DIR:-${HOME:+$HOME/.claude/engine/.landing-lease}}"
CEILING=600
# A taken= further than SKEW seconds in the future is not a lease: it is how a local-time stamp written with a
# Z reads on a machine east of UTC (v2's 8h10m hold on this UTC+8 machine).
SKEW=60
# Two `engine lease take` runs on one scope never interleave: each holds a mkdir lock from its first look to its
# verdict, so of two concurrent takes of one scope exactly one wins (a lock older than 60s is a dead taker's and is
# broken). The lock is per scope ($LEASE_DIR/.take.lock@<repo>@<branch>), so takes of two trunks do not wait on each
# other; a take that leaves the repo or the branch empty overlaps many scopes and holds the global $LEASE_DIR/.take.lock
# instead. The lock binds only takers of one lock name. A lease file written by hand, or one written by an overlapping
# take under another lock, is caught by the re-read SETTLE seconds after the write. That re-read is v2's accepted race,
# which it settles with a winner (the earliest taken=, ties by path, which every taker computes the same way).
SETTLE="${LANDING_LEASE_SETTLE:-1}"
# GRACE — the head's turn, in seconds. Kept under CEILING, so a reservation is a lease every reader trusts.
GRACE="${LANDING_LEASE_GRACE:-120}"
case "$GRACE" in ''|*[!0-9]*) GRACE=120 ;; esac
[ "$GRACE" -ge 1 ] && [ "$GRACE" -lt 600 ] || GRACE=120
RESV="reserved-for:"
TAKE_LOCK=""
release_take_lock() { [ -n "$TAKE_LOCK" ] && rmdir "$TAKE_LOCK" 2>/dev/null; TAKE_LOCK=""; }
take_take_lock() {
  local l="$LEASE_DIR/.take.lock${1:-}" i=0 m
  while ! mkdir "$l" 2>/dev/null; do
    i=$((i+1))
    if [ $((i % 20)) -eq 0 ]; then
      m="$(stat -f %m "$l" 2>/dev/null || stat -c %Y "$l" 2>/dev/null || echo "")"
      [ -n "$m" ] && [ $(( $(now_epoch) - m )) -gt 60 ] && rmdir "$l" 2>/dev/null
    fi
    [ "$i" -ge 1200 ] && return 1
    sleep 0.05
  done
  TAKE_LOCK="$l"; trap release_take_lock EXIT
}

die() { printf 'lease: %s\n' "$1" >&2; exit 2; }
# NO_TAKE — what a take that cannot write the store says. Under the 00:21 rule a seat without the lease may not push,
# so a failed take is a stop and never a licence to land.
NO_TAKE="so no lease was taken; do not push, ask the operator"
[ -n "$LEASE_DIR" ] || die "cannot find the lease store: HOME and LANDING_LEASE_DIR are both unset"
now_epoch() { date -u +%s; }
epoch_to_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
iso_to_epoch() {
  local s="$1" e
  case "$s" in *Z) ;; *) return 1 ;; esac
  e="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$s" +%s 2>/dev/null)" && { printf '%s' "$e"; return 0; }
  e="$(date -u -d "$s" +%s 2>/dev/null)" && { printf '%s' "$e"; return 0; }
  return 1
}
# safe_name — a name as a file-name part: everything but A-Za-z0-9._- becomes '_', and a leading '.' too. It can
# never hold '@', so '@' separates the parts of a lease file's name unambiguously.
safe_name() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_' | sed 's/^\./_/'; }
# scope_suffix <repo> <branch> — "" for the unscoped lease, else "@<repo>@<branch>" (normalised values).
scope_suffix() { [ -z "$1" ] && [ -z "$2" ] && return 0; printf '@%s@%s' "$(safe_name "$1")" "$(safe_name "$2")"; }
# seat_file <seat> [repo] [branch] — the seat's own file for that scope.
seat_file() { printf '%s/%s%s.lease' "$LEASE_DIR" "$(safe_name "$1")" "$(scope_suffix "${2:-}" "${3:-}")"; }
field() { sed -n "s/^$1=//p" "$2" | head -1; }
# one_line — a value for a history.log field: every control byte (TAB, CR, LF, ESC, DEL…) folded to a space, and so
# are U+0085 (NEL), U+2028 and U+2029 (their UTF-8 bytes, written in octal), which Python's splitlines() and JS treat
# as line breaks.
NEL=$(printf '\302\205'); LSEP=$(printf '\342\200\250'); PSEP=$(printf '\342\200\251')
one_line() { printf '%s' "$1" | LC_ALL=C tr '\000-\037\177' ' ' | LC_ALL=C sed -e "s/$NEL/ /g" -e "s/$LSEP/ /g" -e "s/$PSEP/ /g"; }
# norm_repo / norm_branch — the scope as take records it and check compares it: repo case-folded, branch without
# refs/heads/, so `Kit` and `refs/heads/main` name the same trunk as `kit` and `main`.
norm_repo() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
norm_branch() { printf '%s' "${1#refs/heads/}"; }
# row_repo / row_branch — a lease file's scope, normalised the same way (a file take did not write may spell it
# otherwise; a file with no repo= or branch= line names no scope there, so it covers every repo or branch).
row_repo() { norm_repo "$(field repo "$1")"; }
row_branch() { norm_branch "$(field branch "$1")"; }
# overlaps <r1> <b1> <r2> <b2> — do two scopes share a trunk? Empty is every repo (or every branch).
overlaps() {
  { [ -z "$1" ] || [ -z "$3" ] || [ "$1" = "$3" ]; } && { [ -z "$2" ] || [ -z "$4" ] || [ "$2" = "$4" ]; }
}
# parse_scope <usage> [--repo R] [--branch B]… — sets SCOPE_REPO/SCOPE_BRANCH (normalised); an empty value, a missing
# value or any other argument is a usage error, so a typo cannot widen a scope to everything.
parse_scope() {
  local usage="$1"; shift
  SCOPE_REPO=""; SCOPE_BRANCH=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) [ $# -ge 2 ] && [ -n "$2" ] || die "--repo needs a value"; SCOPE_REPO="$(norm_repo "$2")"; shift 2 ;;
      --branch) [ $# -ge 2 ] && [ -n "$2" ] || die "--branch needs a value"; SCOPE_BRANCH="$(norm_branch "$2")"; shift 2 ;;
      *) die "unknown argument: $1 (usage: $usage)" ;;
    esac
  done
}
# lease_history — append one event line to $LEASE_DIR/history.log: the event, then each argument (key=value) as a
# TAB-separated field with its control bytes folded. Best-effort: the lease itself is the seat files.
lease_history() {
  local line a
  line="$(epoch_to_iso "$(now_epoch)")"
  for a in "$@"; do line="$line"$'\t'"$(one_line "$a")"; done
  printf '%s\n' "$line" >> "$LEASE_DIR/history.log" 2>/dev/null || true
}

# live_rows — one line per live lease: "<taken_epoch> <expires_epoch> <file>", earliest taken first, ties by path.
# A row is live only while taken <= now + SKEW and now < min(expires, taken + CEILING): the ceiling is enforced on
# read, not trusted from expires=. A row with an unreadable, non-UTC, future or over-ceiling stamp is not a lease
# (it counts for nobody, so under the hold-to-push rule it lets no seat push), and is reported by `show`.
live_rows() {
  local f t e now
  now="$(now_epoch)"
  [ -d "$LEASE_DIR" ] || return 0
  for f in "$LEASE_DIR"/*.lease; do
    [ -f "$f" ] || continue
    t="$(iso_to_epoch "$(field taken "$f")")" || continue
    e="$(iso_to_epoch "$(field expires "$f")")" || continue
    [ "$t" -le $((now + SKEW)) ] || continue
    [ "$e" -le $((t + CEILING)) ] || e=$((t + CEILING))
    [ "$e" -gt "$now" ] && printf '%s %s %s\n' "$t" "$e" "$f"
  done | sort -k1,1n -k3,3
}

# holder_file <repo> <branch> — the file of the earliest live lease whose scope overlaps <repo>/<branch> (the one a
# take of that scope waits on), or nothing. Empty arguments overlap every lease.
holder_file() {
  local f
  while read -r _ _ f; do
    [ -n "$f" ] || continue
    overlaps "$1" "$2" "$(row_repo "$f")" "$(row_branch "$f")" && { printf '%s' "$f"; return 0; }
  done <<< "$(live_rows)"
}

# describe — one line (no trailing newline; callers add it) naming a row's holder and its effective time left.
describe() {
  local f="$1" t e now
  now="$(now_epoch)"; t="$(iso_to_epoch "$(field taken "$f")")"; e="$(iso_to_epoch "$(field expires "$f")")"
  [ "$e" -le $((t + CEILING)) ] || e=$((t + CEILING))
  printf '%s (repo=%s branch=%s taken=%s expires=%s, %ss left) %s' "$(field seat "$f")" "$(field repo "$f")" \
    "$(field branch "$f")" "$(field taken "$f")" "$(epoch_to_iso "$e")" "$((e - now))" "$(field what "$f")"
}

# ---- the waiting list (see "The waiting list" above) ----
queue_file() { printf '%s/%s@%s.queue' "$LEASE_DIR" "$(safe_name "$1")" "$(safe_name "$2")"; }
# queue_settle <repo> <branch> <write 0|1> — compute the list's state now, from the stamps on disk. Sets Q_SEATS (the
# waiters left, oldest first, one per line), Q_HEAD (whose turn it is, or empty) and Q_END (the turn's end, epoch). With
# write=1 it also persists that state: drops leave the file (history `drop`), expired reservations on this trunk are
# removed, and a head with no reservation gets one (history `turn`). Call it with write=1 only under the trunk's lock.
queue_settle() {
  local repo="$1" branch="$2" write="$3" qf h now F turn e t f seat joined what start kept="" dropped="" line
  Q_SEATS=""; Q_HEAD=""; Q_END=""; Q_START=""
  qf="$(queue_file "$repo" "$branch")"
  [ -f "$qf" ] || return 0
  now="$(now_epoch)"
  h="$(holder_file "$repo" "$branch")"
  if [ -n "$h" ]; then
    Q_SEATS="$(awk -F'\t' '$1=="entry"{print $3}' "$qf")"
    if [ -n "$(field reserved "$h")" ]; then
      Q_HEAD="$(field reserved "$h")"
      t="$(iso_to_epoch "$(field taken "$h")")"; e="$(iso_to_epoch "$(field expires "$h")")"
      [ "$e" -le $((t + CEILING)) ] || e=$((t + CEILING)); Q_END="$e"
    fi
    return 0
  fi
  # Free: the turn starts at the latest of the release (turn=), the expiry of any lease covering the trunk, and the
  # waiter's own joining.
  F=0; turn="$(iso_to_epoch "$(field turn "$qf")" 2>/dev/null)" && F="$turn"
  for f in "$LEASE_DIR"/*.lease; do
    [ -f "$f" ] || continue
    overlaps "$repo" "$branch" "$(row_repo "$f")" "$(row_branch "$f")" || continue
    t="$(iso_to_epoch "$(field taken "$f")")" || continue
    e="$(iso_to_epoch "$(field expires "$f")")" || continue
    [ "$t" -le $((now + SKEW)) ] || continue
    [ "$e" -le $((t + CEILING)) ] || e=$((t + CEILING))
    [ "$e" -le "$now" ] && [ "$e" -gt "$F" ] && F="$e"
  done
  while IFS=$'\t' read -r tag joined seat what; do
    [ "$tag" = entry ] || continue
    if [ -z "$Q_HEAD" ]; then
      start="$(iso_to_epoch "$joined")" || start="$now"
      [ "$start" -ge "$F" ] || start="$F"
      if [ $((start + GRACE)) -le "$now" ]; then
        F=$((start + GRACE)); dropped="$dropped$seat"$'\t'"$F"$'\n'; continue
      fi
      Q_HEAD="$seat"; Q_START="$start"; Q_END=$((start + GRACE))
    fi
    kept="$kept$tag"$'\t'"$joined"$'\t'"$seat"$'\t'"$what"$'\n'
    Q_SEATS="$Q_SEATS${Q_SEATS:+$'\n'}$seat"
  done < "$qf"
  [ "$write" = 1 ] || return 0
  for f in "$LEASE_DIR"/reserved-for_*@"$(safe_name "$repo")"@"$(safe_name "$branch")".lease; do
    [ -f "$f" ] && [ -n "$(field reserved "$f")" ] && rm -f "$f"
  done
  { printf 'repo=%s\nbranch=%s\nturn=%s\n' "$repo" "$branch" "$(field turn "$qf")"; printf '%s' "$kept"; } > "$qf.tmp" \
    && mv -f "$qf.tmp" "$qf" || die "cannot write $qf"
  while IFS=$'\t' read -r seat e; do
    [ -n "$seat" ] && lease_history drop "seat=$seat" "repo=$repo" "branch=$branch" "at=$(epoch_to_iso "$e")"
  done <<< "$dropped"
  if [ -n "$Q_HEAD" ]; then
    printf 'seat=%s\nreserved=%s\nrepo=%s\nbranch=%s\ntaken=%s\nexpires=%s\nwhat=%s\n' "$RESV$Q_HEAD" "$Q_HEAD" "$repo" \
      "$branch" "$(epoch_to_iso "$Q_START")" "$(epoch_to_iso "$Q_END")" \
      "turn of $Q_HEAD in the lease queue; it takes the lease with: engine lease take $Q_HEAD --repo $repo --branch $branch" \
      > "$(seat_file "$RESV$Q_HEAD" "$repo" "$branch")" || die "cannot write the reservation for $Q_HEAD"
    lease_history turn "seat=$Q_HEAD" "repo=$repo" "branch=$branch" "until=$(epoch_to_iso "$Q_END")"
  fi
}
# queue_set_turn <repo> <branch> — record that the lease went free now (a release, or a head leaving).
queue_set_turn() {
  local qf; qf="$(queue_file "$1" "$2")"; [ -f "$qf" ] || return 0
  sed "s/^turn=.*/turn=$(epoch_to_iso "$(now_epoch)")/" "$qf" > "$qf.tmp" && mv -f "$qf.tmp" "$qf"
}
# queue_position <seat> — 1-based place of <seat> in Q_SEATS, or empty.
queue_position() { printf '%s\n' "$Q_SEATS" | awk -v s="$1" '$0==s{print NR; exit}'; }
# queue_join <seat> <repo> <branch> <what> — append <seat> unless it is already waiting (it keeps its place), settle,
# and say where it stands. Call under the trunk's lock.
queue_join() {
  local seat="$1" repo="$2" branch="$3" what="$4" qf pos
  qf="$(queue_file "$repo" "$branch")"
  [ -f "$qf" ] || printf 'repo=%s\nbranch=%s\nturn=\n' "$repo" "$branch" > "$qf" || die "cannot write $qf"
  if ! awk -F'\t' -v s="$seat" '$1=="entry" && $3==s{f=1} END{exit !f}' "$qf"; then
    printf 'entry\t%s\t%s\t%s\n' "$(epoch_to_iso "$(now_epoch)")" "$seat" "$(one_line "$what" | tr '\t' ' ')" >> "$qf" || die "cannot write $qf"
    lease_history wait "seat=$seat" "repo=$repo" "branch=$branch"
  fi
  queue_settle "$repo" "$branch" 1
  pos="$(queue_position "$seat")"
  if [ "$Q_HEAD" = "$seat" ] && [ -n "$(field reserved "$(holder_file "$repo" "$branch")")" ]; then
    printf 'lease: %s is position %s in the %s/%s queue and it is its turn: take it now, before %s: engine lease take %s --repo %s --branch %s\n' \
      "$seat" "$pos" "$repo" "$branch" "$(epoch_to_iso "$Q_END")" "$seat" "$repo" "$branch"
  else
    printf 'lease: %s is position %s in the %s/%s queue; when its turn comes it has %ss to take the lease\n' \
      "$seat" "$pos" "$repo" "$branch" "$GRACE"
  fi
}
# queue_trunk_args — parse `<seat> --repo R --branch B [--what T]` for wait/leave; both scope parts are required.
queue_trunk_args() {
  local usage="$1"; shift
  Q_ARG_SEAT="${1:-}"; [ -n "$Q_ARG_SEAT" ] || die "usage: $usage"; shift
  Q_ARG_WHAT=""
  local rest=()
  while [ $# -gt 0 ]; do
    case "$1" in --what) Q_ARG_WHAT="${2:-}"; shift 2 ;; *) rest+=("$1"); shift ;; esac
  done
  parse_scope "$usage" ${rest[@]+"${rest[@]}"}
  [ -n "$SCOPE_REPO" ] && [ -n "$SCOPE_BRANCH" ] || die "a queue is per trunk: --repo and --branch are both needed (usage: $usage)"
  case "$Q_ARG_SEAT" in "$RESV"*) die "a seat name may not start with $RESV" ;; esac
}
lease_wait() {
  local usage="engine lease wait <seat> --repo R --branch B [--what TEXT]"
  queue_trunk_args "$usage" "$@"
  if [ ! -d "$LEASE_DIR" ]; then
    mkdir -p "$LEASE_DIR" 2>/dev/null || die "the lease store $LEASE_DIR could not be created, so the seat was not queued"
    printf 'lease: created %s (say so in the landing record)\n' "$LEASE_DIR"
  fi
  take_take_lock "$(scope_suffix "$SCOPE_REPO" "$SCOPE_BRANCH")" || die "another take has held the take lock for over a minute, so the seat was not queued"
  queue_join "$Q_ARG_SEAT" "$SCOPE_REPO" "$SCOPE_BRANCH" "$Q_ARG_WHAT"
}
lease_leave() {
  local usage="engine lease leave <seat> --repo R --branch B" qf r
  queue_trunk_args "$usage" "$@"
  qf="$(queue_file "$SCOPE_REPO" "$SCOPE_BRANCH")"
  [ -f "$qf" ] || { printf 'lease: %s is not in the %s/%s queue\n' "$Q_ARG_SEAT" "$SCOPE_REPO" "$SCOPE_BRANCH"; return 0; }
  take_take_lock "$(scope_suffix "$SCOPE_REPO" "$SCOPE_BRANCH")" || die "another take has held the take lock for over a minute"
  if ! awk -F'\t' -v s="$Q_ARG_SEAT" '$1=="entry" && $3==s{f=1} END{exit !f}' "$qf"; then
    printf 'lease: %s is not in the %s/%s queue\n' "$Q_ARG_SEAT" "$SCOPE_REPO" "$SCOPE_BRANCH"; return 0
  fi
  awk -F'\t' -v s="$Q_ARG_SEAT" '!($1=="entry" && $3==s)' "$qf" > "$qf.tmp" && mv -f "$qf.tmp" "$qf" || die "cannot write $qf"
  r="$(seat_file "$RESV$Q_ARG_SEAT" "$SCOPE_REPO" "$SCOPE_BRANCH")"
  if [ -f "$r" ] && [ "$(field reserved "$r")" = "$Q_ARG_SEAT" ]; then rm -f "$r"; queue_set_turn "$SCOPE_REPO" "$SCOPE_BRANCH"; fi
  lease_history leave "seat=$Q_ARG_SEAT" "repo=$SCOPE_REPO" "branch=$SCOPE_BRANCH"
  printf 'lease: %s left the %s/%s queue\n' "$Q_ARG_SEAT" "$SCOPE_REPO" "$SCOPE_BRANCH"
  queue_settle "$SCOPE_REPO" "$SCOPE_BRANCH" 1
  [ -n "$Q_HEAD" ] && [ -n "$Q_START" ] && printf 'lease: turn passes to %s until %s\n' "$Q_HEAD" "$(epoch_to_iso "$Q_END")"
  return 0
}
# queue_show <repo> <branch> — the read-only queue lines for `show`.
queue_show() {
  local qf="$1" repo branch s n=0 out="" now
  repo="$(field repo "$qf")"; branch="$(field branch "$qf")"
  queue_settle "$repo" "$branch" 0
  [ -n "$Q_SEATS" ] || return 0
  now="$(now_epoch)"
  while IFS= read -r s; do
    [ -n "$s" ] || continue; n=$((n + 1))
    if [ "$s" = "$Q_HEAD" ]; then out="$out $n. $s (its turn until $(epoch_to_iso "$Q_END"), $((Q_END - now))s left)"
    else out="$out $n. $s (waiting)"; fi
  done <<< "$Q_SEATS"
  printf 'queue %s/%s:%s\n' "$repo" "$branch" "$out"
}

lease_show() {
  parse_scope "engine lease show [--repo R] [--branch B]" "$@"
  local repo="$SCOPE_REPO" branch="$SCOPE_BRANCH" scoped="" label
  [ -n "$repo$branch" ] && scoped=1
  label="${repo:-*}/${branch:-*}"
  if [ ! -e "$LEASE_DIR" ]; then
    printf 'lease: %s is absent. That says nothing about who holds a lease (ABSENT is not EMPTY); `engine lease take` creates it.\n' "$LEASE_DIR"
    return 0
  fi
  [ -d "$LEASE_DIR" ] || die "$LEASE_DIR exists but is not a directory, so the lease cannot be read; do not push, ask the operator"
  [ -r "$LEASE_DIR" ] && [ -x "$LEASE_DIR" ] || die "cannot read $LEASE_DIR, so the lease cannot be read; do not push, ask the operator"
  local f g paths others=0 shown=0 seen
  paths="$(live_rows | cut -d' ' -f3-)"
  for f in "$LEASE_DIR"/* "$LEASE_DIR"/.[!.]*; do
    [ -e "$f" ] || continue
    case "$f" in *.lease) [ -f "$f" ] && continue ;; */.take.lock|*/.take.lock@*|*/history.log|*.queue) continue ;; esac
    others=$((others + 1))
  done
  # Every live lease, earliest first: a holder when no earlier live lease overlaps its scope, else a later take that
  # yields. With --repo/--branch, only the leases that cover that trunk (check's rule) are listed.
  seen=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ -z "$scoped" ] || overlaps "$repo" "$branch" "$(row_repo "$f")" "$(row_branch "$f")"; then
      g="$(holder_file "$(row_repo "$f")" "$(row_branch "$f")")"
      if [ "$g" = "$f" ]; then
        printf 'lease: held by %s\n' "$(describe "$f")"
      else
        printf '  later take (yields to %s): %s\n' "$(field seat "$g")" "$(describe "$f")"
      fi
      shown=$((shown + 1))
    fi
  done <<< "$paths"
  if [ "$shown" -gt 0 ]; then
    :
  elif [ -n "$scoped" ]; then
    printf 'lease: %s exists and nobody holds a lease that covers %s.\n' "$LEASE_DIR" "$label"
  elif [ "$others" -eq 0 ]; then
    printf 'lease: %s exists and nobody holds a lease.\n' "$LEASE_DIR"
  else
    printf 'lease: %s holds no lease this command can read, and %s other file(s) that may be hand-written leases:\n' "$LEASE_DIR" "$others"
  fi
  for f in "$LEASE_DIR"/*.lease; do
    [ -f "$f" ] || continue
    printf '%s\n' "$paths" | grep -qxF -- "$f" || printf '  not a lease (expired, future, over-ceiling or unreadable stamp): %s taken=%s expires=%s\n' \
      "$(field seat "$f")" "$(field taken "$f")" "$(field expires "$f")"
  done
  for f in "$LEASE_DIR"/* "$LEASE_DIR"/.[!.]*; do
    [ -e "$f" ] || continue
    case "$f" in *.lease) [ -f "$f" ] && continue ;; */.take.lock|*/.take.lock@*|*/history.log|*.queue) continue ;; esac
    printf '  not a lease (unrecognised file; a lease is <seat>[@<repo>@<branch>].lease with seat= repo= branch= taken= expires= what= lines): %s\n' "$(basename "$f")"
  done
  # The waiting lists, read-only: with --repo/--branch only the lists of trunks that scope covers.
  for f in "$LEASE_DIR"/*.queue; do
    [ -f "$f" ] || continue
    if [ -z "$scoped" ] || overlaps "$repo" "$branch" "$(field repo "$f")" "$(field branch "$f")"; then queue_show "$f"; fi
  done
  return 0
}

lease_take() {
  local seat="${1:-}"; [ -n "$seat" ] || die "usage: engine lease take <seat> [--repo R] [--branch B] [--what TEXT]"
  shift
  local repo="" branch="" what="" queue=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) repo="$(norm_repo "${2:-}")"; shift 2 ;;
      --branch) branch="$(norm_branch "${2:-}")"; shift 2 ;;
      --what) what="${2:-}"; shift 2 ;;
      --queue) queue=1; shift ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  case "$seat" in "$RESV"*) die "a seat name may not start with $RESV" ;; esac
  [ -z "$queue" ] || { [ -n "$repo" ] && [ -n "$branch" ]; } || die "--queue needs --repo and --branch: a queue is per trunk"
  # A take that names both repo and branch locks its own scope; one that leaves either empty overlaps many scopes
  # and locks globally (see SETTLE above for how it meets a scoped take of an overlapping trunk).
  local lock=""
  [ -n "$repo" ] && [ -n "$branch" ] && lock="$(scope_suffix "$repo" "$branch")"
  if [ ! -d "$LEASE_DIR" ]; then
    mkdir -p "$LEASE_DIR" 2>/dev/null || die "the lease store $LEASE_DIR could not be created, $NO_TAKE"
    printf 'lease: created %s (say so in the landing record)\n' "$LEASE_DIR"
  fi
  # A store that exists but cannot be written fails here, at once, rather than spinning a minute on the take lock.
  [ -d "$LEASE_DIR" ] && [ -w "$LEASE_DIR" ] && [ -x "$LEASE_DIR" ] || die "the lease store $LEASE_DIR could not be written, $NO_TAKE"
  local mine h
  mine="$(seat_file "$seat" "$repo" "$branch")"
  take_take_lock "$lock" || die "another take has held $LEASE_DIR/.take.lock$lock for over a minute, $NO_TAKE"
  # Hand-offs and drops due on every waiting list this take covers are settled first (they may write a turn).
  local qf
  for qf in "$LEASE_DIR"/*.queue; do
    [ -f "$qf" ] || continue
    overlaps "$repo" "$branch" "$(field repo "$qf")" "$(field branch "$qf")" && queue_settle "$(field repo "$qf")" "$(field branch "$qf")" 1
  done
  h="$(holder_file "$repo" "$branch")"
  local turn=""
  if [ -n "$h" ] && [ -n "$(field reserved "$h")" ]; then
    if [ "$(field reserved "$h")" = "$seat" ] && [ "$(row_repo "$h")" = "$repo" ] && [ "$(row_branch "$h")" = "$branch" ]; then
      turn="$h"; h=""
    else
      printf 'lease: refused, reserved for %s: its turn in the %s/%s queue ends at %s (%ss left)\n' "$(field reserved "$h")" \
        "$(field repo "$h")" "$(field branch "$h")" "$(field expires "$h")" "$(( $(iso_to_epoch "$(field expires "$h")") - $(now_epoch) ))" >&2
      if [ -n "$queue" ]; then queue_join "$seat" "$repo" "$branch" "$what" >&2
      else printf 'lease: join the queue with: engine lease wait %s --repo %s --branch %s\n' "$seat" "$(field repo "$h")" "$(field branch "$h")" >&2; fi
      return 1
    fi
  fi
  if [ -n "$h" ]; then
    [ -n "$queue" ] && [ "$(field seat "$h")" != "$seat" ] && queue_join "$seat" "$repo" "$branch" "$what" >&2
    if [ "$(field seat "$h")" = "$seat" ]; then
      printf 'lease: refused, %s already holds a live lease: %s\n' "$seat" "$(describe "$h")" >&2
    else
      printf 'lease: refused, held by %s\n' "$(describe "$h")" >&2
      printf 'lease: wait until it expires, then take again.\n' >&2
    fi
    return 1
  fi
  [ -z "$turn" ] || rm -f "$turn"
  local t; t="$(now_epoch)"
  printf 'seat=%s\nrepo=%s\nbranch=%s\ntaken=%s\nexpires=%s\nwhat=%s\n' "$seat" "$repo" "$branch" \
    "$(epoch_to_iso "$t")" "$(epoch_to_iso $((t + CEILING)))" "$what" > "$mine" || die "the lease file $mine could not be written, $NO_TAKE"
  sleep "$SETTLE"
  h="$(holder_file "$repo" "$branch")"
  [ -n "$h" ] || { rm -f "$mine"; die "wrote $mine but cannot read it back as a lease, $NO_TAKE"; }
  if [ "$h" != "$mine" ]; then
    rm -f "$mine"
    printf 'lease: refused, lost the tiebreak (earlier taken= wins) to %s\n' "$(describe "$h")" >&2
    printf 'lease: wait until it expires, then take again.\n' >&2
    return 1
  fi
  printf 'lease: taken by %s\n' "$(describe "$mine")"
  # The taker leaves the list it was waiting on (it was the head, or the list was empty).
  qf="$(queue_file "$repo" "$branch")"
  if [ -n "$repo" ] && [ -n "$branch" ] && [ -f "$qf" ]; then
    awk -F'\t' -v s="$seat" '!($1=="entry" && $3==s)' "$qf" > "$qf.tmp" && mv -f "$qf.tmp" "$qf"
  fi
  lease_history take "seat=$seat" "repo=$repo" "branch=$branch" "expires=$(field expires "$mine")" "what=$what"
}

# lease_release — with a scope, remove the seat's own file for that scope; with none, every file of the seat's (its
# unscoped <seat>.lease and each <seat>@*.lease), which is what LANDING.md's `engine lease release <seat>` means. A
# file whose name maps from the seat but whose seat= is another seat's is never removed, and refuses (exit 1).
lease_release() {
  local seat="${1:-}"; [ -n "$seat" ] || die "usage: engine lease release <seat> [--repo R] [--branch B]"
  shift
  parse_scope "engine lease release <seat> [--repo R] [--branch B]" "$@"
  local files f owner r b removed=0 refused=0 released=""
  if [ -n "$SCOPE_REPO$SCOPE_BRANCH" ]; then
    files="$(seat_file "$seat" "$SCOPE_REPO" "$SCOPE_BRANCH")"
  else
    files="$(seat_file "$seat")"
    for f in "$LEASE_DIR/$(safe_name "$seat")"@*.lease; do [ -f "$f" ] && files="$files"$'\n'"$f"; done
  fi
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    owner="$(field seat "$f")"
    if [ "$owner" != "$seat" ]; then
      printf 'lease: refused, %s belongs to seat %s, whose name maps to the same file\n' "$f" "$owner" >&2
      refused=1; continue
    fi
    r="$(field repo "$f")"; b="$(field branch "$f")"
    rm -f "$f" || die "cannot remove $f"
    lease_history release "seat=$seat"
    printf 'lease: released by %s (repo=%s branch=%s)\n' "$seat" "$r" "$b"
    removed=$((removed + 1))
    released="${released}L"$'\t'"$(norm_repo "$r")"$'\t'"$(norm_branch "$b")"$'\n'
  done <<< "$files"
  # Hand-off: each waiting list on a trunk a removed lease covered gets its turn now.
  local qf qr qb tag
  for qf in "$LEASE_DIR"/*.queue; do
    [ -f "$qf" ] || continue
    qr="$(field repo "$qf")"; qb="$(field branch "$qf")"
    while IFS=$'\t' read -r tag r b; do
      [ "$tag" = L ] || continue
      if overlaps "$qr" "$qb" "$r" "$b"; then
        take_take_lock "$(scope_suffix "$qr" "$qb")" || { printf 'lease: could not take the %s/%s take lock; its queue moves on at the next command\n' "$qr" "$qb" >&2; break; }
        queue_set_turn "$qr" "$qb"; queue_settle "$qr" "$qb" 1
        [ -n "$Q_HEAD" ] && [ -n "$Q_START" ] && printf 'lease: turn passes to %s until %s (it takes the lease with: engine lease take %s --repo %s --branch %s)\n' \
          "$Q_HEAD" "$(epoch_to_iso "$Q_END")" "$Q_HEAD" "$qr" "$qb"
        release_take_lock; break
      fi
    done <<< "$released"
  done
  [ "$refused" -eq 0 ] || return 1
  [ "$removed" -gt 0 ] || printf 'lease: %s held no lease file (%s)\n' "$seat" "$(seat_file "$seat" "$SCOPE_REPO" "$SCOPE_BRANCH")"
  return 0
}

# lease_check — the read-only question a push gate asks. The holder is found exactly as `take` finds it, so a
# seat `check` names as holder is a seat `take` would not have refused. It writes nothing; an absent directory
# means nobody holds a lease and prints "lease: free (…)", and an unreadable one is exit 2. Neither is changed by
# the 00:21 rule (core:ops/leasegate-holder), and neither needs to be: the hook permits a push only on the "held by
# …, so <seat> may push" line, so an absent or unwritable store reads as free (or as an error) and the push is
# refused. A store `take` could not write therefore fails in the safe direction, with no lease and no push.
# With --repo/--branch it counts only the leases that cover that trunk: a lease taken for another
# repo's trunk does not stop this one. Its holder is holder_file's for the asked scope, the earliest live lease that
# covers it, which is the lease a take of that scope waits on.
lease_check() {
  local seat="${1:-}"; [ -n "$seat" ] || die "usage: engine lease check <seat> [--repo R] [--branch B]"
  shift
  parse_scope "engine lease check <seat> [--repo R] [--branch B]" "$@"
  local repo="$SCOPE_REPO" branch="$SCOPE_BRANCH"
  if [ ! -e "$LEASE_DIR" ]; then
    printf 'lease: free (%s is absent, so nobody has taken a lease)\n' "$LEASE_DIR"
    return 0
  fi
  [ -d "$LEASE_DIR" ] && [ -r "$LEASE_DIR" ] && [ -x "$LEASE_DIR" ] || die "cannot read $LEASE_DIR"
  local h
  h="$(holder_file "$repo" "$branch")"
  if [ -z "$h" ]; then
    printf 'lease: free\n'
  elif [ "$(field seat "$h")" = "$seat" ]; then
    printf 'lease: held by %s, so %s may push\n' "$(describe "$h")" "$seat"
  else
    printf 'lease: %s may not push now; held by %s\n' "$seat" "$(describe "$h")" >&2
    return 3
  fi
}

cmd="${1:-show}"; [ $# -gt 0 ] && shift
case "$cmd" in
  show) lease_show "$@" ;;
  take) lease_take "$@" ;;
  release) lease_release "$@" ;;
  wait) lease_wait "$@" ;;
  leave) lease_leave "$@" ;;
  check) lease_check "$@" ;;
  -h|--help|help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown subcommand: $cmd (take|release|show|check|wait|leave)" ;;
esac
