#!/bin/bash
# Stop hook: optionally continue the turn instead of stopping — loom-aware.
#
# Hands the turn back with a two-line reason citing §CMD_CONTINUE_ON_STOP, which holds the
# whole of what to do on a wake. SessionStart preloads that atom; this hook queues it only as a
# fallback for a session that was not seeded. Default ON.
#
# ⛔ A Stop hook that blocks is an infinite loop by default: the agent can never end a
# turn and the only exit is killing the process. Three guards, and the toggle is the
# weakest of them:
#   1. autoContinue must not be false in .state.json    (default: absent = ON)
#   2. a hard ceiling on CONSECUTIVE continues          (autoContinueMax, default 3)
#   3. no-op when the last tool CALL of this session's current turn (since the last real
#      user prompt) is AskUserQuestion or ExitPlanMode — a call, not a mention. Note
#      AskUserQuestion resolves IN-turn, so by the time Stop fires the human has already
#      answered: this suppresses a continue just after an answered question rather than
#      preventing one over a pending question.
# The counter resets on any turn this hook does not block, so the ceiling bounds a
# runaway rather than a long session.
#
# Related:
#   ¶INV_HOOKS_NOOP_WHEN_IDLE   — exit 0 immediately when there is nothing to do
#   ¶PTF_EXPLICIT_EXIT_ZERO     — every branch ends in exit 0
#   ¶PTF_BASH32_COMPATIBILITY   — no ((x++)); macOS ships bash 3.2
#   ¶PTF_BLOCKING_CAT_ON_STDIN  — stdin (the Stop hook input) is read once, never with a bare
#                                 `cat`: a bounded `read -t`, skipped when stdin is a tty, so a
#                                 writer that holds stdin open cannot hang the hook
#   ¶PTF_STATE_JSON_RACE        — counter written through safe_json_write

set -uo pipefail

# The Stop hook input is JSON on stdin; its transcript_path names the conversation file the
# harness is writing NOW. Read it before anything else, bounded: `read -d ''` takes the whole
# input up to EOF (it returns non-zero there, hence `|| true`), `-t 2` caps a writer that
# holds stdin open and sends nothing. bash 3.2 has both flags.
INPUT=""
if [ ! -t 0 ]; then
  IFS= read -r -d '' -t 2 INPUT || true
fi

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
# Resolve THIS session's transcript. FIRST from the hook input's transcript_path: it is the
# file the harness is writing this turn. primaryTranscriptKey is set on the first counted tool
# call and is not refreshed when /clear starts a new conversation file, so after a /clear the
# key names a stale file. Measured on kit e58778b2 (2026-10-29): Guard 3b tailed the stale
# file, never found its own injection, and woke an idle agent three times running (test
# STDIN-01). The path is taken only if it names an existing regular file.
JSONL=""
TP=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
if [ -n "${TP:-}" ] && [ -f "$TP" ]; then
  JSONL="$TP"
fi

# Otherwise resolve it by NAME from primaryTranscriptKey. Do not derive its directory from $PWD: a seat
# whose cwd is a worktree computes a slug for a directory that does not exist, every guard
# below is skipped whole, and the hook then injects on every stop until the ceiling — with
# nothing to show it never ran. Measured on a kit seat working in kit-wt/ci-speed whose
# transcript lives under -Users-invizko-Projects-kit. The rule is lib.sh transcript_by_key (the
# cwd's slug first, then every project directory), shared with broadcast's idle_for.
KEY=$(read_state '.primaryTranscriptKey')
if [ -z "$JSONL" ] && [ -n "${KEY:-}" ]; then
  # Guarded: a hook landed without the lib.sh that defines it fails quietly into Guard 3's
  # fail-closed branch below, rather than printing "command not found" on every stop.
  if type transcript_by_key > /dev/null 2>&1; then
    JSONL=$(transcript_by_key "$KEY" "$PWD") || JSONL=""
  fi
fi

# ⛔ Fail CLOSED when this session's transcript cannot be named — neither by the hook input
# nor by the key. Without it the guards below
# cannot tell a turn that did work from one that woke, found nothing and said so — and the
# ceiling is not an answer to that, it only caps how many times we ask. Stopping is the safe
# side: the cost is a turn the human resumes, against a loop the human has to interrupt.
# Never fall back to newest-by-mtime: nine kit seats share one project directory and four of
# them were written in the same minute, so that fallback reads a sibling's turn.
if [ -z "${JSONL:-}" ] || [ ! -f "$JSONL" ]; then
  jq '.autoContinueCount = 0' "$STATE" 2>/dev/null | safe_json_write "$STATE" >/dev/null 2>&1 || true
  exit 0
