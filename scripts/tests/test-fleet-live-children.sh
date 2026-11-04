#!/bin/bash
# test-fleet-live-children.sh — fleet_live_tree / fleet_live_children (scripts/lib.sh) and
# `fleet.sh live-children` / `fleet.sh stale-managers`.
#
# The manager→seat edge is the child's live @pane_parent. FLEET_MANAGES is run.sh's launch-time
# copy of @pane_manages, so it goes stale. These tests hold the helper to three rules:
#   - the live tree is read from tmux; a stubbed tree (FLEET_LIVE_PANES) is honoured ONLY with the
#     test marker FLEET_TEST_SEAM=1, and a stub without the marker is ignored;
#   - an unreadable tree prints "unknown" and exits 2, never an empty child list;
#   - FLEET_MANAGES is used only when the caller asks for the named fallback, and says so.
#
# No live tmux is touched: TMUX/TMUX_PANE are scrubbed, every no-seam read is pointed at a socket
# name no server listens on, or at a PATH-stub `tmux` (and a PATH-stub `ps`) in the fixture dir.
#
# Plant a defect: LIB_SH=<mutated copy> FLEET_SH=<mutated copy> — it must go red.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

TREE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB_SH="${LIB_SH:-$TREE_ROOT/scripts/lib.sh}"
FLEET_SH="${FLEET_SH:-$TREE_ROOT/scripts/fleet.sh}"
HOP_SH="${HOP_SH:-$TREE_ROOT/skills/coordinate/scripts/hop.sh}"
BASH_BIN="${FLEET_ID_BASH:-/bin/bash}"
NO_SOCK="manages2-test-no-such-socket-$$"

SCRUB="-u TMUX -u TMUX_PANE -u FLEET_PANE -u FLEET_PARENT -u FLEET_TMUX_SOCKET -u FLEET_LIVE_PANES
       -u FLEET_TEST_SEAM -u FLEET_LAUNCH_ENV -u FLEET_WARN_PREFIX -u FLEET_WARN_ONCE_DIR
       -u _LIB_SH_LOADED -u HOP_LIVE_PANES -u HOP_TMUX_SOCKET -u FLEET_MANAGES -u FLEET_LIB -u FLEET_PS"

FIX=""

setup() {
  FIX="$(mktemp -d)"
  cat > "$FIX/tree.txt" <<'EOF'
manager:director %1 -
manager:domain %2 manager:director
domain:stats %3 manager:domain
domain:platform %4 MANAGER:Domain
manager:app %5 manager:director
app:deploy %6 manager:app
app:writer %7 manager:app
EOF
  : > "$FIX/argv"
}

teardown() { rm -rf "$FIX"; }

