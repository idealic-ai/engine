#!/bin/bash
# Test: the preload read gate (hooks/pre-tool-use-preload-gate.sh) and its
# coverage tracker (hooks/post-tool-use-preload-read.sh). The pending record and
# the pages come from the real chunker in file mode, so the test reads what the
# hook actually writes. Read responses are built the way Claude Code shapes them:
# tool_response.file {filePath, content, startLine, numLines}.

set -uo pipefail

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; }

ENGINE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CHUNKER="$ENGINE_DIR/hooks/session-start-chunk.sh"
GATE="${GATE:-$ENGINE_DIR/hooks/pre-tool-use-preload-gate.sh}"
CLEAR="${CLEAR:-$ENGINE_DIR/hooks/post-tool-use-preload-read.sh}"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export PRELOAD_FILE_DIR="$SANDBOX/preload" PRELOAD_CACHE_DIR="$SANDBOX/cache"
echo '{"loading": false}' > "$SANDBOX/state.json"
export PRELOAD_GATE_STATE_FILE="$SANDBOX/state.json"
unset PRELOAD_DELIVERY_MODE PRELOAD_READ_GATE PRELOAD_PAGE_LINES PRELOAD_PAGE_BYTES
SID=gatesid
PEND="$PRELOAD_FILE_DIR/$SID/pending.json"
pg() { printf '%s' "$PRELOAD_FILE_DIR/$SID/preload-startup.p$1.txt"; }

printf '#!/bin/bash\ncat %q\n' "$SANDBOX/fixture.txt" > "$SANDBOX/gen.sh"; chmod +x "$SANDBOX/gen.sh"
# start_session <lines> [page-lines] — the real SessionStart hook in file mode.
start_session() {
  : > "$SANDBOX/fixture.txt"
  for ((n=1; n<=$1; n++)); do printf 'L%04d preload line\n' "$n" >> "$SANDBOX/fixture.txt"; done
  rm -rf "$PRELOAD_CACHE_DIR" "$PRELOAD_FILE_DIR"
  printf '{"session_id":"%s","source":"startup"}' "$SID" | PRELOAD_PAGE_LINES="${2:-1990}" PRELOAD_GENERATOR="$SANDBOX/gen.sh" bash "$CHUNKER" 0 1 > /dev/null
}

pre() { jq -nc --arg s "$SID" --arg t "$1" --argjson i "$2" '{session_id:$s, tool_name:$t, tool_input:$i}' | bash "$GATE"; }
# read_page <path> <offset> <limit> — runs the PostToolUse hook for a Read that
# returned lines offset..offset+limit-1 of the file, as Claude Code reports it.
read_page() {
  local p="$1" off="$2" lim="$3" content n
  content=$(sed -n "${off},$((off + lim - 1))p" "$p")
  n=$(sed -n "${off},$((off + lim - 1))p" "$p" | wc -l | tr -d ' ')
  jq -nc --arg s "$SID" --arg p "$p" --arg c "$content" --argjson o "$off" --argjson l "$lim" --argjson n "$n" \
    '{session_id:$s, tool_name:"Read", tool_input:{file_path:$p, offset:$o, limit:$l}, tool_response:{type:"text", file:{filePath:$p, content:$c, startLine:$o, numLines:$n}}}' | bash "$CLEAR"
}
read_whole() { read_page "$1" 1 100000; }
decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null; }
expect_deny()  { if [ "$(decision "$2")" = "deny" ]; then pass "$1"; else fail "$1" "got: ${2:0:200}"; fi; }
expect_allow() { if [ "$(decision "$2")" = "allow" ]; then pass "$1"; else fail "$1" "got: ${2:0:200}"; fi; }
expect_quiet() { if [ -z "$2" ]; then pass "$1"; else fail "$1" "got: ${2:0:200}"; fi; }
pending() { [ -f "$PEND" ]; }
LS='{"command":"ls"}'

