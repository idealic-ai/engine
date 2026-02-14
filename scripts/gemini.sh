#!/bin/bash
# ~/.claude/engine/scripts/gemini.sh — Generic Gemini API wrapper
#
# Sends a prompt (from stdin) + optional context files to Gemini and outputs
# the response to stdout. Stats and errors go to stderr.
#
# Usage:
#   engine gemini [options] [context-file...]
#
# Options:
#   --temperature <float>   Generation temperature (default: 0.3)
#   --model <name>          Model name (default: gemini-3-pro-preview)
#   --system <text>         System instruction prepended to prompt
#
# Stdin:
#   The prompt text
#
# Stdout:
#   The generated text from Gemini
#
# Context files:
#   Each positional arg is a file path. Files are concatenated after the prompt
#   with filename headers:
#     === FILE: path/to/file.md ===
#     <file contents>
#
# Requires:
#   - GEMINI_API_KEY environment variable (or in .env)
#   - curl, jq

# Source .env if GEMINI_API_KEY not already set
if [ -z "${GEMINI_API_KEY:-}" ]; then
  for envfile in .env "$HOME/.env" "$HOME/.claude/.env"; do
    if [ -f "$envfile" ] && grep -q '^GEMINI_API_KEY=' "$envfile" 2>/dev/null; then
      export GEMINI_API_KEY
      GEMINI_API_KEY=$(grep '^GEMINI_API_KEY=' "$envfile" | head -1 | cut -d= -f2-)
      break
    fi
  done
fi

: "${GEMINI_API_KEY:?GEMINI_API_KEY is required — set it in your environment or .env file}"
export GEMINI_API_KEY

set -euo pipefail

# ---- Defaults ----
TEMPERATURE="0.3"
MODEL="gemini-3-pro-preview"
SYSTEM_INSTRUCTION=""
CONTEXT_FILES=()

# ---- Help ----
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "Usage: engine gemini [options] [context-file...]"
  echo ""
  echo "Sends a prompt (from stdin) + optional context files to Gemini."
  echo "Response is written to stdout."
  echo ""
  echo "Options:"
  echo "  --temperature <float>   Generation temperature (default: 0.3)"
  echo "  --model <name>          Model name (default: gemini-3-pro-preview)"
  echo "  --system <text>         System instruction prepended to prompt"
  echo ""
  echo "Examples:"
  echo "  echo 'Say hello' | engine gemini"
  echo "  echo 'Summarize these files' | engine gemini doc1.md doc2.md"
  echo "  echo 'Review this code' | engine gemini --temperature 0.1 src/main.ts"
  exit 0
fi

# ---- Parse arguments ----
while [ $# -gt 0 ]; do
  case "$1" in
    --temperature)
      TEMPERATURE="${2:?--temperature requires a value}"
      shift 2
      ;;
    --model)
      MODEL="${2:?--model requires a value}"
      shift 2
      ;;
    --system)
      SYSTEM_INSTRUCTION="${2:?--system requires a value}"
      shift 2
      ;;
    -*)
      echo "ERROR: Unknown option: $1" >&2
      echo "Run 'engine gemini --help' for usage." >&2
      exit 1
      ;;
    *)
      CONTEXT_FILES+=("$1")
      shift
      ;;
  esac
done

# ---- Validate dependencies ----
for cmd in curl jq; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "ERROR: $cmd is required but not installed." >&2
    exit 1
  fi
done

# ---- Read prompt from stdin ----
PROMPT=$(cat)
if [ -z "$PROMPT" ]; then
  echo "ERROR: No prompt provided on stdin." >&2
  exit 1
fi

# ---- Concatenate context files ----
CONTEXT=""
TOTAL_SIZE=0
for file in ${CONTEXT_FILES[@]+"${CONTEXT_FILES[@]}"}; do
  if [ ! -f "$file" ]; then
    echo "WARNING: Context file not found, skipping: $file" >&2
    continue
  fi
  FILE_SIZE=$(wc -c < "$file")
  TOTAL_SIZE=$((TOTAL_SIZE + FILE_SIZE))
  CONTEXT="${CONTEXT}
=== FILE: ${file} ===
$(cat "$file")
"
done

if [ "$TOTAL_SIZE" -gt 102400 ]; then
  echo "WARNING: Total context is $(( TOTAL_SIZE / 1024 ))KB — large inputs may hit API limits." >&2
fi

# ---- Build full prompt ----
FULL_PROMPT="${PROMPT}"
if [ -n "$CONTEXT" ]; then
  FULL_PROMPT="${PROMPT}

CONTEXT FILES:
${CONTEXT}"
fi

# ---- Build request body ----
API_URL="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"

if [ -n "$SYSTEM_INSTRUCTION" ]; then
  BODY=$(jq -n \
    --arg prompt "$FULL_PROMPT" \
    --arg system "$SYSTEM_INSTRUCTION" \
    --argjson temp "$TEMPERATURE" \
    '{
      systemInstruction: {
        parts: [{ text: $system }]
      },
      contents: [{
        parts: [{ text: $prompt }]
      }],
      generationConfig: {
        temperature: $temp
      }
    }')
else
  BODY=$(jq -n \
    --arg prompt "$FULL_PROMPT" \
    --argjson temp "$TEMPERATURE" \
    '{
      contents: [{
        parts: [{ text: $prompt }]
      }],
      generationConfig: {
        temperature: $temp
      }
    }')
fi

# ---- Call Gemini ----
FILE_COUNT=${#CONTEXT_FILES[@]}
echo "Calling Gemini (${MODEL}, temp=${TEMPERATURE}, files=${FILE_COUNT})..." >&2

RESPONSE=$(curl -s -X POST "${API_URL}?key=${GEMINI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$BODY")

# ---- Extract result ----
ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error.message // empty')
if [ -n "$ERROR_MSG" ]; then
  echo "ERROR: Gemini API error: $ERROR_MSG" >&2
  exit 1
fi

RESULT=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text // empty')
if [ -z "$RESULT" ]; then
  echo "ERROR: No text in Gemini response." >&2
  echo "Response: $(echo "$RESPONSE" | jq -c '.')" >&2
  exit 1
fi

# ---- Output to stdout ----
printf '%s\n' "$RESULT"
