#!/bin/bash
# tools/await-next/await-next.sh — the dual-channel fleet blocking primitive.
#
# Contract (docs/FLEET.md §"await-next (Unified Blocking Primitive)"):
#   1. Sweep children (FLEET_MANAGES) — priority error > unchecked > done
#   2. Scan tags    (FLEET_CLAIMS / FLEET_TARGETED_CLAIMS) under sessions/
#   3. Something found -> auto-claim and return. Children beat work.
#   4. Nothing found -> race child-wake (tmux) against fswatch, bounded by timeout
#   5. On wake -> re-sweep -> return; a wake that resolves nothing resumes the wait
#
# Outcomes, one per line 1, each a NAMED outcome:
#   CHILD <pane>|<state>|<label>|<location>   exit 0   (+ capture JSON, + STATUS)
#   WORK <file>|<tag>|<noun>                  exit 0   (+ CLAIMED line)
#   FOCUSED                                   exit 0   (+ STATUS)
#   TIMEOUT                                   exit 0   (+ STATUS)  <- expiry is an outcome
#   NOCHANNEL                                 exit 2   nothing to wait on; blocking here
#                                                      would be unbounded by construction
#   usage / bad argument                      exit 1
#
# The bound is the supervisor loop, not `timeout(1)`: watchers are reaped when the
# loop expires, so a hung watcher cannot outlive the ceiling. TIMEOUT_MAX caps the
# caller's own request for the same reason. A wake is advisory — the sweep is truth
# (§INV_WAKE_ON_ACTIONABLE_STATES) — so a spurious wake costs a re-scan, not the wait.

set -uo pipefail

TIMEOUT_DEFAULT=300
TIMEOUT_MAX=3600
POLL_MS=250
CAPTURE_LINES=80

TIMEOUT=""
PANES_FILTER=""
CLAIMS=""
TARGETED_CLAIMS=""
SELF_PANE="${FLEET_PANE:-}"
SESSIONS_DIR=""
SOCKET="${FLEET_SOCKET:-fleet}"
DO_CONNECT=1
DEGRADED=""

usage() {
  cat <<'USAGE'
Usage: await-next.sh [timeout_seconds] [options]

  --panes a,b            managed panes (default: $FLEET_MANAGES)
  --claims a,b           claim nouns  (default: $FLEET_CLAIMS)
  --targeted-claims a,b  targeted nouns (default: $FLEET_TARGETED_CLAIMS)
  --pane window:label    this agent's identity (default: $FLEET_PANE)
  --sessions-dir PATH    tag search root (default: <cwd>/sessions)
  --socket NAME          tmux socket (default: $FLEET_SOCKET or "fleet")
  --no-connect           skip the coordinator purple-layer connect/disconnect
  -h, --help

Outcomes: CHILD | WORK | FOCUSED | TIMEOUT (exit 0) · NOCHANNEL (exit 2) · usage (exit 1)
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --panes)           PANES_FILTER="${2:-}"; shift 2 ;;
    --claims)          CLAIMS="${2:-}"; shift 2 ;;
    --targeted-claims) TARGETED_CLAIMS="${2:-}"; shift 2 ;;
    --pane)            SELF_PANE="${2:-}"; shift 2 ;;
    --sessions-dir)    SESSIONS_DIR="${2:-}"; shift 2 ;;
    --socket)          SOCKET="${2:-}"; shift 2 ;;
    --no-connect)      DO_CONNECT=0; shift ;;
    -h|--help)         usage; exit 0 ;;
    [0-9]*)            TIMEOUT="$1"; shift ;;
    *) echo "ERROR: unknown argument '$1'" >&2; usage >&2; exit 1 ;;
  esac
done

[ -n "$TIMEOUT" ] || TIMEOUT="$TIMEOUT_DEFAULT"
case "$TIMEOUT" in
  ''|*[!0-9]*) echo "ERROR: timeout must be a non-negative integer, got '$TIMEOUT'" >&2; exit 1 ;;
