#!/bin/bash
# project.sh — engine project fetch: one Linear-project delta as a single JSON payload
#
# `engine project fetch <project> [--since=<ISO>] [--out=<path>]` queries Linear's
# GraphQL API and writes ONE payload of everything new in a Project since a durable
# per-project waterline: inbox-channel comment TREES, new comments on ordinary tickets,
# new tickets, attachment URLs, normalized lifecycle events (who/when/from→to), a live
# structure catalog, and a summary layer. Read-only toward Linear.
#
# The waterline advances ONLY after the payload is durably written (¶INV_WRITE_BEFORE_WATERMARK):
# any failure leaves it un-advanced + exits non-zero, so an interrupted run re-fetches cleanly.
#
# Usage:
#   engine project fetch <project> [--since=<ISO8601>] [--out=<path>]
#   engine project waterline get   <project>
#   engine project waterline list
#   engine project waterline reset <project>
#
#   <project> : Linear project UUID (used directly) or name (resolved via a projects query).
#   --since   : override the stored waterline for this run (stored waterline still advances after).
#   --out     : payload destination (default $STATE_DIR/payloads/<projectId>-<epoch>.json).
#               The written path is always printed as the last stdout line.
#
# Auth (live path only): LINEAR_API_KEY from env or .env (repo root or ~/.claude/engine/.env).
# Env: PROJECT_FETCH_STATE_DIR (default ~/.claude/engine/.project-fetch) — waterline + default payloads.
#      PROJECT_FETCH_FIXTURE (test-only) — file or colon-separated file list; short-circuits _graphql.
#      LINEAR_API_URL (default https://api.linear.app/graphql).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib.sh"

LINEAR_API_URL="${LINEAR_API_URL:-https://api.linear.app/graphql}"

# Fixture mode (tests): a per-invocation file-backed call counter shared across subshells.
# Command-substitution subshells reset EXIT traps, so this trap fires only when the top-level
# shell exits — cleaning up the temp counter without a subshell deleting it mid-run.
if [ -n "${PROJECT_FETCH_FIXTURE:-}" ]; then
  _FIX_COUNTER="${_FIX_COUNTER:-$(mktemp -t projfetch.XXXXXX)}"
  export _FIX_COUNTER
  [ -s "$_FIX_COUNTER" ] || echo 0 > "$_FIX_COUNTER"
  trap 'rm -f "$_FIX_COUNTER" 2>/dev/null' EXIT
fi

usage() {
  # Print the header's "# Usage:" block through to the first non-comment line.
  awk '/^# Usage:/{p=1} p{ if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
}

# ---- State dir + waterline store ----

_state_dir() {
  local d="${PROJECT_FETCH_STATE_DIR:-$HOME/.claude/engine/.project-fetch}"
  mkdir -p "$d" 2>/dev/null || true
  printf '%s' "$d"
}

_waterlines_file() {
  local f
  f="$(_state_dir)/waterlines.json"
  [ -f "$f" ] || echo '{}' > "$f"
  printf '%s' "$f"
}

# _waterline_get PROJECT_ID → stored ISO waterline (empty if none)
_waterline_get() {
  local pid="$1" f
  f="$(_waterlines_file)"
  jq -r --arg p "$pid" '(.[$p].waterline // "")' "$f" 2>/dev/null || echo ""
}

# _waterline_set PROJECT_ID ISO — atomic under lib.sh lock
_waterline_set() {
  local pid="$1" wm="$2" f
  f="$(_waterlines_file)"
  safe_json_update "$f" --arg p "$pid" --arg w "$wm" --arg ts "$(timestamp)" \
    '.[$p] = {waterline: $w, updatedAt: $ts}'
}

# ---- GraphQL seam (the single injectable HTTP call) ----

# _load_key — source LINEAR_API_KEY from .env if unset (live path only), mirroring gemini.sh.
_load_key() {
  if [ -z "${LINEAR_API_KEY:-}" ]; then
    local envfile
    for envfile in ".env" "$HOME/.claude/engine/.env"; do
      if [ -f "$envfile" ] && grep -q '^LINEAR_API_KEY=' "$envfile" 2>/dev/null; then
        LINEAR_API_KEY=$(grep '^LINEAR_API_KEY=' "$envfile" | head -1 | cut -d= -f2-)
        export LINEAR_API_KEY
        break
      fi
    done
  fi
  : "${LINEAR_API_KEY:?LINEAR_API_KEY is required — set it in your environment or .env file}"
}

