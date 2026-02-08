#!/bin/bash
# SessionEnd hook: Send "done" notification when session ends (including interrupt?)
# This may fire on interrupt where Stop hook doesn't
#
# Related:
#   Docs: (~/.claude/docs/)
#     FLEET.md — Pane notification states
#   Invariants: (~/.claude/standards/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — No-op outside fleet

source "$HOME/.claude/scripts/lib.sh"
notify_fleet done
exit 0
