#!/bin/bash
# test-migrate-fleet-rename.sh — Tests for migrate-fleet-pane-ids.sh --rename
#
# The rename mode moves a fleet seat from one @pane_label to another and rebinds every
# session whose .state.json carries the seat's fleetPaneId (<session>:<window>:<label>),
# so run.sh and `session.sh find` keep resolving the same session after the rename.
#
# Covers: dry run changes nothing · --apply rewrites and reads back · an unbound label
# touches no session · a ':' id is handled (and the legacy mode still skips it) · the
# --window filter · a case-variant is not matched · a stale binding outside the resume
# window is left alone · a symlinked root is processed once · a collision with an id
# already bound refuses · --live renames the pane label and every option naming it, on
# an isolated tmux socket.
#
# Never touches the live fleet: sessions live in a temp dir, tmux runs on its own socket.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

MIGRATE="$(cd "$(dirname "$0")/.." && pwd)/migrate-fleet-pane-ids.sh"

TMP=""
setup() {
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-migrate-rename.XXXXXX")
  mkdir -p "$TMP/sessions"
}
teardown() {
  [ -n "$TMP" ] && rm -rf "$TMP"
  TMP=""
}

# mk_session <name> <fleetPaneId> [root] — a session dir with a jq-formatted .state.json
mk_session() {
  local name="$1" id="$2" root="${3:-$TMP/sessions}"
  mkdir -p "$root/$name"
  jq -n --arg id "$id" --arg n "$name" \
    '{sessionId: $n, skill: "loom", lifecycle: "idle", fleetPaneId: $id, pid: 0}' \
    > "$root/$name/.state.json"
}
fpid() { jq -r '.fleetPaneId' "$1/.state.json"; }
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
tree_sha() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{print $1}'); }

test_dry_run_changes_nothing() {
  mk_session A "yarik-fleet:domain:Agent"
  local before; before=$(tree_sha "$TMP/sessions")
  local out rc
  out=$("$MIGRATE" --rename Agent agent --force --window domain --roots "$TMP/sessions" 2>&1); rc=$?
  assert_eq 0 "$rc" "dry run exits 0"
  assert_contains "WOULD REBIND" "$out" "dry run names the rebind it would make"
  assert_contains "yarik-fleet:domain:agent" "$out" "dry run shows the new id"
  assert_eq "$before" "$(tree_sha "$TMP/sessions")" "dry run leaves every file byte-identical"
}

test_apply_rebinds_and_reads_back() {
  mk_session A "yarik-fleet:domain:Agent"
  local out rc
  out=$("$MIGRATE" --rename Agent agent --force --window domain --roots "$TMP/sessions" --apply 2>&1); rc=$?
  assert_eq 0 "$rc" "apply exits 0"
  assert_eq "yarik-fleet:domain:agent" "$(fpid "$TMP/sessions/A")" "fleetPaneId rewritten"
  assert_contains "REBOUND (read back)" "$out" "apply reports the read-back"
  assert_eq "loom" "$(jq -r '.skill' "$TMP/sessions/A/.state.json")" "other fields preserved"
  # run.sh resumes by a literal grep — the spacing jq writes must survive the rewrite
  assert_ok "run.sh's literal grep still finds the new id" \
    grep -q '"fleetPaneId": "yarik-fleet:domain:agent"' "$TMP/sessions/A/.state.json"
  local nbak; nbak=$(find "$TMP/sessions/A" -name '.state.json.bak-rename-*' | wc -l | tr -d ' ')
  assert_eq 1 "$nbak" "one backup written beside the state file"
}

test_unbound_label_touches_no_session() {
  mk_session A "yarik-fleet:domain:Platform"
  mk_session B "yarik-fleet:meta:Sessions"
  local before; before=$(tree_sha "$TMP/sessions")
  local out rc
  out=$("$MIGRATE" --rename Docker docker --window services --roots "$TMP/sessions" --apply 2>&1); rc=$?
  assert_eq 0 "$rc" "unbound apply exits 0"
  assert_contains "Rebound: 0" "$out" "reports zero rebinds"
  assert_eq "$before" "$(tree_sha "$TMP/sessions")" "no file changed, no backup written"
}

test_colon_id_handled_and_legacy_still_skips() {
  mk_session A "yarik-fleet:meta:Commands"
  local out
  out=$("$MIGRATE" "$TMP/sessions" 2>&1)
  assert_contains "SKIP (already scoped)" "$out" "legacy mode still skips a ':' id"
  assert_eq "yarik-fleet:meta:Commands" "$(fpid "$TMP/sessions/A")" "legacy mode left it"
  "$MIGRATE" --rename Commands commands --force --window meta --roots "$TMP/sessions" --apply >/dev/null 2>&1
  assert_eq "yarik-fleet:meta:commands" "$(fpid "$TMP/sessions/A")" "rename mode rebinds a ':' id"
}

