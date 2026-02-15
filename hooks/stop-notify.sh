#!/bin/bash
# Stop hook: Send "done" notification + detect rate limits for account rotation
# This fires automatically when the agent stops and waits for user input
#
# Detections:
#   1. Rate limit: Tails JSONL for rate_limit errors or "hit your limit" text.
#      On detection, rotates to the next account and signals fleet restart.
#      Race condition prevention: CLAUDE_ACCOUNT env var (set by run.sh at launch)
#      is compared to current active account — if they differ, another pane already rotated.
#   2. Context full: Tails JSONL for context exhaustion errors.
#      On detection, triggers engine session restart (no account rotation).
#
# Related:
#   Docs: (~/.claude/docs/)
#     FLEET.md — Pane notification states
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — No-op outside fleet

source "$HOME/.claude/scripts/lib.sh"
notify_fleet done

# ─────────────────────────────────────────────────────────────────────────────
# Shared: Find the current conversation JSONL
# ─────────────────────────────────────────────────────────────────────────────

# Claude Code stores transcripts at ~/.claude/projects/<escaped-path>/<uuid>.jsonl
PROJECT_SLUG=$(echo "$PWD" | sed 's|/|-|g')
PROJECTS_DIR="$HOME/.claude/projects/$PROJECT_SLUG"

JSONL_FILE=""
if [ -d "$PROJECTS_DIR" ]; then
  JSONL_FILE=$(ls -t "$PROJECTS_DIR"/*.jsonl 2>/dev/null | head -1)
fi

# No JSONL found — nothing to detect
[ -n "$JSONL_FILE" ] && [ -f "$JSONL_FILE" ] || exit 0

TAIL_CONTENT=$(tail -50 "$JSONL_FILE" 2>/dev/null || true)

# ─────────────────────────────────────────────────────────────────────────────
# Detection 1: Rate limit → account rotation + fleet restart
# ─────────────────────────────────────────────────────────────────────────────

ACCOUNT_SWITCH="$HOME/.claude/scripts/account-switch.sh"

# Only attempt rotation if account-switch is available and 2+ accounts configured
if [ -x "$ACCOUNT_SWITCH" ]; then
  ACCOUNT_COUNT=$(jq -r '.accounts | length' "$HOME/.claude/accounts/state.json" 2>/dev/null || echo "0")

  if [ "$ACCOUNT_COUNT" -ge 2 ]; then
    # Check for rate limit indicators:
    #   - JSON field: "rate_limit", "rate_limit_error", "overloaded"
    #   - Text content: "You've hit your limit" (synthetic message text)
    if echo "$TAIL_CONTENT" | grep -qiE '"(rate_limit|rate_limit_error|overloaded)"' || \
       echo "$TAIL_CONTENT" | grep -qiF "hit your limit"; then
      # Rate limit detected — attempt rotation
      rotation_log "RATE_LIMIT_DETECTED" "account=${CLAUDE_ACCOUNT:-unknown} pid=$$"
      ROTATE_OUTPUT=$("$ACCOUNT_SWITCH" rotate 2>&1) || true

      if echo "$ROTATE_OUTPUT" | grep -q "^Rotated:"; then
        # Extract new account from rotate output (format: "Rotated: old@x.com → new@x.com")
        NEW_ACCOUNT=$(echo "$ROTATE_OUTPUT" | sed -n 's/^Rotated:.*→ *//p' | tr -d ' ')
        rotation_log "ROTATED" "old=${CLAUDE_ACCOUNT:-unknown} new=${NEW_ACCOUNT:-unknown}"
        # Rotation succeeded — signal fleet to restart all panes
        if [ -n "${TMUX:-}" ]; then
          FLEET_SCRIPT="$HOME/.claude/scripts/fleet.sh"
          if [ -x "$FLEET_SCRIPT" ]; then
            "$FLEET_SCRIPT" restart-all 2>/dev/null || true
          fi
        fi
      elif echo "$ROTATE_OUTPUT" | grep -q "^SKIP"; then
        rotation_log "ROTATION_SKIPPED" "account=${CLAUDE_ACCOUNT:-unknown} reason=already_rotated"
      else
        rotation_log "ROTATION_ERROR" "account=${CLAUDE_ACCOUNT:-unknown} output=${ROTATE_OUTPUT:-empty}"
      fi
    fi
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Detection 2: Context full → engine session restart (no rotation)
# ─────────────────────────────────────────────────────────────────────────────
# When Claude Code's context window is exhausted, it emits a synthetic message.
# Unlike rate limits, this triggers a session restart (dehydrate + respawn),
# NOT an account rotation — the account is fine, just the context is full.
#
# Known patterns (add more as discovered):
#   - "prompt is too long" (Anthropic API error for exceeding context)
#   - "conversation is too long" (Claude Code internal)
#   - "context_length_exceeded" (API error type)

if echo "$TAIL_CONTENT" | grep -qiE 'prompt is too long|conversation is too long|context_length_exceeded'; then
  # Context exhaustion detected — trigger session restart
  # Find the active session directory
  SESSION_DIR=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
  if [ -n "$SESSION_DIR" ]; then
    "$HOME/.claude/scripts/session.sh" restart "$SESSION_DIR" 2>/dev/null || true
  fi
fi

exit 0
