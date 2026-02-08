#!/bin/bash
# ~/.claude/scripts/escape-tags.sh — Retroactive backtick escaping for tag references
#
# Finds bare tag references (#word-word) on non-Tags lines and wraps them in backticks.
# Tags on the **Tags**: line are left bare (they are actual tags, not references).
# Tags already inside backticks are left alone.
#
# Usage:
#   escape-tags.sh [path]              # Preview diff (default: sessions/)
#   escape-tags.sh [path] --apply      # Apply changes
#
# Related:
#   Commands: (~/.claude/standards/COMMANDS.md)
#     §CMD_ESCAPE_TAG_REFERENCES — Escaping protocol for tag references
#
# Tag pattern: #word-word (kebab-case with at least one hyphen)
# Examples matched: #needs-review, #done-delegation, #active-alert, #current-debrief
# Examples NOT matched: #123 (issue numbers), #hashtag (single word)

set -euo pipefail

SEARCH_PATH="${1:-sessions/}"
APPLY=0
if [[ "${2:-}" == "--apply" ]]; then
  APPLY=1
fi

# Tag pattern: # followed by word-chars, hyphen, word-chars (at least one hyphen)
TAG_PATTERN='#[a-z]+-[a-z-]+'

# Find all .md files
find "$SEARCH_PATH" -name '*.md' -type f | sort | while read -r file; do
  # Process each file: find lines with bare tags that are NOT on the Tags line
  # and NOT already backtick-escaped

  tmpfile=$(mktemp)
  changed=0
  line_num=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))

    # Skip the Tags line — those are actual tags
    if echo "$line" | grep -q '^\*\*Tags\*\*:'; then
      echo "$line" >> "$tmpfile"
      continue
    fi

    # Check if this line has any bare tag references (not already backticked)
    newline="$line"
    if echo "$line" | grep -qE "$TAG_PATTERN"; then
      # Process: wrap bare tags in backticks, skip already-backticked ones
      # Strategy: use perl for negative lookbehind/ahead (more reliable than sed)
      newline=$(echo "$line" | perl -pe "s/(?<!\`)($TAG_PATTERN)(?!\`)/\`\$1\`/g")

      if [[ "$newline" != "$line" ]]; then
        changed=1
        if [[ $APPLY -eq 0 ]]; then
          echo "--- $file:$line_num"
          echo "-  $line"
          echo "+  $newline"
          echo ""
        fi
      fi
    fi

    echo "$newline" >> "$tmpfile"
  done < "$file"

  if [[ $changed -eq 1 ]] && [[ $APPLY -eq 1 ]]; then
    cp "$tmpfile" "$file"
    echo "Updated: $file"
  fi

  rm -f "$tmpfile"
done

if [[ $APPLY -eq 0 ]]; then
  echo "---"
  echo "Preview only. Run with --apply to make changes."
fi
