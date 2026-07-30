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
# The Linear GraphQL seam (_graphql/_load_key/_next_fixture + fixture counter), LINEAR_API_URL,
# and the shared jq transform ($LINEAR_JQ_DEFS/issueToTicket) live here — shared with ticket.sh.
# shellcheck source=/dev/null
source "$SCRIPT_DIR/linear-lib.sh"

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
}
GQL
}

# ---- Fetch ----
# Per-issue follow-up queries (_q_comments/_q_history/_q_attachments) + their pagination
# (_fetch_remaining_* / _paginate_issue_children) are shared machinery in linear-lib.sh.

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

  # Per-issue child pagination (comments/history/attachments overflow) — shared with ticket fetch.
  all=$(_paginate_issue_children "$all") || return 1

  printf '%s' "$all" | jq --argjson meta "$meta" --argjson ms "${milestones:-[]}" --argjson ch "${channels:-[]}" \
    '{project: $meta, milestones: $ms, channels: $ch, issues: .}'
}

# ---- Transform (pure jq) ----

# _assemble RAW SINCE FETCHED_AT INBOX → the envelope. RAW = {project, milestones, issues}.
_assemble() {
  local raw="$1" since="$2" fetched_at="$3" inbox="${4:-Inboxes}"
  # The per-issue defs (author/normTs/buildTree/treeCount/lifeEvents/issueToTicket) come from
  # the shared $LINEAR_JQ_DEFS (linear-lib.sh); only the project envelope is assembled here.
  printf '%s' "$raw" | jq \
    --arg since "$since" --arg fetchedAt "$fetched_at" --arg inbox "$inbox" "$LINEAR_JQ_DEFS"'
    ($since | normTs) as $sn
    | .project as $project
    | .milestones as $milestones
    | (.channels // []) as $channels
    | (([$milestones[].name] | index($inbox)) != null) as $channelsResolved
    | ( [ .issues[]
          | . as $issue
          | issueToTicket($sn)
          | . + { isChannel: (($issue.projectMilestone.name // "") == $inbox),
                  _commentCount: (.comments | treeCount) }
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
