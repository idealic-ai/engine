#!/bin/bash
# Test: session-start-chunk.sh slices a cached preload losslessly and handles
# overflow. Uses a fake generator + temp cache (no real SessionStart side effects).

set -uo pipefail

PASS=0; FAIL=0; ERRORS=""
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then PASS=$((PASS+1)); echo "  PASS: $label"
  else FAIL=$((FAIL+1)); echo "  FAIL: $label"; echo "    expected: $expected"; echo "    actual:   $actual"; fi
}

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

CHUNKER="$HOME/.claude/engine/hooks/session-start-chunk.sh"
CHUNK=8500
TOTAL=24
INPUT='{"hook_event_name":"SessionStart","source":"resume","session_id":"testsid","cwd":"/tmp"}'

# Fake generator: emits its FIXTURE file verbatim.
GEN="$SANDBOX/gen.sh"
cat > "$GEN" <<EOF
#!/bin/bash
cat "$SANDBOX/fixture.txt"
EOF
chmod +x "$GEN"

run_chunks() {
  # Concatenate all TOTAL slices in index order, raw (byte-faithful — no
  # command-substitution newline stripping). Writes to $2.
  local cachedir="$1" outfile="$2" i
  : > "$outfile"
  for ((i=0; i<TOTAL; i++)); do
    printf '%s' "$INPUT" | PRELOAD_GENERATOR="$GEN" PRELOAD_CACHE_DIR="$cachedir" PRELOAD_CHUNK_BYTES="$CHUNK" bash "$CHUNKER" "$i" "$TOTAL" >> "$outfile"
  done
}

# ============================================================
echo "=== C1: lossless reassembly (content fits in 24 slots) ==="
# ~50KB of numbered lines → ~6 chunks
: > "$SANDBOX/fixture.txt"
for ((n=0; n<1200; n++)); do
  printf 'line %04d: the quick brown fox jumps over the lazy dog 0123456789\n' "$n" >> "$SANDBOX/fixture.txt"
done
FIX_BYTES=$(wc -c < "$SANDBOX/fixture.txt" | tr -d ' ')
echo "  fixture size: $FIX_BYTES bytes"

CD1="$SANDBOX/cache1"
run_chunks "$CD1" "$SANDBOX/reassembled.txt"
FIX_SUM=$(shasum < "$SANDBOX/fixture.txt" | cut -d' ' -f1)
RE_SUM=$(shasum < "$SANDBOX/reassembled.txt" | cut -d' ' -f1)
assert_eq "C1: reassembled == generator output (byte-identical)" "$FIX_SUM" "$RE_SUM"

echo "=== C2: generator ran exactly once (cache created, single side effect) ==="
# Count generator invocations via a marker appended each run
GEN2="$SANDBOX/gen2.sh"
cat > "$GEN2" <<EOF
#!/bin/bash
echo "run" >> "$SANDBOX/gen2.count"
cat "$SANDBOX/fixture.txt"
EOF
chmod +x "$GEN2"
: > "$SANDBOX/gen2.count"
CD2="$SANDBOX/cache2"
for ((i=0; i<TOTAL; i++)); do
  printf '%s' "$INPUT" | PRELOAD_GENERATOR="$GEN2" PRELOAD_CACHE_DIR="$CD2" PRELOAD_CHUNK_BYTES="$CHUNK" bash "$CHUNKER" "$i" "$TOTAL" >/dev/null
done
GEN_RUNS=$(wc -l < "$SANDBOX/gen2.count" | tr -d ' ')
assert_eq "C2: generator invoked once across 24 slices" "1" "$GEN_RUNS"

echo "=== C3: every slice stays under the 9000-char truncation limit ==="
CD3="$SANDBOX/cache3"
MAXLEN=0
for ((i=0; i<TOTAL; i++)); do
  L=$(printf '%s' "$INPUT" | PRELOAD_GENERATOR="$GEN" PRELOAD_CACHE_DIR="$CD3" PRELOAD_CHUNK_BYTES="$CHUNK" bash "$CHUNKER" "$i" "$TOTAL" | wc -c | tr -d ' ')
  [ "$L" -gt "$MAXLEN" ] && MAXLEN="$L"
done
echo "  largest slice: $MAXLEN chars"
if [ "$MAXLEN" -lt 9000 ]; then assert_eq "C3: largest slice < 9000" "ok" "ok"; else assert_eq "C3: largest slice < 9000" "ok" "TOO_BIG($MAXLEN)"; fi

echo "=== C4: overflow emits a pointer on the last slot (content > 24 slots) ==="
# ~250KB → far more than 24 * 8500
: > "$SANDBOX/fixture.txt"
for ((n=0; n<4000; n++)); do
  printf 'line %05d: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n' "$n" >> "$SANDBOX/fixture.txt"
