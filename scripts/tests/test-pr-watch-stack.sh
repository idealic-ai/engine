#!/bin/bash
# ============================================================================
# test-pr-watch-stack.sh — the /pr §3 watch loop on a stacked PR
# ============================================================================
# The watch loop lives only as a fenced block in skills/pr/SKILL.md, so this suite
# extracts that block, runs it against a fake `gh`, and checks the line it exits on.
# The fake gh serves JSON fixtures and applies the loop's real --jq with real jq.
# Only these substitutions are made to the extracted block:
#   - the <owner>/<repo>/<n> placeholders are filled in
#   - `sleep 20` becomes `sleep 0`, which changes wall-clock time only
#   - `seq 1 135` becomes `seq 1 $TICKS`
#
# Cases, each run under sh, bash and zsh:
#   non-bottom PR whose lower PRs are open → PR_BLOCKED reason=stacked_below_unmerged below="5 6"
#   bottom PR of a stack                   → PR_COMPLETE
#   non-bottom PR whose lower PRs merged   → PR_COMPLETE
#   unstacked PR (.stack null)             → PR_COMPLETE
# Control: the same non-bottom case, run against a copy of SKILL.md with the stack check
# removed, must NOT block. If it still blocks, the first case never discriminated.
# ============================================================================
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SKILL="${PR_SKILL:-$(cd "$(dirname "$0")/../.." && pwd)/skills/pr/SKILL.md}"
TMP=""

extract_loop() {   # extract_loop <SKILL.md> <out>
  local src="$1" out="$2" start end
  start=$(grep -n '^     OWNER=<owner>; REPO=<repo>; N=<n>$' "$src" | cut -d: -f1)
  end=$(grep -n 'reason=heartbeat_45min' "$src" | cut -d: -f1)
  [ -n "$start" ] && [ -n "$end" ] || return 1
  sed -n "${start},${end}p" "$src" \
    | sed -e 's/^     //' \
          -e 's/OWNER=<owner>; REPO=<repo>; N=<n>/OWNER=acme; REPO=widget; N=${PRN:-7}/' \
          -e 's/seq 1 135/seq 1 ${TICKS:-12}/' \
          -e 's/sleep 20/sleep 0/' > "$out"
}

write_fake_gh() {
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/gh" <<'FAKE'
#!/bin/sh
FX="${FX:?}"
[ "$1" = "api" ] || exit 1
shift
path=""; jqx=""; isgql=0
while [ $# -gt 0 ]; do
  case "$1" in
    --jq) jqx="$2"; shift 2 ;;
    -H|-f) case "$2" in query=*) isgql=1 ;; esac; shift 2 ;;
    --paginate) shift ;;
    graphql) isgql=1; shift ;;
    -*) shift ;;
    *) path="$1"; shift ;;
  esac
