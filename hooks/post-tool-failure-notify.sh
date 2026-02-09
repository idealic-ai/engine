#!/bin/bash
# PostToolUseFailure hook — NO-OP for notification
# A tool failure doesn't mean the agent stopped working.
# The agent will continue thinking and may retry or try a different approach.
# Only Stop/SessionEnd/idle_prompt should transition away from working.
#
# Related:
#   Docs: (~/.claude/docs/)
#     FLEET.md — Pane notification states
#   Invariants: (~/.claude/directives/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — No-op outside fleet

exit 0
