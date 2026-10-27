#!/bin/bash
# next-prefetch.sh — pre-warm the state an agent needs, so a woken agent arrives holding it.
#
# Usage:
#   engine next-prefetch <sessionDir> [--refresh-digest] [--digest-only] [--rag]
#                                     [--stale-minutes N] [--json] [--no-color]
#
# THE CLAIM, stated at its true size. This gathers readings and prints them. It decides nothing,
# ranks nothing, and summarises no source's content — each row is a count, a path, or a verbatim
# first line. Read-only: the only things it writes are its own cache directory and digest.
#
# TWO TIERS, because one source costs 40s and the others cost 1-3s.
#   CHEAP, taken live on every run: the local git reads, `open-asks`, `sweep-check`, `loom-page`.
#     Budgeted per source and in total; a source that overruns is reported UNREAD, never dropped.
#   EXPENSIVE, never taken on this path: `lane-stall` (41s on the operator's machine — it walks
#     every lane regardless of --minutes, which narrows the staleness THRESHOLD and not the scan),
#     the owner-scoped ticket search, and the RAG queries (a 1.9GB sql.js image per call). These
#     are taken only under --refresh-digest and stored; an ordinary run merely READS the digest.
#
# EVERY READING CARRIES ITS AGE. A digest entry stores its own readAt, so a partially refreshed
# digest ages per entry rather than wholesale. An entry older than the staleness bound is printed
# STALE with its value intact — labelling it is the point; dropping it would hide that we have an
# old answer, and injecting it unlabelled as fresh state is the failure this guards against.
#
# UNREAD IS NOT EMPTY. This is the one property the whole script exists to hold. A source that
# could not be read prints UNREAD with a reason; a source that was read and found nothing prints
# OK with a zero value. At the call site the two are indistinguishable unless they are spelled
# differently, and conflating them is how a blocking state goes unnamed. Consequences, all load-
# bearing: `open-asks`/`sweep-check`/`lane-stall` answer 0 = none, 3 = findings, 2 = instrument
# fault, so they are never wrapped in `|| true` — rc 2 is UNREAD and rc 3 is a finding. A branch
# with no upstream is UNREAD (no_upstream), never "ahead=0". No digest makes every expensive slot
# UNREAD (no_digest), never absent. No configured owner makes the ticket slot UNREAD
# (owner_unset), never "no tickets" — an unscoped search would answer for the whole team.
#
# Counting is done with awk, never `grep -c`: `grep -c` prints 0 AND exits 1 on no match, so the
# usual `$(... | grep -c x || echo 0)` yields "0\n0" and the next arithmetic test dies. An rc is
# always read on the line after the command and never through a pipeline, whose `$?` belongs to
# its last element.
#
# CONFIG comes from <sessionDir>/.state.json, not from flags, under a `prefetch` object with
# top-level fallbacks. The repository is read from config because the work may live in a repo that
# is not this engine's root; where a key is missing the row says which fallback supplied it.
#   prefetch.repo                   path to the git repo the session works in
#   prefetch.owner                  the seat a ticket search is scoped to
#   prefetch.team                   Linear team key for that search
#   prefetch.log                    the loom log sweep-check and loom-page read
#   prefetch.gitBudgetSeconds       default 3   (the operator's measured git pair is ~2.5s)
#   prefetch.sourceBudgetSeconds    default 6   per non-git cheap source
#   prefetch.cheapBudgetSeconds     default 12  whole cheap tier; overrun stops further reads
#   prefetch.expensiveBudgetSeconds default 180 per expensive source
#   prefetch.digestStaleMinutes     default 30  the bound past which a digest entry is STALE
#   prefetch.laneStallMinutes       passed to lane-stall --minutes
#
# Exit 0 = every source read · 3 = at least one UNREAD or STALE reading (a finding, not a
# failure) · 2 = instrument fault (bad arguments, unreadable session dir, self-check failed).
# Read the exit status DIRECTLY.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_SCRIPTS="${ENGINE_SCRIPTS_DIR:-$SCRIPT_DIR}"

fault() { echo "next-prefetch: $*" >&2; exit 2; }

USAGE="usage: engine next-prefetch <sessionDir> [--refresh-digest] [--digest-only] [--rag] [--stale-minutes N] [--json]"

