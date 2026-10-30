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
# unreadable, so a broken preload never locks a session out, and when the calls
# keep being denied with no page Read between them (PRELOAD_GATE_MAX_DENIALS,
# default 5, counted at most once per PRELOAD_GATE_DENIAL_GAP seconds, default
# 3), so a session without the Read tool is not blocked for good.
# Allows exactly `rm -f <pending.json>`, the escape command the deny message names.
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

# pending.json is rewritten by this hook and its sibling; serialise with a mkdir
# lock (macOS has no flock). The lock directory holds an owner token, and only
# its owner removes it. A lock older than 5 s is an orphan from a hook killed
# mid-write: reclaim it, so later hooks do not wait out their timeout. The mtime
# comes from `date -r`, which BSD and GNU date both read as a file's mtime; the
# stat fallbacks are ordered GNU first, because GNU stat reads `-f` as
# "filesystem status" and prints a report instead of failing.
_mtime() { date -r "$1" +%s 2>/dev/null || stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
_lock_age() { local m; m=$(_mtime "$1") || m=""; case "$m" in ''|*[!0-9]*) echo 0 ;; *) echo $(( $(date +%s) - m )) ;; esac; }
LOCK_TOKEN="$$.${RANDOM}"
_take_lock() {
  local _
  for _ in $(seq 1 100); do
    if mkdir "$1" 2>/dev/null; then printf '%s' "$LOCK_TOKEN" > "$1/owner" 2>/dev/null || true; return 0; fi
    if [ "$(_lock_age "$1")" -ge 5 ]; then rm -f "$1/owner" 2>/dev/null || true; rmdir "$1" 2>/dev/null || true; continue; fi
    sleep 0.05
  done
  return 1
}
_drop_lock() { if [ "$(cat "$1/owner" 2>/dev/null)" = "$LOCK_TOKEN" ]; then rm -f "$1/owner" 2>/dev/null || true; rmdir "$1" 2>/dev/null || true; fi; return 0; }
LOCK="$PENDING.lockd"
# write_pending <jq filter> [jq args...] — rewrite pending.json; call under the lock.
write_pending() {
  local f="$1"; shift
  if jq "$@" "$f" "$PENDING" > "$PENDING.tmp.$$" 2>/dev/null; then mv -f "$PENDING.tmp.$$" "$PENDING" 2>/dev/null || true; fi
  rm -f "$PENDING.tmp.$$" 2>/dev/null || true
  return 0
}
# fail_open <message> — remove the record under the lock and let the call through
# with one warning.
fail_open() {
  local got=""
  _take_lock "$LOCK" && got=1
  rm -f "$PENDING" 2>/dev/null || true
  [ -n "$got" ] && _drop_lock "$LOCK"
  jq -n --arg m "$1" '{systemMessage: $m}'
  exit 0
}

# Every page must still be on disk; otherwise fail open once.
MISSING=""
while IFS= read -r p; do
  [ -n "$p" ] && [ ! -r "$p" ] && MISSING="$p"
done < <(jq -r '.pages[]?.path' "$PENDING" 2>/dev/null)
if [ -n "$MISSING" ] || [ "$(jq -r '(.pages // []) | length' "$PENDING" 2>/dev/null)" = "0" ]; then
  fail_open "[preload gate] The preload page ${MISSING:-(none recorded)} is missing or unreadable, so the read gate is off for this session. Context from SessionStart may be incomplete."
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

# The escape command, as the deny message prints it: the path shell-quoted with
# printf %q, so a path with spaces or glob characters stays one word.
PENDING_Q=$(printf '%q' "$PENDING")

