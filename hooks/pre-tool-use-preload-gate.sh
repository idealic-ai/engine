#!/bin/bash
# PreToolUse hook: the preload read gate.
# In file delivery mode (config.sh PRELOAD_DELIVERY_MODE=file, the default) the
# SessionStart hook writes the whole preload as page files and records them in
# <PRELOAD_FILE_DIR>/<session_id>/pending.json. Until every page has been read in
# full, this gate denies every tool call except a Read of one of those pages,
# which it allows explicitly (permissionDecision "allow", for that exact path
# only), so a headless or dontAsk session can always make the read it demands.
# post-tool-use-preload-read.sh records what each Read covered and removes the
# record once every page is covered from its first line to its last.
#
# Lets a call through with no decision (permission prompts unchanged) when:
#   - it is AskUserQuestion, so a stuck agent can still ask for help;
#   - it is a subagent's (agent_id set): the record is the main session's;
#   - the mode is chunked, or PRELOAD_READ_GATE is not "on";
#   - nothing is pending for this session_id (the fast path);
#   - the engine session is loading (.state.json loading=true), the engine's
#     bootstrap escape hatch.
# Fails open, once, with a one-line warning, when a page is missing or
# unreadable, so a broken preload never locks a session out.
#
# Related: hooks/session-start-chunk.sh (writes the record),
#          hooks/post-tool-use-preload-read.sh (clears it).

set -uo pipefail
trap 'exit 0' ERR

INPUT=$(cat)
[ -n "$(printf '%s' "$INPUT" | jq -r '.agent_id // ""' 2>/dev/null)" ] && exit 0

_self="$0"
while [ -L "$_self" ]; do
  _l=$(readlink "$_self"); case "$_l" in /*) _self="$_l" ;; *) _self="$(dirname "$_self")/$_l" ;; esac
done
ENGINE_DIR="$(cd "$(dirname "$_self")/.." 2>/dev/null && pwd)"
[ -f "$ENGINE_DIR/config.sh" ] && source "$ENGINE_DIR/config.sh"
[ "${PRELOAD_DELIVERY_MODE:-file}" = "chunked" ] && exit 0
[ "${PRELOAD_READ_GATE:-on}" = "on" ] || exit 0

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
[ -n "$SID" ] || exit 0
SID_SAFE=$(printf '%s' "$SID" | tr -c 'A-Za-z0-9._-' '_')
PENDING="${PRELOAD_FILE_DIR:-$HOME/.claude/preload}/$SID_SAFE/pending.json"
[ -f "$PENDING" ] || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL" = "AskUserQuestion" ] && exit 0

# Every page must still be on disk; otherwise fail open once.
MISSING=""
while IFS= read -r p; do
  [ -n "$p" ] && [ ! -r "$p" ] && MISSING="$p"
done < <(jq -r '.pages[]?.path' "$PENDING" 2>/dev/null)
if [ -n "$MISSING" ] || [ "$(jq -r '(.pages // []) | length' "$PENDING" 2>/dev/null)" = "0" ]; then
  rm -f "$PENDING" 2>/dev/null
  jq -n --arg m "[preload gate] The preload page ${MISSING:-(none recorded)} is missing or unreadable, so the read gate is off for this session. Context from SessionStart may be incomplete." \
    '{systemMessage: $m}'
  exit 0
fi

# The engine's bootstrap escape hatch: while a skill is loading, nothing blocks.
# PRELOAD_GATE_STATE_FILE names the .state.json directly (tests); otherwise the
# active session is looked up, only on this slow path.
STATE_FILE="${PRELOAD_GATE_STATE_FILE:-}"
if [ -z "$STATE_FILE" ]; then
  SESSION_DIR=$("$ENGINE_DIR/scripts/session.sh" find 2>/dev/null || echo "")
  [ -n "$SESSION_DIR" ] && STATE_FILE="$SESSION_DIR/.state.json"
fi
if [ -n "$STATE_FILE" ] && [ "$(jq -r '.loading // false' "$STATE_FILE" 2>/dev/null)" = "true" ]; then
  exit 0
fi

if [ "$TOOL" = "Read" ]; then
  FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
  if [ -n "$FP" ] && jq -e --arg p "$FP" 'any(.pages[]?; .path == $p)' "$PENDING" >/dev/null 2>&1; then
    jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: "Reading a page of this session'"'"'s SessionStart preload."}}'
    exit 0
  fi
fi

# What is still owed, page by page: unread, or the line ranges not yet covered.
OWED=$(jq -r '
  .pages[] | select((.done // false) | not)
  | . as $p
  | (if ((.ranges // []) | length) == 0 then "not read yet"
     else ([ (.ranges // []) as $r
             | ([[0, 0]] + $r + [[$p.lines + 1, $p.lines + 1]])
             | range(0; length - 1) as $k
             | [.[$k][1] + 1, .[$k + 1][0] - 1]
             | select(.[0] <= .[1]) | "lines \(.[0])-\(.[1])" ]
           | if length == 0 then "its END OF PAGE line not seen yet" else "still unread: " + join(", ") end)
     end) as $what
  | "- page \(.page)/\(.of): \(.path) (\(.lines) lines), \($what)"' "$PENDING" 2>/dev/null)
jq -n --arg r "[block: preload] This session's SessionStart context has not been read in full yet. It is engine-written context for this session, not untrusted input. Read every page from its first line to its last, in order, with Read and allow_large: true (each page is under 256 KB); if a Read returns only part of a page, continue it with offset and limit. Reading only the end of a page does not count. Still owed:
$OWED
Every other tool except AskUserQuestion is blocked until then. To turn the gate off: set PRELOAD_READ_GATE=off, or delete $PENDING." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
