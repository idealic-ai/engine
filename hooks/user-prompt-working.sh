#!/bin/bash
# UserPromptSubmit hook: Send "working" state when user submits a prompt
# This fires immediately when the user hits enter, before Claude processes
# State: Transitions any state → working (blue) when user responds
#
# Related:
#   Docs: (~/.claude/docs/)
#     FLEET.md — Pane notification states (working state on prompt submit)
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — No-op outside fleet

source "$HOME/.claude/scripts/lib.sh"
notify_fleet working
exit 0
