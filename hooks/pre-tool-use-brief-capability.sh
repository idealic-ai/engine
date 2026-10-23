#!/bin/bash
# PreToolUse hook: refuse a dispatch whose brief mandates a write the agent cannot perform.
#
# ¶INV_BRIEF_MATCHES_THE_AGENT — a brief's asserted capability is verified against the
# dispatched agent's actual tool set BEFORE the agent starts.
#
# Both sides of the comparison are already in the dispatcher's hands at this moment: the
# brief is `tool_input.prompt` and the agent is `tool_input.subagent_type`. Nothing compared
# them, so a brief that mandated a file write to an `Explore` lane — a type published
# without Write/Edit/NotebookEdit — was dispatched unexecutable, and the lane spent its whole
# run discovering a contradiction the dispatcher already had the information to prevent.
#
# It is a HARD DENY, not a warning. A finding at a severity nothing acts on would print the
# same thing a passing gate prints, and the dispatch would go out anyway.
#
# It is NOT a permissions check. The question is whether the brief DEMANDS something the
# agent LACKS — two things the dispatcher holds — never what the agent is allowed to do.
#
# WHAT COUNTS AS A DEMAND (deliberately narrow — a false refusal costs a real dispatch):
#   a) a write verb followed, later on the same line, by a file path with an extension
#      — ordering matters: "write your findings to builds/x.md" is a demand, while
#        "builds/x.md records that …" is a reading and is not
#   b) the brief names the Write/Edit/NotebookEdit tool
#   c) the brief instructs a shell write — `engine log `, `cat >`, `tee`, `>> path`
#   d) the brief names a deliverable/output FILE at a path
# A line carrying a negation or a hedge (do not / never / cannot / optional / you may /
# no Write) is vetoed, because briefs routinely tell a read-only lane NOT to write.
#
# DECLARED FALSE NEGATIVE: a brief that demands output without naming a destination
# ("report your findings") is not matched, by design — it is executable by a read-only lane.
#
# Exit is always 0; the verdict travels in the JSON permissionDecision (see
# docs/CONTEXT_GUARDIAN.md for hook_allow/hook_deny).
#
# Tests: scripts/tests/test-brief-capability.sh

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HOOK_DIR/../scripts/lib.sh"
[ -f "$LIB" ] || LIB="$HOME/.claude/scripts/lib.sh"
# shellcheck source=/dev/null
source "$LIB"

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
case "$TOOL_NAME" in
  Task|Agent) ;;
  *) hook_allow ;;
esac

SUBAGENT=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // ""' 2>/dev/null || echo "")
# No type named is the default write-capable agent; `fork` inherits the parent's tools.
[ -n "$SUBAGENT" ] || hook_allow

AGENT_KEY=$(printf '%s' "$SUBAGENT" | tr '[:upper:]' '[:lower:]')

# Claude Code's built-in read-only researchers: published as "all tools except … Edit,
# Write, NotebookEdit". These two are the mechanism behind every measured instance.
CAN_WRITE=1
case "$AGENT_KEY" in
  explore|plan) CAN_WRITE=0 ;;
esac

# A repo-local agent that declares a restricted tool set is covered without editing this list.
AGENT_FILE="$HOOK_DIR/../agents/$AGENT_KEY.md"
if [ "$CAN_WRITE" = "1" ] && [ -f "$AGENT_FILE" ]; then
  TOOLS_LINE=$(awk 'NR==1{if($0!="---")exit; next} $0=="---"{exit} /^tools:/{print; exit}' "$AGENT_FILE" 2>/dev/null || true)
  if [ -n "$TOOLS_LINE" ]; then
    if [[ "$TOOLS_LINE" =~ [Ee]xcept.*([Ww]rite|[Ee]dit) ]]; then
      CAN_WRITE=0
    elif [[ "$TOOLS_LINE" =~ ([Ww]rite|[Ee]dit|\*|[Aa]ll[[:space:]]+tools) ]]; then
      CAN_WRITE=1
    else
      CAN_WRITE=0
    fi
  fi
fi

[ "$CAN_WRITE" = "0" ] || hook_allow

PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // ""' 2>/dev/null || echo "")
[ -n "$PROMPT" ] || hook_allow

shopt -s nocasematch

