#!/bin/bash
# Stop hook: Send "done" notification when Claude's turn ends (work complete)
# This fires automatically when the agent stops and waits for user input
#
# Related:
#   Docs: (~/.claude/docs/)
#     FLEET.md — Pane notification states
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — No-op outside fleet

source "$HOME/.claude/scripts/lib.sh"
notify_fleet done
exit 0
