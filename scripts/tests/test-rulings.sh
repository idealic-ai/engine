#!/bin/bash
# test-rulings.sh — `engine rulings` (scripts/rulings.sh) and fleet_live_chain (scripts/lib.sh).
#
# The format, as rulings.sh's header describes it: one section file per manager under rulings/,
# append-only, read down the live ancestor chain.
#
# Every case uses the test seam: FLEET_LIVE_PANES (a stub tree) and RULINGS_DIR (a temp folder),
# both honoured only with FLEET_TEST_SEAM=1. No case reads tmux or the real fleet data dir:
# TMUX/TMUX_PANE are scrubbed and every no-seam read meets "no tmux server named".
#
# Plant a defect: RULINGS_SH=<mutated copy> (it sources RULINGS_LIB, default this tree's lib.sh)
# or RULINGS_LIB=<mutated lib.sh> — it must go red.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

TREE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RULINGS_SH="${RULINGS_SH:-$TREE_ROOT/scripts/rulings.sh}"
RULINGS_LIB="${RULINGS_LIB:-$TREE_ROOT/scripts/lib.sh}"
BASH_BIN="${RULINGS_BASH:-/bin/bash}"

SCRUB="-u TMUX -u TMUX_PANE -u FLEET_PANE -u FLEET_PARENT -u FLEET_TMUX_SOCKET -u FLEET_LIVE_PANES
       -u FLEET_TEST_SEAM -u FLEET_WARN_PREFIX -u FLEET_WARN_ONCE_DIR -u _LIB_SH_LOADED
       -u FLEET_MANAGES -u RULINGS_DIR"

FIX=""
RD=""

setup() {
  FIX="$(mktemp -d)"
  RD="$FIX/rulings"
  mkdir -p "$RD"
  # Four rungs on the meta branch (director → manager → worker → synthetic lane seat), and a
  # sibling branch under manager:core.
  cat > "$FIX/tree.txt" <<'EOF'
manager:director %1 -
manager:meta %32 manager:director
meta:engine %27 manager:meta
meta:engine-lane %90 meta:engine
manager:core %40 manager:director
core:ui %41 manager:core
EOF
}

teardown() { rm -rf "$FIX"; }

# plant <section> <owner> <n> <question> <ruling> [scope] — a hand-written section block, the
# §7 fixture shape. Creates the header on first use.
plant() {
  local f="$RD/$1.md"
  [ -f "$f" ] || printf '%s\n' "# Rulings: $1" "owner: $2" > "$f"
  printf '%s\n' "" "## $1#$3" "at: 2026-11-04T22:00:00Z" "by: $2 %0" "scope: ${6:-subtree}" \
    "question: $4" "ruling: $5" "source: test" >> "$f"
}

# r <NAME=VALUE…> <args…> — run rulings.sh in a scrubbed bash with the seam on. Sets OUT ERR RC.
# Stdin is /dev/null unless IN is set (then IN's content is piped).
r() {
  local envs=()
  while [ $# -gt 0 ] && [[ "$1" == *=* ]]; do envs+=("$1"); shift; done
  # shellcheck disable=SC2086
  OUT=$(printf '%s' "${IN:-}" | env $SCRUB FLEET_TEST_SEAM=1 FLEET_LIVE_PANES="$FIX/tree.txt" \
          RULINGS_DIR="$RD" RULINGS_LIB="$RULINGS_LIB" ${envs[@]+"${envs[@]}"} \
          "$BASH_BIN" "$RULINGS_SH" "$@" 2>"$FIX/err")
  RC=$?
  ERR=$(cat "$FIX/err")
}

# rn — like r but with NO seam marker and no seam values unless passed.
rn() {
  local envs=()
  while [ $# -gt 0 ] && [[ "$1" == *=* ]]; do envs+=("$1"); shift; done
  # shellcheck disable=SC2086
  OUT=$(printf '%s' "${IN:-}" | env $SCRUB RULINGS_LIB="$RULINGS_LIB" ${envs[@]+"${envs[@]}"} \
          "$BASH_BIN" "$RULINGS_SH" "$@" 2>"$FIX/err")
  RC=$?
  ERR=$(cat "$FIX/err")
}

has()   { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "contains: $1" "$2" ;; esac; }
hasnt() { case "$2" in *"$1"*) fail "$3" "does not contain: $1" "$2" ;; *) pass "$3" ;; esac; }
TAB=$(printf '\t')

# ---------------------------------------------------------------- acceptance 1 (§7)

test_planted_ruling_reaches_a_seat_two_rungs_below() {
  plant manager:meta manager:meta 1 planted planted-ruling
  plant manager:core manager:core 1 sibling sibling-ruling
  # Positive control: the plant is on disk, so a failure below is the reader's, not the fixture's.
  has planted-ruling "$(cat "$RD/manager:meta.md")" "fixture planted"
  r live --seat meta:engine-lane
  assert_eq 0 "$RC" "reader exit 0 ($ERR)"
  has "${TAB}manager:meta#1${TAB}" "$OUT" "a seat two rungs below the section owner sees manager:meta#1"
}

test_sibling_branch_does_not_receive_the_ruling() {
  plant manager:meta manager:meta 1 planted planted-ruling
  plant manager:core manager:core 1 sibling sibling-ruling
  r live --seat meta:engine-lane
  assert_eq 0 "$RC" "reader exit 0"
  hasnt sibling-ruling "$OUT" "manager:core's ruling does not leak into the meta chain"
  r live --seat core:ui
  assert_eq 0 "$RC" "sibling reader exit 0"
  hasnt planted-ruling "$OUT" "manager:meta's ruling does not reach core:ui"
  has sibling-ruling "$OUT" "core:ui does see its own manager's ruling (control)"
}

test_fleet_section_reaches_everyone() {
  plant fleet manager:director 1 "Which branch do docs land on?" "Docs land on main." fleet
  local s
  for s in manager:director manager:meta meta:engine meta:engine-lane manager:core core:ui; do
    r live --seat "$s"
    assert_eq 0 "$RC" "$s: exit 0"
    has "fleet${TAB}fleet#1${TAB}" "$OUT" "$s receives fleet#1"
  done
}

