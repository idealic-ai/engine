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
#                  v2 card fields: [--stake …] [--unblocks …] [--related …] [--counter …] [--evidence "a ; b"]
#                  [--rank "2 of 5"] [--topic …] [--tickets "IDE-1, IDE-2"] [--confidence …] [--reversible …]
#                  [--verify …] [--ifUnanswered …] [--neededBy …] [--askedBy …] [--blocks …] [--reserved-for operator]
#   engine ask list [--status open|answered|declined|settled|superseded|all|a,b] [--to T] [--seat S] [--json]
#   engine ask answer <seat>/<id> --revision N (--json '{"Q":["CODE"]}' | --decline <reason>) [--note text]
#                  --relayed-from operator --note "<when/where>"   a seat records the operator's answer
#   engine ask revise <seat>/<id> [card flags as for new] [--keep-body]   the asker revises an open ask
#   engine ask draft  <seat>/<id> --revision N (--json … | --decline <reason>)   save in the file, push nothing
#   engine ask send [<seat>/<id> …]       settle YOUR drafts (all of yours, by default); ONE push per seat
#   engine ask discard <seat>/<id>       drop your draft
#   engine ask read <seat>/<id> [--full] | read --unread [--seat S]   print the answer; stamps YOUR read
#   engine ask acted <seat>/<id> "<summary>" [--ruled-in-chat "<who, when>"]   stamps acted (recipients only)
#   engine ask forward <seat>/<id> --to <seat>   the holder (to:), or its parent, moves it one rung
#   engine ask supersede <seat>/<old-id> --by <seat>/<new-id>   the asker, its manager or the operator retires an open ask for its replacement
#   engine ask serve [dir] [--port N] [--stop]   start (or reuse) the local app on 127.0.0.1
#
# Identity: a seat (FLEET_PANE set) acts as itself; --by naming anyone else, or operator, is refused.
#      With no FLEET_PANE the shell is not a seat and --by is required (the operator: --by operator).
# Env: ASK_ROOT (default ~/.claude/data/yarik/asks), ASK_SESSIONS_DIR (default ~/.claude/sessions),
#      the actor and default --from is this pane's LIVE window:@pane_label (tmux, via TMUX_PANE),
#      default --to its live @pane_parent (none → "operator"); FLEET_PANE / FLEET_PARENT, run.sh's
#      launch-time cache, are used only when tmux cannot be read, and a stale one is warned about
#      (hop.sh's rule). ASK_LIVE_PANES / ASK_TMUX_SOCKET: test seams for that read.
#      FLEET_MANAGES (the panes whose silent asks you may forward as their parent),
#      ASK_LINEAR_ENV (an env file holding LINEAR_API_KEY, for ticket tooltips; default: the working
#      project's .env.local, then .env, resolved as scripts/env-lib.sh does — the server reads it,
#      never argv, the page or its own environment), PROVE_S3_ENV (the env file naming the proof
#      store, for the proofs list), ASK_APP_DIST (the built client to serve). serve remembers both
#      env files in <root>/.ask-app.env and reuses them when a later start does not set them, so a
#      restart from another working directory keeps its tickets and proofs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../tools/ask-app" && pwd)"
ASK_ROOT="${ASK_ROOT:-$HOME/.claude/data/yarik/asks}"
export ASK_ROOT
APP_DIST="${ASK_APP_DIST:-$APP_DIR/dist}"

usage() {
  sed -n '6,38p' "$0" | sed 's/^# \{0,1\}//' >&2
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
# NEW-2: the age is computed from stat, because BSD find rejects `-mmin +0.5` and the recovery never ran.
lock_age() { # seconds since the lock dir was made, or empty when it is gone
  local m; m=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null) || return 0
  echo $(( $(date +%s) - m ))
}
take_lock() {
  local lock="$1" i age
  for i in $(seq 1 200); do
    if mkdir "$lock" 2>/dev/null; then trap 'rmdir "'"$lock"'" 2>/dev/null || true' EXIT; return 0; fi
    age=$(lock_age "$lock")
    if [ -n "$age" ] && [ "$age" -gt 30 ]; then
      # Rename before removing, so two waiters cannot each remove the other's fresh lock.
      mv "$lock" "$lock.stale.$$" 2>/dev/null && rmdir "$lock.stale.$$" 2>/dev/null
      echo "ask serve: recovered a stale lock (${age}s old)" >&2
      continue
    fi
    sleep 0.05
  done
  echo "ask serve: could not take $lock" >&2
  exit 1
}