SESSION_DIR=""
DO_REFRESH=0
DIGEST_ONLY=0
WANT_RAG=0
AS_JSON=0
STALE_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --refresh-digest) DO_REFRESH=1; shift ;;
    --digest-only)    DIGEST_ONLY=1; shift ;;
    --rag)            WANT_RAG=1; shift ;;
    --json)           AS_JSON=1; shift ;;
    --no-color)       shift ;;
    --stale-minutes)  shift; STALE_OVERRIDE="${1:-}"; [ -n "$STALE_OVERRIDE" ] || fault "--stale-minutes needs a value"; shift ;;
    -h|--help)        echo "$USAGE"; exit 0 ;;
    -*)               fault "unknown flag: $1 ($USAGE)" ;;
    *)                [ -z "$SESSION_DIR" ] || fault "more than one sessionDir given ($USAGE)"; SESSION_DIR="$1"; shift ;;
  esac
done

[ -n "$SESSION_DIR" ] || fault "$USAGE"
[ -d "$SESSION_DIR" ] || fault "not a directory: $SESSION_DIR"
SESSION_DIR="$(cd "$SESSION_DIR" && pwd)"
command -v jq >/dev/null 2>&1 || fault "jq is required to read .state.json"

# ── clock ───────────────────────────────────────────────────────────────────────
# A bounded run needs a real clock. perl's Time::HiRes is on every mac (~20ms); without it we
# fall back to whole seconds and SAY so rather than reporting invented milliseconds.
CLOCK_KIND="seconds"
if perl -MTime::HiRes=time -e 1 >/dev/null 2>&1; then CLOCK_KIND="ms"; fi
_ms() {
  if [ "$CLOCK_KIND" = "ms" ]; then
    perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000'
  else
    echo $(( $(date +%s) * 1000 ))
  fi
}
_now()  { date +%s; }
_iso()  { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ── bounded execution ───────────────────────────────────────────────────────────
TIMEOUT_BIN=""
for _c in timeout gtimeout; do
  if command -v "$_c" >/dev/null 2>&1; then TIMEOUT_BIN="$_c"; break; fi
done

# _bounded SECS CMD... — rc 124 means it was cut off. Without a timeout binary we poll a
# backgrounded pid; an unbounded wait is never an option on a path a hook sits behind.
_bounded() {
  local secs="$1"; shift
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$secs" "$@"
    return $?
  fi
  "$@" &
  local pid=$! waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$secs" ]; then
      kill -TERM "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 1
    waited=$(( waited + 1 ))
  done
  wait "$pid"
  return $?
}

WORK="$SESSION_DIR/.next-prefetch"
mkdir -p "$WORK" 2>/dev/null || fault "cannot create cache dir: $WORK"
chmod 700 "$WORK" 2>/dev/null || true
DIGEST="$WORK/digest.json"

# ── config ──────────────────────────────────────────────────────────────────────
STATE="$SESSION_DIR/.state.json"
STATE_OK=0
if [ -f "$STATE" ] && jq -e . "$STATE" >/dev/null 2>&1; then STATE_OK=1; fi

# cfg KEY DEFAULT — prefetch.KEY, then top-level KEY, then DEFAULT.
# Sets CFG_VAL and CFG_VIA as globals and prints nothing: a value returned through stdout is
# captured in a subshell, and the provenance assigned alongside it would never reach the caller.
CFG_VAL=""
CFG_VIA=""
cfg() {
  local key="$1" def="${2:-}" v
  CFG_VAL="$def"
  CFG_VIA="default"
  if [ "$STATE_OK" -eq 1 ]; then
    v=$(jq -r --arg k "$key" '(.prefetch // {}) | .[$k] // empty | tostring' "$STATE" 2>/dev/null)
    if [ -n "$v" ]; then CFG_VAL="$v"; CFG_VIA="prefetch.$key"; return 0; fi
    v=$(jq -r --arg k "$key" '.[$k] // empty | tostring' "$STATE" 2>/dev/null)
    if [ -n "$v" ]; then CFG_VAL="$v"; CFG_VIA="$key"; return 0; fi
  fi
  return 0
}

cfg gitBudgetSeconds 3;         GIT_BUDGET="$CFG_VAL"
cfg sourceBudgetSeconds 6;      SRC_BUDGET="$CFG_VAL"
cfg cheapBudgetSeconds 12;      CHEAP_BUDGET="$CFG_VAL"
cfg expensiveBudgetSeconds 180; EXP_BUDGET="$CFG_VAL"
cfg digestStaleMinutes 30;      STALE_MIN="$CFG_VAL"
[ -n "$STALE_OVERRIDE" ] && STALE_MIN="$STALE_OVERRIDE"
cfg laneStallMinutes "";        LANE_MIN="$CFG_VAL"

for _b in "$GIT_BUDGET" "$SRC_BUDGET" "$CHEAP_BUDGET" "$EXP_BUDGET" "$STALE_MIN"; do
  case "$_b" in ''|*[!0-9]*) fault "budget values in .state.json must be whole seconds/minutes, got '$_b'" ;; esac
