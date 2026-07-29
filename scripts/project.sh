#!/bin/bash
# project.sh — engine project fetch: one Linear-project delta as a single JSON payload
#
# `engine project fetch <project> [--since=<ISO>] [--out=<path>]` queries Linear's
# GraphQL API and writes ONE payload of everything in a Project at/after a caller-supplied
# --since cutoff: inbox-channel comment TREES, new comments on ordinary tickets,
# new tickets, attachment URLs, normalized lifecycle events (who/when/from→to), a live
# structure catalog (channels enumerated independent of the delta), and a summary layer.
# Read-only toward Linear.
#
# The CLI is STATELESS: --since is the caller's responsibility (¶INV_LINEAR_IS_TRUTH).
# A bare `engine project fetch <project>` is a full snapshot (no cutoff); --since=<ISO>
# makes it incremental. The consumer (/intake) owns its own watermark in its own doc —
# there is no CLI-side stored waterline.
#
# The payload is the terminal durable step (¶INV_WRITE_BEFORE_WATERMARK): any failure
# exits non-zero with no payload written, so an interrupted run re-fetches cleanly and the
# caller's watermark (advanced only after the payload lands) never leaps past unseen data.
#
# Usage:
#   engine project fetch <project> [--since=<ISO8601>] [--out=<path>]
#
#   <project> : Linear project UUID (used directly) or name (resolved via a projects query).
#   --since   : ISO8601 cutoff for this run; omit for a full snapshot.
#   --out     : payload destination (default $STATE_DIR/payloads/<projectId>-<epoch>.json).
#               The written path is always printed as the last stdout line.
#
# Auth (live path only): LINEAR_API_KEY from env or .env (repo root or ~/.claude/engine/.env).
# Env: PROJECT_FETCH_STATE_DIR (default ~/.claude/engine/.project-fetch) — default payload dir.
#      PROJECT_FETCH_FIXTURE (test-only) — file or colon-separated file list; short-circuits _graphql.
#      PROJECT_FETCH_INBOX_MILESTONE (default Inboxes) — the milestone naming the inbox channels.
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

# ---- State dir (default payload destination only — no stored waterline) ----

