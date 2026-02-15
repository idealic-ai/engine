#!/bin/bash
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

setup() {
  TMP_DIR=$(mktemp -d)
  setup_fake_home "$TMP_DIR"
  disable_fleet_tmux

  # Symlink lib.sh (read-only, safe to symlink)
  ln -sf "$SCRIPT_DIR/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"

  # Source lib.sh so resolve_refs is available
  source "$FAKE_HOME/.claude/scripts/lib.sh"
  # Reset guard so re-sourcing works across tests
  _LIB_SH_LOADED=""

  # Set up engine .directives structure
  ENGINE_DIRECTIVES="$FAKE_HOME/.claude/engine/.directives"
  mkdir -p "$ENGINE_DIRECTIVES/commands"
  mkdir -p "$ENGINE_DIRECTIVES/formats"
  mkdir -p "$ENGINE_DIRECTIVES/invariants"

  # Set up project root
  export PROJECT_ROOT="$TMP_DIR/project"
  mkdir -p "$PROJECT_ROOT"
}

teardown() {
  teardown_fake_home
  _LIB_SH_LOADED=""
  rm -rf "$TMP_DIR"
}

# --- Test Cases ---

test_resolve_refs_finds_bare_cmd_references() {
  # Case 1: Should find bare §CMD_ references in a file
  cat > "$ENGINE_DIRECTIVES/commands/CMD_FOO.md" <<'EOF'
# CMD_FOO
Some command definition.
EOF
  cat > "$ENGINE_DIRECTIVES/commands/CMD_BAR.md" <<'EOF'
# CMD_BAR
Another command definition.
EOF

  local test_file="$TMP_DIR/test_input.md"
  cat > "$test_file" <<'EOF'
# Test File
Execute §CMD_FOO then §CMD_BAR.
EOF

  source "$FAKE_HOME/.claude/scripts/lib.sh"
  local output
  output=$(resolve_refs "$test_file" 2 '[]')

  assert_contains "CMD_FOO.md" "$output" "finds CMD_FOO reference"
  assert_contains "CMD_BAR.md" "$output" "finds CMD_BAR reference"
}

test_resolve_refs_ignores_backtick_escaped() {
  # Case 2: Should ignore backtick-escaped references
  cat > "$ENGINE_DIRECTIVES/commands/CMD_FOO.md" <<'EOF'
# CMD_FOO
EOF
  cat > "$ENGINE_DIRECTIVES/commands/CMD_BAR.md" <<'EOF'
# CMD_BAR
EOF

  local test_file="$TMP_DIR/test_input.md"
  # Use printf to avoid backtick interpretation issues
  printf '# Test File\nSee `§CMD_FOO` for reference. Execute §CMD_BAR.\n' > "$test_file"

  source "$FAKE_HOME/.claude/scripts/lib.sh"
  local output
  output=$(resolve_refs "$test_file" 2 '[]')

  assert_not_contains "CMD_FOO.md" "$output" "ignores backtick-escaped CMD_FOO"
  assert_contains "CMD_BAR.md" "$output" "finds bare CMD_BAR"
}

test_resolve_refs_respects_depth_limit() {
  # Case 3: Should respect depth limit
  # CMD_A references CMD_B, CMD_B references CMD_C
  cat > "$ENGINE_DIRECTIVES/commands/CMD_A.md" <<'EOF'
# CMD_A
See §CMD_B for details.
EOF
  cat > "$ENGINE_DIRECTIVES/commands/CMD_B.md" <<'EOF'
# CMD_B
See §CMD_C for details.
EOF
  cat > "$ENGINE_DIRECTIVES/commands/CMD_C.md" <<'EOF'
# CMD_C
Leaf command.
EOF

  # File references CMD_A
  local test_file="$TMP_DIR/test_input.md"
  cat > "$test_file" <<'EOF'
# Test
Execute §CMD_A.
EOF

  source "$FAKE_HOME/.claude/scripts/lib.sh"

  # At depth 2: file→CMD_A (depth 1), CMD_A→CMD_B (depth 2), CMD_B→CMD_C would be depth 3 (stopped)
  local output_d2
  output_d2=$(resolve_refs "$test_file" 2 '[]')
  assert_contains "CMD_A.md" "$output_d2" "depth-2: finds CMD_A"
  assert_contains "CMD_B.md" "$output_d2" "depth-2: finds CMD_B (via CMD_A)"
  assert_not_contains "CMD_C.md" "$output_d2" "depth-2: does NOT find CMD_C (depth exceeded)"

  # At depth 1: file→CMD_A only
  local output_d1
  output_d1=$(resolve_refs "$test_file" 1 '[]')
  assert_contains "CMD_A.md" "$output_d1" "depth-1: finds CMD_A"
  assert_not_contains "CMD_B.md" "$output_d1" "depth-1: does NOT find CMD_B"
}

