#!/bin/bash
# seat-projects.sh — the Linear project(s) a seat works in, read from the director's seat→project
# table, so /next can hand `engine project next` a project on a branch with no ticket key.
#
# Usage:
#   bash ~/.claude/engine/skills/next/assets/seat-projects.sh [--seat <seat>] [--file <path>]
#
# The seat is --seat, else read LIVE from tmux (`#{window_name}:#{@pane_label}`, lib.sh
# fleet_self, the rule /ask and hop.sh use), else $FLEET_PANE (run.sh's launch-time cache). A
# cache that differs from the live label is warned about on stderr.
#
# The table, first source that is set wins, and stderr names it:
#   1. --file <path>
#   2. $NEXT_SEAT_PROJECTS
#   3. the `- **Seat projects**: <path>` line in `## Tracker` of CLAUDE.md at the git toplevel
#      (lib.sh tracker_field; the value is cut at its first " (" and loses backticks)
#   4. TEMPORARY, owed for removal once kit's § Tracker carries the line: the hardcoded
#      sessions/2026_10_28_DIRECTOR/builds/SEAT_PROJECTS.tsv
# A relative path in 3 or 4 resolves against the repository's MAIN checkout
# (`git rev-parse --git-common-dir`/..), because sessions/ is gitignored and exists only there,
# so a worktree reads the same file. The director owns the table; this script only reads it.
#
# Table: tab-separated `seat<TAB>linear_project<TAB>role`; `#` lines, blank lines and an
# uncommented `seat<TAB>linear_project…` header row are skipped; a trailing CR is stripped.
# A seat may have several rows. A project of `-` means the row names no project.
#
# Output (stdout): one `project<TAB>role` line per row of the seat, in file order.
# Exit:
#   0  at least one project printed
#   1  the table was read and names no project for the seat (no row, or only `-` rows); stderr
#      says which
#   2  unread: no seat identity, the table is missing or unreadable (a § Tracker line naming a
#      path that does not exist included), or it has no data rows. Never reported as "no row",
#      so an unread table cannot pass for an empty map.
set -uo pipefail

TEMP_DEFAULT_REL="sessions/2026_10_28_DIRECTOR/builds/SEAT_PROJECTS.tsv"

# lib.sh (fleet_self, tracker_file, tracker_field): the engine tree this script sits in.
_here=$(cd -P "$(dirname "$0")" 2>/dev/null && pwd) || _here=""
_lib=""
for _c in "$_here/../../../scripts/lib.sh" "${ENGINE_SCRIPTS:-}/lib.sh"; do
  if [ -n "$_c" ] && [ -f "$_c" ]; then _lib="$_c"; break; fi
done
if [ -z "$_lib" ]; then
  echo "seat-projects: unread — cannot find the engine's scripts/lib.sh beside this script or in \$ENGINE_SCRIPTS" >&2
  exit 2
fi
# shellcheck source=/dev/null
source "$_lib"

seat="" file="" source=""
while [ $# -gt 0 ]; do
  case "$1" in
    --seat) seat="${2:-}"; shift 2 ;;
    --seat=*) seat="${1#*=}"; shift ;;
    --file) file="${2:-}"; source="--file"; shift 2 ;;
    --file=*) file="${1#*=}"; source="--file"; shift ;;
    -h|--help) sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "seat-projects: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

if [ -z "$seat" ]; then
  seat=$(FLEET_WARN_PREFIX=seat-projects fleet_self) || [ $? = 3 ] || seat=""
fi
if [ -z "$seat" ]; then
  echo "seat-projects: unread — no seat identity (no live pane label, FLEET_PANE unset or empty, no --seat)" >&2
  exit 2
fi

main_root() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  (cd "$common/.." 2>/dev/null && pwd -P)
}
# resolve REL-OR-ABS → absolute path against the main checkout; return 1 outside a repository.
resolve() {
  case "$1" in /*) printf '%s' "$1"; return 0 ;; esac
  local root; root=$(main_root) || return 1
  printf '%s/%s' "$root" "$1"
}

if [ -z "$file" ] && [ -n "${NEXT_SEAT_PROJECTS:-}" ]; then
  file="$NEXT_SEAT_PROJECTS"; source="NEXT_SEAT_PROJECTS"
fi
if [ -z "$file" ]; then
  tf=$(tracker_file) && line=$(tracker_field "$tf" "Seat projects") || line=""
  if [ -n "$line" ]; then
    source="§ Tracker 'Seat projects' in $tf"
    file=$(resolve "$line") || { echo "seat-projects: unread — $source names '$line' but no main checkout resolves it" >&2; exit 2; }
  else
    source="temporary hardcoded default (no 'Seat projects' line in § Tracker; owed for removal)"
    file=$(resolve "$TEMP_DEFAULT_REL") || {
      echo "seat-projects: unread — not in a git repository and no table named; pass --file or set NEXT_SEAT_PROJECTS" >&2; exit 2; }
  fi
fi

if [ ! -f "$file" ] || [ ! -r "$file" ]; then
  echo "seat-projects: unread — table not found or unreadable: $file (from $source)" >&2
  exit 2
fi

# One pass: count data rows; print the seat's rows with a project; count its '-' rows.
out=$(awk -F'\t' -v seat="$seat" '
  { sub(/\r$/, "") }
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  $1 == "seat" && $2 == "linear_project" { next }
  { data++ }
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
  echo "seat-projects: unread — table has no data rows: $file (from $source)" >&2
  exit 2
fi
if [ "$hits" = "0" ]; then
  if [ "$dash" != "0" ]; then
    echo "seat-projects: seat '$seat' has a row naming no project (-) in $file (from $source)" >&2
  else
    echo "seat-projects: no row for seat '$seat' in $file (from $source)" >&2
  fi
  exit 1
fi
printf '%s\n' "$rows"
echo "seat-projects: seat '$seat': $hits project(s) from $file (from $source)" >&2
exit 0
