#!/bin/bash
# test-fleet-identity.sh — Tests for fleet_self / fleet_parent in scripts/lib.sh and their readers.
#
# run.sh caches FLEET_PANE and FLEET_PARENT at launch, so a seat renamed or re-parented since
# then carries its old identity in them. The rule: the live tmux label and @pane_parent win, a
# stderr warning names both values when the cache differs, and the cache is used (exit 3, the
# flag) only when tmux cannot be read. No tmux and no cache is an error (exit 1).
#
# No live tmux is touched: TMUX and TMUX_PANE are always scrubbed, and the live read goes either
# through the FLEET_LIVE_PANES seam (a file in hop.sh's live-tree shape) or through a PATH-stub
# `tmux` in the fixture dir with a fake $TMUX.
#
# Plant a defect: LIB_SH= / HOP_SH= / AWAIT_NEXT= / SESSION_SH=<mutated copy> — it must go red.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

LIB_SH="${LIB_SH:-$HOME/.claude/engine/scripts/lib.sh}"
HOP_SH="${HOP_SH:-$HOME/.claude/engine/skills/coordinate/scripts/hop.sh}"
AWAIT_NEXT="${AWAIT_NEXT:-$HOME/.claude/engine/tools/await-next/await-next.sh}"
SESSION_SH="${SESSION_SH:-$HOME/.claude/engine/scripts/session.sh}"
# macOS system bash is 3.2; the functions must run there (§PTF_BASH32_COMPATIBILITY).
BASH_BIN="${FLEET_ID_BASH:-/bin/bash}"

# Every run starts from a scrubbed fleet env: nothing inherited can reach a real server.
SCRUB="-u TMUX -u TMUX_PANE -u FLEET_PANE -u FLEET_PARENT -u FLEET_TMUX_SOCKET -u FLEET_LIVE_PANES
       -u FLEET_WARN_PREFIX -u FLEET_WARN_ONCE_DIR -u _LIB_SH_LOADED -u HOP_LIVE_PANES -u HOP_TMUX_SOCKET
       -u HOP_CHAIN_FILE -u FLEET_MANAGES -u FLEET_CLAIMS -u FLEET_TARGETED_CLAIMS"

FIX=""

setup() {
  FIX="$(mktemp -d)"
  cat > "$FIX/live.txt" <<'EOF'
manager:director %114 -
manager:domain %134 manager:director
domain:stats %60 manager:domain
EOF
  mkdir -p "$FIX/bin"
  # The stub answers `[-S path|-L name] display -p -t <pane> <format>` with
  # "$STUB_LABEL|$STUB_PARENT"; it exits $STUB_RC. Every call's argv lands in $FIX/argv.
  cat > "$FIX/bin/tmux" <<EOF
#!/bin/bash
echo "\$*" >> "$FIX/argv"
[ "\${STUB_RC:-0}" = 0 ] || exit "\$STUB_RC"
while [ "\${1:-}" = -S ] || [ "\${1:-}" = -L ]; do shift 2; done
[ "\${1:-}" = display ] || exit 1
printf '%s|%s\n' "\${STUB_LABEL:-}" "\${STUB_PARENT:-}"
EOF
  chmod +x "$FIX/bin/tmux"
  : > "$FIX/argv"
}

teardown() { rm -rf "$FIX"; }

