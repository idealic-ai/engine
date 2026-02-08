#!/bin/bash
# Post tool completion hook - clears working state
# Fires after any tool completes (success or failure)
# PostToolUseFailure hook will override with error state if needed
# Only clears if currently in working state (avoid unnecessary state changes)
#
# Related:
#   Docs: (~/.claude/docs/)
#     FLEET.md — Pane notification states, working→done transition
#   Invariants: (~/.claude/directives/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — No-op outside fleet

source "$HOME/.claude/scripts/lib.sh"

# Check if we're in fleet tmux first
[ -n "${TMUX:-}" ] || exit 0
socket=$(echo "$TMUX" | cut -d, -f1 | xargs basename 2>/dev/null || echo "")
[[ "$socket" == "fleet" || "$socket" == fleet-* ]] || exit 0

# Only clear if currently in working state
current=$(tmux -L "$socket" display -p '#{@pane_notify}' 2>/dev/null || echo "")
if [[ "$current" == "working" ]]; then
  notify_fleet done
fi
