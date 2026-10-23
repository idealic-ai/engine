#!/bin/bash
# tests/test-receipt-sh.sh — receipt.sh: runs and gos stored as git notes, found by hash.
# Run: bash ~/.claude/engine/scripts/tests/run-all.sh test-receipt-sh.sh
#
# Every test builds a throwaway repo under mktemp; nothing touches a real repository.
# RECEIPT_SH points the suite at a modified copy, which is how each check was watched
# going red before it was trusted.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

RECEIPT="${RECEIPT_SH:-$(cd "$(dirname "$0")/.." && pwd)/receipt.sh}"

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

setup() {
  TMP_DIR=$(mktemp -d)
  setup_fake_home "$TMP_DIR"
  unset FLEET_PANE
  REPO="$TMP_DIR/repo"
  git init -q -b main "$REPO"
  printf 'a1\na2\na3\n' > "$REPO/a.txt"
  printf 'b1\n' > "$REPO/b.txt"
  git -C "$REPO" add a.txt b.txt
  git -C "$REPO" commit -q -m base
  cd "$REPO" || return 1
}

teardown() {
  cd / || true
  teardown_fake_home
  rm -rf "$TMP_DIR"
}

r() { bash "$RECEIPT" "$@"; }

commit_file() { # commit_file <file> <content> <msg>
  printf '%s\n' "$2" > "$1"; git add "$1"; git commit -q -m "$3"
}

test_receipt_run_records_clean_and_find_here_returns_it() {
  local out code
  out=$(r run --seat S1 -- bash -c 'echo first; echo; echo all 3 passed; echo' 2>&1); code=$?
  assert_eq 0 "$code" "run passes a zero exit through"
  assert_contains "receipt: tree:$(git rev-parse 'HEAD^{tree}')" "$out" "run prints the receipt key"
  out=$(r find --here); code=$?
  assert_eq 0 "$code" "find --here finds the clean receipt"
  assert_contains "all 3 passed" "$out" "summary is the last non-empty output line"
  assert_contains "seat=S1" "$out" "seat recorded"
  out=$(r find --commit HEAD --json)
  assert_eq "$(git rev-parse HEAD)" "$(jq -r .commit <<<"$out")" "found by commit too"
  assert_eq "false" "$(jq -r .dirty <<<"$out")" "clean run is not dirty"
}

test_receipt_summary_skips_a_closing_rule() {
  r run -- bash -c 'printf "\033[32m9 passed\033[0m\n=====\n\n"' >/dev/null 2>&1
  assert_eq "9 passed" "$(r find --here --json | jq -r .summary)" "the summary is the last line with content, colour stripped"
  r run --summary "given by hand" -- true >/dev/null 2>&1
  assert_contains "given by hand" "$(r find --here --json | jq -r .summary)" "--summary overrides it"
}

test_receipt_run_passes_failure_exit_through() {
  local code
  r run -- bash -c 'echo boom; exit 7' >/dev/null 2>&1; code=$?
  assert_eq 7 "$code" "run passes a failing exit code through"
  assert_contains "exit=7" "$(r find --here)" "the failure is recorded"
}

test_receipt_dirty_run_is_marked_and_never_reusable() {
  echo dirty >> a.txt
  r run -- true >/dev/null 2>&1
  local out code
  out=$(r find --here 2>/dev/null); code=$?
  assert_eq 1 "$code" "find --here on a dirty tree returns nothing reusable"
  out=$(r find --commit HEAD 2>/dev/null); code=$?
  assert_eq 1 "$code" "a dirty run is not returned by commit either"
  out=$(r find --here --all); code=$?
  assert_eq 0 "$code" "--all shows the dirty receipt"
  assert_contains "DIRTY" "$out" "and marks it dirty"
  assert_neq "$(git rev-parse 'HEAD^{tree}')" "$(r find --here --all --json | jq -r .tree)" \
    "a dirty receipt is keyed by the snapshot tree, not HEAD's"
  assert_eq "a.txt" "$(git diff --cached --name-only; git diff --name-only)" \
    "the real index is untouched (a.txt still unstaged only)"
}

