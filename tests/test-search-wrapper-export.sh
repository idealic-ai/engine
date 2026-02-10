#!/usr/bin/env bash
# test-search-wrapper-export.sh — Regression test for GEMINI_API_KEY export in search wrappers
#
# Verifies that all 4 search wrapper scripts (2 tool-level, 2 engine-level):
# 1. Contain `export GEMINI_API_KEY` (prevents the silent reindex failure)
# 2. Are executable
# 3. Produce a clean error when GEMINI_API_KEY is missing
#
# Bug context: session.sh deactivate backgrounds index commands via the tool-level
# wrappers. Without `export`, the exec'd subprocess doesn't inherit the key.
# See: sessions/2026_02_10_SEARCH_REINDEX_BUG/FIX.md
set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

ENGINE_DIR="$HOME/.claude/engine"
TOOL_SESSION_SEARCH="$ENGINE_DIR/tools/session-search/session-search.sh"
TOOL_DOC_SEARCH="$ENGINE_DIR/tools/doc-search/doc-search.sh"
SCRIPT_SESSION_SEARCH="$ENGINE_DIR/scripts/session-search.sh"
SCRIPT_DOC_SEARCH="$ENGINE_DIR/scripts/doc-search.sh"

assert_pass() {
  local name="$1"
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  ✅ PASS: $name"
}

assert_fail() {
  local name="$1"
  local detail="${2:-}"
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  ❌ FAIL: $name"
  [ -n "$detail" ] && echo "          $detail"
}

echo "=== Search Wrapper Export Tests ==="
echo ""

# --- Case 1-4: Static analysis — export GEMINI_API_KEY ---
echo "--- Static Analysis: export GEMINI_API_KEY ---"

for label_and_path in \
  "Tool session-search|$TOOL_SESSION_SEARCH" \
  "Tool doc-search|$TOOL_DOC_SEARCH" \
  "Engine session-search|$SCRIPT_SESSION_SEARCH" \
  "Engine doc-search|$SCRIPT_DOC_SEARCH"
do
  label="${label_and_path%%|*}"
  path="${label_and_path##*|}"

  if [ ! -f "$path" ]; then
    assert_fail "$label: contains 'export GEMINI_API_KEY'" "File not found: $path"
    continue
  fi

  if grep -q 'export GEMINI_API_KEY' "$path"; then
    assert_pass "$label: contains 'export GEMINI_API_KEY'"
  else
    assert_fail "$label: contains 'export GEMINI_API_KEY'" "Missing export in: $path"
  fi
done

echo ""

# --- Case 5: Error propagation — missing key produces clean error ---
echo "--- Error Propagation: missing key behavior ---"

for label_and_path in \
  "Tool session-search|$TOOL_SESSION_SEARCH" \
  "Tool doc-search|$TOOL_DOC_SEARCH"
do
  label="${label_and_path%%|*}"
  path="${label_and_path##*|}"

  if [ ! -f "$path" ]; then
    assert_fail "$label: clean error on missing key" "File not found: $path"
    continue
  fi

  # Run the wrapper in a subshell with:
  # - GEMINI_API_KEY unset
  # - CWD set to /tmp (no .env file)
  # - Capture stderr
  stderr_output=$(cd /tmp && env -u GEMINI_API_KEY bash "$path" index 2>&1 || true)

  if echo "$stderr_output" | grep -q "GEMINI_API_KEY not set"; then
    assert_pass "$label: clean error on missing key"
  else
    assert_fail "$label: clean error on missing key" "Expected 'GEMINI_API_KEY not set' in stderr, got: $stderr_output"
  fi
done

echo ""

# --- Case 6: Executability ---
echo "--- Executability Check ---"

for label_and_path in \
  "Tool session-search|$TOOL_SESSION_SEARCH" \
  "Tool doc-search|$TOOL_DOC_SEARCH" \
  "Engine session-search|$SCRIPT_SESSION_SEARCH" \
  "Engine doc-search|$SCRIPT_DOC_SEARCH"
do
  label="${label_and_path%%|*}"
  path="${label_and_path##*|}"

  if [ -x "$path" ]; then
    assert_pass "$label: is executable"
  else
    assert_fail "$label: is executable" "Not executable: $path"
  fi
done

echo ""

# --- Summary ---
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