esac
if [ "$TIMEOUT" -gt "$TIMEOUT_MAX" ]; then
  echo "ERROR: timeout $TIMEOUT exceeds ceiling $TIMEOUT_MAX" >&2
  exit 1
fi

[ -n "$PANES_FILTER" ]    || PANES_FILTER="${FLEET_MANAGES:-}"
[ -n "$CLAIMS" ]          || CLAIMS="${FLEET_CLAIMS:-}"
[ -n "$TARGETED_CLAIMS" ] || TARGETED_CLAIMS="${FLEET_TARGETED_CLAIMS:-}"
[ -n "$SESSIONS_DIR" ]    || SESSIONS_DIR="$PWD/sessions"

TMUX_FMT='#{pane_id}|#{@pane_notify}|#{@pane_fleet_id}|#{@pane_label}|#{@pane_user_focused}|#{session_name}:#{window_name}|#{pane_title}'

HAS_CHILD_CHANNEL=0
HAS_WORK_CHANNEL=0
[ -n "$PANES_FILTER" ] && HAS_CHILD_CHANNEL=1
if [ -n "$CLAIMS" ] || [ -n "$TARGETED_CLAIMS" ]; then HAS_WORK_CHANNEL=1; fi

if [ "$HAS_CHILD_CHANNEL" -eq 1 ] && ! tmux -L "$SOCKET" has-session >/dev/null 2>&1; then
  HAS_CHILD_CHANNEL=0
  DEGRADED="${DEGRADED}no-tmux-server "
fi
if [ "$HAS_WORK_CHANNEL" -eq 1 ] && [ ! -d "$SESSIONS_DIR" ]; then
  HAS_WORK_CHANNEL=0
  DEGRADED="${DEGRADED}no-sessions-dir "
fi

if [ "$HAS_CHILD_CHANNEL" -eq 0 ] && [ "$HAS_WORK_CHANNEL" -eq 0 ]; then
  echo "NOCHANNEL"
  echo "REASON panes='${PANES_FILTER}' claims='${CLAIMS}' targeted='${TARGETED_CLAIMS}' sessions_dir='${SESSIONS_DIR}' degraded='${DEGRADED% }'"
  exit 2
fi

# ------------------------------------------------------------------
# list membership — case-match on a comma-fenced string. No word splitting,
# so it behaves the same whether the caller's shell splits scalars or not.
# ------------------------------------------------------------------
_in_csv() {
  local needle="$1" list="$2"
  [ -n "$list" ] || return 1
  case ",${list}," in
    *",${needle},"*) return 0 ;;
  esac
  return 1
}

_pane_matches_filter() {
  local pane_id="$1" fleet_id="$2" label="$3" title="$4"
  [ -n "$PANES_FILTER" ] || return 0
  _in_csv "$fleet_id" "$PANES_FILTER" && return 0
  _in_csv "$pane_id"  "$PANES_FILTER" && return 0
  _in_csv "$label"    "$PANES_FILTER" && return 0
  _in_csv "$title"    "$PANES_FILTER" && return 0
  return 1
}

# ------------------------------------------------------------------
# _scan_children — actionable, non-focused managed panes, highest priority first.
# Emits "FOCUSED:<n>" when every actionable pane was skipped for user focus, which
# is how the caller learns about focus without relying on a variable that a command
# substitution would strand in a subshell.
# ------------------------------------------------------------------
_scan_children() {
  [ "$HAS_CHILD_CHANNEL" -eq 1 ] || return 0
  local err="" unch="" don="" line focused=0
  local pane_id notify fleet_id label focus location title
  while IFS='|' read -r pane_id notify fleet_id label focus location title; do
    [ -n "$pane_id" ] || continue
    case "$notify" in unchecked|error|done) ;; *) continue ;; esac
    _pane_matches_filter "$pane_id" "$fleet_id" "$label" "$title" || continue
    if [ "$focus" = "1" ]; then
      focused=$((focused + 1))
      continue
    fi
    line="${pane_id}|${notify}|${label}|${location}"
    case "$notify" in
      error)     err="${err}${line}"$'\n' ;;
      unchecked) unch="${unch}${line}"$'\n' ;;
      done)      don="${don}${line}"$'\n' ;;
    esac
  done <<EOF