if [ "$TOOL" = "Bash" ]; then
  # The named escape hatch must be usable while everything else is blocked:
  # exactly `rm -f <this session's pending.json>`, with the path as printf %q
  # prints it (bare, for a path of plain characters), single-quoted when the path
  # has no single quote, or double-quoted when it has nothing double quotes
  # expand. A bare path that needs quoting is not accepted: the shell would
  # split it into other paths.
  # The "allow" skips the permission prompt only. A user's deny rule covering rm
  # still wins: measured on Claude Code 2.1.314 with a Bash(rm:*) deny rule and a
  # hook returning allow, the rm was refused.
  CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
  CMD="${CMD#"${CMD%%[![:space:]]*}"}"; CMD="${CMD%"${CMD##*[![:space:]]}"}"
  ESCAPE=""
  [ "$CMD" = "rm -f $PENDING_Q" ] && ESCAPE=1
  case "$PENDING" in *"'"*) ;; *) [ "$CMD" = "rm -f '$PENDING'" ] && ESCAPE=1 ;; esac
  case "$PENDING" in *[\"\$\`\\]*) ;; *) [ "$CMD" = "rm -f \"$PENDING\"" ] && ESCAPE=1 ;; esac
  if [ -n "$ESCAPE" ]; then
    jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: "Removing this session'"'"'s preload gate record."}}'
    exit 0
  fi
fi

if [ "$TOOL" = "Read" ]; then
  FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
  if [ -n "$FP" ] && jq -e --arg p "$FP" 'any(.pages[]?; .path == $p)' "$PENDING" >/dev/null 2>&1; then
    # A page Read resets the denial count, always, under the lock, so it cannot
    # be lost to a concurrent denial's write.
    if _take_lock "$LOCK"; then
      [ -f "$PENDING" ] && write_pending '.denials = 0 | del(.lastDeniedAt)'
      _drop_lock "$LOCK"
    fi
    jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: "Reading a page of this session'"'"'s SessionStart preload."}}'
    exit 0
  fi
fi

# A session that cannot read (Read removed with --tools or --disallowedTools)
# would be blocked for good. So denials are counted, and once DENY_MAX have been
# counted with no page Read between them, the next counted call fails open, once,
# with a warning. A denial counts only when it comes at least DENY_GAP seconds
# after the last counted one: the calls of one assistant message reach the hook
# within a second or so, so one message counts about once, and the model sees a
# deny before the gate can turn itself off. Both settings fall back to their
# defaults when not a whole number. The count is read, decided on and written
# under the lock, so concurrent calls neither lose a count nor undo a Read's
# reset.
num_or() { case "$1" in ''|*[!0-9]*) echo "$2" ;; *) echo "$1" ;; esac; }
DENY_MAX=$(num_or "${PRELOAD_GATE_MAX_DENIALS:-}" 5)
DENY_GAP=$(num_or "${PRELOAD_GATE_DENIAL_GAP:-}" 3)
NOW=$(date +%s)
COUNT=""
if _take_lock "$LOCK"; then
  if [ ! -f "$PENDING" ]; then _drop_lock "$LOCK"; exit 0; fi
  COUNT=$(num_or "$(jq -r '.denials // 0' "$PENDING" 2>/dev/null)" 0)
  LAST=$(num_or "$(jq -r '.lastDeniedAt // 0' "$PENDING" 2>/dev/null)" 0)
  if [ $((NOW - LAST)) -ge "$DENY_GAP" ]; then
    if [ "$COUNT" -ge "$DENY_MAX" ]; then
      rm -f "$PENDING" 2>/dev/null || true
      _drop_lock "$LOCK"
      jq -n --arg m "[preload gate] $DENY_MAX tool calls in a row were blocked without a Read of the preload pages, so the read gate is off for this session. Context from SessionStart may not have been read." \
        '{systemMessage: $m}'
      exit 0
    fi
    COUNT=$((COUNT + 1))
    write_pending '.denials = $n | .lastDeniedAt = $t' --argjson n "$COUNT" --argjson t "$NOW"
  fi
  _drop_lock "$LOCK"
else
  # The lock could not be had within 5 s: deny without counting.
  COUNT=$(num_or "$(jq -r '.denials // 0' "$PENDING" 2>/dev/null)" 0)
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
Every other tool except AskUserQuestion is blocked until then (denial $COUNT of $DENY_MAX in a row, counting at most one every $DENY_GAP s; after that the gate turns itself off). To turn the gate off now: run exactly \`rm -f $PENDING_Q\` (allowed through the gate), or set PRELOAD_READ_GATE=off." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
