#!/bin/bash
# Test: session-start-chunk.sh delivery modes (PRELOAD_DELIVERY_MODE in config.sh).
#   file    (default) — slot 0 writes the whole preload as durable pages, each
#                       ending "[END OF PAGE i/N <sha8>]", the last also
#                       "[END OF PRELOAD <sha8>]", and prints ONE message under
#                       the 10,000-character hook cap: the read instruction first,
#                       the page list, the preload's head, the pointer.
#   chunked           — today's slices (covered by test-session-start-chunk.sh).
# Uses a fake generator + temp dirs (no real SessionStart side effects).

set -uo pipefail

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; }
assert_eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected: $2 | actual: $3"; fi; }

ENGINE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CHUNKER="${CHUNKER:-$ENGINE_DIR/hooks/session-start-chunk.sh}"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
PDIR="$HOME/.claude/preload-test-$$"     # outside TMPDIR on purpose, removed below
trap 'rm -rf "$SANDBOX" "$PDIR"' EXIT
INPUT='{"hook_event_name":"SessionStart","source":"clear","session_id":"modesid","cwd":"/tmp"}'
HEADER_START='[Hook context: read it in full before acting.'
P1="$PDIR/modesid/preload-clear.p1.txt"; P2="$PDIR/modesid/preload-clear.p2.txt"

GEN="$SANDBOX/gen.sh"
printf '#!/bin/bash\ncat %q\n' "$SANDBOX/fixture.txt" > "$GEN"; chmod +x "$GEN"

# slot <cachedir> <index> <total> [mode] — one hook invocation, raw stdout.
slot() {
  local cd="$1" i="$2" t="$3" mode="${4:-}"
  if [ -n "$mode" ]; then
    printf '%s' "$INPUT" | PRELOAD_DELIVERY_MODE="$mode" PRELOAD_GENERATOR="$GEN" PRELOAD_CACHE_DIR="$cd" PRELOAD_FILE_DIR="$PDIR" bash "$CHUNKER" "$i" "$t"
  else
    printf '%s' "$INPUT" | env -u PRELOAD_DELIVERY_MODE -u PRELOAD_READ_GATE PRELOAD_GENERATOR="$GEN" PRELOAD_CACHE_DIR="$cd" PRELOAD_FILE_DIR="$PDIR" bash "$CHUNKER" "$i" "$t"
  fi
}

# A banner block, then ordered sections with one repeated, ~250KB: far past
# 48 slots of 8500 bytes and past the 10,000-character cap.
{
  echo "════════════════"; echo "BANNER_TEXT_ABOUT_CHUNKS"; echo "════════════════"
  echo "[Session Context] FIT_SESSION_LINE"
  for s in 1 2 3 4 5 6; do
    echo "[Preloaded: /fit/SECTION_$s.md]"
    for ((n=0; n<600; n++)); do printf 'section %d line %04d: the quick brown fox jumps over the lazy dog 0123456789\n' "$s" "$n"; done
  done
  echo "[Preloaded: /fit/SECTION_2.md]"; echo "REPEATED_SECTION_BODY"
  echo "[Pitfalls index, fit]"; echo "FIT_LAST_LINE"
} > "$SANDBOX/fixture.txt"
echo "  fixture: $(wc -c < "$SANDBOX/fixture.txt" | tr -d ' ') bytes"

echo "=== M1: the shipped default is file (read from the engine's config.sh) ==="
assert_eq "M1: config.sh sets the default to file" 'PRELOAD_DELIVERY_MODE="${PRELOAD_DELIVERY_MODE:-file}"' "$(grep -E '^PRELOAD_DELIVERY_MODE=' "$ENGINE_DIR/config.sh" || true)"

