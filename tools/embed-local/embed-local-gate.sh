#!/usr/bin/env bash
# embed-local-gate.sh — the ONE readiness gate for the engine's local embeddings.
#
# Sourced by every search wrapper (scripts/{session,doc}-search.sh and
# tools/{session-search,doc-search}/*.sh). It replaces the GEMINI_API_KEY gate:
# the search tools embed through tools/embed-local (Ollama embeddinggemma,
# 768-d) and there is NO remote fallback, so what must be true before a run is
# "a runner answers and has the model", not "a key is set".
#
#   . embed-local-gate.sh && embed_local_gate || exit 1
#
# Reads the same overrides as tools/embed-local/src/config.ts:
#   ENGINE_EMBED_ENDPOINT (default http://127.0.0.1:11434), ENGINE_EMBED_MODEL
#   (default embeddinggemma). Prints one named line to stderr on failure:
#   RUNNER_ABSENT or MODEL_ABSENT, matching the TypeScript client's codes.

embed_local_gate() {
  local endpoint="${ENGINE_EMBED_ENDPOINT:-http://127.0.0.1:11434}"
  local model="${ENGINE_EMBED_MODEL:-embeddinggemma}"
  local tags
  endpoint="${endpoint%/}"

  if ! command -v curl >/dev/null 2>&1; then
    # Cannot probe; let the client report its own named failure.
    return 0
  fi

  if ! tags=$(curl -sf -m 3 "$endpoint/api/tags" 2>/dev/null); then
    echo "[embed-local] RUNNER_ABSENT: no embedding runner is answering at $endpoint. Start Ollama (\`ollama serve\` or the app), or set ENGINE_EMBED_ENDPOINT. There is no remote fallback." >&2
    return 1
  fi

  # Ollama resolves an untagged name to ":latest", so "embeddinggemma" matches only
  # "embeddinggemma" or "embeddinggemma:latest" — another tag (":300m") is a
  # different model to /api/embed. Dots are escaped so they match only dots.
  # A bare grep on the JSON keeps this free of a jq dependency.
  local pat="${model//./\\.}"
  case "$model" in *:*) ;; *) pat="${pat}(:latest)?" ;; esac
  if ! printf '%s' "$tags" | grep -qE "\"(name|model)\":\"${pat}\""; then
    echo "[embed-local] MODEL_ABSENT: $endpoint does not have $model. Fetch it once with \`ollama pull $model\`." >&2
    return 1
  fi
  return 0
}
