#!/bin/bash
# Post tool completion hook — NO-OP for notification
# Previously cleared working→done after every tool, but this caused flashing
# because the agent is still working between tool calls.
#
# The correct lifecycle:
#   UserPromptSubmit → working (agent starts)
#   PreToolUse       → working (re-assert during loop)
#   PostToolUse      → (no state change — agent is still thinking)
#   Stop             → done (agent truly finished)
#   SessionEnd       → done (session closed)
#   Notification(idle_prompt) → done (agent idle)
#
# Related:
#   Docs: (~/.claude/docs/)
#     FLEET.md — Pane notification states
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — No-op outside fleet

exit 0
