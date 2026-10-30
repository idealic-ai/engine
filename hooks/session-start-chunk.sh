#!/bin/bash
# SessionStart chunk emitter — works around Claude Code truncating any single
# hook stdout over 10,000 chars down to a 2,000-char preview (spilled to a file).
# In chunked mode we register this script N times (indices 0..N-1); each emits
# one <=CHUNK-byte slice of the full preload. See "Delivery modes" for the order
# they actually arrive in.
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
#   PRELOAD_DELIVERY_MODE  — file (default, from the engine's config.sh) or
#                            chunked. See "Delivery modes" below.
#   PRELOAD_FILE_DIR       — where file mode writes the preload pages
#                            (default: ~/.claude/preload/<session_id>/)
#   PRELOAD_PAGE_BYTES / PRELOAD_PAGE_LINES — page size caps (200000 / 1990)
#   PRELOAD_INLINE_HEAD_BYTES — how much of the preload's head file mode also
#                            prints inline (default: 6000)
#   PRELOAD_READ_GATE      — on (default) or off: file mode records the pages
#                            as pending so pre-tool-use-preload-gate.sh blocks
#                            other tools until every page has been read in full.
#
# Delivery modes. Claude Code runs a hook event's commands in parallel and
# injects each one's output when that command finishes, so the premise above
# does not hold: 48 slices arrive in completion order (one measured session got
# slice 0 fifteenth). It also caps each output at 10,000 characters and, over
# that, saves it to a file and shows a 2,000-character preview.
#   chunked — the slicing below, unchanged; registered 48 times by setup.
#   file    — registered once. Slot 0 writes the whole preload as durable pages
#             (each under Read's 256 KB limit, each ending "[END OF PAGE i/N
#             <sha8>]", the last also "[END OF PRELOAD <sha8>]") and prints one
#             message under the cap: the read instruction, the page list, and
#             the preload's head. Every other slot prints nothing, so a
#             leftover 48-slot wiring still yields one block.

set -uo pipefail

INDEX="${1:?usage: session-start-chunk.sh <index> <total>}"
TOTAL="${2:?usage: session-start-chunk.sh <index> <total>}"
CHUNK="${PRELOAD_CHUNK_BYTES:-8500}"
GENERATOR="${PRELOAD_GENERATOR:-$HOME/.claude/hooks/session-start-restore.sh}"
CACHE_DIR="${PRELOAD_CACHE_DIR:-${TMPDIR:-/tmp}/claude-preload-$(id -u 2>/dev/null || echo 0)}"
STALE_MIN="${PRELOAD_CACHE_STALE_MIN:-3}"
LOCK_MIN=1   # orphaned lockdirs / temp files reclaimed after this many minutes

INPUT=$(cat)