echo "=== G1: before the read, other tools are blocked; the message says how, and how to get out ==="
start_session 30 10
{ [ -f "$(pg 1)" ] && [ -f "$(pg 3)" ] && [ ! -e "$(pg 4)" ]; } && pass "G1pre: three pages written" || fail "G1pre: three pages written"
pending && pass "G1pre2: SessionStart left a pending record" || fail "G1pre2: SessionStart left a pending record"
OUT=$(pre Bash "$LS"); expect_deny "G1a: Bash ls denied" "$OUT"
case "$OUT" in *"$(pg 1)"*"$(pg 2)"*"$(pg 3)"*) pass "G1b: deny lists every page, in order" ;; *) fail "G1b: deny lists every page, in order" "${OUT:0:300}" ;; esac
case "$OUT" in *"allow_large: true"*"PRELOAD_READ_GATE=off"*"$PEND"*) pass "G1c: deny names allow_large and both escape hatches" ;; *) fail "G1c: deny names allow_large and both escape hatches" "${OUT:0:400}" ;; esac
expect_deny "G1d: Read of another file denied" "$(pre Read '{"file_path":"/etc/hosts"}')"
expect_deny "G1e: Edit denied" "$(pre Edit '{"file_path":"/x","old_string":"a","new_string":"b"}')"
expect_deny "G1f: Bash cat of a page is not an allowed read" "$(pre Bash "$(jq -nc --arg c "cat $(pg 1)" '{command:$c}')")"

echo "=== G2: a Read of a page is allowed explicitly; AskUserQuestion passes ==="
expect_allow "G2a: Read of page 1 gets permissionDecision allow" "$(pre Read "$(jq -nc --arg p "$(pg 1)" '{file_path:$p, allow_large:true}')")"
expect_allow "G2b: Read of page 3 (out of order) is allowed too" "$(pre Read "$(jq -nc --arg p "$(pg 3)" '{file_path:$p}')")"
expect_quiet "G2c: AskUserQuestion passes with no decision" "$(pre AskUserQuestion '{"questions":[]}')"

echo "=== G3: reading only the end never clears it (the critic's offset-3040 case) ==="
start_session 3101
P2L=$(wc -l < "$(pg 2)" | tr -d ' ')
read_page "$(pg 1)" 1950 100           # page 1's tail, its END line included
read_page "$(pg 2)" 1050 100           # page 2's tail: both END lines included
pending && pass "G3a: tails of both pages, END lines seen: still pending" || fail "G3a: tails of both pages, END lines seen: still pending"
OUT=$(pre Bash "$LS"); expect_deny "G3b: still blocked" "$OUT"
case "$OUT" in *"still unread: lines 1-1949"*"still unread: lines 1-1049"*) pass "G3c: deny names the unread ranges of each page" ;; *) fail "G3c: deny names the unread ranges of each page" "${OUT:0:500}" ;; esac
read_page "$(pg 1)" 1 1949
read_page "$(pg 2)" 1 1049
pending && fail "G3d: reading the missing ranges too clears it" || pass "G3d: reading the missing ranges too clears it"

echo "=== G4: every page must be covered; a page read in two halves counts ==="
start_session 30 10
read_whole "$(pg 1)"; read_whole "$(pg 2)"
pending && pass "G4a: two of three pages read: still pending" || fail "G4a: two of three pages read: still pending"
OUT=$(pre Bash "$LS")
case "$OUT" in *"$(pg 3)"*) pass "G4b: deny names the page still owed" ;; *) fail "G4b: deny names the page still owed" "${OUT:0:300}" ;; esac
case "$OUT" in *"page 1/3"*) fail "G4c: deny no longer lists a finished page" "${OUT:0:300}" ;; *) pass "G4c: deny no longer lists a finished page" ;; esac
read_page "$(pg 3)" 1 6; read_page "$(pg 3)" 7 100
pending && fail "G4d: the last page read in two halves clears it" || pass "G4d: the last page read in two halves clears it"
expect_quiet "G4e: Bash allowed after the full read" "$(pre Bash "$LS")"

echo "=== G5: the END line must carry the page's own sha8 ==="
start_session 5
P=$(pg 1); FAKE=$(sed '$d' "$P" | sed '$d'; echo "[END OF PAGE 1/1 00000000]"; tail -n 1 "$P")
jq -nc --arg s "$SID" --arg p "$P" --arg c "$FAKE" --argjson n "$(wc -l < "$P" | tr -d ' ')" \
  '{session_id:$s, tool_name:"Read", tool_input:{file_path:$p}, tool_response:{file:{filePath:$p, content:$c, startLine:1, numLines:$n}}}' | bash "$CLEAR"