test_window_filter_and_case_variant() {
  mk_session META "yarik-fleet:meta:Overseer"
  mk_session DOM "yarik-fleet:domain:Overseer"
  mk_session LOW "yarik-fleet:meta:overseer-old"
  mk_session CASE "yarik-fleet:meta:OVERSEER"
  local out
  out=$("$MIGRATE" --rename Overseer overseer --force --window meta --roots "$TMP/sessions" --apply --max-age-days 0 2>&1)
  assert_eq "yarik-fleet:meta:overseer" "$(fpid "$TMP/sessions/META")" "the named window is rebound"
  assert_eq "yarik-fleet:domain:Overseer" "$(fpid "$TMP/sessions/DOM")" "another window's same label is left"
  assert_eq "yarik-fleet:meta:overseer-old" "$(fpid "$TMP/sessions/LOW")" "a label that only starts the same is left"
  assert_eq "yarik-fleet:meta:OVERSEER" "$(fpid "$TMP/sessions/CASE")" "a case-variant is not matched"
  assert_contains "CASE-VARIANT" "$out" "a case-variant is reported"
}

test_stale_binding_left_alone_by_default() {
  mk_session OLD "yarik-fleet:meta:Fleet"
  touch -t 202001010000 "$TMP/sessions/OLD"
  local out
  out=$("$MIGRATE" --rename Fleet fleet --force --window meta --roots "$TMP/sessions" --apply 2>&1)
  assert_eq "yarik-fleet:meta:Fleet" "$(fpid "$TMP/sessions/OLD")" "stale binding outside the window is left"
  assert_contains "STALE" "$out" "stale binding is reported"
  "$MIGRATE" --rename Fleet fleet --force --window meta --roots "$TMP/sessions" --apply --max-age-days 0 >/dev/null 2>&1
  assert_eq "yarik-fleet:meta:fleet" "$(fpid "$TMP/sessions/OLD")" "--max-age-days 0 takes every age"
}

test_symlinked_root_processed_once() {
  mk_session A "yarik-fleet:domain:Language"
  ln -s "$TMP/sessions" "$TMP/alias"
  local out
  out=$("$MIGRATE" --rename Language language --force --window domain --roots "$TMP/sessions" "$TMP/alias" --apply 2>&1)
  assert_contains "Rebound: 1" "$out" "one file reached by two roots is rebound once"
  local nbak; nbak=$(find "$TMP/sessions/A" -name '.state.json.bak-rename-*' | wc -l | tr -d ' ')
  assert_eq 1 "$nbak" "and backed up once"
}

test_collision_refuses() {
  mk_session A "yarik-fleet:domain:Agent"
  mk_session B "yarik-fleet:domain:agent"
  local before; before=$(tree_sha "$TMP/sessions")
  local out rc
  out=$("$MIGRATE" --rename Agent agent --window domain --roots "$TMP/sessions" --apply 2>&1); rc=$?
  assert_eq 2 "$rc" "collision exits 2 (a refusal, not a crash)"
  assert_contains "already bound" "$out" "collision is named"
  assert_eq "$before" "$(tree_sha "$TMP/sessions")" "collision changes nothing"
}

test_bad_args_refuse() {
  local rc
  # exit 2 exactly: a refusal. A crash (1, 127, a signal) must not pass as one (NIT-1)
  "$MIGRATE" --rename Agent Agent --roots "$TMP/sessions" >/dev/null 2>&1; rc=$?
  assert_eq 2 "$rc" "old == new refuses (exit 2)"
  "$MIGRATE" --rename Agent "a:b" --roots "$TMP/sessions" >/dev/null 2>&1; rc=$?
  assert_eq 2 "$rc" "a ':' in the new label refuses (exit 2)"
  "$MIGRATE" --rename Agent --roots "$TMP/sessions" >/dev/null 2>&1; rc=$?
  assert_eq 2 "$rc" "a missing new label refuses (exit 2)"
}

