#!/bin/bash
# Test: escape_tags() function from post-tool-use-details-log.sh
# Validates tag escaping per ¶INV_ESCAPE_BY_DEFAULT
set -euo pipefail

PASS=0
FAIL=0
ERRORS=""

# Extract escape_tags function from the hook
escape_tags() {
  perl -pe 's/(?<!`)#((?:needs|delegated|next|claimed|done)-\w+|active-alert)(?![\w-])(?!`)/`#$1`/g'
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $label\n    expected: $expected\n    actual:   $actual"
    echo "  FAIL: $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

echo "=== escape_tags() tests ==="

# --- Case 1: Bare lifecycle tags are escaped ---
echo ""
echo "Case 1: Bare lifecycle tags"
assert_eq "needs-review" '`#needs-review`' "$(printf '#needs-review' | escape_tags)"
assert_eq "delegated-implementation" '`#delegated-implementation`' "$(printf '#delegated-implementation' | escape_tags)"
assert_eq "next-brainstorm" '`#next-brainstorm`' "$(printf '#next-brainstorm' | escape_tags)"
assert_eq "claimed-fix" '`#claimed-fix`' "$(printf '#claimed-fix' | escape_tags)"
assert_eq "done-documentation" '`#done-documentation`' "$(printf '#done-documentation' | escape_tags)"
assert_eq "active-alert" '`#active-alert`' "$(printf '#active-alert' | escape_tags)"

# --- Case 2: Already-backticked tags are NOT double-escaped ---
echo ""
echo "Case 2: No double-escaping"
assert_eq "backticked needs-review" '`#needs-review`' "$(printf '`#needs-review`' | escape_tags)"
assert_eq "backticked delegated-X" '`#delegated-chores`' "$(printf '`#delegated-chores`' | escape_tags)"
assert_eq "backticked active-alert" '`#active-alert`' "$(printf '`#active-alert`' | escape_tags)"

# --- Case 3: Multiple tags in one line ---
echo ""
echo "Case 3: Multiple tags in one line"
assert_eq "two tags" 'swap `#needs-review` to `#done-review`' "$(printf 'swap #needs-review to #done-review' | escape_tags)"
assert_eq "mixed bare and backticked" '`#needs-fix` and `#delegated-fix`' "$(printf '#needs-fix and `#delegated-fix`' | escape_tags)"

# --- Case 4: Non-lifecycle hashtags are NOT escaped ---
echo ""
echo "Case 4: Non-lifecycle tags preserved"
assert_eq "plain hashtag" '#123' "$(printf '#123' | escape_tags)"
assert_eq "TODO" '#TODO' "$(printf '#TODO' | escape_tags)"
assert_eq "random" '#foobar' "$(printf '#foobar' | escape_tags)"
assert_eq "P0 priority" '#P0' "$(printf '#P0' | escape_tags)"

# --- Case 5: Tags in realistic DIALOGUE.md content ---
echo ""
echo "Case 5: Realistic content"
assert_eq "in sentence" 'The `#needs-review` tag is auto-applied' "$(printf 'The #needs-review tag is auto-applied' | escape_tags)"
assert_eq "in option label" 'Options: Approve all for `#delegated-implementation`' "$(printf 'Options: Approve all for #delegated-implementation' | escape_tags)"
assert_eq "in blockquote" '> We swapped `#needs-fix` to `#done-fix`' "$(printf '> We swapped #needs-fix to #done-fix' | escape_tags)"

# --- Case 6: Edge cases ---
echo ""
echo "Case 6: Edge cases"
assert_eq "tag at start of line" '`#needs-review` is common' "$(printf '#needs-review is common' | escape_tags)"
assert_eq "tag at end of line" 'apply `#needs-review`' "$(printf 'apply #needs-review' | escape_tags)"
assert_eq "empty string" '' "$(printf '' | escape_tags)"
assert_eq "no tags" 'hello world' "$(printf 'hello world' | escape_tags)"
assert_eq "tag with hyphenated suffix" '`#needs-brainstorm`' "$(printf '#needs-brainstorm' | escape_tags)"
assert_eq "done-alert covered by done-*" '`#done-alert`' "$(printf '#done-alert' | escape_tags)"

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  printf "$ERRORS\n"
  exit 1
fi
exit 0