test_output_shape_and_order_match_the_contract() {
  plant fleet manager:director 1 "Which branch do docs land on?" "Docs land on main." fleet
  plant manager:meta manager:meta 1 old old-ruling
  plant manager:meta manager:meta 2 "Run the full suite per lane?" "No: once per wave."
  printf '%s\n' "" "## manager:meta#1 superseded" "at: 2026-11-04T22:10:00Z" "by: manager:meta %32" \
    "superseded-by: manager:meta#2" >> "$RD/manager:meta.md"
  mkdir -p "$RD/.reads"
  printf 'fleet\t1\n' > "$RD/.reads/meta:engine-lane.tsv"
  r live --seat meta:engine-lane
  assert_eq 0 "$RC" "exit 0"
  local want
  want="$(printf 'fleet\tfleet#1\t2026-11-04T22:00:00Z\tfleet\t-\tWhich branch do docs land on?\tDocs land on main.\tread\nmanager:meta\tmanager:meta#2\t2026-11-04T22:00:00Z\tsubtree\t-\tRun the full suite per lane?\tNo: once per wave.\tunread')"
  assert_eq "$want" "$OUT" "exact §6 rows: fleet first, superseded #1 absent, read state per cursor"
  r live --seat meta:engine-lane --unread
  assert_eq "$(printf '%s\n' "$want" | sed -n 2p)" "$OUT" "--unread filters to the unread rows (S4)"
  r unread --seat meta:engine-lane
  assert_eq "$(printf '%s\n' "$want" | sed -n 2p)" "$OUT" "unread is the same as live --unread"
}

# ---------------------------------------------------------------- the shared resolver (lib.sh)

test_fleet_live_chain_prints_top_down_and_folds_case() {
  local out rc
  out=$(env $SCRUB FLEET_TEST_SEAM=1 FLEET_LIVE_PANES="$FIX/tree.txt" "$BASH_BIN" -c 'source "$1"; fleet_live_chain META:Engine-Lane' _ "$RULINGS_LIB" 2>/dev/null); rc=$?
  assert_eq 0 "$rc" "chain exit 0"
  assert_eq "$(printf 'manager:director %%1\nmanager:meta %%32\nmeta:engine %%27\nmeta:engine-lane %%90')" "$out" "chain top down, tree spelling"
}

# ---------------------------------------------------------------- write rights

test_owner_writes_its_own_section() {
  IN=$'question: Run the full suite per lane?\nruling: No: once per wave.\nsource: test' r TMUX_PANE=%32 write
  assert_eq 0 "$RC" "owner write exit 0 ($ERR)"
  assert_eq "manager:meta#1" "$OUT" "prints the new id"
  has "owner: manager:meta" "$(cat "$RD/manager:meta.md")" "section created with its owner line"
  has "by: manager:meta %32" "$(cat "$RD/manager:meta.md")" "by: is the live seat and pane"
  r live --seat meta:engine-lane
  has "${TAB}manager:meta#1${TAB}" "$OUT" "the written ruling reaches the lane seat"
}

test_sibling_manager_is_refused_and_writes_nothing() {
  plant manager:meta manager:meta 1 planted planted-ruling
  cp "$RD/manager:meta.md" "$FIX/before"
  IN=$'question: q\nruling: r\nsource: test' r TMUX_PANE=%40 write --section manager:meta
  assert_eq 4 "$RC" "sibling manager: exit 4"
  has "does not own section 'manager:meta'" "$ERR" "refusal names the section"
  cmp -s "$FIX/before" "$RD/manager:meta.md" && pass "section bytes unchanged" || fail "section bytes unchanged"
}

test_worker_gets_a_proposal_and_nothing_is_written() {
  IN=$'question: May I skip the suite?\nruling: Yes, for docs.\nsource: chat:now' r TMUX_PANE=%41 write
  assert_eq 4 "$RC" "worker: exit 4"
  assert_file_not_exists "$RD/core:ui.md" "no worker section created"
  has "to: manager:core" "$OUT" "the proposal is addressed to the worker's manager"
  has 'ask: Skill(ask, "May I skip the suite? (proposes a ruling for manager:core) --to manager:core")' "$OUT" "a ready ask for the /ask skill"
  hasnt "engine ask new" "$OUT" "no hand-run engine ask new (spec §5)"
  assert_eq "proposes-ruling: manager:core" "$(printf '%s\n' "$OUT" | sed -n '/^body:$/{n;p;}')" "first body line names the target section"
  has "ruling: Yes, for docs." "$OUT" "the proposal carries the proposed ruling"
  [ -z "$(ls -A "$RD")" ] && pass "nothing written in the rulings folder" || fail "nothing written" "" "$(ls -A "$RD")"
}

# ---------------------------------------------------------------- supersession

test_supersession_appends_and_never_rewrites() {
  IN=$'question: q1\nruling: first\nsource: test' r TMUX_PANE=%32 write
  cp "$RD/manager:meta.md" "$FIX/before"
  IN=$'question: q1\nruling: second\nsource: test\nsupersedes: manager:meta#1' r TMUX_PANE=%32 write
  assert_eq 0 "$RC" "supersession exit 0 ($ERR)"
  local size; size=$(wc -c < "$FIX/before" | tr -d ' ')
  head -c "$size" "$RD/manager:meta.md" | cmp -s - "$FIX/before" && pass "bytes before are a prefix of the bytes after" || fail "prefix preserved"
  [ "$(wc -c < "$RD/manager:meta.md" | tr -d ' ')" -gt "$size" ] && pass "file grew" || fail "file grew"
  r live --seat meta:engine
  hasnt "${TAB}manager:meta#1${TAB}" "$OUT" "superseded #1 is no longer live"
  has "${TAB}manager:meta#2${TAB}" "$OUT" "#2 is live"
}

test_superseded_ruling_stays_readable_and_names_its_replacement() {
  IN=$'question: q1\nruling: first\nsource: test' r TMUX_PANE=%32 write
  IN=$'question: q1\nruling: second\nsource: test\nsupersedes: manager:meta#1' r TMUX_PANE=%32 write
  local f; f=$(cat "$RD/manager:meta.md")
  has $'## manager:meta#1\nat:' "$f" "the original block is still there"
  has "ruling: first" "$f" "the original ruling text is still there"
  has $'## manager:meta#1 superseded' "$f" "a superseded marker follows"
  has "superseded-by: manager:meta#2" "$f" "the marker names its replacement"
  IN=$'question: q1\nruling: third\nsource: test\nsupersedes: manager:meta#1' r TMUX_PANE=%32 write
  assert_eq 1 "$RC" "superseding a dead ruling is refused"
}

# ---------------------------------------------------------------- conflicts (Q1)

test_higher_rung_wins_and_the_repeat_warns() {
  plant fleet manager:director 1 "Run the full suite per lane?" "Yes." fleet
  IN=$'question: run the FULL suite  per lane?\nruling: No.\nsource: test' r TMUX_PANE=%32 write
  assert_eq 0 "$RC" "the repeat is still written"
  has "warning: fleet#1" "$ERR" "the write warns, naming the ancestor ruling"
  r live --seat meta:engine
  assert_eq "fleet#1" "$(printf '%s\n' "$OUT" | awk -F'\t' 'NR == 1 { print $2 }')" "the higher rung is listed first"
  IN=$'question: Something new\nruling: x\nsource: test' r TMUX_PANE=%32 write
  hasnt "warning" "$ERR" "no warning for a question no ancestor ruled (control)"
}

