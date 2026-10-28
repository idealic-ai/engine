#!/bin/bash
# ~/.claude/engine/scripts/ask.sh — /ask: non-blocking questions as files (delegator)
#
# Reached as `engine ask …` through the dispatcher's generic scripts/<subcmd>.sh fallback.
# `path` and `serve` live here; `new`, `list` and `answer` delegate to the node CLI in
# tools/ask-app so the file format has exactly one parser.
#
#   engine ask path [seat] [id]          asks root, a seat's dir, or one ask's file
#   engine ask new [--from S] [--to T] [--id ID] [--why …] [--importance …] [--stakes …]
#                  [--context …] [--alternatives …] [--lean …] [--falsifier …] [--dependsOn ID]
#                  [--body-file F]       body (decision-tree markdown) on stdin by default
#   engine ask list [--status open|answered|superseded|all] [--to T] [--seat S] [--json]
#   engine ask answer <seat>/<id> --revision N (--json '{"Q":["CODE"]}' | --decline <reason>) [--by who] [--note text]
#   engine ask serve [dir] [--port N] [--stop]   start (or reuse) the local app on 127.0.0.1
#
# Env: ASK_ROOT (default ~/.claude/data/yarik/asks), ASK_SESSIONS_DIR (default ~/.claude/sessions),
#      FLEET_PANE (default --from), FLEET_PARENT (default --to, else "operator").
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../tools/ask-app" && pwd)"
ASK_ROOT="${ASK_ROOT:-$HOME/.claude/data/yarik/asks}"
export ASK_ROOT

usage() {
  sed -n '6,17p' "$0" | sed 's/^# \{0,1\}//' >&2
}

health() { # health <port> → prints the health JSON, or nothing
  curl -s --max-time 1 -H "Host: 127.0.0.1:$1" "http://127.0.0.1:$1/api/health" 2>/dev/null || true
}

# is_ours <pid> <port> <root>: the pid is THIS root's ask-app, proven two ways — its command line is
# our server for this root and port, and the server on that port reports this pid and root. A pid
# alone proves nothing: pidfiles outlive reboots and crashes, and pids are recycled (MF-2).
is_ours() {
  local pid="$1" port="$2" root="$3" cmd
  [ -n "$pid" ] && [ -n "$port" ] && kill -0 "$pid" 2>/dev/null || return 1
  cmd=$(ps -o command= -p "$pid" 2>/dev/null) || return 1
  case "$cmd" in *"ask-app/src/server.ts --root $root --port $port"*) ;; *) return 1 ;; esac
  health "$port" | grep -qF "\"root\":\"$root\",\"pid\":$pid,"
}

# One serve/stop at a time per root (SF-1). mkdir is atomic; a lock older than 30s is a dead holder's.
take_lock() {
  local lock="$1" i
  for i in $(seq 1 200); do
    if mkdir "$lock" 2>/dev/null; then trap 'rmdir "'"$lock"'" 2>/dev/null || true' EXIT; return 0; fi
    if [ -n "$(find "$lock" -maxdepth 0 -mmin +0.5 2>/dev/null)" ]; then rmdir "$lock" 2>/dev/null || true; fi
    sleep 0.05
  done
  echo "ask serve: could not take $lock" >&2
  exit 1
}

cmd_serve() {
  local root="" port="" stop=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --port) port="$2"; shift 2 ;;
      --stop) stop=1; shift ;;
      -*) echo "ask serve: unknown flag $1" >&2; exit 1 ;;
      *) root="$1"; shift ;;
    esac
  done
  root="${root:-$ASK_ROOT}"
  mkdir -p "$root"
  root="$(cd "$root" && pwd -P)"
  local pidfile="$root/.ask-app.pid" pid="" oldport=""
  take_lock "$root/.ask-app.lock"
  if [ -f "$pidfile" ]; then read -r pid oldport < "$pidfile" || true; fi

  if [ "$stop" = 1 ]; then
    if is_ours "$pid" "$oldport" "$root"; then
      kill "$pid"
      for _ in $(seq 1 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.05; done
      rm -f "$pidfile"
      echo "stopped ask-app pid $pid"
    elif [ -f "$pidfile" ]; then
      rm -f "$pidfile"
      echo "stale pidfile removed: pid ${pid:-?} is not this root's ask-app; nothing killed"
    else
      echo "not running"
    fi
    return 0
  fi

  if is_ours "$pid" "$oldport" "$root"; then
    if [ -z "$port" ] || [ "$port" = "$oldport" ]; then
      echo "reusing ask-app pid $pid" >&2
      echo "http://127.0.0.1:$oldport/"
      return 0
    fi
    echo "ask serve: already running for $root on port $oldport (pid $pid); --stop it first to change port" >&2
    exit 1
  fi
  [ -f "$pidfile" ] && { echo "ask serve: removing stale pidfile (pid ${pid:-?})" >&2; rm -f "$pidfile"; }
  port="${port:-${oldport:-4977}}"

  # A server for this same root already on the port (its pidfile was lost): adopt it, don't refuse.
  local h hpid
  h=$(health "$port")
  if [ -n "$h" ]; then
    hpid=$(echo "$h" | sed -n 's/.*"pid":\([0-9]*\).*/\1/p')
    if is_ours "$hpid" "$port" "$root"; then
      echo "$hpid $port" > "$pidfile"
      echo "adopted running ask-app pid $hpid" >&2
      echo "http://127.0.0.1:$port/"
      return 0
    fi
    echo "ask serve: port $port already serves something else: $h" >&2
    exit 1
  fi
  if [ ! -f "$APP_DIR/dist/index.html" ]; then
    echo "building ask-app client…" >&2
    (cd "$APP_DIR" && npx vite build --logLevel error >&2)
  fi
  nohup node --no-warnings "$APP_DIR/src/server.ts" --root "$root" --port "$port" > "$root/.ask-app.log" 2>&1 &
  pid=$!
  local i
  for i in $(seq 1 50); do
    if is_ours "$pid" "$port" "$root"; then
      echo "$pid $port" > "$pidfile"   # written only once the server is proven up
      echo "started ask-app pid $pid" >&2
      echo "http://127.0.0.1:$port/"
      return 0
    fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  echo "ask serve: server did not come up; log: $root/.ask-app.log" >&2
  tail -5 "$root/.ask-app.log" >&2 || true
  kill "$pid" 2>/dev/null || true
  exit 1
}

sub="${1:-}"
[ $# -gt 0 ] && shift
case "$sub" in
  path)
    if [ $# -eq 0 ]; then echo "$ASK_ROOT"
    elif [ $# -eq 1 ]; then echo "$ASK_ROOT/$1"
    else echo "$ASK_ROOT/$1/$2.md"
    fi
    ;;
  new|list|answer)
    exec node --no-warnings "$APP_DIR/src/cli.ts" "$sub" "$@"
    ;;
  serve)
    cmd_serve "$@"
    ;;
  ""|-h|--help|help)
    usage
    [ -n "$sub" ] || exit 1
    ;;
  *)
    echo "ask: unknown subcommand '$sub'" >&2
    usage
    exit 1
    ;;
esac
