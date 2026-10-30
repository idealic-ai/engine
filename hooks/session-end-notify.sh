#!/bin/bash
# SessionEnd hook: Send "done" notification when session ends (including interrupt?)
# This may fire on interrupt where Stop hook doesn't
#
# Related:
#   Docs: (~/.claude/docs/)
#     FLEET.md — Pane notification states
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — No-op outside fleet

source "$HOME/.claude/scripts/lib.sh"
notify_fleet done

# File-mode preload pages (hooks/session-start-chunk.sh) are only needed while
# the session runs: remove this session's directory. A later resume writes new
# pages. Older leftovers are swept after 2 days by the SessionStart hook.
INPUT=""; [ -t 0 ] || INPUT=$(cat 2>/dev/null || true)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)
if [ -n "$SID" ]; then
  SID_SAFE=$(printf '%s' "$SID" | tr -c 'A-Za-z0-9._-' '_')
  rm -rf "${PRELOAD_FILE_DIR:-$HOME/.claude/preload}/$SID_SAFE" 2>/dev/null || true
fi
exit 0
