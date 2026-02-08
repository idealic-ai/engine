#!/bin/bash
# Notification hook for idle_prompt: Clear working state
# Fires when Claude is idle/waiting - means work stopped (possibly interrupted)
#
# Related:
#   Docs: (~/.claude/docs/)
#     FLEET.md — Pane notification states
#   Invariants: (~/.claude/directives/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — No-op outside fleet

source "$HOME/.claude/scripts/lib.sh"
notify_fleet done
exit 0
