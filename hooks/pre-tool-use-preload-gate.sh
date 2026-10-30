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

# pending.json is rewritten by this hook and its sibling; serialise with a mkdir
# lock (macOS has no flock). A lockdir older than 5 s is an orphan from a hook
# killed mid-write: reclaim it, so later hooks do not wait out their timeout.
_lock_age() { local m; m=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null) || { echo 0; return; }; echo $(( $(date +%s) - m )); }
_take_lock() {
  local _
  for _ in $(seq 1 100); do
    mkdir "$1" 2>/dev/null && return 0
    [ "$(_lock_age "$1")" -ge 5 ] && rmdir "$1" 2>/dev/null && continue
    sleep 0.05
  done
  return 1
}
LOCK="$PENDING.lockd"
# set_denials <n> — the consecutive-denial counter, kept in pending.json.
set_denials() {
  local got=""
  _take_lock "$LOCK" && got=1
  [ -f "$PENDING" ] && jq --argjson n "$1" '.denials = $n' "$PENDING" > "$PENDING.tmp.$$" 2>/dev/null && mv -f "$PENDING.tmp.$$" "$PENDING"
  rm -f "$PENDING.tmp.$$" 2>/dev/null
  [ -n "$got" ] && rmdir "$LOCK" 2>/dev/null
  return 0
}

if [ "$TOOL" = "Bash" ]; then
  # The named escape hatch must be usable while everything else is blocked:
  # exactly `rm -f <this session's pending.json>`, the path bare or quoted.
  CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
  CMD="${CMD#"${CMD%%[![:space:]]*}"}"; CMD="${CMD%"${CMD##*[![:space:]]}"}"
  case "$CMD" in
    "rm -f $PENDING"|"rm -f '$PENDING'"|"rm -f \"$PENDING\"")
      jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: "Removing this session'"'"'s preload gate record."}}'
      exit 0 ;;
  esac
fi

if [ "$TOOL" = "Read" ]; then
  FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
  if [ -n "$FP" ] && jq -e --arg p "$FP" 'any(.pages[]?; .path == $p)' "$PENDING" >/dev/null 2>&1; then
    [ "$(jq -r '.denials // 0' "$PENDING" 2>/dev/null)" = "0" ] || set_denials 0
    jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: "Reading a page of this session'"'"'s SessionStart preload."}}'
    exit 0
  fi
fi

# A session that cannot read (Read removed with --tools or --disallowedTools)
# would be blocked for good: after DENY_MAX consecutive denials with no page Read
# between them, fail open once, with a warning.
DENY_MAX="${PRELOAD_GATE_MAX_DENIALS:-5}"
DENIALS=$(jq -r '.denials // 0' "$PENDING" 2>/dev/null || echo 0)
if [ "${DENIALS:-0}" -ge "$DENY_MAX" ]; then
  rm -f "$PENDING" 2>/dev/null
  jq -n --arg m "[preload gate] $DENY_MAX tool calls in a row were blocked without a Read of the preload pages, so the read gate is off for this session. Context from SessionStart may not have been read." \
    '{systemMessage: $m}'
  exit 0
fi
set_denials $((DENIALS + 1))

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
Every other tool except AskUserQuestion is blocked until then (denial $((DENIALS + 1)) of $DENY_MAX in a row; after that the gate turns itself off). To turn the gate off now: run exactly \`rm -f $PENDING\` (allowed through the gate), or set PRELOAD_READ_GATE=off." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
