#!/bin/bash
# Pane focus style hook - sets focused pane to black, unfocused to status tint
# Called by tmux after-select-pane hook
# Uses guard variable to prevent re-entry loop
#
# Related:
#   Docs: (~/.claude/docs/)
#     FLEET.md — Pane styling, status colors
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — No-op outside fleet

# Auto-detect fleet socket from $TMUX env var (fleet or fleet-*)
if [[ -n "${TMUX:-}" ]]; then
  SOCKET=$(echo "$TMUX" | cut -d, -f1 | xargs basename 2>/dev/null || echo "")
else
  SOCKET="fleet"
fi
BLACK="bg=black"

# Tinted backgrounds for unfocused panes (darker versions of status colors)
# These are dim versions that don't overwhelm but show the status
TINT_ERROR="bg=#3d2020"      # dark red
TINT_UNCHECKED="bg=#081a10"  # dark mint green (needs attention)
TINT_WORKING="bg=#080c10"    # very dark blue
TINT_CHECKED="bg=#0a1005"    # very dark sage (dimmer, acknowledged)
TINT_DEFAULT="bg=#0a0a0a"    # very dark gray (done/no status)

# Suppress check: programmatic style changes set @suppress_focus_hook=1
# (INV_SUPPRESS_HOOKS_FOR_PROGRAMMATIC_STYLE — prevents cascade during fleet.sh notify)
SUPPRESS=$(tmux -L "$SOCKET" show -gqv @suppress_focus_hook 2>/dev/null)
if [ "$SUPPRESS" = "1" ]; then
  exit 0
fi

# Guard: check if we're already running (prevent loop)
GUARD=$(tmux -L "$SOCKET" show -gqv @focus_hook_running 2>/dev/null)
if [ "$GUARD" = "1" ]; then
  exit 0
fi

# Set guard
tmux -L "$SOCKET" set -g @focus_hook_running "1"

# Get current pane
CURR=$(tmux -L "$SOCKET" display -p '#{pane_id}')

# Get last focused pane from variable
LAST=$(tmux -L "$SOCKET" show -gqv @last_focused_pane 2>/dev/null)

# If we have a last pane and it's different, set its background based on status
if [ -n "$LAST" ] && [ "$LAST" != "$CURR" ]; then
  # Get the notification status of the old pane
  STATUS=$(tmux -L "$SOCKET" display -t "$LAST" -p '#{@pane_notify}' 2>/dev/null)

  case "$STATUS" in
    error)     TINT="$TINT_ERROR" ;;
    unchecked) TINT="$TINT_UNCHECKED" ;;
    working)   TINT="$TINT_WORKING" ;;
    checked)   TINT="$TINT_CHECKED" ;;
    *)         TINT="$TINT_DEFAULT" ;;
  esac

  # State-check: skip if tint already matches (INV_SKIP_REDUNDANT_STYLE_APPLY)
  CURRENT_STYLE=$(tmux -L "$SOCKET" display -t "$LAST" -p '#{window-style}' 2>/dev/null || echo "")
  if [ "$CURRENT_STYLE" != "$TINT" ]; then
    tmux -L "$SOCKET" set -g @suppress_focus_hook 1 \; \
      select-pane -t "$LAST" -P "$TINT" \; \
      select-pane -t "$CURR" \; \
      set -g @suppress_focus_hook 0 2>/dev/null
  fi
fi

# Set current pane to black (state-check: skip if already black)
CURR_STYLE=$(tmux -L "$SOCKET" display -t "$CURR" -p '#{window-style}' 2>/dev/null || echo "")
if [ "$CURR_STYLE" != "$BLACK" ]; then
  tmux -L "$SOCKET" set -g @suppress_focus_hook 1 \; \
    select-pane -t "$CURR" -P "$BLACK" \; \
    set -g @suppress_focus_hook 0 2>/dev/null
fi

# Store current as last for next time
tmux -L "$SOCKET" set -g @last_focused_pane "$CURR"

# Clear guard
tmux -L "$SOCKET" set -g @focus_hook_running "0"
exit 0