pending && pass "G5a: a full range with a wrong END sha does not clear" || fail "G5a: a full range with a wrong END sha does not clear"
read_whole "$P"
pending && fail "G5b: the genuine END line clears" || pass "G5b: the genuine END line clears"

echo "=== G6: a response without startLine/numLines falls back to offset and the content ==="
start_session 5
P=$(pg 1)
jq -nc --arg s "$SID" --arg p "$P" --arg c "$(tail -n 2 "$P")" '{session_id:$s, tool_name:"Read", tool_input:{file_path:$p, offset:6}, tool_response:{file:{filePath:$p, content:$c}}}' | bash "$CLEAR"
pending && pass "G6a: a tail with no range fields does not clear" || fail "G6a: a tail with no range fields does not clear"
jq -nc --arg s "$SID" --arg p "$P" --arg c "$(cat "$P")" '{session_id:$s, tool_name:"Read", tool_input:{file_path:$p}, tool_response:{file:{filePath:$p, content:$c}}}' | bash "$CLEAR"
pending && fail "G6b: the whole page with no range fields clears" || pass "G6b: the whole page with no range fields clears"

echo "=== G7: fail-open, once, with a warning, when a page is missing ==="
start_session 30 10; rm -f "$(pg 2)"
OUT=$(pre Bash "$LS")
[ "$(decision "$OUT")" = "deny" ] && fail "G7a: missing page does not block" "$OUT" || pass "G7a: missing page does not block"
case "$OUT" in *systemMessage*missing*) pass "G7b: one-line warning" ;; *) fail "G7b: one-line warning" "${OUT:0:200}" ;; esac
expect_quiet "G7c: warning given once, then quiet" "$(pre Bash "$LS")"

echo "=== G8: inert in chunked mode, with the gate off, in a subagent, while loading, for another session ==="
start_session 30 10
expect_quiet "G8a: chunked mode allows" "$(jq -nc --arg s "$SID" '{session_id:$s, tool_name:"Bash", tool_input:{command:"ls"}}' | PRELOAD_DELIVERY_MODE=chunked bash "$GATE")"
expect_quiet "G8b: PRELOAD_READ_GATE=off allows" "$(jq -nc --arg s "$SID" '{session_id:$s, tool_name:"Bash", tool_input:{command:"ls"}}' | PRELOAD_READ_GATE=off bash "$GATE")"
expect_quiet "G8c: a subagent's call allows" "$(jq -nc --arg s "$SID" '{session_id:$s, agent_id:"a1", tool_name:"Bash", tool_input:{command:"ls"}}' | bash "$GATE")"
echo '{"loading": true}' > "$SANDBOX/state.json"
expect_quiet "G8d: loading=true allows" "$(pre Bash "$LS")"
echo '{"loading": false}' > "$SANDBOX/state.json"
expect_quiet "G8e: another session_id is not gated" "$(jq -nc '{session_id:"other", tool_name:"Bash", tool_input:{command:"ls"}}' | bash "$GATE")"
expect_deny "G8f: control — the same call in this session is still denied" "$(pre Bash "$LS")"
rm -rf "$PRELOAD_FILE_DIR"
printf '{"session_id":"%s","source":"startup"}' "$SID" | PRELOAD_DELIVERY_MODE=chunked PRELOAD_GENERATOR="$SANDBOX/gen.sh" bash "$CHUNKER" 0 48 > /dev/null
pending && fail "G8g: chunked SessionStart writes no pending record" || pass "G8g: chunked SessionStart writes no pending record"

echo "=== G9: three pages read in parallel — no update lost ==="
start_session 30 10
read_whole "$(pg 1)" & A=$!; read_whole "$(pg 2)" & B=$!; read_whole "$(pg 3)" & C=$!
wait "$A" "$B" "$C"
pending && fail "G9: parallel full reads clear it" "$(cat "$PEND")" || pass "G9: parallel full reads clear it"

echo ""
echo "======================================="
echo "Results: $PASS passed, $FAIL failed"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
