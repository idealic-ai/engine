#!/bin/bash
# user-info.sh — Auto-detect user info from Google Drive symlink or cache
#
# Related:
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     ¶INV_INFER_USER_FROM_GDRIVE — Auto-detect identity from GDrive symlink
#
# Usage: user-info.sh [field]
#   field: username | email | domain | data-root | json (default: json)
#
# Detection order:
#   1. Check ~/.claude/engine/.user.json cache (local mode)
#   2. Read ~/.claude/tools symlink target, extract GoogleDrive-* path (remote mode)
#
# Fields:
#   username   — e.g., "yarik"
#   email      — e.g., "yarik@finchclaims.com"
#   domain     — e.g., "finchclaims.com"
#   data-root  — GDrive shared drive root (where user data lives: sessions, assets, etc.)
#                e.g., "/Users/.../GoogleDrive-yarik@finchclaims.com/Shared drives/finch-os"
#                Works in both local and remote mode.
#
# Example:
#   user-info.sh              # {"username":"yarik","email":"yarik@finchclaims.com","domain":"finchclaims.com"}
#   user-info.sh username     # yarik
#   user-info.sh email        # yarik@finchclaims.com
#   user-info.sh data-root    # /Users/.../Shared drives/finch-os

set -euo pipefail

FIELD="${1:-json}"
CACHE_FILE="$HOME/.claude/engine/.user.json"

# Resolve GDrive shared drive root from email.
# This is where user data lives (sessions, assets, fleet configs, etc.)
# Works regardless of whether the engine itself is local or on GDrive.
resolve_data_root() {
    local email="$1"
    # Scan CloudStorage for the GoogleDrive mount matching this email
    local gdrive_mount
    gdrive_mount=$(find "$HOME/Library/CloudStorage" -maxdepth 1 -name "GoogleDrive-${email}" -type d 2>/dev/null | head -1)
    if [[ -n "$gdrive_mount" ]]; then
        echo "$gdrive_mount/Shared drives/finch-os"
        return
    fi
    # Fallback: construct the expected path (may not exist yet)
    echo "$HOME/Library/CloudStorage/GoogleDrive-${email}/Shared drives/finch-os"
}

# Check for cached identity first (local mode)
if [ -f "$CACHE_FILE" ]; then
    case "$FIELD" in
        json)     cat "$CACHE_FILE" ;;
        username) jq -r '.username' "$CACHE_FILE" ;;
        email)    jq -r '.email' "$CACHE_FILE" ;;
        domain)   jq -r '.domain' "$CACHE_FILE" ;;
        data-root)
            local_email=$(jq -r '.email' "$CACHE_FILE")
            resolve_data_root "$local_email"
            ;;
        *)        echo "Unknown field: $FIELD" >&2; exit 1 ;;
    esac
    exit 0
fi

# Fall back to symlink detection (remote mode)
# Use ~/.claude/tools as the reference symlink (always exists, points to engine)
REFERENCE_SYMLINK="$HOME/.claude/tools"

# Get symlink target and extract Google Drive path
SYMLINK_TARGET=$(readlink "$REFERENCE_SYMLINK" 2>/dev/null || true)

if [[ -z "$SYMLINK_TARGET" ]]; then
    case "$FIELD" in
        json) echo '{"username":null,"email":null,"domain":null}' ;;
        *) echo "" ;;
    esac
    exit 0
fi

# Extract GoogleDrive-email@domain.com from path
# Example: /Users/.../GoogleDrive-yarik@finchclaims.com/Shared drives/...
if [[ "$SYMLINK_TARGET" =~ GoogleDrive-([^/]+) ]]; then
    EMAIL="${BASH_REMATCH[1]}"
    USERNAME="${EMAIL%@*}"
    DOMAIN="${EMAIL#*@}"
else
    case "$FIELD" in
        json) echo '{"username":null,"email":null,"domain":null}' ;;
        *) echo "" ;;
    esac
    exit 0
fi

case "$FIELD" in
    username) echo "$USERNAME" ;;
    email)    echo "$EMAIL" ;;
    domain)   echo "$DOMAIN" ;;
    data-root)
        # Remote mode: tools symlink points into GDrive, derive root from it
        # .../Shared drives/finch-os/engine/tools → .../Shared drives/finch-os
        echo "$SYMLINK_TARGET" | sed -E 's|/engine/tools$||'
        ;;
    json)     echo "{\"username\":\"$USERNAME\",\"email\":\"$EMAIL\",\"domain\":\"$DOMAIN\"}" ;;
    *)        echo "Unknown field: $FIELD" >&2; exit 1 ;;
esac
