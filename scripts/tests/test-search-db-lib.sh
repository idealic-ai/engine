#!/bin/bash
# Test: search-db-lib.sh — the lazy search-DB mover
#
# Covers path/namespace resolution, project-root walking, the migration
# contract, and the wrapper entry point that moves .session-search.db /
# .doc-search.db off the Google Drive sessions mount. Every failure mode here is
# silent in production, so the contract is encoded as tests rather than trusted
# to review.
#
# Per ¶INV_TEST_SANDBOX_ISOLATION: temp sandbox + fake HOME. The mover writes
# under $HOME/.claude/cache/, so a leaked HOME would touch the real cache.
#
# Function names contain "search-db" (hyphens) deliberately: `engine test --grep
# search-db` matches the FILE but is ALSO applied as TEST_FILTER against test
# function NAMES. With underscore names the filter matched nothing and the suite
# reported "ALL SUITES PASSED (0 passed)" — green while running zero tests.

source "$HOME/.claude/scripts/tests/test-helpers.sh"

# Resolve the lib BEFORE setup_fake_home repoints HOME — otherwise this looks
# for it inside the sandbox, silently loads nothing, and every test fails with
# "command not found" rather than a real assertion failure.
LIB="$HOME/.claude/scripts/search-db-lib.sh"
[ -f "$LIB" ] || LIB="$HOME/.claude/engine/scripts/search-db-lib.sh"

# pwd -P so the sandbox path matches what the lib resolves to. On macOS mktemp
# yields /var/folders/... which is a symlink to /private/var/... — without this,
# every path equality assertion would compare the two spellings and fail.
TMP_DIR=$(cd "$(mktemp -d)" && pwd -P)
trap 'chmod -R u+w "$TMP_DIR" 2>/dev/null; teardown_fake_home; rm -rf "$TMP_DIR"' EXIT
setup_fake_home "$TMP_DIR"

[ -f "$LIB" ] && source "$LIB"

DB=".session-search.db"

_mk_sessions_dir() {
  local d="$TMP_DIR/${1:-plain}/sessions"
  mkdir -p "$d"
  echo "$d"
}

# Fixtures must be REAL databases: the mover now asks sqlite3 to open a file
# before trusting it, precisely so a valid header on a truncated body cannot
# pass. A header + padding would (correctly) be rejected.
_mk_sqlite_at() {
  local f="$1" rows="${2:-8}" i
  mkdir -p "$(dirname "$f")"
  rm -f "$f"
  {
    echo "CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT);"
    i=0; while [ "$i" -lt "$rows" ]; do echo "INSERT INTO t(v) VALUES('row-$i');"; i=$((i+1)); done
  } | sqlite3 "$f"
}

_mk_legacy_db() {
  _mk_sqlite_at "$1/$DB" "${2:-8}"
}

_size_of() { wc -c < "$1" | tr -d ' '; }

# ============================================================
# Namespace derivation
# ============================================================

test_search-db_namespace_gdrive() {
  local got
  got=$(search_db_namespace "/Users/x/Library/CloudStorage/GoogleDrive-a@b.com/Shared drives/finch-os/yarik/finch/sessions")
  assert_eq "yarik/finch/sessions" "$got" "gdrive path yields user/project/sessions namespace"
}

test_search-db_namespace_fallback_is_project_scoped() {
  local got
  got=$(search_db_namespace "/work/acme/sessions")
  assert_contains "acme-" "$got" "off-drive namespace carries the project dir name"
  assert_contains "/sessions" "$got" "off-drive namespace still ends in /sessions"
}

test_search-db_namespace_fallback_distinguishes_projects() {
  # A constant fallback would collapse every off-Drive project onto one cache
  # file and let them clobber each other's index.
  local a b
  a=$(search_db_namespace "/work/acme/sessions")
  b=$(search_db_namespace "/elsewhere/acme/sessions")
  assert_neq "$a" "$b" "same-named projects at different paths get distinct namespaces"
}

