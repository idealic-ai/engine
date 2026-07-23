#!/bin/bash
# tests/test-log-sh.sh — Tests for log.sh auto-timestamp injection
# Run: bash ~/.claude/engine/scripts/tests/test-log-sh.sh

set -euo pipefail

source "$(dirname "$0")/test-helpers.sh"

LOG_SH="$HOME/.claude/scripts/log.sh"
TMPDIR=$(mktemp -d)

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

# File-based assert helpers (different signature from shared library — kept local)
assert_file_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -qP "$pattern" "$file" 2>/dev/null || grep -q "$pattern" "$file" 2>/dev/null; then
    pass "$label"
  else
    fail "$label" "pattern: $pattern" "not found in $(head -10 "$file")"
  fi
}

assert_file_not_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    fail "$label" "NOT contain: $pattern" "found in $(head -10 "$file")"
  else
    pass "$label"
  fi
}

# --- Test 1: Normal append --- timestamp injected ---
echo "Test 1: Normal append --- timestamp injected into ## heading"
FILE="$TMPDIR/test1.md"
echo "# Existing content" > "$FILE"
"$LOG_SH" "$FILE" <<'EOF'
## ▶️ Task Start
*   **Item**: Step 1
*   **Goal**: Test
EOF

assert_file_contains "$FILE" '## \[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\] ▶️ Task Start' \
  "Timestamp injected into heading"
assert_file_contains "$FILE" 'Item' "Body content preserved"

# --- Test 2: Double-stamp guard --- no double injection ---
echo ""
echo "Test 2: Double-stamp guard --- already-timestamped heading unchanged"
FILE="$TMPDIR/test2.md"
echo "# Existing content" > "$FILE"
"$LOG_SH" "$FILE" <<'EOF'
## [2026-02-08 10:00:00] Already Timestamped
*   **Item**: Step 1
EOF

# Should have exactly one timestamp, not two
assert_file_contains "$FILE" '## \[2026-02-08 10:00:00\] Already Timestamped' \
  "Original timestamp preserved"
assert_file_not_contains "$FILE" '## \[20.*\] \[2026-02-08' \
  "No double timestamp"

# --- Test 3: No heading in append mode --- exit 1 ---
echo ""
echo "Test 3: No ## heading in append mode --- should error"
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
  pass "Exit code is non-zero ($EXIT_CODE)"
else
  fail "Expected non-zero exit code" "non-zero" "$EXIT_CODE"
fi

if echo "$OUTPUT" | grep -q "ERROR"; then
  pass "Error message present"
else
  fail "Expected error message in output" "contains ERROR" "$OUTPUT"
fi

# --- Test 4: --overwrite mode --- no injection ---
echo ""
echo "Test 4: --overwrite mode --- no timestamp injection"
FILE="$TMPDIR/test4.md"
"$LOG_SH" --overwrite "$FILE" <<'EOF'
# Full File Content
## Section One
Some text here
EOF

assert_file_contains "$FILE" '## Section One' "Section heading present"
assert_file_not_contains "$FILE" '## \[20' "No timestamp injected in overwrite mode"

# --- Test 5: Multiple ## headings --- only first gets timestamp ---
echo ""
echo "Test 5: Multiple ## headings --- only first gets timestamp"
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
  pass "Exactly 1 heading has timestamp"
else
  fail "Expected 1 timestamped heading" "1" "$TS_COUNT"
fi
assert_file_contains "$FILE" '## Second Heading' "Second heading has no timestamp"

# --- Test 6: Content after heading preserved exactly ---
echo ""
echo "Test 6: Content after heading preserved exactly"
FILE="$TMPDIR/test6.md"
echo "# Existing" > "$FILE"
"$LOG_SH" "$FILE" <<'EOF'
## Block
*   **Obstacle**: TypeScript Error 2322
*   **Context**: Missing type in test env
*   **Severity**: Blocking
EOF

assert_file_contains "$FILE" 'Obstacle.*TypeScript Error 2322' "Bullet 1 preserved"
assert_file_contains "$FILE" 'Context.*Missing type' "Bullet 2 preserved"
assert_file_contains "$FILE" 'Severity.*Blocking' "Bullet 3 preserved"

# --- Test 7: Append works after cd to different directory ---
echo ""
echo "Test 7: sessions/ path resolves correctly even after cd"
# Simulate project root with sessions dir
PROJECT="$TMPDIR/project7"
mkdir -p "$PROJECT/sessions/TEST_SESSION"
mkdir -p "$PROJECT/subdir"
FILE="$PROJECT/sessions/TEST_SESSION/LOG.md"
echo "# Log" > "$FILE"

# cd into a subdirectory (simulates agent running `cd packages/sdk && tsup`)
(
  cd "$PROJECT"
  "$LOG_SH" "sessions/TEST_SESSION/LOG.md" <<'EOF'
## Entry Before CD
*   **Status**: Written from project root
EOF
)

# Now cd away and try to log — this is the bug scenario
(
  cd "$PROJECT/subdir"
  "$LOG_SH" "$PROJECT/sessions/TEST_SESSION/LOG.md" <<'EOF'
## Entry With Absolute Path
*   **Status**: Written with absolute path (always works)
EOF
)

assert_file_contains "$FILE" 'Entry Before CD' "Entry from project root persisted"
assert_file_contains "$FILE" 'Entry With Absolute Path' "Entry with absolute path persisted"

# The real bug: relative path after cd
# Agent runs: engine log sessions/DIR/LOG.md but CWD is /subdir
# log.sh should NOT mkdir -p and silently create dirs — it should error
set +e
CD_OUTPUT=$(cd "$PROJECT/subdir" && "$LOG_SH" "sessions/TEST_SESSION/LOG.md" <<'EOF' 2>&1
## Entry After CD
*   **Status**: Written from wrong CWD
EOF
)
CD_RESULT=$?
set -e

# The entry should NOT silently create sessions/TEST_SESSION/LOG.md under subdir/
if [ -f "$PROJECT/subdir/sessions/TEST_SESSION/LOG.md" ]; then
  fail "Relative path after cd: no silent misdirection" \
    "file NOT created under subdir/" \
    "file created at $PROJECT/subdir/sessions/TEST_SESSION/LOG.md"
else
  pass "Relative path after cd: no silent misdirection"
fi
# It should have errored (dir doesn't exist, no mkdir -p to save it)
if [ "$CD_RESULT" -ne 0 ]; then
  pass "Relative path after cd: errors when dir doesn't exist (exit $CD_RESULT)"
else
  fail "Relative path after cd: errors when dir doesn't exist" \
    "non-zero exit" \
    "exit 0 (silent success)"
fi

# --- Summary ---
exit_with_results