test_receipt_find_flags_inconsistent_exit_codes() {
  local flag="$TMP_DIR/flag"
  touch "$flag"
  r run -- test -f "$flag" >/dev/null 2>&1
  rm "$flag"
  r run -- test -f "$flag" >/dev/null 2>&1
  r run -- true >/dev/null 2>&1
  local out; out=$(r find --here)
  assert_contains "inconsistent: test -f" "$out" "same command, different exits is flagged"
  assert_not_contains "inconsistent: true" "$out" "a consistent command is not flagged"
}

test_receipt_concurrent_appends_lose_nothing() {
  local i n=16 id
  id=$(r id HEAD --form whole)
  for i in $(seq 1 $n); do
    r go "$id" --form whole --owner "O$i" --seat "W$i" >/dev/null 2>&1 &
  done
  wait
  local got; got=$(r find --patch "$id" --json | jq -r .owner | sort -u | wc -l | tr -d ' ')
  assert_eq "$n" "$got" "all $n concurrent gos are present under the key"
  got=$(git notes --ref=receipts show "$(printf 'receipt-key:index:go' | git hash-object --stdin)" \
    | sed '/^$/d' | wc -l | tr -d ' ')
  assert_eq "$n" "$got" "and in the go index"
  assert_empty "$(git for-each-ref refs/notes/receipts-tmp)" "no temp refs left behind"
}

test_receipt_second_worktree_reads_the_same_notes() {
  r run --seat S1 -- true >/dev/null 2>&1
  local tree; tree=$(git rev-parse 'HEAD^{tree}')
  git worktree add -q "$TMP_DIR/wt2" -b side
  local out code
  out=$(cd "$TMP_DIR/wt2" && bash "$RECEIPT" find --here); code=$?
  assert_eq 0 "$code" "a second worktree finds the receipt by its tree"
  assert_contains "seat=S1" "$out" "it is the same receipt"
  (cd "$TMP_DIR/wt2" && bash "$RECEIPT" go "$(bash "$RECEIPT" id HEAD --form whole)" --form whole --owner W2) 2>/dev/null
  assert_contains "owner=W2" "$(r find --patch "$(r id HEAD --form whole)")" "and a go written there is read here"
}

test_receipt_go_given_whole_does_not_satisfy_path_scoped_check() {
  commit_file a.txt 'a-changed' 'touch a'
  local whole path out code
  whole=$(r id HEAD --form whole+text)
  path=$(r id HEAD --form path+text --paths a.txt)
  assert_eq "$whole" "$path" "precondition: on a one-file commit both forms give the same id"
  r go "$whole" --form whole+text --owner Claims >/dev/null 2>&1
  out=$(r check main~1..main --owner Claims=a.txt); code=$?
  assert_eq 1 "$code" "a whole go does not pass a path-scoped check"
  assert_contains "FORM-MISMATCH (a go exists in form whole+text, not path+text" "$out" "named as a form mismatch"
  assert_not_contains "MISSING" "$out" "not reported as plain missing"
  local notext; notext=$(r id HEAD --form path --paths a.txt)
  assert_eq "$path" "$notext" "precondition: on a text file --text does not change the id"
  r go "$notext" --form path --paths a.txt --owner Claims >/dev/null 2>&1
  out=$(r check main~1..main --owner Claims=a.txt); code=$?
  assert_eq 1 "$code" "a go given without --text does not pass a --text check on the same paths"
  assert_contains "FORM-MISMATCH (a go exists in form path,whole+text, not path+text" "$out" "both other forms named"
  r go "$path" --form path+text --paths a.txt --owner Claims >/dev/null 2>&1
  out=$(r check main~1..main --owner Claims=a.txt); code=$?
  assert_eq 0 "$code" "the path-scoped go passes"
  assert_contains "by unknown" "$out" "and names its giver"
}

