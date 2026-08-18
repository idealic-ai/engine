#!/usr/bin/env bash
# search-db-lib.sh — resolve, and lazily relocate, the semantic-search DBs.
#
# The sessions/ dir is frequently a symlink into a Google Drive shared drive,
# where most files are cloud-only and a read can block for minutes. Both search
# tools rewrite their ENTIRE SQLite image on every save, so keeping the DB there
# makes each index run re-upload the whole file. These helpers keep the working
# DB on local disk and move an existing one across on first index.
#
# Sourced by all FOUR wrapper scripts — scripts/{session,doc}-search.sh and
# tools/{session-search,doc-search}/*.sh. They are near-duplicate entry points
# for the same CLI and different callers reach different ones, so every one of
# them must call search_db_export_path. The wrapper is the single source of
# truth for the path; the TypeScript only reads ENGINE_SEARCH_DB_PATH.

# Namespace for a resolved sessions dir — the per-project segment of the cache
# path, so two projects never share a DB file.
#   ".../finch-os/yarik/finch/sessions" -> "yarik/finch/sessions"
#   "/work/acme/sessions"               -> "acme-<checksum>/sessions"
#
# The shared-drive branch matches extractResultNamespace() in
# tools/session-search/src/db-path.ts. The fallback deliberately does NOT: that
# function returns a constant "sessions", which is right for prefixing search
# RESULTS but would collapse every off-Drive project onto one cache file here.
search_db_namespace() {
  local resolved="$1" proj sum
  case "$resolved" in
    *finch-os/*)
      echo "${resolved#*finch-os/}"
      ;;
    *)
      proj=$(basename "$(dirname "$resolved")")
      sum=$(printf '%s' "$resolved" | cksum | cut -d' ' -f1)
      echo "${proj}-${sum}/sessions"
      ;;
  esac
}

# Project root: nearest ancestor containing .claude/, else the git root, else
# the starting dir. Mirrors getProjectRoot() in tools/doc-search/src/db-path.ts,
# which is how doc-search locates its sessions/ dir.
search_db_project_root() {
  local start="${1:-$PWD}" dir git_root
  # Absolutise first. `dirname .` is `.`, so a relative argument would otherwise
  # walk to "." and spin there forever — the loop only terminates at "/".
  case "$start" in
    /*) dir="$start" ;;
    *)  dir="$PWD/$start"; start="$dir" ;;
  esac
  while [ -n "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "." ]; do
    if [ -d "$dir/.claude" ]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  git_root=$(cd "$start" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$git_root" ]; then
    echo "$git_root"
    return 0
  fi
  echo "$start"
}

# Fully resolve a sessions dir (follows the Drive symlink). Falls back to the
# literal argument when it isn't an existing directory, so callers can pass
# hypothetical paths.
_search_db_sessions_dir() {
  local sdir="${1:-$PWD/sessions}"
  if [ -d "$sdir" ]; then
    (cd "$sdir" 2>/dev/null && pwd -P) || echo "$sdir"
  else
    echo "$sdir"
  fi
}

# Is this a plausible SQLite image? Existence is not integrity: saveDb() is a
# single non-atomic writeFileSync of a ~1.4 GB buffer, so an interrupted write
# leaves a truncated file that would otherwise satisfy every `-f` gate here
# while sql.js rejects it outright.
_search_db_is_sqlite() {
  local f="$1"
  [ -s "$f" ] || return 1
  [ "$(head -c 15 "$f" 2>/dev/null)" = "SQLite format 3" ] || return 1
  # The header alone is not enough: a write cut short leaves a VALID header on a
  # truncated body, which sql.js then rejects with "database disk image is
  # malformed". Ask sqlite3 to actually open it when available — reading
  # schema_version touches only the header and schema pages, so this stays cheap
  # even on a 1.4 GB file. If sqlite3 is absent we keep the header-only check
  # rather than refusing to migrate at all.
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$f" 'PRAGMA schema_version;' >/dev/null 2>&1 || return 1
  fi
  return 0
}

# Where the DB should live: local, namespaced, outside every repo (so no
# .gitignore entry is ever needed).
search_db_local_path() {
  local db="$1" sdir ns root
  sdir=$(_search_db_sessions_dir "${2:-}")
  ns=$(search_db_namespace "$sdir")
  root="${ENGINE_SEARCH_DB_DIR:-$HOME/.claude/cache/search-db}"
  echo "$root/$ns/$db"
}

# Where the DB used to live — inside the (possibly Drive-backed) sessions dir.
search_db_legacy_path() {
  local db="$1" sdir
  sdir=$(_search_db_sessions_dir "${2:-}")
  echo "$sdir/$db"
}

# The DB to actually use right now. Never migrates, so `query` stays fast and
# can never block on a Drive read it didn't ask for.
search_db_active_path() {
  local db="$1" local_path
  local_path=$(search_db_local_path "$db" "${2:-}")
  if [ -f "$local_path" ]; then
    echo "$local_path"
  else
    search_db_legacy_path "$db" "${2:-}"
  fi
}

# Move a legacy DB to local storage. Called only from `index`, which is already
# long-running — a Drive read can return nothing for minutes, so this must never
# sit in the `query` path.
#
# Returns 0 on success or no-op, 1 on a handled failure. Never exits the caller:
# on failure the legacy DB is left intact and the tool keeps using it.
search_db_migrate() {
  local db="$1" sdir_arg="${2:-}"
  local local_path legacy_path tmp_path cache_dir legacy_size copied_size

  local_path=$(search_db_local_path "$db" "$sdir_arg")
  legacy_path=$(search_db_legacy_path "$db" "$sdir_arg")

  if [ -f "$local_path" ]; then
    # Already migrated — leave the legacy file alone rather than deleting a path
    # we have not verified; another differently-configured tool may still read it.
    _search_db_is_sqlite "$local_path" && return 0
    # A truncated or empty local DB must not shadow migration forever: the
    # legacy copy is deleted by design, so this is the last chance to recover.
    if [ -f "$legacy_path" ]; then
      echo "search-db: local $local_path is not a valid SQLite image — re-migrating from legacy" >&2
      rm -f "$local_path" 2>/dev/null
    else
      echo "search-db: local $local_path is not a valid SQLite image and no legacy copy remains — run 'engine reindex'" >&2
      return 1
    fi
  fi

  # Nothing to move (fresh install, or already migrated and cleaned up).
  [ -f "$legacy_path" ] || return 0

  cache_dir=$(dirname "$local_path")
  if ! mkdir -p "$cache_dir" 2>/dev/null; then
    echo "search-db: cannot create $cache_dir — keeping $legacy_path" >&2
    return 1
  fi

  tmp_path="$local_path.$$.tmp"
  if ! cp "$legacy_path" "$tmp_path" 2>/dev/null; then
    rm -f "$tmp_path" 2>/dev/null
    echo "search-db: copy failed — keeping $legacy_path" >&2
    return 1
  fi

  legacy_size=$(wc -c < "$legacy_path" 2>/dev/null | tr -d ' ')
  copied_size=$(wc -c < "$tmp_path" 2>/dev/null | tr -d ' ')
  if [ -z "$copied_size" ] || [ "$legacy_size" != "$copied_size" ]; then
    rm -f "$tmp_path" 2>/dev/null
    echo "search-db: size mismatch ($legacy_size vs $copied_size) — keeping $legacy_path" >&2
    return 1
  fi

  # The size check catches a stalled Drive read but not a same-length corrupt
  # copy — and the next step deletes the only other copy, so verify the image
  # itself before that becomes irreversible.
  if ! _search_db_is_sqlite "$tmp_path"; then
    rm -f "$tmp_path" 2>/dev/null
    echo "search-db: copied file is not a valid SQLite image — keeping $legacy_path" >&2
    return 1
  fi

  # Atomic within one filesystem: concurrent runs each write a distinct pid
  # temp and the last rename wins, so no lock is required.
  if ! mv "$tmp_path" "$local_path" 2>/dev/null; then
    rm -f "$tmp_path" 2>/dev/null
    echo "search-db: rename failed — keeping $legacy_path" >&2
    return 1
  fi

  rm -f "$legacy_path" 2>/dev/null
  # doc-search derives its advisory lock from the DB path, so the lock moved
  # with the DB. Clear the orphan left behind in the old location.
  rm -f "$(dirname "$legacy_path")/${db%.db}.lock" 2>/dev/null
  echo "search-db: migrated $db to $local_path" >&2
  return 0
}

# THE wrapper entry point. Works out the sessions dir the CLI will use, migrates
# when the subcommand is `index`, and exports ENGINE_SEARCH_DB_PATH.
#
#   search_db_export_path session "$@"   # session-search wrappers
#   search_db_export_path doc     "$@"   # doc-search wrappers
#
# Never fails the caller: a search that falls back to the legacy path is slow,
# but a wrapper that aborts leaves the caller with no search at all.
search_db_export_path() {
  local kind="$1"; shift
  local subcmd="${1:-}" arg2="${2:-}"
  local db sessions_dir resolved

  if [ "$kind" = "session" ]; then
    db=".session-search.db"
    sessions_dir=""
    # `index <path>` wins — but only for a non-flag token. cli.ts's parseArgs
    # routes anything starting with `-` into flags and never into positionals,
    # so treating a flag as a path would mint a garbage namespace.
    if [ "$subcmd" = "index" ]; then
      case "$arg2" in
        ""|-*) ;;
        *) sessions_dir="$arg2" ;;
      esac
    fi
    if [ -z "$sessions_dir" ]; then
      if [ -n "${WORKSPACE:-}" ]; then
        sessions_dir="$PWD/$WORKSPACE/sessions"
      else
        sessions_dir="$PWD/sessions"
      fi
    fi
  else
    db=".doc-search.db"
    sessions_dir="$(search_db_project_root)/sessions"
  fi

  if [ "$subcmd" = "index" ]; then
    # index writes to the LOCAL path even when there was nothing to migrate —
    # otherwise a fresh install keeps creating the DB on Drive forever. Only a
    # genuinely failed migration falls back, so the run still works.
    if search_db_migrate "$db" "$sessions_dir"; then
      resolved="$(search_db_local_path "$db" "$sessions_dir")"
    else
      resolved="$(search_db_legacy_path "$db" "$sessions_dir")"
    fi
  else
    resolved="$(search_db_active_path "$db" "$sessions_dir")"
  fi

  ENGINE_SEARCH_DB_PATH="$resolved"
  export ENGINE_SEARCH_DB_PATH
}