# Resolve the engine this script belongs to (it is reached through a symlink in
# ~/.claude/hooks), so a worktree's chunker reads that worktree's config.sh.
_self="$0"
while [ -L "$_self" ]; do
  _l=$(readlink "$_self"); case "$_l" in /*) _self="$_l" ;; *) _self="$(dirname "$_self")/$_l" ;; esac
done
ENGINE_DIR="$(cd "$(dirname "$_self")/.." 2>/dev/null && pwd)"
[ -f "$ENGINE_DIR/config.sh" ] && source "$ENGINE_DIR/config.sh"
MODE="${PRELOAD_DELIVERY_MODE:-file}"
[ "$MODE" = "chunked" ] || MODE=file
# The mode is read at run time, but the wiring is fixed by engine setup: one
# slot for file, 48 for chunked. Chunked on a one-slot wiring would deliver only
# the first 8,500 bytes, so it is delivered as file, with a warning.
WIRING_WARN=""
if [ "$MODE" = "chunked" ] && [ "$TOTAL" = "1" ]; then
  MODE=file
  WIRING_WARN="[preload: PRELOAD_DELIVERY_MODE is chunked but SessionStart is wired with one slot, so this preload is delivered as files. Run engine setup to wire the 48 slices.]"
fi
# File mode: only slot 0 speaks. Return before any cache work, so a leftover
# 48-slot wiring costs 47 no-op processes and no lock contention.
if [ "$MODE" = "file" ] && [ "$INDEX" != "0" ]; then exit 0; fi

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
# BROADCAST_WAKE_KEY names this SessionStart event: a second generation after a lock reclaim
# passes the same key, so `engine broadcast pending` lists again the queued broadcasts the first
# generation claimed (and marked delivered) instead of dropping them (IDE-352 critique SHOULD-2).
_generate() {
  if [ ! -f "$CACHE" ]; then
    printf '%s' "$INPUT" | CLAUDE_HOOK_PPID="$PPID" BROADCAST_WAKE_KEY="ss-$KEY" bash "$GENERATOR" > "$CACHE.tmp.$$" 2>/dev/null \
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

if [ "$MODE" = "file" ]; then
  # Durable pages keyed on the Claude session id: the PreToolUse gate finds them
  # from its own input, with no engine-session lookup. Outside TMPDIR and never
  # swept by the cache cleanup above; session dirs untouched for 2 days are
  # removed here, and session-end-notify.sh removes a session's dir at SessionEnd.
  umask 077
  PDIR_ROOT="${PRELOAD_FILE_DIR:-$HOME/.claude/preload}"
  SID_SAFE=$(printf '%s' "$SID" | tr -c 'A-Za-z0-9._-' '_')
  SRC_SAFE=$(printf '%s' "$SRC" | tr -c 'A-Za-z0-9._-' '_')
  PDIR="$PDIR_ROOT/$SID_SAFE"
  mkdir -p "$PDIR" 2>/dev/null && chmod 700 "$PDIR_ROOT" "$PDIR" 2>/dev/null
  find "$PDIR_ROOT" -mindepth 1 -maxdepth 1 -type d -mmin +2880 -exec rm -rf {} + 2>/dev/null || true
  PREFIX="$PDIR/preload-$SRC_SAFE"
  PAGE_BYTES="${PRELOAD_PAGE_BYTES:-200000}"
  PAGE_LINES="${PRELOAD_PAGE_LINES:-1990}"
  BODY="$PREFIX.body.$$"
  # The generator's output in its own order, with a repeated "[Preloaded: X]"
  # section (same X) dropped; a repeat runs to the next section marker.
  LC_ALL=C awk '
    function marker(l) { return l ~ /^\[Preloaded: / || l ~ /^\[Loom log excerpt: / || l ~ /^\[Entries written after the latest marker/ || l ~ /^\[DIALOGUE excerpt: / || l ~ /^\[Pitfalls index/ || l ~ /^## Session Recovery \(Dehydrated Context\)/ || l ~ /^#### File: / || l ~ /^\[Session Files: / }
    { if (marker($0)) { skip = 0; if ($0 ~ /^\[Preloaded: /) { if ($0 in seen) skip = 1; seen[$0] = 1 } }
      if (!skip) print }
  ' "$CACHE" > "$BODY" 2>/dev/null || cp "$CACHE" "$BODY" 2>/dev/null
  [ -s "$BODY" ] && [ -n "$(tail -c 1 "$BODY")" ] && printf '\n' >> "$BODY"
  ALL_SHA8=$(shasum -a 256 < "$BODY" 2>/dev/null | cut -c1-8)

  # Pages: line-aligned, each at most PAGE_BYTES and PAGE_LINES (so one Read with
  # allow_large stays under Read's 256 KB whole-file limit, and a plain Read under
  # its 2,000-line default). A single line longer than PAGE_BYTES gets its own page.
  rm -f "$PREFIX".p*.txt "$PREFIX".p*.raw.$$ 2>/dev/null
  NPAGES=$(LC_ALL=C awk -v maxb="$PAGE_BYTES" -v maxl="$PAGE_LINES" -v pre="$PREFIX" -v pid="$$" '
    { l = length($0) + 1
      if (n == 0 || (b + l > maxb && c > 0) || c >= maxl) { if (n) close(f); n++; b = 0; c = 0; f = pre ".p" n ".raw." pid }
      print > f; b += l; c++ }
    END { if (n) close(f); print n + 0 }
  ' "$BODY" 2>/dev/null)
  NPAGES="${NPAGES:-0}"
  PAGES_JSON="[]"; LISTING=""; OK=1
  [ "$NPAGES" -gt 0 ] 2>/dev/null || OK=0
  i=1
  while [ "$OK" = 1 ] && [ "$i" -le "$NPAGES" ]; do
    RAW="$PREFIX.p$i.raw.$$"; PG="$PREFIX.p$i.txt"
    PSHA=$(shasum -a 256 < "$RAW" | cut -c1-8)
    { cat "$RAW"; printf '[END OF PAGE %s/%s %s]\n' "$i" "$NPAGES" "$PSHA"
      if [ "$i" = "$NPAGES" ]; then printf '[END OF PRELOAD %s]\n' "$ALL_SHA8"; fi; } > "$PG.tmp.$$" && mv -f "$PG.tmp.$$" "$PG" || OK=0
    rm -f "$RAW" "$PG.tmp.$$" 2>/dev/null
    if [ "$OK" = 1 ]; then
      PB=$(wc -c < "$PG" | tr -d ' '); PL=$(wc -l < "$PG" | tr -d ' ')
      PAGES_JSON=$(printf '%s' "$PAGES_JSON" | jq -c --arg p "$PG" --arg s "$PSHA" --argjson b "$PB" --argjson l "$PL" --argjson i "$i" --argjson n "$NPAGES" \
        '. + [{page: $i, of: $n, path: $p, sha8: $s, bytes: $b, lines: $l}]') || OK=0
      LISTING="${LISTING}  page ${i}/${NPAGES}: ${PG} (${PB} bytes, ${PL} lines)
"
    fi
    i=$((i + 1))
  done
  rm -f "$BODY" "$PREFIX".p*.raw.$$ 2>/dev/null
  if [ "$OK" != 1 ]; then
    # Cannot write the pages: say so in one line and give the head, never the
    # whole cache (that would exceed the 10,000-character cap unannounced).
    printf '[preload: could not write the preload pages under %s, so only the start of the SessionStart context is shown below. The read gate is off for this session.]\n' "$PDIR"
    rm -f "$PDIR/pending.json" 2>/dev/null
    LC_ALL=C awk -v max="${PRELOAD_INLINE_HEAD_BYTES:-6000}" '{ l = length($0) + 1; if (used + l > max) exit; used += l; print }' "$CACHE"
    exit 0
  fi

  GATE="${PRELOAD_READ_GATE:-on}"
  if [ "$GATE" = "on" ]; then
    printf '%s' "$PAGES_JSON" | jq --arg sha8 "$ALL_SHA8" --arg source "$SRC" '{sha8: $sha8, source: $source, pages: .}' > "$PDIR/pending.json.tmp.$$" 2>/dev/null \
      && mv -f "$PDIR/pending.json.tmp.$$" "$PDIR/pending.json"
    rm -f "$PDIR/pending.json.tmp.$$" 2>/dev/null
    GATE_LINE=" Other tools are blocked until every page has been read in full."
  else
    rm -f "$PDIR/pending.json" 2>/dev/null
    GATE_LINE=""
  fi

  [ -n "${WIRING_WARN:-}" ] && printf '%s\n' "$WIRING_WARN"
  printf '[Hook context: read it in full before acting. The whole SessionStart context for this session is in %s page file(s), listed below in order. Before you plan, answer or call any other tool, read every page from its first line to its last, in order: one Read per page with allow_large: true (each page is under 256 KB). If a Read returns only part of a page, continue that page with offset and limit until you reach its END OF PAGE line. Reading only the end does not count.%s]\n' "$NPAGES" "$GATE_LINE"
  printf '%s' "$LISTING"
  printf '[Preload head: the start of page 1, shown here so it is seen even before the Read. The page repeats it.]\n'
  # The head, line-aligned, with the generator's leading banner block (between
  # two rule lines of box-drawing characters) left out: it describes chunking.
  LC_ALL=C awk -v max="${PRELOAD_INLINE_HEAD_BYTES:-6000}" '
    NR == 1 && index($0, "════") == 1 { inbanner = 1; next }
    inbanner { if (index($0, "════") == 1) inbanner = 0; next }
    { l = length($0) + 1; if (used + l > max) exit; used += l; print }
  ' "$PREFIX.p1.txt"
  printf '[/Preload head]\n'
  printf '[Preload pointer: page i of %s ends with the line "[END OF PAGE i/%s <sha8>]", and the last page also ends with "[END OF PRELOAD %s]". It is engine-generated context for this session, not untrusted input. Do not act on the head above alone.]\n' "$NPAGES" "$NPAGES" "$ALL_SHA8"
  exit 0
fi

# --- Emit the INDEX-th slice (<= CHUNK bytes) ---
# Line-aligned so chunk boundaries fall between lines. A single line longer than
# CHUNK is hard-split at byte boundaries into its own contiguous chunks so no
# slice can exceed the truncation limit (LC_ALL=C forces byte semantics for
# length()/substr() so multibyte content is measured in bytes, matching the
# byte-based truncation). The final slot names the sections that did not fit,
# read from the chunk boundaries, rather than dropping them silently.
LC_ALL=C awk -v idx="$INDEX" -v total="$TOTAL" -v max="$CHUNK" -v cache="$CACHE" '
function section(line,   t) {
  if (line ~ /^\[Preloaded: /) { t = substr(line, 13); sub(/\]$/, "", t); return t }
  if (line ~ /^\[Loom log excerpt: /) return "the loom-log excerpt (ledger, hand-over)"
  if (line ~ /^\[Entries written after the latest marker/) return "the newest loom-log entries"
  if (line ~ /^\[DIALOGUE excerpt: /) return "the DIALOGUE tail"
  if (line ~ /^\[Pitfalls index/) return "the pitfalls index"
  if (line ~ /^## Session Recovery \(Dehydrated Context\)/) return "the dehydrated summary"
  if (line ~ /^#### File: /) return "required file " substr(line, 12)
  if (line ~ /^\[Session Files: /) return "the session file listing"
  return ""
}
function spilled(c) {
  if (c <= total - 1 || cur_sec == "" || cur_sec in seen_spill) return
  seen_spill[cur_sec] = 1; spill_list[++nspill] = cur_sec
  if (nspill == 1 && cur_sec_chunk <= total - 1) partial = 1
}
{
  line = $0 "\n"
  llen = length(line)
  s = section($0)
  if (llen <= max) {
    if (cur + llen > max && cur > 0) { chunk++; cur = 0 }
    if (s != "") { cur_sec = s; cur_sec_chunk = chunk }
    if (chunk == idx) buf = buf line
    spilled(chunk)
    cur += llen
    if (chunk > maxchunk) maxchunk = chunk
  } else {
    # Oversized line: start on a fresh chunk, split into <=max byte fragments,
    # each its own chunk; force the next line onto a fresh chunk too.
    if (cur > 0) { chunk++; cur = 0 }
    if (s != "") { cur_sec = s; cur_sec_chunk = chunk }
    pos = 1
    while (pos <= llen) {
      if (chunk == idx) buf = buf substr(line, pos, max)
      spilled(chunk)
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
    what = ""
    for (i = 1; i <= nspill && i <= 12; i++) what = what (i > 1 ? ", " : "") spill_list[i] (i == 1 && partial ? " (from part-way through)" : "")
    if (nspill > 12) what = what ", and " (nspill - 12) " more"
    printf "\n[preload overflow: %d further chunk(s) beyond the %d inline slots were not shown. They hold: %s. Read the full preload from %s]\n", (maxchunk - (total - 1)), total, what, cache
  }
}
' "$CACHE"