# ---------------------------------------------------------------- read cursor (Q2)

test_unread_and_mark_read_without_touching_anything_else() {
  plant fleet manager:director 1 fq fr fleet
  plant manager:meta manager:meta 1 mq mr
  r unread --seat meta:engine
  assert_eq 2 "$(printf '%s\n' "$OUT" | awk 'NF' | wc -l | tr -d ' ')" "two unread"
  (cd "$FIX" && find . -type f | sort | xargs cksum) > "$FIX/../ck.before.$$"
  r TMUX_PANE=%27 HOME="$FIX/home" mark-read --seat meta:engine
  assert_eq 0 "$RC" "mark-read exit 0 ($ERR)"
  (cd "$FIX" && find . -type f | sort | xargs cksum) > "$FIX/../ck.after.$$"
  local changed; changed=$(diff "$FIX/../ck.before.$$" "$FIX/../ck.after.$$" | awk '/^>/ { print $4 }' | grep -v '^./err$' | tr '\n' ' ')
  rm -f "$FIX/../ck.before.$$" "$FIX/../ck.after.$$"
  assert_eq "./rulings/.reads/meta:engine.tsv " "$changed" "the cursor is the only file written (no brake, no other store)"
  r unread --seat meta:engine
  assert_empty "$OUT" "nothing unread after mark-read"
  r live --seat meta:engine
  hasnt "${TAB}unread" "$OUT" "live shows every row read"
  plant manager:meta manager:meta 2 mq2 mr2
  r unread --seat meta:engine
  has "${TAB}manager:meta#2${TAB}" "$OUT" "a later ruling is unread again"
  r TMUX_PANE=%32 mark-read --seat meta:engine
  assert_eq 4 "$RC" "another seat may not advance meta:engine's cursor"
}

# ---------------------------------------------------------------- fail closed

test_unreadable_tree_is_unknown_exit_2() {
  plant manager:meta manager:meta 1 planted planted-ruling
  r FLEET_LIVE_PANES="$FIX/no-such-tree" live --seat meta:engine
  assert_eq 2 "$RC" "unreadable tree: exit 2"
  assert_eq unknown "$OUT" "unreadable tree: stdout unknown, never an empty list"
  printf 'meta:engine %%27 manager:gone\n' > "$FIX/tree.txt"
  r live --seat meta:engine
  assert_eq 2 "$RC" "a parent no pane carries: exit 2"
  assert_eq unknown "$OUT" "broken rung: unknown"
}

test_unreadable_or_missing_rulings_is_unknown_exit_2() {
  plant manager:meta manager:meta 1 planted planted-ruling
  chmod 000 "$RD/manager:meta.md"
  r live --seat meta:engine
  chmod 644 "$RD/manager:meta.md"
  assert_eq 2 "$RC" "unreadable section: exit 2"
  assert_eq unknown "$OUT" "unreadable section: unknown"
  printf 'garbage\n' > "$RD/manager:meta.md"
  r live --seat meta:engine
  assert_eq 2 "$RC" "malformed section: exit 2"
  r RULINGS_DIR="$FIX/none" live --seat meta:engine
  assert_eq 2 "$RC" "missing rulings folder: exit 2"
  assert_eq unknown "$OUT" "missing rulings folder: unknown"
}

test_two_panes_exit_4_and_absent_seat_exit_5() {
  printf 'meta:engine %%99 manager:meta\n' >> "$FIX/tree.txt"
  r live --seat meta:engine
  assert_eq 4 "$RC" "seat carried by two panes: exit 4"
  assert_eq unknown "$OUT" "two panes: unknown"
  r live --seat meta:engine-lane
  assert_eq 4 "$RC" "a rung carried by two panes: exit 4"
  r live --seat meta:nobody
  assert_eq 5 "$RC" "absent seat: exit 5"
  assert_eq unknown "$OUT" "absent seat: unknown"
}

test_seams_are_ignored_without_the_marker() {
  plant manager:meta manager:meta 1 planted planted-ruling
  printf '%s\n' "" "## manager:meta#2" "at: x" "by: core:ui %41" "scope: subtree" "question: q" "ruling: stray" "source: t" >> "$RD/manager:meta.md"
  r verify
  assert_eq 1 "$RC" "control: with the marker, verify reads the seam and flags the stray block"
  has "NOT-OWNER manager:meta manager:meta#2" "$OUT" "control: the stray block is named"
  rn RULINGS_DIR="$RD" HOME="$FIX/home" verify
  has "ignoring a test seam (RULINGS_DIR)" "$ERR" "without the marker RULINGS_DIR is ignored, and said so"
  hasnt "NOT-OWNER" "$OUT" "without the marker the fixture is not read"
  cp "$RD/manager:meta.md" "$FIX/before"
  IN=$'question: q\nruling: r\nsource: t' rn RULINGS_DIR="$RD" FLEET_LIVE_PANES="$FIX/tree.txt" TMUX_PANE=%32 HOME="$FIX/home" write
  assert_eq 2 "$RC" "without the marker the stub tree is not an identity: refused"
  has "ignoring a test seam (FLEET_LIVE_PANES)" "$ERR" "the tree seam is ignored, and said so"
  cmp -s "$FIX/before" "$RD/manager:meta.md" && pass "nothing written to the fixture" || fail "nothing written to the fixture"
  rn FLEET_LIVE_PANES="$FIX/tree.txt" live --seat meta:engine
  assert_eq 2 "$RC" "live without the marker: the stub tree is ignored (no tmux here) -> exit 2"
}

# ---------------------------------------------------------------- field hygiene

test_tab_or_newline_in_a_field_is_refused() {
  IN=$'question: a\tb\nruling: r\nsource: t' r TMUX_PANE=%32 write
  assert_eq 1 "$RC" "a tab is refused"
  IN=$'question: first line\nsecond line of the question\nruling: r\nsource: t' r TMUX_PANE=%32 write
  assert_eq 1 "$RC" "a value spanning lines is refused"
  IN=$'question: q\nruling: r\nsource: t\nscope: seats: a, b' r TMUX_PANE=%32 write
  assert_eq 1 "$RC" "a narrower scope is refused (Q6: subtree only)"
  assert_file_not_exists "$RD/manager:meta.md" "nothing written by any refused write"
}

# ---------------------------------------------------------------- concurrency

