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
#   engine project next  [<project>] [--query "<text>"] [--tickets K1,K2] [--all] [--limit N] [--json] [--team KEY]
#   engine project lint  <project> | --all | --stdin --container <c> [--target NAME]
#                        [--schema <path>] [--inbox <milestone>] [--json] [--strict]
#
#   <project> : Linear project UUID (used directly) or name (resolved via a projects query).
#   --since   : ISO8601 cutoff for this run; omit for a full snapshot.
#   --out     : payload destination (default $STATE_DIR/payloads/<projectId>-<epoch>.json).
#               The written path is always printed as the last stdout line.
#
# `next` — advisory, read-only "what's next here": open work ranked milestone→priority→blocked,
#   grouped by work-type, printed as THREE never-blended lists — importance (always), adjacency
#   (--query, fuzzy term-overlap), and linked (--tickets K1,K2: the exact Linear relation cluster —
#   related/parent/child/blocks/blockedBy/duplicate, cross-project resolved). Each importance row
#   also carries its own relatedTo/parent/blocks/blockedBy keys. Proposes; never starts. <project>
#   defaults from the branch's ticket key; --all widens to team-wide (priority-ranked).
#
# `lint` — read-only container conformance: checks a project's description, its Inbox Handbook and
#   its channel tickets against the section schema (skills/intake/assets/project-schema.json).
#   --all lints every project in the schema's own `scope` block and adds the cross-project peer
#   comparison; --stdin --container <c> lints text the caller already holds (the wave's pre-write
#   gate) and has no peers to compare against, so it says so rather than reporting a clean one.
#   Exit 0 clean-or-warnings · 1 failures · 2 could-not-run OR partial coverage.
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
  cat <<'GQL' | _sub_comment_fields
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
          nodes { @COMMENT_FIELDS@ }
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

# ---- `next`: advisory next-task queue (stateless, read-only) ----
#
# Reuses the shared seam (_graphql/_load_key/fixtures) but NOT cmd_fetch — a thin projection,
# not the full-snapshot engine (¶INV: reuse the seam, not the query). Proposes; never starts
# (only read queries are ever issued). Importance and adjacency stay two separate lists.

# Known work-type labels, first substring match wins, else "other".
_PROJECT_NEXT_WORKTYPES="bug feature chore spike docs refactor"

# Thin projection — open issues only, milestone/priority/labels/blocking. Nested first: kept
# small (labels 10 + inverseRelations 10 on issues 50) so the complexity product stays well
# under Linear's 10k cap (¶PTF_NESTED_GRAPHQL_FIRST_MULTIPLIES_COMPLEXITY). No comments/history.
_q_next() {
  cat <<'GQL'
query($projectId: String!, $after: String) {
  project(id: $projectId) {
    id name url
    projectMilestones(first: 100) { nodes { id name sortOrder } }
    issues(first: 50, after: $after, filter: { state: { type: { nin: ["completed", "canceled"] } } }) {
      pageInfo { hasNextPage endCursor }
      nodes {
        id identifier title url priority estimate
        state { name type }
        projectMilestone { name sortOrder }
        labels(first: 10) { nodes { name } }
        parent { identifier }
        relations(first: 10) { nodes { type relatedIssue { identifier state { type } } } }
        inverseRelations(first: 10) { nodes { type issue { identifier state { type } } } }
      }
    }
  }
}
GQL
}

# Team-wide open issues (--all) — no project scope; carries each issue's project name.
_q_next_team() {
  cat <<'GQL'
query($teamKey: String!, $after: String) {
  issues(first: 50, after: $after, filter: { team: { key: { eq: $teamKey } }, state: { type: { nin: ["completed", "canceled"] } } }) {
    pageInfo { hasNextPage endCursor }
    nodes {
      id identifier title url priority
      state { name type }
      project { name }
      projectMilestone { name sortOrder }
      labels(first: 10) { nodes { name } }
      parent { identifier }
      relations(first: 10) { nodes { type relatedIssue { identifier state { type } } } }
      inverseRelations(first: 10) { nodes { type issue { identifier state { type } } } }
    }
  }
}
GQL
}

# Anchor query (--tickets) — one issue with its FULL relation graph, titles/state/project resolved
# inline so cross-project links are usable without a follow-up read. Called once per anchor key.
_q_anchor() {
  cat <<'GQL'
query($id: String!) {
  issue(id: $id) {
    identifier title state { name type } project { name }
    parent { identifier title state { name type } project { name } }
    children(first: 20) { nodes { identifier title state { name type } project { name } } }
    relations(first: 20) { nodes { type relatedIssue { identifier title state { name type } project { name } } } }
    inverseRelations(first: 20) { nodes { type issue { identifier title state { name type } project { name } } } }
  }
}
GQL
}

