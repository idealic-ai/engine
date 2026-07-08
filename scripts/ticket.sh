#!/bin/bash
# ticket.sh — engine ticket subscribe/notify subsystem
#
# A lightweight dirty-flag + watermark tracker over session .state.json files.
# Sessions subscribe to Linear tickets; when an agent posts a comment it notifies
# the OTHER subscribers, whose status line then surfaces the dirty ticket. `read`
# drains the queue and hands back {ticket, since} so the agent fetches the actual
# comments from Linear via MCP — the engine never stores comment content.
#
# Usage:
#   engine ticket subscribe   <KEY> [session]
#   engine ticket unsubscribe <KEY> [session]
#   engine ticket notify      <KEY> [note] [--from <session>]
#   engine ticket read        [KEY] [--since <dt>] [--json] [session]
#   engine ticket list        [KEY] [--since <dt>] [--json] [session]
#
# Data model (per session .state.json):
#   tickets:        [ {key, subscribedAt, lastReadAt} ]        # subscriptions
#   updatedTickets: [ {ticket, notifiedAt, from, note} ]       # dirty queue
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib.sh"

usage() {
  sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
}

_now() { timestamp; }

# Uppercase + strip whitespace; warn (don't fail) if not a standard Linear key.
normalize_key() {
  local raw="$1" key
  key=$(printf '%s' "$raw" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')
  if ! printf '%s' "$key" | grep -qE '^[A-Z]+-[0-9]+$'; then
    echo "ticket: warning: '$raw' is not a standard Linear key (expected e.g. FIN-123)" >&2
  fi
  printf '%s' "$key"
}

_looks_like_session() {
  case "$1" in */*) return 0 ;; esac
  [ -d "$1" ]
}

# Resolve target session dir: explicit arg wins; else auto-detect via session.sh find.
_resolve_session() {
  local arg="${1:-}" dir
  if [ -n "$arg" ]; then
    resolve_session_path "$arg"
    return 0
  fi
  dir=$("$SCRIPT_DIR/session.sh" find 2>/dev/null) || dir=""
  if [ -z "$dir" ]; then
    echo "ticket: no active session found — pass a session path" >&2
    return 1
  fi
  printf '%s' "$dir"
}

_require_state() {
  local dir="$1"
  if [ ! -f "$dir/.state.json" ]; then
    echo "ticket: no .state.json at $dir" >&2
    return 1
  fi
}

# ---- Verbs ----

cmd_subscribe() {
  local key dir state now
  [ -n "${1:-}" ] || { echo "ticket: subscribe requires a KEY" >&2; return 1; }
  key=$(normalize_key "$1")
  dir=$(_resolve_session "${2:-}") || return 1
  _require_state "$dir" || return 1
  state="$dir/.state.json"
  now=$(_now)
  safe_json_update "$state" --arg k "$key" --arg ts "$now" '
    (.tickets // []) as $cur
    | .tickets = ( if ($cur | any(.key == $k))
                   then $cur
                   else $cur + [{key: $k, subscribedAt: $ts, lastReadAt: $ts}] end )
  ' || return 1
  echo "ticket: subscribed $(basename "$dir") → $key"
}

cmd_unsubscribe() {
  local key dir state
  [ -n "${1:-}" ] || { echo "ticket: unsubscribe requires a KEY" >&2; return 1; }
  key=$(normalize_key "$1")
  dir=$(_resolve_session "${2:-}") || return 1
  _require_state "$dir" || return 1
  state="$dir/.state.json"
  safe_json_update "$state" --arg k "$key" '
    .tickets        = [ (.tickets // [])[]        | select(.key    != $k) ]
    | .updatedTickets = [ (.updatedTickets // [])[] | select(.ticket != $k) ]
  ' || return 1
  echo "ticket: unsubscribed $(basename "$dir") → $key"
}

cmd_notify() {
  local key note="" from="" sessions_dir notifier_dir="" from_label now count=0
  [ -n "${1:-}" ] || { echo "ticket: notify requires a KEY" >&2; return 1; }
  key=$(normalize_key "$1"); shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) from="${2:-}"; shift 2 ;;
      --from=*) from="${1#*=}"; shift ;;
      *) note="$1"; shift ;;
    esac
  done

  sessions_dir=$(resolve_sessions_dir)
  now=$(_now)
  if [ -n "$from" ]; then
    notifier_dir=$(resolve_session_path "$from")
  else
    notifier_dir=$("$SCRIPT_DIR/session.sh" find 2>/dev/null || echo "")
  fi
  from_label="external"
  [ -n "$notifier_dir" ] && from_label=$(basename "$notifier_dir")

  local state sdir
  for state in "$sessions_dir"/*/.state.json; do
    [ -f "$state" ] || continue
    sdir=$(dirname "$state")
    if [ -n "$notifier_dir" ] && [ "$sdir" -ef "$notifier_dir" ] 2>/dev/null; then continue; fi
    if jq -e --arg k "$key" '(.tickets // []) | any(.key == $k)' "$state" >/dev/null 2>&1; then
      safe_json_update "$state" --arg t "$key" --arg ts "$now" --arg f "$from_label" --arg n "$note" '
        .updatedTickets = ((.updatedTickets // []) + [{ticket: $t, notifiedAt: $ts, from: $f, note: $n}])
      ' && count=$((count + 1))
    fi
  done

  if [ "$count" -eq 0 ]; then
    echo "ticket: notify $key — no subscribers"
  else
    echo "ticket: notify $key → $count subscriber(s)"
  fi
}

# Emit the matched-update view as a JSON array (grouped by ticket, with since watermark).
_build_view() {
  local state="$1" key="$2" since="$3"
  jq --arg k "$key" --arg since "$since" '
    (.tickets // []) as $subs
    | [ (.updatedTickets // [])[]
        | select( ($k == "" or .ticket == $k) and ($since == "" or .notifiedAt >= $since) ) ]
    | group_by(.ticket)
    | map( .[0].ticket as $tk | {
        ticket: $tk,
        since: ( ([ $subs[] | select(.key == $tk) | (.lastReadAt // .subscribedAt) ] | first) // "" ),
        notifiedAt: ( max_by(.notifiedAt).notifiedAt ),
        count: length,
        notes: [ .[] | {notifiedAt, from, note} ]
      })
  ' "$state"
}

_render_human() {
  # stdin: JSON array from _build_view
  jq -r '
    if length == 0 then "No ticket updates."
    else .[] | "🎟 \(.ticket)  since=\(.since)  (\(.count) update\(if .count == 1 then "" else "s" end))"
      + ( [ .notes[] | "\n    • \(.notifiedAt) [\(.from)] \(.note)" ] | add // "" )
    end
  '
}

_parse_view_args() {
  # sets globals: V_KEY V_SINCE V_JSON V_SESSION
  V_KEY=""; V_SINCE=""; V_JSON=0; V_SESSION=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) V_JSON=1; shift ;;
      --since) V_SINCE="${2:-}"; shift 2 ;;
      --since=*) V_SINCE="${1#*=}"; shift ;;
      *)
        if _looks_like_session "$1"; then V_SESSION="$1"; else V_KEY=$(normalize_key "$1"); fi
        shift ;;
    esac
  done
}

cmd_list() {
  local dir state view
  _parse_view_args "$@"
  dir=$(_resolve_session "$V_SESSION") || return 1
  _require_state "$dir" || return 1
  state="$dir/.state.json"
  view=$(_build_view "$state" "$V_KEY" "$V_SINCE")
  if [ "$V_JSON" -eq 1 ]; then printf '%s\n' "$view"; else printf '%s\n' "$view" | _render_human; fi
}

cmd_read() {
  local dir state view now
  _parse_view_args "$@"
  dir=$(_resolve_session "$V_SESSION") || return 1
  _require_state "$dir" || return 1
  state="$dir/.state.json"
  now=$(_now)

  view=$(_build_view "$state" "$V_KEY" "$V_SINCE")

  # Drain the shown entries and advance lastReadAt for each drained ticket.
  safe_json_update "$state" --arg k "$V_KEY" --arg since "$V_SINCE" --arg now "$now" '
    (.updatedTickets // []) as $all
    | ( [ $all[] | select( ($k == "" or .ticket == $k) and ($since == "" or .notifiedAt >= $since) ) | .ticket ] | unique ) as $drained
    | .updatedTickets = [ $all[] | select( ($k != "" and .ticket != $k) or ($since != "" and .notifiedAt < $since) ) ]
    | .tickets = [ (.tickets // [])[] | (.key) as $kk | if ($drained | index($kk)) then .lastReadAt = $now else . end ]
  ' || return 1

  if [ "$V_JSON" -eq 1 ]; then printf '%s\n' "$view"; else printf '%s\n' "$view" | _render_human; fi
}

# Clear .state.json:watchTaskId, but only when it still records OUR pid — a re-armed
# newer watcher (which overwrote the field) must survive our EXIT. Best-effort.
_watch_unregister() {
  local state="$1" mypid="$2" stored
  [ -f "$state" ] || return 0
  stored=$(jq -r '.watchTaskId.pid // empty' "$state" 2>/dev/null || echo "")
  [ "$stored" = "$mypid" ] || return 0
  safe_json_update "$state" 'del(.watchTaskId)' 2>/dev/null || true
}

# Block (via fswatch) until a watched ticket has a pending update, then exit 0
# printing the matched key(s). KEY narrows to one ticket; omitted watches all
# subscribed. Non-destructive — the caller runs `read` afterward to drain + get
# `since`. Designed for Bash(run_in_background): the harness re-invokes the agent
# on exit. Exit: 0 update, 124 timeout, 2 fswatch missing, 1 nothing to watch.
cmd_watch() {
  if ! command -v fswatch >/dev/null 2>&1; then
    echo "ticket: fswatch is required for 'watch' but not installed. Install: brew install fswatch" >&2
    return 2
  fi
  local key="" timeout=0 session=""   # timeout=0 → unbounded (block until a real update)
  while [ $# -gt 0 ]; do
    case "$1" in
      --timeout) timeout="${2:-0}"; shift 2 ;;
      --timeout=*) timeout="${1#*=}"; shift ;;
      *)
        if _looks_like_session "$1"; then session="$1"; else key=$(normalize_key "$1"); fi
        shift ;;
    esac
  done
  local dir state
  dir=$(_resolve_session "$session") || return 1
  _require_state "$dir" || return 1
  state="$dir/.state.json"

  # jq printing the matched pending ticket keys (space-separated) for the watched set.
  # Watermark-authoritative: an entry fires the watch only if notifiedAt > that ticket's
  # lastReadAt — so an already-read entry that lingers (a keyed/`--since` partial drain,
  # or a re-arm without a full `read`) can never re-wake the agent on an old notify.
  local match_filter='
    (.tickets // []) as $subs
    | (if $k != "" then [$k] else [ $subs[].key ] end) as $w
    | ( [ $subs[] | {key: .key, value: (.lastReadAt // .subscribedAt // "")} ] | from_entries ) as $wm
    | [ (.updatedTickets // [])[]
        | select( (.ticket as $t | $w | index($t)) and (.notifiedAt > ($wm[.ticket] // "")) )
        | .ticket ] | unique | join(" ")'

  local watched_count
  watched_count=$(jq -r --arg k "$key" '(.tickets // []) as $s | (if $k != "" then [$k] else [ $s[].key ] end) | length' "$state" 2>/dev/null || echo 0)
  if [ "${watched_count:-0}" -eq 0 ]; then
    echo "ticket: nothing to watch — no subscribed tickets${key:+ (and not subscribed to $key)}" >&2
    return 1
  fi

  local matched
  matched=$(jq -r --arg k "$key" "$match_filter" "$state" 2>/dev/null)   # race guard
  if [ -n "$matched" ]; then echo "$matched"; return 0; fi

  # Self-register as the live watcher so the auto-watch gate can confirm this session
  # is armed (liveness = kill -0 on this pid; the trap below is the graceful fast-path).
  # Capture any previous watcher BEFORE we overwrite the field, so we can supersede it.
  local prev_pid
  prev_pid=$(jq -r '.watchTaskId.pid // empty' "$state" 2>/dev/null || echo "")
  local watched_keys
  watched_keys=$(jq -r --arg k "$key" '(.tickets // []) as $s | (if $k != "" then [$k] else [ $s[].key ] end) | join(",")' "$state" 2>/dev/null || echo "")
  safe_json_update "$state" --argjson pid "$$" --arg started "$(_now)" --arg keys "$watched_keys" '
    .watchTaskId = {pid: $pid, startedAt: $started, keys: $keys}
  ' || true
  # Clear watchTaskId on exit only if it still holds OUR pid (never clobber a newer watcher).
  # Bake a shell-quoted $state + $$ now: at EXIT-trap fire time cmd_watch's locals are out of
  # scope. INT/TERM route through `exit` so a signalled teardown still runs the cleanup.
  trap "_watch_unregister $(printf '%q' "$state") $$" EXIT
  trap 'exit' INT TERM

  # Supersede the previous live watcher — only ONE watcher per session, so re-arming
  # (on wake / after a nudge) can't stack multiple blocked `fswatch` shells. Register
  # first (above) so watchTaskId already points at us; the old watcher's pid-guarded
  # EXIT cleanup then sees our pid and leaves our registration intact.
  if [ -n "$prev_pid" ] && [ "$prev_pid" != "$$" ] && kill -0 "$prev_pid" 2>/dev/null; then
    kill "$prev_pid" 2>/dev/null || true
  fi

  # A non-matching fs event re-checks and re-blocks WITHOUT exiting, so the agent is
  # only re-invoked (a background-task exit) on a real match — never on churn.
  if [ "${timeout:-0}" -gt 0 ]; then
    # Bounded (opt-in --timeout): exit 124 if no matching update lands before the deadline.
    local deadline now remaining
    deadline=$(( $(date +%s) + timeout ))
    while :; do
      now=$(date +%s); remaining=$(( deadline - now ))
      [ "$remaining" -le 0 ] && break
      # Watch the session dir (not the file) so the atomic mv-write from safe_json_update is caught.
      if timeout "$remaining" fswatch -1 "$dir" >/dev/null 2>&1; then
        matched=$(jq -r --arg k "$key" "$match_filter" "$state" 2>/dev/null)
        if [ -n "$matched" ]; then echo "$matched"; return 0; fi
      else
        break  # fswatch hit the deadline
      fi
    done
    echo "ticket: watch timed out after ${timeout}s — no update" >&2
    return 124
  fi

  # Unbounded (default): block until a real matching update. A modest internal
  # re-check tick re-evaluates the condition even with zero fs events, so an entry
  # landing in the check-then-block window (between the race-guard and fswatch
  # starting) is caught deterministically — not left to incidental .state.json
  # writes. The tick NEVER exits the process (only a real match does), so there are
  # still no fake-wakes and watchTaskId stays live for the gate.
  local recheck="${WATCH_RECHECK_SECS:-30}" rc
  while :; do
    timeout "$recheck" fswatch -1 "$dir" >/dev/null 2>&1
    rc=$?
    if [ "$rc" -eq 0 ] || [ "$rc" -eq 124 ]; then
      # 0 = fs event, 124 = internal re-check tick — either way, re-evaluate.
      matched=$(jq -r --arg k "$key" "$match_filter" "$state" 2>/dev/null)
      if [ -n "$matched" ]; then echo "$matched"; return 0; fi
    else
      # Not a tick and not an event — a genuine fswatch backend failure. Surface it
      # (exit 2) rather than hot-spinning the loop.
      echo "ticket: watch backend (fswatch) exited unexpectedly" >&2
      return 2
    fi
  done
}

# ---- Dispatch ----
case "${1:-}" in
  subscribe)   shift; cmd_subscribe "$@" ;;
  unsubscribe) shift; cmd_unsubscribe "$@" ;;
  notify)      shift; cmd_notify "$@" ;;
  read)        shift; cmd_read "$@" ;;
  list)        shift; cmd_list "$@" ;;
  watch)       shift; cmd_watch "$@" ;;
  ""|-h|--help|help) usage ;;
  *) echo "ticket: unknown subcommand '$1'" >&2; usage; exit 1 ;;
esac