done
if [ "$isgql" = 1 ]; then src="$FX/graphql.json"
else
  case "$path" in
    */pulls/*/reviews*)   src="$FX/reviews.json" ;;
    */pulls/*/comments*)  src="$FX/pr_comments.json" ;;
    */pulls/*)            src="$FX/pull.json" ;;
    */stacks/*)           src="$FX/stack.json" ;;
    */check-runs*)        src="$FX/check_runs.json" ;;
    */reactions*)         src="$FX/reactions.json" ;;
    */issues/*/comments*) src="$FX/issue_comments.json" ;;
    *) echo "FAKEGH: unmapped path: $path" >&2; exit 1 ;;
  esac
fi
[ -f "$src" ] || { echo "FAKEGH: missing fixture $src" >&2; exit 1; }
if [ -n "$jqx" ]; then jq -r "$jqx" < "$src"; else cat "$src"; fi
FAKE
  chmod +x "$TMP/bin/gh"
}

# fixture <name> <pull.json body> <stack.json body>
# Everything else is a ready PR: green checks, both reviewers settled, nothing owed, CLEAN.
fixture() {
  local d="$TMP/fx_$1"; mkdir -p "$d"
  printf '%s\n' "$2" > "$d/pull.json"
  printf '%s\n' "$3" > "$d/stack.json"
  echo '{"check_runs":[{"id":1,"name":"build","status":"completed","conclusion":"success"}]}' > "$d/check_runs.json"
  echo '[{"id":11,"user":{"login":"copilot-pull-request-reviewer[bot]"},"body":""},{"id":12,"user":{"login":"chatgpt-codex-connector[bot]"},"body":""}]' > "$d/reviews.json"
  echo '[]' > "$d/pr_comments.json"
  echo '[]' > "$d/issue_comments.json"
  echo '[]' > "$d/reactions.json"
  echo '{"data":{"repository":{"pullRequest":{"mergeStateStatus":"CLEAN","mergeable":"MERGEABLE","reviewDecision":"APPROVED"}}}}' > "$d/graphql.json"
}

STACK_OPEN='{"number":8,"pull_requests":[{"number":5,"state":"open"},{"number":6,"state":"open"},{"number":7,"state":"open"},{"number":9,"state":"open"}]}'
STACK_MERGED='{"number":8,"pull_requests":[{"number":5,"state":"closed","merged_at":"t"},{"number":6,"state":"closed","merged_at":"t"},{"number":7,"state":"open"}]}'

setup() {
  TMP=$(mktemp -d)
  write_fake_gh
  extract_loop "$SKILL" "$TMP/loop.sh" || { echo "FAIL: watch fence not found in $SKILL"; }
  fixture upper   '{"head":{"sha":"aaa111"},"draft":false,"stack":{"number":8,"position":3,"size":4}}' "$STACK_OPEN"
  fixture bottom  '{"head":{"sha":"aaa111"},"draft":false,"stack":{"number":8,"position":1,"size":4}}' "$STACK_OPEN"
  fixture merged  '{"head":{"sha":"aaa111"},"draft":false,"stack":{"number":8,"position":3,"size":3}}' "$STACK_MERGED"
  fixture plain   '{"head":{"sha":"aaa111"},"draft":false,"stack":null}' '{}'
}

teardown() { rm -rf "$TMP"; }

run_loop() {   # run_loop <loop> <fixture> <pr number> <shell> → the exit line
  FX="$TMP/fx_$2" PRN="$3" PATH="$TMP/bin:$PATH" TICKS=12 "$4" "$1" 2>/dev/null | grep -o 'PR_[A-Z_]*.*' | tail -1
}

test_upper_pr_blocks_while_lower_prs_are_open() {
  local sh out
  for sh in sh bash zsh; do
    out=$(run_loop "$TMP/loop.sh" upper 7 "$sh")
    assert_contains 'PR_BLOCKED pr=7 head=aaa111 reason=stacked_below_unmerged stack=8 position=3 below="5 6"' "$out" "[$sh] non-bottom PR with open PRs below → stacked_below_unmerged naming only the PRs below"
  done
}

test_bottom_pr_completes() {
  local sh out
  for sh in sh bash zsh; do
    out=$(run_loop "$TMP/loop.sh" bottom 5 "$sh")
    assert_contains 'PR_COMPLETE pr=5' "$out" "[$sh] bottom PR of a stack → PR_COMPLETE"
  done
}

test_upper_pr_completes_once_lower_prs_merged() {
  local sh out
  for sh in sh bash zsh; do
    out=$(run_loop "$TMP/loop.sh" merged 7 "$sh")
    assert_contains 'PR_COMPLETE pr=7' "$out" "[$sh] lower PRs merged → PR_COMPLETE"
  done
}

test_unstacked_pr_completes() {
  local sh out
  for sh in sh bash zsh; do
    out=$(run_loop "$TMP/loop.sh" plain 7 "$sh")
    assert_contains 'PR_COMPLETE pr=7' "$out" "[$sh] unstacked PR → PR_COMPLETE"
  done
}

test_control_without_the_stack_check_does_not_block() {
  # Plant: delete the stack check from a copy of SKILL.md. The upper case must then exit
  # PR_COMPLETE. That proves the blocking result above comes from the check itself.
  sed '/A non-bottom PR in a stack can read CLEAN/,/^         fi$/d' "$SKILL" > "$TMP/planted.md"
  local removed; removed=$(( $(wc -l < "$SKILL") - $(wc -l < "$TMP/planted.md") ))
  assert_gt "$removed" 5 "plant removed the stack-check block ($removed lines)"
  extract_loop "$TMP/planted.md" "$TMP/loop_planted.sh"
  local out; out=$(run_loop "$TMP/loop_planted.sh" upper 7 bash)
  assert_contains 'PR_COMPLETE pr=7' "$out" "control: with the check removed, the same upper PR reads PR_COMPLETE"
}

run_discovered_tests