# --- live mode, on an isolated tmux socket ---------------------------------------------
SOCK=""
live_setup() {
  SOCK="renametest-$$"   # not fleet-*: is_fleet_socket must not see test servers
  tmux -L "$SOCK" kill-server 2>/dev/null || true
  tmux -L "$SOCK" new-session -d -s yarik-fleet -n manager -x 120 -y 40
  tmux -L "$SOCK" set-option -g default-size 200x60   # screen fixtures are up to ~125 columns
  SOCK_PATH=$(tmux -L "$SOCK" display-message -p '#{socket_path}')
  tmux -L "$SOCK" new-window -d -t yarik-fleet -n domain
  tmux -L "$SOCK" split-window -d -t yarik-fleet:domain
  tmux -L "$SOCK" new-window -d -t yarik-fleet -n services
  tmux -L "$SOCK" split-window -d -t yarik-fleet:services
  local m d1 d2 s1 s2
  m=$(tmux -L "$SOCK" list-panes -t yarik-fleet:manager -F '#{pane_id}' | head -1)
  d1=$(tmux -L "$SOCK" list-panes -t yarik-fleet:domain -F '#{pane_id}' | sed -n 1p)
  d2=$(tmux -L "$SOCK" list-panes -t yarik-fleet:domain -F '#{pane_id}' | sed -n 2p)
  s1=$(tmux -L "$SOCK" list-panes -t yarik-fleet:services -F '#{pane_id}' | sed -n 1p)
  s2=$(tmux -L "$SOCK" list-panes -t yarik-fleet:services -F '#{pane_id}' | sed -n 2p)
  tmux -L "$SOCK" set-option -p -t "$m" @pane_label domain
  tmux -L "$SOCK" set-option -p -t "$m" @pane_manages "Platform,Agent,stats"
  tmux -L "$SOCK" set-option -p -t "$d1" @pane_label Agent
  tmux -L "$SOCK" set-option -p -t "$d1" @pane_parent "manager:domain"
  tmux -L "$SOCK" set-option -p -t "$d1" @pane_manages "Agentic,x"
  tmux -L "$SOCK" set-option -p -t "$d2" @pane_label Child
  tmux -L "$SOCK" set-option -p -t "$d2" @pane_manager Agent
  tmux -L "$SOCK" set-option -p -t "$d2" @pane_parent "domain:Agent"
  tmux -L "$SOCK" set-option -p -t "$d1" @pane_fleet_id domain-agent
  tmux -L "$SOCK" set-option -p -t "$d2" @pane_manages "domain-agent,ghost-seat,titled-seat"
  tmux -L "$SOCK" set-option -p -t "$s1" @pane_label Terminal
  tmux -L "$SOCK" set-option -p -t "$s2" @pane_label Terminal
  tmux -L "$SOCK" split-window -d -t yarik-fleet:services
  local s3; s3=$(tmux -L "$SOCK" list-panes -t yarik-fleet:services -F '#{pane_id} #{@pane_label}' | awk 'NF==1{print $1; exit}')
  tmux -L "$SOCK" set-option -p -t "$s3" @pane_label tchild
  tmux -L "$SOCK" set-option -p -t "$s3" @pane_manager Terminal
  tmux -L "$SOCK" set-option -p -t "$s3" @pane_parent "services:Terminal"
  P_S3="$s3"
  P_M="$m" P_D1="$d1" P_D2="$d2" P_S1="$s1" P_S2="$s2"
}
# kill-server does not unlink the socket file here, so teardown removes the one this run
# made (NIT-3). Only our own path: renametest-<this pid>.
SOCK_PATH=""
live_teardown() {
  [ -n "$SOCK" ] && tmux -L "$SOCK" kill-server 2>/dev/null
  [ -n "$SOCK_PATH" ] && [[ "$(basename "$SOCK_PATH")" == "renametest-$$" ]] && rm -f "$SOCK_PATH"
  SOCK=""
}
trap 'live_teardown' EXIT
opt() { tmux -L "$SOCK" show-options -p -v -t "$1" "$2" 2>/dev/null; }
all_opts() { local p; for p in $(tmux -L "$SOCK" list-panes -a -F '#{pane_id}'); do echo "== $p"; tmux -L "$SOCK" show-options -p -t "$p" | grep '^@'; done; }

test_live_rename_updates_label_and_references() {
  command -v tmux >/dev/null || { skip "live rename" "no tmux"; return; }
  live_setup
  mk_session A "yarik-fleet:domain:Agent"
  local out snap_before
  snap_before=$(all_opts)
  out=$("$MIGRATE" --rename Agent agent --window domain --roots "$TMP/sessions" --live --socket "$SOCK" 2>&1)
  assert_eq "Agent" "$(opt "$P_D1" @pane_label)" "live dry run leaves the label"
  assert_eq "$snap_before" "$(all_opts)" "live dry run leaves every option on every pane identical"
  assert_eq "yarik-fleet:domain:Agent" "$(fpid "$TMP/sessions/A")" "live dry run leaves the session"
  assert_contains "WOULD SET" "$out" "live dry run names the option change"
  out=$("$MIGRATE" --rename Agent agent --window domain --roots "$TMP/sessions" --live --socket "$SOCK" --apply 2>&1)
  assert_eq "agent" "$(opt "$P_D1" @pane_label)" "label renamed"
  assert_eq "Platform,agent,stats" "$(opt "$P_M" @pane_manages)" "manager's @pane_manages element renamed"
  assert_eq "agent" "$(opt "$P_D2" @pane_manager)" "child's @pane_manager renamed"
  assert_eq "domain:agent" "$(opt "$P_D2" @pane_parent)" "child's @pane_parent renamed"
  assert_eq "Agentic,x" "$(opt "$P_D1" @pane_manages)" "an element that only starts the same is left"
  assert_eq "manager:domain" "$(opt "$P_D1" @pane_parent)" "unrelated parent left"
  assert_eq "yarik-fleet:domain:agent" "$(fpid "$TMP/sessions/A")" "session rebound in the same step"
  assert_contains "LABEL (read back)" "$out" "live apply reads the label back"
  live_teardown
}

