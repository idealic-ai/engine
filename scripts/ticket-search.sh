#!/bin/bash
# ticket-search.sh — engine ticket search: rank Linear tickets related to a free-text query
#
# `engine ticket-search "<free text / taskSummary>" [--team <KEY>] [--include-closed]
#  [--limit <N>] [--json]` queries Linear's GraphQL API for tickets related to the text and
# prints ranked excerpts — one line per hit plus an indented description snippet. Read-only
# toward Linear. STATELESS: a search has no watermark (unlike project.sh's delta waterline).
#
# Startup use: session.sh feeds `taskSummary` verbatim; the block drops under
# `## SRC_RELATED_TICKETS`. Done/closed tickets are kept by default — a done match is an
# "already built" signal for duplicate detection.
#
# Search field: `searchIssues(term:, includeArchived:)` — CONFIRMED live against Finch's Linear
# (returns real ranked nodes with state{name,type}). We do NOT rely on the API's own ordering:
# `_rank` re-sorts by local term-overlap (see there). If Linear ever renames the field, ONLY
# `_q_search` and `_rank` need to change — everything else is field-shape tolerant (missing
# description/state handled).
#
# Usage:
#   engine ticket-search "<free text>" [--team <KEY>] [--include-closed] [--limit <N>] [--json]
#
#   <free text> : raw query / taskSummary. Reduced internally to salient search terms
#                 (see _reduce_terms — lexical search degrades on a whole paragraph).
#   --team <KEY>       : scope to a team by identifier prefix (e.g. FIN → keep FIN-* only).
#   --include-closed   : surface completed/canceled tickets (DEFAULT ON — a done match =
#                        "already built"). Negate with --no-include-closed (alias --open-only),
#                        which drops them via a state.type post-filter. NOTE: "closed" is a
#                        workflow STATE, distinct from Linear's separate archived/trashed axis.
#   --limit <N>        : max hits (default 10).
#   --json             : emit structured rows [{identifier,title,url,state,stateType,project,score,snippet}].
#
# Auth (live path only): LINEAR_API_KEY from env, else ./.env.local then ./.env (env-lib.sh).
# Env: TICKET_SEARCH_FIXTURE (test-only) — file or colon-separated file list; short-circuits _graphql.
#      TICKET_SEARCH_DEBUG (test-only) — echo the reduced term string to stderr.
#      LINEAR_API_URL (default https://api.linear.app/graphql).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib.sh"