done
CD4="$SANDBOX/cache4"
LAST=$(printf '%s' "$INPUT" | PRELOAD_GENERATOR="$GEN" PRELOAD_CACHE_DIR="$CD4" PRELOAD_CHUNK_BYTES="$CHUNK" bash "$CHUNKER" $((TOTAL-1)) "$TOTAL")
if printf '%s' "$LAST" | grep -q "preload overflow"; then assert_eq "C4: last slot has overflow pointer" "ok" "ok"
else assert_eq "C4: last slot has overflow pointer" "ok" "MISSING"; fi

echo "=== C5: an aged cache (> STALE_MIN) is regenerated on a later event ==="
# A within-burst cache is immutable (reused); a cache older than STALE_MIN is
# cleaned + regenerated so a later same-key event isn't served stale.
: > "$SANDBOX/fixture.txt"
printf 'small preload body\n' > "$SANDBOX/fixture.txt"
: > "$SANDBOX/gen5.count"
GEN5="$SANDBOX/gen5.sh"
cat > "$GEN5" <<EOF
#!/bin/bash
echo "run" >> "$SANDBOX/gen5.count"
cat "$SANDBOX/fixture.txt"
EOF
chmod +x "$GEN5"
CD5="$SANDBOX/cache5"
printf '%s' "$INPUT" | PRELOAD_GENERATOR="$GEN5" PRELOAD_CACHE_DIR="$CD5" PRELOAD_CACHE_STALE_MIN=3 bash "$CHUNKER" 0 "$TOTAL" >/dev/null
touch -t 202001010000 "$CD5"/*.txt   # age far past STALE_MIN
printf '%s' "$INPUT" | PRELOAD_GENERATOR="$GEN5" PRELOAD_CACHE_DIR="$CD5" PRELOAD_CACHE_STALE_MIN=3 bash "$CHUNKER" 0 "$TOTAL" >/dev/null
RUNS5=$(wc -l < "$SANDBOX/gen5.count" | tr -d ' ')
assert_eq "C5: aged cache triggers regeneration (2 generations)" "2" "$RUNS5"

echo "=== C6: a single line longer than CHUNK is byte-split — no slice exceeds the limit, reassembly lossless ==="
# One 20000-byte line embedded among normal lines (models a pasted blob/diff).
{ printf 'header line\n'; printf 'A%.0s' $(seq 1 20000); printf '\n'; printf 'footer line\n'; } > "$SANDBOX/fixture.txt"
FIX6_SUM=$(shasum < "$SANDBOX/fixture.txt" | cut -d' ' -f1)
CD6="$SANDBOX/cache6"
: > "$SANDBOX/reassembled6.txt"; MAX6=0
for ((i=0; i<TOTAL; i++)); do
  OUT=$(printf '%s' "$INPUT" | PRELOAD_GENERATOR="$GEN" PRELOAD_CACHE_DIR="$CD6" PRELOAD_CHUNK_BYTES="$CHUNK" bash "$CHUNKER" "$i" "$TOTAL")
  L=$(printf '%s' "$OUT" | wc -c | tr -d ' '); [ "$L" -gt "$MAX6" ] && MAX6="$L"
  printf '%s' "$INPUT" | PRELOAD_GENERATOR="$GEN" PRELOAD_CACHE_DIR="$CD6" PRELOAD_CHUNK_BYTES="$CHUNK" bash "$CHUNKER" "$i" "$TOTAL" >> "$SANDBOX/reassembled6.txt"
done
echo "  largest slice with 20000-byte line: $MAX6"
if [ "$MAX6" -lt 9000 ]; then assert_eq "C6: no slice exceeds limit despite long line" "ok" "ok"; else assert_eq "C6: no slice exceeds limit despite long line" "ok" "TOO_BIG($MAX6)"; fi
RE6_SUM=$(shasum < "$SANDBOX/reassembled6.txt" | cut -d' ' -f1)
assert_eq "C6b: long-line reassembly byte-identical" "$FIX6_SUM" "$RE6_SUM"

echo "=== C7: an orphaned lock (winner died) is reclaimed — preload not wiped ==="
printf 'recovered body\n' > "$SANDBOX/fixture.txt"
CD7="$SANDBOX/cache7"; mkdir -p "$CD7"
# Simulate a dead winner: a lockdir with no cache, aged past LOCK_MIN(1).
KEY7=$(printf 'testsid_resume' | tr -c 'A-Za-z0-9._-' '_')
mkdir -p "$CD7/$KEY7.lockd"; touch -t 202001010000 "$CD7/$KEY7.lockd"
OUT7=$(printf '%s' "$INPUT" | PRELOAD_GENERATOR="$GEN" PRELOAD_CACHE_DIR="$CD7" PRELOAD_CHUNK_BYTES="$CHUNK" bash "$CHUNKER" 0 "$TOTAL")
if [ -n "$OUT7" ]; then assert_eq "C7: orphaned lock reclaimed, slice non-empty" "ok" "ok"; else assert_eq "C7: orphaned lock reclaimed, slice non-empty" "ok" "EMPTY"; fi

echo ""
echo "======================================="
echo "Results: $PASS passed, $FAIL failed"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