_state_dir() {
  local d="${PROJECT_FETCH_STATE_DIR:-$HOME/.claude/engine/.project-fetch}"
  mkdir -p "$d" 2>/dev/null || true
  printf '%s' "$d"
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
query($projectId: String!, $filter: IssueFilter, $after: String, $inbox: String!) {
  project(id: $projectId) {
    id name url
    projectMilestones(first: 100) { nodes { id name } }
    channels: issues(first: 100, filter: { projectMilestone: { name: { eq: $inbox } } }) {
      nodes { id identifier title projectMilestone { name } }
    }
    issues(first: 25, after: $after, orderBy: createdAt, filter: $filter) {
      pageInfo { hasNextPage endCursor }
      nodes {
        id identifier title url createdAt updatedAt priority
        state { name }
        projectMilestone { name }
        comments(first: 40) {
          pageInfo { hasNextPage endCursor }
          nodes { id body createdAt quotedText parent { id } user { name } botActor { name } }
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
}
GQL
}

_q_comments() {
  cat <<'GQL'
query($issueId: String!, $after: String) {
  issue(id: $issueId) {
    comments(first: 250, after: $after) {
      pageInfo { hasNextPage endCursor }
      nodes { id body createdAt quotedText parent { id } user { name } botActor { name } }
    }
  }
}
GQL
}

# Per-issue follow-up queries. Flat (single issue → one connection), so first:250 is safe here —
# only the NESTED first: values in _q_issues multiply into Linear's query-complexity cap.
_q_history() {
  cat <<'GQL'
query($issueId: String!, $after: String) {
  issue(id: $issueId) {
    history(first: 250, after: $after) {
      pageInfo { hasNextPage endCursor }
      nodes {
        createdAt actor { name }
        fromState { name } toState { name }
        fromPriority toPriority
        fromAssignee { name } toAssignee { name }
        fromProjectMilestone { name } toProjectMilestone { name }
      }
    }
  }
}
GQL
}

_q_attachments() {
  cat <<'GQL'
query($issueId: String!, $after: String) {
  issue(id: $issueId) {
    attachments(first: 250, after: $after) {
      pageInfo { hasNextPage endCursor }
      nodes { id title url }
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

# _fetch_all INPUT_ID SINCE INBOX → {project, milestones, channels, issues} on stdout (paginated).
# Channels are enumerated from the aliased inbox-milestone connection (independent of the delta
# filter), so a quiet channel with no new activity still appears in structure.channels.
_fetch_all() {
  local pid="$1" since="$2" inbox="${3:-Inboxes}" after="null" resp page meta="" milestones="" channels="" prev_cursor=""
  # Accumulate pages to a temp FILE (one compact node-array per line), never to a shell var
  # passed via `jq --argjson` — a first-full-drain accumulator would blow ARG_MAX/E2BIG
  # (single-arg exec caps at ~1MB on macOS, 128KB per arg on Linux).
  local issues_file; issues_file=$(mktemp -t projfetch-issues.XXXXXX)
  trap 'rm -f "$issues_file"' RETURN
  while :; do
    resp=$(_graphql "$(_q_issues)" \
      "$(jq -n --arg p "$pid" --arg s "$since" --argjson a "$after" --arg ib "$inbox" \
        '{projectId: $p, filter: (if $s == "" then {} else {updatedAt: {gt: $s}} end), after: $a, inbox: $ib}')") || return 1
    page=$(printf '%s' "$resp" | jq '.data.project // null')
    if [ "$page" = "null" ]; then echo "project: project not found: $pid" >&2; return 1; fi
    if [ -z "$meta" ]; then
      meta=$(printf '%s' "$page" | jq '{id, name, url}')
      milestones=$(printf '%s' "$page" | jq '[.projectMilestones.nodes[]? | {id, name}]')
      channels=$(printf '%s' "$page" | jq '[.channels.nodes[]? | {id, identifier, title, milestone: (.projectMilestone.name // null)}]')
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

  # Per-issue child pagination: any issue whose first inline page (comments / history / attachments)
  # is truncated gets its remaining rows fetched and appended. _q_issues keeps the per-issue child
  # page small to stay under Linear's query-complexity cap; the overflow is paginated here per-issue
  # (flat follow-up queries, cheap) so a firehose channel or a long-history epic is never truncated.
  local trunc iid more
  for iid in $(printf '%s' "$all" | jq -r '.[] | select(.comments.pageInfo.hasNextPage // false) | .id'); do
    trunc=$(printf '%s' "$all" | jq -r --arg id "$iid" '.[] | select(.id==$id) | .comments.pageInfo.endCursor')
    more=$(_fetch_remaining_comments "$iid" "$trunc") || return 1
    all=$(printf '%s' "$all" | jq --arg id "$iid" --argjson more "$more" \
      'map(if .id == $id then .comments.nodes = (.comments.nodes + $more) else . end)')
  done
  for iid in $(printf '%s' "$all" | jq -r '.[] | select(.history.pageInfo.hasNextPage // false) | .id'); do
    trunc=$(printf '%s' "$all" | jq -r --arg id "$iid" '.[] | select(.id==$id) | .history.pageInfo.endCursor')
    more=$(_fetch_remaining_history "$iid" "$trunc") || return 1
    all=$(printf '%s' "$all" | jq --arg id "$iid" --argjson more "$more" \
      'map(if .id == $id then .history.nodes = (.history.nodes + $more) else . end)')
  done
  for iid in $(printf '%s' "$all" | jq -r '.[] | select(.attachments.pageInfo.hasNextPage // false) | .id'); do
    trunc=$(printf '%s' "$all" | jq -r --arg id "$iid" '.[] | select(.id==$id) | .attachments.pageInfo.endCursor')
    more=$(_fetch_remaining_attachments "$iid" "$trunc") || return 1
    all=$(printf '%s' "$all" | jq --arg id "$iid" --argjson more "$more" \
      'map(if .id == $id then .attachments.nodes = (.attachments.nodes + $more) else . end)')
  done

  printf '%s' "$all" | jq --argjson meta "$meta" --argjson ms "${milestones:-[]}" --argjson ch "${channels:-[]}" \
    '{project: $meta, milestones: $ms, channels: $ch, issues: .}'
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

# _fetch_remaining_history ISSUE_ID AFTER_CURSOR → array of remaining history nodes.
_fetch_remaining_history() {
  local iid="$1" after="$2" acc="[]" resp
  while :; do
    resp=$(_graphql "$(_q_history)" "$(jq -n --arg id "$iid" --arg a "$after" '{issueId: $id, after: $a}')") || return 1
    acc=$(printf '%s' "$acc" | jq --argjson n "$(printf '%s' "$resp" | jq '[.data.issue.history.nodes[]?]')" '. + $n')
    local has
    has=$(printf '%s' "$resp" | jq -r '.data.issue.history.pageInfo.hasNextPage')
    [ "$has" = "true" ] || break
    after=$(printf '%s' "$resp" | jq -r '.data.issue.history.pageInfo.endCursor')
  done
  printf '%s' "$acc"
}

# _fetch_remaining_attachments ISSUE_ID AFTER_CURSOR → array of remaining attachment nodes.
_fetch_remaining_attachments() {
  local iid="$1" after="$2" acc="[]" resp
  while :; do
    resp=$(_graphql "$(_q_attachments)" "$(jq -n --arg id "$iid" --arg a "$after" '{issueId: $id, after: $a}')") || return 1
    acc=$(printf '%s' "$acc" | jq --argjson n "$(printf '%s' "$resp" | jq '[.data.issue.attachments.nodes[]?]')" '. + $n')
    local has
    has=$(printf '%s' "$resp" | jq -r '.data.issue.attachments.pageInfo.hasNextPage')
    [ "$has" = "true" ] || break
    after=$(printf '%s' "$resp" | jq -r '.data.issue.attachments.pageInfo.endCursor')
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
        | { id, author: author, createdAt, body, quotedText: (.quotedText // null), orphanReply: false, children: kids(.id) } ];
      [ $cs[]
        | select((.parent.id // null) as $p | ($p == null) or (($ids | index($p)) == null))
        | { id, author: author, createdAt, body, quotedText: (.quotedText // null),
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
    | (.channels // []) as $channels
    | (([$milestones[].name] | index($inbox)) != null) as $channelsResolved
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
        channelsResolved: $channelsResolved,
        structure: {
          milestones: $milestones,
          channels: $channels
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

  # --since is the caller's responsibility; no stored waterline. Omitted → full snapshot.
  local pid since=""
  pid=$(_resolve_project_id "$input") || return 1
  if [ "$have_since" = "1" ]; then since="$since_override"; fi

  # Which milestone designates the inbox channels (default "Inboxes"). Passed to the channels
  # query so a quiet channel still enumerates; channelsResolved in the payload is the machine
  # signal, and a missing milestone gets a human-readable stderr note.
  local inbox="${PROJECT_FETCH_INBOX_MILESTONE:-Inboxes}"

  local raw
  raw=$(_fetch_all "$pid" "$since" "$inbox") || return 1

  if ! printf '%s' "$raw" | jq -e --arg ib "$inbox" '[.milestones[]?.name] | index($ib)' >/dev/null 2>&1; then
    echo "project: note — no milestone named '$inbox' in this project; structure.channels will be empty (channelsResolved:false; override with PROJECT_FETCH_INBOX_MILESTONE)" >&2
  fi

  local fetched_at payload
  fetched_at="$(timestamp)"
  payload=$(_assemble "$raw" "$since" "$fetched_at" "$inbox") || { echo "project: transform failed" >&2; return 1; }

  # The payload write is the terminal durable step (¶INV_WRITE_BEFORE_WATERMARK): any failure
  # above already returned non-zero with nothing written, and there is no CLI-side watermark to
  # advance — the consumer advances its own only after this path prints the payload location.
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

  printf '%s\n' "$out"
}

# ---- Dispatch ----
case "${1:-}" in
  fetch)     shift; cmd_fetch "$@" ;;
  ""|-h|--help|help) usage ;;
  *) echo "project: unknown subcommand '$1'" >&2; usage; exit 1 ;;
esac
