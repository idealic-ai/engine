# shellcheck shell=bash
# Sourced by publish-s3.sh. Defines prove_seat_resolve, which answers "which seat is publishing
# this page?" so the page can tell its reader whom to message back.
#
# prove_seat_resolve  →  prints "<seat>\t<source>\t<via>" on stdout, always exit 0.
#   source is one of: PROVE_SEAT · session-file · FLEET_PANE · unknown (seat empty)
#   via    is the live seat an explicit PROVE_SEAT overrode, when the two differ; else empty.
#
# Order, first that yields a non-empty name wins:
#   1. PROVE_SEAT: an explicit per-invocation value beats an inferred one. It lets a conductor
#      route replies to the worker seat that owns a board. A stale export would silently restamp
#      every page, so the live seat it overrode is returned as `via` and printed on the page.
#   2. the LIVE seat: walk this process's ancestors; the first ancestor pid that has
#      <sessions>/<pid>.json with a non-empty "name" is the publishing Claude session.
#      Measured 2026-10-28 from a dispatched subagent: the Bash tool's shell is a child of the
#      parent session's `claude` process, so a subagent publishes as its parent seat
#      (manager:director), which is the seat that can actually receive a reply.
#   3. FLEET_PANE (set in fleet tmux panes).
# Only ANCESTORS count. A seat file for some other live session is never taken: picking "a"
# running claude is the guess this exists to avoid. Registry files for dead pids linger, and a
# dead pid can be REUSED by an ancestor shell, so a file that records procStart is taken only when
# it equals that pid's real start time (`ps -o lstart=` in UTC, the format the file was written in).
#
# PROVE_SEAT_SESSIONS_DIR (default ~/.claude/sessions) and PROVE_SEAT_START_PID (default: this
# shell) exist for the tests.
_prove_seat_live() {
  local dir="${PROVE_SEAT_SESSIONS_DIR:-$HOME/.claude/sessions}"
  local pid="${PROVE_SEAT_START_PID:-$$}" info name want got hops=0 parent
  while [ -n "$pid" ] && [ "$pid" -ge 1 ] 2>/dev/null && [ "$hops" -lt 64 ]; do
    if [ -f "$dir/$pid.json" ]; then
      info="$(python3 -c 'import json,sys
try: d = json.load(open(sys.argv[1]))
except Exception: d = {}
print((d.get("name") or "").strip()); print(" ".join((d.get("procStart") or "").split()))' "$dir/$pid.json" 2>/dev/null || true)"
      name="$(printf '%s\n' "$info" | sed -n 1p)"
      want="$(printf '%s\n' "$info" | sed -n 2p)"
      if [ -n "$name" ] && [ -n "$want" ]; then
        got="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$pid" 2>/dev/null | tr -s ' ' | sed 's/^ *//; s/ *$//')"
        [ "$got" = "$want" ] || name=""
      fi
      if [ -n "$name" ]; then
        printf '%s\t%s\n' "$name" "session-file"
        return 0
      fi
    fi
    [ "$pid" -le 1 ] && break
    parent="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ "$parent" = "$pid" ] && break
    pid="$parent"
    hops=$((hops + 1))
  done
  if [ -n "${FLEET_PANE:-}" ]; then
    printf '%s\t%s\n' "$FLEET_PANE" "FLEET_PANE"
  else
    printf '\t%s\n' "unknown"
  fi
}

prove_seat_resolve() {
  local live liveSeat
  live="$(_prove_seat_live)"
  liveSeat="${live%%	*}"
  if [ -n "${PROVE_SEAT:-}" ]; then
    if [ -n "$liveSeat" ] && [ "$liveSeat" != "$PROVE_SEAT" ]; then
      printf '%s\t%s\t%s\n' "$PROVE_SEAT" "PROVE_SEAT" "$liveSeat"
    else
      printf '%s\t%s\t\n' "$PROVE_SEAT" "PROVE_SEAT"
    fi
  else
    printf '%s\t\n' "$live"
  fi
  return 0
}