test_search-db_namespace_handles_spaces_and_parens() {
  # The real tree contains "Shared drives" (space) and "PROVE_THEME (1)" (parens).
  local got
  got=$(search_db_namespace "/x/Shared drives/finch-os/yarik/finch/sessions")
  assert_eq "yarik/finch/sessions" "$got" "a space in the path does not split the namespace"
  got=$(search_db_namespace "/work/proj (1)/sessions")
  assert_contains "proj (1)-" "$got" "parentheses survive namespace derivation"
}

# ============================================================
# Project root walking
# ============================================================

test_search-db_project_root_finds_claude_dir() {
  local root got
  root="$TMP_DIR/projroot"; mkdir -p "$root/.claude" "$root/a/b"
  got=$(search_db_project_root "$root/a/b")
  assert_eq "$root" "$got" "walks up to the nearest ancestor holding .claude/"
}

test_search-db_project_root_terminates_on_relative_input() {
  # `dirname .` is `.`, so an un-absolutised relative arg spins forever.
  local got rc
  got=$(cd "$TMP_DIR" && timeout 10 bash -c "source '$LIB'; search_db_project_root 'some/rel/path'" 2>/dev/null)
  rc=$?
  assert_neq "124" "$rc" "relative input terminates instead of hanging"
  assert_not_empty "$got" "relative input still yields a root"
}

test_search-db_project_root_terminates_on_dot() {
  local rc
  timeout 10 bash -c "cd '$TMP_DIR'; source '$LIB'; search_db_project_root '.'" >/dev/null 2>&1
  rc=$?
  assert_neq "124" "$rc" "a bare '.' terminates instead of hanging"
}

# ============================================================
# Path resolution
# ============================================================

test_search-db_local_path_honours_env() {
  local sdir got
  sdir=$(_mk_sessions_dir env)
  got=$(ENGINE_SEARCH_DB_DIR="$TMP_DIR/custom-cache" search_db_local_path "$DB" "$sdir")
  assert_contains "$TMP_DIR/custom-cache" "$got" "ENGINE_SEARCH_DB_DIR overrides the default cache root"
  assert_contains "$DB" "$got" "local path ends with the db filename"
}

test_search-db_local_path_defaults_under_home() {
  local sdir got
  sdir=$(_mk_sessions_dir home)
  got=$(search_db_local_path "$DB" "$sdir")
  assert_contains "$HOME/.claude/cache/search-db" "$got" "default cache root lives under HOME/.claude/cache/search-db"
}

test_search-db_active_path_prefers_local() {
  local sdir local_path got
  sdir=$(_mk_sessions_dir prefer)
  _mk_legacy_db "$sdir"
  local_path=$(search_db_local_path "$DB" "$sdir")
  _mk_sqlite_at "$local_path"
  got=$(search_db_active_path "$DB" "$sdir")
  assert_eq "$local_path" "$got" "active path prefers the local db when it exists"
}

test_search-db_active_path_falls_back_to_legacy() {
  local sdir got
  sdir=$(_mk_sessions_dir fallback)
  _mk_legacy_db "$sdir"
  got=$(search_db_active_path "$DB" "$sdir")
  assert_eq "$sdir/$DB" "$got" "active path falls back to legacy when no local db"
}

# ============================================================
# Migration contract
# ============================================================

test_search-db_migrate_noop_when_no_legacy() {
  local sdir local_path
  sdir=$(_mk_sessions_dir nolegacy)
  assert_ok "migrate returns 0 when there is nothing to move" search_db_migrate "$DB" "$sdir"
  local_path=$(search_db_local_path "$DB" "$sdir")
  assert_file_not_exists "$local_path" "no local db is fabricated"
}

