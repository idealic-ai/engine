#!/bin/bash
# PostToolUse hook: clears the preload read gate once the preload has been read.
# When a Read (or a Bash cat/sed) of the pending preload file returns content that
# contains its "[END OF PRELOAD <sha8>]" line, the pending record is removed and
# pre-tool-use-preload-gate.sh stops blocking. A read of that file that stops
# short marks the record partial, so the gate's message says to continue with
# offset and limit.
#
# Related: hooks/session-start-chunk.sh (writes the record),
#          hooks/pre-tool-use-preload-gate.sh (enforces it).

set -uo pipefail
trap 'exit 0' ERR

INPUT=$(cat)
[ -n "$(printf '%s' "$INPUT" | jq -r '.agent_id // ""' 2>/dev/null)" ] && exit 0

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
[ -n "$SID" ] || exit 0
SID_SAFE=$(printf '%s' "$SID" | tr -c 'A-Za-z0-9._-' '_')
PENDING="${PRELOAD_FILE_DIR:-$HOME/.claude/preload}/$SID_SAFE/pending.json"
[ -f "$PENDING" ] || exit 0

PFILE=$(jq -r '.path // ""' "$PENDING" 2>/dev/null)
SHA8=$(jq -r '.sha8 // ""' "$PENDING" 2>/dev/null)
[ -n "$PFILE" ] || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL" in
  Read) [ "$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')" = "$PFILE" ] || exit 0 ;;
  Bash) CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""'); [[ "$CMD" == *"$PFILE"* ]] || exit 0 ;;
  *) exit 0 ;;
esac

# The response's shape differs by tool; search all of it as text. Captured into a
# variable, not piped into grep -q: under pipefail an early-exiting grep fails the
# producer on a large response and inverts the answer.
RESP=$(printf '%s' "$INPUT" | jq -r '.tool_response | tostring' 2>/dev/null)
if [[ "$RESP" == *"[END OF PRELOAD $SHA8]"* ]]; then
  rm -f "$PENDING"
else
  jq '.partial = true' "$PENDING" > "$PENDING.tmp.$$" 2>/dev/null && mv -f "$PENDING.tmp.$$" "$PENDING"
  rm -f "$PENDING.tmp.$$" 2>/dev/null
fi
exit 0
