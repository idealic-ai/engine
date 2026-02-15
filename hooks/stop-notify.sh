#!/bin/bash
# Stop hook: Send "done" notification + detect rate limits for account rotation
# This fires automatically when the agent stops and waits for user input
#
# Rate limit detection:
#   Tails the current conversation JSONL for rate_limit errors.
#   On detection, rotates to the next account and signals fleet restart.
#   Race condition prevention: CLAUDE_ACCOUNT env var (set by run.sh at launch)
#   is compared to current active account — if they differ, another pane already rotated.
#
# Related:
#   Docs: (~/.claude/docs/)
#     FLEET.md — Pane notification states
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — No-op outside fleet

source "$HOME/.claude/scripts/lib.sh"
notify_fleet done

# ─────────────────────────────────────────────────────────────────────────────
# Rate limit detection for account auto-rotation
# ─────────────────────────────────────────────────────────────────────────────

ACCOUNT_SWITCH="$HOME/.claude/scripts/account-switch.sh"

# Skip if account-switch tool not available
[ -x "$ACCOUNT_SWITCH" ] || exit 0

# Skip if no accounts are configured (< 2 means rotation is impossible)
ACCOUNT_COUNT=$(jq -r '.accounts | length' "$HOME/.claude/accounts/state.json" 2>/dev/null || echo "0")
[ "$ACCOUNT_COUNT" -ge 2 ] || exit 0

# Find the current conversation JSONL by deriving the project dir from PWD
# Claude Code stores transcripts at ~/.claude/projects/<escaped-path>/<uuid>.jsonl
PROJECT_SLUG=$(echo "$PWD" | sed 's|/|-|g; s|^-||')
PROJECTS_DIR="$HOME/.claude/projects/$PROJECT_SLUG"

if [ -d "$PROJECTS_DIR" ]; then
  # Get the most recently modified JSONL file
  JSONL_FILE=$(ls -t "$PROJECTS_DIR"/*.jsonl 2>/dev/null | head -1)

  if [ -n "$JSONL_FILE" ] && [ -f "$JSONL_FILE" ]; then
    # Check last 50 lines for rate limit indicators
    # Patterns: API rate_limit_error, subscription rate limit, usage cap
    if tail -50 "$JSONL_FILE" 2>/dev/null | grep -qiE '"(rate_limit|rate_limit_error|overloaded)"'; then
      # Rate limit detected — attempt rotation
      ROTATE_OUTPUT=$("$ACCOUNT_SWITCH" rotate 2>&1) || true

      if echo "$ROTATE_OUTPUT" | grep -q "^Rotated:"; then
        # Rotation succeeded — signal fleet to restart all panes
        if [ -n "${TMUX:-}" ]; then
          FLEET_SCRIPT="$HOME/.claude/scripts/fleet.sh"
          if [ -x "$FLEET_SCRIPT" ]; then
            "$FLEET_SCRIPT" restart-all 2>/dev/null || true
          fi
        fi
      fi
      # If SKIP or ERROR, do nothing — rotation was already handled or not possible
    fi
  fi
fi

exit 0
