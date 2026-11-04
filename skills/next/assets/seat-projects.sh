#!/bin/bash
# seat-projects.sh — the Linear project(s) a seat works in, read from the director's seat→project
# table, so /next can hand `engine project next` a project on a branch with no ticket key.
#
# Usage:
#   bash ~/.claude/engine/skills/next/assets/seat-projects.sh [--seat <seat>] [--file <path>]
#
# The seat is --seat, else $FLEET_PANE (the seat label /next already uses for asks, such as
# `meta:engine`). The table is --file, else $NEXT_SEAT_PROJECTS, else the director's file read in
# place under the repository's MAIN checkout (a git worktree resolves to the same file):
#   <main checkout>/sessions/2026_10_28_DIRECTOR/builds/SEAT_PROJECTS.tsv
# The director owns that file; this script only reads it.
#
# Table: tab-separated `seat<TAB>linear_project<TAB>role`; `#` lines and blank lines are skipped.
# A seat may have several rows. A project of `-` means the row names no project.
#
# Output (stdout): one `project<TAB>role` line per row of the seat, in file order.
# Exit:
#   0  at least one project printed
#   1  the table was read and names no project for the seat (no row, or only `-` rows); stderr
#      says which
#   2  unread: no seat identity, the table is missing or unreadable, or it has no data rows.
#      Never reported as "no row", so an unread table cannot pass for an empty map.
set -uo pipefail

DEFAULT_REL="sessions/2026_10_28_DIRECTOR/builds/SEAT_PROJECTS.tsv"

seat="${FLEET_PANE:-}" file="${NEXT_SEAT_PROJECTS:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --seat) seat="${2:-}"; shift 2 ;;
    --seat=*) seat="${1#*=}"; shift ;;
    --file) file="${2:-}"; shift 2 ;;
    --file=*) file="${1#*=}"; shift ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "seat-projects: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

if [ -z "$seat" ]; then
  echo "seat-projects: unread — no seat identity (FLEET_PANE unset or empty, no --seat)" >&2
  exit 2
fi

if [ -z "$file" ]; then
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || common=""
  if [ -z "$common" ]; then
    echo "seat-projects: unread — not in a git repository, so the director's table ($DEFAULT_REL) has no root; pass --file or set NEXT_SEAT_PROJECTS" >&2
    exit 2
  fi
  root=$(cd "$common/.." 2>/dev/null && pwd -P) || root=""
  file="$root/$DEFAULT_REL"
fi

if [ ! -f "$file" ] || [ ! -r "$file" ]; then
  echo "seat-projects: unread — table not found or unreadable: $file" >&2
  exit 2
fi

# One pass: count data rows; print the seat's rows with a project; count its '-' rows.
out=$(awk -F'\t' -v seat="$seat" '
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  { data++; sub(/\r$/, "") }
  $1 == seat {
    if ($2 == "-" || $2 == "") { dash++; next }
    print $2 "\t" $3; hits++
  }
  END { printf "#counts %d %d %d\n", data, hits, dash }
' "$file")
counts=$(printf '%s\n' "$out" | tail -1)
rows=$(printf '%s\n' "$out" | sed '$d')
set -- $counts
data="$2" hits="$3" dash="$4"

if [ "$data" = "0" ]; then
  echo "seat-projects: unread — table has no data rows: $file" >&2
  exit 2
fi
if [ "$hits" = "0" ]; then
  if [ "$dash" != "0" ]; then
    echo "seat-projects: seat '$seat' has a row naming no project (-) in $file" >&2
  else
    echo "seat-projects: no row for seat '$seat' in $file" >&2
  fi
  exit 1
fi
printf '%s\n' "$rows"
echo "seat-projects: seat '$seat': $hits project(s) from $file" >&2
exit 0
