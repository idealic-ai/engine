#!/bin/bash
# ~/.claude/scripts/migrate-fleet-pane-ids.sh — One-time migration for scoped fleetPaneId
#
# Related:
#   Docs: (~/.claude/docs/)
#     FLEET.md — Fleet pane ID format (scoped composite IDs)
#
# Migrates existing .state.json files from old format (e.g., "MCP") to new scoped format
# (e.g., "fleet:MCP"). Creates backups before modifying.
#
# Usage:
#   migrate-fleet-pane-ids.sh [sessions_dir]
#
# Examples:
#   migrate-fleet-pane-ids.sh                    # Uses $PWD/sessions
#   migrate-fleet-pane-ids.sh ~/project/sessions # Explicit path

set -euo pipefail

SESSIONS_DIR="${1:-$PWD/sessions}"
DEFAULT_PREFIX="fleet"  # Default tmux session name for fleet

if [ ! -d "$SESSIONS_DIR" ]; then
  echo "ERROR: Sessions directory not found: $SESSIONS_DIR" >&2
  exit 1
fi

echo "Migrating fleetPaneId in: $SESSIONS_DIR"
echo "New format: {tmux_session}:{pane_label} (e.g., fleet:MCP)"
echo ""

migrated=0
skipped=0
errors=0

# Find all .state.json files
while IFS= read -r agent_file; do
  [ -f "$agent_file" ] || continue

  # Get current fleetPaneId
  fleet_pane_id=$(jq -r '.fleetPaneId // ""' "$agent_file" 2>/dev/null || echo "")

  if [ -z "$fleet_pane_id" ]; then
    # No fleetPaneId, skip
    continue
  fi

  if [[ "$fleet_pane_id" == *":"* ]]; then
    # Already scoped, skip
    echo "SKIP (already scoped): $agent_file -> $fleet_pane_id"
    ((skipped++))
    continue
  fi

  # Needs migration — create backup first
  backup_file="${agent_file}.bak"
  cp "$agent_file" "$backup_file"

  # Update to scoped format
  new_fleet_pane_id="${DEFAULT_PREFIX}:${fleet_pane_id}"

  if jq --arg new_id "$new_fleet_pane_id" '.fleetPaneId = $new_id' "$agent_file" > "$agent_file.tmp"; then
    mv "$agent_file.tmp" "$agent_file"
    echo "MIGRATED: $agent_file"
    echo "  Old: $fleet_pane_id"
    echo "  New: $new_fleet_pane_id"
    ((migrated++))
  else
    echo "ERROR: Failed to migrate $agent_file" >&2
    # Restore from backup
    mv "$backup_file" "$agent_file"
    ((errors++))
  fi

done < <(find -L "$SESSIONS_DIR" -name ".state.json" -type f 2>/dev/null)

echo ""
echo "Migration complete:"
echo "  Migrated: $migrated"
echo "  Skipped (already scoped): $skipped"
echo "  Errors: $errors"

if [ $errors -gt 0 ]; then
  exit 1
fi
