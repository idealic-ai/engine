#!/bin/bash
# SessionStart chunk emitter — works around Claude Code truncating any single
# hook stdout over ~9000 chars down to ~2000 (spilled to a file). We register
# this script N times (indices 0..N-1); each emits one <=CHUNK-byte slice of the
# full preload. Claude Code concatenates the slices back inline, in order.
#
# Usage (per settings.json hook entry): session-start-chunk.sh <index> <total>
# Input (stdin): the SessionStart hook JSON ({session_id, source, cwd, ...})
# Output (stdout): this index's slice of the preload (empty if beyond the end).
#
# The full preload is produced ONCE per SessionStart event by the generator
# (session-start-restore.sh) and cached; every index slices the same immutable
# bytes so the pieces reassemble losslessly regardless of execution order.
#
# Design premise (unverifiable from here — confirm on restart): Claude Code
# concatenates the N hook stdouts in registration order, inline, without
# inserting separators. Slices are line-aligned to degrade gracefully (blank
# lines between lines, not mid-line corruption) if a separator ever appears.
#
# Env overrides (for tests):
#   PRELOAD_GENERATOR      — command producing the full preload (default: the
#                            session-start-restore.sh generator)
#   PRELOAD_CACHE_DIR      — cache directory (default: per-user temp dir)
#   PRELOAD_CHUNK_BYTES    — slice size in bytes (default: 8500)
#   PRELOAD_CACHE_STALE_MIN — minutes before a cache is regenerated (default: 3).
#                            Must exceed the worst-case burst so slices of one
#                            event never straddle two generations.

set -uo pipefail

INDEX="${1:?usage: session-start-chunk.sh <index> <total>}"
TOTAL="${2:?usage: session-start-chunk.sh <index> <total>}"
CHUNK="${PRELOAD_CHUNK_BYTES:-8500}"
GENERATOR="${PRELOAD_GENERATOR:-$HOME/.claude/hooks/session-start-restore.sh}"
CACHE_DIR="${PRELOAD_CACHE_DIR:-${TMPDIR:-/tmp}/claude-preload-$(id -u 2>/dev/null || echo 0)}"
STALE_MIN="${PRELOAD_CACHE_STALE_MIN:-3}"
LOCK_MIN=1   # orphaned lockdirs / temp files reclaimed after this many minutes

INPUT=$(cat)

# Cache key: one preload per SessionStart event (session_id + source), sanitized.
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosid"' 2>/dev/null || echo "nosid")
SRC=$(printf '%s' "$INPUT" | jq -r '.source // "unknown"' 2>/dev/null || echo "unknown")
KEY=$(printf '%s_%s' "$SID" "$SRC" | tr -c 'A-Za-z0-9._-' '_')
mkdir -p "$CACHE_DIR" 2>/dev/null || true
chmod 700 "$CACHE_DIR" 2>/dev/null || true
CACHE="$CACHE_DIR/$KEY.txt"
LOCKDIR="$CACHE_DIR/$KEY.lockd"

# --- Opportunistic cleanup (cheap, idempotent, runs on every slice) ---
# Regenerate across events: drop this key's cache once it ages past STALE_MIN, so
# a later same-key event rebuilds. STALE_MIN >> a burst (seconds), so this never
# deletes a cache mid-burst. Also reclaim orphaned locks / temp files (a winner
# killed mid-generation) so a dead generation can't wipe the preload forever.
find "$CACHE_DIR" -maxdepth 1 -name '*.txt'   -mmin +"$STALE_MIN" -delete       2>/dev/null || true
find "$CACHE_DIR" -maxdepth 1 -name '*.tmp.*' -mmin +"$LOCK_MIN"  -delete       2>/dev/null || true
find "$CACHE_DIR" -maxdepth 1 -type d -name '*.lockd' -mmin +"$LOCK_MIN" -exec rmdir {} + 2>/dev/null || true

# --- Generate once, feeding the generator our stdin ---
# `mkdir` is an atomic, portable lock (macOS has no flock). The winner generates;
# followers wait for the cache. If the winner dies (leaving an orphan lock), a
# follower reclaims the lock after a bounded wait and generates itself, so a
# killed generation never permanently empties the preload. Exporting the
# chunker's own PPID (= Claude's PID) lets the generator key its seed/preload
# state to Claude's process rather than this transient chunker's PID.
_generate() {
  if [ ! -f "$CACHE" ]; then
    printf '%s' "$INPUT" | CLAUDE_HOOK_PPID="$PPID" bash "$GENERATOR" > "$CACHE.tmp.$$" 2>/dev/null \
      && mv -f "$CACHE.tmp.$$" "$CACHE" 2>/dev/null
    rm -f "$CACHE.tmp.$$" 2>/dev/null || true
  fi
}

if [ ! -f "$CACHE" ]; then
  if mkdir "$LOCKDIR" 2>/dev/null; then
    _generate
    rmdir "$LOCKDIR" 2>/dev/null || true
  else
    # Follower: wait ~12s for the winner's cache, then assume the winner died,
    # reclaim the orphaned lock, and generate ourselves.
    waited=""
    for _ in $(seq 1 240); do
      [ -f "$CACHE" ] && { waited=done; break; }
      sleep 0.05
    done
    if [ -z "$waited" ] && [ ! -f "$CACHE" ]; then
      rmdir "$LOCKDIR" 2>/dev/null || true
      if mkdir "$LOCKDIR" 2>/dev/null; then
        _generate
        rmdir "$LOCKDIR" 2>/dev/null || true
      else
        # someone else re-acquired — give it a short grace period
        for _ in $(seq 1 200); do [ -f "$CACHE" ] && break; sleep 0.05; done
      fi
    fi
  fi
fi

[ -f "$CACHE" ] || exit 0

# --- Emit the INDEX-th slice (<= CHUNK bytes) ---
# Line-aligned so chunk boundaries fall between lines. A single line longer than
# CHUNK is hard-split at byte boundaries into its own contiguous chunks so no
# slice can exceed the truncation limit (LC_ALL=C forces byte semantics for
# length()/substr() so multibyte content is measured in bytes, matching the
# byte-based truncation). The final slot names any un-inlined overflow rather
# than dropping it silently.
LC_ALL=C awk -v idx="$INDEX" -v total="$TOTAL" -v max="$CHUNK" -v cache="$CACHE" '
{
  line = $0 "\n"
  llen = length(line)
  if (llen <= max) {
    if (cur + llen > max && cur > 0) { chunk++; cur = 0 }
    if (chunk == idx) buf = buf line
    cur += llen
    if (chunk > maxchunk) maxchunk = chunk
  } else {
    # Oversized line: start on a fresh chunk, split into <=max byte fragments,
    # each its own chunk; force the next line onto a fresh chunk too.
    if (cur > 0) { chunk++; cur = 0 }
    pos = 1
    while (pos <= llen) {
      if (chunk == idx) buf = buf substr(line, pos, max)
      if (chunk > maxchunk) maxchunk = chunk
      pos += max
      if (pos <= llen) chunk++
    }
    chunk++; cur = 0
  }
}
END {
  printf "%s", buf
  if (idx == total - 1 && maxchunk > total - 1) {
    printf "\n[preload overflow: %d further chunk(s) beyond the %d inline slots were not shown — later preload sections (e.g. session debrief / DIALOGUE). Read the full preload from %s]\n", (maxchunk - (total - 1)), total, cache
  }
}
' "$CACHE"
