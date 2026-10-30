#!/bin/bash
# PostToolUse hook: records what each Read of a preload page covered, and clears
# the preload read gate once every page is covered.
# A page counts as read when the line ranges its Reads returned, merged, run from
# line 1 to its last line, AND one of those Reads returned its own
# "[END OF PAGE i/N <sha8>]" line. So reading only a page's tail never clears it.
# The range of a Read is [startLine, startLine + numLines - 1] from the response
# (tool_response.file), falling back to tool_input.offset and the content's line
# count when the response does not carry them.
#
# Related: hooks/session-start-chunk.sh (writes the record),
#          hooks/pre-tool-use-preload-gate.sh (enforces it).

set -uo pipefail
trap 'exit 0' ERR

INPUT=$(cat)
[ -n "$(printf '%s' "$INPUT" | jq -r '.agent_id // ""' 2>/dev/null)" ] && exit 0
[ "$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)" = "Read" ] || exit 0

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
[ -n "$SID" ] || exit 0
SID_SAFE=$(printf '%s' "$SID" | tr -c 'A-Za-z0-9._-' '_')
PENDING="${PRELOAD_FILE_DIR:-$HOME/.claude/preload}/$SID_SAFE/pending.json"
[ -f "$PENDING" ] || exit 0

FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
jq -e --arg p "$FP" 'any(.pages[]?; .path == $p)' "$PENDING" >/dev/null 2>&1 || exit 0

# The range this Read returned, and whether it returned the page's END line.
# Captured into variables, not piped into grep -q: under pipefail an early-exiting
# grep fails the producer on a large response and inverts the answer.
CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_response.file.content // (.tool_response | if type == "string" then . else tostring end)' 2>/dev/null)
START=$(printf '%s' "$INPUT" | jq -r '.tool_response.file.startLine // .tool_input.offset // 1' 2>/dev/null)
NUM=$(printf '%s' "$INPUT" | jq -r '.tool_response.file.numLines // empty' 2>/dev/null)
[ -n "$NUM" ] || NUM=$(printf '%s\n' "$CONTENT" | wc -l | tr -d ' ')
END_LINE=$(jq -r --arg p "$FP" '.pages[] | select(.path == $p) | "[END OF PAGE \(.page)/\(.of) \(.sha8)]"' "$PENDING" 2>/dev/null)
SAW_END=false
[[ "$CONTENT" == *"$END_LINE"* ]] && SAW_END=true

# Parallel Reads of several pages fire this hook concurrently: serialise the
# read-modify-write with a mkdir lock (macOS has no flock).
LOCK="$PENDING.lockd"
GOT=""
for _ in $(seq 1 100); do mkdir "$LOCK" 2>/dev/null && { GOT=1; break; }; sleep 0.05; done
[ -n "$GOT" ] && trap 'rmdir "$LOCK" 2>/dev/null; exit 0' EXIT
[ -f "$PENDING" ] || exit 0

jq --arg p "$FP" --argjson s "${START:-1}" --argjson n "${NUM:-0}" --argjson end "$SAW_END" '
  def merge: sort_by(.[0]) | reduce .[] as $r ([]; if length > 0 and $r[0] <= (.[-1][1] + 1)
    then .[-1][1] = ([.[-1][1], $r[1]] | max) else . + [$r] end);
  .pages |= map(if .path == $p and $n > 0 then
      .ranges = (((.ranges // []) + [[$s, $s + $n - 1]]) | merge)
      | .endSeen = ((.endSeen // false) or $end)
      | .done = ((.ranges | length) == 1 and .ranges[0][0] <= 1 and .ranges[0][1] >= .lines and .endSeen)
    else . end)
' "$PENDING" > "$PENDING.tmp.$$" 2>/dev/null && mv -f "$PENDING.tmp.$$" "$PENDING"
rm -f "$PENDING.tmp.$$" 2>/dev/null
if jq -e 'all(.pages[]; .done == true)' "$PENDING" >/dev/null 2>&1; then
  rm -f "$PENDING"
fi
exit 0
