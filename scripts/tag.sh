#!/bin/bash
# ~/.claude/scripts/tag.sh — Semantic tag management for workflow engine
#
# Related:
#   Docs: (~/.claude/docs/)
#     DIRECTIVES_SYSTEM.md — Tag protocol, escaping convention
#     DAEMON.md — Tag-based dispatch
#   Invariants: (~/.claude/directives/INVARIANTS.md)
#     ¶INV_CLAIM_BEFORE_WORK — Tag swap pattern
#   Commands: (~/.claude/directives/COMMANDS.md)
#     §CMD_ESCAPE_TAG_REFERENCES — Backtick escaping protocol
#     §CMD_TAG_FILE — Add tag to file
#     §CMD_UNTAG_FILE — Remove tag from file
#     §CMD_SWAP_TAG_IN_FILE — Atomic tag swap
#     §CMD_FIND_TAGGED_FILES — Tag discovery
#
# Usage:
#   tag.sh add    <file> <tag>                          # Add tag to Tags line
#   tag.sh remove <file> <tag>                          # Remove tag from Tags line
#   tag.sh remove <file> <tag> --inline <line>          # Remove inline tag at line
#   tag.sh swap   <file> <old-tag> <new-tag>            # Swap tag on Tags line
#   tag.sh swap   <file> <old1,old2> <new-tag>          # Swap any of several tags on Tags line
#   tag.sh swap   <file> <old-tag> <new-tag> --inline N # Swap inline tag at line N
#   tag.sh find   <tag> [path]                          # Find files with tag (default: sessions/)
#   tag.sh find   <tag> [path] --context                # Find with line numbers + lookaround
#
# Tags live on a **Tags**: line immediately after the H1 heading.
# All tag arguments should include the # prefix (e.g., #needs-review).
#
# Discovery (find) uses two-pass search:
#   Pass 1: Tags line (line 2) — structured, zero noise
#   Pass 2: Inline body — bare tags only (backtick-escaped references filtered out)
#
# Examples:
#   tag.sh add    sessions/.../BRAINSTORM.md '#needs-review'
#   tag.sh remove sessions/.../BRAINSTORM.md '#needs-review'
#   tag.sh remove sessions/.../LOG.md '#needs-decision' --inline 47
#   tag.sh swap   sessions/.../BRAINSTORM.md '#needs-review' '#done-review'
#   tag.sh swap   sessions/.../LOG.md '#needs-decision' '#done-decision' --inline 47
#   tag.sh find   '#needs-review'
#   tag.sh find   '#needs-review' sessions/ --context

set -euo pipefail

ACTION="${1:?Usage: tag.sh add|remove|swap|find <args>}"