# _fetch_anchor KEYS_CSV → the `linked` array: every ticket connected to any anchor key, tagged
# by relation kind (related/parent/child/blocks/blockedBy/duplicate), titles/project resolved.
_fetch_anchor() {
  local keys_csv="$1" acc="[]" key resp rows
  local oldIFS="$IFS"; IFS=','
  for key in $keys_csv; do
    IFS="$oldIFS"
    key=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')
    if [ -n "$key" ]; then
      resp=$(_graphql "$(_q_anchor)" "$(jq -n --arg id "$key" '{id: $id}')") || { IFS="$oldIFS"; return 1; }
      rows=$(printf '%s' "$resp" | jq --arg anchor "$key" '
        (.data.issue // null) as $iss
        | if $iss == null then [] else
          [ ( $iss.parent // empty | { identifier, title, state: (.state.name // null), project: (.project.name // null), relation: "parent" } ),
            ( ($iss.children.nodes // [])[] | { identifier, title, state: (.state.name // null), project: (.project.name // null), relation: "child" } ),
            ( ($iss.relations.nodes // [])[] | { identifier: .relatedIssue.identifier, title: .relatedIssue.title, state: (.relatedIssue.state.name // null), project: (.relatedIssue.project.name // null),
                relation: (if .type == "blocks" then "blocks" elif .type == "duplicate" then "duplicate" else "related" end) } ),
            ( ($iss.inverseRelations.nodes // [])[] | { identifier: .issue.identifier, title: .issue.title, state: (.issue.state.name // null), project: (.issue.project.name // null),
                relation: (if .type == "blocks" then "blockedBy" elif .type == "duplicate" then "duplicate" else "related" end) } )
          ] | map(. + { anchor: $anchor })
        end')
      acc=$(printf '%s' "$acc" | jq --argjson r "$rows" '. + $r')
    fi
    IFS=','
  done
  IFS="$oldIFS"
  printf '%s' "$acc" | jq 'unique_by([.identifier, .relation, .anchor])'
}

# Resolve a project id from the current git branch's leading ticket key (e.g. fin-2833-… → FIN-2833).
_q_issue_project() { cat <<'GQL'
query($id: String!) { issue(id: $id) { id identifier project { id name } } }
GQL
}
_infer_project_from_branch() {
  local branch key resp pid
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
  key=$(printf '%s' "$branch" | grep -oiE '^[a-z]+-[0-9]+' | head -1)
  [ -n "$key" ] || return 1
  key=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')
  resp=$(_graphql "$(_q_issue_project)" "$(jq -n --arg id "$key" '{id: $id}')") || return 1
  pid=$(printf '%s' "$resp" | jq -r '.data.issue.project.id // empty')
  [ -n "$pid" ] || return 1
  printf '%s' "$pid"
}

# _fetch_next PID → {project, milestones, issues} (paginated, thin). Cursor-progress guarded.
_fetch_next() {
  local pid="$1" after="null" resp page meta="" milestones="" prev_cursor=""
  local issues_file; issues_file=$(mktemp -t projnext-issues.XXXXXX)
  trap 'rm -f "$issues_file"' RETURN
  while :; do
    resp=$(_graphql "$(_q_next)" "$(jq -n --arg p "$pid" --argjson a "$after" '{projectId: $p, after: $a}')") || return 1
    page=$(printf '%s' "$resp" | jq '.data.project // null')
    if [ "$page" = "null" ]; then echo "project: project not found: $pid" >&2; return 1; fi
    if [ -z "$meta" ]; then
      meta=$(printf '%s' "$page" | jq '{id, name, url}')
      milestones=$(printf '%s' "$page" | jq '[.projectMilestones.nodes[]? | {name, sortOrder}]')
    fi
    printf '%s' "$page" | jq -c '[.issues.nodes[]?]' >> "$issues_file"
    local has end
    has=$(printf '%s' "$page" | jq -r '.issues.pageInfo.hasNextPage')
    [ "$has" = "true" ] || break
    end=$(printf '%s' "$page" | jq -r '.issues.pageInfo.endCursor')
    if [ -z "$end" ] || [ "$end" = "null" ] || [ "$end" = "$prev_cursor" ]; then
      echo "project: issue pagination cursor did not advance — aborting to avoid an infinite loop" >&2; return 1
    fi
    prev_cursor="$end"; after=$(jq -n --arg c "$end" '$c')
  done
  local all; all=$(jq -s 'add // []' "$issues_file")
  printf '%s' "$all" | jq --argjson meta "$meta" --argjson ms "${milestones:-[]}" \
    '{project: $meta, milestones: $ms, issues: .}'
}

# _fetch_next_team TEAMKEY → {project, milestones:[], issues} (team-wide, always degraded).
_fetch_next_team() {
  local team="$1" after="null" resp nodes issues_file prev_cursor=""
  issues_file=$(mktemp -t projnext-team.XXXXXX)
  trap 'rm -f "$issues_file"' RETURN
  while :; do
    resp=$(_graphql "$(_q_next_team)" "$(jq -n --arg t "$team" --argjson a "$after" '{teamKey: $t, after: $a}')") || return 1
    nodes=$(printf '%s' "$resp" | jq '.data.issues // null')
    if [ "$nodes" = "null" ]; then echo "project: team not found: $team" >&2; return 1; fi
    printf '%s' "$nodes" | jq -c '[.nodes[]?]' >> "$issues_file"
    local has end
    has=$(printf '%s' "$nodes" | jq -r '.pageInfo.hasNextPage')
    [ "$has" = "true" ] || break
    end=$(printf '%s' "$nodes" | jq -r '.pageInfo.endCursor')
    if [ -z "$end" ] || [ "$end" = "null" ] || [ "$end" = "$prev_cursor" ]; then
      echo "project: team issue pagination cursor did not advance — aborting" >&2; return 1
    fi
    prev_cursor="$end"; after=$(jq -n --arg c "$end" '$c')
  done
  local all; all=$(jq -s 'add // []' "$issues_file")
  printf '%s' "$all" | jq --arg t "$team" '{project: {name: ("(team " + $t + ")")}, milestones: [], issues: .}'
}

# _rank_next RAW WORKTYPES QUERY LIMIT → {project, degraded, importance, adjacency, overlap}.
# Importance = flat rank milestone→priority→blocked. Adjacency (only when QUERY non-empty) =
# term-overlap on title+labels. The two lists are NEVER merged into one score.
_rank_next() {
  local raw="$1" types_str="$2" query="$3" limit="$4" linked_json="${5:-[]}" types_json
  local inbox="${PROJECT_FETCH_INBOX_MILESTONE:-Inboxes}"
  types_json=$(printf '%s' "$types_str" | jq -R 'split(" ")')
  printf '%s' "$raw" | jq \
    --argjson types "$types_json" --arg query "$query" --argjson limit "$limit" --arg inbox "$inbox" \
    --argjson linked "$linked_json" '
    def relatedKeys:
      ( [ (.relations.nodes // [])[] | select(.type == "related") | .relatedIssue.identifier ]
      + [ (.inverseRelations.nodes // [])[] | select(.type == "related") | .issue.identifier ] ) | unique;
    def blocksKeys:    [ (.relations.nodes // [])[]        | select(.type == "blocks")    | .relatedIssue.identifier ] | unique;
    def blockedByKeys: [ (.inverseRelations.nodes // [])[] | select(.type == "blocks")    | .issue.identifier ]        | unique;
    def dupOf:       ( [ (.relations.nodes // [])[]        | select(.type == "duplicate") | .relatedIssue.identifier ] | first ) // null;
    def workTypeOf:
      ([ (.labels.nodes // [])[].name | ascii_downcase ]) as $ls
      | (first( $types[] | select( . as $t | any($ls[]; contains($t)) ) )) // "other";
    def isBlocked:
      ([ (.inverseRelations.nodes // [])[]
         | select(.type == "blocks" and ((.issue.state.type // "") as $st | ($st != "completed" and $st != "canceled"))) ]
       | length) > 0;
    def clean: { identifier, title, url, priority, estimate, state, milestone, workType, blocked, project,
                 relatedTo, parent, blocks, blockedBy, duplicateOf };
    ([ ($query | ascii_downcase | splits("[^a-z0-9-]+")) ]
      | map(select(length >= 4 or test("^[a-z]+-[0-9]+$"))) | unique) as $terms
    | ((.milestones | length) == 0) as $degraded
    | [ .issues[]
        | select((.projectMilestone.name // "") != $inbox)
        | {
            identifier, title, url,
            priority: (.priority // 0),
            estimate: (.estimate // null),
            state: (.state.name // null),
            milestone: (.projectMilestone.name // null),
            project: (.project.name // null),
            workType: workTypeOf,
            blocked: isBlocked,
            relatedTo: relatedKeys,
            parent: (.parent.identifier // null),
            blocks: blocksKeys,
            blockedBy: blockedByKeys,
            duplicateOf: dupOf,
            _ms: (.projectMilestone.sortOrder // 1000000),
            _pr: (if (.priority // 0) == 0 then 99 else .priority end),
            _bl: (if isBlocked then 1 else 0 end),
            _adj: ( ($terms | length) as $n
                    | if $n == 0 then 0
                      else (((.title // "") + " " + ([ (.labels.nodes // [])[].name ] | join(" "))) | ascii_downcase) as $hay
                        | ([ $terms[] as $t | select($hay | contains($t)) ] | length) / $n end )
          }
      ] as $rows
    | ($rows | sort_by([._ms, ._pr, ._bl, .identifier])) as $imp
    | ( if ($terms | length) == 0 then []
        else [ $rows[] | select(._adj > 0) ] | sort_by([(- ._adj), .identifier]) end ) as $adj
    | ($imp[0:$limit] | map(.identifier)) as $impTop
    | ($adj[0:$limit] | map(.identifier)) as $adjTop
    | ([ $linked[] | .identifier ] | unique) as $linkedKeys
    | ($adjTop + $linkedKeys | unique) as $relatedTop
    | {
        project: .project,
        degraded: $degraded,
        importance: [ $imp[0:$limit][] | clean ],
        adjacency:  [ $adj[0:$limit][] | clean ],
        linked: $linked,
        overlap: [ $impTop[] | select(. as $x | ($relatedTop | index($x)) != null) ]
      }
  '
}

# _format_next ENVELOPE MODE → stdout. json → the envelope; else grouped human view.
_format_next() {
  local env="$1" mode="$2"
  if [ "$mode" = "json" ]; then printf '%s\n' "$env" | jq '.'; return 0; fi
  printf '%s' "$env" | jq -r '
    def prLabel($p): (["None","Urgent","High","Medium","Low"][$p]) // "None";
    . as $env
    | ([ $env.importance[].workType ] | reduce .[] as $w ([]; if any(.[]; . == $w) then . else . + [$w] end)) as $order
    | "Project: \($env.project.name)\(if $env.degraded then "  · degraded (no milestones — priority-ranked)" else "" end)",
      "",
      "Importance — what'"'"'s next here:",
      ( if ($env.importance | length) == 0 then "  (no open work)" else empty end ),
      ( $order[] as $w
        | "  \($w):",
          ( $env.importance[] | select(.workType == $w)
            | "    [\(.identifier)] \(.title) · \(prLabel(.priority)) · \(.milestone // "no milestone")\(if .blocked then " · blocked" else "" end)" ) ),
      ( if ($env.adjacency | length) > 0 then
          ( "", "Adjacency — topical to your query (★ = also high-importance):",
            ( $env.adjacency[] | . as $a
              | "    [\($a.identifier)] \($a.title)\(if (($env.overlap // []) | index($a.identifier)) != null then " ★" else "" end)" ) )
        else empty end ),
      ( if ($env.linked | length) > 0 then
          ( "", "Linked (via relations — ★ = also high-importance):",
            ( $env.linked[] | . as $l
              | "    [\($l.identifier)] \($l.title // "?") · \($l.relation)"
                + (if ($l.project // null) != null and ($l.project != $env.project.name) then " · \($l.project)" else "" end)
                + (if (($env.overlap // []) | index($l.identifier)) != null then " ★" else "" end) ) )
        else empty end )
  '
}

cmd_next() {
  local input="" query="" all=0 limit=10 mode="human" team="" tickets=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --query) query="${2:-}"; shift 2 ;;
      --query=*) query="${1#*=}"; shift ;;
      --tickets) tickets="${2:-}"; shift 2 ;;
      --tickets=*) tickets="${1#*=}"; shift ;;
      --all) all=1; shift ;;
      --team) team="${2:-}"; shift 2 ;;
      --team=*) team="${1#*=}"; shift ;;
      --limit) limit="${2:-}"; shift 2 ;;
      --limit=*) limit="${1#*=}"; shift ;;
      --json) mode="json"; shift ;;
      -h|--help) usage; return 0 ;;
      -*) echo "project: unknown flag '$1'" >&2; return 1 ;;
      *) input="$1"; shift ;;
    esac
  done
  if ! printf '%s' "$limit" | grep -qE '^[1-9][0-9]*$'; then
    echo "project: next --limit must be a positive integer" >&2; return 1
  fi

  local raw
  if [ "$all" = "1" ]; then
    if [ -z "$team" ]; then
      local branch
      branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | grep -oiE '^[a-z]+' | head -1)
      team=$(printf '%s' "$branch" | tr '[:lower:]' '[:upper:]')
    fi
    [ -n "$team" ] || { echo "project: next --all needs a --team KEY (none given, none inferable)" >&2; return 1; }
    raw=$(_fetch_next_team "$team") || return 1
  else
    if [ -z "$input" ]; then
      input=$(_infer_project_from_branch) || {
        echo "project: next requires a <project> (none given, and no branch ticket key to infer one from)" >&2; return 1; }
    fi
    local pid
    pid=$(_resolve_project_id "$input") || return 1
    raw=$(_fetch_next "$pid") || return 1
  fi

  # Relation-anchored linked cluster (--tickets): one issue(id) read per anchor key.
  local linked="[]"
  if [ -n "$tickets" ]; then
    linked=$(_fetch_anchor "$tickets") || return 1
  fi

  local envelope
  envelope=$(_rank_next "$raw" "$_PROJECT_NEXT_WORKTYPES" "$query" "$limit" "$linked") || { echo "project: ranking failed" >&2; return 1; }
  _format_next "$envelope" "$mode"
}

# ---- Lint reads: the three live containers ----
#
# Data access only — the reads `engine project lint` needs, with no lint logic attached.
# Reuses the shared `_graphql` seam but NOT cmd_fetch's query (¶INV: reuse the seam, not the
# query): linting needs three markdown bodies, not a full delta with comment trees.
#
# The Linear field-naming trap, stated once so nobody re-derives it: `Project.description` is a
# ONE-LINE summary (~130-200 chars). The markdown body carrying the `##` sections and the 📘
# pointer is `Project.content`. Both are carried below — `summary` and `text` respectively —
# because a caller reaching for "the description" wants `text`.
#
# All three containers are normalized to the same record shape — {container, target, text, …} —
# so a caller can walk one list. Targets that could not be read land in `unreachable` rather than
# being silently absent: a container missing from the list must never read as a clean container.

_q_lint_project() {
  cat <<'GQL'
query($projectId: String!) {
  project(id: $projectId) {
    id name url slugId
    description
    content
  }
}
GQL
}

# The engine's first `documents(` query. Kept here, in one home, per the plan.
_q_lint_documents() {
  cat <<'GQL'
query($projectId: ID!, $after: String) {
  documents(filter: { project: { id: { eq: $projectId } } }, first: 50, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes { id title slugId url updatedAt content }
  }
}
GQL
}

# Channels as a FLAT top-level issues connection rather than cmd_fetch's connection nested under
# project — flat keeps a large `first:` cheap (¶PTF_NESTED_GRAPHQL_FIRST_MULTIPLIES_COMPLEXITY)
# and, unlike the nested one, it can be paginated without re-reading the project on every page.
_q_lint_channels() {
  cat <<'GQL'
query($projectId: ID!, $inbox: String!, $after: String) {
  issues(first: 100, after: $after, filter: { project: { id: { eq: $projectId } }, projectMilestone: { name: { eq: $inbox } } }) {
    pageInfo { hasNextPage endCursor }
    nodes { id identifier title url description }
  }
}
GQL
}

# _fetch_lint_project PID → {id, name, url, slugId, summary, text}. `text` is Project.content.
_fetch_lint_project() {
  local pid="$1" resp node
  resp=$(_graphql "$(_q_lint_project)" "$(jq -n --arg p "$pid" '{projectId: $p}')") || return 1
  node=$(printf '%s' "$resp" | jq '.data.project // null')
  if [ "$node" = "null" ]; then echo "project: project not found: $pid" >&2; return 1; fi
  printf '%s' "$node" | jq '{id, name, url, slugId, summary: (.description // ""), text: (.content // "")}'
}

# _fetch_lint_documents PID → array of {id, title, slugId, url, updatedAt, text} (paginated).
_fetch_lint_documents() {
  local pid="$1" after="null" acc="[]" resp conn has end prev_cursor=""
  while :; do
    resp=$(_graphql "$(_q_lint_documents)" "$(jq -n --arg p "$pid" --argjson a "$after" '{projectId: $p, after: $a}')") || return 1
    conn=$(printf '%s' "$resp" | jq '.data.documents // null')
    if [ "$conn" = "null" ]; then echo "project: documents query returned no connection for $pid" >&2; return 1; fi
    acc=$(printf '%s' "$acc" | jq --argjson n "$(printf '%s' "$conn" | jq '[.nodes[]? | {id, title, slugId, url, updatedAt, text: (.content // "")}]')" '. + $n')
    has=$(printf '%s' "$conn" | jq -r '.pageInfo.hasNextPage')
    [ "$has" = "true" ] || break
    end=$(printf '%s' "$conn" | jq -r '.pageInfo.endCursor')
    if [ -z "$end" ] || [ "$end" = "null" ] || [ "$end" = "$prev_cursor" ]; then
      echo "project: document pagination cursor did not advance — aborting to avoid an infinite loop" >&2; return 1
    fi
    prev_cursor="$end"; after=$(jq -n --arg c "$end" '$c')
  done
  printf '%s' "$acc"
}

# _fetch_lint_channels PID INBOX → array of {id, identifier, title, url, text} (paginated).
# `text` is Issue.description — the channel ticket's markdown body.
_fetch_lint_channels() {
  local pid="$1" inbox="${2:-Inboxes}" after="null" acc="[]" resp conn has end prev_cursor=""
  while :; do
    resp=$(_graphql "$(_q_lint_channels)" \
      "$(jq -n --arg p "$pid" --arg ib "$inbox" --argjson a "$after" '{projectId: $p, inbox: $ib, after: $a}')") || return 1
    conn=$(printf '%s' "$resp" | jq '.data.issues // null')
    if [ "$conn" = "null" ]; then echo "project: channel query returned no connection for $pid" >&2; return 1; fi
    acc=$(printf '%s' "$acc" | jq --argjson n "$(printf '%s' "$conn" | jq '[.nodes[]? | {id, identifier, title, url, text: (.description // "")}]')" '. + $n')
    has=$(printf '%s' "$conn" | jq -r '.pageInfo.hasNextPage')
    [ "$has" = "true" ] || break
    end=$(printf '%s' "$conn" | jq -r '.pageInfo.endCursor')
    if [ -z "$end" ] || [ "$end" = "null" ] || [ "$end" = "$prev_cursor" ]; then
      echo "project: channel pagination cursor did not advance — aborting to avoid an infinite loop" >&2; return 1
    fi
    prev_cursor="$end"; after=$(jq -n --arg c "$end" '$c')
  done
  printf '%s' "$acc"
}

# _fetch_lint_containers PID HANDBOOK_SLUG [INBOX] → the read envelope:
#   { project: {...}, containers: [ {container, target, text, source, ...} ], unreachable: [...] }
#
# The handbook is matched on slugId, never on words in the URL: retitling a Linear document
# re-slugs the human-readable segment while the 12-hex slugId stays put.
#
# Issues exactly three GraphQL calls, in this order: project → documents → channels. Fixture
# lists (LINEAR_FIXTURE) must be ordered to match; a name-resolved <project> adds one call ahead.
_fetch_lint_containers() {
  local pid="$1" slug="${2:-}" inbox="${3:-Inboxes}"
  local proj docs channels
  proj=$(_fetch_lint_project "$pid") || return 1
  docs=$(_fetch_lint_documents "$pid") || return 1
  channels=$(_fetch_lint_channels "$pid" "$inbox") || return 1
  jq -n --argjson p "$proj" --argjson d "$docs" --argjson c "$channels" --arg slug "$slug" --arg inbox "$inbox" '
    ( if $slug == "" then null else ([ $d[] | select(.slugId == $slug) ] | first) end ) as $hb
    | {
        project: { id: $p.id, name: $p.name, url: $p.url, slugId: $p.slugId, summary: $p.summary },
        containers: (
          [ { container: "description", target: $p.name, text: $p.text, url: $p.url, source: "project.content" } ]
          + ( if $hb == null then []
              else [ { container: "handbook", target: $hb.title, text: $hb.text, url: $hb.url,
                       slugId: $hb.slugId, updatedAt: $hb.updatedAt, source: "document.content" } ] end )
          + [ $c[] | { container: "channel", target: .identifier, title: .title, text: .text,
                       url: .url, source: "issue.description" } ] ),
        unreachable: (
          ( if $slug == "" then
              [ { container: "handbook", target: "(no handbookSlug given)",
                  reason: "no handbookSlug supplied for this project" } ]
            elif $hb == null then
              [ { container: "handbook", target: ("slugId " + $slug),
                  reason: ("no document with slugId " + $slug + " in project " + $p.name) } ]
            else [] end )
          + ( if ($c | length) == 0 then
                [ { container: "channel", target: ("milestone " + $inbox),
                    reason: "no channel tickets found under this milestone" } ]
              else [] end ) )
      }'
}

# ---- Lint: container conformance against the section schema ----
#
# `engine project lint` checks the three live container tiers read above against the machine-readable
# section schema, using the pure logic in lint-lib.sh. Read-only toward Linear in every mode.
#
# Exit contract — 0 clean-or-warnings · 1 failures · 2 could-not-run OR partial coverage.
# 2 outranking 1 is the point: an incomplete run must never read as a bill of health, and a target
# that could not be fetched is recorded in `unreachable`, never dropped from the checked list.

_lint_schema_path() { printf '%s' "${PROJECT_LINT_SCHEMA:-$HOME/.claude/engine/skills/intake/assets/project-schema.json}"; }
_lint_registry_path() { printf '%s' "${PROJECT_LINT_REGISTRY:-$HOME/.claude/engine/skills/inbox-post/assets/INBOX_REGISTRY.md}"; }

# _lint_peers_from_list SCHEMA CONTAINER  (one `label:file` spec per line on stdin)
# Rebuilds varargs through the positional params — bash 3.2 has no safe empty named array
# (¶PTF_BASH32_COMPATIBILITY), and a single peer is not a comparison.
_lint_peers_from_list() {
  local schema="$1" container="$2" line
  set --
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    set -- "$@" "$line"
  done
  if [ $# -lt 2 ]; then printf '[]'; return 0; fi
  lint_peers "$schema" "$container" "$@"
}

# _lint_scope_registry_drift SCHEMA REGISTRY -> findings JSON array
#
# `schema.scope` is the RULE (which projects this command is responsible for); INBOX_REGISTRY.md is
# a navigation CACHE for /inbox-post. They are deliberately NOT merged — one is a contract, one is
# data that self-heals from Linear. But two hand-maintained copies of the same five names is the
# exact duplication class this whole command exists to catch, so silence would be hypocritical:
# they are compared, and disagreement is a warn. Offline.
#
# A missing registry is COULD-NOT-RUN, not clean: returning `[]` for a check that never executed
# is the exact lie the exit contract exists to refuse. The caller records it in `unreachable`.
_lint_scope_registry_drift() {
  local schema="$1" registry="$2" names
  [ -f "$registry" ] || {
    printf '[]'
    echo "registry not found at $registry — the scope <-> registry drift check could not run" >&2
    return 1; }
  names=$(grep -E '^## Product: ' "$registry" 2>/dev/null | sed 's/^## //' | jq -Rn '[inputs] | map(sub("\\s+$"; ""))')
  [ -n "$names" ] || names='[]'
  jq -Rs --slurpfile _s "$schema" --argjson names "$names" --arg reg "$(basename "$registry")" '
    . as $text
    | ($_s[0].scope.projects // []) as $P
    | [ $P[] | . as $p | select($names | index($p.name) | not)
        | { container: "scope", target: $p.name, severity: "warn", rule: "scope-registry-drift",
            id: null, heading: null, belongsIn: null,
            message: ("schema.scope names `" + $p.name + "` but " + $reg + " has no `## " + $p.name
                      + "` section — the lint scope and the navigation cache disagree.") } ]
    + [ $names[] | . as $n | select([ $P[].name ] | index($n) | not)
        | { container: "scope", target: $n, severity: "warn", rule: "scope-registry-drift",
            id: null, heading: null, belongsIn: null,
            message: ($reg + " lists `" + $n + "` but schema.scope does not — `--all` would skip it entirely.") } ]
    + [ $P[] | . as $p | select($text | contains($p.handbookSlug) | not)
        | { container: "scope", target: $p.name, severity: "warn", rule: "scope-registry-drift",
            id: null, heading: null, belongsIn: null,
            message: ("schema.scope pins handbookSlug `" + $p.handbookSlug + "` which " + $reg
                      + " never mentions — one of the two is pointing at the wrong document.") } ]
  ' < "$registry"
}

# _lint_render ENVELOPE MODE -> the human or JSON report on stdout.
_lint_render() {
  local env="$1" mode="$2"
  if [ "$mode" = "json" ]; then printf '%s\n' "$env" | jq '.'; return 0; fi
  printf '%s' "$env" | jq -r '
    def sev: if .severity == "fail" then "FAIL" else "WARN" end;
    . as $e
    | "Container lint — \($e.scope)",
      "Schema: \($e.schema)\(if $e.strict then "  (strict)" else "" end)",
      "",
      ( if ($e.findings | length) == 0 then "No findings."
        else ( $e.findings[]
               | "\(. | sev)  \(.container) · \(.target)", "      \(.message)", "" ) end ),
      ( if ($e.unreachable | length) > 0 then
          ( "Could not check (\($e.unreachable | length)):",
            ( $e.unreachable[] | "      \(.container) · \(.target) — \(.reason)" ),
            "" )
        else empty end ),
      ( if $e.peerCompared then "Peer comparison: ran across \($e.peerCount) peers"
        else "Peer comparison: SKIPPED — \($e.peerSkipped)" end ),
      "Checked \($e.checked | length) container(s) · "
        + "\([$e.findings[] | select(.severity == "fail")] | length) fail · "
        + "\([$e.findings[] | select(.severity == "warn")] | length) warn · "
        + "\($e.unreachable | length) unreachable"
  '
}

# cmd_lint — see usage(). Accumulates into these four, all JSON strings or newline lists, never
# bash arrays (¶PTF_BASH32_COMPATIBILITY: the happy path is an empty list, which is where it bites).
cmd_lint() {
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/lint-lib.sh"

  local schema="" mode="human" strict="" is_strict=false do_all=false use_stdin=false
  local container="" target="" project="" inbox="${PROJECT_FETCH_INBOX_MILESTONE:-Inboxes}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --all)          do_all=true; shift ;;
      --stdin)        use_stdin=true; shift ;;
      --container)    container="${2:-}"; shift 2 ;;
      --container=*)  container="${1#*=}"; shift ;;
      --target)       target="${2:-}"; shift 2 ;;
      --target=*)     target="${1#*=}"; shift ;;
      --schema)       schema="${2:-}"; shift 2 ;;
      --schema=*)     schema="${1#*=}"; shift ;;
      --inbox)        inbox="${2:-}"; shift 2 ;;
      --inbox=*)      inbox="${1#*=}"; shift ;;
      --json)         mode="json"; shift ;;
      --strict)       strict="--strict"; is_strict=true; shift ;;
      -h|--help)      usage; return 0 ;;
      -*)             echo "project lint: unknown option '$1'" >&2; return 2 ;;
      *)
        if [ -n "$project" ]; then echo "project lint: unexpected argument '$1'" >&2; return 2; fi
        project="$1"; shift ;;
    esac
  done

  [ -n "$schema" ] || schema="$(_lint_schema_path)"
  if [ ! -f "$schema" ]; then echo "project lint: no such schema: $schema" >&2; return 2; fi

  # Mode selection. A bad invocation is could-not-run (2), never a clean 0.
  if [ "$use_stdin" = true ] && [ "$do_all" = true ]; then
    echo "project lint: --stdin and --all are different jobs; pick one" >&2; return 2
  fi
  if [ "$use_stdin" = true ] && [ -z "$container" ]; then
    echo "project lint: --stdin requires --container <$(jq -r '.containers|keys|join("|")' "$schema")>" >&2; return 2
  fi
  if [ "$use_stdin" = false ] && [ "$do_all" = false ] && [ -z "$project" ]; then
    echo "project lint: name a project, or pass --all, or pipe text with --stdin --container <c>" >&2; return 2
  fi
  if [ "$use_stdin" = true ] && [ -n "$project" ]; then
    echo "project lint: --stdin reads text the caller already holds; drop the <project> argument" >&2; return 2
  fi

  local tmp; tmp=$(mktemp -d) || return 2

  local findings="[]" unreachable="[]" checked="[]"
  local peer_compared=false peer_skipped="" peer_count=0
  local scope_label="" out rc n i c t txtfile reason pid env

  if [ "$use_stdin" = true ]; then
    # --stdin has NO peers. Reporting a clean peer comparison for one that never ran would be a lie
    # about the only mode the wave's pre-write gate uses.
    peer_skipped="--stdin lints text the caller holds; there are no peers to compare it against"
    [ -n "$target" ] || target="(stdin)"
    scope_label="$target ($container, from stdin)"
    cat > "$tmp/stdin.md"
    out=$(lint_container "$schema" "$container" "$tmp/stdin.md" $strict --target "$target" 2>"$tmp/err"); rc=$?
    if [ "$rc" != "0" ] || ! lint_is_findings "$out"; then
      reason=$(cat "$tmp/err"); [ -n "$reason" ] || reason="lint failed"
      unreachable=$(printf '%s' "$unreachable" | jq --arg c "$container" --arg t "$target" --arg r "$reason" \
        '. + [{container: $c, target: $t, reason: $r}]')
    else
      findings=$(printf '%s' "$findings" | jq --argjson f "$out" '. + $f')
      checked=$(printf '%s' "$checked" | jq --arg c "$container" --arg t "$target" '. + [{container: $c, target: $t}]')
    fi
  else
    # Live modes. --all derives its target list from the schema's own `scope` block rather than a
    # hardcoded one, which is the only thing that makes `scope` more than documentation.
    local targets
    if [ "$do_all" = true ]; then
      targets=$(jq -r '.scope.projects[]? | .name + "\t" + (.handbookSlug // "")' "$schema")
      if [ -z "$targets" ]; then echo "project lint: schema declares no scope.projects for --all" >&2; return 2; fi
      scope_label="all $(printf '%s\n' "$targets" | grep -c .) projects in schema.scope"
    else
      targets=$(jq -r --arg n "$project" '(.scope.projects[]? | select(.name == $n) | .name + "\t" + (.handbookSlug // ""))' "$schema")
      [ -n "$targets" ] || targets=$(printf '%s\t' "$project")
      scope_label="$project"
    fi

    local pname pslug idx=0
    while IFS=$'\t' read -r pname pslug; do
      [ -n "$pname" ] || continue
      idx=$((idx + 1))
      pid=$(_resolve_project_id "$pname" 2>"$tmp/err") || {
        reason=$(cat "$tmp/err"); [ -n "$reason" ] || reason="could not resolve project"
        unreachable=$(printf '%s' "$unreachable" | jq --arg t "$pname" --arg r "$reason" \
          '. + [{container: "project", target: $t, reason: $r}]')
        continue; }
      env=$(_fetch_lint_containers "$pid" "$pslug" "$inbox" 2>"$tmp/err") || {
        reason=$(cat "$tmp/err"); [ -n "$reason" ] || reason="could not read containers"
        unreachable=$(printf '%s' "$unreachable" | jq --arg t "$pname" --arg r "$reason" \
          '. + [{container: "project", target: $t, reason: $r}]')
        continue; }
      unreachable=$(printf '%s' "$unreachable" | jq --argjson u "$(printf '%s' "$env" | jq '.unreachable')" '. + $u')

      n=$(printf '%s' "$env" | jq '.containers | length')
      i=0
      while [ "$i" -lt "$n" ]; do
        c=$(printf '%s' "$env" | jq -r --argjson i "$i" '.containers[$i].container')
        t=$(printf '%s' "$env" | jq -r --argjson i "$i" '.containers[$i].target')
        # All five handbooks carry the SAME title, and a channel identifier does not name its
        # project — so every non-description target is qualified, or a --all report is unactionable.
        [ "$c" = "description" ] || t="$pname · $t"
        txtfile="$tmp/c-$idx-$i.md"
        printf '%s' "$env" | jq -r --argjson i "$i" '.containers[$i].text' > "$txtfile"
        out=$(lint_container "$schema" "$c" "$txtfile" $strict --target "$t" 2>"$tmp/err"); rc=$?
        if [ "$rc" != "0" ] || ! lint_is_findings "$out"; then
          reason=$(cat "$tmp/err"); [ -n "$reason" ] || reason="lint failed"
          unreachable=$(printf '%s' "$unreachable" | jq --arg c "$c" --arg t "$t" --arg r "$reason" \
            '. + [{container: $c, target: $t, reason: $r}]')
        else
          findings=$(printf '%s' "$findings" | jq --argjson f "$out" '. + $f')
          checked=$(printf '%s' "$checked" | jq --arg c "$c" --arg t "$t" '. + [{container: $c, target: $t}]')
          # Peer specs, one per line: `<label>:<path>`, split at the LAST colon by lint_peers.
          if [ "$do_all" = true ] && [ "$c" != "channel" ]; then
            printf '%s:%s\n' "$pname" "$txtfile" >> "$tmp/peers-$c.txt"
          fi
        fi
        i=$((i + 1))
      done
    done <<EOFTARGETS
$targets
EOFTARGETS

    if [ "$do_all" = true ]; then
      local pc peer_attempted=false
      for c in description handbook; do
        [ -f "$tmp/peers-$c.txt" ] || continue
        pc=$(grep -c . "$tmp/peers-$c.txt")
        [ "$pc" -ge 2 ] || continue
        peer_attempted=true
        # The peer axis has its own accumulation path, so it needs its own could-not-run
        # bookkeeping. Swallowing a failure into `[]` and setting peer_compared anyway renders
        # a comparison that DIED as "ran across N peers, nothing wrong" — the same lie --stdin
        # was built to refuse, in the only mode that actually has peers.
        out=$(_lint_peers_from_list "$schema" "$c" < "$tmp/peers-$c.txt" 2>"$tmp/perr"); rc=$?
        if [ "$rc" != "0" ] || ! lint_is_findings "$out"; then
          reason=$(cat "$tmp/perr"); [ -n "$reason" ] || reason="peer comparison failed"
          unreachable=$(printf '%s' "$unreachable" | jq --arg c "peer:$c" --arg t "$pc peers" --arg r "$reason" \
            '. + [{container: $c, target: $t, reason: $r}]')
        else
          findings=$(printf '%s' "$findings" | jq --argjson f "$out" '. + $f')
          peer_compared=true
          if [ "$pc" -gt "$peer_count" ]; then peer_count="$pc"; fi
        fi
      done
      if [ "$peer_compared" != true ]; then
        if [ "$peer_attempted" = true ]; then
          peer_skipped="every peer comparison failed — see the could-not-check list"
        else
          peer_skipped="fewer than two peers were readable"
        fi
      fi
      out=$(_lint_scope_registry_drift "$schema" "$(_lint_registry_path)" 2>"$tmp/serr"); rc=$?
      if [ "$rc" != "0" ] || ! lint_is_findings "$out"; then
        reason=$(cat "$tmp/serr"); [ -n "$reason" ] || reason="scope <-> registry drift check failed"
        unreachable=$(printf '%s' "$unreachable" | jq --arg t "$(_lint_registry_path)" --arg r "$reason" \
          '. + [{container: "scope", target: $t, reason: $r}]')
      else
        findings=$(printf '%s' "$findings" | jq --argjson f "$out" '. + $f')
      fi
    else
      peer_skipped="a single project has no peers — run --all for the cross-project comparison"
    fi
  fi

  local code; code=$(lint_exit_code "$findings" "$(printf '%s' "$unreachable" | jq 'length')")
  local envelope
  envelope=$(jq -n --arg scope "$scope_label" --arg schema "$schema" --argjson strict "$is_strict" \
    --argjson checked "$checked" --argjson findings "$findings" --argjson unreachable "$unreachable" \
    --argjson peerCompared "$peer_compared" --arg peerSkipped "$peer_skipped" \
    --argjson peerCount "$peer_count" --argjson exitCode "$code" '
    { scope: $scope, schema: $schema, strict: $strict, checked: $checked,
      peerCompared: $peerCompared, peerCount: $peerCount,
      peerSkipped: (if $peerCompared then null else $peerSkipped end),
      findings: $findings, unreachable: $unreachable, exitCode: $exitCode }')
  _lint_render "$envelope" "$mode"
  rm -rf "$tmp"
  return "$code"
}

# ---- Dispatch ----
case "${1:-}" in
  fetch)     shift; cmd_fetch "$@" ;;
  next)      shift; cmd_next "$@" ;;
  lint)      shift; cmd_lint "$@" ;;
  ""|-h|--help|help) usage ;;
  *) echo "project: unknown subcommand '$1'" >&2; usage; exit 1 ;;
esac
