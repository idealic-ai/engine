#!/bin/bash
# Test: session-search and doc-search work from a worktree, by falling back to the live session's project.
#
# IDE-333 round 2. Both searches find their database from the working directory: session-search reads
# `$PWD/sessions`, doc-search the project root above `$PWD`. A loom lane works in a worktree, which has
# neither, so a bare `engine session-search query …` exited 1 there ("Sessions directory not found"),
# and so did doc-search ("No index found"). search-db-lib.sh now falls back to the project of the live
# session (`engine session find`), and only when the working directory yields nothing.
#
# Each wrapper (the two in scripts/ and the two in tools/) runs for real from three places — the main
# checkout, a worktree of that project, and a worktree of an unrelated repository — against a stubbed
# index. The stubs: `engine` (session find prints the live session), `curl` (the embed gate sees a
# runner with the model), and `npx`, which stands in for the TypeScript CLI and makes the same two
# checks it makes (session-search: `$PWD/sessions` exists; both: the exported DB file exists), then
# reports the project doc-search would name. No Ollama, no network.

source "$(dirname "$0")/test-helpers.sh"

ENGINE_DIR="${SEARCH_ENGINE_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
echo "under test: $ENGINE_DIR/scripts/search-db-lib.sh"

T=$(cd "$(mktemp -d)" && pwd -P)
REAL_HOME="$HOME"
trap 'rm -rf "$T"' EXIT

git_init() {  # $1 dir — a repository with one commit
  mkdir -p "$1"
  git -C "$1" init -q -b main
  git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
}

# ── fixture: a project with a live session, a worktree of it, and an unrelated repo's worktree ──
KIT="$T/kit"; SESSION="$KIT/sessions/2026_10_30_LIVE"
git_init "$KIT"; mkdir -p "$KIT/.claude" "$SESSION"; echo '{}' > "$SESSION/.state.json"
git -C "$KIT" worktree add -q -b lane "$T/kit-wt/lane"
ENG="$T/engine"; git_init "$ENG"
git -C "$ENG" worktree add -q -b lane2 "$T/engine-wt/lane2"

# A fake HOME, so the scripts/ wrappers' `$HOME/.claude/tools/<tool>` resolves and the real cache is
# never touched.
export HOME="$T/home"
mkdir -p "$HOME/.claude/tools/session-search/src" "$HOME/.claude/tools/doc-search/src"
export ENGINE_SEARCH_DB_DIR="$T/cache" ENGINE_SCRIPTS="$ENGINE_DIR/scripts"
unset WORKSPACE

BIN="$T/bin"; mkdir -p "$BIN"
cat > "$BIN/engine" <<EOF
#!/bin/bash
[ "\$1 \$2" = "session find" ] || exit 2
[ -n "\${STUB_NO_SESSION:-}" ] && exit 1
echo called >> "$T/find-calls"
echo "$SESSION"
EOF
cat > "$BIN/curl" <<'EOF'
#!/bin/bash
echo '{"models":[{"name":"embeddinggemma:latest"}]}'
EOF
cat > "$BIN/npx" <<'EOF'
#!/bin/bash
# argv: --prefix <tool dir> tsx <the CLI source under the tool dir> <args…>
cli="$4"
case "$cli" in
  */session-search/src/*)
    [ -d "$PWD/sessions" ] || { echo "Error: Sessions directory not found: $PWD/sessions" >&2; exit 1; } ;;
esac
[ -f "${ENGINE_SEARCH_DB_PATH:-}" ] || { echo "Error: No index found. Run 'index' first." >&2; exit 1; }
d="$PWD"; while [ "$d" != / ] && [ ! -d "$d/.claude" ]; do d=$(dirname "$d"); done
[ "$d" = / ] && d=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
echo "Project: $(basename "$d")"
echo "db: $ENGINE_SEARCH_DB_PATH"
EOF
chmod +x "$BIN"/*
export PATH="$BIN:$PATH"

# The stubbed index: both databases at the local path the lib computes for the project's sessions dir.
# shellcheck source=/dev/null
source "$ENGINE_DIR/scripts/search-db-lib.sh"
for db in "$SEARCH_DB_SESSION_FILE" "$SEARCH_DB_DOC_FILE"; do
  f=$(search_db_local_path "$db" "$KIT/sessions"); mkdir -p "$(dirname "$f")"
  echo "CREATE TABLE t(x);" | sqlite3 "$f"
done

WRAPPERS="scripts/session-search.sh scripts/doc-search.sh tools/session-search/session-search.sh tools/doc-search/doc-search.sh"

run_from() {  # $1 label, $2 dir — every wrapper must run and name the project's index
  local label="$1" dir="$2" w out rc
  for w in $WRAPPERS; do
    out=$(cd "$dir" && bash "$ENGINE_DIR/$w" query "landing protocol" --limit 5 2>&1); rc=$?
    if [ "$rc" -eq 0 ] && [[ "$out" == *"Project: kit"* ]] && [[ "$out" == *"db: $ENGINE_SEARCH_DB_DIR/"* ]]; then
      pass "$label: $w query exits 0 against the project's index"
    else
      fail "$label: $w query exits 0 against the project's index" "exit 0, Project: kit, db under the cache" "exit $rc: $out"
    fi
  done
}

test_main_checkout_works_without_asking_the_live_session() {
  rm -f "$T/find-calls"
  run_from "main checkout" "$KIT"
  if [ -f "$T/find-calls" ]; then
    fail "main checkout: today's resolution answers first" "engine session find not called" "called $(wc -l < "$T/find-calls" | tr -d ' ') times"
  else
    pass "main checkout: today's resolution answers first, engine session find is never called"
  fi
}

test_a_worktree_of_the_project_falls_back_to_the_live_session() {
  run_from "kit worktree" "$T/kit-wt/lane"
}

test_a_worktree_of_another_repo_falls_back_to_the_live_session() {
  run_from "engine worktree" "$T/engine-wt/lane2"
}

test_no_live_session_leaves_todays_failure_unchanged() {
  # Control: with no session to fall back to, a worktree still fails as it did, so the passes above
  # come from the fallback and not from a fixture that would have passed anyway.
  local out rc
  out=$(cd "$T/engine-wt/lane2" && STUB_NO_SESSION=1 bash "$ENGINE_DIR/scripts/session-search.sh" query "x" 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"Sessions directory not found"* ]] \
    && pass "control: without a live session, session-search from a worktree still exits non-zero" \
    || fail "control: without a live session it still fails" "non-zero, Sessions directory not found" "exit $rc: $out"
}

run_discovered_tests