test_live_duplicate_needs_pane() {
  command -v tmux >/dev/null || { skip "live duplicate" "no tmux"; return; }
  live_setup
  local out rc
  out=$("$MIGRATE" --rename Terminal terminal-1 --window services --roots "$TMP/sessions" --live --socket "$SOCK" --apply 2>&1); rc=$?
  assert_eq 2 "$rc" "ambiguous duplicate label refuses (exit 2) without --pane"
  assert_eq "Terminal" "$(opt "$P_S1" @pane_label)" "and changes nothing"
  out=$("$MIGRATE" --rename Terminal terminal-1 --window services --roots "$TMP/sessions" --live --socket "$SOCK" --pane "$P_S1" --apply 2>&1); rc=$?
  assert_eq 0 "$rc" "--pane picks one of the duplicates"
  assert_eq "terminal-1" "$(opt "$P_S1" @pane_label)" "that pane renamed"
  assert_eq "Terminal" "$(opt "$P_S2" @pane_label)" "its twin left"
  assert_eq "Terminal" "$(opt "$P_S3" @pane_manager)" "a reference to a still-duplicated label is left (ambiguous)"
  assert_eq "services:Terminal" "$(opt "$P_S3" @pane_parent)" "and so is its parent"
  live_teardown
}

test_live_label_collision_refuses() {
  command -v tmux >/dev/null || { skip "live collision" "no tmux"; return; }
  live_setup
  local rc
  "$MIGRATE" --rename Agent Child --window domain --roots "$TMP/sessions" --live --socket "$SOCK" --apply >/dev/null 2>&1; rc=$?
  assert_eq 2 "$rc" "renaming onto a label another pane carries refuses (exit 2)"
  assert_eq "Agent" "$(opt "$P_D1" @pane_label)" "and changes nothing"
  live_teardown
}

test_session_dir_symlink_rebound_once_backup_keeps_original() {
  # M1: a single session DIR symlinked from a second root (finch/S -> kit/S), as live
  mkdir -p "$TMP/kit" "$TMP/finch"
  mk_session S "yarik-fleet:domain:Platform" "$TMP/kit"
  ln -s "$TMP/kit/S" "$TMP/finch/S"
  local out
  out=$("$MIGRATE" --rename Platform platform --window domain --roots "$TMP/kit" "$TMP/finch" --force --apply --max-age-days 0 2>&1)
  assert_contains "Rebound: 1" "$out" "a symlinked session dir is rebound once"
  local baks; baks=$(find "$TMP/kit/S" -name '.state.json.bak-rename-*')
  assert_eq 1 "$(echo "$baks" | grep -c .)" "one backup"
  assert_eq "yarik-fleet:domain:Platform" "$(jq -r .fleetPaneId "$baks")" "the backup holds the ORIGINAL id"
  assert_eq "yarik-fleet:domain:platform" "$(fpid "$TMP/kit/S")" "the file is rebound"
}

test_session_dir_symlink_not_reported_stale() {
  # M1: the link's own mtime is old, the real dir's is fresh: judge the real dir
  mkdir -p "$TMP/kit" "$TMP/finch"
  mk_session S "yarik-fleet:domain:Platform" "$TMP/kit"
  ln -s "$TMP/kit/S" "$TMP/finch/S"
  touch -h -t 202001010000 "$TMP/finch/S"
  local out
  out=$("$MIGRATE" --rename Platform platform --window domain --roots "$TMP/finch" "$TMP/kit" --force 2>&1)
  assert_not_contains "STALE" "$out" "a fresh session reached through an old link is not called stale"
  assert_contains "would rebind 1 session" "$out" "and it is planned once"
}

test_refuses_rebind_without_live_pane() {
  # S3: without --live (or with no pane carrying the label) a rebind would orphan the session
  mk_session A "yarik-fleet:domain:stats"
  local before; before=$(tree_sha "$TMP/sessions")
  local out rc
  out=$("$MIGRATE" --rename stats Stats --window domain --roots "$TMP/sessions" --apply 2>&1); rc=$?
  assert_eq 2 "$rc" "refuses (exit 2)"
  assert_contains "no live pane will carry" "$out" "names why"
  assert_eq "$before" "$(tree_sha "$TMP/sessions")" "nothing written"
}

test_live_failure_rolls_back_and_summarises() {
  # S4: a set-option that fails mid-apply rolls back what was set, writes no session, prints the summary
  command -v tmux >/dev/null || { skip "live rollback" "no tmux"; return; }
  live_setup
  mk_session A "yarik-fleet:domain:Agent"
  local real; real=$(command -v tmux)
  mkdir -p "$TMP/fakebin"
  cat > "$TMP/fakebin/tmux" <<EOF
#!/bin/bash
for a in "\$@"; do [ "\$a" = "@pane_parent" ] && [ "\$3" = "set-option" ] && exit 1; done
exec "$real" "\$@"
EOF
  chmod +x "$TMP/fakebin/tmux"
  local out rc
  out=$(PATH="$TMP/fakebin:$PATH" "$MIGRATE" --rename Agent agent --window domain --roots "$TMP/sessions" --live --socket "$SOCK" --apply 2>&1); rc=$?
  assert_eq 1 "$rc" "a failed set-option exits 1"
  assert_contains "Errors: 1" "$out" "and still prints the summary"
  assert_eq "Agent" "$(opt "$P_D1" @pane_label)" "the label set before the failure is rolled back"
  assert_eq "Platform,Agent,stats" "$(opt "$P_M" @pane_manages)" "so is the manages list"
  assert_eq "yarik-fleet:domain:Agent" "$(fpid "$TMP/sessions/A")" "no session was rebound"
  live_teardown
}