test_concurrent_appends_stay_whole() {
  local i w
  for w in a b; do
    (
      for i in 1 2 3 4 5 6 7 8 9 10; do
        printf 'question: %s-%s\nruling: r\nsource: t\n' "$w" "$i" | env $SCRUB FLEET_TEST_SEAM=1 \
          FLEET_LIVE_PANES="$FIX/tree.txt" RULINGS_DIR="$RD" RULINGS_LIB="$RULINGS_LIB" TMUX_PANE=%32 \
          "$BASH_BIN" "$RULINGS_SH" write >/dev/null 2>>"$FIX/cerr"
      done
    ) &
  done
  wait
  local f="$RD/manager:meta.md"
  assert_eq 20 "$(grep -c '^## manager:meta#' "$f")" "twenty blocks"
  assert_eq 20 "$(grep '^## manager:meta#' "$f" | sort -u | wc -l | tr -d ' ')" "twenty distinct ids"
  assert_eq "$(seq 1 20 | tr '\n' ' ')" "$(grep '^## manager:meta#' "$f" | sed 's/.*#//' | tr '\n' ' ')" "ids 1..20 in file order"
  local whole
  whole=$(awk '/^## /{ if (h) print h, c; h=$2; c=0; next } h && NF { c++ } END { print h, c }' "$f" | awk '$2 != 6' )
  assert_empty "$whole" "every block has its six lines (at by scope question ruling source)"
  r live --seat meta:engine
  assert_eq 20 "$(printf '%s\n' "$OUT" | awk 'NF' | wc -l | tr -d ' ')" "the reader parses all twenty"
}

test_runs_under_bash_3_2() {
  local v; v=$("$BASH_BIN" -c 'echo $BASH_VERSION')
  case "$v" in 3.2*) pass "suite ran under bash $v" ;; *) skip "bash 3.2" "BASH_BIN is $v" ;; esac
}

# ================================================================ fix round 1 (review findings)

# stub_engine — a copy of rulings.sh + lib.sh whose own user-info.sh points at $FIX/data, and a
# PATH-stub tmux answering from $FIX/tree.txt. This is the PRODUCTION path (no seam marker): the
# folder comes from the script's own user-info.sh, the tree from "tmux".
stub_engine() {
  mkdir -p "$FIX/eng" "$FIX/bin" "$FIX/data"
  cp "$RULINGS_SH" "$FIX/eng/rulings.sh"; cp "$RULINGS_LIB" "$FIX/eng/lib.sh"
  cat > "$FIX/eng/user-info.sh" <<EOF
#!/bin/bash
case "\$1" in data-root) echo "$FIX/data" ;; username) echo u ;; esac
EOF
  cat > "$FIX/bin/tmux" <<EOF
#!/bin/bash
while [ \$# -gt 0 ]; do case "\$1" in -L|-S) shift 2 ;; *) break ;; esac; done
case "\$1" in
  list-panes) cat "$FIX/tree.txt" ;;
  display) pane=""; shift; while [ \$# -gt 0 ]; do case "\$1" in -t) pane="\$2"; shift 2 ;; *) shift ;; esac; done
           /usr/bin/awk -v p="\$pane" '\$2 == p { print \$1 "|" \$3 }' "$FIX/tree.txt" ;;
esac
EOF
  chmod +x "$FIX/eng/user-info.sh" "$FIX/bin/tmux" "$FIX/eng/rulings.sh"
  cat > "$FIX/forged-lib.sh" <<EOF
source "$FIX/eng/lib.sh"
echo FORGED-LIB-LOADED >&2
fleet_self() { echo manager:director; }
fleet_live_seat() { echo "manager:director %1 -"; }
fleet_live_children() { echo manager:meta; }
EOF
}

test_M4_forged_lib_without_the_marker_cannot_write_fleet_md() {
  stub_engine
  local prod="$FIX/data/u/assets/fleet/rulings"
  # Control: the forged lib DOES impersonate when the marker is on, so the instrument can see it.
  IN=$'question: q\nruling: forged\nsource: t' OUT=$(printf '%s' "$IN" | env $SCRUB FLEET_TEST_SEAM=1 RULINGS_LIB="$FIX/forged-lib.sh" \
      RULINGS_DIR="$FIX/ctl" PATH="$FIX/bin:$PATH" FLEET_TMUX_SOCKET=stub TMUX_PANE=%41 "$BASH_BIN" "$FIX/eng/rulings.sh" write --section fleet 2>&1)
  [ -f "$FIX/ctl/fleet.md" ] && pass "control: with the marker the forged lib writes fleet.md" || fail "control: forged lib honoured under the marker" "" "$OUT"
  # The case: no marker. The seat is core:ui (a worker) on the stub tmux tree.
  OUT=$(printf 'question: q\nruling: forged\nsource: t\n' | env $SCRUB RULINGS_LIB="$FIX/forged-lib.sh" PATH="$FIX/bin:$PATH" \
      FLEET_TMUX_SOCKET=stub TMUX_PANE=%41 "$BASH_BIN" "$FIX/eng/rulings.sh" write --section fleet 2>"$FIX/err"); RC=$?
  ERR=$(cat "$FIX/err")
  has "ignoring a test seam (RULINGS_LIB)" "$ERR" "RULINGS_LIB without the marker is ignored, and said so"
  hasnt "FORGED-LIB-LOADED" "$ERR" "the forged lib is never sourced"
  assert_eq 4 "$RC" "the worker's fleet write is proposal-only"
  has "proposal: nothing was written" "$OUT" "the worker gets a proposal"
  assert_file_not_exists "$prod/fleet.md" "nothing written to fleet.md"
}

test_M1_eight_writers_never_share_an_id() {
  local trial w i dups
  for trial in 1 2 3; do
    rm -rf "$RD"; mkdir -p "$RD"
    for w in 1 2 3 4 5 6 7 8; do
      (
        for i in 1 2 3; do
          printf 'question: w%s-%s\nruling: r\nsource: t\n' "$w" "$i" | env $SCRUB FLEET_TEST_SEAM=1 \
            FLEET_LIVE_PANES="$FIX/tree.txt" RULINGS_DIR="$RD" RULINGS_LIB="$RULINGS_LIB" TMUX_PANE=%32 \
            "$BASH_BIN" "$RULINGS_SH" write >/dev/null 2>>"$FIX/cerr"
        done
      ) &
    done
    wait
    dups=$(grep '^## manager:meta#[0-9]*$' "$RD/manager:meta.md" | sort | uniq -d | tr '\n' ' ')
    assert_empty "$dups" "trial $trial: no duplicate headings among 8 writers x 3"
    assert_eq 24 "$(grep -c '^## manager:meta#[0-9]*$' "$RD/manager:meta.md")" "trial $trial: 24 rulings written"
  done
}

test_M1_parser_withholds_a_duplicate_id() {
  plant manager:meta manager:meta 1 one r1
  plant manager:meta manager:meta 2 two r2
  plant manager:meta manager:meta 2 two-again r2b
  r live --seat meta:engine
  assert_eq 3 "$RC" "a repeated id is a partial read (exit 3), never accepted"
  hasnt "${TAB}manager:meta#2${TAB}" "$OUT" "neither copy of the repeated id is served"
  has "${TAB}manager:meta#1${TAB}" "$OUT" "the section's other rulings are served"
  has "manager:meta#2 appears twice" "$ERR" "stderr names the block"
}