# lib <NAME=VALUE…> <fn> [args…] — a lib.sh function in a scrubbed bash. Sets OUT, ERR, RC.
lib() {
  local envs=() fn
  while [ $# -gt 0 ] && [[ "$1" == *=* ]]; do envs+=("$1"); shift; done
  fn="$1"; shift
  # shellcheck disable=SC2086
  OUT=$(env $SCRUB ${envs[@]+"${envs[@]}"} \
          "$BASH_BIN" -c 'source "$1"; shift; "$@"' _ "$LIB_SH" "$fn" "$@" 2>"$FIX/err")
  RC=$?
  ERR=$(cat "$FIX/err")
}

# fleet <NAME=VALUE…> <subcommand> [args…] — fleet.sh in a scrubbed bash. Sets OUT, ERR, RC.
fleet() {
  local envs=()
  while [ $# -gt 0 ] && [[ "$1" == *=* ]]; do envs+=("$1"); shift; done
  # shellcheck disable=SC2086
  # No FLEET_LIB: fleet.sh's own loader picks the lib (its tree's scripts/lib.sh), as in production.
  OUT=$(env $SCRUB ${envs[@]+"${envs[@]}"} "$BASH_BIN" "$FLEET_SH" "$@" 2>"$FIX/err")
  RC=$?
  ERR=$(cat "$FIX/err")
}

SEAM() { echo "FLEET_TEST_SEAM=1"; }

assert_has() {
  if grep -qF -- "$1" <<<"$2"; then pass "$3"; else fail "$3" "contains '$1'" "'$2'"; fi
}
assert_hasnt() {
  if grep -qF -- "$1" <<<"$2"; then fail "$3" "no '$1'" "'$2'"; else pass "$3"; fi
}

# ---------------------------------------------------------------- live children

test_children_listed() {
  lib "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" fleet_live_children manager:app
  assert_eq 0 "$RC" "children: exit 0"
  assert_eq "app:deploy
app:writer" "$OUT" "children: the seats whose live @pane_parent is manager:app, sorted"
}

test_children_match_ignoring_case() {
  lib "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" fleet_live_children Manager:DOMAIN
  assert_eq 0 "$RC" "case: exit 0"
  assert_eq "domain:platform
domain:stats" "$OUT" "case: the query and a parent field written MANAGER:Domain both match"
}

test_seat_with_no_children_is_an_empty_list_at_exit_0() {
  lib "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" fleet_live_children domain:stats
  assert_eq 0 "$RC" "leaf: exit 0 (a read tree, so an empty list is a true reading)"
  assert_eq "" "$OUT" "leaf: no children"
}

test_ambiguous_seat_refused() {
  printf 'manager:app %%9 manager:director\n' >> "$FIX/tree.txt"
  lib "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" fleet_live_children manager:APP
  assert_eq 4 "$RC" "ambiguous: exit 4"
  assert_eq "unknown" "$OUT" "ambiguous: stdout is 'unknown', not a list"
  assert_has "2 panes carry" "$ERR" "ambiguous: stderr names the reason"
}

test_ambiguous_child_is_left_out_and_named() {
  printf 'app:deploy %%9 manager:app\n' >> "$FIX/tree.txt"
  lib "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" fleet_live_children manager:app
  assert_eq 0 "$RC" "ambiguous child: exit 0"
  assert_eq "app:writer" "$OUT" "ambiguous child: a seat two panes carry has no live manager (as ask-app)"
  assert_has "app:deploy" "$ERR" "ambiguous child: stderr names it"
}

test_unreadable_seam_file_is_unknown_exit_2() {
  lib "$(SEAM)" FLEET_LIVE_PANES="$FIX/missing.txt" fleet_live_children manager:app
  assert_eq 2 "$RC" "unreadable stub: exit 2"
  assert_eq "unknown" "$OUT" "unreadable stub: 'unknown', no list"
}

test_empty_tree_is_unknown_exit_2() {
  : > "$FIX/empty.txt"
  lib "$(SEAM)" FLEET_LIVE_PANES="$FIX/empty.txt" fleet_live_children manager:app
  assert_eq 2 "$RC" "empty tree: exit 2"
  assert_eq "unknown" "$OUT" "empty tree: 'unknown', never an empty child list"
}

test_unreachable_tmux_is_unknown_exit_2() {
  lib FLEET_TMUX_SOCKET="$NO_SOCK" fleet_live_children manager:app
  assert_eq 2 "$RC" "no tmux server: exit 2"
  assert_eq "unknown" "$OUT" "no tmux server: 'unknown', no list"
  assert_has "cannot read the live tree" "$ERR" "no tmux server: stderr says why"
}

test_no_server_named_is_unknown_exit_2() {
  lib fleet_live_children manager:app
  assert_eq 2 "$RC" "no TMUX, no socket: exit 2 (never the default server)"
  assert_eq "unknown" "$OUT" "no TMUX, no socket: 'unknown'"
}

# The planted case: a stubbed tree with the marker unset must NOT be used. The live read then
# goes to a socket nobody listens on, so the only way to print children is to have used the stub.
test_stub_without_marker_is_ignored() {
  lib FLEET_LIVE_PANES="$FIX/tree.txt" FLEET_TMUX_SOCKET="$NO_SOCK" fleet_live_children manager:app
  assert_eq 2 "$RC" "no marker: exit 2 (the stub was not read)"
  assert_eq "unknown" "$OUT" "no marker: 'unknown'"
  assert_hasnt "app:deploy" "$OUT" "no marker: the stub's children are not printed"
  assert_has "FLEET_TEST_SEAM" "$ERR" "no marker: stderr says the stub was ignored and why"
}

test_marker_must_be_exactly_1() {
  lib FLEET_TEST_SEAM=yes FLEET_LIVE_PANES="$FIX/tree.txt" FLEET_TMUX_SOCKET="$NO_SOCK" fleet_live_children manager:app
  assert_eq 2 "$RC" "marker=yes: not the marker, stub ignored"
  assert_hasnt "app:deploy" "$OUT" "marker=yes: no stub children"
}

test_hop_seam_name_is_not_honoured() {
  lib "$(SEAM)" HOP_LIVE_PANES="$FIX/tree.txt" FLEET_TMUX_SOCKET="$NO_SOCK" fleet_live_children manager:app
  assert_eq 2 "$RC" "HOP_LIVE_PANES: not this helper's seam"
}

test_fleet_manages_is_never_used_unasked() {
  lib FLEET_MANAGES="deploy,writer" FLEET_TMUX_SOCKET="$NO_SOCK" fleet_live_children manager:app
  assert_eq 2 "$RC" "no fallback asked: exit 2 even with FLEET_MANAGES set"
  assert_eq "unknown" "$OUT" "no fallback asked: FLEET_MANAGES is not printed"
}

test_named_fallback_says_so() {
  lib FLEET_PANE=manager:app FLEET_MANAGES="deploy,writer" FLEET_TMUX_SOCKET="$NO_SOCK" fleet_live_children Manager:App --fallback-launch
  assert_eq 3 "$RC" "fallback: exit 3 for this process's own seat"
  assert_eq "fallback FLEET_MANAGES
deploy
writer" "$OUT" "fallback: first line names the source, then the launch-time entries"
  assert_has "launch-time" "$ERR" "fallback: stderr says it is the launch-time copy"
}

# MUST-FIX 2: FLEET_MANAGES is this process's launch copy; it never answers for another seat.
test_fallback_refuses_another_seat() {
  lib FLEET_PANE=manager:app FLEET_MANAGES="kernel,storage" FLEET_TMUX_SOCKET="$NO_SOCK" fleet_live_children idealic:ui --fallback-launch
  assert_eq 2 "$RC" "fallback, other seat: exit 2"
  assert_eq "unknown" "$OUT" "fallback, other seat: 'unknown', not the caller's list"
  assert_has "own seat" "$ERR" "fallback, other seat: stderr says the fallback covers only the own seat"
}

test_fallback_refuses_when_own_seat_unresolved() {
  lib FLEET_MANAGES="deploy,writer" FLEET_TMUX_SOCKET="$NO_SOCK" fleet_live_children manager:app --fallback-launch
  assert_eq 2 "$RC" "fallback, no own identity: exit 2"
  assert_eq "unknown" "$OUT" "fallback, no own identity: 'unknown'"
}

# An unmarked stub must not decide the own seat either.
test_fallback_identity_ignores_unmarked_stub() {
  printf 'manager:app %%77 -\n' > "$FIX/self.txt"
  lib TMUX_PANE=%77 FLEET_LIVE_PANES="$FIX/self.txt" FLEET_PANE=other:seat FLEET_MANAGES="deploy" FLEET_TMUX_SOCKET="$NO_SOCK" \
    fleet_live_children manager:app --fallback-launch
  assert_eq 2 "$RC" "fallback, unmarked stub names the seat: still exit 2"
  assert_hasnt "deploy" "$OUT" "fallback, unmarked stub: no list"
}

test_fallback_splits_on_whitespace_too() {
  lib FLEET_PANE=manager:app FLEET_MANAGES="deploy writer" FLEET_TMUX_SOCKET="$NO_SOCK" fleet_live_children manager:app --fallback-launch
  assert_eq "fallback FLEET_MANAGES
deploy
writer" "$OUT" "fallback: commas and whitespace both split (ask-app's [\\s,]+)"
}

# SHOULD 1: a seat no pane carries is not "manages nobody".
test_absent_seat_is_unknown_exit_5() {
  lib "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" fleet_live_children manager:domian
  assert_eq 5 "$RC" "absent seat: exit 5"
  assert_eq "unknown" "$OUT" "absent seat: 'unknown', never an empty list"
  assert_has "no pane carries" "$ERR" "absent seat: stderr names it"
}

test_fallback_with_no_fleet_manages_stays_unknown() {
  lib FLEET_PANE=manager:app FLEET_TMUX_SOCKET="$NO_SOCK" fleet_live_children manager:app --fallback-launch
  assert_eq 2 "$RC" "fallback, FLEET_MANAGES unset: exit 2"
  assert_eq "unknown" "$OUT" "fallback, FLEET_MANAGES unset: 'unknown'"
  lib FLEET_PANE=manager:app FLEET_MANAGES="" FLEET_TMUX_SOCKET="$NO_SOCK" fleet_live_children manager:app --fallback-launch
  assert_eq 2 "$RC" "fallback, FLEET_MANAGES empty: exit 2, not 'manages nobody'"
}

test_fallback_not_used_when_the_tree_reads() {
  lib "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" FLEET_MANAGES="nobody" fleet_live_children manager:app --fallback-launch
  assert_eq 0 "$RC" "fallback asked, tree read: exit 0"
  assert_eq "app:deploy
app:writer" "$OUT" "fallback asked, tree read: the live children win"
}

test_usage_error() {
  lib fleet_live_children
  assert_eq 1 "$RC" "no seat: usage error exit 1"
}

test_fleet_sh_live_children_subcommand() {
  fleet "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" live-children manager:app
  assert_eq 0 "$RC" "fleet.sh live-children: exit 0"
  assert_eq "app:deploy
app:writer" "$OUT" "fleet.sh live-children: same list as the lib helper"
  fleet FLEET_TMUX_SOCKET="$NO_SOCK" live-children manager:app
  assert_eq 2 "$RC" "fleet.sh live-children: unreadable → exit 2"
  assert_eq "unknown" "$OUT" "fleet.sh live-children: unreadable → 'unknown'"
}

# The tmux format the helper reads must be hop.sh's, so the two never disagree on the tree shape.
test_tree_format_parity_with_hop() {
  local a b
  a=$(grep -o "list-panes -a -F '[^']*'" "$HOP_SH" | head -1)
  b=$(grep -o "list-panes -a -F '[^']*'" "$LIB_SH" | head -1)
  assert_not_empty "$a" "parity: hop.sh still reads list-panes -a -F"
  assert_eq "$a" "$b" "parity: lib.sh's tree read uses hop.sh's exact format"
}

test_env_value_parse() {
  lib _fleet_env_value FLEET_MANAGES "/usr/bin/claude --x FLEET_MANAGES=no PATH=/bin FLEET_MANAGES=stats,storage TERM=x"
  assert_eq 0 "$RC" "env parse: found"
  assert_eq "stats,storage" "$OUT" "env parse: the LAST FLEET_MANAGES= token (env follows argv)"
  lib _fleet_env_value FLEET_MANAGES "/usr/bin/claude PATH=/bin TERM=x"
  assert_eq 1 "$RC" "env parse: absent → exit 1"
}

# ---------------------------------------------------------------- stale-managers (seam)

launch_env() {
  # <pane> <launch FLEET_MANAGES | - unset | ? unreadable> <@pane_manages | ->
  cat > "$FIX/launch.txt"
}

test_stale_manager_flagged_and_matching_one_passes() {
  launch_env <<'EOF'
%2 stats,storage stats,platform
%5 deploy,writer deploy,writer
%1 domain,app domain,app
EOF
  fleet "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" FLEET_LAUNCH_ENV="$FIX/launch.txt" stale-managers
  assert_eq 3 "$RC" "stale: exit 3"
  assert_has "STALE %2 manager:domain" "$OUT" "stale: the manager whose launch list differs is named with its pane"
  assert_has "launch: stats,storage" "$OUT" "stale: launch list printed"
  assert_has "live:   domain:platform,domain:stats" "$OUT" "stale: live list printed"
  assert_has "launch only: storage" "$OUT" "stale: launch-only entry"
  assert_has "live only: domain:platform" "$OUT" "stale: live-only child"
  assert_has "restart" "$OUT" "stale: says a restart re-exports it"
  assert_has "@pane_manages: stats,platform" "$OUT" "stale: shows what a restart would re-export"
  assert_hasnt "STALE %5" "$OUT" "matching: manager:app (deploy,writer) is not flagged"
  assert_hasnt "STALE %1" "$OUT" "matching: manager:director (label entries) is not flagged"
}

test_restart_note_warns_when_pane_manages_is_stale_too() {
  launch_env <<'EOF'
%2 stats stats
%5 deploy,writer deploy,writer
%1 domain,app domain,app
EOF
  fleet "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" FLEET_LAUNCH_ENV="$FIX/launch.txt" stale-managers
  assert_eq 3 "$RC" "stale pane option: exit 3"
  assert_has "@pane_manages is stale too" "$OUT" "stale pane option: a restart alone would not fix it, and says so"
}

# NIT 1: label entries match as ask-app's listNames does, case-sensitively.
test_label_entry_is_case_sensitive() {
  launch_env <<'EOF'
%2 stats,platform stats,platform
%5 Deploy,writer deploy,writer
%1 domain,app domain,app
EOF
  fleet "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" FLEET_LAUNCH_ENV="$FIX/launch.txt" stale-managers
  assert_has "STALE %5 manager:app" "$OUT" "case: launch 'Deploy' does not name app:deploy (listNames)"
}

test_nothing_stale_exit_0() {
  launch_env <<'EOF'
%2 stats,platform stats,platform
%5 deploy,writer deploy,writer
%1 domain,app domain,app
EOF
  fleet "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" FLEET_LAUNCH_ENV="$FIX/launch.txt" stale-managers
  assert_eq 0 "$RC" "none stale: exit 0"
  assert_hasnt "STALE" "$OUT" "none stale: no STALE line"
  assert_has "3 manager" "$OUT" "none stale: says how many managers it checked"
}

test_launched_with_no_list_but_has_children_is_stale() {
  launch_env <<'EOF'
%2 stats,platform stats,platform
%5 - -
%1 domain,app domain,app
EOF
  fleet "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" FLEET_LAUNCH_ENV="$FIX/launch.txt" stale-managers
  assert_eq 3 "$RC" "no launch list, live children: exit 3"
  assert_has "STALE %5 manager:app" "$OUT" "no launch list, live children: flagged"
}

test_unreadable_manager_env_is_unknown() {
  launch_env <<'EOF'
%2 stats,platform stats,platform
%5 ? deploy,writer
%1 domain,app domain,app
EOF
  fleet "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" FLEET_LAUNCH_ENV="$FIX/launch.txt" stale-managers
  assert_eq 2 "$RC" "unreadable env, nothing else stale: exit 2"
  assert_has "UNKNOWN %5 manager:app" "$OUT" "unreadable env: named as unknown, never as matching"
}

test_stale_managers_unreadable_tree_exit_2() {
  fleet FLEET_TMUX_SOCKET="$NO_SOCK" stale-managers
  assert_eq 2 "$RC" "stale-managers, no tree: exit 2"
  assert_eq "unknown" "$OUT" "stale-managers, no tree: 'unknown'"
}

test_stale_managers_stub_without_marker_ignored() {
  launch_env <<'EOF'
%2 stats stats
EOF
  fleet FLEET_LIVE_PANES="$FIX/tree.txt" FLEET_LAUNCH_ENV="$FIX/launch.txt" FLEET_TMUX_SOCKET="$NO_SOCK" stale-managers
  assert_eq 2 "$RC" "stale-managers, no marker: the stubs are not read"
  assert_hasnt "STALE" "$OUT" "stale-managers, no marker: nothing reported from the stubs"
}

# ---------------------------------------------------------------- stale-managers (production path)
# PATH-stub tmux and ps: the same code the live fleet runs, with no seam and no marker.

make_stubs() {
  mkdir -p "$FIX/bin"
  cat > "$FIX/pids.txt" <<'EOF'
%1 101
%2 102
%5 105
EOF
  cat > "$FIX/opts.txt" <<'EOF'
%2 stats,platform
%5 deploy,writer
EOF
  cat > "$FIX/procs.txt" <<'EOF'
101 1 -zsh
201 101 /opt/bin/claude --resume
102 1 -zsh
202 102 node /opt/bin/claude
105 1 -zsh
205 105 /bin/bash run.sh
305 205 claude
EOF
  cat > "$FIX/envs.txt" <<'EOF'
201 /opt/bin/claude --resume PATH=/bin FLEET_MANAGES=domain,app TERM=x
202 node /opt/bin/claude PATH=/bin FLEET_MANAGES=stats,storage
305 claude PATH=/bin FLEET_MANAGES=deploy,writer
EOF
  cat > "$FIX/bin/tmux" <<EOF
#!/bin/bash
echo "\$*" >> "$FIX/argv"
while [ "\${1:-}" = -S ] || [ "\${1:-}" = -L ]; do shift 2; done
case "\$1" in
  list-panes) cat "$FIX/tree.txt" ;;
  display) awk -v p="\$4" '\$1 == p { print \$2 }' "$FIX/pids.txt" ;;
  show-options) awk -v p="\$5" '\$1 == p { print \$2 }' "$FIX/opts.txt" ;;
  *) exit 1 ;;