test_search-db_migrate_noop_when_local_exists() {
  local sdir local_path
  sdir=$(_mk_sessions_dir localexists)
  _mk_legacy_db "$sdir"
  local_path=$(search_db_local_path "$DB" "$sdir")
  _mk_sqlite_at "$local_path" 3
  local keep_size; keep_size=$(_size_of "$local_path")

  assert_ok "migrate returns 0 when a valid local db already exists" search_db_migrate "$DB" "$sdir"
  assert_eq "$keep_size" "$(_size_of "$local_path")" "existing local db is not overwritten"
  assert_file_exists "$sdir/$DB" "legacy is left alone when local already exists"
}

test_search-db_migrate_happy_path() {
  local sdir local_path
  sdir=$(_mk_sessions_dir happy)
  _mk_legacy_db "$sdir"
  local_path=$(search_db_local_path "$DB" "$sdir")
  local src_size; src_size=$(_size_of "$sdir/$DB")

  assert_ok "migrate succeeds on the happy path" search_db_migrate "$DB" "$sdir"
  assert_file_exists "$local_path" "local db was created"
  assert_eq "$src_size" "$(_size_of "$local_path")" "local db has the same byte count"
  assert_file_not_exists "$sdir/$DB" "legacy db is deleted after a verified move"
}

test_search-db_migrate_mkdir_failure_preserves_legacy() {
  local sdir cache_root local_path
  sdir=$(_mk_sessions_dir mkdirfail)
  _mk_legacy_db "$sdir"
  cache_root="$TMP_DIR/readonly-cache"; mkdir -p "$cache_root"; chmod 500 "$cache_root"

  local_path=$(ENGINE_SEARCH_DB_DIR="$cache_root" search_db_local_path "$DB" "$sdir")
  assert_fail "migrate reports failure when the cache root is unwritable" \
    env ENGINE_SEARCH_DB_DIR="$cache_root" search_db_migrate "$DB" "$sdir"
  assert_file_exists "$sdir/$DB" "legacy db is preserved when migration fails"
  assert_file_not_exists "$local_path" "no partial local db is left behind"
  chmod 700 "$cache_root"
}

test_search-db_migrate_rejects_non_sqlite_legacy() {
  # A byte count alone would pass this; the image check must not, because the
  # very next step deletes the only other copy.
  local sdir local_path
  sdir=$(_mk_sessions_dir notsqlite)
  head -c 4096 /dev/zero | tr '\0' 'x' > "$sdir/$DB"
  local_path=$(search_db_local_path "$DB" "$sdir")

  assert_fail "migrate refuses a legacy file that is not a SQLite image" search_db_migrate "$DB" "$sdir"
  assert_file_exists "$sdir/$DB" "the non-SQLite legacy file is NOT deleted"
  assert_file_not_exists "$local_path" "no local db is produced from a bad source"
}

test_search-db_migrate_replaces_corrupt_local() {
  # A truncated local db must not shadow migration forever — the legacy copy is
  # deleted by design, so this is the last chance to self-heal.
  local sdir local_path
  sdir=$(_mk_sessions_dir corruptlocal)
  _mk_legacy_db "$sdir"
  local_path=$(search_db_local_path "$DB" "$sdir")
  local src_size; src_size=$(_size_of "$sdir/$DB")
  mkdir -p "$(dirname "$local_path")"
  : > "$local_path"   # 0-byte, satisfies -f but is not a SQLite image

  assert_ok "migrate re-runs over a corrupt local db" search_db_migrate "$DB" "$sdir"
  assert_eq "$src_size" "$(_size_of "$local_path")" "corrupt local db was replaced by the legacy copy"
  assert_file_not_exists "$sdir/$DB" "legacy deleted after the repair migration"
}

test_search-db_migrate_corrupt_local_no_legacy_reports_failure() {
  local sdir local_path
  sdir=$(_mk_sessions_dir corruptnolegacy)
  local_path=$(search_db_local_path "$DB" "$sdir")
  mkdir -p "$(dirname "$local_path")"
  : > "$local_path"

  assert_fail "migrate reports failure when local is corrupt and no legacy remains" \
    search_db_migrate "$DB" "$sdir"
}