$(tmux -L "$SOCKET" list-panes -a -F "$TMUX_FMT" 2>/dev/null)
EOF
  # documented priority error > unchecked > done. fleet.sh's deprecated
  # coordinate-wait took tmux enumeration order instead; this corrects it.
  local result="${err}${unch}${don}"
  if [ -z "$result" ] && [ "$focused" -gt 0 ]; then
    echo "FOCUSED:$focused"
    return 0
  fi
  printf '%s' "$result"
}

_status() {
  if [ "$HAS_CHILD_CHANNEL" -ne 1 ]; then
    echo "STATUS total=0 working=0 done=0 focused=0 idle=0"
    return 0
  fi
  local total=0 working=0 don=0 focused=0 idle=0
  local pane_id notify fleet_id label focus location title
  while IFS='|' read -r pane_id notify fleet_id label focus location title; do
    [ -n "$pane_id" ] || continue
    _pane_matches_filter "$pane_id" "$fleet_id" "$label" "$title" || continue
    total=$((total + 1))
    [ "$focus" = "1" ] && focused=$((focused + 1))
    case "$notify" in
      working) working=$((working + 1)) ;;
      done)    don=$((don + 1)) ;;
      *)       idle=$((idle + 1)) ;;
    esac
  done <<EOF
$(tmux -L "$SOCKET" list-panes -a -F "$TMUX_FMT" 2>/dev/null)
EOF
  echo "STATUS total=$total working=$working done=$don focused=$focused idle=$idle"
}

# ------------------------------------------------------------------
# _scan_tags — one claimable #delegated-<noun> under SESSIONS_DIR.
# Emits "<file>|<tag>|<noun>". The %target modifier decides who may claim:
# targeted work needs the noun in FLEET_TARGETED_CLAIMS and the target to be us;
# untargeted work needs the noun in FLEET_CLAIMS.
# ------------------------------------------------------------------
_scan_tags() {
  [ "$HAS_WORK_CHANNEL" -eq 1 ] || return 0
  local all="$CLAIMS"
  if [ -n "$TARGETED_CLAIMS" ]; then
    if [ -n "$all" ]; then all="${all},${TARGETED_CLAIMS}"; else all="$TARGETED_CLAIMS"; fi
  fi
  local nouns noun file hit target
  nouns=$(printf '%s' "$all" | tr ',' '\n')
  while IFS= read -r noun; do
    [ -n "$noun" ] || continue
    while IFS= read -r file; do
      [ -n "$file" ] || continue
      hit=$(grep -oE "#delegated-${noun}([[:space:]]+%[^[:space:]]+)?" "$file" 2>/dev/null | head -1)
      [ -n "$hit" ] || continue
      case "$hit" in
        *%*) target="${hit##*%}" ;;
        *)   target="" ;;
      esac
      if [ -n "$target" ]; then
        [ -n "$SELF_PANE" ] || continue
        [ "$target" = "$SELF_PANE" ] || continue
        _in_csv "$noun" "$TARGETED_CLAIMS" || continue
      else
        _in_csv "$noun" "$CLAIMS" || continue
      fi
      echo "${file}|${hit}|${noun}"
      return 0
    done <<EOF
$(grep -rlE "#delegated-${noun}([[:space:]]|\$)" "$SESSIONS_DIR" --include='*.md' 2>/dev/null)
EOF
  done <<EOF
$nouns
EOF
  return 0
}

