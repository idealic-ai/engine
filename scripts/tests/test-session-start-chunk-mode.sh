#!/bin/bash
# Test: session-start-chunk.sh delivery modes (PRELOAD_DELIVERY_MODE in config.sh).
#   file    (default) — slot 0 writes the whole preload to a durable file ending
#                       in "[END OF PRELOAD <sha8>]" and prints ONE message under
#                       the 10,000-character hook cap: the read instruction first,
#                       the preload's head, then the pointer. Other slots: nothing.
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
PFILE="$PDIR/modesid/preload-clear.txt"

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
grep -qF "$PFILE" "$SANDBOX/s0.txt" && pass "M2d: names the durable path" || fail "M2d: names the durable path"
grep -qF 'FIT_SESSION_LINE' "$SANDBOX/s0.txt" && pass "M2e: head carries the session line inline" || fail "M2e: head carries the session line inline"
grep -qF 'BANNER_TEXT_ABOUT_CHUNKS' "$SANDBOX/s0.txt" && fail "M2f: leading banner block left out of the head" || pass "M2f: leading banner block left out of the head"
grep -q 'preload overflow' "$SANDBOX/s0.txt" && fail "M2g: no overflow notice" || pass "M2g: no overflow notice"
H_OPEN=$(grep -n '^\[Preload head' "$SANDBOX/s0.txt" | cut -d: -f1); P_LINE=$(grep -n '^\[Preload pointer' "$SANDBOX/s0.txt" | cut -d: -f1)
if [ -n "$H_OPEN" ] && [ -n "$P_LINE" ] && [ "$H_OPEN" -lt "$P_LINE" ]; then pass "M2h: instruction, head, pointer in that order"; else fail "M2h: instruction, head, pointer in that order" "head=$H_OPEN pointer=$P_LINE"; fi

echo "=== M3: the durable file — whole, in source order, sentinel sha matches ==="
[ -f "$PFILE" ] && pass "M3a: file exists" || fail "M3a: file exists"
case "$PFILE" in "${TMPDIR:-/tmp}"*) fail "M3b: file is outside TMPDIR" ;; *) pass "M3b: file is outside TMPDIR" ;; esac
LAST=$(tail -n 1 "$PFILE")
BODY_SHA=$(sed '$d' "$PFILE" | shasum -a 256 | cut -c1-8)
assert_eq "M3c: last line is the sentinel with the body's sha8" "[END OF PRELOAD $BODY_SHA]" "$LAST"
ORDER=$(grep -o '^\[Preloaded: /fit/SECTION_[0-9]' "$PFILE" | grep -o '[0-9]$' | tr -d '\n')
assert_eq "M3d: sections in source order, the repeat dropped" "123456" "$ORDER"
grep -qF REPEATED_SECTION_BODY "$PFILE" && fail "M3e: repeated section's body dropped" || pass "M3e: repeated section's body dropped"
grep -qF FIT_LAST_LINE "$PFILE" && pass "M3f: the section after a dropped repeat is kept" || fail "M3f: the section after a dropped repeat is kept"
# Everything else byte-identical: the fixture minus the repeat == the body.
grep -vxF -e '[Preloaded: /fit/SECTION_2.md]' -e REPEATED_SECTION_BODY "$SANDBOX/fixture.txt" > "$SANDBOX/exp.txt"
sed '$d' "$PFILE" | grep -vxF '[Preloaded: /fit/SECTION_2.md]' > "$SANDBOX/got.txt"
assert_eq "M3g: body otherwise byte-identical to the generator output" "$(shasum < "$SANDBOX/exp.txt" | cut -d' ' -f1)" "$(shasum < "$SANDBOX/got.txt" | cut -d' ' -f1)"

echo "=== M4: the durable file survives the chunker's stale-cache sweep ==="
touch -t 202001010000 "$PFILE"
slot "$SANDBOX/c2" 0 1 chunked > /dev/null   # a later run sweeps the cache dir
[ -f "$PFILE" ] && pass "M4: file still there after the sweep" || fail "M4: file still there after the sweep"

echo "=== M5: file mode — slots 1..47 print nothing; a 48-slot burst is one block ==="
BLOCKS=0
for ((i=0; i<48; i++)); do OUT=$(slot "$SANDBOX/c5" "$i" 48); [ -n "$OUT" ] && BLOCKS=$((BLOCKS+1)); done
assert_eq "M5: one non-empty hook output per event" "1" "$BLOCKS"

echo "=== M6: pending record written for the gate; PRELOAD_READ_GATE=off writes none ==="
PEND="$PDIR/modesid/pending.json"
assert_eq "M6a: pending.json names the file" "$PFILE" "$(jq -r .path "$PEND" 2>/dev/null)"
assert_eq "M6b: pending.json carries the sentinel sha8" "$BODY_SHA" "$(jq -r .sha8 "$PEND" 2>/dev/null)"
printf '%s' "$INPUT" | PRELOAD_READ_GATE=off PRELOAD_GENERATOR="$GEN" PRELOAD_CACHE_DIR="$SANDBOX/c6" PRELOAD_FILE_DIR="$PDIR" bash "$CHUNKER" 0 1 > "$SANDBOX/s6.txt"
[ -f "$PEND" ] && fail "M6c: gate off leaves no pending record" || pass "M6c: gate off leaves no pending record"
grep -qF 'blocked' "$SANDBOX/s6.txt" && fail "M6d: gate off message does not claim a block" || pass "M6d: gate off message does not claim a block"

echo "=== M7: chunked mode — slot 0 is today's slice, no header, no file ==="
rm -rf "$PDIR"
S0C=$(slot "$SANDBOX/c7" 0 48 chunked)
case "$S0C" in "$HEADER_START"*) fail "M7a: chunked slot has no header" ;; *) pass "M7a: chunked slot has no header" ;; esac
L7=$(printf '%s' "$S0C" | wc -c | tr -d ' ')
assert_eq "M7b: chunked slot 0 is the first bytes of the preload" "$(head -c "$L7" "$SANDBOX/fixture.txt" | shasum | cut -d' ' -f1)" "$(printf '%s' "$S0C" | shasum | cut -d' ' -f1)"
[ -e "$PDIR" ] && fail "M7c: chunked mode writes no durable file" || pass "M7c: chunked mode writes no durable file"

echo "=== M8: an unknown mode value falls back to file ==="
S8=$(slot "$SANDBOX/c8" 0 1 bogus | head -n 1)
case "$S8" in "$HEADER_START"*) pass "M8: unknown mode delivers as file" ;; *) fail "M8: unknown mode delivers as file" "${S8:0:80}" ;; esac

echo ""
echo "======================================="
echo "Results: $PASS passed, $FAIL failed"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