echo "=== M2: file mode — slot 0 prints one message under the cap, read instruction first ==="
slot "$SANDBOX/c2" 0 1 > "$SANDBOX/s0.txt"
FIRST=$(head -n 1 "$SANDBOX/s0.txt")
case "$FIRST" in "$HEADER_START"*) pass "M2a: output starts with the read instruction" ;; *) fail "M2a: output starts with the read instruction" "first line: ${FIRST:0:120}" ;; esac
# UTF-16 units <= UTF-8 bytes, so a byte count under 10,000 is under the cap.
B=$(wc -c < "$SANDBOX/s0.txt" | tr -d ' ')
if [ "$B" -lt 10000 ]; then pass "M2b: inline message under 10,000 ($B bytes)"; else fail "M2b: inline message under 10,000" "$B bytes"; fi
grep -qF "allow_large: true" "$SANDBOX/s0.txt" && pass "M2c: names how to read it (allow_large)" || fail "M2c: names how to read it"
grep -qF "Reading only the end does not count" "$SANDBOX/s0.txt" && pass "M2c2: says a tail read does not count" || fail "M2c2: says a tail read does not count"
grep -q "one Read call" "$SANDBOX/s0.txt" && fail "M2c3: no longer promises one Read call" || pass "M2c3: no longer promises one Read call"
L1=$(grep -nF "page 1/2: $P1 (" "$SANDBOX/s0.txt" | cut -d: -f1); L2=$(grep -nF "page 2/2: $P2 (" "$SANDBOX/s0.txt" | cut -d: -f1)
if [ -n "$L1" ] && [ -n "$L2" ] && [ "$L1" -lt "$L2" ]; then pass "M2d: lists both pages, in order"; else fail "M2d: lists both pages, in order" "p1=$L1 p2=$L2"; fi
grep -qF 'FIT_SESSION_LINE' "$SANDBOX/s0.txt" && pass "M2e: head carries the session line inline" || fail "M2e: head carries the session line inline"
grep -qF 'BANNER_TEXT_ABOUT_CHUNKS' "$SANDBOX/s0.txt" && fail "M2f: leading banner block left out of the head" || pass "M2f: leading banner block left out of the head"
grep -q 'preload overflow' "$SANDBOX/s0.txt" && fail "M2g: no overflow notice" || pass "M2g: no overflow notice"
H_OPEN=$(grep -n '^\[Preload head' "$SANDBOX/s0.txt" | cut -d: -f1); P_LINE=$(grep -n '^\[Preload pointer' "$SANDBOX/s0.txt" | cut -d: -f1)
if [ -n "$L2" ] && [ -n "$H_OPEN" ] && [ -n "$P_LINE" ] && [ "$L2" -lt "$H_OPEN" ] && [ "$H_OPEN" -lt "$P_LINE" ]; then pass "M2h: instruction, pages, head, pointer in that order"; else fail "M2h: instruction, pages, head, pointer in that order" "pages=$L2 head=$H_OPEN pointer=$P_LINE"; fi

