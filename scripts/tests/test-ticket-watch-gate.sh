#!/bin/bash
# ============================================================================
# test-ticket-watch-gate.sh — Tests for pre-tool-use-ticket-watch-gate.sh
# ============================================================================
# The hard gate that forces any session subscribed to tickets[] to arm a
# background `engine ticket watch`. Verifies:
#   noop when no active session / empty tickets[]  → allow (never blocks)
#   armed (live watchTaskId.pid via kill -0)        → allow
#   whitelist (engine ticket watch spawn, AskUserQuestion, Skill, engine bookkeeping)
#   grace window then hard-block with the spawn instruction
#   re-arm: a dead watchTaskId.pid re-blocks (and is opportunistically cleared)
# Sandbox pattern mirrors test-post-tool-use-injections.sh (mock session.sh + lib.sh).
# ============================================================================
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

REAL_HOME="$HOME"
HOOK="$REAL_HOME/.claude/engine/hooks/pre-tool-use-ticket-watch-gate.sh"

TMP=""; SANDBOX=""; SDIR=""

setup() {
  TMP=$(mktemp -d)
  export CLAUDE_SUPERVISOR_PID=88881111
  export CLAUDE_HOOK_WARNED_DIR="$TMP/grace"
  unset CLAUDE_TICKET_WATCH_GRACE 2>/dev/null || true
  mkdir -p "$TMP/grace"

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

# gate <tool_name> <tool_input_json> — run the gate against $SDIR
gate() {
  local tn="$1" ti="${2:-{\}}"
  printf '{"tool_name":"%s","tool_input":%s}' "$tn" "$ti" \
    | HOME="$SANDBOX" TEST_SESSION_DIR="$SDIR" "$HOOK" 2>/dev/null
}

# ---- Tests ----

test_noop_when_no_active_session() {
  wstate '{"tickets":[{"key":"FIN-9","subscribedAt":"t","lastReadAt":"t"}]}'
  local out
  out=$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
    | HOME="$SANDBOX" TEST_SESSION_DIR="" "$HOOK" 2>/dev/null)
  assert_empty "$out" "no active session → silent exit (no stray stdout)"
}

test_noop_when_no_tickets() {
  wstate '{"tickets":[]}'
  local out; out=$(gate Bash '{"command":"ls -la"}')
  assert_contains '"allow"' "$out" "empty tickets[] → allow any tool"
  assert_not_contains '"deny"' "$out" "empty tickets[] never denies"
}

test_allow_when_armed_live_pid() {
  sleep 30 & local lp=$!
  wstate "{\"tickets\":[{\"key\":\"FIN-9\",\"subscribedAt\":\"t\",\"lastReadAt\":\"t\"}],\"watchTaskId\":{\"pid\":$lp,\"startedAt\":\"t\",\"keys\":\"FIN-9\"}}"
  export CLAUDE_TICKET_WATCH_GRACE=0
  local out; out=$(gate Bash '{"command":"ls"}')
  assert_contains '"allow"' "$out" "live watchTaskId.pid (kill -0) → allow even at grace 0"
  kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
}

test_allow_spawn_command() {
  wstate '{"tickets":[{"key":"FIN-9","subscribedAt":"t","lastReadAt":"t"}]}'
  export CLAUDE_TICKET_WATCH_GRACE=0
  local out; out=$(gate Bash '{"command":"engine ticket watch --timeout 1800"}')
  assert_contains '"allow"' "$out" "the arming command (engine ticket watch) is whitelisted, even at grace 0"
}

test_allow_ask_and_skill() {
  wstate '{"tickets":[{"key":"FIN-9","subscribedAt":"t","lastReadAt":"t"}]}'
  export CLAUDE_TICKET_WATCH_GRACE=0
  local out
  out=$(gate AskUserQuestion '{}')
  assert_contains '"allow"' "$out" "AskUserQuestion whitelisted (never lock out asking)"
  out=$(gate Skill '{"skill":"communicate"}')
  assert_contains '"allow"' "$out" "Skill whitelisted (never lock out skills)"
}

test_allow_engine_bookkeeping() {
  wstate '{"tickets":[{"key":"FIN-9","subscribedAt":"t","lastReadAt":"t"}]}'
  export CLAUDE_TICKET_WATCH_GRACE=0
  local out
  out=$(gate Bash '{"command":"engine ticket read"}')
  assert_contains '"allow"' "$out" "engine ticket bookkeeping whitelisted"
  out=$(gate Bash '{"command":"engine log sessions/x/LOG.md"}')
  assert_contains '"allow"' "$out" "engine log whitelisted (agent must keep logging)"
}

test_grace_then_block() {
  wstate '{"tickets":[{"key":"FIN-9","subscribedAt":"t","lastReadAt":"t"}]}'
  export CLAUDE_TICKET_WATCH_GRACE=2
  local out
  out=$(gate Bash '{"command":"ls"}');  assert_contains '"allow"' "$out" "ordinary tool #1 within grace → allow"
  out=$(gate Bash '{"command":"ls"}');  assert_contains '"allow"' "$out" "ordinary tool #2 within grace → allow"
  out=$(gate Bash '{"command":"ls"}');  assert_contains '"deny"'  "$out" "ordinary tool #3 past grace, unarmed → deny"
  assert_contains 'engine ticket watch' "$out" "deny message carries the exact spawn command"
  assert_contains 'FIN-9' "$out" "deny message names the subscribed ticket(s)"
}

test_re_arm_after_pid_dies() {
  export CLAUDE_TICKET_WATCH_GRACE=0
  sleep 30 & local lp=$!
  wstate "{\"tickets\":[{\"key\":\"FIN-9\",\"subscribedAt\":\"t\",\"lastReadAt\":\"t\"}],\"watchTaskId\":{\"pid\":$lp,\"startedAt\":\"t\",\"keys\":\"FIN-9\"}}"
  local out; out=$(gate Bash '{"command":"ls"}')
  assert_contains '"allow"' "$out" "armed → allow"
  kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
  out=$(gate Bash '{"command":"ls"}')
  assert_contains '"deny"' "$out" "after the watcher pid dies, the gate re-blocks"
  assert_empty "$(jq -r '.watchTaskId.pid // empty' "$SDIR/.state.json" 2>/dev/null)" "dead watchTaskId opportunistically cleared"
}

run_discovered_tests
