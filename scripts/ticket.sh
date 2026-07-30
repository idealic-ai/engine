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
#   engine ticket watch       [KEY] [--timeout <s>] [session]   # block until an update; run via run_in_background:true
#   engine ticket resolve-comment <commentId> [--reopen] [--json]  # resolve (or --reopen: unresolve) a Linear comment thread
#
# `watch` blocks (via fswatch) until a subscribed ticket has a pending update, then
# exits: 0 = update waiting (run `read` to drain, THEN re-arm — else it re-fires
# instantly on the same undrained entry), 124 = --timeout deadline, 2 = fswatch
# missing, 1 = nothing subscribed.
#
# Data model (per session .state.json):
#   tickets:        [ {key, subscribedAt} ]                    # subscriptions
#   updatedTickets: [ {ticket, notifiedAt, from, note} ]       # dirty queue
#   ticketCursor:   "<ISO8601>"                                # ONE shared read watermark W over
#                                                              # the whole watched set (the session
#                                                              # drains all its tickets together)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib.sh"
# The Linear GraphQL seam + shared per-issue transform (shared with project.sh) — powers
# `ticket fetch`, the Linear pull. subscribe/notify/read/watch don't need it, but sourcing
# once at the top keeps the dependency explicit.
# shellcheck source=/dev/null
source "$SCRIPT_DIR/linear-lib.sh"

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
                   else $cur + [{key: $k, subscribedAt: $ts}] end )
    | .ticketCursor = (.ticketCursor // $ts)
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
    (.ticketCursor // "") as $W
    | [ (.updatedTickets // [])[]
        | select( ($k == "" or .ticket == $k) and ($since == "" or .notifiedAt >= $since) ) ]
    | group_by(.ticket)
    | map( .[0].ticket as $tk | {
        ticket: $tk,
        since: $W,
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

  # Drain the WHOLE set and advance the single shared cursor W (KEY/since were display filters
  # only — a partial drain would desync the one cursor). Entries newer than `now` (arrived
  # mid-read) are preserved so a concurrent notify is never lost.
  safe_json_update "$state" --arg now "$now" '
    .ticketCursor = $now
    | .updatedTickets = [ (.updatedTickets // [])[] | select(.notifiedAt > $now) ]
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

# On wake, AUTO-DRAIN: fetch the matched tickets from Linear since the shared cursor W into a
# payload FILE, then advance W and clear the acked queue, and emit the matched key(s) + the
# payload PATH to stdout — so the background-task wake notification carries the update directly
# (§CMD_DRAIN_TICKET_QUEUE_ON_WAKE reads the file), with no separate fetch step. The payload rides
# a FILE, never stdout, because the harness truncates large tool stdout but not a file the agent
# then reads. Fetch BEFORE advancing W (¶INV_WRITE_BEFORE_WATERMARK): a failed fetch leaves W +
# the dirty queue untouched, so the next re-arm re-drains the same window rather than leaping
# past unseen comments.
_watch_drain_emit() {
  local state="$1" matched="$2" now W dir payload_out drain_json
  W=$(jq -r '.ticketCursor // ""' "$state" 2>/dev/null || echo "")
  dir=$(dirname "$state")
  payload_out="$dir/.ticket-drain/drain-$(date +%s)-$$.json"
  mkdir -p "$dir/.ticket-drain" 2>/dev/null || true

  # Split $matched (space-separated keys) into cmd_fetch args; omit --since when W is empty (a
  # full read — e.g. before the first cold-read seeds the cursor).
  local -a fargs; fargs=($matched)
  [ -n "$W" ] && fargs+=(--since "$W")
  fargs+=(--out "$payload_out")
  if ! cmd_fetch "${fargs[@]}" >/dev/null 2>&1; then
    # Fail-closed: cursor NOT advanced, queue NOT cleared — the agent re-arms and retries.
    printf 'ticket update — %s\nFETCH FAILED (since=%s) — cursor NOT advanced; re-arm to retry\n' "$matched" "$W"
    return 0
  fi

  now=$(_now)
  safe_json_update "$state" --arg now "$now" '
    .ticketCursor = $now
    | .updatedTickets = [ (.updatedTickets // [])[] | select(.notifiedAt > $now) ]
  ' || true
  drain_json=$(jq -n -c --arg keys "$matched" --arg since "$W" --arg path "$payload_out" '
    { keys: ($keys | split(" ")), since: $since, payload: $path }')
  printf 'ticket update — %s\n%s\n' "$matched" "$drain_json"
}

# Block (via fswatch) until a watched ticket has a pending update, then AUTO-DRAIN and
# exit 0 emitting the matched key(s) + per-ticket `since` to stdout (via _watch_drain_emit)
# — the wake notification carries the update directly (§CMD_DRAIN_TICKET_QUEUE_ON_WAKE), no separate
# `read`. KEY narrows to one ticket; omitted watches all subscribed. Designed for
# Bash(run_in_background): the harness re-invokes the agent on exit. Exit: 0 update,
# 124 timeout, 2 fswatch missing, 1 nothing to watch.
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
  # Watermark-authoritative against the SINGLE shared cursor W: an entry fires the watch only if
  # notifiedAt > W — so an already-drained entry that lingers (a re-arm without a fresh notify)
  # can never re-wake the agent on an old notify.
  local match_filter='
    (.ticketCursor // "") as $W
    | (.tickets // []) as $subs
    | (if $k != "" then [$k] else [ $subs[].key ] end) as $w
    | [ (.updatedTickets // [])[]
        | select( (.ticket as $t | $w | index($t)) and (.notifiedAt > $W) )
        | .ticket ] | unique | join(" ")'

  local watched_count
  watched_count=$(jq -r --arg k "$key" '(.tickets // []) as $s | (if $k != "" then [$k] else [ $s[].key ] end) | length' "$state" 2>/dev/null || echo 0)
  if [ "${watched_count:-0}" -eq 0 ]; then
    echo "ticket: nothing to watch — no subscribed tickets${key:+ (and not subscribed to $key)}" >&2
    return 1
  fi

  local matched
  matched=$(jq -r --arg k "$key" "$match_filter" "$state" 2>/dev/null)   # race guard
  if [ -n "$matched" ]; then _watch_drain_emit "$state" "$matched"; return 0; fi

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
        if [ -n "$matched" ]; then _watch_drain_emit "$state" "$matched"; return 0; fi
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
      if [ -n "$matched" ]; then _watch_drain_emit "$state" "$matched"; return 0; fi
    else
      # Not a tick and not an event — a genuine fswatch backend failure. Surface it
      # (exit 2) rather than hot-spinning the loop.
      echo "ticket: watch backend (fswatch) exited unexpectedly" >&2
      return 2
    fi
  done
}

# ---- ticket fetch (Linear pull — the per-ticket analog of `project fetch`) ----
#
# `engine ticket fetch K1 K2 … [--since <ISO>] [--out <path>]` pulls a delta of the given
# tickets from Linear as ONE JSON payload (comment trees w/ reactions + normalized lifecycle
# + attachments), reusing project.sh's transform via linear-lib.sh. STATELESS: --since is the
# caller's (the shared session cursor W lives in the watch path, not here). No --since = the
# full ticket (cold-read / context load). Payload → file; the path is the last stdout line
# (never the payload itself — shell stdout truncates; the file does not).

# Root issues query filtered to an id-set of tickets (vs project.sh's project-scoped _q_issues).
_q_tickets() {
  cat <<'GQL'
query($filter: IssueFilter, $after: String) {
  issues(first: 25, after: $after, orderBy: createdAt, filter: $filter) {
    pageInfo { hasNextPage endCursor }
    nodes {
      id identifier title url createdAt updatedAt priority
      state { name }
      projectMilestone { name }
      comments(first: 40) {
        pageInfo { hasNextPage endCursor }
        nodes { id body createdAt quotedText parent { id } user { name } botActor { name } reactions { emoji createdAt user { name } externalUser { name } } }
      }
      history(first: 20) {
        pageInfo { hasNextPage endCursor }
        nodes {
          createdAt actor { name }
          fromState { name } toState { name }
          fromPriority toPriority
          fromAssignee { name } toAssignee { name }
          fromProjectMilestone { name } toProjectMilestone { name }
        }
      }
      attachments(first: 20) {
        pageInfo { hasNextPage endCursor }
        nodes { id title url }
      }
    }
  }
}
GQL
}

# _ticket_fetch_all FILTER_JSON → array of raw issue nodes (paginated + children drained).
_ticket_fetch_all() {
  local filter="$1" after="null" resp page prev_cursor=""
  local issues_file; issues_file=$(mktemp -t ticketfetch-issues.XXXXXX)
  trap 'rm -f "$issues_file"' RETURN
  while :; do
    resp=$(_graphql "$(_q_tickets)" "$(jq -n --argjson f "$filter" --argjson a "$after" '{filter: $f, after: $a}')") || return 1
    page=$(printf '%s' "$resp" | jq '.data.issues // null')
    if [ "$page" = "null" ]; then echo "ticket: fetch — unexpected response shape from Linear" >&2; return 1; fi
    printf '%s' "$page" | jq -c '[.nodes[]?]' >> "$issues_file"
    local has end
    has=$(printf '%s' "$page" | jq -r '.pageInfo.hasNextPage')
    [ "$has" = "true" ] || break
    end=$(printf '%s' "$page" | jq -r '.pageInfo.endCursor')
    if [ -z "$end" ] || [ "$end" = "null" ] || [ "$end" = "$prev_cursor" ]; then
      echo "ticket: fetch pagination cursor did not advance — aborting to avoid an infinite loop" >&2; return 1
    fi
    prev_cursor="$end"
    after=$(jq -n --arg c "$end" '$c')
  done
  local all; all=$(jq -s 'add // []' "$issues_file")
  _paginate_issue_children "$all" || return 1
}

# _ticket_assemble ISSUES SINCE FETCHED_AT KEYS_JSON → the thin ticket-fetch envelope.
_ticket_assemble() {
  local issues="$1" since="$2" fetched_at="$3" keys="$4"
  printf '%s' "$issues" | jq \
    --arg since "$since" --arg fetchedAt "$fetched_at" --argjson keys "$keys" "$LINEAR_JQ_DEFS"'
    ($since | normTs) as $sn
    | { since: $since,
        fetchedAt: $fetchedAt,
        keys: $keys,
        tickets: [ .[] | issueToTicket($sn) ],
        summary: {
          ticketCount: length,
          requested: ($keys | length)
        } }
  '
}

cmd_fetch() {
  local since="" out="" ; local -a keys=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --since) since="${2:-}"; shift 2 ;;
      --since=*) since="${1#*=}"; shift ;;
      --out) out="${2:-}"; shift 2 ;;
      --out=*) out="${1#*=}"; shift ;;
      -*) echo "ticket: fetch: unknown flag '$1'" >&2; return 1 ;;
      *) keys+=("$(normalize_key "$1")"); shift ;;
    esac
  done
  [ "${#keys[@]}" -gt 0 ] || { echo "ticket: fetch requires at least one KEY (e.g. FIN-3473)" >&2; return 1; }
  local k
  for k in "${keys[@]}"; do
    printf '%s' "$k" | grep -qE '^[A-Z]+-[0-9]+$' || { echo "ticket: fetch: '$k' is not a valid Linear key (expected TEAM-NUM)" >&2; return 1; }
  done

  # Keys are Linear identifiers (FIN-3473), not UUIDs. IssueFilter honors {team, or:[{number}…]}
  # but SILENTLY IGNORES a compound {team, number} nested inside an `or` (verified live) — so a
  # naive per-key OR returns the whole workspace. Group by team → one filter+fetch per team
  # ({team.key} AND (n1 OR n2 …) AND updatedAt). The common single-team case is one query.
  local keys_json teams_json
  keys_json=$(printf '%s\n' "${keys[@]}" | jq -R . | jq -s .)
  teams_json=$(jq -n -c --argjson keys "$keys_json" '
    $keys | map(capture("^(?<t>[A-Z]+)-(?<n>[0-9]+)$"))
    | group_by(.t) | map({ team: .[0].t, numbers: [.[].n | tonumber] })')

  local issues="[]" fetched_at payload
  local tcount i filter part
  tcount=$(printf '%s' "$teams_json" | jq 'length')
  for i in $(seq 0 $(( tcount - 1 )) ); do
    filter=$(printf '%s' "$teams_json" | jq -c --argjson i "$i" --arg since "$since" '
      .[$i] as $g
      | ({ team: { key: { eq: $g.team } }, or: [ $g.numbers[] | { number: { eq: . } } ] })
        + (if $since == "" then {} else { updatedAt: { gt: $since } } end)')
    part=$(_ticket_fetch_all "$filter") || return 1
    issues=$(jq -n --argjson a "$issues" --argjson b "$part" '$a + $b')
  done
  fetched_at="$(timestamp)"
  payload=$(_ticket_assemble "$issues" "$since" "$fetched_at" "$keys_json") || { echo "ticket: fetch transform failed" >&2; return 1; }

  # Payload write is the terminal durable step (¶INV_WRITE_BEFORE_WATERMARK) — any failure above
  # already returned non-zero with nothing written; the caller advances its cursor only after this.
  if [ -z "$out" ]; then
    local pdir="${TICKET_FETCH_STATE_DIR:-$HOME/.claude/engine/.ticket-fetch}/payloads"
    mkdir -p "$pdir"
    out="$pdir/tickets-$(date +%s)-$$.json"
  else
    mkdir -p "$(dirname "$out")" 2>/dev/null || true
  fi
  if ! printf '%s' "$payload" | safe_json_write "$out"; then
    echo "ticket: failed to write payload to $out" >&2; return 1
  fi
  printf '%s\n' "$out"
}

# ---- resolve-comment (Linear comment-thread resolution via GraphQL) ----
#
# `engine ticket resolve-comment <commentId> [--reopen] [--json]` resolves (or, with --reopen,
# unresolves) a Linear issue-comment thread — the affordance the MCP does not expose (it has only
# resolve_diff_thread, for diff reviews). Reuses linear-lib.sh's _graphql seam (fixture-backed via
# LINEAR_FIXTURE in tests). Idempotent: commentResolve on an already-resolved comment still returns
# success with resolvedAt set. Default prints a human line; --json emits {id, resolvedAt}.
cmd_resolve_comment() {
  local cid="" reopen=0 json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --reopen) reopen=1; shift ;;
      --json)   json=1; shift ;;
      -*) echo "ticket: resolve-comment: unknown flag '$1'" >&2; return 1 ;;
      *) if [ -z "$cid" ]; then cid="$1"; else echo "ticket: resolve-comment: unexpected extra arg '$1'" >&2; return 1; fi; shift ;;
    esac
  done
  [ -n "$cid" ] || { echo "ticket: resolve-comment requires a <commentId>" >&2; return 1; }

  local field mut
  if [ "$reopen" -eq 1 ]; then
    field="commentUnresolve"
    mut='mutation($id: String!) { commentUnresolve(id: $id) { success comment { id resolvedAt } } }'
  else
    field="commentResolve"
    mut='mutation($id: String!) { commentResolve(id: $id) { success comment { id resolvedAt } } }'
  fi

  local vars resp
  vars=$(jq -n --arg id "$cid" '{id: $id}')
  resp=$(_graphql "$mut" "$vars") || return 1   # _graphql fails closed on network / GraphQL errors[] / bad JSON

  local ok
  ok=$(printf '%s' "$resp" | jq -r --arg f "$field" '.data[$f].success // false')
  if [ "$ok" != "true" ]; then
    echo "ticket: resolve-comment: Linear reported success=false for $cid" >&2
    return 1
  fi

  local rid resolved_at
  rid=$(printf '%s' "$resp" | jq -r --arg f "$field" --arg c "$cid" '.data[$f].comment.id // $c')
  resolved_at=$(printf '%s' "$resp" | jq -r --arg f "$field" '.data[$f].comment.resolvedAt // null')

  if [ "$json" -eq 1 ]; then
    if [ "$resolved_at" = "null" ]; then
      jq -n --arg id "$rid" '{id: $id, resolvedAt: null}'
    else
      jq -n --arg id "$rid" --arg ra "$resolved_at" '{id: $id, resolvedAt: $ra}'
    fi
  elif [ "$reopen" -eq 1 ]; then
    echo "🎟 reopened $rid"
  else
    echo "🎟 resolved $rid at $resolved_at"
  fi
}

# ---- Dispatch ----
case "${1:-}" in
  subscribe)   shift; cmd_subscribe "$@" ;;
  fetch)       shift; cmd_fetch "$@" ;;
  unsubscribe) shift; cmd_unsubscribe "$@" ;;
  notify)      shift; cmd_notify "$@" ;;
  read)        shift; cmd_read "$@" ;;
  list)        shift; cmd_list "$@" ;;
  watch)       shift; cmd_watch "$@" ;;
  resolve-comment) shift; cmd_resolve_comment "$@" ;;
  ""|-h|--help|help) usage ;;
  *) echo "ticket: unknown subcommand '$1'" >&2; usage; exit 1 ;;
esac
