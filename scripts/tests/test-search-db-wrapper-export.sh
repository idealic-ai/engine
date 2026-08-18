#!/bin/bash
# Test: every search-tool wrapper wires in the local-DB mechanism
#
# Promoted from search-db-mover_repro/finding-1-live-wrapper-bypassed.sh.
#
# The engine has FOUR near-duplicate entry points for the same two CLIs —
# scripts/{session,doc}-search.sh and tools/{session-search,doc-search}/*.sh —
# and different callers reach different ones (session.sh hardcodes the tools/
# pair at three sites). A wrapper that skips search_db_export_path leaves
# ENGINE_SEARCH_DB_PATH unset, the CLI silently falls back to the in-sessions
# path, and the next index rebuilds a ~1.4 GB database on Google Drive — the
# exact behaviour the mechanism exists to prevent, with no error anywhere.
#
# This test DISCOVERS wrappers rather than listing them, so a newly-added fifth
# entry point fails here instead of silently bypassing the mechanism.

source "$HOME/.claude/scripts/tests/test-helpers.sh"

ENGINE_ROOT="$HOME/.claude/engine"
[ -d "$ENGINE_ROOT" ] || ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Any shell script that launches one of the search CLIs is a wrapper.
_discover_wrappers() {
  grep -rl 'src/cli\.ts' \
    "$ENGINE_ROOT/scripts" \
    "$ENGINE_ROOT/tools/session-search" \
    "$ENGINE_ROOT/tools/doc-search" \
    --include='*.sh' 2>/dev/null | sort -u
}

test_search-db_wrapper_discovery_finds_the_known_entry_points() {
  local found count
  found=$(_discover_wrappers)
  count=$(echo "$found" | grep -c . || echo 0)
  assert_gt "$count" "3" "at least the four known search wrappers are discovered"
  assert_contains "scripts/session-search.sh" "$found" "outer session-search wrapper discovered"
  assert_contains "scripts/doc-search.sh" "$found" "outer doc-search wrapper discovered"
  assert_contains "tools/session-search/session-search.sh" "$found" "inner session-search wrapper discovered"
  assert_contains "tools/doc-search/doc-search.sh" "$found" "inner doc-search wrapper discovered"
}

test_search-db_every_wrapper_calls_export_path() {
  local w missing=""
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    grep -q 'search_db_export_path' "$w" || missing="$missing ${w#$ENGINE_ROOT/}"
  done <<< "$(_discover_wrappers)"
  assert_empty "$missing" "every wrapper that launches a search CLI calls search_db_export_path"
}

test_search-db_every_wrapper_sources_the_lib_with_a_fallback() {
  # A bare `source "$HOME/..."` under `set -e` kills the wrapper on any machine
  # whose per-file symlinks have not been created yet; both consumers in
  # session.sh discard stderr, so the breakage would be invisible.
  local w missing=""
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    grep -q 'search-db-lib.sh' "$w" || { missing="$missing ${w#$ENGINE_ROOT/}(no-lib)"; continue; }
    # More than one candidate path == a real fallback chain, not a hardcoded path.
    if [ "$(grep -c 'search-db-lib\.sh' "$w")" -lt 2 ]; then
      missing="$missing ${w#$ENGINE_ROOT/}(no-fallback)"
    fi
  done <<< "$(_discover_wrappers)"
  assert_empty "$missing" "every wrapper resolves search-db-lib.sh through a fallback chain"
}

test_search-db_export_path_is_defined_by_the_lib() {
  local lib="$ENGINE_ROOT/scripts/search-db-lib.sh"
  assert_file_exists "$lib" "search-db-lib.sh exists"
  # shellcheck source=/dev/null
  source "$lib"
  if type search_db_export_path >/dev/null 2>&1; then
    pass "search_db_export_path is defined after sourcing the lib"
  else
    fail "search_db_export_path is defined after sourcing the lib" "defined" "missing"
  fi
}

run_discovered_tests
