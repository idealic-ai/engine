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

# --- Test 8: Bare log (no --reason) --- no reason marker (byte-compat) ---
echo ""
echo "Test 8: Bare log with no --reason --- timestamp injected, NO «» marker"
FILE="$TMPDIR/test8.md"
echo "# Existing" > "$FILE"
"$LOG_SH" "$FILE" <<'EOF'
## ▶️ Task Start
*   **Item**: Step 1
EOF

assert_file_contains "$FILE" '## \[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\] ▶️ Task Start' \
  "Timestamp injected (bare log)"
assert_file_not_contains "$FILE" '«' "No reason marker when --reason absent"

# --- Test 9: --reason section --- marker injected after timestamp ---
echo ""
echo "Test 9: --reason section --- ## [ts] «section» <text>"
FILE="$TMPDIR/test9.md"
echo "# Existing" > "$FILE"
"$LOG_SH" --reason section "$FILE" <<'EOF'
## Task Start
*   **Item**: Step 1
EOF

assert_file_contains "$FILE" '## \[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\] «section» Task Start' \
  "Reason marker injected after timestamp"

# --- Test 10: Bare ## heading + --reason step --- ## [ts] «step» ---
echo ""
echo "Test 10: Bare ## heading + --reason step --- ## [ts] «step»"
FILE="$TMPDIR/test10.md"
echo "# Existing" > "$FILE"
"$LOG_SH" --reason step "$FILE" <<'EOF'
##
*   **Item**: Step 1
EOF

assert_file_contains "$FILE" '## \[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\] «step»' \
  "Bare heading gets timestamp + reason marker"

# --- Test 11: Invalid --reason bogus --- exit 1 + stderr lists valid set ---
echo ""
echo "Test 11: Invalid --reason bogus --- exit 1 + valid set in stderr"
FILE="$TMPDIR/test11.md"
echo "# Existing" > "$FILE"
set +e
OUTPUT=$("$LOG_SH" --reason bogus "$FILE" <<'EOF' 2>&1
## Heading
*   **Item**: body
EOF
)
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -ne 0 ]; then
  pass "Invalid reason exits non-zero ($EXIT_CODE)"
else
  fail "Expected non-zero exit for invalid reason" "non-zero" "$EXIT_CODE"
fi
assert_contains "step section plan found-issue divergence interruption decision block" "$OUTPUT" \
  "stderr lists the valid reason set"

# --- Test 12: --reason with no value --- exit 1 ---
echo ""
echo "Test 12: --reason with no value --- exit 1"
FILE="$TMPDIR/test12.md"
echo "# Existing" > "$FILE"
set +e
OUTPUT=$("$LOG_SH" --reason <<'EOF' 2>&1
## Heading
*   **Item**: body
EOF
)
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -ne 0 ]; then
  pass "Missing reason value exits non-zero ($EXIT_CODE)"
else
  fail "Expected non-zero exit for missing reason value" "non-zero" "$EXIT_CODE"
fi

# --- Test 13: Already-timestamped heading + --reason --- skip (no marker) ---
echo ""
echo "Test 13: Already-timestamped heading + --reason --- guard holds, no marker"
FILE="$TMPDIR/test13.md"
echo "# Existing" > "$FILE"
"$LOG_SH" --reason section "$FILE" <<'EOF'
## [2026-02-08 10:00:00] Already Timestamped
*   **Item**: Step 1
EOF

assert_file_contains "$FILE" '## \[2026-02-08 10:00:00\] Already Timestamped' \
  "Original timestamp preserved (double-stamp guard holds)"
assert_file_not_contains "$FILE" '«' "No reason marker injected when heading already stamped"

# --- Test 14: --overwrite --reason --- exit 1 (append-only flag) ---
echo ""
echo "Test 14: --overwrite --reason section --- exit 1 (only valid in append mode)"
FILE="$TMPDIR/test14.md"
set +e
OUTPUT=$("$LOG_SH" --overwrite --reason section "$FILE" <<'EOF' 2>&1
# Full File
## Section
EOF
)
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -ne 0 ]; then
  pass "--overwrite --reason exits non-zero ($EXIT_CODE)"
else
  fail "Expected non-zero exit for --overwrite --reason" "non-zero" "$EXIT_CODE"
fi
assert_contains "append mode" "$OUTPUT" "Error explains --reason is append-only"

# --- Test 15: Missing ## heading (append) + --reason --- still errors ---
echo ""
echo "Test 15: Missing ## heading + --reason --- heading-required check unchanged"
FILE="$TMPDIR/test15.md"
echo "# Existing" > "$FILE"
set +e
OUTPUT=$("$LOG_SH" --reason step "$FILE" <<'EOF' 2>&1
No heading here
Just body text
EOF
)
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -ne 0 ]; then
  pass "Missing heading + --reason exits non-zero ($EXIT_CODE)"
else
  fail "Expected non-zero exit for missing heading" "non-zero" "$EXIT_CODE"
fi
if echo "$OUTPUT" | grep -q "ERROR"; then
  pass "Heading-required error message present"
else
  fail "Expected heading-required error" "contains ERROR" "$OUTPUT"
fi

# --- Summary ---
# --- Test 16: --reason AFTER the <file> positional (position tolerance) ---
echo ""
echo "Test 16: <file> --reason section --- flag after the positional still stamps"
FILE="$TMPDIR/test16.md"
echo "# Existing" > "$FILE"
"$LOG_SH" "$FILE" --reason section <<'EOF'
## Task Start
*   **Item**: after-file flag
EOF

assert_file_contains "$FILE" '## \[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\] «section» Task Start' \
  "C-order: reason marker injected when --reason follows the file (position-tolerant)"

exit_with_results
