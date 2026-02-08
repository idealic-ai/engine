#!/bin/bash
# tests/test-log-sh.sh — Tests for log.sh auto-timestamp injection
# Run: bash ~/.claude/engine/scripts/tests/test-log-sh.sh

set -euo pipefail

LOG_SH="$HOME/.claude/scripts/log.sh"
TMPDIR=$(mktemp -d)
PASS=0
FAIL=0

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

assert_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -qP "$pattern" "$file" 2>/dev/null || grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  ✅ PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $label"
    echo "    Expected pattern: $pattern"
    echo "    File contents:"
    cat "$file" | head -10
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  ❌ FAIL: $label"
    echo "    Should NOT contain: $pattern"
    echo "    File contents:"
    cat "$file" | head -10
    FAIL=$((FAIL + 1))
  else
    echo "  ✅ PASS: $label"
    PASS=$((PASS + 1))
  fi
}

# ─── Test 1: Normal append — timestamp injected ───
echo "Test 1: Normal append — timestamp injected into ## heading"
FILE="$TMPDIR/test1.md"
echo "# Existing content" > "$FILE"
"$LOG_SH" "$FILE" <<'EOF'
## ▶️ Task Start
*   **Item**: Step 1
*   **Goal**: Test
EOF

assert_contains "$FILE" '## \[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\] ▶️ Task Start' \
  "Timestamp injected into heading"
assert_contains "$FILE" 'Item' "Body content preserved"

# ─── Test 2: Double-stamp guard — no double injection ───
echo ""
echo "Test 2: Double-stamp guard — already-timestamped heading unchanged"
FILE="$TMPDIR/test2.md"
echo "# Existing content" > "$FILE"
"$LOG_SH" "$FILE" <<'EOF'
## [2026-02-08 10:00:00] Already Timestamped
*   **Item**: Step 1
EOF

# Should have exactly one timestamp, not two
assert_contains "$FILE" '## \[2026-02-08 10:00:00\] Already Timestamped' \
  "Original timestamp preserved"
assert_not_contains "$FILE" '## \[20.*\] \[2026-02-08' \
  "No double timestamp"

# ─── Test 3: No heading in append mode — exit 1 ───
echo ""
echo "Test 3: No ## heading in append mode — should error"
FILE="$TMPDIR/test3.md"
echo "# Existing" > "$FILE"
set +e
OUTPUT=$("$LOG_SH" "$FILE" <<'EOF' 2>&1
No heading here
Just body text
EOF
)
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -ne 0 ]; then
  echo "  ✅ PASS: Exit code is non-zero ($EXIT_CODE)"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: Expected non-zero exit code, got $EXIT_CODE"
  FAIL=$((FAIL + 1))
fi

if echo "$OUTPUT" | grep -q "ERROR"; then
  echo "  ✅ PASS: Error message present"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: Expected error message in output"
  echo "    Got: $OUTPUT"
  FAIL=$((FAIL + 1))
fi

# ─── Test 4: --overwrite mode — no injection ───
echo ""
echo "Test 4: --overwrite mode — no timestamp injection"
FILE="$TMPDIR/test4.md"
"$LOG_SH" --overwrite "$FILE" <<'EOF'
# Full File Content
## Section One
Some text here
EOF

assert_contains "$FILE" '## Section One' "Section heading present"
assert_not_contains "$FILE" '## \[20' "No timestamp injected in overwrite mode"

# ─── Test 5: Multiple ## headings — only first gets timestamp ───
echo ""
echo "Test 5: Multiple ## headings — only first gets timestamp"
FILE="$TMPDIR/test5.md"
echo "# Existing" > "$FILE"
"$LOG_SH" "$FILE" <<'EOF'
## First Heading
Content under first

## Second Heading
Content under second
EOF

# Count lines with timestamps
TS_COUNT=$(grep -c '## \[20[0-9][0-9]-' "$FILE" || true)
if [ "$TS_COUNT" -eq 1 ]; then
  echo "  ✅ PASS: Exactly 1 heading has timestamp"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: Expected 1 timestamped heading, got $TS_COUNT"
  cat "$FILE"
  FAIL=$((FAIL + 1))
fi
assert_contains "$FILE" '## Second Heading' "Second heading has no timestamp"

# ─── Test 6: Content after heading preserved exactly ───
echo ""
echo "Test 6: Content after heading preserved exactly"
FILE="$TMPDIR/test6.md"
echo "# Existing" > "$FILE"
"$LOG_SH" "$FILE" <<'EOF'
## 🚧 Block
*   **Obstacle**: TypeScript Error 2322
*   **Context**: Missing type in test env
*   **Severity**: Blocking
EOF

assert_contains "$FILE" 'Obstacle.*TypeScript Error 2322' "Bullet 1 preserved"
assert_contains "$FILE" 'Context.*Missing type' "Bullet 2 preserved"
assert_contains "$FILE" 'Severity.*Blocking' "Bullet 3 preserved"

# ─── Summary ───
echo ""
echo "════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