test_S1_lock_without_owner_is_reclaimed_live_lock_is_not() {
  mkdir -p "$RD/.lock/manager:meta"
  touch -t 202001010000 "$RD/.lock/manager:meta"
  IN=$'question: q\nruling: r\nsource: t' r TMUX_PANE=%32 RULINGS_LOCK_TRIES=40 write
  assert_eq 0 "$RC" "an old lock with no owner file is reclaimed ($ERR)"
  has "breaking a stale lock" "$ERR" "the break is announced"
  # A lock held by a live process (this test shell, with its real start time) is never broken.
  mkdir -p "$RD/.lock/manager:meta"
  # The token's start time is read as rulings.sh reads it: C locale, UTC (M-R3-2).
  local st; st=$(LC_ALL=C LANG=C TZ=UTC0 ps -o lstart= -p $$ | tr -s ' ' | sed 's/^ //;s/ $//')
  printf '%s %s\n' "$$" "$st" > "$RD/.lock/manager:meta/owner"
  touch -t 202001010000 "$RD/.lock/manager:meta"
  IN=$'question: q2\nruling: r\nsource: t' r TMUX_PANE=%32 RULINGS_LOCK_TRIES=10 write
  assert_eq 2 "$RC" "a live holder's lock times out the writer"
  assert_eq "$$ $st" "$(cat "$RD/.lock/manager:meta/owner" 2>/dev/null)" "the live holder's lock is untouched"
  # The same pid with a different start time is a reused pid: the holder is gone.
  printf '%s %s\n' "$$" "Thu Jan  1 00:00:00 1970" > "$RD/.lock/manager:meta/owner"
  IN=$'question: q3\nruling: r\nsource: t' r TMUX_PANE=%32 RULINGS_LOCK_TRIES=40 write
  assert_eq 0 "$RC" "a reused pid does not wedge the section"
}

test_M2_supersedes_and_withdraws_take_exactly_one_id() {
  IN=$'question: q1\nruling: first\nsource: t' r TMUX_PANE=%32 write
  IN=$'question: q2\nruling: second\nsource: t' r TMUX_PANE=%32 write
  cp "$RD/manager:meta.md" "$FIX/before"
  IN=$'withdraws: manager:meta#1 \nreason: x' r TMUX_PANE=%32 write
  assert_eq 1 "$RC" "a trailing space in withdraws is refused"
  IN=$'question: q\nruling: r\nsource: t\nsupersedes: manager:meta#1 manager:meta#2' r TMUX_PANE=%32 write
  assert_eq 1 "$RC" "two ids in supersedes are refused"
  IN=$'question: q\nruling: r\nsource: t\nsupersedes: *' r TMUX_PANE=%32 write
  assert_eq 1 "$RC" "a glob in supersedes is refused"
  IN=$'question: q\nruling: r\nsource: t\nsupersedes: manager:core#1' r TMUX_PANE=%32 write
  assert_eq 1 "$RC" "another section's id is refused"
  IN=$'question: q\nruling: r\nsource: t\nsupersedes: manager:meta#01' r TMUX_PANE=%32 write
  assert_eq 1 "$RC" "a zero-padded id is refused"
  cmp -s "$FIX/before" "$RD/manager:meta.md" && pass "no refused write touched the section" || fail "no refused write touched the section"
  r live --seat meta:engine
  assert_eq 0 "$RC" "the section still reads cleanly"
}

test_M2_a_bad_block_withholds_its_ids_and_serves_the_rest() {
  plant manager:meta manager:meta 1 one r1
  plant manager:meta manager:meta 2 two r2
  printf '%s\n' "" "## manager:meta#1  withdrawn" "at: x" "by: manager:meta %32" "reason: x" >> "$RD/manager:meta.md"
  plant fleet manager:director 1 fq fr fleet
  r live --seat meta:engine-lane
  assert_eq 3 "$RC" "a bad block is a partial read, not unknown"
  has "${TAB}manager:meta#2${TAB}" "$OUT" "the section's other ruling is served"
  hasnt "${TAB}manager:meta#1${TAB}" "$OUT" "the id the bad heading names is withheld"
  has "fleet${TAB}fleet#1" "$OUT" "the other sections are served"
  has 'unreadable heading "## manager:meta#1  withdrawn" (withholds manager:meta#1)' "$ERR" "stderr names the block and what it withholds"
  IN=$'question: q3\nruling: r3\nsource: t' r TMUX_PANE=%32 write
  assert_eq 0 "$RC" "the owner can still write to the section"
  assert_eq "manager:meta#3" "$OUT" "the next id passes every id any heading names"
}

# shim_awk — a PATH awk that fails on its $FAILK-th call (counted in $FIX/awkn).
shim_awk() {
  mkdir -p "$FIX/shim"
  cat > "$FIX/shim/awk" <<EOF
#!/bin/bash
c=\$(cat "$FIX/awkn" 2>/dev/null || echo 0); c=\$((c + 1)); echo "\$c" > "$FIX/awkn"
[ "\$c" = "\${FAILK:-0}" ] && exit 2
exec /usr/bin/awk "\$@"
EOF
  chmod +x "$FIX/shim/awk"
}

test_M3_any_awk_failure_is_unknown_never_a_short_list() {
  plant fleet manager:director 1 fq fr fleet
  plant manager:meta manager:meta 1 mq mr
  mkdir -p "$RD/.reads"; printf 'fleet\t1\nmanager:meta\t0\n' > "$RD/.reads/meta:engine.tsv"
  shim_awk
  rm -f "$FIX/awkn"
  r PATH="$FIX/shim:$PATH" FAILK=0 live --seat meta:engine
  local base="$OUT" calls k bad=""
  calls=$(cat "$FIX/awkn")
  assert_eq 2 "$(printf '%s\n' "$base" | awk 'NF' | wc -l | tr -d ' ')" "baseline: two rows through the shim"
  [ "${calls:-0}" -ge 3 ] && pass "the shim saw $calls awk calls" || fail "the shim saw the awk calls" ">= 3" "$calls"
  k=1
  while [ "$k" -le "$calls" ]; do
    rm -f "$FIX/awkn"
    r PATH="$FIX/shim:$PATH" FAILK="$k" live --seat meta:engine
    if [ "$OUT" != "$base" ] && { [ "$RC" != 2 ] || [ "$OUT" != unknown ]; }; then bad="$bad k=$k(rc=$RC,out=$(printf '%s' "$OUT" | wc -l | tr -d ' ')lines)"; fi
    k=$((k + 1))
  done
  assert_empty "$bad" "failing any one awk call gives either the full list or exit 2 unknown"
}

