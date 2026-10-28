#!/usr/bin/env bash
# Tests for embed-local-gate.sh: the readiness gate every search wrapper sources.
# Serves a fake /api/tags from a temp dir with python3's http.server, so no real
# Ollama is needed. Exit 0 = all pass, 1 = a failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/../embed-local-gate.sh"
# shellcheck source=/dev/null
. "$GATE"

FAILS=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s — %s\n' "$1" "$2"; FAILS=$((FAILS + 1)); }

WORK="$(mktemp -d)"
SERVER_PID=""
cleanup() { [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK/www/api"
printf '{"models":[{"name":"embeddinggemma:latest","model":"embeddinggemma:latest"},{"name":"gemma3:27b"}]}' > "$WORK/www/api/tags"
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
(cd "$WORK/www" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1) &
SERVER_PID=$!
disown "$SERVER_PID" 2>/dev/null || true
for _ in $(seq 1 50); do curl -sf -m 1 "http://127.0.0.1:$PORT/api/tags" >/dev/null 2>&1 && break; sleep 0.1; done

# 1. ready: the model is listed under a tag
if ENGINE_EMBED_ENDPOINT="http://127.0.0.1:$PORT/" embed_local_gate 2>"$WORK/err"; then
  pass "gate passes when the runner lists embeddinggemma:latest"
else
  fail "ready" "gate refused: $(cat "$WORK/err")"
fi

# 2. MODEL_ABSENT: the runner answers, the model is not there
if ENGINE_EMBED_ENDPOINT="http://127.0.0.1:$PORT" ENGINE_EMBED_MODEL="nomic-embed-text" embed_local_gate 2>"$WORK/err"; then
  fail "model absent" "gate passed for a model the runner does not list"
elif grep -q 'MODEL_ABSENT' "$WORK/err" && grep -q 'ollama pull nomic-embed-text' "$WORK/err"; then
  pass "an unlisted model is MODEL_ABSENT, naming the pull command"
else
  fail "model absent" "wrong message: $(cat "$WORK/err")"
fi

# 3. a prefix of a listed name is not a match ("embedding" vs "embeddinggemma")
if ENGINE_EMBED_ENDPOINT="http://127.0.0.1:$PORT" ENGINE_EMBED_MODEL="embedding" embed_local_gate 2>/dev/null; then
  fail "prefix" "gate accepted a prefix of a listed model name"
else
  pass "a name prefix does not count as the model"
fi

# 3b. another tag of the same family is a different model to /api/embed
printf '{"models":[{"name":"embeddinggemma:300m"}]}' > "$WORK/www/api/tags"
if ENGINE_EMBED_ENDPOINT="http://127.0.0.1:$PORT" embed_local_gate 2>/dev/null; then
  fail "other tag" "gate accepted embeddinggemma:300m for embeddinggemma"
else
  pass "embeddinggemma:300m alone does not satisfy embeddinggemma (Ollama means :latest)"
fi
if ENGINE_EMBED_ENDPOINT="http://127.0.0.1:$PORT" ENGINE_EMBED_MODEL="embeddinggemma:300m" embed_local_gate 2>/dev/null; then
  pass "an explicitly tagged model matches its own tag"
else
  fail "explicit tag" "gate refused embeddinggemma:300m when asked for it"
fi
printf '{"models":[{"name":"embeddinggemma:latest","model":"embeddinggemma:latest"},{"name":"gemma3:27b"}]}' > "$WORK/www/api/tags"

# 4. RUNNER_ABSENT: nothing listening
DEAD=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
if ENGINE_EMBED_ENDPOINT="http://127.0.0.1:$DEAD" embed_local_gate 2>"$WORK/err"; then
  fail "runner absent" "gate passed with nothing listening"
elif grep -q 'RUNNER_ABSENT' "$WORK/err" && grep -q "127.0.0.1:$DEAD" "$WORK/err"; then
  pass "no listener is RUNNER_ABSENT, naming the endpoint"
else
  fail "runner absent" "wrong message: $(cat "$WORK/err")"
fi

# 5. no GEMINI_API_KEY is consulted: a run with it unset still passes
if env -u GEMINI_API_KEY ENGINE_EMBED_ENDPOINT="http://127.0.0.1:$PORT" bash -c ". '$GATE' && embed_local_gate" 2>/dev/null; then
  pass "the gate needs no GEMINI_API_KEY"
else
  fail "no key" "gate failed with GEMINI_API_KEY unset"
fi

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
