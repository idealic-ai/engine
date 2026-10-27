#!/bin/bash
# Stop hook: optionally continue the turn instead of stopping — loom-aware.
#
# Asks the agent to do the next thing it already knows about, or to invoke /next when it
# does not. A live weave gets one extra line pointing at its own open rows. Default ON.
#
# ⛔ A Stop hook that blocks is an infinite loop by default: the agent can never end a
# turn and the only exit is killing the process. Three guards, and the toggle is the
# weakest of them:
#   1. autoContinue must not be false in .state.json    (default: absent = ON)
#   2. a hard ceiling on CONSECUTIVE continues          (autoContinueMax, default 3)
#   3. no-op when this session's recent transcript tail carries AskUserQuestion or
#      ExitPlanMode. Note AskUserQuestion resolves IN-turn, so by the time Stop fires the
#      human has already answered: this suppresses a continue just after an answered
#      question rather than preventing one over a pending question.
# The counter resets on any turn this hook does not block, so the ceiling bounds a
# runaway rather than a long session.
#
# Related:
#   ¶INV_HOOKS_NOOP_WHEN_IDLE   — exit 0 immediately when there is nothing to do
#   ¶PTF_EXPLICIT_EXIT_ZERO     — every branch ends in exit 0
#   ¶PTF_BASH32_COMPATIBILITY   — no ((x++)); macOS ships bash 3.2
#   ¶PTF_BLOCKING_CAT_ON_STDIN  — this hook never reads stdin
#   ¶PTF_STATE_JSON_RACE        — counter written through safe_json_write

set -uo pipefail

source "$HOME/.claude/scripts/lib.sh" 2>/dev/null || exit 0

SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
[ -n "$SESSION_DIR" ] || exit 0
STATE="$SESSION_DIR/.state.json"
[ -f "$STATE" ] || exit 0

read_state() { jq -r "$1 // empty" "$STATE" 2>/dev/null || echo ""; }

# ── Guard 1: the toggle. DEFAULT ON — only an explicit false turns it off, which is the
# `Auto-continue` loom disposition's "off" position written into .state.json. Because the
# default is on, the CEILING below is the only thing between this hook and a loop: treat it
# as load-bearing rather than defensive. ──
# ⛔ NOT read_state: `jq '.x // empty'` treats a literal `false` as falsy and returns empty,
# so the off-switch would never fire on a default-ON hook. Read the raw value.
[ "$(jq -r '.autoContinue' "$STATE" 2>/dev/null)" != "false" ] || exit 0

# A session that is not active has nothing to continue.
[ "$(read_state '.lifecycle')" = "active" ] || exit 0

# ── Guard 2: the ceiling on CONSECUTIVE continues. ──
COUNT=$(read_state '.autoContinueCount'); COUNT=${COUNT:-0}
MAX=$(read_state '.autoContinueMax'); MAX=${MAX:-3}
case "$COUNT$MAX" in *[!0-9]*) exit 0 ;; esac
if [ "$COUNT" -ge "$MAX" ]; then
  # Ceiling reached. Reset so the next human turn starts fresh, and let the agent stop.
  jq '.autoContinueCount = 0' "$STATE" 2>/dev/null | safe_json_write "$STATE" >/dev/null 2>&1 || true
  exit 0
fi

# ── Guard 3: did the last turn end by asking the human something? ──
# Tail THIS session's transcript, named from .state.json rather than picked by mtime.
PROJECT_SLUG=$(echo "$PWD" | sed 's|/|-|g')
PROJECTS_DIR="$HOME/.claude/projects/$PROJECT_SLUG"
if [ -d "$PROJECTS_DIR" ]; then
  # Name this session's own transcript. The project directory is shared by every session
  # of this project, so picking by mtime can read a sibling session's turn instead.
  KEY=$(read_state '.primaryTranscriptKey')
  if [ -n "${KEY:-}" ] && [ -f "$PROJECTS_DIR/$KEY" ]; then
    JSONL="$PROJECTS_DIR/$KEY"
  else
    JSONL=$(ls -t "$PROJECTS_DIR"/*.jsonl 2>/dev/null | head -1 || true)
  fi
  if [ -n "${JSONL:-}" ] && [ -f "$JSONL" ]; then
    # ── Guard 3b: did the LAST wake accomplish anything? ──
    # If our own previous injection is in recent history and the agent made no tool
    # call after it, it woke, found nothing to advance, and said so. Waking it again
    # asks a question already answered — and the ceiling is not an answer to that,
    # it just caps how many times we ask. Back off and reset instead.
    RECENT=$(tail -60 "$JSONL" 2>/dev/null || true)
    case "$RECENT" in *"auto-continues;"*)
      # `grep -c` PRINTS 0 and EXITS 1 on no match, so `|| echo 0` would append a
      # second 0 and the arithmetic test below would error on "0\n0".
      # Anchor on the LAST injection, not the first. With several in the window a tool
      # call made after an EARLY one masks an idle turn after the latest — so the guard
      # got weaker the more it fired, which is exactly backwards.
      AFTER=$(printf '%s\n' "$RECENT" \
        | awk '/auto-continues;/{buf=""; next} {buf=buf $0 "\n"} END{printf "%s", buf}' \
        | grep -c '"type":"tool_use"' || true)
      if [ "${AFTER:-0}" -eq 0 ]; then
        jq '.autoContinueCount = 0' "$STATE" 2>/dev/null | safe_json_write "$STATE" >/dev/null 2>&1 || true
        exit 0
      fi ;;
    esac

    TAIL=$(tail -8 "$JSONL" 2>/dev/null || true)
    case "$TAIL" in *AskUserQuestion*|*ExitPlanMode*)
      jq '.autoContinueCount = 0' "$STATE" 2>/dev/null | safe_json_write "$STATE" >/dev/null 2>&1 || true
      exit 0 ;;
    esac
  fi
fi

# ── Branch: a live weave gets its own cadences; a cold session gets /next. ──
SKILL=$(read_state '.skill')
PHASE=$(read_state '.currentPhase')

if [ "$SKILL" = "loom" ] && [ "${PHASE#1}" != "$PHASE" ]; then
  HINT=" In a live weave the next thing is usually an open row — \`🔓 Open claims\`, \`📚 Docs owed\` or \`🗳️ Boards\` in the log."
else
  HINT=""
fi

REASON="If you invoked \`/next\` recently and are part-way through the sequence it named, carry on with its next step.$HINT Otherwise invoke \`/next\`: it reads what state the work is actually in and runs the sequence that advances it, blocking-first. Do not manufacture work — if there is genuinely nothing to advance, say so in one line and stop."

NEW=$((COUNT + 1))
jq ".autoContinueCount = $NEW" "$STATE" 2>/dev/null | safe_json_write "$STATE" >/dev/null 2>&1 || true

jq -n --arg r "$REASON ($NEW of $MAX auto-continues; set \`autoContinue: false\` in .state.json, or the loom Auto-continue disposition to off, to stop.)" \
  '{decision: "block", reason: $r}' 2>/dev/null || true

exit 0
