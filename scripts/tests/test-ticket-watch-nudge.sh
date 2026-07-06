#!/bin/bash
# ============================================================================
# test-ticket-watch-nudge.sh — Tests for post-tool-use-ticket-watch.sh
# ============================================================================
# PostToolUse nudge: after a Bash `engine session activate`/`phase`, if the
# session subscribes to tickets[] and is NOT already armed, inject an
# additionalContext hint telling the agent to spawn the background watcher.
# Idempotent — silent when armed, when there are no tickets, or when the tool
# call is not a session activate/phase.
# Sandbox pattern mirrors test-post-tool-use-injections.sh.
# ============================================================================
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

REAL_HOME="$HOME"
HOOK="$REAL_HOME/.claude/engine/hooks/post-tool-use-ticket-watch.sh"

TMP=""; SANDBOX=""; SDIR=""

setup() {
  TMP=$(mktemp -d)
  SANDBOX="$TMP/home"
  mkdir -p "$SANDBOX/.claude/scripts"
  ln -sf "$REAL_HOME/.claude/scripts/lib.sh" "$SANDBOX/.claude/scripts/lib.sh"
  cat > "$SANDBOX/.claude/scripts/session.sh" <<'MOCK'
#!/bin/bash
[ "${1:-}" = "find" ] && { echo "$TEST_SESSION_DIR"; exit 0; }
exit 1
MOCK
  chmod +x "$SANDBOX/.claude/scripts/session.sh"
  SDIR="$TMP/sessions/S"
  mkdir -p "$SDIR"
}

teardown() {
  [ -n "$TMP" ] && rm -rf "$TMP"
  TMP=""
}

wstate() { echo "$1" > "$SDIR/.state.json"; }

# nudge <tool_name> <tool_input_json>
nudge() {
  local tn="$1" ti="${2:-{\}}"
  printf '{"tool_name":"%s","tool_input":%s}' "$tn" "$ti" \
    | HOME="$SANDBOX" TEST_SESSION_DIR="$SDIR" "$HOOK" 2>/dev/null
}

# ---- Tests ----

test_inject_on_activate_unarmed() {
  wstate '{"tickets":[{"key":"FIN-9","subscribedAt":"t","lastReadAt":"t"}]}'
  local out; out=$(nudge Bash '{"command":"engine session activate sessions/x implement"}')
  assert_contains 'additionalContext' "$out" "activate + tickets + unarmed → inject additionalContext"
  assert_contains 'engine ticket watch' "$out" "nudge names the exact spawn command"
  assert_contains 'PostToolUse' "$out" "nudge uses the PostToolUse event shape"
}

test_inject_on_phase() {
  wstate '{"tickets":[{"key":"FIN-9","subscribedAt":"t","lastReadAt":"t"}]}'
  local out; out=$(nudge Bash '{"command":"engine session phase 2"}')
  assert_contains 'engine ticket watch' "$out" "session phase transition also nudges when unarmed"
}

test_skip_when_armed() {
  sleep 30 & local lp=$!
  wstate "{\"tickets\":[{\"key\":\"FIN-9\",\"subscribedAt\":\"t\",\"lastReadAt\":\"t\"}],\"watchTaskId\":{\"pid\":$lp,\"startedAt\":\"t\",\"keys\":\"FIN-9\"}}"
  local out; out=$(nudge Bash '{"command":"engine session activate sessions/x implement"}')
  assert_empty "$out" "already armed (live pid) → no nudge (idempotent)"
  kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
}

test_skip_when_no_tickets() {
  wstate '{"tickets":[]}'
  local out; out=$(nudge Bash '{"command":"engine session activate sessions/x implement"}')
  assert_empty "$out" "no tickets → no nudge"
}

test_skip_non_session_command() {
  wstate '{"tickets":[{"key":"FIN-9","subscribedAt":"t","lastReadAt":"t"}]}'
  local out; out=$(nudge Bash '{"command":"ls -la"}')
  assert_empty "$out" "ordinary Bash (not activate/phase) → no nudge"
}

test_skip_no_session() {
  wstate '{"tickets":[{"key":"FIN-9","subscribedAt":"t","lastReadAt":"t"}]}'
  local out
  out=$(printf '{"tool_name":"Bash","tool_input":{"command":"engine session activate sessions/x implement"}}' \
    | HOME="$SANDBOX" TEST_SESSION_DIR="" "$HOOK" 2>/dev/null)
  assert_empty "$out" "no active session → silent"
}

run_discovered_tests
