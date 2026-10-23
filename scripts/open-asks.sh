#!/bin/bash
# open-asks.sh — list lane asks with no later answer, across every *_LOG.md under a session dir.
#   engine open-asks <sessionDir>
# An ask is a "## [TAG] ❓ Ask <id>: …" heading; a later "## [TAG] ✅ Answered <id>" in the same
# log closes it, and an ask written after its answer reopens it. Exit 0 = none open, 3 = some open.
set -uo pipefail
SESSION_DIR="${1:?usage: engine open-asks <sessionDir>}"
[ -d "$SESSION_DIR" ] || { echo "open-asks: not a directory: $SESSION_DIR" >&2; exit 2; }
logs=0; open=0
while IFS= read -r -d '' log; do
  logs=$((logs + 1))
  found=$(awk '
    function key(kind,   s) { s = substr($0, RSTART, RLENGTH); sub(kind, "", s); sub(/[ :].*/, "", s)
      match($0, /\[[A-Za-z0-9_-]+\] /); return substr($0, RSTART, RLENGTH) s }
    /^## / && match($0, /\[[A-Za-z0-9_-]+\] ❓ Ask [^ :]+/) { k = key(".*❓ Ask "); ask[k] = $0; if (!(k in seen)) { seen[k] = 1; order[++n] = k }; delete closed[k]; next }
    /^## / && match($0, /\[[A-Za-z0-9_-]+\] ✅ Answered [^ :]+/) { k = key(".*✅ Answered "); closed[k] = 1 }
    END { for (i = 1; i <= n; i++) if (!(order[i] in closed)) print ask[order[i]] }' "$log")
  [ -z "$found" ] && continue
  while IFS= read -r line; do echo "OPEN $log: $line"; open=$((open + 1)); done <<<"$found"
done < <(find "$SESSION_DIR" -name '*_LOG.md' -type f -print0)
echo "open asks: $open · logs read: $logs"
[ "$open" -gt 0 ] && exit 3 || exit 0
