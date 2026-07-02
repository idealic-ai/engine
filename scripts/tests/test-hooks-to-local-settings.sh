#!/bin/bash
# ============================================================================
# test-hooks-to-local-settings.sh — engine hooks route to settings.local.json
# ============================================================================
# Engine hook commands are version-specific absolute paths and must never land
# in the shared, tracked .claude/settings.json (teammates on a different engine
# version get "No such file" on every tool). configure_hooks writes them to the
# gitignored settings.local.json; the shared settings.json keeps only the
# version-agnostic statusLine + permissions, with any leftover hooks defused.
# ============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
source "$SCRIPT_DIR/../setup-lib.sh"

TEST_DIR=""
setup() { TEST_DIR=$(mktemp -d); export VERBOSE=false; ACTIONS=(); }
teardown() { [ -n "$TEST_DIR" ] && rm -rf "$TEST_DIR"; TEST_DIR=""; }

# HLS-01: configure_hooks populates settings.local.json
setup
echo '{}' > "$TEST_DIR/settings.local.json"
configure_hooks "$TEST_DIR/settings.local.json"
assert_contains "pre-tool-use-overflow-v2.sh" "$(cat "$TEST_DIR/settings.local.json")" "HLS-01: hooks written to settings.local.json"
assert_json "$TEST_DIR/settings.local.json" '.hooks.PreToolUse | length' "2" "HLS-01b: PreToolUse has overflow-v2 + one-strike"
assert_contains "post-tool-use-templates.sh" "$(cat "$TEST_DIR/settings.local.json")" "HLS-01c: PostToolUse templates wired"
assert_contains "subagent-start-context.sh" "$(cat "$TEST_DIR/settings.local.json")" "HLS-01d: SubagentStart wired"
teardown

# HLS-02: routing hooks to the local file adds NO hooks to the shared settings.json
setup
echo '{"permissions":{"allow":["Bash(engine *)"]},"statusLine":{"type":"command","command":"~/.claude/tools/statusline.sh"}}' > "$TEST_DIR/settings.json"
echo '{}' > "$TEST_DIR/settings.local.json"
configure_hooks "$TEST_DIR/settings.local.json"
assert_eq "false" "$(jq 'has("hooks")' "$TEST_DIR/settings.json")" "HLS-02: shared settings.json gains no hooks"
assert_json "$TEST_DIR/settings.json" '.statusLine.command' "~/.claude/tools/statusline.sh" "HLS-02b: statusLine preserved in shared file"
teardown

# HLS-03: defuse (the engine's cleanup jq) empties populated hooks in settings.json
setup
cat > "$TEST_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"~/.claude/hooks/pre-tool-use-overflow-v2.sh"}]}],"Stop":[]}}
JSON
echo "$(jq '.hooks |= map_values([])' "$TEST_DIR/settings.json")" > "$TEST_DIR/settings.json"
assert_json "$TEST_DIR/settings.json" '.hooks.PreToolUse | length' "0" "HLS-03: populated hooks emptied"
assert_not_contains "overflow-v2" "$(cat "$TEST_DIR/settings.json")" "HLS-03b: no script refs remain after defuse"
teardown

# HLS-04: defuse is idempotent — byte-identical on already-empty hooks (no git churn)
setup
echo '{"hooks":{"PreToolUse":[],"Stop":[]}}' | jq '.' > "$TEST_DIR/settings.json"
BEFORE=$(cat "$TEST_DIR/settings.json")
AFTER=$(echo "$BEFORE" | jq '.hooks |= map_values([])')
assert_eq "$BEFORE" "$AFTER" "HLS-04: defuse no-ops on already-empty hooks"
teardown

# HLS-05: effective set (empty shared + populated local) yields the real hook exactly once
setup
echo '{"hooks":{"PreToolUse":[]}}' > "$TEST_DIR/settings.json"
echo '{}' > "$TEST_DIR/settings.local.json"
configure_hooks "$TEST_DIR/settings.local.json"
COUNT=$(jq -s '[.[].hooks.PreToolUse[]?] | map(select(.hooks[0].command|test("overflow-v2"))) | length' "$TEST_DIR/settings.json" "$TEST_DIR/settings.local.json")
assert_eq "1" "$COUNT" "HLS-05: overflow-v2 present exactly once across merged settings"
teardown

# HLS-06: SessionStart is wired as 24 chunk-emitter commands (truncation workaround)
setup
echo '{}' > "$TEST_DIR/settings.local.json"
configure_hooks "$TEST_DIR/settings.local.json"
assert_json "$TEST_DIR/settings.local.json" '.hooks.SessionStart[0].hooks | length' "24" "HLS-06: SessionStart has 24 chunk commands"
assert_contains "session-start-chunk.sh 0 24" "$(cat "$TEST_DIR/settings.local.json")" "HLS-06b: first chunk command present"
assert_contains "session-start-chunk.sh 23 24" "$(cat "$TEST_DIR/settings.local.json")" "HLS-06c: last chunk command present"
teardown

# HLS-07: legacy single session-start-restore.sh entry is migrated to chunks
setup
cat > "$TEST_DIR/settings.local.json" <<'JSON'
{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"~/.claude/hooks/session-start-restore.sh","timeout":30}]}]}}
JSON
configure_hooks "$TEST_DIR/settings.local.json"
assert_json "$TEST_DIR/settings.local.json" '.hooks.SessionStart | length' "1" "HLS-07: one SessionStart entry after migration"
assert_json "$TEST_DIR/settings.local.json" '.hooks.SessionStart[0].hooks | length' "24" "HLS-07b: legacy restore hook replaced by 24 chunks"
assert_json "$TEST_DIR/settings.local.json" '[.hooks.SessionStart[].hooks[].command | select(test("restore"))] | length' "0" "HLS-07c: no session-start-restore.sh left"
teardown

# HLS-08: SessionStart wiring is idempotent (re-run keeps one entry, 24 chunks)
setup
echo '{}' > "$TEST_DIR/settings.local.json"
configure_hooks "$TEST_DIR/settings.local.json"
configure_hooks "$TEST_DIR/settings.local.json"
assert_json "$TEST_DIR/settings.local.json" '.hooks.SessionStart | length' "1" "HLS-08: still one SessionStart entry after re-run"
assert_json "$TEST_DIR/settings.local.json" '.hooks.SessionStart[0].hooks | length' "24" "HLS-08b: still 24 chunks after re-run"
teardown

exit_with_results
