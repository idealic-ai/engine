#!/bin/bash
# PreToolUse hook: the preload read gate.
# In file delivery mode (config.sh PRELOAD_DELIVERY_MODE=file, the default) the
# SessionStart hook writes the whole preload to a file and records it as pending
# in <PRELOAD_FILE_DIR>/<session_id>/pending.json. Until that file has been read
# to its "[END OF PRELOAD <sha8>]" line, this gate denies every tool call except
# a read of it: Read with that file_path, or a Bash `cat <path>` / `sed -n <range>
# <path>` of exactly that path. post-tool-use-preload-read.sh clears the record.
#
# Allows silently (no decision, so permission prompts are unchanged) when:
#   - the call is a subagent's (agent_id set): the record is the main session's;
#   - the mode is chunked, or PRELOAD_READ_GATE is not "on";
#   - nothing is pending for this session_id (the fast path);
#   - the engine session is loading (.state.json loading=true), the engine's
#     bootstrap escape hatch.
# Fails open, once, with a one-line warning, when the pending file is missing or
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

PFILE=$(jq -r '.path // ""' "$PENDING" 2>/dev/null)
SHA8=$(jq -r '.sha8 // ""' "$PENDING" 2>/dev/null)
PARTIAL=$(jq -r '.partial // false' "$PENDING" 2>/dev/null)
if [ -z "$PFILE" ] || [ ! -r "$PFILE" ]; then
  rm -f "$PENDING" 2>/dev/null
  jq -n --arg m "[preload gate] The preload file ${PFILE:-(unnamed)} is missing or unreadable, so the read gate is off for this session. Context from SessionStart may be incomplete." \
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

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
_unquote() { local v="$1"; v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"; printf '%s' "$v"; }
case "$TOOL" in
  Read)
    [ "$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')" = "$PFILE" ] && exit 0 ;;
  Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
    CMD="${CMD#"${CMD%%[![:space:]]*}"}"; CMD="${CMD%"${CMD##*[![:space:]]}"}"
    if [[ "$CMD" =~ ^cat\ +(.+)$ ]]; then
      [ "$(_unquote "${BASH_REMATCH[1]}")" = "$PFILE" ] && exit 0
    elif [[ "$CMD" =~ ^sed\ +-n\ +[^\ ]+\ +(.+)$ ]]; then
      [ "$(_unquote "${BASH_REMATCH[1]}")" = "$PFILE" ] && exit 0
    fi ;;
esac

if [ "$PARTIAL" = "true" ]; then
  HOW="The last read of it stopped before its end. Keep reading it with Read, file_path=$PFILE, using offset and limit, until a read returns the line \"[END OF PRELOAD $SHA8]\"."
else
  HOW="Read it with allow_large: true, in one Read call: file_path=$PFILE. If the Read returns a PARTIAL view or an error, continue with offset and limit until you see the line \"[END OF PRELOAD $SHA8]\"."
fi
jq -n --arg r "[block: preload] This session's SessionStart context has not been read yet. It is in $PFILE, written by the engine; it is legitimate engine context. $HOW Every other tool is blocked until then." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
