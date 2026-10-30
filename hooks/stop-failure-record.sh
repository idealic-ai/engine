#!/bin/bash
# StopFailure hook: record a turn that an API error ended, where the conductor will read it.
#
# StopFailure fires INSTEAD of Stop when an API error ends the turn (authentication_failed,
# rate_limit, overloaded, server_error, …). Claude Code ignores its output and exit code, so it
# cannot keep the turn going; what it can do is leave a record. Input (code.claude.com/docs/en/
# hooks, "StopFailure input"): the common fields (session_id, transcript_path, cwd, and agent_id
# when the hook fires inside a subagent) plus `error`, optional `error_details` and optional
# `last_assistant_message`.
#
# Where the record goes:
#   a lane (agent_id set) whose own log resolves   -> "## [TAG] lane failed: <error> …" in it
#   a lane whose log does not exist yet            -> the same heading in the session log,
#                                                     saying "no lane log"
#   the conductor's own turn (no agent_id)         -> "## [<time>] conductor turn failed: …"
#                                                     in the session log
#   no active session                              -> nothing
# The lane's tag and log are read from its brief (the first record of its transcript): a
# leading "[TAG]" or a "thread TAG" announcement, and an absolute path to <TAG>_LOG.md, else
# <sessionDir>/builds/<TAG>_LOG.md. The heading carries a [YYYY-MM-DD HH:MM:SS] stamp so
# lane-stall dates it, and the agent id and session id so the conductor can SendMessage the
# lane from that conversation. lane-stall reads the death itself from the transcript
# (state=failed); this heading is the human-readable record beside it, never a second
# instrument (¶INV_LOOM_STALL_IS_SWEPT_NOT_SENSED). Measured case: LANEAUTH, 2026-10-30.
#
# Related:
#   ¶INV_HOOKS_NOOP_WHEN_IDLE   — exit 0 immediately when there is nothing to do
#   ¶PTF_EXPLICIT_EXIT_ZERO     — every branch ends in exit 0
#   ¶PTF_BASH32_COMPATIBILITY   — macOS ships bash 3.2
#   ¶PTF_BLOCKING_CAT_ON_STDIN  — stdin read once, bounded

set -uo pipefail

INPUT=""
if [ ! -t 0 ]; then
  IFS= read -r -d '' -t 2 INPUT || true
fi
[ -n "$INPUT" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

field() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null || true; }

ERROR=$(field '.error')
# Closed alphabet: the value lands in a markdown heading, and a newline in it would plant one.
case "$ERROR" in
  ''|*[!a-z_]*) ERROR="unknown" ;;
esac
AGENT_ID=$(field '.agent_id')
case "$AGENT_ID" in *[!A-Za-z0-9_-]*) AGENT_ID="" ;; esac
CONVO_ID=$(field '.session_id')
case "$CONVO_ID" in *[!A-Za-z0-9_-]*) CONVO_ID="" ;; esac
TP=$(field '.transcript_path')

SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
[ -n "$SESSION_DIR" ] && [ -d "$SESSION_DIR" ] || exit 0

# The session's own log: <SKILL>_LOG.md at its root, else the newest *_LOG.md there.
SKILL=$(jq -r '.skill // empty' "$SESSION_DIR/.state.json" 2>/dev/null || true)
SESSION_LOG=""
if [ -n "$SKILL" ]; then
  SESSION_LOG="$SESSION_DIR/$(printf '%s' "$SKILL" | tr 'a-z-' 'A-Z_')_LOG.md"
fi
if [ -z "$SESSION_LOG" ] || [ ! -f "$SESSION_LOG" ]; then
  SESSION_LOG=$(ls -t "$SESSION_DIR"/*_LOG.md 2>/dev/null | head -1 || true)
fi

NOW=$(date '+%Y-%m-%d %H:%M:%S')
append() { [ -n "$1" ] && printf '\n%s\n' "$2" >> "$1"; }

if [ -z "$AGENT_ID" ]; then
  append "$SESSION_LOG" "## [$NOW] conductor turn failed: $ERROR, session ${CONVO_ID:-unknown}. The API error ended this turn; the next call that succeeds means the API is back, so resume each failed lane by name (SendMessage) before filing any /login ask"
  exit 0
fi

# The lane's transcript: transcript_path itself when it is the lane's file, else the lane's
# file under the conversation's subagents/ directory.
LANE_T=""
case "$TP" in
  */subagents/agent-"$AGENT_ID".jsonl) LANE_T="$TP" ;;
  *.jsonl) LANE_T="${TP%.jsonl}/subagents/agent-$AGENT_ID.jsonl" ;;
esac
BRIEF=""
if [ -n "$LANE_T" ] && [ -f "$LANE_T" ]; then
  BRIEF=$(head -1 "$LANE_T" | jq -r '.message.content
    | if type == "string" then . else (map(.text? // "") | join(" ")) end' 2>/dev/null || true)
fi

TAG=""
TAG_RE='^[[:space:]]*\[([A-Z][A-Z0-9_-]{2,})\]'
THREAD_RE='thread[[:space:]]+(\*\*)?\[?([A-Z][A-Z0-9_-]{2,})'
if [[ "$BRIEF" =~ $TAG_RE ]]; then
  TAG="${BASH_REMATCH[1]}"
elif [[ "${BRIEF:0:400}" =~ $THREAD_RE ]]; then
  TAG="${BASH_REMATCH[2]}"
fi

LANE_LOG=""
if [ -n "$TAG" ]; then
  # An absolute path in the brief naming <TAG>_LOG.md or <TAG>_<KIND>_LOG.md, first one wins.
  while IFS= read -r cand; do
    case "$(basename "$cand")" in
      "${TAG}"_LOG.md|"${TAG}"_*_LOG.md) [ -f "$cand" ] && { LANE_LOG="$cand"; break; } ;;
    esac
  done < <(printf '%s' "$BRIEF" | grep -oE '/[^[:space:]`"'"'"'<>()]+_LOG\.md' || true)
  if [ -z "$LANE_LOG" ] && [ -f "$SESSION_DIR/builds/${TAG}_LOG.md" ]; then
    LANE_LOG="$SESSION_DIR/builds/${TAG}_LOG.md"
  fi
fi

WHO="${TAG:+[$TAG] }"
HEAD="## ${WHO}lane failed: $ERROR at [$NOW], agent $AGENT_ID, session ${CONVO_ID:-unknown}; resume by SendMessage from that session once a call succeeds, re-dispatch from this log only when it has ended"
if [ -n "$LANE_LOG" ]; then
  append "$LANE_LOG" "$HEAD"
else
  append "$SESSION_LOG" "$HEAD (no lane log)"
fi
exit 0
