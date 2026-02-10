#!/bin/bash
# Notification hook: Send "unchecked" state when Claude needs user input
# Triggers: permission_prompt, idle_prompt, elicitation_dialog
# State: unchecked (orange) → checked (gray) when user focuses pane
#
# Related:
#   Docs: (~/.claude/docs/)
#     FLEET.md — Pane notification states (unchecked/done/working/error)
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — No-op outside fleet

source "$HOME/.claude/scripts/lib.sh"
notify_fleet unchecked
exit 0