# _next_fixture — pop the next fixture path from the colon-separated PROJECT_FETCH_FIXTURE list.
# The call counter is FILE-backed (not a shell var) so it survives the command-substitution
# subshells that wrap _resolve_project_id / _fetch_all — otherwise a subshell's increment is lost
# and the next call re-serves fixture #1. The last fixture repeats once the list is exhausted.
_next_fixture() {
  local n pick
  n=$(( $(cat "$_FIX_COUNTER" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$_FIX_COUNTER"
  # Exhaustion is an ERROR, not repeat-the-last — an unexpected extra GraphQL call must
  # surface loudly in tests rather than being fed a stale (valid-looking) response.
  pick=$(printf '%s' "$PROJECT_FETCH_FIXTURE" | awk -F: -v n="$n" '{ if (n<=NF) print $n; else exit 1 }')
  if [ -z "$pick" ]; then
    echo "project: fixture list exhausted at call $n — unexpected extra GraphQL call" >&2
    return 1
  fi
  printf '%s' "$pick"
}

# _graphql QUERY VARS_JSON → raw response JSON on stdout, or return 1 on any failure.
# Fixture-backed when PROJECT_FETCH_FIXTURE is set; else a live curl POST. GraphQL-level
# errors (Linear returns HTTP 200 + errors[]) are treated as FAILURE for BOTH paths.
_graphql() {
  local query="$1" vars="${2:-null}" resp
  if [ -n "${PROJECT_FETCH_FIXTURE:-}" ]; then
    local fx
    fx="$(_next_fixture)"
    if [ ! -f "$fx" ]; then echo "project: fixture not found: $fx" >&2; return 1; fi
    resp="$(cat "$fx")"
  else
    _load_key || return 1
    local body
    body=$(jq -n --arg q "$query" --argjson v "$vars" '{query: $q, variables: $v}')
    resp=$(curl -s --connect-timeout 15 --max-time 300 -X POST "$LINEAR_API_URL" \
      -H "Authorization: $LINEAR_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$body") || { echo "project: network error/timeout calling Linear" >&2; return 1; }
  fi
  if printf '%s' "$resp" | jq -e '(.errors // []) | length > 0' >/dev/null 2>&1; then
    echo "project: GraphQL error: $(printf '%s' "$resp" | jq -c '.errors' 2>/dev/null)" >&2
    return 1
  fi
  if ! printf '%s' "$resp" | jq -e . >/dev/null 2>&1; then
    echo "project: invalid JSON response from Linear" >&2
    return 1
  fi
  printf '%s' "$resp"
}

# ---- GraphQL queries ----

_q_resolve_project() {
  cat <<'GQL'
query($name: String!) {
  projects(filter: { name: { eq: $name } }, first: 50) {
    nodes { id name url }
  }
}
GQL
}

_q_issues() {
  cat <<'GQL'
query($projectId: String!, $since: DateTimeOrDuration, $after: String) {
  project(id: $projectId) {
    id name url
    projectMilestones(first: 100) { nodes { id name } }
    issues(first: 250, after: $after, orderBy: createdAt, filter: { updatedAt: { gt: $since } }) {
      pageInfo { hasNextPage endCursor }
      nodes {
        id identifier title url createdAt updatedAt priority
        state { name }
        projectMilestone { name }
        comments(first: 250) {
          pageInfo { hasNextPage endCursor }
          nodes { id body createdAt parent { id } user { name } botActor { name } }
        }
        history(first: 250) {
          pageInfo { hasNextPage }
          nodes {
            createdAt actor { name }
            fromState { name } toState { name }
            fromPriority toPriority
            fromAssignee { name } toAssignee { name }
            fromProjectMilestone { name } toProjectMilestone { name }
          }
        }
        attachments(first: 250) {
          pageInfo { hasNextPage }
          nodes { id title url }
        }
      }
    }
  }
}
GQL
}

_q_comments() {
  cat <<'GQL'
query($issueId: String!, $after: String) {
  issue(id: $issueId) {
    comments(first: 250, after: $after) {
      pageInfo { hasNextPage endCursor }
      nodes { id body createdAt parent { id } user { name } botActor { name } }
    }
  }
}
GQL
}

# ---- Fetch ----

# _resolve_project_id INPUT → project UUID on stdout. UUID passed through; name resolved.
_resolve_project_id() {
  local input="$1"
  if printf '%s' "$input" | grep -qiE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
    printf '%s' "$input"; return 0
  fi
  local resp nodes count
  resp=$(_graphql "$(_q_resolve_project)" "$(jq -n --arg n "$input" '{name: $n}')") || return 1
  nodes=$(printf '%s' "$resp" | jq '[.data.projects.nodes[]?]')
  count=$(printf '%s' "$nodes" | jq 'length')
  if [ "$count" = "0" ]; then echo "project: no project named '$input'" >&2; return 1; fi
  if [ "$count" != "1" ]; then
    echo "project: ambiguous name '$input' → $(printf '%s' "$nodes" | jq -c 'map({id,name})')" >&2
    return 1
  fi
  printf '%s' "$nodes" | jq -r '.[0].id'
}

# _fetch_all INPUT_ID SINCE → {project, milestones, issues} on stdout (fully paginated).
_fetch_all() {
  local pid="$1" since="$2" after="null" resp page meta="" milestones="" prev_cursor=""
  # Accumulate pages to a temp FILE (one compact node-array per line), never to a shell var
  # passed via `jq --argjson` — a first-full-drain accumulator would blow ARG_MAX/E2BIG
  # (single-arg exec caps at ~1MB on macOS, 128KB per arg on Linux).
  local issues_file; issues_file=$(mktemp -t projfetch-issues.XXXXXX)
  trap 'rm -f "$issues_file"' RETURN
  while :; do
    resp=$(_graphql "$(_q_issues)" \
      "$(jq -n --arg p "$pid" --arg s "$since" --argjson a "$after" \
        '{projectId: $p, since: (if $s == "" then null else $s end), after: $a}')") || return 1
    page=$(printf '%s' "$resp" | jq '.data.project // null')
    if [ "$page" = "null" ]; then echo "project: project not found: $pid" >&2; return 1; fi
    if [ -z "$meta" ]; then
      meta=$(printf '%s' "$page" | jq '{id, name, url}')
      milestones=$(printf '%s' "$page" | jq '[.projectMilestones.nodes[]? | {id, name}]')
    fi
    printf '%s' "$page" | jq -c '[.issues.nodes[]?]' >> "$issues_file"
    local has end
    has=$(printf '%s' "$page" | jq -r '.issues.pageInfo.hasNextPage')
    [ "$has" = "true" ] || break
    end=$(printf '%s' "$page" | jq -r '.issues.pageInfo.endCursor')
    # Cursor-progress guard: a blank/non-advancing endCursor with hasNextPage:true loops forever.
    if [ -z "$end" ] || [ "$end" = "null" ] || [ "$end" = "$prev_cursor" ]; then
      echo "project: issue pagination cursor did not advance — aborting to avoid an infinite loop" >&2
      return 1
    fi
    prev_cursor="$end"
    after=$(jq -n --arg c "$end" '$c')
  done
  # Slurp all page-arrays into one issues array (read from file, off argv).
  local all
  all=$(jq -s 'add // []' "$issues_file")

  # Nested comment pagination: any issue whose first comment page is truncated gets its
  # remaining comments fetched and appended (a firehose channel can exceed 250 in one delta).
  # History/attachments overflow is implausible in a delta window → fail-closed rather than
  # silently truncate (never emit a tree/list missing rows).
  local overflow
  overflow=$(printf '%s' "$all" | jq -r '[.[] | select((.history.pageInfo.hasNextPage // false) or (.attachments.pageInfo.hasNextPage // false)) | .identifier] | join(", ")')
  if [ -n "$overflow" ]; then
    echo "project: delta too large — issue(s) [$overflow] have >250 new history/attachment rows; narrow --since" >&2
    return 1
  fi

  local trunc iid
  for iid in $(printf '%s' "$all" | jq -r '.[] | select(.comments.pageInfo.hasNextPage // false) | .id'); do
    trunc=$(printf '%s' "$all" | jq -r --arg id "$iid" '.[] | select(.id==$id) | .comments.pageInfo.endCursor')
    local more
    more=$(_fetch_remaining_comments "$iid" "$trunc") || return 1
    all=$(printf '%s' "$all" | jq --arg id "$iid" --argjson more "$more" \
      'map(if .id == $id then .comments.nodes = (.comments.nodes + $more) else . end)')
  done

  printf '%s' "$all" | jq --argjson meta "$meta" --argjson ms "${milestones:-[]}" \
    '{project: $meta, milestones: $ms, issues: .}'
}

# _fetch_remaining_comments ISSUE_ID AFTER_CURSOR → array of remaining comment nodes.
_fetch_remaining_comments() {
  local iid="$1" after="$2" acc="[]" resp
  while :; do
    resp=$(_graphql "$(_q_comments)" "$(jq -n --arg id "$iid" --arg a "$after" '{issueId: $id, after: $a}')") || return 1
    acc=$(printf '%s' "$acc" | jq --argjson n "$(printf '%s' "$resp" | jq '[.data.issue.comments.nodes[]?]')" '. + $n')
    local has
    has=$(printf '%s' "$resp" | jq -r '.data.issue.comments.pageInfo.hasNextPage')
    [ "$has" = "true" ] || break
    after=$(printf '%s' "$resp" | jq -r '.data.issue.comments.pageInfo.endCursor')
  done
  printf '%s' "$acc"
}

# ---- Transform (pure jq) ----

# _assemble RAW SINCE FETCHED_AT INBOX → the envelope. RAW = {project, milestones, issues}.
_assemble() {
  local raw="$1" since="$2" fetched_at="$3" inbox="${4:-Inboxes}"
  printf '%s' "$raw" | jq \
    --arg since "$since" --arg fetchedAt "$fetched_at" --arg inbox "$inbox" '
    def author: (.user.name // .botActor.name // "(bot)");
    # Normalize ISO8601 to fixed-width millisecond form so a lexicographic compare is
    # chronologically correct across mixed precision (plain vs .SSS, Z-optional).
    def normTs:
      (. // "") as $t
      | if $t == "" then "" else
          ($t | sub("Z$"; "")) as $b
          | ($b | split(".")) as $p
          | $p[0] + "." + (((if ($p | length) > 1 then $p[1] else "" end) + "000")[0:3]) + "Z"
        end;
    # Comment forest: a root is parentless OR its parent was filtered out by the since-cutoff
    # (pre-since). Re-rooting orphans means a NEW reply to an OLD thread is never dropped.
    def buildTree($cs; $ids):
      def kids($pid): [ $cs[] | select((.parent.id // null) == $pid)
        | { id, author: author, createdAt, body, orphanReply: false, children: kids(.id) } ];
      [ $cs[]
        | select((.parent.id // null) as $p | ($p == null) or (($ids | index($p)) == null))
        | { id, author: author, createdAt, body,
            orphanReply: ((.parent.id // null) != null), children: kids(.id) } ];
    def treeCount: reduce .[] as $c (0; . + 1 + ($c.children | treeCount));
    # One IssueHistory node → ALL its applicable normalized transitions (a single edit can
    # change several fields at once; emit each, not just the first).
    def lifeEvents:
      . as $h
      | [ (if $h.toState != null then {type:"state", actor:($h.actor.name // "(unknown)"), at:$h.createdAt, from:($h.fromState.name // null), to:$h.toState.name} else empty end),
          (if ($h.toProjectMilestone != null or $h.fromProjectMilestone != null) then {type:"milestone", actor:($h.actor.name // "(unknown)"), at:$h.createdAt, from:($h.fromProjectMilestone.name // null), to:($h.toProjectMilestone.name // null)} else empty end),
          (if ($h.toAssignee != null or $h.fromAssignee != null) then {type:"assignee", actor:($h.actor.name // "(unknown)"), at:$h.createdAt, from:($h.fromAssignee.name // null), to:($h.toAssignee.name // null)} else empty end),
          (if $h.toPriority != null then {type:"priority", actor:($h.actor.name // "(unknown)"), at:$h.createdAt, from:$h.fromPriority, to:$h.toPriority} else empty end) ];

    ($since | normTs) as $sn
    | .project as $project
    | .milestones as $milestones
    | ( [ .issues[]
          | ( [ (.comments.nodes // [])[] | select((.createdAt | normTs) > $sn) ] ) as $cs
          | ( $cs | map(.id) ) as $ids
          | ( [ (.history.nodes // [])[] | select((.createdAt | normTs) > $sn) | lifeEvents[] ] ) as $life
          | ( [ (.attachments.nodes // [])[] | { id, title, url } ] ) as $att
          | ( buildTree($cs; $ids) ) as $tree
          | {
              id, identifier, title, url,
              state: (.state.name // null),
              priority,
              milestone: (.projectMilestone.name // null),
              isChannel: ((.projectMilestone.name // "") == $inbox),
              createdAt, updatedAt,
              isNew: ((.createdAt | normTs) > $sn),
              comments: $tree,
              lifecycle: $life,
              attachments: $att,
              _commentCount: ($tree | treeCount)
            }
        ] ) as $tickets
    | {
        project: $project,
        since: $since,
        fetchedAt: $fetchedAt,
        structure: {
          milestones: $milestones,
          channels: [ $tickets[] | select(.isChannel)
                      | { id, identifier, title, milestone } ]
        },
        tickets: [ $tickets[] | del(._commentCount) ],
        summary: {
          ticketCount: ($tickets | length),
          newTicketCount: ([ $tickets[] | select(.isNew) ] | length),
          activity: [ $tickets[]
            | select((._commentCount > 0) or (.lifecycle | length > 0) or (.attachments | length > 0))
            | { identifier, title,
                comments: ._commentCount,
                lifecycle: (.lifecycle | length),
                attachments: (.attachments | length) } ]
        }
      }
  '
}

# ---- fetch orchestration (¶INV_WRITE_BEFORE_WATERMARK) ----

cmd_fetch() {
  local input="" since_override="" out="" have_since=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --since) since_override="${2:-}"; have_since=1; shift 2 ;;
      --since=*) since_override="${1#*=}"; have_since=1; shift ;;
      --out) out="${2:-}"; shift 2 ;;
      --out=*) out="${1#*=}"; shift ;;
      -*) echo "project: unknown flag '$1'" >&2; return 1 ;;
      *) input="$1"; shift ;;
    esac
  done
  [ -n "$input" ] || { echo "project: fetch requires <project>" >&2; return 1; }

  local pid since
  pid=$(_resolve_project_id "$input") || return 1
  if [ "$have_since" = "1" ]; then since="$since_override"; else since="$(_waterline_get "$pid")"; fi

  local raw
  raw=$(_fetch_all "$pid" "$since") || return 1

  # Which milestone designates the inbox channels (default "Inboxes"). A project whose intake
  # milestone is named differently would otherwise return silently-empty channels — warn.
  local inbox="${PROJECT_FETCH_INBOX_MILESTONE:-Inboxes}"
  if ! printf '%s' "$raw" | jq -e --arg ib "$inbox" '[.milestones[]?.name] | index($ib)' >/dev/null 2>&1; then
    echo "project: note — no milestone named '$inbox' in this project; structure.channels will be empty (override with PROJECT_FETCH_INBOX_MILESTONE)" >&2
  fi

  local fetched_at payload
  fetched_at="$(timestamp)"
  payload=$(_assemble "$raw" "$since" "$fetched_at" "$inbox") || { echo "project: transform failed" >&2; return 1; }

  # Durable write BEFORE waterline advance. Any failure above already returned non-zero
  # with the waterline untouched.
  if [ -z "$out" ]; then
    local pdir
    pdir="$(_state_dir)/payloads"
    mkdir -p "$pdir"
    out="$pdir/${pid}-$(date +%s)-$$.json"
  else
    mkdir -p "$(dirname "$out")" 2>/dev/null || true
  fi
  if ! printf '%s' "$payload" | safe_json_write "$out"; then
    echo "project: failed to write payload to $out" >&2
    return 1
  fi

  # Payload is durable — NOW advance the waterline to the max updatedAt seen (idempotent
  # re-runs: next fetch filters updatedAt > this). No issues → keep the effective since.
  # Normalize before max so mixed ISO precision (.SSS vs plain Z) can't undershoot the
  # high-water mark and re-emit a boundary issue next run (parity with _assemble's normTs).
  local new_wm
  new_wm=$(printf '%s' "$raw" | jq -r '
    def normTs: (. // "") | if . == "" then "" else (sub("Z$"; "")) as $b
      | ($b | split(".")) as $p
      | $p[0] + "." + (((if ($p | length) > 1 then $p[1] else "" end) + "000")[0:3]) + "Z" end;
    ([.issues[].updatedAt | normTs] | max) // empty')
  [ -n "$new_wm" ] || new_wm="$since"
  if [ -n "$new_wm" ]; then _waterline_set "$pid" "$new_wm" || true; fi

  printf '%s\n' "$out"
}

# ---- waterline subcommand ----

cmd_waterline() {
  case "${1:-}" in
    get)
      [ -n "${2:-}" ] || { echo "project: waterline get requires <project>" >&2; return 1; }
      local pid; pid=$(_resolve_project_id "$2") || return 1
      _waterline_get "$pid"; echo ;;
    list)
      jq '.' "$(_waterlines_file)" ;;
    reset)
      [ -n "${2:-}" ] || { echo "project: waterline reset requires <project>" >&2; return 1; }
      local pid; pid=$(_resolve_project_id "$2") || return 1
      safe_json_update "$(_waterlines_file)" --arg p "$pid" 'del(.[$p])' && echo "project: reset waterline for $pid" ;;
    *) echo "project: waterline <get|list|reset> [project]" >&2; return 1 ;;
  esac
}

# ---- Dispatch ----
case "${1:-}" in
  fetch)     shift; cmd_fetch "$@" ;;
  waterline) shift; cmd_waterline "$@" ;;
  ""|-h|--help|help) usage ;;
  *) echo "project: unknown subcommand '$1'" >&2; usage; exit 1 ;;
esac