# ------------------------------------------------------------------
# _claim — atomic #delegated-X -> #claimed-X under a mkdir lock, re-verified
# inside the lock so a worker that lost the race hands back nothing.
# ------------------------------------------------------------------
_claim() {
  local file="$1" noun="$2"
  local lock="${file}.await-next.lock"
  local waited=0
  while ! mkdir "$lock" 2>/dev/null; do
    waited=$((waited + 1))
    if [ "$waited" -gt 50 ]; then
      echo "CLAIM_FAILED lock_timeout"
      return 1
    fi
    sleep 0.1
  done
  local rc=1
  if grep -qE "#delegated-${noun}([[:space:]]|$)" "$file" 2>/dev/null; then
    local tmp="${file}.await-next.$$"
    if sed "s/#delegated-${noun}/#claimed-${noun}/g" "$file" > "$tmp" 2>/dev/null && mv "$tmp" "$file" 2>/dev/null; then
      echo "CLAIMED ${file} #claimed-${noun}"
      rc=0
    else
      rm -f "$tmp" 2>/dev/null || true
      echo "CLAIM_FAILED write_failed"
    fi
  else
    echo "CLAIM_FAILED already_taken"
  fi
  rmdir "$lock" 2>/dev/null || true
  return "$rc"
}

# ------------------------------------------------------------------
# coordinator purple layer
# ------------------------------------------------------------------
_disconnect_previous() {
  [ "$DO_CONNECT" -eq 1 ] || return 0
  [ "$HAS_CHILD_CHANNEL" -eq 1 ] || return 0
  [ -n "${TMUX_PANE:-}" ] || return 0
  local prev
  prev=$(tmux -L "$SOCKET" show-option -pqv -t "$TMUX_PANE" @pane_last_coordinated 2>/dev/null)
  [ -n "$prev" ] || return 0
  tmux -L "$SOCKET" set-option -pu -t "$prev" @pane_coordinator_active 2>/dev/null || true
  tmux -L "$SOCKET" set-option -pu -t "$TMUX_PANE" @pane_last_coordinated 2>/dev/null || true
}

_connect() {
  local pane="$1"
  [ "$DO_CONNECT" -eq 1 ] || return 0
  [ -n "${TMUX_PANE:-}" ] || return 0
  [ -n "$pane" ] || return 0
  tmux -L "$SOCKET" set-option -p -t "$pane" @pane_coordinator_active "true" 2>/dev/null || true
  tmux -L "$SOCKET" set-option -p -t "$TMUX_PANE" @pane_last_coordinated "$pane" 2>/dev/null || true
}

_json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

_emit_child() {
  local line="$1" pane state label rest
  pane="${line%%|*}"
  rest="${line#*|}"
  state="${rest%%|*}"
  rest="${rest#*|}"
  label="${rest%%|*}"
  _connect "$pane"
  echo "CHILD $line"
  local cap cap_rc
  cap=$(tmux -L "$SOCKET" capture-pane -t "$pane" -p -S "-${CAPTURE_LINES}" 2>/dev/null)
  cap_rc=$?
  local tail_txt
  tail_txt=$(printf '%s' "$cap" | tail -5 | tr '\n' ' ' | tr -s ' ')
  # A blank screen is a successful capture of nothing, not a failed capture —
  # tmux's own status is the only thing that distinguishes them.
  if [ "$cap_rc" -eq 0 ]; then
    printf '{"pane":"%s","state":"%s","label":"%s","lines":%s,"tail":"%s"}\n' \
      "$(_json_escape "$pane")" "$(_json_escape "$state")" "$(_json_escape "$label")" \
      "$(printf '%s' "$cap" | wc -l | tr -d ' ')" "$(_json_escape "$tail_txt")"
  else
    printf '{"pane":"%s","state":"%s","label":"%s","error":"capture failed"}\n' \
      "$(_json_escape "$pane")" "$(_json_escape "$state")" "$(_json_escape "$label")"
  fi
  _status
}