# S9 (round 2): the client is identified by its BUILD ID — a hash of src/client/**, format.ts and
# the kit sheets main.tsx imports (src/build-id.ts) — never by mtimes, which a checkout, a merge or a
# restored copy moves either way. The server refuses a client whose id is not its sources'.
want_build_id() { node --no-warnings "$APP_DIR/src/build-id.ts"; }
have_build_id() { node --no-warnings "$APP_DIR/src/build-id.ts" "$1"; }

# ensure_client: rebuild APP_DIST only when its build id differs from the sources'. The build goes
# into a temp dir beside it and is moved into place under a lock on the dist itself, so a server
# reading the dist never sees it half-written or emptied, and two serves never build into it at once.
ensure_client() {
  local want lock="$APP_DIST.lock" tmp old age i
  want=$(want_build_id) || { echo "ask serve: cannot compute the client build id" >&2; exit 1; }
  [ "$(have_build_id "$APP_DIST")" = "$want" ] && return 0
  for i in $(seq 1 1200); do
    mkdir "$lock" 2>/dev/null && break
    age=$(lock_age "$lock")
    if [ -n "$age" ] && [ "$age" -gt 300 ]; then
      mv "$lock" "$lock.stale.$$" 2>/dev/null && rmdir "$lock.stale.$$" 2>/dev/null
      echo "ask serve: recovered a stale client-build lock (${age}s old)" >&2
      continue
    fi
    [ "$i" = 1200 ] && { echo "ask serve: could not take $lock" >&2; exit 1; }
    sleep 0.1
  done
  # Another serve may have built it while we waited.
  if [ "$(have_build_id "$APP_DIST")" = "$want" ]; then rmdir "$lock"; return 0; fi
  tmp="$APP_DIST.tmp-$$"; old="$APP_DIST.old-$$"
  echo "building ask-app client $want into ${APP_DIST}…" >&2
  # ASK_VITE_BUILD: a test seam standing in for `npx vite build` (it gets the same --outDir args).
  if ! (cd "$APP_DIR" && ${ASK_VITE_BUILD:-npx vite build} --logLevel error --outDir "$tmp" --emptyOutDir >&2) \
     || [ "$(have_build_id "$tmp")" != "$want" ]; then
    rm -rf "$tmp"; rmdir "$lock"
    echo "ask serve: the client build failed or is not build $want; $APP_DIST is unchanged" >&2
    exit 1
  fi
  # SHOULD-5: an unstamped (v1) client is kept aside as the rollback, never deleted.
  if [ -e "$APP_DIST" ] && [ -z "$(have_build_id "$APP_DIST")" ]; then
    old="$APP_DIST.v1-backup-$(date +%Y%m%d-%H%M%S)"
    mv "$APP_DIST" "$old"
    echo "ask serve: the unstamped client is kept at $old (rollback)" >&2
    mv "$tmp" "$APP_DIST"
  else
    if [ -e "$APP_DIST" ]; then mv "$APP_DIST" "$old"; fi
    mv "$tmp" "$APP_DIST"
    rm -rf "$old"
  fi
  rmdir "$lock"
}

# resolve_linear_env: export ASK_LINEAR_ENV as the working project's .env.local, else .env — the
# first that holds LINEAR_API_KEY — anchored by scripts/env-lib.sh. No project, no key: tooltips off.
resolve_linear_env() {
  [ -n "${ASK_LINEAR_ENV:-}" ] && return 0
  local files f
  files=$( (source "$SCRIPT_DIR/env-lib.sh" && env_key_files) 2>/dev/null) || return 0
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    if grep -qE '^[[:space:]]*(export[[:space:]]+)?LINEAR_API_KEY[[:space:]]*=' "$f"; then
      export ASK_LINEAR_ENV="$f"
      return 0
    fi
  done <<< "$files"
  return 0
}