done

cfg owner ""; OWNER="$CFG_VAL"; OWNER_VIA="$CFG_VIA"
cfg team "";  TEAM="$CFG_VAL";  TEAM_VIA="$CFG_VIA"

# Repo: config first, because the work may live in a repo that is not the engine's root.
cfg repo ""; REPO="$CFG_VAL"; REPO_VIA="$CFG_VIA"
_git_root() { git -C "$1" rev-parse --show-toplevel 2>/dev/null; }
if [ -n "$REPO" ] && [ ! -d "$REPO" ]; then
  REPO_VIA="$REPO_VIA (configured path does not exist)"
  REPO=""
fi
if [ -z "$REPO" ] && [ "$STATE_OK" -eq 1 ]; then
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    r=$(_git_root "$d") || r=""
    if [ -n "$r" ]; then REPO="$r"; REPO_VIA="directoriesOfInterest"; break; fi
  done < <(jq -r '.directoriesOfInterest // [] | .[]' "$STATE" 2>/dev/null)
fi
if [ -z "$REPO" ]; then
  r=$(_git_root "$PWD") || r=""
  if [ -n "$r" ]; then REPO="$r"; REPO_VIA="cwd"; fi
fi

# Log: config first, then LOOM_LOG.md, then the single *_LOG.md at the session root.
cfg log ""; LOG="$CFG_VAL"; LOG_VIA="$CFG_VIA"
if [ -n "$LOG" ] && [ ! -f "$LOG" ]; then LOG_VIA="$LOG_VIA (configured path does not exist)"; LOG=""; fi
if [ -z "$LOG" ] && [ -f "$SESSION_DIR/LOOM_LOG.md" ]; then LOG="$SESSION_DIR/LOOM_LOG.md"; LOG_VIA="session root"; fi
if [ -z "$LOG" ]; then
  n=$(ls -1 "$SESSION_DIR"/*_LOG.md 2>/dev/null | awk 'END{print NR+0}')
  if [ "$n" = "1" ]; then LOG=$(ls -1 "$SESSION_DIR"/*_LOG.md 2>/dev/null); LOG_VIA="session root (only candidate)"; fi
fi

# ── readings ────────────────────────────────────────────────────────────────────
R_NAME=(); R_TIER=(); R_STATUS=(); R_REASON=(); R_AGE=(); R_TOOK=(); R_VALUE=()

# record NAME TIER STATUS REASON AGE_SECONDS TOOK_MS VALUE
# Self-checking: OK without a value and UNREAD/STALE without a reason are instrument faults,
# because either one would let a row read as something it is not.
record() {
  local name="$1" tier="$2" status="$3" reason="$4" age="$5" took="$6" value="$7"
  case "$status" in
    OK)            [ -n "$value" ]  || fault "self-check: OK reading '$name' carries no value" ;;
    UNREAD|STALE)  [ -n "$reason" ] || fault "self-check: $status reading '$name' carries no reason" ;;
    *)             fault "self-check: unknown status '$status' for '$name'" ;;
  esac
  R_NAME+=("$name"); R_TIER+=("$tier"); R_STATUS+=("$status"); R_REASON+=("$reason")
  R_AGE+=("$age"); R_TOOK+=("$took"); R_VALUE+=("$value")
}

A_RC=0; A_MS=0; A_OUT=""; A_ERR=""
# _attempt NAME BUDGET CMD... — rc read on the line after the call, never through a pipe.
_attempt() {
  local name="$1" budget="$2"; shift 2
  local t0 t1
  A_OUT="$WORK/$name.out"; A_ERR="$WORK/$name.err"
  t0=$(_ms)
  _bounded "$budget" "$@" >"$A_OUT" 2>"$A_ERR"
  A_RC=$?
  t1=$(_ms)
  A_MS=$(( t1 - t0 ))
}

_err1() { awk 'NF{print; exit}' "${1:-/dev/null}" 2>/dev/null | cut -c1-160; }
# Row counts anchor on the producing tool's documented line prefix (^OPEN, ^UNROWED, ^STALE).
# An unanchored match counts the tool's own explanatory header as a finding, and a case-wrong
# one reported 154 stale lanes as zero.
_count() { awk 'END{print NR+0}' "${1:-/dev/null}" 2>/dev/null; }

CHEAP_SPENT_MS=0
CHEAP_CUT=0
# True once the whole cheap tier's budget is gone. A source skipped for that reason is UNREAD
# with reason budget_exhausted — it is emphatically not a source that answered nothing.
_cheap_room() {
  if [ "$CHEAP_SPENT_MS" -ge $(( CHEAP_BUDGET * 1000 )) ]; then CHEAP_CUT=1; return 1; fi
  return 0
}
_spend() { CHEAP_SPENT_MS=$(( CHEAP_SPENT_MS + $1 )); }

# ── cheap tier ──────────────────────────────────────────────────────────────────
read_cheap() {
  # git
  if [ -z "$REPO" ]; then
    record git.head   cheap UNREAD "repo_unresolved: no prefetch.repo, no git root under directoriesOfInterest or cwd" "" "" ""
    record git.status cheap UNREAD "repo_unresolved" "" "" ""
    record git.branch_divergence cheap UNREAD "repo_unresolved" "" "" ""
  else
    if _cheap_room; then
      _attempt git.head "$GIT_BUDGET" git -C "$REPO" rev-parse --abbrev-ref HEAD
      _spend "$A_MS"
      if [ "$A_RC" -eq 0 ]; then
        record git.head cheap OK "" 0 "$A_MS" "branch=$(_err1 "$A_OUT") repo=$REPO"
      elif [ "$A_RC" -eq 124 ]; then
        record git.head cheap UNREAD "timeout after ${GIT_BUDGET}s" 0 "$A_MS" ""
      else
        record git.head cheap UNREAD "git_exit_$A_RC: $(_err1 "$A_ERR")" 0 "$A_MS" ""
      fi
    else
      record git.head cheap UNREAD "budget_exhausted" "" "" ""
    fi

    if _cheap_room; then
      _attempt git.status "$GIT_BUDGET" git -C "$REPO" status --porcelain
      _spend "$A_MS"
      if [ "$A_RC" -eq 0 ]; then
        local total untracked staged
        total=$(_count "$A_OUT")
        untracked=$(awk '/^\?\?/{c++} END{print c+0}' "$A_OUT" 2>/dev/null)
        staged=$(awk '/^[MARCD]/{c++} END{print c+0}' "$A_OUT" 2>/dev/null)
        record git.status cheap OK "" 0 "$A_MS" "changed=$total staged=$staged untracked=$untracked"
      elif [ "$A_RC" -eq 124 ]; then
        record git.status cheap UNREAD "timeout after ${GIT_BUDGET}s" 0 "$A_MS" ""
      else
        record git.status cheap UNREAD "git_exit_$A_RC: $(_err1 "$A_ERR")" 0 "$A_MS" ""
      fi
    else
      record git.status cheap UNREAD "budget_exhausted" "" "" ""
    fi

    if _cheap_room; then
      _attempt git.upstream "$GIT_BUDGET" git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{u}'
      _spend "$A_MS"
      if [ "$A_RC" -ne 0 ]; then
        # No upstream is a missing reading, not a divergence of zero.
        record git.branch_divergence cheap UNREAD "no_upstream: this branch tracks nothing, so ahead/behind is unknowable" 0 "$A_MS" ""
      else
        local up; up=$(_err1 "$A_OUT")
        _attempt git.divergence "$GIT_BUDGET" git -C "$REPO" rev-list --count --left-right "$up...HEAD"
        _spend "$A_MS"
        if [ "$A_RC" -eq 0 ]; then
          local lr behind ahead
          lr=$(_err1 "$A_OUT")
          behind=$(echo "$lr" | awk '{print $1+0}')
          ahead=$(echo "$lr" | awk '{print $2+0}')
          record git.branch_divergence cheap OK "" 0 "$A_MS" "ahead=$ahead behind=$behind vs=$up"
        elif [ "$A_RC" -eq 124 ]; then
          record git.branch_divergence cheap UNREAD "timeout after ${GIT_BUDGET}s" 0 "$A_MS" ""
        else
          record git.branch_divergence cheap UNREAD "git_exit_$A_RC: $(_err1 "$A_ERR")" 0 "$A_MS" ""
        fi
      fi
    else
      record git.branch_divergence cheap UNREAD "budget_exhausted" "" "" ""
    fi
  fi

  # open asks
  if ! _cheap_room; then
    record asks cheap UNREAD "budget_exhausted" "" "" ""
  elif [ ! -x "$ENGINE_SCRIPTS/open-asks.sh" ]; then
    record asks cheap UNREAD "tool_missing: $ENGINE_SCRIPTS/open-asks.sh" "" "" ""
  else
    _attempt asks "$SRC_BUDGET" "$ENGINE_SCRIPTS/open-asks.sh" "$SESSION_DIR"
    _spend "$A_MS"
    case "$A_RC" in
      0) record asks cheap OK "" 0 "$A_MS" "open=0" ;;
      3) record asks cheap OK "" 0 "$A_MS" "open=$(awk '/^(OPEN|UNPARSED) /{c++} END{print c+0}' "$A_OUT") at=$A_OUT" ;;
      124) record asks cheap UNREAD "timeout after ${SRC_BUDGET}s" 0 "$A_MS" "" ;;
      *) record asks cheap UNREAD "open-asks_exit_$A_RC: $(_err1 "$A_ERR")" 0 "$A_MS" "" ;;
    esac
  fi

  # sweep-check
  if [ -z "$LOG" ]; then
    record sweep cheap UNREAD "log_unresolved: no prefetch.log, no LOOM_LOG.md, no single *_LOG.md at the session root" "" "" ""
  elif ! _cheap_room; then
    record sweep cheap UNREAD "budget_exhausted" "" "" ""
  elif [ ! -x "$ENGINE_SCRIPTS/sweep-check.sh" ]; then
    record sweep cheap UNREAD "tool_missing: $ENGINE_SCRIPTS/sweep-check.sh" "" "" ""
  else
    _attempt sweep "$SRC_BUDGET" "$ENGINE_SCRIPTS/sweep-check.sh" "$LOG"
    _spend "$A_MS"
    case "$A_RC" in
      0) record sweep cheap OK "" 0 "$A_MS" "certainly_unrowed=0" ;;
      3) record sweep cheap OK "" 0 "$A_MS" "certainly_unrowed=$(awk '/^UNROWED/{c++} END{print c+0}' "$A_OUT") at=$A_OUT" ;;
      124) record sweep cheap UNREAD "timeout after ${SRC_BUDGET}s" 0 "$A_MS" "" ;;
      *) record sweep cheap UNREAD "sweep-check_exit_$A_RC: $(_err1 "$A_ERR")" 0 "$A_MS" "" ;;
    esac
  fi

  # loom-page present state
  if [ -z "$LOG" ]; then
    record loom_state cheap UNREAD "log_unresolved" "" "" ""
  elif ! _cheap_room; then
    record loom_state cheap UNREAD "budget_exhausted" "" "" ""
  elif [ ! -x "$ENGINE_SCRIPTS/loom-page.sh" ]; then
    record loom_state cheap UNREAD "tool_missing: $ENGINE_SCRIPTS/loom-page.sh" "" "" ""
  else
    _attempt loom_state "$SRC_BUDGET" "$ENGINE_SCRIPTS/loom-page.sh" "$LOG" --text
    _spend "$A_MS"
    if [ "$A_RC" -eq 0 ]; then
      record loom_state cheap OK "" 0 "$A_MS" "lines=$(_count "$A_OUT") at=$A_OUT"
    elif [ "$A_RC" -eq 124 ]; then
      record loom_state cheap UNREAD "timeout after ${SRC_BUDGET}s" 0 "$A_MS" ""
    else
      record loom_state cheap UNREAD "loom-page_exit_$A_RC: $(_err1 "$A_ERR")" 0 "$A_MS" ""
    fi
  fi
}

# ── expensive tier (only under --refresh-digest) ───────────────────────────────
E_NAME=(); E_STATUS=(); E_REASON=(); E_TOOK=(); E_VALUE=()
erecord() {
  E_NAME+=("$1"); E_STATUS+=("$2"); E_REASON+=("$3"); E_TOOK+=("$4"); E_VALUE+=("$5")
}

EXPENSIVE_SLOTS="lanes tickets rag_sessions"

refresh_digest() {
  # lane-stall: 41s on the operator's machine, and --minutes narrows the threshold and not the
  # scan, so this cannot sit on a synchronous path at any setting.
  if [ ! -x "$ENGINE_SCRIPTS/lane-stall.sh" ]; then
    erecord lanes UNREAD "tool_missing: $ENGINE_SCRIPTS/lane-stall.sh" 0 ""
  else
    local args=("$SESSION_DIR")
    [ -n "$LANE_MIN" ] && args+=(--minutes "$LANE_MIN")
    _attempt lanes "$EXP_BUDGET" "$ENGINE_SCRIPTS/lane-stall.sh" ${args[@]+"${args[@]}"}
    case "$A_RC" in
      0) erecord lanes OK "" "$A_MS" "stalled=0" ;;
      3) erecord lanes OK "" "$A_MS" "stalled=$(awk '/^STALE/{c++} END{print c+0}' "$A_OUT") at=$A_OUT" ;;
      124) erecord lanes UNREAD "timeout after ${EXP_BUDGET}s" "$A_MS" "" ;;
      *) erecord lanes UNREAD "lane-stall_exit_$A_RC: $(_err1 "$A_ERR")" "$A_MS" "" ;;
    esac
  fi

  # Owner-scoped ticket search. No owner means NOT SEARCHED — an unscoped search would answer
  # for the whole team, and that answer dressed as this seat's work is worse than no answer.
  if [ -z "$OWNER" ]; then
    erecord tickets UNREAD "owner_unset: no prefetch.owner in .state.json; an unscoped search would return the whole team's work, so none was run" 0 ""
  elif [ ! -x "$ENGINE_SCRIPTS/ticket-search.sh" ]; then
    erecord tickets UNREAD "tool_missing: $ENGINE_SCRIPTS/ticket-search.sh" 0 ""
  else
    local targs=("$OWNER")
    [ -n "$TEAM" ] && targs+=(--team "$TEAM")
    _attempt tickets "$EXP_BUDGET" "$ENGINE_SCRIPTS/ticket-search.sh" ${targs[@]+"${targs[@]}"}
    if [ "$A_RC" -eq 0 ]; then
      erecord tickets OK "" "$A_MS" "hits=$(_count "$A_OUT") owner=$OWNER at=$A_OUT"
    elif [ "$A_RC" -eq 124 ]; then
      erecord tickets UNREAD "timeout after ${EXP_BUDGET}s" "$A_MS" ""
    else
      erecord tickets UNREAD "ticket-search_exit_$A_RC: $(_err1 "$A_ERR")" "$A_MS" ""
    fi
  fi

  # RAG. The slot is wired and off by default: a query cost roughly 14-21s when measured in Oct
  # 2026 — the spread is machine state, idle versus loaded — because query.ts scores every indexed
  # chunk instead of using a vector index. Cost tracks chunk count, not image bytes, so
  # ENGINE_RAG_TIMEOUT is the thing to raise, not the index to shrink.
  if [ "$WANT_RAG" -ne 1 ]; then
    erecord rag_sessions UNREAD "rag_disabled: semantic search cost roughly 14-21s per query when measured in Oct 2026 (the spread is machine load), against a bound that then defaulted to 10s; the cost is a full scan of every indexed chunk, not the index size; pass --rag to attempt it anyway" 0 ""
  else
    local tool="$HOME/.claude/tools/session-search/session-search.sh"
    if [ ! -x "$tool" ]; then
      erecord rag_sessions UNREAD "tool_missing: $tool" 0 ""
    else
      local q
      q=$(jq -r '.taskSummary // empty' "$STATE" 2>/dev/null | cut -c1-200)
      [ -n "$q" ] || q="session state"
      _attempt rag_sessions "${ENGINE_RAG_TIMEOUT:-30}" "$tool" query "$q" --limit 5
      if [ "$A_RC" -eq 0 ]; then
        erecord rag_sessions OK "" "$A_MS" "hits=$(_count "$A_OUT") at=$A_OUT"
      elif [ "$A_RC" -eq 124 ]; then
        erecord rag_sessions UNREAD "timeout after ${ENGINE_RAG_TIMEOUT:-30}s" "$A_MS" ""
      else
        erecord rag_sessions UNREAD "session-search_exit_$A_RC: $(_err1 "$A_ERR")" "$A_MS" ""
      fi
    fi
  fi

  local now; now=$(_now)
  local tmp="$WORK/digest.json.tmp.$$"
  {
    printf '{\n  "writtenAt": %s,\n  "writtenAtIso": "%s",\n  "entries": [\n' "$now" "$(_iso)"
    local i=0 n=${#E_NAME[@]}
    while [ "$i" -lt "$n" ]; do
      [ "$i" -gt 0 ] && printf ',\n'
      jq -cn --arg name "${E_NAME[$i]}" --arg status "${E_STATUS[$i]}" \
             --arg reason "${E_REASON[$i]}" --arg value "${E_VALUE[$i]}" \
             --argjson took "${E_TOOK[$i]:-0}" --argjson readAt "$now" \
        '{name:$name,status:$status,reason:$reason,value:$value,tookMs:$took,readAt:$readAt}' \
        | awk '{print "    " $0}' | tr -d '\n'
      i=$(( i + 1 ))
    done
    printf '\n  ]\n}\n'
  } > "$tmp"
  if jq -e . "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$DIGEST"
    chmod 600 "$DIGEST" 2>/dev/null || true
  else
    rm -f "$tmp"
    fault "self-check: refused to write a malformed digest"
  fi
}

# Fold the digest into the readings. A missing digest, or a slot absent from it, is UNREAD —
# never a quietly omitted row, because an omitted row is read as nothing-to-report.
read_digest() {
  local have=0 written=""
  if [ -f "$DIGEST" ] && jq -e . "$DIGEST" >/dev/null 2>&1; then have=1; fi
  local now; now=$(_now)
  local slot
  for slot in $EXPENSIVE_SLOTS; do
    if [ "$have" -ne 1 ]; then
      record "$slot" digest UNREAD "no_digest: run 'engine next-prefetch $SESSION_DIR --refresh-digest' out of band" "" "" ""
      continue
    fi
    local row
    row=$(jq -c --arg n "$slot" '.entries[]? | select(.name == $n)' "$DIGEST" 2>/dev/null | head -1)
    if [ -z "$row" ]; then
      record "$slot" digest UNREAD "absent_from_digest: the digest was written without this slot" "" "" ""
      continue
    fi
    local st rs vl ra tk age
    st=$(printf '%s' "$row" | jq -r '.status // "UNREAD"')
    rs=$(printf '%s' "$row" | jq -r '.reason // ""')
    vl=$(printf '%s' "$row" | jq -r '.value // ""')
    ra=$(printf '%s' "$row" | jq -r '.readAt // 0')
    tk=$(printf '%s' "$row" | jq -r '.tookMs // 0')
    age=$(( now - ra ))
    [ "$age" -lt 0 ] && age=0
    if [ "$st" = "OK" ] && [ "$age" -gt $(( STALE_MIN * 60 )) ]; then
      # Labelled, never dropped: an old answer we know is old still beats no answer.
      record "$slot" digest STALE "age_exceeds_bound: ${age}s old, bound ${STALE_MIN}m" "$age" "$tk" "$vl"
    elif [ "$st" = "OK" ]; then
      record "$slot" digest OK "" "$age" "$tk" "$vl"
    else
      # A stored UNREAD stays UNREAD and keeps its own reason; age still stated.
      record "$slot" digest UNREAD "${rs:-stored_unread}" "$age" "$tk" ""
    fi
  done
}

# ── render ──────────────────────────────────────────────────────────────────────
_fmt_age() {
  local a="${1:-}"
  [ -z "$a" ] && { printf '%s' "-"; return; }
  if [ "$a" -lt 60 ]; then printf '%ss' "$a"
  elif [ "$a" -lt 3600 ]; then printf '%sm' $(( a / 60 ))
  else printf '%sh%sm' $(( a / 3600 )) $(( (a % 3600) / 60 )); fi
}
_fmt_took() {
  local t="${1:-}"
  [ -z "$t" ] && { printf '%s' "-"; return; }
  printf '%sms' "$t"
}

render_text() {
  local n=${#R_NAME[@]} i=0 ok=0 unread=0 stale=0
  echo "# next-prefetch — $(basename "$SESSION_DIR") at $(_iso)"
  echo "config  sessionDir=$SESSION_DIR"
  echo "config  repo=${REPO:-UNRESOLVED} (via ${REPO_VIA})"
  echo "config  log=${LOG:-UNRESOLVED} (via ${LOG_VIA})"
  if [ -n "$OWNER" ]; then
    echo "config  owner=$OWNER (via $OWNER_VIA)"
  else
    echo "config  owner=UNSET — no seat to scope a ticket search to; the ticket slot reports UNREAD rather than searching unscoped"
  fi
  echo "config  budgets git=${GIT_BUDGET}s source=${SRC_BUDGET}s cheapTotal=${CHEAP_BUDGET}s expensive=${EXP_BUDGET}s staleBound=${STALE_MIN}m clock=${CLOCK_KIND}"
  [ "$STATE_OK" -eq 1 ] || echo "config  WARNING .state.json unreadable or not JSON — every value above is a default"
  echo ""
  printf '%-7s %-22s %-7s %-8s %s\n' "STATUS" "SOURCE" "AGE" "TOOK" "VALUE / REASON"
  while [ "$i" -lt "$n" ]; do
    local body
    case "${R_STATUS[$i]}" in
      OK)     body="${R_VALUE[$i]}"; ok=$(( ok + 1 )) ;;
      STALE)  body="${R_VALUE[$i]}  <<< ${R_REASON[$i]}"; stale=$(( stale + 1 )) ;;
      UNREAD) body="reason=${R_REASON[$i]}"; unread=$(( unread + 1 )) ;;
    esac
    printf '%-7s %-22s %-7s %-8s %s\n' "${R_STATUS[$i]}" "${R_NAME[$i]}" \
      "$(_fmt_age "${R_AGE[$i]}")" "$(_fmt_took "${R_TOOK[$i]}")" "$body"
    i=$(( i + 1 ))
  done
  echo ""
  echo "cheap tier spent ${CHEAP_SPENT_MS}ms of $(( CHEAP_BUDGET * 1000 ))ms budget"
  [ "$CHEAP_CUT" -eq 1 ] && echo "cheap tier BUDGET EXHAUSTED — the sources below the cut were not attempted"
  if [ -f "$DIGEST" ]; then
    echo "digest     $DIGEST written $(jq -r '.writtenAtIso // "?"' "$DIGEST" 2>/dev/null)"
  else
    echo "digest     ABSENT at $DIGEST — refresh it out of band with --refresh-digest"
  fi
  echo "tally      $ok OK · $unread UNREAD · $stale STALE"
  # The loud line. These are sources we DID NOT READ, not sources that answered nothing.
  local names=""
  i=0
  while [ "$i" -lt "$n" ]; do
    if [ "${R_STATUS[$i]}" = "UNREAD" ]; then names="$names ${R_NAME[$i]}"; fi
    i=$(( i + 1 ))
  done
  if [ -n "$names" ]; then
    echo "UNREAD    $(echo "$names" | sed 's/^ //') — NOT read. These are not empty readings; treat each as unknown state."
  else
    echo "UNREAD    none — every source answered."
  fi
}

render_json() {
  local n=${#R_NAME[@]} i=0
  local rows="$WORK/readings.jsonl.$$"
  : > "$rows"
  while [ "$i" -lt "$n" ]; do
    jq -cn --arg name "${R_NAME[$i]}" --arg tier "${R_TIER[$i]}" --arg status "${R_STATUS[$i]}" \
           --arg reason "${R_REASON[$i]}" --arg value "${R_VALUE[$i]}" \
           --arg age "${R_AGE[$i]}" --arg took "${R_TOOK[$i]}" \
      '{name:$name,tier:$tier,status:$status,reason:$reason,value:$value,
        ageSeconds:(if $age=="" then null else ($age|tonumber) end),
        tookMs:(if $took=="" then null else ($took|tonumber) end)}' >> "$rows"
    i=$(( i + 1 ))
  done
  jq -n --slurpfile readings "$rows" \
        --arg generatedAt "$(_iso)" --arg sessionDir "$SESSION_DIR" \
        --arg repo "${REPO:-}" --arg repoVia "$REPO_VIA" \
        --arg log "${LOG:-}" --arg logVia "$LOG_VIA" \
        --arg owner "${OWNER:-}" --arg ownerVia "$OWNER_VIA" \
        --arg digest "$DIGEST" --arg clock "$CLOCK_KIND" \
        --argjson staleMinutes "$STALE_MIN" --argjson cheapSpentMs "$CHEAP_SPENT_MS" \
        --argjson cheapBudgetMs "$(( CHEAP_BUDGET * 1000 ))" --argjson cheapCut "$CHEAP_CUT" \
    '{generatedAt:$generatedAt, sessionDir:$sessionDir,
      config:{repo:$repo, repoVia:$repoVia, log:$log, logVia:$logVia,
              owner:(if $owner=="" then null else $owner end), ownerVia:$ownerVia,
              digestPath:$digest, staleMinutes:$staleMinutes, clock:$clock},
      budget:{cheapSpentMs:$cheapSpentMs, cheapBudgetMs:$cheapBudgetMs, exhausted:($cheapCut==1)},
      readings:$readings,
      unread:[$readings[] | select(.status=="UNREAD") | .name],
      stale:[$readings[] | select(.status=="STALE") | .name]}'
  rm -f "$rows"
}

# ── main ────────────────────────────────────────────────────────────────────────
[ "$DO_REFRESH" -eq 1 ] && refresh_digest
[ "$DIGEST_ONLY" -eq 1 ] || read_cheap
read_digest

if [ "$AS_JSON" -eq 1 ]; then render_json; else render_text; fi

RC=0
i=0
while [ "$i" -lt "${#R_STATUS[@]}" ]; do
  case "${R_STATUS[$i]}" in UNREAD|STALE) RC=3 ;; esac
  i=$(( i + 1 ))
done
exit "$RC"