test_S2_mark_read_through_leaves_a_later_ruling_unread() {
  plant manager:meta manager:meta 1 mq mr
  r unread --seat meta:engine
  has "${TAB}manager:meta#1${TAB}" "$OUT" "the seat prints #1"
  plant manager:meta manager:meta 2 mq2 mr2
  r TMUX_PANE=%27 mark-read --seat meta:engine --through manager:meta=1
  assert_eq 0 "$RC" "mark-read --through exit 0 ($ERR)"
  r unread --seat meta:engine
  has "${TAB}manager:meta#2${TAB}" "$OUT" "the ruling written after the print stays unread"
  hasnt "${TAB}manager:meta#1${TAB}" "$OUT" "the printed ruling is read"
  r TMUX_PANE=%27 mark-read --seat meta:engine --through manager:core=5
  assert_eq 1 "$RC" "--through refuses a section off the chain"
}

test_S3_two_roots_cannot_claim_fleet_md() {
  printf '%s\n' 'rogue:boss %9 -' 'rogue:kid %10 rogue:boss' >> "$FIX/tree.txt"
  IN=$'question: q\nruling: mine\nsource: t' r TMUX_PANE=%9 write --section fleet
  assert_eq 4 "$RC" "a second root with children may not create fleet.md"
  assert_file_not_exists "$RD/fleet.md" "fleet.md not created"
  IN=$'question: q\nruling: mine\nsource: t' r TMUX_PANE=%1 write --section fleet
  assert_eq 4 "$RC" "nor may the director while the top is ambiguous"
  hasnt "--to operator" "$OUT" "a root seat's proposal never goes --to operator"
  has "to: none" "$OUT" "a root seat is told there is no manager to propose to"
}

test_S6_worker_under_an_absent_manager_still_gets_its_proposal() {
  printf '%s\n' 'manager:director %1 -' 'core:ui %41 manager:core' > "$FIX/tree.txt"
  IN=$'question: q\nruling: r\nsource: t' r TMUX_PANE=%41 write
  assert_eq 4 "$RC" "refused, not unknown"
  has "to: manager:core" "$OUT" "the proposal names the absent manager"
  has "proposes-ruling: manager:core" "$OUT" "with its proposes-ruling line"
}

test_N2_a_section_name_holding_a_newline_is_refused() {
  IN=$'question: q\nruling: r\nsource: t' r TMUX_PANE=%32 write --section $'manager:meta\nx'
  assert_eq 1 "$RC" "a newline in --section is refused as a name"
}

test_N7_exported_functions_cannot_stand_in() {
  plant manager:meta manager:meta 1 mq mr
  r live --seat meta:engine
  local base="$OUT"
  OUT=$(env $SCRUB FLEET_TEST_SEAM=1 FLEET_LIVE_PANES="$FIX/tree.txt" RULINGS_DIR="$RD" RULINGS_LIB="$RULINGS_LIB" \
    "$BASH_BIN" -c 'command() { echo HIJACK; }; awk() { echo HIJACK; }; sed() { echo HIJACK; }; export -f command awk sed; "$0" "$1" live --seat meta:engine' \
    "$BASH_BIN" "$RULINGS_SH" 2>"$FIX/err")
  assert_eq "$base" "$OUT" "rulings.sh: exported command/awk/sed functions do not change the output"
  OUT=$(env $SCRUB FLEET_TEST_SEAM=1 FLEET_LIVE_PANES="$FIX/tree.txt" \
    "$BASH_BIN" -c 'command() { echo HIJACK; }; awk() { echo HIJACK; }; export -f command awk; "$0" "$1" live-children manager:meta' \
    "$BASH_BIN" "$TREE_ROOT/scripts/fleet.sh" 2>"$FIX/err")
  assert_eq "meta:engine" "$OUT" "fleet.sh: exported command/awk functions do not change live-children"
}

# ================================================================ fix round 2 (Round 2 check)

test_R1_a_holder_ps_cannot_read_keeps_its_lock() {
  IN=$'question: q0\nruling: r\nsource: t' r TMUX_PANE=%32 write
  sleep 60 & local holder=$!
  mkdir -p "$RD/.lock/manager:meta" "$FIX/psbin"
  printf '%s %s\n' "$holder" "Mon Jan  1 00:00:00 2024" > "$RD/.lock/manager:meta/owner"
  cat > "$FIX/psbin/ps" <<EOF
#!/bin/bash
case " \$* " in *" $holder "*) exit 1 ;; esac
exec /bin/ps "\$@"
EOF
  chmod +x "$FIX/psbin/ps"
  sleep 1.2
  cp "$RD/manager:meta.md" "$FIX/before"
  IN=$'question: q1\nruling: r\nsource: t' r PATH="$FIX/psbin:$PATH" TMUX_PANE=%32 RULINGS_LOCK_TRIES=20 write
  assert_eq 2 "$RC" "the writer waits out its budget and gives up (exit 2)"
  hasnt "breaking a stale lock" "$ERR" "a holder ps cannot read is not called dead"
  assert_eq "$holder Mon Jan  1 00:00:00 2024" "$(cat "$RD/.lock/manager:meta/owner" 2>/dev/null)" "the holder's lock is untouched"
  cmp -s "$FIX/before" "$RD/manager:meta.md" && pass "no write landed over the held lock" || fail "no write landed over the held lock"
  # Past the age threshold the same lock is broken: it is far older than any write.
  touch -t 202001010000 "$RD/.lock/manager:meta"
  IN=$'question: q2\nruling: r\nsource: t' r PATH="$FIX/psbin:$PATH" TMUX_PANE=%32 RULINGS_LOCK_TRIES=20 write
  assert_eq 0 "$RC" "an unreadable holder's lock older than the threshold is broken"
  kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
}

test_R2_verify_flags_a_marker_without_a_valid_by() {
  plant manager:meta manager:meta 1 one r1
  plant manager:meta manager:meta 2 two r2
  printf '%s\n' "" "## manager:meta#1 withdrawn" "reason: x" >> "$RD/manager:meta.md"
  r verify
  assert_eq 1 "$RC" "verify exits non-zero on a marker with no by:"
  has "manager:meta#1 withdrawn" "$OUT" "verify names the marker"
  printf '%s\n' "" "## manager:meta#2 superseded" "at: x" "by: core:ui %41" "superseded-by: manager:meta#9" >> "$RD/manager:meta.md"
  r verify
  has "manager:meta#2 superseded" "$OUT" "verify names a marker whose by: is not the owner"
}

