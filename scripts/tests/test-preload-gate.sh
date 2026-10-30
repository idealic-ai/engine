#!/bin/bash
# Test: the preload read gate (hooks/pre-tool-use-preload-gate.sh) and its clear
# (hooks/post-tool-use-preload-read.sh). The pending record is produced by the
# real chunker in file mode, so the test reads what the hook actually writes.

set -uo pipefail

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; }

ENGINE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CHUNKER="$ENGINE_DIR/hooks/session-start-chunk.sh"
GATE="$ENGINE_DIR/hooks/pre-tool-use-preload-gate.sh"
CLEAR="$ENGINE_DIR/hooks/post-tool-use-preload-read.sh"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export PRELOAD_FILE_DIR="$SANDBOX/preload" PRELOAD_CACHE_DIR="$SANDBOX/cache"
echo '{"loading": false}' > "$SANDBOX/state.json"
export PRELOAD_GATE_STATE_FILE="$SANDBOX/state.json"
unset PRELOAD_DELIVERY_MODE PRELOAD_READ_GATE
SID=gatesid

printf 'line one\n[Preloaded: /fit/A.md]\nbody\n' > "$SANDBOX/fixture.txt"
printf '#!/bin/bash\ncat %q\n' "$SANDBOX/fixture.txt" > "$SANDBOX/gen.sh"; chmod +x "$SANDBOX/gen.sh"
start_session() {   # runs the real SessionStart hook in file mode
  rm -rf "$PRELOAD_CACHE_DIR"
  printf '{"session_id":"%s","source":"startup"}' "$SID" | PRELOAD_GENERATOR="$SANDBOX/gen.sh" bash "$CHUNKER" 0 1 > /dev/null
}
PFILE="$PRELOAD_FILE_DIR/$SID/preload-startup.txt"
PEND="$PRELOAD_FILE_DIR/$SID/pending.json"

# pre <tool> <tool_input-json> [extra-jq] — the gate's stdout.
pre() { jq -nc --arg s "$SID" --arg t "$1" --argjson i "$2" '{session_id:$s, tool_name:$t, tool_input:$i}' | bash "$GATE"; }
post() { jq -nc --arg s "$SID" --arg t "$1" --argjson i "$2" --argjson r "$3" '{session_id:$s, tool_name:$t, tool_input:$i, tool_response:$r}' | bash "$CLEAR"; }
is_deny() { [ "$(printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)" = "deny" ]; }
expect_deny()  { if is_deny "$2"; then pass "$1"; else fail "$1" "got: ${2:0:200}"; fi; }
expect_quiet() { if [ -z "$2" ]; then pass "$1"; else fail "$1" "got: ${2:0:200}"; fi; }

echo "=== G1: before the read, other tools are blocked; the message names the path and allow_large ==="
start_session
[ -f "$PEND" ] && pass "G1pre: SessionStart left a pending record" || fail "G1pre: SessionStart left a pending record"
OUT=$(pre Bash '{"command":"ls"}'); expect_deny "G1a: Bash ls denied" "$OUT"
case "$OUT" in *"$PFILE"*"allow_large: true"*) pass "G1b: deny names path and allow_large" ;; *) fail "G1b: deny names path and allow_large" "${OUT:0:300}" ;; esac
expect_deny "G1c: Read of another file denied" "$(pre Read '{"file_path":"/etc/hosts"}')"
expect_deny "G1d: Edit denied" "$(pre Edit '{"file_path":"/x","old_string":"a","new_string":"b"}')"
expect_deny "G1e: cat of the path chained with another command denied" "$(pre Bash "$(jq -nc --arg c "cat $PFILE && rm -rf /tmp/x" '{command:$c}')")"

echo "=== G2: the read itself is allowed (Read, cat, sed -n) ==="
expect_quiet "G2a: Read of the path allowed" "$(pre Read "$(jq -nc --arg p "$PFILE" '{file_path:$p, allow_large:true}')")"
expect_quiet "G2b: cat of the path allowed" "$(pre Bash "$(jq -nc --arg c "cat '$PFILE'" '{command:$c}')")"
expect_quiet "G2c: sed -n of the path allowed" "$(pre Bash "$(jq -nc --arg c "sed -n 1,400p \"$PFILE\"" '{command:$c}')")"