test_search-db_migrate_handles_spaces_and_parens_in_paths() {
  local base sdir local_path
  base="$TMP_DIR/Shared drives/proj (1)"
  sdir="$base/sessions"; mkdir -p "$sdir"
  _mk_legacy_db "$sdir"
  local_path=$(search_db_local_path "$DB" "$sdir")

  assert_ok "migrate works through a path with spaces and parentheses" search_db_migrate "$DB" "$sdir"
  assert_file_exists "$local_path" "local db created under a space/paren path"
  assert_file_not_exists "$sdir/$DB" "legacy removed under a space/paren path"
}

test_search-db_migrate_leaves_no_tmp_files() {
  local sdir cache_dir tmp_count
  sdir=$(_mk_sessions_dir notmp)
  _mk_legacy_db "$sdir"
  search_db_migrate "$DB" "$sdir" >/dev/null 2>&1
  cache_dir=$(dirname "$(search_db_local_path "$DB" "$sdir")")
  tmp_count=$(find "$cache_dir" -name '*.tmp' 2>/dev/null | wc -l | tr -d ' ')
  assert_eq "0" "$tmp_count" "no .tmp residue after a successful migration"
}

test_search-db_migrate_is_idempotent() {
  local sdir local_path
  sdir=$(_mk_sessions_dir idem)
  _mk_legacy_db "$sdir"
  search_db_migrate "$DB" "$sdir" >/dev/null 2>&1
  local_path=$(search_db_local_path "$DB" "$sdir")
  local first_size; first_size=$(_size_of "$local_path")
  assert_ok "a second migrate is a clean no-op" search_db_migrate "$DB" "$sdir"
  assert_eq "$first_size" "$(_size_of "$local_path")" "local db is unchanged by the second run"
}

test_search-db_migrate_removes_orphan_lock() {
  # doc-search derives its advisory lock from the DB path, so the lock moved
  # with the DB; the one left in sessions/ would never be cleared otherwise.
  local sdir
  sdir=$(_mk_sessions_dir orphanlock)
  _mk_legacy_db "$sdir"
  : > "$sdir/.session-search.lock"
  search_db_migrate "$DB" "$sdir" >/dev/null 2>&1
  assert_file_not_exists "$sdir/.session-search.lock" "orphan lock beside the legacy db is cleaned up"
}

# ============================================================
# Wrapper entry point
# ============================================================

test_search-db_export_path_query_does_not_migrate() {
  local sdir
  sdir=$(_mk_sessions_dir exportquery)
  _mk_legacy_db "$sdir"
  (cd "$(dirname "$sdir")" && search_db_export_path session query "hello" >/dev/null 2>&1)
  assert_file_exists "$sdir/$DB" "query must never migrate — legacy still present"
}

test_search-db_export_path_index_uses_local_with_nothing_to_migrate() {
  # Without this, a fresh install keeps creating the DB on Drive forever.
  local sdir out
  sdir=$(_mk_sessions_dir exportfresh)
  out=$(cd "$(dirname "$sdir")" && search_db_export_path session index >/dev/null 2>&1; echo "$ENGINE_SEARCH_DB_PATH")
  assert_contains "$HOME/.claude/cache/search-db" "$out" "index resolves to the local cache even with nothing to migrate"
}

test_search-db_export_path_ignores_flag_shaped_second_arg() {
  # cli.ts routes --flags away from positionals; treating one as a path would
  # mint a garbage namespace the query side never looks in.
  local sdir with_flag plain
  sdir=$(_mk_sessions_dir exportflag)
  with_flag=$(cd "$(dirname "$sdir")" && search_db_export_path session index --limit 5 >/dev/null 2>&1; echo "$ENGINE_SEARCH_DB_PATH")
  plain=$(cd "$(dirname "$sdir")" && search_db_export_path session index >/dev/null 2>&1; echo "$ENGINE_SEARCH_DB_PATH")
  assert_eq "$plain" "$with_flag" "a flag-shaped arg is not mistaken for a sessions path"
  assert_not_contains "limit" "$with_flag" "resolved path contains no flag token"
}

run_discovered_tests