# One decision point shared by the pre-sweep and every post-wake sweep, so the two
# can never disagree about priority or about children-first.
_resolve_and_emit() {
  local children work first claim_out wfile wnoun
  children=$(_scan_children)
  case "$children" in
    FOCUSED:*)
      # focus is the lowest-ranked outcome: tagged work still wins over it
      work=$(_scan_tags)
      if [ -n "$work" ]; then
        wfile="${work%%|*}"
        wnoun="${work##*|}"
        if claim_out=$(_claim "$wfile" "$wnoun"); then
          echo "WORK $work"
          printf '%s\n' "$claim_out"
          return 0
        fi
      fi
      echo "FOCUSED"
      _status
      return 0
      ;;
    "") ;;
    *)
      first=$(printf '%s' "$children" | head -1)
      _emit_child "$first"
      return 0
      ;;
  esac
  work=$(_scan_tags)
  if [ -n "$work" ]; then
    wfile="${work%%|*}"
    wnoun="${work##*|}"
    if claim_out=$(_claim "$wfile" "$wnoun"); then
      echo "WORK $work"
      printf '%s\n' "$claim_out"
      return 0
    fi
    # lost the race — fall through rather than hand back work we do not hold
  fi
  return 1
}

[ -n "$DEGRADED" ] && echo "DEGRADED ${DEGRADED% }" >&2

_disconnect_previous

# --- sweep-first: a notify that fired while we were busy must not cost a full wait ---
if _resolve_and_emit; then
  exit 0
fi

# --- bounded dual-channel race ---
if [ "$TIMEOUT" -gt 0 ]; then
  RACE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/await-next.XXXXXX")
  WATCHERS=""
  POLL_TAGS=0

  if [ "$HAS_CHILD_CHANNEL" -eq 1 ]; then
    ( while :; do tmux -L "$SOCKET" wait-for coordinator-wake >/dev/null 2>&1 || break; : > "$RACE_DIR/child"; done ) &
    WATCHERS="$WATCHERS $!"
  fi

  if [ "$HAS_WORK_CHANNEL" -eq 1 ]; then
    if command -v fswatch >/dev/null 2>&1; then
      ( fswatch --recursive "$SESSIONS_DIR" 2>/dev/null | while IFS= read -r _; do : > "$RACE_DIR/work"; done ) &
      WATCHERS="$WATCHERS $!"
    else
      # no fswatch: the supervisor re-scans each tick instead. Bounded identically,
      # so the channel degrades in latency and never in liveness.
      POLL_TAGS=1
      echo "DEGRADED no-fswatch-polling-tags" >&2
    fi
  fi

  _reap_watchers() {
    local p
    for p in $WATCHERS; do
      pkill -P "$p" 2>/dev/null || true
      kill "$p" 2>/dev/null || true
    done
    rm -rf "$RACE_DIR" 2>/dev/null || true
  }
  trap '_reap_watchers; exit 130' INT TERM

  TICKS=$(( (TIMEOUT * 1000) / POLL_MS ))
  [ "$TICKS" -lt 1 ] && TICKS=1
  SLEEP_FRAC=$(printf '0.%03d' "$POLL_MS")
  i=0
  RESOLVED=0
  while [ "$i" -lt "$TICKS" ]; do
    if [ -f "$RACE_DIR/child" ] || [ -f "$RACE_DIR/work" ]; then
      rm -f "$RACE_DIR/child" "$RACE_DIR/work" 2>/dev/null || true
      if _resolve_and_emit; then
        RESOLVED=1
        break
      fi
      # A wake is advisory, not a promise. Nothing actionable -> resume the wait
      # rather than reporting a timeout the ceiling has not reached.
    elif [ "$POLL_TAGS" -eq 1 ]; then
      if _resolve_and_emit; then
        RESOLVED=1
        break
      fi
    fi
    sleep "$SLEEP_FRAC"
    i=$((i + 1))
  done

  _reap_watchers
  trap - INT TERM

  [ "$RESOLVED" -eq 1 ] && exit 0
fi

# The ceiling is reached. This is an outcome, not a failure: exit 0.
echo "TIMEOUT"
_status
exit 0