test_R3_a_partial_read_ends_with_a_trailer() {
  plant manager:meta manager:meta 1 one r1
  plant manager:meta manager:meta 2 two r2
  r live --seat meta:engine
  assert_eq 0 "$RC" "clean read: exit 0"
  hasnt "# partial" "$OUT" "clean read: no trailer"
  printf '%s\n' "" "## manager:meta#1  withdrawn" "at: x" "by: manager:meta %32" "reason: x" >> "$RD/manager:meta.md"
  r live --seat meta:engine
  assert_eq 3 "$RC" "damaged block: exit 3"
  assert_eq "# partial: manager:meta#1" "$(printf '%s\n' "$OUT" | tail -n 1)" "damaged block: stdout ends with the trailer naming the withheld ids"
  r unread --seat meta:engine
  assert_eq "# partial: manager:meta#1" "$(printf '%s\n' "$OUT" | tail -n 1)" "the trailer rides unread too"
}

test_R4_an_exported_unset_cannot_defeat_the_guard() {
  plant manager:meta manager:meta 1 mq mr
  r live --seat meta:engine
  local base="$OUT"
  OUT=$(env $SCRUB FLEET_TEST_SEAM=1 FLEET_LIVE_PANES="$FIX/tree.txt" RULINGS_DIR="$RD" RULINGS_LIB="$RULINGS_LIB" \
    "$BASH_BIN" -c 'unset() { :; }; builtin() { :; }; awk() { echo HIJACK; }; command() { echo HIJACK; }; export -f unset builtin awk command; "$0" "$1" live --seat meta:engine' \
    "$BASH_BIN" "$RULINGS_SH" 2>"$FIX/err"); RC=$?
  assert_eq 0 "$RC" "rulings.sh runs with exported unset/builtin/awk/command functions"
  assert_eq "$base" "$OUT" "rulings.sh: the output is unchanged"
  printf 'awk() { echo HIJACK; }\n' > "$FIX/bash_env"
  OUT=$(env $SCRUB FLEET_TEST_SEAM=1 FLEET_LIVE_PANES="$FIX/tree.txt" RULINGS_DIR="$RD" RULINGS_LIB="$RULINGS_LIB" BASH_ENV="$FIX/bash_env" \
    "$BASH_BIN" "$RULINGS_SH" live --seat meta:engine 2>"$FIX/err"); RC=$?
  assert_eq "$base" "$OUT" "rulings.sh: a BASH_ENV defining awk does not change the output"
  OUT=$(env $SCRUB FLEET_TEST_SEAM=1 FLEET_LIVE_PANES="$FIX/tree.txt" \
    "$BASH_BIN" -c 'unset() { :; }; builtin() { :; }; awk() { echo HIJACK; }; command() { echo HIJACK; }; export -f unset builtin awk command; "$0" "$1" live-children manager:meta' \
    "$BASH_BIN" "$TREE_ROOT/scripts/fleet.sh" 2>"$FIX/err"); RC=$?
  assert_eq "meta:engine" "$OUT" "fleet.sh: exported unset/builtin/awk/command do not change live-children"
}

# ================================================================ fix round 3 (Round 3 check)

# bounded <secs> <cmd…> — run cmd in its own process group; past <secs> kill the whole group and
# return 124, so a relaunch loop fails its case instead of hanging the suite or leaving children.
bounded() {
  perl -e 'my $t = shift; my $p = fork; die "fork: $!" unless defined $p;
    if (!$p) { setpgrp(0, 0); exec @ARGV or exit 127 }
    $SIG{ALRM} = sub { kill "KILL", -$p; waitpid($p, 0); exit 124 }; alarm $t;
    waitpid($p, 0); exit($? & 127 ? 128 + ($? & 127) : $? >> 8)' "$@"
}

test_M_R3_1_a_value_holding_a_guard_line_relaunches_once_then_refuses() {
  plant manager:meta manager:meta 1 mq mr
  local v
  for v in $'hello\nBASH_ENV=x' $'x\nBASH_FUNC_y=z'; do
    OUT=$(bounded 20 env $SCRUB FLEET_TEST_SEAM=1 FLEET_LIVE_PANES="$FIX/tree.txt" RULINGS_DIR="$RD" \
      RULINGS_LIB="$RULINGS_LIB" NOTES="$v" "$BASH_BIN" "$RULINGS_SH" live --seat meta:engine 2>"$FIX/err" </dev/null); RC=$?
    ERR=$(cat "$FIX/err")
    assert_eq 2 "$RC" "rulings.sh: a value holding a guard line ends at exit 2 (124 means it looped until killed)"
    assert_eq unknown "$OUT" "rulings.sh: the refusal prints unknown"
    has "after one clean relaunch" "$ERR" "rulings.sh: stderr says why it refused"
    OUT=$(bounded 20 env $SCRUB FLEET_TEST_SEAM=1 FLEET_LIVE_PANES="$FIX/tree.txt" NOTES="$v" \
      "$BASH_BIN" "$TREE_ROOT/scripts/fleet.sh" live-children manager:meta 2>"$FIX/err" </dev/null); RC=$?
    assert_eq 2 "$RC" "fleet.sh: a value holding a guard line ends at exit 2 (124 means it looped until killed)"
    assert_eq unknown "$OUT" "fleet.sh: the refusal prints unknown"
  done
  # Controls: a real imported function still gets its one relaunch and the body runs; a marker
  # the caller set in a clean environment changes nothing.
  OUT=$(bounded 20 env $SCRUB FLEET_TEST_SEAM=1 FLEET_LIVE_PANES="$FIX/tree.txt" RULINGS_DIR="$RD" RULINGS_LIB="$RULINGS_LIB" \
    "$BASH_BIN" -c 'awk() { echo HIJACK; }; export -f awk; "$0" "$1" live --seat meta:engine' \
    "$BASH_BIN" "$RULINGS_SH" 2>"$FIX/err" </dev/null); RC=$?
  assert_eq 0 "$RC" "control: a real exported awk is stripped by the one relaunch"
  has "${TAB}manager:meta#1${TAB}" "$OUT" "control: the body ran and served the row"
  r RULINGS_GUARD_RAN=1 live --seat meta:engine
  assert_eq 0 "$RC" "control: a preset marker in a clean environment is harmless"
}

# A date shim that stalls the clock read a write makes after it has read the next id, while it
# holds the lock: the slow write on a loaded machine, made deterministic.
slow_date() {
  mkdir -p "$FIX/slowbin"
  cat > "$FIX/slowbin/date" <<'EOF'
#!/bin/bash
case "$1" in -u) sleep "${STALL:-4}" ;; esac
exec /bin/date "$@"
EOF
  chmod +x "$FIX/slowbin/date"
}