echo "=== G3: a partial read keeps the gate and switches its message to offset/limit ==="
post Read "$(jq -nc --arg p "$PFILE" '{file_path:$p}')" '{"type":"text","file":{"content":"line one\n"}}'
[ -f "$PEND" ] && pass "G3a: still pending after a read without the END line" || fail "G3a: still pending after a partial read"
OUT=$(pre Bash '{"command":"ls"}'); expect_deny "G3b: still blocked after a partial read" "$OUT"
case "$OUT" in *"stopped before its end"*"offset and limit"*) pass "G3c: message says to continue with offset/limit" ;; *) fail "G3c: message says to continue with offset/limit" "${OUT:0:300}" ;; esac

echo "=== G4: a full read clears it ==="
post Read "$(jq -nc --arg p "$PFILE" '{file_path:$p, allow_large:true}')" "$(jq -nc --arg c "$(cat "$PFILE")" '{type:"text", file:{content:$c}}')"
[ -f "$PEND" ] && fail "G4a: pending cleared after the full read" || pass "G4a: pending cleared after the full read"
expect_quiet "G4b: Bash allowed after the full read" "$(pre Bash '{"command":"ls"}')"
start_session
post Read '{"file_path":"/etc/hosts"}' "$(jq -nc --arg c "$(cat "$PFILE")" '{file:{content:$c}}')"
[ -f "$PEND" ] && pass "G4c: the END line read from another path does not clear it" || fail "G4c: the END line read from another path does not clear it"

echo "=== G5: fail-open, once, with a warning, when the file is missing ==="
start_session; rm -f "$PFILE"
OUT=$(pre Bash '{"command":"ls"}')
is_deny "$OUT" && fail "G5a: missing file does not block" "$OUT" || pass "G5a: missing file does not block"
case "$OUT" in *systemMessage*missing*) pass "G5b: one-line warning" ;; *) fail "G5b: one-line warning" "${OUT:0:200}" ;; esac
expect_quiet "G5c: warning given once, then quiet" "$(pre Bash '{"command":"ls"}')"

echo "=== G6: inert in chunked mode, with the gate off, in a subagent, and while loading ==="
start_session
expect_quiet "G6a: chunked mode allows" "$(jq -nc --arg s "$SID" '{session_id:$s, tool_name:"Bash", tool_input:{command:"ls"}}' | PRELOAD_DELIVERY_MODE=chunked bash "$GATE")"
expect_quiet "G6b: PRELOAD_READ_GATE=off allows" "$(jq -nc --arg s "$SID" '{session_id:$s, tool_name:"Bash", tool_input:{command:"ls"}}' | PRELOAD_READ_GATE=off bash "$GATE")"
expect_quiet "G6c: a subagent's call allows" "$(jq -nc --arg s "$SID" '{session_id:$s, agent_id:"a1", tool_name:"Bash", tool_input:{command:"ls"}}' | bash "$GATE")"
echo '{"loading": true}' > "$SANDBOX/state.json"
expect_quiet "G6d: loading=true allows" "$(pre Bash '{"command":"ls"}')"
echo '{"loading": false}' > "$SANDBOX/state.json"
expect_quiet "G6e: another session_id is not gated" "$(jq -nc '{session_id:"other", tool_name:"Bash", tool_input:{command:"ls"}}' | bash "$GATE")"
expect_deny "G6f: control — the same call in this session is still denied" "$(pre Bash '{"command":"ls"}')"
rm -rf "$PRELOAD_FILE_DIR"
printf '{"session_id":"%s","source":"startup"}' "$SID" | PRELOAD_DELIVERY_MODE=chunked PRELOAD_GENERATOR="$SANDBOX/gen.sh" bash "$CHUNKER" 0 48 > /dev/null
[ -f "$PEND" ] && fail "G6g: chunked SessionStart writes no pending record" || pass "G6g: chunked SessionStart writes no pending record"

echo ""
echo "======================================="
echo "Results: $PASS passed, $FAIL failed"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
