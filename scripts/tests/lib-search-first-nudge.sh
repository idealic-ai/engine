#!/usr/bin/env bash
# lib-search-first-nudge.sh — one check shared by the suites that read a "search before you ask" nudge
# (IDE-333 acceptance 3; ¶INV_ASK_THE_REPOSITORY_BEFORE_ASKING_THE_CODE).
#
# search_nudge_violations <file> <section heading, without "## "> <engine dir>
#   Prints one line per violation; prints nothing when the section carries a nudge whose commands work:
#   - both `engine session-search query "…"` and `engine doc-search query "…"` are written in it;
#   - each runs from the main checkout (`git worktree list --porcelain`), because both searches find
#     their database from the working directory and exit 1 from a worktree (measured 2026-10-30:
#     "No index found" / "Sessions directory not found: <worktree>/sessions");
#   - the CLI under <engine dir>/tools/<tool>/src/cli.ts lists a `query "text"` subcommand, and every
#     --flag written after the command is one its usage text lists;
#   - it gives the "searched, nothing relevant" fallback and says a search can miss.
# Hermetic: it reads the CLI's usage text and never runs a search (that needs a live Ollama).

search_nudge_violations() {
  local file="$1" heading="$2" engine="$3" body tool usage line flag
  body=$(awk -v h="## $heading" 'index($0,h)==1 {f=1; next} f && /^## / {exit} f' "$file")
  [ -n "$body" ] || { echo "section '## $heading' absent or empty in $(basename "$file")"; return; }
  printf '%s' "$body" | grep -qF 'git worktree list --porcelain' \
    || echo "no cd to the main checkout: both searches exit 1 from a worktree"
  printf '%s' "$body" | grep -qF 'searched, nothing relevant' || echo "no 'searched, nothing relevant' fallback"
  printf '%s' "$body" | grep -qiF 'can miss' || echo "does not say a search can miss"
  for tool in session-search doc-search; do
    usage="$engine/tools/$tool/src/cli.ts"
    [ -f "$usage" ] || { echo "$tool: no CLI at $usage"; continue; }
    grep -qF "$tool query \"text\"" "$usage" || echo "$tool: its CLI usage lists no query subcommand"
    line=$(printf '%s\n' "$body" | grep -F "engine $tool query \"" | head -1)
    [ -n "$line" ] || { echo "$tool: no 'engine $tool query \"…\"' command in the section"; continue; }
    # The flags are what follows the command up to the closing backtick of its code span.
    for flag in $(printf '%s' "${line#*engine $tool query}" | sed 's/`.*//' | grep -oE -- '--[a-z][a-z-]*'); do
      grep -qE -- "^ +$flag( |$)" "$usage" || echo "$tool: flag $flag is not in its CLI usage"
    done
  done
}