test_receipt_go_survives_a_rebase() {
  git checkout -q -b topic
  commit_file a.txt 'topic-change' 'topic'
  local id; id=$(r id HEAD --form path+text --paths a.txt)
  r go "$id" --form path+text --paths a.txt --owner Legal --commit HEAD >/dev/null 2>&1
  git checkout -q main
  commit_file b.txt 'main-moved' 'main moves'
  git checkout -q -b topic2
  git cherry-pick topic >/dev/null
  assert_neq "$(git rev-parse topic)" "$(git rev-parse HEAD)" "precondition: a different sha"
  assert_eq "topic" "$(git log -1 --format=%s)" "precondition: the re-pick landed"
  local out code
  out=$(r check main..topic2 --owner Legal=a.txt); code=$?
  assert_eq 0 "$code" "the go given before the re-pick is found after it"
  assert_contains "go     owner=Legal form=path+text paths=a.txt" "$out" "the go is listed against the new sha"
}

test_receipt_check_fails_closed_without_an_ownership_map() {
  commit_file a.txt 'a-new' 'change a'
  r run -- true >/dev/null 2>&1
  local out code
  out=$(r check main~1..main); code=$?
  assert_eq 1 "$code" "no map + clean merge + passing receipts still fails"
  assert_contains "owner=undeclared" "$out" "the path is undeclared"
  assert_contains "MISSING" "$out" "and its go is missing"
  assert_contains "clean" "$out" "while the merge itself is clean"
}

test_receipt_check_reports_empty_paths_not_an_id() {
  commit_file a.txt 'a-only' 'only a'
  local out code
  out=$(r check main~1..main --owner Xact=b.txt); code=$?
  assert_contains "EMPTY" "$out" "an untouched owner path is EMPTY"
  assert_eq 0 "$code" "and needs no go"
  r id HEAD --paths b.txt >/dev/null; code=$?
  assert_eq 1 "$code" "id refuses to print an id for an empty diff"
}

test_receipt_check_detects_merge_conflicts() {
  git checkout -q -b other
  commit_file a.txt 'other-side' 'other'
  git checkout -q main
  git checkout -q -b mine
  commit_file a.txt 'my-side' 'mine'
  local id out code
  id=$(r id HEAD --form path+text --paths a.txt)
  r go "$id" --form path+text --paths a.txt --owner O >/dev/null 2>&1
  out=$(r check main..mine --owner O=a.txt); code=$?
  assert_eq 0 "$code" "gos present and merge onto main clean"
  out=$(r check main..mine --owner O=a.txt --against other); code=$?
  assert_eq 1 "$code" "a conflict against another branch fails the check"
  assert_contains "onto other: CONFLICT" "$out" "the conflict is named"
  assert_contains "a.txt" "$out" "with its file"
}

test_receipt_withdrawn_go_no_longer_counts() {
  commit_file a.txt 'w' 'w'
  local id; id=$(r id HEAD --paths a.txt)
  r go "$id" --form path+text --paths a.txt --owner O >/dev/null 2>&1
  r go "$id" --form path+text --paths a.txt --owner O --withdraw >/dev/null 2>&1
  local code; r check main~1..main --owner O=a.txt >/dev/null; code=$?
  assert_eq 1 "$code" "a withdrawn go is a new entry that cancels the go"
  assert_eq 2 "$(r find --patch "$id" --json | wc -l | tr -d ' ')" "both entries are kept"
}

test_receipt_go_refuses_an_id_the_commit_does_not_give() {
  commit_file a.txt 'x' 'x'
  local wrong; wrong=$(r id HEAD --form whole)
  local code; r go "$wrong" --form path --paths b.txt --owner O --commit HEAD >/dev/null 2>&1; code=$?
  assert_eq 2 "$code" "a go whose id does not match its stated commit and form is refused"
}

