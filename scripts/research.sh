#!/bin/bash
# ~/.claude/scripts/research.sh — Gemini Deep Research API wrapper
#
# Related:
#   (no direct doc/invariant/command references — API wrapper)
#   Protocol: Gemini Deep Research (deep-research-pro-preview-12-2025)
#
# Usage:
#   research.sh <output-file> <<'EOF'
#   Your research query here
#   EOF
#
#   research.sh --continue <interaction-id> <output-file> <<'EOF'
#   Your follow-up question here
#   EOF
#
# Output file format:
#   Line 1: INTERACTION_ID=<id>
#   Line 2+: Full research report from Gemini
#
# Requires:
#   - GEMINI_API_KEY environment variable
#   - curl, jq


: "${GEMINI_API_KEY:=AIzaSyDjT2ZF-1hkkv5W0ALQNaVTVmKYSrDPod0}"
export GEMINI_API_KEY

set -euo pipefail

# ---- Parse arguments ----
CONTINUE_ID=""
if [ "${1:-}" = "--continue" ]; then
  CONTINUE_ID="${2:?Missing interaction ID after --continue}"
  shift 2
fi

OUTPUT_FILE="${1:?Usage: research.sh [--continue <id>] <output-file> (reads query from stdin)}"

# ---- Validate dependencies ----
if [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "ERROR: GEMINI_API_KEY environment variable is not set." >&2
  exit 1
fi

for cmd in curl jq; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "ERROR: $cmd is required but not installed." >&2
    exit 1
  fi
done

# ---- Read query from stdin ----
QUERY=$(cat)
if [ -z "$QUERY" ]; then
  echo "ERROR: No query provided on stdin." >&2
  exit 1
fi

# ---- Build request body ----
API_URL="https://generativelanguage.googleapis.com/v1beta/interactions"
MODEL="deep-research-pro-preview-12-2025"

BODY=$(jq -n \
  --arg input "$QUERY" \
  --arg agent "$MODEL" \
  --arg prev_id "$CONTINUE_ID" \
  '{
    input: $input,
    agent: $agent,
    background: true
  } + (if $prev_id != "" then { previous_interaction_id: $prev_id } else {} end)'
)

# ---- Create interaction ----
echo "Starting Gemini Deep Research..." >&2

RESPONSE=$(curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -d "$BODY")

INTERACTION_ID=$(echo "$RESPONSE" | jq -r '.id // empty')
if [ -z "$INTERACTION_ID" ]; then
  echo "ERROR: Failed to create interaction." >&2
  echo "Response: $RESPONSE" >&2
  exit 1
fi

echo "Interaction created: $INTERACTION_ID" >&2

# Write interaction ID to output file immediately (agent can read this before polling completes)
mkdir -p "$(dirname "$OUTPUT_FILE")"
printf 'INTERACTION_ID=%s\n' "$INTERACTION_ID" > "$OUTPUT_FILE"

echo "Polling for results (this may take several minutes)..." >&2

# ---- Poll until complete ----
POLL_INTERVAL=10
MAX_POLLS=360  # 60 minutes max

for i in $(seq 1 $MAX_POLLS); do
  sleep $POLL_INTERVAL

  RESULT=$(curl -s -X GET "$API_URL/$INTERACTION_ID" \
    -H "x-goog-api-key: $GEMINI_API_KEY")

  STATUS=$(echo "$RESULT" | jq -r '.status // "unknown"')

  case "$STATUS" in
    completed)
      echo "Research complete." >&2
      REPORT=$(echo "$RESULT" | jq -r '.outputs[-1].text // "No output text found"')
      printf '%s\n' "$REPORT" >> "$OUTPUT_FILE"
      echo "Results written to $OUTPUT_FILE" >&2
      exit 0
      ;;
    failed)
      ERROR=$(echo "$RESULT" | jq -r '.error.message // "Unknown error"')
      echo "ERROR: Research failed: $ERROR" >&2
      exit 1
      ;;
    *)
      # Still running — log progress every 6 polls (60s)
      if (( i % 6 == 0 )); then
        ELAPSED=$((i * POLL_INTERVAL))
        echo "Still researching... (${ELAPSED}s elapsed, status: $STATUS)" >&2
      fi
      ;;
  esac
done

echo "ERROR: Research timed out after $((MAX_POLLS * POLL_INTERVAL))s." >&2
echo "Interaction ID: $INTERACTION_ID (can resume with --continue)" >&2
exit 1
