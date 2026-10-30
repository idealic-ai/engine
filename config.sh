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
#   file    — the default. ONE hook writes the whole preload to a durable file
#             (~/.claude/projects/<slug>/<session_id>/preload-<source>.txt) and
#             prints an inline message under Claude Code's 10,000-character hook
#             cap: a read instruction, the head of the preload, and the file's
#             path, size and end line. One output, so its order is the source's.
#   chunked — 48 hooks each print an 8,500-byte slice. Claude Code runs hooks in
#             parallel and injects each output when it finishes, so the slices
#             arrive in completion order, not index order.
# An environment variable of the same name wins; any other value means file.
PRELOAD_DELIVERY_MODE="${PRELOAD_DELIVERY_MODE:-file}"
