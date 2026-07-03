#!/bin/bash
# reap-stray-sessions.sh — Merge bug-created stray sessions/ dirs into the repo root.
#
# Before session resolution was anchored (find_project_root), activating from a
# subfolder wrote $PWD/sessions — forking stray sessions/ dirs across the tree.
# This reaper moves those sessions back to where they belong.
#
# A sessions/ dir is a STRAY iff its immediate parent has no .claude/. Legitimate
# roots (the repo root, git/agent worktrees) have .claude beside their sessions/,
# so they're skipped. Each stray's sessions are merged into the nearest .claude
# ancestor's sessions/ (so a stray inside a worktree merges into that worktree).
#
# Dedupe on name collision: keep the NEWER session (by .state.json mtime, else dir
# mtime); the older duplicate is deleted. Empty stray sessions/ dirs are removed.
#
# Usage:
#   reap-stray-sessions.sh [--root DIR] [--apply] [--yes] [--audit-dir DIR]
#   (default: DRY RUN from the current repo root — prints the plan, changes nothing)
#
# Env (tests): FIND_PROJECT_ROOT_OVERRIDE unused; pass --root explicitly.

set -uo pipefail
source "$HOME/.claude/scripts/lib.sh"

APPLY=0; YES=0; ROOT=""; AUDIT_DIR="${TMPDIR:-/tmp}"
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --yes|-y) YES=1; shift ;;
    --root) ROOT="${2:?--root requires a dir}"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --audit-dir) AUDIT_DIR="${2:?--audit-dir requires a dir}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$ROOT" ] || ROOT=$(find_project_root 2>/dev/null || echo "$PWD")
ROOT=$(cd "$ROOT" 2>/dev/null && pwd -P) || { echo "bad --root" >&2; exit 2; }
[ -d "$ROOT/.claude" ] || { echo "warn: $ROOT has no .claude/ (not a project root?)" >&2; }

_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
# Session "age" = mtime of its .state.json if present, else the dir mtime.
_session_mtime() { [ -f "$1/.state.json" ] && _mtime "$1/.state.json" || _mtime "$1"; }

MODE="DRY-RUN"; [ "$APPLY" -eq 1 ] && MODE="APPLY"
echo "reap-stray-sessions [$MODE] root=$ROOT"

# Collect stray sessions/ dirs (parent lacks .claude/), pruning noise.
STRAYS=()
while IFS= read -r sdir; do
  [ -d "$sdir" ] || continue
  parent=$(dirname "$sdir")
  # Legitimate: a sessions/ dir whose parent is itself a project/worktree root.
  [ -d "$parent/.claude" ] && continue
  STRAYS+=("$sdir")
done < <(find "$ROOT" \( -name node_modules -o -name .git \) -prune -o -type d -name sessions -print 2>/dev/null)

if [ "${#STRAYS[@]}" -eq 0 ]; then
  echo "No stray sessions/ dirs found."
  exit 0
fi

echo "Found ${#STRAYS[@]} stray sessions/ dir(s):"
MOVES=0; REPLACES=0; DUP_DROPS=0; RMDIRS=0
declare -a PLAN=()
for sdir in "${STRAYS[@]}"; do
  parent=$(dirname "$sdir")
  target_root=$(find_project_root "$parent" 2>/dev/null || echo "")
  if [ -z "$target_root" ] || [ "$target_root/sessions" = "$sdir" ]; then
    echo "  SKIP (no anchor): $sdir"
    continue
  fi
  target="$target_root/sessions"
  echo "  $sdir  ->  $target"
  for sess in "$sdir"/*/; do
    [ -d "$sess" ] || continue
    sess="${sess%/}"
    name=$(basename "$sess")
    if [ -e "$target/$name" ]; then
      sm=$(_session_mtime "$sess"); tm=$(_session_mtime "$target/$name")
      if [ "$sm" -gt "$tm" ]; then
        echo "    REPLACE (stray newer): $name"
        PLAN+=("replace|$sess|$target/$name")
        REPLACES=$((REPLACES+1))
      else
        echo "    DROP (target newer dup): $name"
        PLAN+=("drop|$sess|$target/$name")
        DUP_DROPS=$((DUP_DROPS+1))
      fi
    else
      echo "    MOVE: $name"
      PLAN+=("move|$sess|$target/$name")
      MOVES=$((MOVES+1))
    fi
  done
  PLAN+=("rmdir|$sdir|")
  RMDIRS=$((RMDIRS+1))
done

echo "Plan: $MOVES move, $REPLACES replace, $DUP_DROPS drop-dup, $RMDIRS rmdir"

if [ "$APPLY" -eq 0 ]; then
  echo "(dry-run — re-run with --apply to execute)"
  exit 0
fi

if [ "$YES" -eq 0 ]; then
  printf "Apply these changes? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) echo "aborted"; exit 1 ;; esac
fi

AUDIT="$AUDIT_DIR/reap-stray-sessions-$$.jsonl"
: > "$AUDIT"; chmod 600 "$AUDIT" 2>/dev/null || true
_audit() { printf '{"action":"%s","from":"%s","to":"%s"}\n' "$1" "$2" "$3" >> "$AUDIT"; }

for entry in "${PLAN[@]}"; do
  IFS='|' read -r action from to <<< "$entry"
  case "$action" in
    move|replace)
      # Re-check the target at apply time: it may now exist because a prior step
      # moved a same-named session from another stray. Always keep the newer.
      if [ -e "$to" ]; then
        if [ "$(_session_mtime "$from")" -gt "$(_session_mtime "$to")" ]; then
          rm -rf "$to" && mv "$from" "$to" && _audit replace "$from" "$to"
        else
          rm -rf "$from" && _audit drop "$from" "$to"
        fi
      else
        mkdir -p "$(dirname "$to")"
        mv "$from" "$to" && _audit move "$from" "$to"
      fi
      ;;
    drop)
      rm -rf "$from" && _audit drop "$from" "$to"
      ;;
    rmdir)
      rmdir "$from" 2>/dev/null && _audit rmdir "$from" "" || echo "  (not empty, kept): $from"
      ;;
  esac
done

echo "Applied. Audit: $AUDIT"