# --- SHOULD-3: a failure in the session stage rolls back and prints the summary ----------
# fake_bin <name> <script body>: a stand-in on PATH for one migrate run
fake_bin() { mkdir -p "$TMP/fakebin"; printf '#!/bin/bash\n%s\n' "$2" > "$TMP/fakebin/$1"; chmod +x "$TMP/fakebin/$1"; }

test_backup_cp_failure_rolls_back_and_summarises() {
  command -v tmux >/dev/null || { skip "cp failure" "no tmux"; return; }
  live_setup
  mk_session A "yarik-fleet:domain:Agent"
  mk_session B "yarik-fleet:domain:Agent"
  # the SECOND backup copy fails (a full disk, a read-only dir); every other cp is real
  fake_bin cp "case \"\${@: -1}\" in *.bak-rename-*) if [ -e '$TMP/cp.mark' ]; then echo 'cp: fake failure' >&2; exit 1; fi; touch '$TMP/cp.mark';; esac
exec /bin/cp \"\$@\""
  local out rc
  out=$(PATH="$TMP/fakebin:$PATH" "$MIGRATE" --rename Agent agent --window domain --roots "$TMP/sessions" --live --socket "$SOCK" --apply 2>&1); rc=$?
  assert_eq 1 "$rc" "a failed backup copy exits 1 (not errexit's bare death)"
  assert_contains "Errors: 1" "$out" "and still prints the summary"
  assert_contains "ROLLED BACK: $(cd -P "$TMP" && pwd)/sessions/" "$out" "the session rebound before the failure is restored"
  assert_eq "yarik-fleet:domain:Agent" "$(fpid "$TMP/sessions/A")" "session A holds the original id"
  assert_eq "yarik-fleet:domain:Agent" "$(fpid "$TMP/sessions/B")" "session B holds the original id"
  assert_eq "Agent" "$(opt "$P_D1" @pane_label)" "the live label applied before the failure is rolled back"
  assert_eq "Platform,Agent,stats" "$(opt "$P_M" @pane_manages)" "so is the manages list"
  live_teardown
}

# jq_fails_on <n>: the n-th `jq -r .fleetPaneId <file>` of the apply stage fails (1 = the
# id read before the backup, 2 = the read-back after the rewrite)
jq_fails_on() {
  local real; real=$(command -v jq)
  fake_bin jq "if [ \$# -eq 3 ] && [ \"\$1\" = -r ] && [ \"\$2\" = .fleetPaneId ]; then
  n=\$(( \$(cat '$TMP/jq.count' 2>/dev/null || echo 0) + 1 )); echo \$n > '$TMP/jq.count'
  [ \$n -eq $1 ] && { echo 'jq: fake failure' >&2; exit 2; }
fi
exec '$real' \"\$@\""
}

test_id_read_failure_rolls_back_and_summarises() {
  command -v tmux >/dev/null || { skip "jq failure" "no tmux"; return; }
  live_setup
  mk_session A "yarik-fleet:domain:Agent"
  jq_fails_on 1
  local out rc
  out=$(PATH="$TMP/fakebin:$PATH" "$MIGRATE" --rename Agent agent --window domain --roots "$TMP/sessions" --live --socket "$SOCK" --apply 2>&1); rc=$?
  assert_eq 1 "$rc" "an unreadable state file mid-apply exits 1"
  assert_contains "Errors: 1" "$out" "and still prints the summary"
  assert_eq "Agent" "$(opt "$P_D1" @pane_label)" "the live label is rolled back"
  assert_eq "yarik-fleet:domain:Agent" "$(fpid "$TMP/sessions/A")" "the session is untouched"
  live_teardown
}

test_readback_failure_rolls_back_and_summarises() {
  command -v tmux >/dev/null || { skip "read-back failure" "no tmux"; return; }
  live_setup
  mk_session A "yarik-fleet:domain:Agent"
  jq_fails_on 2
  local out rc
  out=$(PATH="$TMP/fakebin:$PATH" "$MIGRATE" --rename Agent agent --window domain --roots "$TMP/sessions" --live --socket "$SOCK" --apply 2>&1); rc=$?
  assert_eq 1 "$rc" "a failed read-back exits 1"
  assert_contains "Errors: 1" "$out" "and still prints the summary"
  assert_eq "yarik-fleet:domain:Agent" "$(fpid "$TMP/sessions/A")" "the rewritten session is restored from its backup"
  assert_eq "Agent" "$(opt "$P_D1" @pane_label)" "the live label is rolled back"
  live_teardown
}