echo "=== M3: the pages — whole, in source order, each under the Read limits, sentinels match ==="
{ [ -f "$P1" ] && [ -f "$P2" ] && [ ! -e "$PDIR/modesid/preload-clear.p3.txt" ]; } && pass "M3a: exactly two pages" || fail "M3a: exactly two pages"
case "$P1" in "${TMPDIR:-/tmp}"*) fail "M3b: pages are outside TMPDIR" ;; *) pass "M3b: pages are outside TMPDIR" ;; esac
C1=$(sed '$d' "$P1" | shasum -a 256 | cut -c1-8); C2=$(sed '$d' "$P2" | sed '$d' | shasum -a 256 | cut -c1-8)
assert_eq "M3c: page 1 ends with its own sha8" "[END OF PAGE 1/2 $C1]" "$(tail -n 1 "$P1")"
assert_eq "M3c2: page 2 ends with its own sha8, then the preload's" "[END OF PAGE 2/2 $C2]" "$(tail -n 2 "$P2" | head -n 1)"
joined() { sed '$d' "$P1"; sed '$d' "$P2" | sed '$d'; }
ALL=$(joined | shasum -a 256 | cut -c1-8)
assert_eq "M3c3: last line is the preload sentinel over both pages" "[END OF PRELOAD $ALL]" "$(tail -n 1 "$P2")"
for P in "$P1" "$P2"; do
  PB=$(wc -c < "$P" | tr -d ' '); PL=$(wc -l < "$P" | tr -d ' ')
  PN=${P##*/}
  if [ "$PB" -le 200100 ] && [ "$PL" -le 2000 ]; then pass "M3d: $PN under the caps, $PB B, $PL lines"; else fail "M3d: $PN under the caps" "$PB B, $PL lines"; fi
done
joined > "$SANDBOX/got.txt"
ORDER=$(grep -o '^\[Preloaded: /fit/SECTION_[0-9]' "$SANDBOX/got.txt" | grep -o '[0-9]$' | tr -d '\n')
assert_eq "M3e: sections in source order, the repeat dropped" "123456" "$ORDER"
grep -qF REPEATED_SECTION_BODY "$SANDBOX/got.txt" && fail "M3f: repeated section's body dropped" || pass "M3f: repeated section's body dropped"
grep -qF FIT_LAST_LINE "$SANDBOX/got.txt" && pass "M3g: the section after a dropped repeat is kept" || fail "M3g: the section after a dropped repeat is kept"
grep -vxF -e REPEATED_SECTION_BODY "$SANDBOX/fixture.txt" | awk '!($0 == "[Preloaded: /fit/SECTION_2.md]" && seen++)' > "$SANDBOX/exp.txt"
assert_eq "M3h: pages joined == generator output minus the repeat (byte-identical)" "$(shasum < "$SANDBOX/exp.txt" | cut -d' ' -f1)" "$(shasum < "$SANDBOX/got.txt" | cut -d' ' -f1)"
assert_eq "M3i: pages are private (0600)" "600" "$(stat -f '%Lp' "$P1")"
assert_eq "M3j: pending.json is private (0600)" "600" "$(stat -f '%Lp' "$PDIR/modesid/pending.json")"

echo "=== M4: retention — the cache sweep spares pages; session dirs older than 2 days go ==="
touch -t 202001010000 "$P1"
slot "$SANDBOX/c2" 0 48 chunked > /dev/null   # a later run sweeps the cache dir
[ -f "$P1" ] && pass "M4a: page still there after the cache sweep" || fail "M4a: page still there after the cache sweep"
mkdir -p "$PDIR/oldsid"; touch -t 202001010000 "$PDIR/oldsid"
mkdir -p "$PDIR/recentsid"
slot "$SANDBOX/c4" 0 1 > /dev/null
[ -e "$PDIR/oldsid" ] && fail "M4b: a session dir older than 2 days is removed" || pass "M4b: a session dir older than 2 days is removed"
[ -d "$PDIR/recentsid" ] && pass "M4c: a recent session dir is kept" || fail "M4c: a recent session dir is kept"
printf '{"session_id":"modesid","reason":"exit"}' | env -u TMUX PRELOAD_FILE_DIR="$PDIR" bash "$ENGINE_DIR/hooks/session-end-notify.sh"
[ -e "$PDIR/modesid" ] && fail "M4d: SessionEnd removes the session's pages" || pass "M4d: SessionEnd removes the session's pages"
[ -d "$PDIR/recentsid" ] && pass "M4e: SessionEnd leaves other sessions alone" || fail "M4e: SessionEnd leaves other sessions alone"

echo "=== M5: file mode — slots 1..47 print nothing; a 48-slot burst is one block ==="
BLOCKS=0
for ((i=0; i<48; i++)); do OUT=$(slot "$SANDBOX/c5" "$i" 48); [ -n "$OUT" ] && BLOCKS=$((BLOCKS+1)); done
assert_eq "M5: one non-empty hook output per event" "1" "$BLOCKS"

echo "=== M6: pending record lists the pages; PRELOAD_READ_GATE=off writes none ==="
PEND="$PDIR/modesid/pending.json"
assert_eq "M6a: pending.json lists both pages in order" "$P1 $P2" "$(jq -r '[.pages[].path] | join(" ")' "$PEND" 2>/dev/null)"
assert_eq "M6b: pending.json carries each page's sha8" "$(tail -n 2 "$P2" | head -n 1 | grep -o '[0-9a-f]\{8\}\]$' | tr -d ']')" "$(jq -r '.pages[1].sha8' "$PEND" 2>/dev/null)"
printf '%s' "$INPUT" | PRELOAD_READ_GATE=off PRELOAD_GENERATOR="$GEN" PRELOAD_CACHE_DIR="$SANDBOX/c6" PRELOAD_FILE_DIR="$PDIR" bash "$CHUNKER" 0 1 > "$SANDBOX/s6.txt"
[ -f "$PEND" ] && fail "M6c: gate off leaves no pending record" || pass "M6c: gate off leaves no pending record"
grep -qF 'blocked' "$SANDBOX/s6.txt" && fail "M6d: gate off message does not claim a block" || pass "M6d: gate off message does not claim a block"

echo "=== M7: chunked mode — slot 0 is today's slice, no header, no pages ==="
rm -rf "$PDIR"
S0C=$(slot "$SANDBOX/c7" 0 48 chunked)
case "$S0C" in "$HEADER_START"*) fail "M7a: chunked slot has no header" ;; *) pass "M7a: chunked slot has no header" ;; esac
L7=$(printf '%s' "$S0C" | wc -c | tr -d ' ')
assert_eq "M7b: chunked slot 0 is the first bytes of the preload" "$(head -c "$L7" "$SANDBOX/fixture.txt" | shasum | cut -d' ' -f1)" "$(printf '%s' "$S0C" | shasum | cut -d' ' -f1)"
[ -e "$PDIR" ] && fail "M7c: chunked mode writes no pages" || pass "M7c: chunked mode writes no pages"