test_resolve_refs_dedup_against_already_loaded() {
  # Case 4: Should dedup against already-loaded files
  cat > "$ENGINE_DIRECTIVES/commands/CMD_FOO.md" <<'EOF'
# CMD_FOO
EOF

  local test_file="$TMP_DIR/test_input.md"
  cat > "$test_file" <<'EOF'
# Test
Execute §CMD_FOO.
EOF

  local normalized_path
  normalized_path=$(normalize_preload_path "$ENGINE_DIRECTIVES/commands/CMD_FOO.md")

  source "$FAKE_HOME/.claude/scripts/lib.sh"
  local output
  output=$(resolve_refs "$test_file" 2 "[\"$normalized_path\"]")

  assert_empty "$output" "deduplicates against already-loaded files"
}

test_resolve_refs_skips_skill_md_cmd_refs() {
  # Case 5: Should skip SKILL.md files for CMD refs
  cat > "$ENGINE_DIRECTIVES/commands/CMD_FOO.md" <<'EOF'
# CMD_FOO
EOF

  local test_file="$TMP_DIR/SKILL.md"
  cat > "$test_file" <<'EOF'
# My Skill
Execute §CMD_FOO in phase 0.
EOF

  source "$FAKE_HOME/.claude/scripts/lib.sh"
  local output
  output=$(resolve_refs "$test_file" 2 '[]')

  assert_empty "$output" "SKILL.md CMD refs are excluded"
}

test_resolve_refs_finds_fmt_references() {
  # Case 6: Should find §FMT_ references
  cat > "$ENGINE_DIRECTIVES/formats/FMT_LIGHT_LIST.md" <<'EOF'
# FMT_LIGHT_LIST
Format definition.
EOF

  local test_file="$TMP_DIR/test_input.md"
  cat > "$test_file" <<'EOF'
# Test
Use §FMT_LIGHT_LIST formatting.
EOF

  source "$FAKE_HOME/.claude/scripts/lib.sh"
  local output
  output=$(resolve_refs "$test_file" 2 '[]')

  assert_contains "FMT_LIGHT_LIST.md" "$output" "finds FMT_LIGHT_LIST reference"
}

test_resolve_refs_walk_up_local_override() {
  # Case 7: Should resolve via walk-up (local override)
  # Create a project-local commands dir and an engine-level file
  local local_dir="$TMP_DIR/project/sub/.directives/commands"
  mkdir -p "$local_dir"
  cat > "$local_dir/CMD_FOO.md" <<'EOF'
# CMD_FOO (local override)
EOF
  cat > "$ENGINE_DIRECTIVES/commands/CMD_FOO.md" <<'EOF'
# CMD_FOO (engine)
EOF

  # File lives in the sub directory
  local test_file="$TMP_DIR/project/sub/test_input.md"
  mkdir -p "$(dirname "$test_file")"
  cat > "$test_file" <<'EOF'
# Test
Execute §CMD_FOO.
EOF

  source "$FAKE_HOME/.claude/scripts/lib.sh"
  local output
  output=$(resolve_refs "$test_file" 2 '[]')

  # Should resolve to local version, not engine version
  assert_contains "project/sub/.directives/commands/CMD_FOO.md" "$output" "resolves to local override"
  # Should NOT contain engine path
  local engine_norm
  engine_norm=$(normalize_preload_path "$ENGINE_DIRECTIVES/commands/CMD_FOO.md")
  assert_not_contains "$engine_norm" "$output" "does not resolve to engine version"
}

test_resolve_refs_no_references() {
  # Case 8: Should handle files with no references
  local test_file="$TMP_DIR/test_input.md"
  cat > "$test_file" <<'EOF'
# Test File
No special references here. Just plain text.
EOF

  source "$FAKE_HOME/.claude/scripts/lib.sh"
  local output
  output=$(resolve_refs "$test_file" 2 '[]')

  assert_empty "$output" "empty output for file with no refs"
}

test_resolve_refs_only_section_sign_not_pilcrow() {
  # Case 9: Should only match § (section sign), not ¶ (pilcrow)
  cat > "$ENGINE_DIRECTIVES/commands/CMD_FOO.md" <<'EOF'
# CMD_FOO
EOF
  cat > "$ENGINE_DIRECTIVES/commands/CMD_BAR.md" <<'EOF'
# CMD_BAR
EOF

  local test_file="$TMP_DIR/test_input.md"
  cat > "$test_file" <<'EOF'
# Test
Definition: ¶CMD_FOO
Reference: §CMD_BAR
EOF

  source "$FAKE_HOME/.claude/scripts/lib.sh"
  local output
  output=$(resolve_refs "$test_file" 2 '[]')

  assert_not_contains "CMD_FOO.md" "$output" "ignores pilcrow definition ¶CMD_FOO"
  assert_contains "CMD_BAR.md" "$output" "finds section sign reference §CMD_BAR"
}