case "$ACTION" in
  add)
    FILE="${2:?Missing file argument}"
    TAG="${3:?Missing tag argument}"
    # Ensure **Tags**: line exists after H1 (line 1)
    grep -q '^\*\*Tags\*\*:' "$FILE" || printf '1a\n**Tags**:\n.\nw\nq\n' | ed -s "$FILE"
    # Append tag if not already present on Tags line
    grep '^\*\*Tags\*\*:' "$FILE" | grep -q "$TAG" || sed -i '' "/^\*\*Tags\*\*:/ s/$/ $TAG/" "$FILE"
    ;;

  remove)
    FILE="${2:?Missing file argument}"
    TAG="${3:?Missing tag argument}"
    if [[ "${4:-}" == "--inline" ]]; then
      LINE="${5:?Missing line number for --inline}"
      # Verify tag exists at the specified line
      if ! sed -n "${LINE}p" "$FILE" | grep -q "$TAG"; then
        echo "ERROR: Tag '$TAG' not found at line $LINE of $FILE" >&2
        exit 1
      fi
      # Remove the tag from the specific line (preserve surrounding text)
      sed -i '' "${LINE}s/ *$TAG//" "$FILE"
    else
      # Tags-line only: anchor to **Tags**: line
      sed -i '' "/^\*\*Tags\*\*:/ s/ $TAG//g" "$FILE"
    fi
    ;;

  swap)
    FILE="${2:?Missing file argument}"
    OLD="${3:?Missing old-tag argument}"
    NEW="${4:?Missing new-tag argument}"
    if [[ "${5:-}" == "--inline" ]]; then
      LINE="${6:?Missing line number for --inline}"
      # Support comma-separated old tags
      IFS=',' read -ra OLD_TAGS <<< "$OLD"
      local_found=0
      for old_tag in "${OLD_TAGS[@]}"; do
        if sed -n "${LINE}p" "$FILE" | grep -q "$old_tag"; then
          sed -i '' "${LINE}s/$old_tag/$NEW/" "$FILE"
          local_found=1
          break
        fi
      done
      if [[ $local_found -eq 0 ]]; then
        echo "ERROR: None of '$OLD' found at line $LINE of $FILE" >&2
        exit 1
      fi
    else
      # Tags-line only: anchor to **Tags**: line
      IFS=',' read -ra OLD_TAGS <<< "$OLD"
      for old_tag in "${OLD_TAGS[@]}"; do
        sed -i '' "/^\*\*Tags\*\*:/ s/$old_tag/$NEW/g" "$FILE"
      done
    fi
    ;;

  find)
    TAG="${2:?Missing tag argument}"
    # Parse remaining args: [path] [--context] [--tags-only]
    SEARCH_PATH="sessions/"
    CONTEXT_MODE=0
    TAGS_ONLY=0
    shift 2
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --context) CONTEXT_MODE=1 ;;
        --tags-only) TAGS_ONLY=1 ;;
        *) SEARCH_PATH="$1" ;;
      esac
      shift
    done

    # Ensure trailing slash — BSD grep -r on macOS requires it for directory search
    [[ "$SEARCH_PATH" != */ ]] && SEARCH_PATH="${SEARCH_PATH}/"

    # Escape tag for grep (# is literal, not special in grep)
    ESCAPED_TAG="$TAG"

    # Pass 1: Tags-line matches (high precision — NEVER filtered by file type)
    TAGS_LINE_FILES=$(grep -rl --exclude='*.db' --exclude='*.db.bak' \
      "^\*\*Tags\*\*:.*${ESCAPED_TAG}" "$SEARCH_PATH" 2>/dev/null || true)

    if [[ $TAGS_ONLY -eq 1 ]]; then
      # --tags-only: skip inline pass, return Tags-line matches only
      ALL_FILES=$(printf '%s\n' $TAGS_LINE_FILES | sort -u | grep -v '^$' || true)
    else
      # Pass 2: Inline body matches — bare tag, not on Tags line, not backtick-escaped
      # Excludes non-text files: binary DBs (*.db) and serialized state (.state.json).
      # All .md file types are now searchable — the session.sh check gate (¶INV_ESCAPE_BY_DEFAULT)
      # ensures bare inline tags are intentional by the time synthesis completes.
      INLINE_FILES=$(grep -rn \
        --exclude='*.db' --exclude='*.db.bak' \
        --exclude='.state.json' \
        "${ESCAPED_TAG}" "$SEARCH_PATH" 2>/dev/null \
        | grep -v '^\*\*Tags\*\*:' \
        | grep -v "\`${ESCAPED_TAG}\`" \
        | cut -d: -f1 \
        | sort -u 2>/dev/null || true)

      # Union and deduplicate
      ALL_FILES=$(printf '%s\n' $TAGS_LINE_FILES $INLINE_FILES | sort -u | grep -v '^$' || true)
    fi

    if [[ -z "$ALL_FILES" ]]; then
      exit 0
    fi

    if [[ $CONTEXT_MODE -eq 0 ]]; then
      # Files-only output
      echo "$ALL_FILES"
    else
      # Context output: file:line + 2-line lookaround
      for file in $ALL_FILES; do
        # Find all matching line numbers in this file (Tags-line and inline, excluding backtick-escaped)
        LINE_NUMS=$(grep -n "${ESCAPED_TAG}" "$file" 2>/dev/null \
          | grep -v "\`${ESCAPED_TAG}\`" \
          | cut -d: -f1 || true)
        for line_num in $LINE_NUMS; do
          echo "${file}:${line_num}"
          # Show 2-line lookaround (line-1, line, line+1)
          start=$((line_num - 1))
          [[ $start -lt 1 ]] && start=1
          end=$((line_num + 1))
          sed -n "${start},${end}p" "$file" | while IFS= read -r text; do
            echo "  ${start}: ${text}"
            start=$((start + 1))
          done
          echo ""
        done
      done
    fi
    ;;

  *)
    echo "ERROR: Unknown action '$ACTION'. Use: add, remove, swap, find" >&2
    exit 1
    ;;
esac
