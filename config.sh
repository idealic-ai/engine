#!/bin/bash
# ~/.claude/engine/config.sh — Central configuration for the Claude workflow engine.
# Sourced by scripts that need shared constants.
# This file MUST be idempotent and side-effect free (only variable assignments).
#
# Related:
#   Docs: (~/.claude/docs/)
#     CONTEXT_GUARDIAN.md — Overflow threshold documentation
#   Consumers: pre-tool-use-overflow.sh, statusline.sh

# Context overflow threshold (raw percentage 0.0-1.0)
# When contextUsage >= this value, dehydration is triggered by pre-tool-use-overflow.sh.
# Claude's auto-compact fires at ~80%. Our threshold must be below that to leave
# headroom for dehydration to complete.
#
# History:
#   0.80 — initial (same as auto-compact, too late)
#   0.78 — first reduction (2% headroom)
#   0.76 — second reduction (4% headroom, default)
#   0.95 — when DISABLE_AUTO_COMPACT=1 (full context, 5% dehydration headroom)
#
# When DISABLE_AUTO_COMPACT=1, auto-compact is disabled via CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=100.
# We raise the threshold to use the full context window, keeping 5% headroom for dehydration.
if [ "${DISABLE_AUTO_COMPACT:-}" = "1" ]; then
  OVERFLOW_THRESHOLD=0.95
else
  OVERFLOW_THRESHOLD=0.76
fi

# How SessionStart hook context reaches the agent (hooks/session-start-chunk.sh,
# and scripts/setup-lib.sh, which registers the hook to match).
#   file    — the default. ONE hook writes the whole preload as pages of at most
#             200,000 bytes and 1,990 lines, ~/.claude/preload/<session_id>/
#             preload-<source>.p<i>.txt, each ending "[END OF PAGE i/N <sha8>]",
#             and prints an inline message under Claude Code's 10,000-character
#             hook cap: the read instruction, the page list, and the preload's
#             head. One output, so its order is the source's.
#   chunked — 48 hooks each print an 8,500-byte slice. Claude Code runs hooks in
#             parallel and injects each output when it finishes, so the slices
#             arrive in completion order, not index order.
# An environment variable of the same name wins at run time, but the number of
# SessionStart slots is fixed by `engine setup`: after changing the mode, re-run
# it. Chunked on the one-slot wiring is delivered as file, with a warning.
# Any value other than chunked means file.
PRELOAD_DELIVERY_MODE="${PRELOAD_DELIVERY_MODE:-file}"

# file mode only: on, the default, makes hooks/pre-tool-use-preload-gate.sh
# deny other tools until every page has been read in full. off disables it.
PRELOAD_READ_GATE="${PRELOAD_READ_GATE:-on}"