test_M_R3_2_a_holder_in_another_zone_or_locale_keeps_its_lock() {
  slow_date
  local arm a_env b_tz apid arc i ids
  # "other": A and B a day apart in zone (TZ=ZZZ-14 vs ZZZ+11, so the arm discriminates on any
  # machine). "locale": same zone, A in de_DE (it discriminates only where that locale is
  # installed; elsewhere ps falls back to C). "same": the control, both alike.
  for arm in other locale same; do
    rm -rf "$RD"; mkdir -p "$RD"
    plant manager:meta manager:meta 1 q0 r0
    case "$arm" in
      other)  a_env="TZ=ZZZ-14"; b_tz="ZZZ+11" ;;
      locale) a_env="LC_ALL=de_DE.UTF-8"; b_tz="ZZZ-14" ;;
      same)   a_env="TZ=ZZZ-14"; b_tz="ZZZ-14" ;;
    esac
    # shellcheck disable=SC2086
    printf 'question: qa\nruling: a\nsource: t\n' | env $SCRUB FLEET_TEST_SEAM=1 FLEET_LIVE_PANES="$FIX/tree.txt" \
      RULINGS_DIR="$RD" RULINGS_LIB="$RULINGS_LIB" TMUX_PANE=%32 TZ=ZZZ-14 $a_env PATH="$FIX/slowbin:$PATH" STALL=4 \
      "$BASH_BIN" "$RULINGS_SH" write >"$FIX/a.out" 2>"$FIX/a.err" &
    apid=$!
    i=0
    while [ ! -s "$RD/.lock/manager:meta/owner" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
    [ -s "$RD/.lock/manager:meta/owner" ] && pass "$arm: writer A holds the lock" || fail "$arm: writer A holds the lock" "an owner file" "none after 5 s"
    IN=$'question: qb\nruling: b\nsource: t' r TZ="$b_tz" TMUX_PANE=%32 write
    wait "$apid"; arc=$?
    assert_eq 0 "$arc" "$arm: writer A exit 0 ($(cat "$FIX/a.err"))"
    assert_eq 0 "$RC" "$arm: writer B exit 0 ($ERR)"
    hasnt "breaking a stale lock" "$ERR" "$arm: B does not break a live holder's lock"
    ids=$(printf '%s\n' "$(cat "$FIX/a.out")" "$OUT" | sort | tr '\n' ' ' | sed 's/ $//')
    assert_eq "manager:meta#2 manager:meta#3" "$ids" "$arm: the two writers get distinct ids"
    assert_empty "$(grep '^## manager:meta#[0-9]*$' "$RD/manager:meta.md" | sort | uniq -d)" "$arm: no heading appears twice"
  done
}

test_S_R3_1_mark_read_through_refuses_an_id_past_the_newest() {
  plant manager:meta manager:meta 1 mq mr
  r TMUX_PANE=%27 mark-read --seat meta:engine --through manager:meta=999
  assert_eq 1 "$RC" "--through past the newest id is refused"
  has "past the newest ruling in manager:meta (manager:meta#1)" "$ERR" "the refusal names the newest id"
  assert_file_not_exists "$RD/.reads/meta:engine.tsv" "the refused mark-read wrote no cursor"
  plant manager:meta manager:meta 2 mq2 mr2
  r unread --seat meta:engine
  has "${TAB}manager:meta#2${TAB}" "$OUT" "a ruling written after the refused mark-read is unread"
  r TMUX_PANE=%27 mark-read --seat meta:engine --through fleet=1
  assert_eq 1 "$RC" "--through into a section with no file (newest id 0) is refused"
  r TMUX_PANE=%27 mark-read --seat meta:engine --through manager:meta=2
  assert_eq 0 "$RC" "control: --through at the newest id is accepted ($ERR)"
}

test_S_R3_2_a_tab_or_cr_in_a_hand_written_block_is_withheld_and_flagged() {
  plant manager:meta manager:meta 1 one r1
  printf '%s\n' "" "## manager:meta#2" "at: x" "by: manager:meta %32" "scope: subtree" \
    "question: half${TAB}other" "ruling: real-ruling" "source: t" >> "$RD/manager:meta.md"
  r live --seat meta:engine
  assert_eq 3 "$RC" "a block holding a tab makes the read partial (exit 3), not a clean 0"
  hasnt "real-ruling" "$OUT" "the tab block's ruling is not served"
  hasnt "other" "$OUT" "the text after the tab is never served as the ruling column"
  has "${TAB}manager:meta#1${TAB}" "$OUT" "the section's other ruling is served"
  assert_eq "# partial: manager:meta#2" "$(printf '%s\n' "$OUT" | tail -n 1)" "the trailer names the withheld id"
  has "manager:meta#2 holds a tab or a carriage return" "$ERR" "stderr names the block"
  r verify
  assert_eq 1 "$RC" "verify exits 1 on a block holding a tab"
  has "MALFORMED manager:meta block manager:meta#2 holds a tab or a carriage return" "$OUT" "verify names it"
  printf '%s\n' "" "## manager:meta#3" "at: x" "by: manager:meta %32" "scope: subtree" \
    "question: q3" "ruling: crlf"$'\r' "source: t" >> "$RD/manager:meta.md"
  r live --seat meta:engine
  hasnt "crlf" "$OUT" "a block holding a carriage return is not served"
  assert_eq "# partial: manager:meta#2 manager:meta#3" "$(printf '%s\n' "$OUT" | tail -n 1)" "both damaged blocks are withheld"
  assert_empty "$(printf '%s\n' "$OUT" | grep -v '^# partial' | awk -F'\t' 'NF != 8')" "every served row has exactly 8 columns"
}

test_NIT1_fields_foreign_to_the_block_kind_are_refused() {
  IN=$'question: q1\nruling: r1\nsource: t' r TMUX_PANE=%32 write
  cp "$RD/manager:meta.md" "$FIX/before"
  IN=$'question: q2\nruling: r2\nsource: t\nreason: why' r TMUX_PANE=%32 write
  assert_eq 1 "$RC" "a reason: on a ruling is refused, not dropped"
  IN=$'withdraws: manager:meta#1\nreason: x\nsource: t' r TMUX_PANE=%32 write
  assert_eq 1 "$RC" "a source: on a withdrawal is refused, not dropped"
  IN=$'withdraws: manager:meta#1\nreason: x\ndetail: d' r TMUX_PANE=%32 write
  assert_eq 1 "$RC" "a detail: on a withdrawal is refused, not dropped"
  cmp -s "$FIX/before" "$RD/manager:meta.md" && pass "no refused write touched the section" || fail "no refused write touched the section"
  IN=$'withdraws: manager:meta#1\nreason: x' r TMUX_PANE=%32 write
  assert_eq 0 "$RC" "control: a plain withdrawal is written ($ERR)"
}

test_NIT4_an_inherited_lib_loaded_flag_does_not_disable_the_library() {
  plant manager:meta manager:meta 1 mq mr
  r _LIB_SH_LOADED=1 live --seat meta:engine
  assert_eq 0 "$RC" "an exported _LIB_SH_LOADED does not make every call exit 127 ($ERR)"
  has "${TAB}manager:meta#1${TAB}" "$OUT" "the row is served"
}

run_discovered_tests
