#!/bin/bash
# ~/.claude/engine/scripts/rewrite.sh — Gemini document rewriter
#
# Uses Gemini 3 Pro (generateContent API) to rewrite a document
# based on instructions piped via stdin.
#
# Usage:
#   engine rewrite <input-file> <output-file> <<'EOF'
#   Make this document shorter and more concise.
#   EOF
#
# Arguments:
#   <input-file>   Path to the document to rewrite
#   <output-file>  Path where the rewritten document will be written
#
# Stdin:
#   Rewrite instructions (composed by the /rewrite skill based on mode)
#
# Requires:
#   - GEMINI_API_KEY environment variable
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

# ---- Help ----
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "Usage: engine rewrite <input-file> <output-file>"
  echo ""
  echo "Rewrites a document using Gemini 3 Pro based on instructions from stdin."
  echo ""
  echo "Arguments:"
  echo "  <input-file>   Path to the document to rewrite"
  echo "  <output-file>  Path where the rewritten document will be written"
  echo ""
  echo "Stdin:"
  echo "  Rewrite instructions (e.g., 'Make this shorter and more concise')"
  echo ""
  echo "Examples:"
  echo "  engine rewrite doc.md doc-rewritten.md <<< 'Make shorter and more concise'"
  echo "  echo 'Rewrite for executive audience' | engine rewrite report.md report-exec.md"
  exit 0
fi

# ---- Parse arguments ----
INPUT_FILE="${1:?Usage: engine rewrite <input-file> <output-file> (instructions from stdin)}"
OUTPUT_FILE="${2:?Usage: engine rewrite <input-file> <output-file> (instructions from stdin)}"

# ---- Validate ----
if [ ! -f "$INPUT_FILE" ]; then
  echo "ERROR: Input file not found: $INPUT_FILE" >&2
  exit 1
fi

for cmd in curl jq; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "ERROR: $cmd is required but not installed." >&2
    exit 1
  fi
done

# ---- Read instructions from stdin ----
INSTRUCTIONS=$(cat)
if [ -z "$INSTRUCTIONS" ]; then
  echo "ERROR: No rewrite instructions provided on stdin." >&2
  exit 1
fi

# ---- Read input document ----
DOCUMENT=$(cat "$INPUT_FILE")
if [ -z "$DOCUMENT" ]; then
  echo "ERROR: Input file is empty: $INPUT_FILE" >&2
  exit 1
fi

# ---- Warn on large documents ----
DOC_SIZE=$(wc -c < "$INPUT_FILE")
if [ "$DOC_SIZE" -gt 102400 ]; then
  echo "WARNING: Input file is $(( DOC_SIZE / 1024 ))KB — large documents may hit API limits." >&2
fi

# ---- Build prompt ----
PROMPT="You are a professional document editor. Your task is to rewrite the following document according to the instructions below.

INSTRUCTIONS:
${INSTRUCTIONS}

IMPORTANT RULES:
- Output ONLY the rewritten document. No preamble, no explanation, no meta-commentary.
- Preserve markdown formatting (headers, links, code blocks, lists).
- Do not add new information that wasn't in the original.
- Maintain the document's factual accuracy.

DOCUMENT TO REWRITE:
${DOCUMENT}"

# ---- Build request body ----
MODEL="gemini-3-pro-preview"
API_URL="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"

BODY=$(jq -n \
  --arg prompt "$PROMPT" \
  '{
    contents: [{
      parts: [{
        text: $prompt
      }]
    }],
    generationConfig: {
      temperature: 0.3
    }
  }')

# ---- Call Gemini ----
echo "Rewriting document with Gemini 3 Pro..." >&2

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

# ---- Write output ----
mkdir -p "$(dirname "$OUTPUT_FILE")"
printf '%s\n' "$RESULT" > "$OUTPUT_FILE"

echo "Rewrite complete: $OUTPUT_FILE" >&2

# ---- Stats ----
ORIG_LINES=$(wc -l < "$INPUT_FILE" | tr -d ' ')
NEW_LINES=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
ORIG_WORDS=$(wc -w < "$INPUT_FILE" | tr -d ' ')
NEW_WORDS=$(wc -w < "$OUTPUT_FILE" | tr -d ' ')

echo "  Original: ${ORIG_LINES} lines, ${ORIG_WORDS} words" >&2
echo "  Rewritten: ${NEW_LINES} lines, ${NEW_WORDS} words" >&2

if [ "$ORIG_WORDS" -gt 0 ]; then
  RATIO=$(( (NEW_WORDS * 100) / ORIG_WORDS ))
  echo "  Ratio: ${RATIO}% of original" >&2
fi