test_receipt_sync_carries_gos_between_clones() {
  local bare="$TMP_DIR/remote.git" A="$TMP_DIR/A" B="$TMP_DIR/B"
  git clone -q --bare "$REPO" "$bare"
  git clone -q "$bare" "$A"
  git clone -q "$bare" "$B"
  local id; id=$(cd "$A" && bash "$RECEIPT" id HEAD --form whole)
  (cd "$A" && bash "$RECEIPT" go "$id" --form whole --owner Claims --seat SA) 2>/dev/null
  local code
  (cd "$B" && bash "$RECEIPT" find --patch "$id") >/dev/null 2>&1; code=$?
  assert_eq 1 "$code" "precondition: clone B cannot see A's go before a sync"
  (cd "$A" && bash "$RECEIPT" sync) 2>/dev/null
  (cd "$B" && bash "$RECEIPT" go "$id" --form whole --owner Legal --seat SB) 2>/dev/null
  (cd "$B" && bash "$RECEIPT" sync) 2>/dev/null; code=$?
  assert_eq 0 "$code" "B syncs over its own diverged notes"
  local out; out=$(cd "$B" && bash "$RECEIPT" find --patch "$id")
  assert_contains "owner=Claims" "$out" "A's go is found in clone B after sync"
  assert_contains "owner=Legal" "$out" "and B's own go is kept"
  (cd "$A" && bash "$RECEIPT" sync) 2>/dev/null
  assert_contains "owner=Legal" "$(cd "$A" && bash "$RECEIPT" find --patch "$id")" "B's go reaches A"
  assert_contains "+refs/notes/receipts:refs/notes/receipts-remote/origin" \
    "$(git -C "$A" config --get-all remote.origin.fetch)" "a fetch refspec is configured"
  local before after
  before=$(git -C "$A" rev-list refs/notes/receipts | wc -l | tr -d ' ')
  (cd "$A" && bash "$RECEIPT" sync) 2>/dev/null
  after=$(git -C "$A" rev-list refs/notes/receipts | wc -l | tr -d ' ')
  assert_eq "$before" "$after" "a sync with nothing new writes nothing"
}

test_receipt_lookups_write_nothing_in_a_clone_that_never_wrote() {
  local bare="$TMP_DIR/remote.git" C="$TMP_DIR/C" id
  id=$(r id HEAD --form whole)
  r go "$id" --form whole --owner Claims >/dev/null 2>&1
  # file:// forces the pack transport; a local-path clone hardlinks every object, the
  # unreachable key objects included, and would hide a lookup that needs them.
  git clone -q --bare "file://$REPO" "$bare"
  git remote add origin "$bare"
  r sync >/dev/null 2>&1
  git clone -q "file://$bare" "$C"
  local key; key=$(printf 'receipt-key:patch:%s' "$id" | git hash-object --stdin)
  git -C "$C" cat-file -e "$key" 2>/dev/null
  assert_eq 1 "$?" "precondition: clone C does not hold the key object"
  (cd "$C" && bash "$RECEIPT" sync --no-push) 2>/dev/null
  local before after out
  before=$(git -C "$C" count-objects -v | awk '/^count:/{print $2}')
  out=$(cd "$C" && bash "$RECEIPT" find --patch "$id")
  (cd "$C" && bash "$RECEIPT" check HEAD~0..HEAD) >/dev/null 2>&1
  after=$(git -C "$C" count-objects -v | awk '/^count:/{print $2}')
  assert_contains "owner=Claims" "$out" "a clone that never stored the key object still finds the go"
  assert_eq "$before" "$after" "find and check add no objects to the repo"
}

test_receipt_withdrawal_ordered_by_time_after_a_sorting_merge() {
  commit_file a.txt 'w2' 'w2'
  local bare="$TMP_DIR/remote.git" A="$TMP_DIR/A" id
  git clone -q --bare "$REPO" "$bare"
  git clone -q "$bare" "$A"
  id=$(cd "$A" && bash "$RECEIPT" id HEAD --paths a.txt)
  (cd "$A" && bash "$RECEIPT" go "$id" --form path+text --paths a.txt --owner O --withdraw \
     && bash "$RECEIPT" sync) 2>/dev/null
  git remote add origin "$bare"
  r go "$id" --form path+text --paths a.txt --owner O >/dev/null 2>&1
  r sync >/dev/null 2>&1
  local code; r check main~1..main --owner O=a.txt >/dev/null; code=$?
  assert_eq 0 "$code" "the later go wins over the earlier withdrawal whatever the merged line order"
}

run_discovered_tests
