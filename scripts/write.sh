#!/bin/bash
# ~/.claude/scripts/write.sh — Write content to system clipboard
#
# Related:
#   (no direct doc/invariant/command references — clipboard utility)
#   Consumer: /session dehydrate
#
# Usage:
#   write.sh <<'EOF'
#   content here
#   EOF
#
# Reads stdin and copies it to the system clipboard via pbcopy.
# Used by /session dehydrate to export session snapshots.

set -euo pipefail

pbcopy
