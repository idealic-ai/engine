#!/bin/bash
# ~/.claude/engine/scripts/rewrite.sh — Document rewriter (thin wrapper around gemini.sh)
#
# Composes a rewrite-specific prompt and delegates to engine gemini.
# Writes the result to an output file with word-count stats.
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
#   - engine gemini (gemini.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

# ---- Read instructions from stdin ----
INSTRUCTIONS=$(cat)
if [ -z "$INSTRUCTIONS" ]; then
  echo "ERROR: No rewrite instructions provided on stdin." >&2
  exit 1
fi

# ---- Compose rewrite prompt ----
SYSTEM_PROMPT="You are a professional document editor. Your task is to rewrite the following document according to the instructions below.

IMPORTANT RULES:
- Output ONLY the rewritten document. No preamble, no explanation, no meta-commentary.
- Preserve markdown formatting (headers, links, code blocks, lists).
- Do not add new information that wasn't in the original.
- Maintain the document's factual accuracy."

# ---- Call engine gemini ----
echo "Rewriting document with Gemini 3 Pro..." >&2

RESULT=$(echo "$INSTRUCTIONS" | "$SCRIPT_DIR/gemini.sh" \
  --system "$SYSTEM_PROMPT" \
  "$INPUT_FILE")

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