fi

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

# ── Guard 3: did this turn's LAST tool call ask the human something? ──
# Walk the turn, not a fixed window. A fixed `tail -8` missed most real cases: when the
# question is the turn's last call the harness writes PreToolUse hook lines, the
# tool_result, PostToolUse lines, reminders and the closing text after it before Stop
# fires, and that pushed the call out of the window in 9 of 15 measured Stop points.
# So: over a bounded tail, track the name of the last tool_use, clearing it at every
# real user prompt — a "type":"user" line that is not a tool_result, not isMeta (the Stop
# hook's own feedback and peer messages are isMeta, so a wake is not a new prompt), not a
# background task-notification (origin kind task-notification), and not the harness's
# "[Request interrupted by user" marker (a rejected or interrupted question is still the
# human being asked; measured: 6 of 15 real last-call Stop points carry those lines).
# Suppress when what is left is AskUserQuestion or ExitPlanMode.
# Match the CALL, never the word. The call line is compact JSON —
# "type":"tool_use","id":"…","name":"AskUserQuestion" — and prose about the tool (this
# hook's own atom says "do NOT hand-roll an `AskUserQuestion`", delivered after a wake's
# first call) sits inside an escaped JSON string, where the unescaped key cannot match
# (test BACKOFF-05). 300 lines covers a long turn's tail; the file is not read whole.
LAST_CALL=$(tail -300 "$JSONL" 2>/dev/null | awk '
  /"type":"tool_use","id":"[^"]*","name":"/ {
    s = $0
    while (match(s, /"type":"tool_use","id":"[^"]*","name":"[^"]*"/)) {
      m = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
      sub(/.*"name":"/, "", m); sub(/"$/, "", m); last = m
    }
    next
  }
  /"type":"user"/ && !/"type":"tool_result"/ && !/"isMeta":true/ {
    if (index($0, "\"origin\":{\"kind\":\"task-notification\"")) next
    if (index($0, "[Request interrupted by user")) next
    last = ""
  }
  END { print last }' 2>/dev/null || true)
case "$LAST_CALL" in AskUserQuestion|ExitPlanMode)
  jq '.autoContinueCount = 0' "$STATE" 2>/dev/null | safe_json_write "$STATE" >/dev/null 2>&1 || true
  exit 0 ;;
esac

# ── The reason: two lines that cite the atom. ──
# The guidance itself — finish a /next sequence, a live weave's open rows, /next, send an
# operator-only question up the chain as an ask (/interrogate and /decide only for an
# operator present at this terminal), never manufacture work — lives in the
# ¶CMD_CONTINUE_ON_STOP section of .directives/COMMANDS.md, so this hook and its readers say it once.
# Line 2 is the counter suffix; Guard 3b above finds our own injection by its
# "auto-continues;" text, so that wording is load-bearing — and it must appear in nothing
# else that lands in the transcript, COMMANDS.md included: it is preloaded at SessionStart
# (or, in an unseeded session, delivered by the fallback below after the wake's first tool
# call), so a copy there would become the anchor (test BACKOFF-05).
ATOM="$HOME/.claude/.directives/COMMANDS.md"
REASON="Follow \`§CMD_CONTINUE_ON_STOP\`: carry on the \`/next\` sequence you are in, else invoke \`/next\`; put a question only the operator can answer in an ask, \`engine ask new --to <the first word hop.sh target prints: your parent seat, or operator>\`, never a hand-rolled ask (\`/interrogate\` and \`/decide\` only for an operator present at this terminal, never from a seat with a parent); if nothing is left, say so in one line and stop."

NEW=$((COUNT + 1))
jq ".autoContinueCount = $NEW" "$STATE" 2>/dev/null | safe_json_write "$STATE" >/dev/null 2>&1 || true

# A cited atom that never reaches the agent is a citation to nothing. The atom lives in
# COMMANDS.md, which SessionStart preloads with the core standards (get_session_start_seeds), so
# in a seeded session it is already in preloadedFiles and this call is a skip. It is the fallback
# for a session that lacks COMMANDS.md: the preload guard rule then delivers it in full on the
# agent's next tool call, and preloadedFiles dedup keeps that to once per context.
preload_ensure "$ATOM" "stop-auto-continue" "next" >/dev/null 2>&1 || true

jq -n --arg r "$REASON
($NEW of $MAX auto-continues; set \`autoContinue: false\` in .state.json, or the loom Auto-continue disposition to off, to stop.)" \
  '{decision: "block", reason: $r}' 2>/dev/null || true

exit 0
