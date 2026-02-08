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
#   0.76 — second reduction (4% headroom, current)
OVERFLOW_THRESHOLD=0.76