# --- NIT-2: the backup guard, reached by pinning the timestamp ------------------------
test_existing_backup_is_never_overwritten() {
  # The dedupe makes a same-run collision impossible, so the guard is reached here by a
  # fake `date` that returns a timestamp whose backup already exists (a second run within
  # the same second does the same thing for real).
  mk_session A "yarik-fleet:domain:Agent"
  fake_bin date 'if [ "$1" = "+%Y%m%dT%H%M%S" ]; then echo 20200101T000000; else exec /bin/date "$@"; fi'
  echo '{"sentinel": "an earlier backup"}' > "$TMP/sessions/A/.state.json.bak-rename-20200101T000000"
  local out rc
  out=$(PATH="$TMP/fakebin:$PATH" "$MIGRATE" --rename Agent agent --force --window domain --roots "$TMP/sessions" --apply 2>&1); rc=$?
  assert_eq 1 "$rc" "an existing backup stops the run (exit 1)"
  assert_contains "already exists; refusing to overwrite it" "$out" "and names why"
  assert_eq "an earlier backup" "$(jq -r .sentinel "$TMP/sessions/A/.state.json.bak-rename-20200101T000000")" "the earlier backup is untouched"
  assert_eq "yarik-fleet:domain:Agent" "$(fpid "$TMP/sessions/A")" "and the session is not rebound"
}

# --- SHOULD-2: the runbook's recovery when a hook reverts fleetPaneId -------------------
test_recovery_after_hook_revert() {
  command -v tmux >/dev/null || { skip "recovery" "no tmux"; return; }
  live_setup
  mk_session A "yarik-fleet:domain:Agent"
  "$MIGRATE" --rename Agent agent --window domain --roots "$TMP/sessions" --live --socket "$SOCK" --apply >/dev/null 2>&1
  # a hook's read-modify-write lands after the tool's mv: the old id comes back
  jq '.fleetPaneId = "yarik-fleet:domain:Agent"' "$TMP/sessions/A/.state.json" > "$TMP/x" && mv "$TMP/x" "$TMP/sessions/A/.state.json"
  local out rc
  out=$("$MIGRATE" --rename Agent agent --window domain --roots "$TMP/sessions" --live --socket "$SOCK" --apply 2>&1); rc=$?
  assert_eq 2 "$rc" "re-running WITH --live refuses: the label already moved"
  sleep 1   # the recovery's backup name is per-second; keep it distinct from the first run's
  out=$("$MIGRATE" --rename Agent agent --window domain --session yarik-fleet --roots "$TMP/sessions" --force --apply 2>&1); rc=$?
  assert_eq 0 "$rc" "the runbook recovery (--force --apply, no --live) exits 0"
  assert_eq "yarik-fleet:domain:agent" "$(fpid "$TMP/sessions/A")" "and rebinds the reverted session"
  assert_eq "agent" "$(opt "$P_D1" @pane_label)" "the live label is untouched by the recovery"
  live_teardown
}

# --- SHOULD-1: the Handbook shape (a seat whose manager is NOT manager:domain) ----------
test_handbook_shape_moves_docs_manages() {
  command -v tmux >/dev/null || { skip "handbook shape" "no tmux"; return; }
  live_setup
  local docs hb
  tmux -L "$SOCK" split-window -d -t yarik-fleet:manager
  docs=$(tmux -L "$SOCK" list-panes -t yarik-fleet:manager -F '#{pane_id} #{@pane_label}' | awk 'NF==1{print $1; exit}')
  tmux -L "$SOCK" set-option -p -t "$docs" @pane_label docs
  tmux -L "$SOCK" set-option -p -t "$docs" @pane_manages Handbook
  tmux -L "$SOCK" split-window -d -t yarik-fleet:domain
  hb=$(tmux -L "$SOCK" list-panes -t yarik-fleet:domain -F '#{pane_id} #{@pane_label}' | awk 'NF==1{print $1; exit}')
  tmux -L "$SOCK" set-option -p -t "$hb" @pane_label Handbook
  tmux -L "$SOCK" set-option -p -t "$hb" @pane_manager docs
  tmux -L "$SOCK" set-option -p -t "$hb" @pane_parent manager:docs
  mk_session H "yarik-fleet:domain:Handbook"
  local out
  out=$("$MIGRATE" --rename Handbook handbook --window domain --session yarik-fleet --roots "$TMP/sessions" --live --socket "$SOCK" 2>&1)
  assert_contains "WOULD SET: $docs @pane_manages 'Handbook' -> 'handbook'" "$out" "the dry run names manager:docs' manages element"
  assert_not_contains "WOULD SET: $P_M " "$out" "and nothing on manager:domain"
  "$MIGRATE" --rename Handbook handbook --window domain --session yarik-fleet --roots "$TMP/sessions" --live --socket "$SOCK" --apply >/dev/null 2>&1
  assert_eq "handbook" "$(opt "$docs" @pane_manages)" "the apply moves docs' element"
  assert_eq "docs" "$(opt "$hb" @pane_manager)" "Handbook's own manager pointer is left"
  assert_eq "yarik-fleet:domain:handbook" "$(fpid "$TMP/sessions/H")" "and its session is rebound"
  live_teardown
}