# env-lib.sh owns the ONE dotfile-precedence rule, shared with linear-lib.sh — otherwise
# `engine ticket-search` and `engine project fetch` answer the same key differently in the
# same directory. Resolved from this script's OWN dir, walking the link chain first: the
# test suite symlinks this script into a fake HOME that holds no sibling libs.
_TS_SRC="${BASH_SOURCE[0]:-$0}"
while [ -L "$_TS_SRC" ]; do
  _TS_DIR="$(cd -P "$(dirname "$_TS_SRC")" && pwd)"
  _TS_SRC="$(readlink "$_TS_SRC")"
  case "$_TS_SRC" in /*) ;; *) _TS_SRC="$_TS_DIR/$_TS_SRC" ;; esac
done
_TS_DIR="$(cd -P "$(dirname "$_TS_SRC")" && pwd)"
if [ -f "$_TS_DIR/env-lib.sh" ]; then
  # shellcheck source=/dev/null
  . "$_TS_DIR/env-lib.sh"
else
  echo "ticket-search: missing required $_TS_DIR/env-lib.sh" >&2; exit 1
fi

LINEAR_API_URL="${LINEAR_API_URL:-https://api.linear.app/graphql}"
DEFAULT_LIMIT=10

# Fixture mode (tests): a per-invocation file-backed call counter shared across subshells,
# mirroring project.sh. Command-substitution subshells reset EXIT traps, so this trap fires
# only when the top-level shell exits — cleaning up the temp counter without a subshell
# deleting it mid-run.
if [ -n "${TICKET_SEARCH_FIXTURE:-}" ]; then
  _FIX_COUNTER="${_FIX_COUNTER:-$(mktemp -t ticketsearch.XXXXXX)}"
  export _FIX_COUNTER
  [ -s "$_FIX_COUNTER" ] || echo 0 > "$_FIX_COUNTER"
  trap 'rm -f "$_FIX_COUNTER" 2>/dev/null' EXIT
fi

usage() {
  # Print the header's "# Usage:" block through to the first non-comment line.
  awk '/^# Usage:/{p=1} p{ if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
}

# ---- GraphQL seam (the single injectable HTTP call) ----

# _load_key — resolve LINEAR_API_KEY from a project dotfile if unset (live path only)
# through the SHARED env-lib precedence, identical to linear-lib.sh's copy: one key, one
# answer, whichever command asks. Values are trimmed and one quote layer is stripped.
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

# _next_fixture — pop the next fixture path from the colon-separated TICKET_SEARCH_FIXTURE list.
# The call counter is FILE-backed (not a shell var) so it survives command-substitution
# subshells. Exhaustion is an ERROR — an unexpected extra GraphQL call surfaces loudly in
# tests rather than being fed a stale (valid-looking) response.
_next_fixture() {
  local n pick
  n=$(( $(cat "$_FIX_COUNTER" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$_FIX_COUNTER"
  pick=$(printf '%s' "$TICKET_SEARCH_FIXTURE" | awk -F: -v n="$n" '{ if (n<=NF) print $n; else exit 1 }')
  if [ -z "$pick" ]; then
    echo "ticket-search: fixture list exhausted at call $n — unexpected extra GraphQL call" >&2
    return 1
  fi
  printf '%s' "$pick"
}

# _graphql QUERY VARS_JSON → raw response JSON on stdout, or return 1 on any failure.
# Fixture-backed when TICKET_SEARCH_FIXTURE is set; else a live curl POST (hard --max-time so a
# slow Linear never stalls startup). GraphQL-level errors (Linear returns HTTP 200 + errors[])
# are treated as FAILURE for BOTH paths. Fails CLOSED at the CLI level; session.sh swallows
# the non-zero exit into `(none)` separately.
_graphql() {
  local query="$1" vars="${2:-null}" resp
  if [ -n "${TICKET_SEARCH_FIXTURE:-}" ]; then
    local fx
    fx="$(_next_fixture)" || return 1
    if [ ! -f "$fx" ]; then echo "ticket-search: fixture not found: $fx" >&2; return 1; fi
    resp="$(cat "$fx")"
  else
    _load_key || return 1
    local body
    body=$(jq -n --arg q "$query" --argjson v "$vars" '{query: $q, variables: $v}')
    resp=$(curl -s --max-time 8 -X POST "$LINEAR_API_URL" \
      -H "Authorization: $LINEAR_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$body") || { echo "ticket-search: network error calling Linear" >&2; return 1; }
  fi
  if printf '%s' "$resp" | jq -e '(.errors // []) | length > 0' >/dev/null 2>&1; then
    echo "ticket-search: GraphQL error: $(printf '%s' "$resp" | jq -c '.errors' 2>/dev/null)" >&2
    return 1
  fi
  if ! printf '%s' "$resp" | jq -e . >/dev/null 2>&1; then
    echo "ticket-search: invalid JSON response from Linear" >&2
    return 1
  fi
  printf '%s' "$resp"
}

# ---- GraphQL query (the single swappable search seam) ----

# `searchIssues(term:)` confirmed live (see header). Swap ONLY this function + _rank if Linear
# ever renames the field; everything downstream is field-shape tolerant.
_q_search() {
  cat <<'GQL'
query($term: String!, $first: Int!, $includeArchived: Boolean!) {
  searchIssues(term: $term, first: $first, includeArchived: $includeArchived) {
    nodes { identifier title url priority state { name type } project { name } description }
  }
}
GQL
}

# ---- Query reduction ----

# _reduce_terms RAW_TEXT → space-separated salient search terms on stdout.
# WHY: lexical `searchIssues` degrades on a whole paragraph — a taskSummary is prose, but the
# search wants keywords. Keep FIN-keys and salient/technical tokens (uppercase, digits, long
# words), drop common stopwords, cap length. Do NOT "simplify" this into raw-paragraph-in.
_reduce_terms() {
  local raw="$1"
  printf '%s' "$raw" | tr -c 'A-Za-z0-9-' ' ' | tr ' ' '\n' | awk '
    BEGIN {
      split("the a an and or of to in on for with is are be this that it as at by from into your our we you they i his her their its will can may not no but if then than also more most such some any all each per via use used using add adds added new via into onto off out up down over under then them these those there here what which who whom when where why how do does did done doing", sw, " ");
      for (k in sw) stop[tolower(sw[k])] = 1;
    }
    {
      t = $0;
      if (t == "") next;
      lc = tolower(t);
      keep = 0;
      # FIN-key (or any TEAM-<num>) — always salient, even if short.
      if (t ~ /^[A-Za-z]+-[0-9]+$/) keep = 1;
      # A stopword is noise regardless of case (drops sentence-initial "Add", "New", "The").
      else if (lc in stop) keep = 0;
      # Has an uppercase letter or a digit → technical identifier / proper noun.
      else if (t ~ /[A-Z]/ || t ~ /[0-9]/) keep = 1;
      # Long-enough lexical token.
      else if (length(t) >= 4) keep = 1;
      if (!keep) next;
      if (seen[lc]++) next;         # dedup (case-insensitive)
      if (++n > 12) exit;           # cap ~12 terms
      out = (out == "" ? t : out " " t);
    }
    END { print out }
  '
}

# ---- Ranking (the single swappable relevance seam) ----

# _rank RESPONSE_JSON TERMS LIMIT → ranked+scored JSON array of hits.
# Computes a term-overlap score and sorts by it descending, tie-broken by the node's original
# order (stable). This tolerates BOTH cases the VERIFY-BEFORE-SHIP check leaves open: if the API
# returns UNRANKED nodes, overlap orders them; if it returns RANKED nodes, equal-overlap ties
# preserve the API order while every row still carries a score. Swap here if ranking is confirmed.
_rank() {
  local resp="$1" terms="$2" limit="$3"
  printf '%s' "$resp" | jq \
    --arg terms "$terms" --argjson limit "$limit" '
    def score2($s): (($s * 100) | round) as $h
      | ($h / 100 | tostring) as $str
      | (if ($str | test("\\.")) then ($str + "00")[0:(($str | index(".")) + 3)]
         else $str + ".00" end);
    ([ $terms | ascii_downcase | splits("[^a-z0-9-]+") ] | map(select(length > 0))) as $t
    | ($t | length) as $n
    | [ (.data.searchIssues.nodes // [])[]
        | (((.title // "") + " " + (.description // "") + " " + (.identifier // "")) | ascii_downcase) as $hay
        | (if $n == 0 then 0 else ([ $t[] as $term | select($hay | contains($term)) ] | length) / $n end) as $ov
        | {
            identifier: (.identifier // ""),
            title: (.title // ""),
            url: (.url // ""),
            state: (.state.name // null),
            stateType: (.state.type // null),
            project: (.project.name // null),
            _ov: $ov,
            score: (($ov * 100 | round) / 100),
            scoreLabel: score2($ov),
            snippet: ((.description // "") | gsub("\\\\[rnt]"; " ") | gsub("[\r\n\t]+"; " ") | gsub(" +"; " ")
                      | sub("^ +"; "") | sub(" +$"; "") | .[0:120])
          }
      ]
    | to_entries | map(.value + { _idx: .key })
    | sort_by([ (- ._ov), ._idx ])
    | .[0:$limit]
    | map(del(._ov, ._idx))
  '
}

# ---- Format ----

# _format RANKED_JSON MODE → stdout. MODE=json → the structured array; else human excerpt block.
_format() {
  local ranked="$1" mode="$2"
  if [ "$mode" = "json" ]; then
    printf '%s' "$ranked" | jq 'map(del(.scoreLabel))'
    echo
    return 0
  fi
  # Human: `N. [KEY] title · <state>` then an indented one-line snippet. NO score column — the
  # local term-overlap fraction reads as "irrelevant" (0.00) for prose taskSummary right where a
  # human skims SRC_RELATED_TICKETS; a rank ordinal conveys best-match-first honestly. The numeric
  # score stays in --json for the skill.
  printf '%s' "$ranked" | jq -r '
    to_entries[]
    | "\(.key + 1). [\(.value.identifier)] \(.value.title) · \(.value.state // "?")",
      "    \(if (.value.snippet // "") == "" then "(no description)" else .value.snippet end)"
  '
}

# ---- Search orchestration ----

cmd_search() {
  local query="" team="" include_closed=1 limit="$DEFAULT_LIMIT" mode="human"
  while [ $# -gt 0 ]; do
    case "$1" in
      --team) team="${2:-}"; shift 2 ;;
      --team=*) team="${1#*=}"; shift ;;
      --include-closed) include_closed=1; shift ;;   # DEFAULT ON; explicit affirm is a no-op
      --no-include-closed|--open-only) include_closed=0; shift ;;  # drop completed/canceled (state.type)
      --limit) limit="${2:-}"; shift 2 ;;
      --limit=*) limit="${1#*=}"; shift ;;
      --json) mode="json"; shift ;;
      -h|--help) usage; return 0 ;;
      -*) echo "ticket-search: unknown flag '$1'" >&2; return 1 ;;
      *) if [ -z "$query" ]; then query="$1"; else query="$query $1"; fi; shift ;;
    esac
  done
  [ -n "$query" ] || { echo "ticket-search: requires a query string" >&2; return 1; }
  if ! printf '%s' "$limit" | grep -qE '^[1-9][0-9]*$'; then
    echo "ticket-search: --limit must be a positive integer" >&2; return 1
  fi

  local terms
  terms="$(_reduce_terms "$query")"
  # Reduction emptied the query (all stopwords) → fall back to the raw text so we never search
  # for nothing.
  [ -n "$terms" ] || terms="$query"
  [ -n "${TICKET_SEARCH_DEBUG:-}" ] && echo "ticket-search: terms: $terms" >&2

  local include_archived="true"
  [ "$include_closed" = "1" ] || include_archived="false"

  local resp
  resp=$(_graphql "$(_q_search)" \
    "$(jq -n --arg t "$terms" --argjson f "$limit" --argjson ia "$include_archived" \
      '{term: $t, first: $f, includeArchived: $ia}')") || return 1

  local ranked
  ranked=$(_rank "$resp" "$terms" "$limit") || { echo "ticket-search: ranking failed" >&2; return 1; }

  # --include-closed OFF → drop completed/canceled by workflow state.type. This is the correct
  # "closed" axis — NOT includeArchived, which toggles Linear's separate trashed/archived axis.
  # Field-shape tolerant: a missing stateType is KEPT (fail-open, mirrors the VERIFY-BEFORE-SHIP
  # tolerance — better to over-surface than silently drop when the schema is unconfirmed).
  if [ "$include_closed" != "1" ]; then
    ranked=$(printf '%s' "$ranked" | jq \
      'map(select((.stateType // "") | (. != "completed" and . != "canceled")))')
  fi

  # Team scope: keep only hits whose identifier prefix matches the team key (e.g. FIN → FIN-*).
  # Post-filter keeps _q_search stable across the VERIFY-BEFORE-SHIP field question.
  if [ -n "$team" ]; then
    printf '%s' "$team" | grep -qiE '^[0-9a-f]{8}-' \
      && echo "ticket-search: --team expects an identifier prefix (e.g. FIN), not a UUID" >&2
    ranked=$(printf '%s' "$ranked" | jq --arg team "$team" \
      'map(select(.identifier | ascii_upcase | startswith(($team | ascii_upcase) + "-")))')
  fi

  _format "$ranked" "$mode"
}

# ---- Dispatch ----
case "${1:-}" in
  -h|--help|help) usage ;;
  "") echo "ticket-search: requires a query string" >&2; usage; exit 1 ;;
  *) cmd_search "$@" ;;
esac