NEG='(do[[:space:]]+not|don.t|never|cannot|can[[:space:]]+not|must[[:space:]]+not|may[[:space:]]+not|will[[:space:]]+not|no[[:space:]]+need[[:space:]]+to|instead[[:space:]]+of|rather[[:space:]]+than|read-only|optional|unable[[:space:]]+to|you[[:space:]]+may|(no|without)[[:space:]]+(the[[:space:]]+|a[[:space:]]+)?(write|edit))'
VERB='(^|[^a-z])(write|writes|writing|append|appends|appending|create|creates|creating|save|saves|saving|record|records|recording|emit|emits|emitting|land|lands|landing|fill|fills|populate|populates|update|updates|edit|edits|author|authors)([^a-z]|$)'
FILEPATH='[a-z0-9_~./@-]*[a-z0-9_-]\.(md|markdown|json|jsonl|txt|csv|tsv|sh|bash|zsh|ts|tsx|js|jsx|mjs|py|rb|go|rs|java|yaml|yml|toml|ini|sql|html|css|svg|log)([^a-z0-9]|$)'
TOOLNAMED='((^|[^a-z])(write|edit|notebookedit)[[:space:]]*\(|(^|[^a-z])(write|edit)[[:space:]]+tool)'
SHELLWRITE='(engine[[:space:]]+log[[:space:]]|cat[[:space:]]*>|tee[[:space:]]+[a-z0-9_~./-]|>>[[:space:]]*[a-z0-9_~./-]+)'
DELIVERABLE='(deliverable|output|artifact)[[:space:]]+(file|path|document)'

MATCH_LINE=""
MATCH_KIND=""

while IFS= read -r line || [ -n "$line" ]; do
  [ -n "$line" ] || continue
  [[ "$line" =~ $NEG ]] && continue

  if [[ "$line" =~ $VERB.*$FILEPATH ]]; then
    MATCH_LINE="$line"; MATCH_KIND="a write verb naming a file destination"; break
  fi
  if [[ "$line" =~ $TOOLNAMED ]]; then
    MATCH_LINE="$line"; MATCH_KIND="the Write/Edit tool named in the brief"; break
  fi
  if [[ "$line" =~ $SHELLWRITE ]]; then
    MATCH_LINE="$line"; MATCH_KIND="a shell write instruction"; break
  fi
  if [[ "$line" =~ $DELIVERABLE.*$FILEPATH ]]; then
    MATCH_LINE="$line"; MATCH_KIND="a deliverable file the lane is told to own"; break
  fi
done <<< "$PROMPT"

shopt -u nocasematch

[ -n "$MATCH_LINE" ] || hook_allow

# Trim and bound the quoted line so the refusal stays readable. jq slices by codepoint
# whatever the environment; `cut -c` slices codepoints only when LC_CTYPE names a UTF-8
# locale and slices BYTES when it does not, which splits a multibyte character in half and
# emits invalid UTF-8. A hook inherits whatever environment the host hands it, and briefs
# are full of multibyte characters (em dashes, accented names).
QUOTED=$(printf '%s' "$MATCH_LINE" | jq -Rr 'sub("^[[:space:]]+";"") | sub("[[:space:]]+$";"") | .[0:200]' 2>/dev/null || printf '%s' "$MATCH_LINE")
DEST=$(printf '%s' "$MATCH_LINE" | grep -oE '[A-Za-z0-9_~./@-]*[A-Za-z0-9_-]\.(md|markdown|json|jsonl|txt|csv|tsv|sh|bash|zsh|ts|tsx|js|jsx|mjs|py|rb|go|rs|java|yaml|yml|toml|ini|sql|html|css|svg|log)' | head -1 || true)
[ -n "$DEST" ] || DEST="(no path on the matched line — the brief names the write tool or a shell redirect)"

hook_deny \
  "[block: brief-capability] ¶INV_BRIEF_MATCHES_THE_AGENT — dispatch refused: the brief mandates a write the \`${SUBAGENT}\` agent cannot perform." \
  "mandated action: ${MATCH_KIND}
  brief says: ${QUOTED}
  destination: ${DEST}
missing capability: Write / Edit — the \`${SUBAGENT}\` agent type carries no Write, Edit or NotebookEdit tool, so that instruction is unexecutable from the lane's first token.

Change one of the two sides before dispatching:
  - name a write-capable agent type (builder, operator, general-purpose, …), or
  - rewrite the brief so the lane hands its output BACK and the dispatcher lands the file.
A read-only lane briefed to report rather than to write passes this check untouched." \
  "tool=${TOOL_NAME} subagent_type=${SUBAGENT} kind=${MATCH_KIND}"

exit 0