test_resolve_refs_skill_md_allows_fmt() {
  # Case 10: SKILL.md CAN trigger FMT preloading
  cat > "$ENGINE_DIRECTIVES/formats/FMT_LIGHT_LIST.md" <<'EOF'
# FMT_LIGHT_LIST
EOF
  cat > "$ENGINE_DIRECTIVES/commands/CMD_FOO.md" <<'EOF'
# CMD_FOO
EOF

  local test_file="$TMP_DIR/SKILL.md"
  cat > "$test_file" <<'EOF'
# My Skill
Use §FMT_LIGHT_LIST and §CMD_FOO.
EOF

  source "$FAKE_HOME/.claude/scripts/lib.sh"
  local output
  output=$(resolve_refs "$test_file" 2 '[]')

  assert_contains "FMT_LIGHT_LIST.md" "$output" "SKILL.md FMT refs are resolved"
  assert_not_contains "CMD_FOO.md" "$output" "SKILL.md CMD refs are excluded"
}

test_resolve_refs_nonexistent_file() {
  # Edge case: nonexistent file returns empty
  source "$FAKE_HOME/.claude/scripts/lib.sh"
  local output
  output=$(resolve_refs "/nonexistent/file.md" 2 '[]')

  assert_empty "$output" "nonexistent file returns empty"
}

test_resolve_refs_zero_depth() {
  # Edge case: depth 0 returns empty
  cat > "$ENGINE_DIRECTIVES/commands/CMD_FOO.md" <<'EOF'
# CMD_FOO
EOF

  local test_file="$TMP_DIR/test_input.md"
  cat > "$test_file" <<'EOF'
Execute §CMD_FOO.
EOF

  source "$FAKE_HOME/.claude/scripts/lib.sh"
  local output
  output=$(resolve_refs "$test_file" 0 '[]')

  assert_empty "$output" "depth 0 returns empty"
}

test_resolve_refs_dedup_within_output() {
  # Edge case: same ref mentioned twice only outputs once
  cat > "$ENGINE_DIRECTIVES/commands/CMD_FOO.md" <<'EOF'
# CMD_FOO
EOF

  local test_file="$TMP_DIR/test_input.md"
  cat > "$test_file" <<'EOF'
# Test
Execute §CMD_FOO first. Then §CMD_FOO again.
EOF

  source "$FAKE_HOME/.claude/scripts/lib.sh"
  local output
  output=$(resolve_refs "$test_file" 2 '[]')

  local count
  count=$(echo "$output" | grep -c "CMD_FOO.md" || true)
  assert_eq "1" "$count" "same ref mentioned twice only outputs once"
}

test_resolve_refs_inv_prefix() {
  # Should find §INV_ references
  cat > "$ENGINE_DIRECTIVES/invariants/INV_TEST_RULE.md" <<'EOF'
# INV_TEST_RULE
EOF

  local test_file="$TMP_DIR/test_input.md"
  cat > "$test_file" <<'EOF'
# Test
See §INV_TEST_RULE for the rule.
EOF

  source "$FAKE_HOME/.claude/scripts/lib.sh"
  local output
  output=$(resolve_refs "$test_file" 2 '[]')

  assert_contains "INV_TEST_RULE.md" "$output" "finds INV_ references"
}

test_resolve_refs_skips_code_fence_content() {
  # Code fence content should not trigger preloading
  cat > "$ENGINE_DIRECTIVES/commands/CMD_FOO.md" <<'EOF'
# CMD_FOO
EOF
  cat > "$ENGINE_DIRECTIVES/commands/CMD_BAR.md" <<'EOF'
# CMD_BAR
EOF

  local test_file="$TMP_DIR/test_input.md"
  cat > "$test_file" <<'OUTER'
# Test File

Execute §CMD_BAR in the real text.

```json
{"proof": ["§CMD_FOO"]}
```

Done.
OUTER

  source "$FAKE_HOME/.claude/scripts/lib.sh"
  local output
  output=$(resolve_refs "$test_file" 2 '[]')

  assert_not_contains "CMD_FOO.md" "$output" "ignores refs inside code fences"
  assert_contains "CMD_BAR.md" "$output" "finds refs outside code fences"
}

test_resolve_refs_unresolvable_ref() {
  # Reference to a file that doesn't exist — should be silently skipped
  local test_file="$TMP_DIR/test_input.md"
  cat > "$test_file" <<'EOF'
# Test
Execute §CMD_NONEXISTENT.
EOF

  source "$FAKE_HOME/.claude/scripts/lib.sh"
  local output
  output=$(resolve_refs "$test_file" 2 '[]')

  assert_empty "$output" "unresolvable reference silently skipped"
}

# --- Run all tests ---
run_test test_resolve_refs_finds_bare_cmd_references
run_test test_resolve_refs_ignores_backtick_escaped
run_test test_resolve_refs_respects_depth_limit
run_test test_resolve_refs_dedup_against_already_loaded
run_test test_resolve_refs_skips_skill_md_cmd_refs
run_test test_resolve_refs_finds_fmt_references
run_test test_resolve_refs_walk_up_local_override
run_test test_resolve_refs_no_references
run_test test_resolve_refs_only_section_sign_not_pilcrow
run_test test_resolve_refs_skill_md_allows_fmt
run_test test_resolve_refs_nonexistent_file
run_test test_resolve_refs_zero_depth
run_test test_resolve_refs_dedup_within_output
run_test test_resolve_refs_inv_prefix
run_test test_resolve_refs_skips_code_fence_content
run_test test_resolve_refs_unresolvable_ref
exit_with_results
