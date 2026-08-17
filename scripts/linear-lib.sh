#!/bin/bash
# linear-lib.sh — shared Linear GraphQL seam + payload transform.
#
# Sourced by project.sh (`engine project fetch`) and ticket.sh (`engine ticket fetch`).
# The two commands differ ONLY in their query filter (a whole project vs. an id-set of
# tickets) and their envelope; the GraphQL seam, the fixture mechanism, the auth, and the
# per-issue jq transform are shared here so a field added for one is added for both
# (¶INV_SHARED_TRANSFORM_NO_DIVERGE).
#
# Fixture (tests): LINEAR_FIXTURE (canonical) or PROJECT_FETCH_FIXTURE (back-compat alias)
#   — a file or colon-separated file list that short-circuits _graphql. File-backed call
#   counter survives the command-substitution subshells; list exhaustion is a loud error.
# Auth (live): LINEAR_API_KEY from env, else the first PROJECT dotfile that has it —
#   ./.env.local → ./.env (the shared precedence in env-lib.sh; `.env` still works, and
#   a key present in both resolves to the `.env.local` one, announced once on stderr).
# Env: LINEAR_API_URL (default https://api.linear.app/graphql).

LINEAR_API_URL="${LINEAR_API_URL:-https://api.linear.app/graphql}"