# remember_serve_env <file>: the server's env-file settings outlive the shell that started it. An
# unset ASK_LINEAR_ENV or PROVE_S3_ENV is taken from <file> when the path it names still exists, then
# the Linear key falls back to the working project's; whatever is set is exported and written back.
# The file holds paths only, never a key.
remember_serve_env() {
  local file="$1" name val
  if [ -f "$file" ]; then
    while IFS='=' read -r name val; do
      case "$name" in ASK_LINEAR_ENV|PROVE_S3_ENV) ;; *) continue ;; esac
      [ -n "${!name:-}" ] || { [ -f "$val" ] && export "$name=$val"; }
    done < "$file"
  fi
  resolve_linear_env
  [ -n "${PROVE_S3_ENV:-}" ] && export PROVE_S3_ENV
  : > "$file"
  for name in ASK_LINEAR_ENV PROVE_S3_ENV; do
    [ -n "${!name:-}" ] && printf '%s=%s\n' "$name" "${!name}" >> "$file"
  done
  return 0
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

  # NEW-1: discover this root's servers by ROOT, not by the one port the pidfile names — a lost or
  # wrong pidfile must not hide a running server. Every hit is still proven with is_ours.
  local found=() hit hport
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    hport=$(ps -o command= -p "$hit" 2>/dev/null | sed -n 's/.*ask-app\/src\/server\.ts --root .* --port \([0-9]*\).*/\1/p')
    if [ -n "$hport" ] && is_ours "$hit" "$hport" "$root"; then found+=("$hit $hport"); fi
  # N4: pgrep matches a REGEX, so the root (which may hold + or parentheses) is not in the pattern;
  # every ask-app server is listed and is_ours matches the root as a fixed string.
  done < <(pgrep -f 'ask-app/src/server\.ts --root ' 2>/dev/null || true)

  if [ "$stop" = 1 ]; then
    local stopped=0 entry spid
    for entry in "${found[@]+"${found[@]}"}"; do
      spid=${entry%% *}
      kill "$spid"
      for _ in $(seq 1 50); do kill -0 "$spid" 2>/dev/null || break; sleep 0.05; done
      echo "stopped ask-app pid $spid"
      stopped=1
    done
    if [ -f "$pidfile" ]; then
      rm -f "$pidfile"
      [ "$stopped" = 1 ] || echo "stale pidfile removed: pid ${pid:-?} is not this root's ask-app; nothing killed"
    elif [ "$stopped" = 0 ]; then
      echo "not running"
    fi
    return 0
  fi

  if [ "${#found[@]}" -gt 1 ]; then
    echo "ask serve: ${#found[@]} servers are running for $root (${found[*]}); --stop stops them all" >&2
    exit 1
  fi
  if [ "${#found[@]}" -eq 1 ]; then
    local fpid=${found[0]%% *} fport=${found[0]##* }
    if [ -n "$port" ] && [ "$port" != "$fport" ]; then
      echo "ask serve: already running for $root on port $fport (pid $fpid); --stop it first to change port" >&2
      exit 1
    fi
    [ "$fpid $fport" = "$pid $oldport" ] && echo "reusing ask-app pid $fpid" >&2 || echo "adopted running ask-app pid $fpid" >&2
    echo "$fpid $fport" > "$pidfile"
    echo "http://127.0.0.1:$fport/"
    return 0
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
  # S9: the client this server will serve is the one its sources build (see ensure_client).
  ensure_client
  # The Linear key for ticket tooltips reaches the server through the environment (a file path),
  # never argv: argv is readable by every process on the machine through ps. S7: the file is the
  # working project's, found the way every engine credential is (env-lib.sh), never a fixed path.
  remember_serve_env "$root/.ask-app.env"
  # N1: an exported LINEAR_API_KEY would sit in the server's environment block, readable through
  # `ps eww`, for the server's whole life; it is dropped before the server starts.
  nohup env -u LINEAR_API_KEY ASK_APP_DIST="$APP_DIST" node --no-warnings "$APP_DIR/src/server.ts" --root "$root" --port "$port" > "$root/.ask-app.log" 2>&1 &
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
  new|revise|list|answer|draft|send|discard|read|acted|forward|supersede)
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