esac
EOF
  cat > "$FIX/bin/ps" <<EOF
#!/bin/bash
case "\$1" in
  -A) cat "$FIX/procs.txt" ;;
  eww) p="\${@: -1}"; awk -v p="\$p" '\$1 == p { \$1=""; sub(/^ /, ""); print }' "$FIX/envs.txt" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$FIX/bin/tmux" "$FIX/bin/ps"
}

test_stale_managers_production_path() {
  make_stubs
  fleet PATH="$FIX/bin:$PATH" FLEET_TMUX_SOCKET=stubsock stale-managers
  assert_eq 3 "$RC" "prod path: exit 3"
  assert_has "STALE %2 manager:domain" "$OUT" "prod path: env read via ps eww under the pane's claude"
  assert_has "launch only: storage" "$OUT" "prod path: launch-only entry"
  assert_hasnt "STALE %5" "$OUT" "prod path: claude found two levels down (run.sh → claude) and matches"
  assert_hasnt "STALE %1" "$OUT" "prod path: manager:director matches"
  assert_hasnt "set-option" "$(cat "$FIX/argv")" "prod path: tmux is only read"
  assert_hasnt "send-keys" "$(cat "$FIX/argv")" "prod path: tmux is only read (no send-keys)"
}

# ---------------------------------------------------------------- loader (MUST-FIX 1)
# bash imports exported functions. A stub fleet_live_tree exported into fleet.sh's environment,
# with no marker, must never stand in for the fleet: the loader sources lib.sh regardless.
exported_stub() { # <subcommand…> — fleet.sh with an exported fleet_live_tree/_fleet_children_in stub
  # shellcheck disable=SC2086
  OUT=$(env $SCRUB FLEET_TMUX_SOCKET="$NO_SOCK" "$BASH_BIN" -c '
    fleet_live_tree() { printf "manager:x %%9 -\nw:fake %%8 manager:x\n"; }
    _fleet_children_in() { echo w:fake; }
    fleet_live_children() { echo w:fake; }
    export -f fleet_live_tree _fleet_children_in fleet_live_children
    exec "$0" "$@"' "$FLEET_SH" "$@" 2>"$FIX/err")
  RC=$?
  ERR=$(cat "$FIX/err")
}

test_exported_function_does_not_bypass_live_children() {
  exported_stub live-children manager:x
  assert_eq 2 "$RC" "exported stub, live-children: the real tree is read (exit 2, no server)"
  assert_eq "unknown" "$OUT" "exported stub, live-children: 'unknown', not the stub's child"
}

test_exported_function_does_not_bypass_stale_managers() {
  exported_stub stale-managers
  assert_eq 2 "$RC" "exported stub, stale-managers: exit 2, never 0"
  assert_eq "unknown" "$OUT" "exported stub, stale-managers: 'unknown', no '0 checked' line"
}

test_loader_refuses_a_lib_missing_functions() {
  printf 'fleet_live_tree() { echo "manager:x %%9 -"; }\n' > "$FIX/partial-lib.sh"
  mkdir -p "$FIX/tree/scripts"; cp "$FLEET_SH" "$FIX/tree/scripts/fleet.sh"; cp "$FIX/partial-lib.sh" "$FIX/tree/scripts/lib.sh"
  # shellcheck disable=SC2086
  OUT=$(env $SCRUB HOME="$FIX/nohome" "$BASH_BIN" "$FIX/tree/scripts/fleet.sh" stale-managers 2>"$FIX/err"); RC=$?
  assert_eq 2 "$RC" "partial lib: exit 2"
  assert_eq "unknown" "$OUT" "partial lib: 'unknown'"
}

# NIT 5: an exported shell function named tmux (or ps) must not supply the tree or the env.
test_exported_tmux_function_does_not_supply_the_tree() {
  # shellcheck disable=SC2086
  OUT=$(env $SCRUB FLEET_TMUX_SOCKET="$NO_SOCK" "$BASH_BIN" -c '
    tmux() { printf "manager:x %%9 -\nw:fake %%8 manager:x\n"; }
    ps() { echo "1 0 claude PATH=/x FLEET_MANAGES=bogus"; }
    export -f tmux ps
    exec "$0" "$@"' "$FLEET_SH" live-children manager:x 2>"$FIX/err"); RC=$?
  assert_eq 2 "$RC" "exported tmux fn: the real tmux is asked (no server → exit 2)"
  assert_hasnt "w:fake" "$OUT" "exported tmux fn: the function's tree is not used"
  # shellcheck disable=SC2086
  OUT=$(env $SCRUB FLEET_TMUX_SOCKET="$NO_SOCK" "$BASH_BIN" -c '
    tmux() { printf "manager:x %%9 -\nw:fake %%8 manager:x\n"; }
    export -f tmux
    exec "$0" "$@"' "$FLEET_SH" stale-managers 2>"$FIX/err"); RC=$?
  assert_eq 2 "$RC" "exported tmux fn, stale-managers: exit 2"
  assert_eq "unknown" "$OUT" "exported tmux fn, stale-managers: 'unknown'"
}

# ---------------------------------------------------------------- ps through the marked seam
# Tree via FLEET_LIVE_PANES, ps via FLEET_PS (both only with the marker), tmux display/show-options
# via the PATH stub. This drives agent discovery and the env parse, not the FLEET_LAUNCH_ENV shortcut.
ps_seam() {
  make_stubs
  cp "$FIX/bin/ps" "$FIX/fake-ps"; rm -f "$FIX/bin/ps"
}

test_ps_seam_reads_env_through_agent_discovery() {
  ps_seam
  fleet "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" FLEET_PS="$FIX/fake-ps" PATH="$FIX/bin:$PATH" FLEET_TMUX_SOCKET=stubsock stale-managers
  assert_eq 3 "$RC" "ps seam: exit 3"
  assert_has "STALE %2 manager:domain" "$OUT" "ps seam: manager:domain read through ps eww"
  assert_hasnt "STALE %5" "$OUT" "ps seam: manager:app matches"
}

test_ps_seam_ignored_without_marker() {
  ps_seam
  printf '#!/bin/bash\necho called >> "%s/fake-ps-called"\nexec "%s/fake-ps.real" "$@"\n' "$FIX" "$FIX" > "$FIX/spy-ps"
  mv "$FIX/fake-ps" "$FIX/fake-ps.real"; cp "$FIX/fake-ps.real" "$FIX/bin/ps"; chmod +x "$FIX/spy-ps"
  fleet FLEET_PS="$FIX/spy-ps" PATH="$FIX/bin:$PATH" FLEET_TMUX_SOCKET=stubsock stale-managers
  assert_file_not_exists "$FIX/fake-ps-called" "ps seam, no marker: FLEET_PS is not run"
  assert_eq 1 "$(grep -c 'ignoring a test seam (FLEET_PS)' <<<"$ERR")" "ps seam, no marker: one warning, as the other seams give"
  assert_eq 3 "$RC" "ps seam, no marker: the real (PATH) ps is used"
}

test_ps_manager_with_children_and_no_agent_is_unknown() {
  ps_seam
  # %5's shell has no claude under it any more.
  awk '$1 != 305' "$FIX/procs.txt" > "$FIX/p2" && mv "$FIX/p2" "$FIX/procs.txt"
  awk '$1 != 202' "$FIX/envs.txt" > "$FIX/e2" && mv "$FIX/e2" "$FIX/envs.txt"
  printf '202 node /opt/bin/claude PATH=/bin FLEET_MANAGES=stats,platform\n' >> "$FIX/envs.txt"
  fleet "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" FLEET_PS="$FIX/fake-ps" PATH="$FIX/bin:$PATH" FLEET_TMUX_SOCKET=stubsock stale-managers
  assert_eq 2 "$RC" "no agent under a manager with children: exit 2, never 0"
  assert_has "UNKNOWN %5 manager:app" "$OUT" "no agent: named UNKNOWN"
}

test_ps_showing_no_environment_is_unknown() {
  ps_seam
  awk '$1 != 202 && $1 != 305' "$FIX/envs.txt" > "$FIX/e2" && mv "$FIX/e2" "$FIX/envs.txt"
  printf '202 node /opt/bin/claude\n305 claude PATH=/bin FLEET_MANAGES=deploy,writer\n' >> "$FIX/envs.txt"
  fleet "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" FLEET_PS="$FIX/fake-ps" PATH="$FIX/bin:$PATH" FLEET_TMUX_SOCKET=stubsock stale-managers
  assert_eq 2 "$RC" "ps shows no env: exit 2"
  assert_has "UNKNOWN %2 manager:domain" "$OUT" "ps shows no env: UNKNOWN, not STALE and not clean"
}

test_ps_empty_fleet_manages_with_children_is_stale() {
  ps_seam
  awk '$1 != 202' "$FIX/envs.txt" > "$FIX/e2" && mv "$FIX/e2" "$FIX/envs.txt"
  printf '202 node /opt/bin/claude PATH=/bin FLEET_MANAGES=\n' >> "$FIX/envs.txt"
  fleet "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" FLEET_PS="$FIX/fake-ps" PATH="$FIX/bin:$PATH" FLEET_TMUX_SOCKET=stubsock stale-managers
  assert_eq 3 "$RC" "FLEET_MANAGES= empty, live children: exit 3"
  assert_has "launch: (none)" "$OUT" "FLEET_MANAGES= empty: launch read as an empty list"
}

test_ps_two_claudes_at_one_depth_takes_the_first_listed() {
  ps_seam
  awk '$1 != 202' "$FIX/procs.txt" > "$FIX/p2" && mv "$FIX/p2" "$FIX/procs.txt"
  printf '402 102 claude --first\n403 102 claude --second\n' >> "$FIX/procs.txt"
  printf '402 claude --first PATH=/bin FLEET_MANAGES=stats,platform\n403 claude --second PATH=/bin FLEET_MANAGES=bogus\n' >> "$FIX/envs.txt"
  fleet "$(SEAM)" FLEET_LIVE_PANES="$FIX/tree.txt" FLEET_PS="$FIX/fake-ps" PATH="$FIX/bin:$PATH" FLEET_TMUX_SOCKET=stubsock stale-managers
  assert_hasnt "STALE %2" "$OUT" "two claudes: the first one ps lists is the agent read"
}

run_discovered_tests