# Resolved from the script's OWN directory: project.sh / ticket.sh run from any cwd, and
# the test suites SYMLINK this lib into a fake HOME — so the link chain is walked first,
# otherwise the sibling lookup lands in a directory that holds only the symlink.
_LINEAR_LIB_SRC="${BASH_SOURCE[0]:-$0}"
while [ -L "$_LINEAR_LIB_SRC" ]; do
  _LINEAR_LIB_DIR="$(cd -P "$(dirname "$_LINEAR_LIB_SRC")" && pwd)"
  _LINEAR_LIB_SRC="$(readlink "$_LINEAR_LIB_SRC")"
  case "$_LINEAR_LIB_SRC" in /*) ;; *) _LINEAR_LIB_SRC="$_LINEAR_LIB_DIR/$_LINEAR_LIB_SRC" ;; esac
done
_LINEAR_LIB_DIR="$(cd -P "$(dirname "$_LINEAR_LIB_SRC")" && pwd)"
if [ -f "$_LINEAR_LIB_DIR/env-lib.sh" ]; then
  # shellcheck source=/dev/null
  . "$_LINEAR_LIB_DIR/env-lib.sh"
else
  echo "linear-lib: missing required $_LINEAR_LIB_DIR/env-lib.sh" >&2
  return 1 2>/dev/null || exit 1
fi

# Canonical fixture var, with the original project-scoped name kept as a back-compat alias
# so the existing project.sh test corpus (which sets PROJECT_FETCH_FIXTURE) keeps working.
: "${LINEAR_FIXTURE:=${PROJECT_FETCH_FIXTURE:-}}"

# Fixture mode (tests): a per-invocation file-backed call counter shared across subshells.
# Command-substitution subshells reset EXIT traps, so this trap fires only when the top-level
# shell exits — cleaning up the temp counter without a subshell deleting it mid-run.
if [ -n "${LINEAR_FIXTURE:-}" ]; then
  _FIX_COUNTER="${_FIX_COUNTER:-$(mktemp -t linearfix.XXXXXX)}"
  export _FIX_COUNTER
  [ -s "$_FIX_COUNTER" ] || echo 0 > "$_FIX_COUNTER"
  trap 'rm -f "$_FIX_COUNTER" 2>/dev/null' EXIT
fi

# _load_key — resolve LINEAR_API_KEY from a dotfile if unset (live path only), through
# the shared env-lib precedence. Unlike the old inline grep, the value is whitespace-
# trimmed and one layer of surrounding quotes is stripped, so a quoted key works.
_load_key() {
  if [ -z "${LINEAR_API_KEY:-}" ]; then
    local val
    if val="$(resolve_env_key LINEAR_API_KEY)"; then
      LINEAR_API_KEY="$val"
      export LINEAR_API_KEY
    fi
  fi
  : "${LINEAR_API_KEY:?LINEAR_API_KEY is required — set it in your environment or .env.local/.env}"
}

# _next_fixture — pop the next fixture path from the colon-separated LINEAR_FIXTURE list.
# The call counter is FILE-backed (not a shell var) so it survives the command-substitution
# subshells that wrap the callers — otherwise a subshell's increment is lost and the next
# call re-serves fixture #1. Exhaustion is an ERROR (an unexpected extra GraphQL call must
# surface loudly in tests), not repeat-the-last.
_next_fixture() {
  local n pick
  n=$(( $(cat "$_FIX_COUNTER" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$_FIX_COUNTER"
  pick=$(printf '%s' "$LINEAR_FIXTURE" | awk -F: -v n="$n" '{ if (n<=NF) print $n; else exit 1 }')
  if [ -z "$pick" ]; then
    echo "linear: fixture list exhausted at call $n — unexpected extra GraphQL call" >&2
    return 1
  fi
  printf '%s' "$pick"
}

# _graphql QUERY VARS_JSON → raw response JSON on stdout, or return 1 on any failure.
# Fixture-backed when LINEAR_FIXTURE is set; else a live curl POST. GraphQL-level errors
# (Linear returns HTTP 200 + errors[]) are treated as FAILURE for BOTH paths.
_graphql() {
  local query="$1" vars="${2:-null}" resp
  if [ -n "${LINEAR_FIXTURE:-}" ]; then
    local fx
    fx="$(_next_fixture)"
    if [ ! -f "$fx" ]; then echo "linear: fixture not found: $fx" >&2; return 1; fi
    resp="$(cat "$fx")"
  else
    _load_key || return 1
    local body
    body=$(jq -n --arg q "$query" --argjson v "$vars" '{query: $q, variables: $v}')
    resp=$(curl -s --connect-timeout 15 --max-time 300 -X POST "$LINEAR_API_URL" \
      -H "Authorization: $LINEAR_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$body") || { echo "linear: network error/timeout calling Linear" >&2; return 1; }
  fi
  if printf '%s' "$resp" | jq -e '(.errors // []) | length > 0' >/dev/null 2>&1; then
    echo "linear: GraphQL error: $(printf '%s' "$resp" | jq -c '.errors' 2>/dev/null)" >&2
    return 1
  fi
  if ! printf '%s' "$resp" | jq -e . >/dev/null 2>&1; then
    echo "linear: invalid JSON response from Linear" >&2
    return 1
  fi
  printf '%s' "$resp"
}

# ---- Per-issue child-pagination (shared) ----
#
# When an issue's inline comment/history/attachment page (kept small in the list query to stay
# under Linear's query-complexity cap) is truncated, its remaining rows are paginated here with
# flat single-issue follow-up queries. Both `project fetch` and `ticket fetch` run their fetched
# issues array through _paginate_issue_children so a firehose thread is never silently truncated.

# ---- Comment field selection (single source) ----
#
# Three queries need the same comment selection: this file's per-issue pagination, project.sh's
# project-scoped list, and ticket.sh's id-set list. All three emit GraphQL from QUOTED heredocs so
# that GraphQL's own $variables survive unexpanded — which is exactly why the shared text is
# injected by token substitution instead of shell interpolation. An unsubstituted token fails loudly
# at the API rather than silently dropping fields.
LINEAR_COMMENT_FIELDS='id body createdAt resolvedAt resolvingUser { name } quotedText parent { id } user { name } botActor { name } reactions { emoji createdAt user { name } externalUser { name } }'

_sub_comment_fields() {
  sed "s|@COMMENT_FIELDS@|${LINEAR_COMMENT_FIELDS}|g"
}

_q_comments() {
  cat <<'GQL' | _sub_comment_fields
query($issueId: String!, $after: String) {
  issue(id: $issueId) {
    comments(first: 250, after: $after) {
      pageInfo { hasNextPage endCursor }
      nodes { @COMMENT_FIELDS@ }
    }
  }
}
GQL
}

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

# _paginate_issue_children ISSUES_JSON → ISSUES_JSON with every truncated comment/history/attachment
# connection fully drained and appended. Read on stdin? No — takes the array as $1, prints the result.
_paginate_issue_children() {
  local all="$1" trunc iid more
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
  printf '%s' "$all"
}

# ---- Shared jq transform defs ----
#
# Injected as a prefix into BOTH project.sh's `_assemble` and ticket.sh's fetch transform,
# so the comment-tree / lifecycle / attachment shaping can never diverge between the two
# commands (¶INV_SHARED_TRANSFORM_NO_DIVERGE). The main filter that follows supplies $sn
# (the normalized since-cutoff) and calls `issueToTicket($sn)` per issue.
#
# `issueToTicket` produces the COMMON per-ticket shape; each caller adds its own envelope
# (project.sh: isChannel + _commentCount for its summary; ticket.sh: nothing).
LINEAR_JQ_DEFS='
  def author: (.user.name // .botActor.name // "(bot)");
  # Comment reactions → [{emoji, at, by}]; actor falls back user → externalUser (bot/integration
  # reactions like the 👀 Codex gate arrive via externalUser, mirroring the botActor author path).
  def reactionsOf: [ (.reactions // [])[] | { emoji, at: .createdAt, by: (.user.name // .externalUser.name // "(unknown)") } ];
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
      | { id, author: author, createdAt, body, quotedText: (.quotedText // null),
          resolvedAt: (.resolvedAt // null), resolvedBy: (.resolvingUser.name // null),
          reactions: reactionsOf, orphanReply: false, children: kids(.id) } ];
    [ $cs[]
      | select((.parent.id // null) as $p | ($p == null) or (($ids | index($p)) == null))
      | { id, author: author, createdAt, body, quotedText: (.quotedText // null),
          resolvedAt: (.resolvedAt // null), resolvedBy: (.resolvingUser.name // null),
          reactions: reactionsOf,
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
  # One raw issue node + the normalized since-cutoff $sn → the common per-ticket object.
  # Comments/history are since-filtered; attachments are carried whole (URLs, cheap).
  def issueToTicket($sn):
    ( [ (.comments.nodes // [])[] | select((.createdAt | normTs) > $sn) ] ) as $cs
    | ( $cs | map(.id) ) as $ids
    | ( [ (.history.nodes // [])[] | select((.createdAt | normTs) > $sn) | lifeEvents[] ] ) as $life
    | ( [ (.attachments.nodes // [])[] | { id, title, url } ] ) as $att
    | ( buildTree($cs; $ids) ) as $tree
    | {
        id, identifier, title, url,
        state: (.state.name // null),
        priority,
        milestone: (.projectMilestone.name // null),
        createdAt, updatedAt,
        isNew: ((.createdAt | normTs) > $sn),
        comments: $tree,
        lifecycle: $life,
        attachments: $att
      };
'