# fid <NAME=VALUE…> <fn> [args…] — the lib function against the seam. Sets OUT, ERR, RC.
fid() {
  local envs=() fn
  while [ $# -gt 0 ] && [[ "$1" == *=* ]]; do envs+=("$1"); shift; done
  fn="$1"; shift
  # shellcheck disable=SC2086
  OUT=$(env $SCRUB FLEET_LIVE_PANES="$FIX/live.txt" ${envs[@]+"${envs[@]}"} \
          "$BASH_BIN" -c 'source "$1"; shift; "$@"' _ "$LIB_SH" "$fn" "$@" 2>"$FIX/err")
  RC=$?
  ERR=$(cat "$FIX/err")
}

# fstub <NAME=VALUE…> <fn> [args…] — no seam: the live read goes to the PATH-stub tmux, with a
# fake $TMUX (pass TMUX= to blank it).
fstub() {
  local envs=() fn
  while [ $# -gt 0 ] && [[ "$1" == *=* ]]; do envs+=("$1"); shift; done
  fn="$1"; shift
  : > "$FIX/argv"
  # shellcheck disable=SC2086
  OUT=$(env $SCRUB PATH="$FIX/bin:$PATH" TMUX="$FIX/sock,1,0" ${envs[@]+"${envs[@]}"} \
          "$BASH_BIN" -c 'source "$1"; shift; "$@"' _ "$LIB_SH" "$fn" "$@" 2>"$FIX/err")
  RC=$?
  ERR=$(cat "$FIX/err")
}

assert_has() {
  local pattern="$1" actual="$2" msg="$3"
  if grep -qF -- "$pattern" <<<"$actual"; then pass "$msg"; else fail "$msg" "contains '$pattern'" "'$actual'"; fi
}
assert_hasnt() {
  local pattern="$1" actual="$2" msg="$3"
  if grep -qF -- "$pattern" <<<"$actual"; then fail "$msg" "no '$pattern'" "'$actual'"; else pass "$msg"; fi
}

test_files_exist() {
  assert_file_exists "$LIB_SH" "lib.sh exists (so the empty-stdout checks below are not vacuous)"
  assert_file_exists "$HOP_SH" "hop.sh exists"
  assert_file_exists "$AWAIT_NEXT" "await-next.sh exists"
}

# ---------------------------------------------------------------- fleet_self

test_self_stale_fleet_pane_gives_live_label_and_warning() {
  fid TMUX_PANE=%60 FLEET_PANE=domain:domain fleet_self
  assert_eq "0|domain:stats" "$RC|$OUT" "fleet_self: stale FLEET_PANE → the live label, exit 0"
  assert_has "FLEET_PANE 'domain:domain' is stale; using the live pane label 'domain:stats'" "$ERR" \
    "fleet_self: the warning names both values"
}

test_self_matching_cache_warns_nothing() {
  fid TMUX_PANE=%60 FLEET_PANE=domain:stats fleet_self
  assert_eq "0|domain:stats" "$RC|$OUT" "fleet_self: matching FLEET_PANE → the live label"
  assert_eq "" "$ERR" "fleet_self: a matching cache warns nothing"
}

test_self_unset_cache_uses_live_silently() {
  fid TMUX_PANE=%60 fleet_self
  assert_eq "0|domain:stats|" "$RC|$OUT|$ERR" "fleet_self: no FLEET_PANE, live label → the live label, silently"
}

test_self_tmux_unreadable_gives_cache_and_flag() {
  fid FLEET_PANE=domain:domain fleet_self
  assert_eq "3|domain:domain" "$RC|$OUT" "fleet_self: no TMUX_PANE → the cache, flagged exit 3"
  assert_has "using the launch-time FLEET_PANE 'domain:domain'" "$ERR" "fleet_self: the fallback is flagged on stderr"
  fid TMUX_PANE=%999 FLEET_PANE=domain:domain fleet_self
  assert_eq "3|domain:domain" "$RC|$OUT" "fleet_self: pane not in the live tree → the cache, exit 3"
  fid TMUX_PANE=%60 FLEET_PANE=domain:domain FLEET_LIVE_PANES="$FIX/missing.txt" fleet_self
  assert_eq "3|domain:domain" "$RC|$OUT" "fleet_self: seam unreadable → the cache, exit 3"
}

test_self_no_tmux_no_cache_is_an_error() {
  fid fleet_self
  assert_eq "1|" "$RC|$OUT" "fleet_self: no tmux and no FLEET_PANE → exit 1, nothing on stdout"
  assert_has "cannot resolve this seat's identity" "$ERR" "fleet_self: the error says why"
}

test_self_real_read_targets_the_agents_own_server() {
  fstub TMUX_PANE=%60 FLEET_PANE=domain:domain STUB_LABEL=domain:stats STUB_PARENT=manager:domain fleet_self
  assert_eq "0|domain:stats" "$RC|$OUT" "fleet_self (tmux): the live label wins"
  assert_has "FLEET_PANE 'domain:domain' is stale" "$ERR" "fleet_self (tmux): the stale warning"
  assert_has "-S $FIX/sock display -p -t %60" "$(cat "$FIX/argv")" "fleet_self (tmux): reads display -p -t \$TMUX_PANE on \$TMUX's server (-S)"
  assert_eq "1" "$(wc -l < "$FIX/argv" | tr -d ' ')" "fleet_self (tmux): one display call"
  fstub TMUX_PANE=%60 FLEET_TMUX_SOCKET=fleet-x STUB_LABEL=domain:stats fleet_self
  assert_has "-L fleet-x display -p -t %60" "$(cat "$FIX/argv")" "fleet_self (tmux): honours FLEET_TMUX_SOCKET"
}

test_self_no_TMUX_means_no_live_read() {
  # Without $TMUX a bare tmux would reach the default server, where %60 is somebody else's pane.
  fstub TMUX= TMUX_PANE=%60 FLEET_PANE=domain:domain STUB_LABEL=other:pane fleet_self
  assert_eq "3|domain:domain" "$RC|$OUT" "fleet_self: TMUX unset → the cache, exit 3"
  assert_eq "" "$(cat "$FIX/argv")" "fleet_self: TMUX unset → tmux is never called"
}

test_self_real_read_failure_or_blank_label_falls_back() {
  fstub TMUX_PANE=%60 FLEET_PANE=domain:domain STUB_RC=1 fleet_self
  assert_eq "3|domain:domain" "$RC|$OUT" "fleet_self (tmux): tmux fails → the cache, exit 3"
  fstub TMUX_PANE=%60 FLEET_PANE=domain:domain STUB_LABEL="domain:" fleet_self
  assert_eq "3|domain:domain" "$RC|$OUT" "fleet_self (tmux): a pane with no @pane_label is not a live seat → cache"
  fstub TMUX_PANE=%60 STUB_RC=1 fleet_self
  assert_eq "1|" "$RC|$OUT" "fleet_self (tmux): tmux fails and no cache → exit 1"
}

test_warn_once_dir_dedupes_a_repeated_warning() {
  fid TMUX_PANE=%60 FLEET_PANE=domain:domain FLEET_WARN_ONCE_DIR="$FIX/once" fleet_self
  assert_has "is stale" "$ERR" "warn-once: the first stale warning is printed"
  fid TMUX_PANE=%60 FLEET_PANE=domain:domain FLEET_WARN_ONCE_DIR="$FIX/once" fleet_self
  assert_eq "0|domain:stats|" "$RC|$OUT|$ERR" "warn-once: the same warning again is silent, the answer unchanged"
  fid TMUX_PANE=%60 FLEET_PANE=domain:other FLEET_WARN_ONCE_DIR="$FIX/once" fleet_self
  assert_has "FLEET_PANE 'domain:other' is stale" "$ERR" "warn-once: a different cache value warns again"
}

# ---------------------------------------------------------------- fleet_parent

test_parent_stale_fleet_parent_gives_live_parent() {
  fid TMUX_PANE=%60 FLEET_PARENT=manager:director fleet_parent
  assert_eq "0|manager:domain" "$RC|$OUT" "fleet_parent: stale FLEET_PARENT → the live parent, exit 0"
  assert_has "FLEET_PARENT 'manager:director' is stale; using the live @pane_parent 'manager:domain'" "$ERR" \
    "fleet_parent: the warning names both values"
  fid TMUX_PANE=%60 FLEET_PARENT=manager:domain fleet_parent
  assert_eq "0|manager:domain|" "$RC|$OUT|$ERR" "fleet_parent: a matching cache warns nothing"
  fstub TMUX_PANE=%60 STUB_LABEL=domain:stats STUB_PARENT=manager:domain FLEET_PARENT=manager:director fleet_parent
  assert_eq "0|manager:domain" "$RC|$OUT" "fleet_parent (tmux): the live parent wins"
}

test_parent_dash_means_no_parent() {
  fid TMUX_PANE=%114 FLEET_PARENT=manager:ghost fleet_parent
  assert_eq "0|" "$RC|$OUT" "fleet_parent: live '-' beats a stale FLEET_PARENT → no parent (empty, exit 0)"
  assert_has "FLEET_PARENT 'manager:ghost' is stale; using the live @pane_parent 'none'" "$ERR" \
    "fleet_parent: the warning names the cache and 'none'"
  fid TMUX_PANE=%114 fleet_parent
  assert_eq "0||" "$RC|$OUT|$ERR" "fleet_parent: live '-' with no cache → no parent, no warning"
  fstub TMUX_PANE=%114 STUB_LABEL=manager:director STUB_PARENT=- FLEET_PARENT=manager:ghost fleet_parent
  assert_eq "0|" "$RC|$OUT" "fleet_parent (tmux): live '-' → no parent"
}

test_parent_of_a_pane_that_is_not_a_seat_is_unreadable() {
  # The label and parent come from one read: a pane with no @pane_label has no live parent either.
  fstub TMUX_PANE=%114 STUB_LABEL= STUB_PARENT=- FLEET_PARENT=manager:director fleet_parent
  assert_eq "3|manager:director" "$RC|$OUT" "fleet_parent (tmux): an unlabelled pane → the cache, exit 3"
  assert_hasnt "is stale" "$ERR" "fleet_parent (tmux): and no 'stale' claim against a non-seat"
  fstub TMUX= TMUX_PANE=%114 STUB_LABEL=x:y STUB_PARENT=- FLEET_PARENT=manager:director fleet_parent
  assert_eq "3|manager:director|" "$RC|$OUT|$(cat "$FIX/argv")" "fleet_parent: TMUX unset → the cache, tmux never called"
}

test_parent_tmux_unreadable_gives_cache_and_flag() {
  fid FLEET_PARENT=manager:director fleet_parent
  assert_eq "3|manager:director" "$RC|$OUT" "fleet_parent: no TMUX_PANE → the cache, flagged exit 3"
  assert_has "using the launch-time FLEET_PARENT 'manager:director'" "$ERR" "fleet_parent: the fallback is flagged"
  fstub TMUX_PANE=%60 FLEET_PARENT=manager:director STUB_RC=1 fleet_parent
  assert_eq "3|manager:director" "$RC|$OUT" "fleet_parent (tmux): tmux fails → the cache, exit 3"
}

test_parent_no_tmux_no_cache_is_an_error() {
  fid fleet_parent
  assert_eq "1|" "$RC|$OUT" "fleet_parent: no tmux and no FLEET_PARENT → exit 1"
  assert_has "cannot resolve this seat's parent" "$ERR" "fleet_parent: the error says why"
}

test_parent_live_value_from_the_caller() {
  # hop.sh already read the edge from its live tree; it hands that value in with --live.
  fid FLEET_PARENT=manager:director fleet_parent --live manager:idealic --of idealic:kernel
  assert_eq "0|manager:idealic" "$RC|$OUT" "fleet_parent --live: the caller's live edge wins"
  assert_has "FLEET_PARENT 'manager:director' is stale; using the live @pane_parent 'manager:idealic' of 'idealic:kernel'" \
    "$ERR" "fleet_parent --live --of: the warning names the seat"
  fid fleet_parent --live manager:idealic
  assert_has "FLEET_PARENT unset; using live @pane_parent 'manager:idealic'" "$ERR" "fleet_parent: an unset cache is noted"
  fid FLEET_WARN_PREFIX=hop FLEET_PARENT=x:y fleet_parent --live -
  assert_eq "0|" "$RC|$OUT" "fleet_parent --live -: no parent"
  assert_has "hop: FLEET_PARENT 'x:y' is stale" "$ERR" "FLEET_WARN_PREFIX names the caller"
}

# ---------------------------------------------------------------- hop.sh finds the rule

# hop_in <NAME=VALUE…> <hop.sh path> <args…> → OUT, ERR, RC
hop_in() {
  local envs=()
  while [ $# -gt 0 ] && [[ "$1" == *=* ]]; do envs+=("$1"); shift; done
  # shellcheck disable=SC2086
  OUT=$(env $SCRUB HOP_LIVE_PANES="$FIX/live.txt" ${envs[@]+"${envs[@]}"} "$BASH_BIN" "$@" 2>"$FIX/err")
  RC=$?
  ERR=$(cat "$FIX/err")
}

# marker_tree <dir> <relative path of the script> <source script> — a tree whose own
# scripts/lib.sh defines marker identities (and sets the double-source guard, as lib.sh does).
marker_tree() {
  mkdir -p "$1/scripts" "$1/$(dirname "$2")"
  cp "$3" "$1/$2"
  cat > "$1/scripts/lib.sh" <<'EOF'
_LIB_SH_LOADED=1
fleet_self() { echo marker:seat; }
fleet_parent() { while [ $# -gt 0 ]; do [ "$1" = --live ] && { [ "$2" = - ] || echo "$2"; }; shift; done; return 0; }
EOF
}

test_hop_uses_its_own_trees_lib() {
  marker_tree "$FIX/tree" skills/coordinate/scripts/hop.sh "$HOP_SH"
  printf 'marker:seat %%7 manager:director\nmanager:director %%114 -\n' > "$FIX/marker-live.txt"
  hop_in HOP_LIVE_PANES="$FIX/marker-live.txt" "$FIX/tree/skills/coordinate/scripts/hop.sh" target
  assert_eq "0|manager:director %114" "$RC|$OUT" "hop: the tree's own lib.sh is used before ~/.claude's"
}

test_hop_survives_an_inherited_lib_guard() {
  hop_in _LIB_SH_LOADED=1 FLEET_PANE=domain:stats "$HOP_SH" chain
  assert_eq "0" "$RC" "hop chain: an inherited _LIB_SH_LOADED does not hide fleet_self"
  assert_has "domain:stats %60 manager:domain" "$OUT" "hop chain: and the chain starts at the seat"
  assert_hasnt "command not found" "$ERR" "hop chain: no 'command not found'"
}

test_hop_without_lib_keeps_identity_free_subcommands() {
  mkdir -p "$FIX/nolib/skills/coordinate/scripts" "$FIX/emptyhome"
  cp "$HOP_SH" "$FIX/nolib/skills/coordinate/scripts/hop.sh"
  hop_in HOME="$FIX/emptyhome" "$FIX/nolib/skills/coordinate/scripts/hop.sh" ask-id --pane %1 --question hi
  assert_eq "0" "$RC" "hop ask-id: works with no lib.sh anywhere"
  assert_not_empty "$OUT" "hop ask-id: and prints an id"
  hop_in HOME="$FIX/emptyhome" FLEET_PANE=domain:stats "$FIX/nolib/skills/coordinate/scripts/hop.sh" target
  assert_eq "2|" "$RC|$OUT" "hop target: no lib.sh → exit 2, nothing on stdout"
  assert_has "no scripts/lib.sh defining fleet_self" "$ERR" "hop target: the error names the missing lib"
}

test_hop_identity_failure_is_one_line_with_the_real_reason() {
  hop_in "$HOP_SH" target
  assert_eq "2" "$RC" "hop target: no identity → exit 2"
  assert_eq "1" "$(grep -c 'cannot resolve' <<<"$ERR")" "hop target: one identity error line, not two"
  assert_has "fleet_self exit 1" "$ERR" "hop target: the line carries fleet_self's real exit"
}

# ---------------------------------------------------------------- await-next

# await_targeted <target> [NAME=VALUE… | TOOL=path] [-- extra args] → OUT, RC, ERR
await_targeted() {
  local target="$1"; shift
  local envs=() sdir="$FIX/sessions-$RANDOM" tool="$AWAIT_NEXT"
  while [ $# -gt 0 ] && [ "$1" != -- ]; do
    case "$1" in TOOL=*) tool="${1#TOOL=}" ;; *) envs+=("$1") ;; esac
    shift
  done
  [ "${1:-}" = -- ] && shift
  mkdir -p "$sdir/s1"
  printf '# Request\n\n**Tags**: #delegated-implementation %%%s\n' "$target" > "$sdir/s1/REQUEST.md"
  # shellcheck disable=SC2086
  OUT=$(env $SCRUB FLEET_LIVE_PANES="$FIX/live.txt" FLEET_WARN_ONCE_DIR="$FIX/once-$RANDOM" ${envs[@]+"${envs[@]}"} \
          "$BASH_BIN" "$tool" 1 --targeted-claims implementation --sessions-dir "$sdir" --no-connect \
          --socket "fleetid-test-none-$$" "$@" 2>"$FIX/err")
  RC=$?
  ERR=$(cat "$FIX/err")
}

test_await_next_default_identity_is_the_live_label() {
  await_targeted domain:stats TMUX_PANE=%60 FLEET_PANE=domain:domain
  assert_eq "0" "$RC" "await-next: exits 0"
  assert_has "WORK " "$OUT" "await-next: a tag for the live label is claimed despite a stale FLEET_PANE"
  assert_has "FLEET_PANE 'domain:domain' is stale" "$ERR" "await-next: the stale cache is named on stderr"
  await_targeted domain:domain TMUX_PANE=%60 FLEET_PANE=domain:domain
  assert_has "TIMEOUT" "$OUT" "await-next: a tag for the stale launch-time label is not ours"
  await_targeted domain:domain FLEET_PANE=domain:domain
  assert_has "WORK " "$OUT" "await-next: tmux unreadable → the FLEET_PANE cache still serves"
}

test_await_next_warns_once_per_stale_value() {
  await_targeted domain:stats TMUX_PANE=%60 FLEET_PANE=domain:domain FLEET_WARN_ONCE_DIR="$FIX/an-once"
  assert_has "is stale" "$ERR" "await-next: the first turn names the stale cache"
  await_targeted domain:stats TMUX_PANE=%60 FLEET_PANE=domain:domain FLEET_WARN_ONCE_DIR="$FIX/an-once"
  assert_has "WORK " "$OUT" "await-next: the next turn still claims"
  assert_hasnt "is stale" "$ERR" "await-next: but does not repeat the warning"
}

test_await_next_reads_identity_on_its_own_server_not_socket() {
  # The later --socket wins over the harness's nonexistent one.
  await_targeted domain:stats FLEET_LIVE_PANES= PATH="$FIX/bin:$PATH" TMUX="$FIX/sock,1,0" TMUX_PANE=%60 \
    STUB_LABEL=domain:stats STUB_PARENT=manager:domain -- --socket other
  local argv; argv=$(cat "$FIX/argv")
  assert_has "WORK " "$OUT" "await-next --socket other: the live label is still read"
  assert_has "-S $FIX/sock display -p -t %60" "$argv" "await-next: identity is read on \$TMUX's server"
  assert_hasnt "-L other" "$argv" "await-next: --socket other is never queried for identity"
}

test_await_next_uses_its_own_trees_lib_and_survives_the_guard() {
  marker_tree "$FIX/atree" tools/await-next/await-next.sh "$AWAIT_NEXT"
  await_targeted marker:seat TOOL="$FIX/atree/tools/await-next/await-next.sh"
  assert_has "WORK " "$OUT" "await-next: the tree's own lib.sh is used"
  await_targeted domain:stats _LIB_SH_LOADED=1 TMUX_PANE=%60
  assert_has "WORK " "$OUT" "await-next: an inherited _LIB_SH_LOADED does not hide fleet_self"
}

test_await_next_says_why_targeted_tags_are_skipped() {
  await_targeted domain:stats
  assert_has "TIMEOUT" "$OUT" "await-next: no identity → the targeted tag is not claimed"
  assert_has "identity is unknown (fleet_self exit 1)" "$ERR" "await-next: and says why on stderr"
}

# ---------------------------------------------------------------- session.sh

# session.sh's FLEET_PANE is reassigned before any read, so it never reads run.sh's cache:
# activate resets it, then takes --fleet-pane or the live `fleet.sh pane-id`
# (session:window:label); find assigns it from the live read. Every read must sit in one of
# those two arms, after that assignment.
test_session_sh_reads_no_launch_cache() {
  local scan
  scan=$(awk '
    /^  [a-z|-]+\)/ { arm = $1; sub(/\)$/, "", arm) }
    /^[[:space:]]*#/ { next }
    /(^|[^A-Za-z0-9_])FLEET_PANE([^A-Za-z0-9_]|$)/ { print arm "\t" $0 }
  ' "$SESSION_SH")
  assert_not_empty "$scan" "session.sh: the scan finds its FLEET_PANE lines (not vacuous)"
  assert_eq "" "$(awk -F'\t' '$1 != "activate" && $1 != "find"' <<<"$scan")" \
    "session.sh: every FLEET_PANE line sits in the activate or find arm"
  assert_has 'FLEET_PANE=""' "$(awk -F'\t' '$1 == "activate" { print $2; exit }' <<<"$scan")" \
    "session.sh activate: the first FLEET_PANE line is the reset"
  assert_has 'FLEET_PANE=$(get_fleet_pane_id)' "$(awk -F'\t' '$1 == "find" { print $2; exit }' <<<"$scan")" \
    "session.sh find: the first FLEET_PANE line is the live assignment"
  assert_eq "0" "$(grep -c 'FLEET_PARENT' "$SESSION_SH")" "session.sh reads no FLEET_PARENT"
}

run_discovered_tests