echo "=== M8: an unknown mode value falls back to file ==="
S8=$(slot "$SANDBOX/c8" 0 1 bogus | head -n 1)
case "$S8" in "$HEADER_START"*) pass "M8: unknown mode delivers as file" ;; *) fail "M8: unknown mode delivers as file" "${S8:0:80}" ;; esac

echo "=== M9: chunked on the one-slot wiring is delivered as file, with a warning ==="
slot "$SANDBOX/c9" 0 1 chunked > "$SANDBOX/s9.txt"
case "$(head -n 1 "$SANDBOX/s9.txt")" in "[preload: PRELOAD_DELIVERY_MODE is chunked but SessionStart is wired with one slot"*) pass "M9a: warning line first" ;; *) fail "M9a: warning line first" "$(head -c 120 "$SANDBOX/s9.txt")" ;; esac
grep -qF "$HEADER_START" "$SANDBOX/s9.txt" && pass "M9b: then the file-mode message" || fail "M9b: then the file-mode message"

echo "=== M10: a write failure prints one line and the head, not the whole cache ==="
: > "$SANDBOX/notadir"
printf '%s' "$INPUT" | env -u PRELOAD_DELIVERY_MODE PRELOAD_GENERATOR="$GEN" PRELOAD_CACHE_DIR="$SANDBOX/c10" PRELOAD_FILE_DIR="$SANDBOX/notadir" bash "$CHUNKER" 0 1 > "$SANDBOX/s10.txt"
case "$(head -n 1 "$SANDBOX/s10.txt")" in "[preload: could not write the preload pages"*) pass "M10a: one-line notice first" ;; *) fail "M10a: one-line notice first" "$(head -c 120 "$SANDBOX/s10.txt")" ;; esac
B10=$(wc -c < "$SANDBOX/s10.txt" | tr -d ' ')
if [ "$B10" -lt 10000 ]; then pass "M10b: under the cap, $B10 bytes"; else fail "M10b: under the cap" "$B10 bytes"; fi

echo ""
echo "======================================="
echo "Results: $PASS passed, $FAIL failed"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