# --- NIT-4: a manages element that names no live pane is listed -----------------------
test_dry_run_lists_dangling_manages() {
  command -v tmux >/dev/null || { skip "dangling manages" "no tmux"; return; }
  live_setup
  tmux -L "$SOCK" select-pane -t "$P_S1" -T "✳ titled-seat"   # live titles carry a status glyph
  local out
  out=$("$MIGRATE" --rename Agent agent --window domain --roots "$TMP/sessions" --live --socket "$SOCK" 2>&1)
  assert_contains "DANGLING: $P_M @pane_manages element 'Platform'" "$out" "a label no pane carries is listed"
  assert_contains "DANGLING: $P_D2 @pane_manages element 'ghost-seat'" "$out" "so is a name matching no label, fleet id or title"
  assert_not_contains "element 'domain-agent'" "$out" "an element naming a live @pane_fleet_id is not"
  assert_not_contains "element 'titled-seat'" "$out" "nor one naming a live title behind its status glyph"
  assert_not_contains "element 'Agent'" "$out" "nor one naming a live label"
  live_teardown
}

# --- SHOULD-2 / MUST-1 (round 3): the idle check, on screens captured from real panes ----
# Each screen below is a capture-pane of a real fleet pane (source named on each), cut to
# the region the check reads. The fake `claude` prints one and then idles, or runs the
# process shape named by the kind. Kinds and expected verdicts are in the table in the test.
screens_setup() {
  local d="$TMP/screens"; mkdir -p "$d"
  # %119 domain:stats at 02:49:32, mid-turn; round 2's check called it IDLE
  cat > "$d/real_119.txt" <<'SCREEN'
  So the blocker isn't a decision at all. Telling Language's manager immediately.

❯ /prove -explore ❯ i wanna know   ────────────────────────────────────────────────────────────────────────────────────
  ──────────────────────────────────── what do we do about these issues
  ctrl+x ctrl+s to send now

✳ Deliberating… (3m 54s · ↓ 13.3k tokens)
  ⎿  Tip: Use /btw to ask a quick side question without interrupting Claude's current work

───────────────────────────────────────────────────────────────────────────────────────────────────────── domain:stats ─
❯ Press up to edit queued messages
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  2026_10_28_STATS_LOOM · loom · [1 of 2] Loom · $86.24 · 69%
  ⏵⏵ auto mode on (shift+tab to cycle) · ← 9 agents
SCREEN
  # %118 manager:docs at 02:37 (re-reviewer probe): thinking, no tool child
  cat > "$d/real_thinking.txt" <<'SCREEN'
⏺ Reading the project-specific glyph sentence

✻ Zigzagging… (18m 21s · ↓ 35.2k tokens · thinking)
  ⎿  Tip: Use /btw to ask a quick side question

@@R@@ manager:docs ─
❯
@@R@@
  2026_10_28_DOCS_LOOM · loom · [1 of 2] Loom · $17.18 · 51%
  ⏵⏵ auto mode on · ← 9 agents
SCREEN
  # %134 manager:domain at 02:37 (re-reviewer probe): a turn ending in its Stop hooks
  cat > "$d/real_stophook.txt" <<'SCREEN'
✢ Reticulating… (running Stop hooks… 1/2 · 3s · ↓ 60 tokens)

@@R@@ manager:domain ─
❯
@@R@@
  2026_10_28_DOMAIN_MANAGER_LOOM · loom
  ⏵⏵ auto mode on (shift+tab to cycle)
SCREEN
  # old-style spinner pushed far up by a todo list and queued messages (re-reviewer probe)
  {
    printf '✻ Working… (12s · esc to interrupt)\n'
    for i in 1 2 3 4 5 6 7 8 9; do printf '  ⎿  ☐ todo item %d\n' "$i"; done
    for i in 1 2 3 4 5; do printf '› Message from @manager-domain: queued %d …\n(ctrl+o to expand)\n' "$i"; done
    printf '@@R@@\n❯\n@@R@@\n  ⏵⏵ auto mode on\n'
  } > "$d/old_spinner_far.txt"
  # %5 meta:Sessions at 01:5x and 02:49: a finished turn, an empty box, 8 finished agents;
  # the conversation above mentions shells and agents, which must not count
  cat > "$d/idle.txt" <<'SCREEN'
  Read 1 file, ran 5 shell commands
  I'll leave the deletion and the git worktree prune until the director reports the copies are verified, and until you
  say go.

✻ Crunched for 49s · done 12:02 AM
                                                                               ✔ Update installed · /restart to apply
@@R@@ meta:Sessions ─
❯
@@R@@
  2026_09_15_IDENTITY_MIGRATION · loom · [1 of 2] Loom · $1.78 · 8%
  ⏵⏵ auto mode on (shift+tab to cycle) · ← 8 agents
SCREEN
  # the %119 box with its spinner gone: queued messages alone are BUSY
  sed 's/^✻ Crunched for 49s · done 12:02 AM$//; s/^❯$/❯ Press up to edit queued messages/' "$d/idle.txt" > "$d/queued_only.txt"
  # %26's shape: a multi-line draft typed into the box at idle
  awk '/^❯$/ { print "❯ /session continue the IDE-211 thread once the director"; print "  confirms the copies are verified"; next } { print }' "$d/idle.txt" > "$d/draft.txt"
  # %27 at 01:5x: an open question menu — no box
  cat > "$d/menu.txt" <<'SCREEN'
  Which of these do you want?

❯ 1. △●Ⓢ★ Move both
  2. Keep them apart
  3. Type something.
SCREEN
  # %4 at 01:5x: background shells in the footer
  sed 's/· ← 8 agents$/· 6 shells · ← 9 agents/' "$d/idle.txt" > "$d/shells.txt"
  # %4 / %26 at 01:5x: running subagent rows (◯) in the footer
  { cat "$d/idle.txt"; printf '  ⏺ main\n  ◯ builder  Logging final checks to CMPREALM_LOG.md            48m 1s · ↓ 109.8k tokens\n'; } > "$d/agents.txt"
  printf 'Reading files\n' > "$d/noprompt.txt"
  # no box (a question is open), but the footer still lists running subagents: every reason
  # is reported, not just the missing box
  { cat "$d/menu.txt"; printf '@@R@@\n  ⏵⏵ auto mode on · 4 shells · ← 9 agents\n  ◯ builder  Committing the lock fix   12m 3s · ↓ 88.1k tokens\n'; } > "$d/menu_with_agents.txt"
  local r; r=$(printf '%.0s─' $(seq 1 100))
  for f in "$d"/*.txt; do sed -i '' "s/@@R@@/$r/g" "$f"; done
}

# seat <kind>: a fixture pane whose agent process is a fake `claude` of that kind
seat() {
  tmux -L "$SOCK" new-window -d -P -F '#{pane_id}' -t yarik-fleet -n "s-$1" "bash '$TMP/fakebin/claude' $1"
}
wait_screen() { local i; for i in $(seq 1 30); do
  [ -n "$(tmux -L "$SOCK" capture-pane -p -t "$1" | tr -d '[:space:]')" ] && return 0; sleep 0.1; done; }

test_idle_check_on_real_screens() {
  command -v tmux >/dev/null || { skip "idle check" "no tmux"; return; }
  live_setup
  screens_setup
  mkdir -p "$TMP/fakebin/daemon"
  printf '#!/bin/bash\nsleep 600\n' > "$TMP/fakebin/daemon/claude"; chmod +x "$TMP/fakebin/daemon/claude"
  fake_bin claude 'S="'"$TMP"'/screens"
case "$1" in
  child|caffeine|zombie|daemon) cat "$S/idle.txt" ;;
  *) cat "$S/$1.txt" ;;
esac
case "$1" in
  child)    sleep 600 ;;
  caffeine) caffeinate -i -t 600 & ;;
  zombie)   exec -a claude perl -e "if (fork) { sleep 600 } else { exit 0 }" ;;
  daemon)   bash "'"$TMP"'/fakebin/daemon/claude" daemon run --origin transient & ;;
esac
read -r _'
  # kind | expected verdict | a reason line that must appear (BUSY) or "-"
  local cases='real_119|BUSY|a turn is running: ✳ Deliberating…
real_119|BUSY|Press up to edit queued messages
real_thinking|BUSY|a turn is running: ✻ Zigzagging…
real_stophook|BUSY|a turn is running: ✢ Reticulating…
old_spinner_far|BUSY|a turn is running: ✻ Working…
queued_only|BUSY|Press up to edit queued messages
menu|BUSY|input box (❯ between two rules) is not visible
noprompt|BUSY|input box (❯ between two rules) is not visible
menu_with_agents|BUSY|input box (❯ between two rules) is not visible
menu_with_agents|BUSY|a subagent is running
menu_with_agents|BUSY|background work in the footer: 4 shells
shells|BUSY|background work in the footer: 6 shells
agents|BUSY|a subagent is running
child|BUSY|agent child process
idle|IDLE|-
draft|IDLE|-
caffeine|IDLE|-
zombie|IDLE|not counted as work
daemon|IDLE|not counted as work'
  local k want reason p out rc seen=""
  while IFS='|' read -r k want reason; do
    case " $seen " in *" $k "*) ;; *)
      p=$(seat "$k"); wait_screen "$p"; sleep 0.3; seen="$seen $k"
      eval "P_SEAT_${k}=\$p" ;;
    esac
    eval "p=\$P_SEAT_${k}"
    out=$("$MIGRATE" --idle-check "$p" --socket "$SOCK" 2>&1); rc=$?
    if [ "$want" = IDLE ]; then
      assert_eq 0 "$rc" "idle check: $k is IDLE (exit 0)"
      assert_contains "=> IDLE" "$out" "idle check: $k says IDLE"
    else
      assert_eq 1 "$rc" "idle check: $k is BUSY (exit 1)"
      assert_contains "=> BUSY" "$out" "idle check: $k says BUSY"
    fi
    [ "$reason" = - ] || assert_contains "$reason" "$out" "idle check: $k names '$reason'"
  done <<< "$cases"
  out=$("$MIGRATE" --idle-check %99999 --socket "$SOCK" 2>&1); rc=$?
  assert_eq 2 "$rc" "idle check: an unknown pane is an error (exit 2), not IDLE"
  live_teardown
}

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  run_test "$t"
done
exit_with_results
