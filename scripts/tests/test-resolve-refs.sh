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

test_resolve_refs_resolves_skill_md_cmd_refs() {
  # Case 5: SKILL.md CMD refs ARE now resolved (exclusion removed)
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

  assert_contains "CMD_FOO.md" "$output" "SKILL.md CMD refs are resolved"
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

test_resolve_refs_skill_md_allows_all_refs() {
  # Case 10: SKILL.md resolves both FMT and CMD refs
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
  assert_contains "CMD_FOO.md" "$output" "SKILL.md CMD refs are resolved"
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

# --- Integration Tests: Hook Wiring ---
# These tests verify that _claim_and_preload() in overflow-v2.sh and the
# templates hook correctly invoke resolve_refs() and queue results into
# pendingPreloads in .state.json.

# Capture real hook paths before HOME gets swapped
_REAL_OVERFLOW_HOOK="$(cd "$(dirname "$0")/../../hooks" && pwd)/pre-tool-use-overflow-v2.sh"
_REAL_TEMPLATES_HOOK="$(cd "$(dirname "$0")/../../hooks" && pwd)/post-tool-use-templates.sh"

# Extract a bash function from a script file without executing the script.
# Uses awk to find the function definition and track brace depth.
_extract_function() {
  local file="$1" func_name="$2"
  awk -v name="$func_name" '
    $0 ~ "^" name "\\(\\) \\{" { found=1; depth=0 }
    found {
      for (i=1; i<=length($0); i++) {
        c = substr($0, i, 1)
        if (c == "{") depth++
        if (c == "}") depth--
      }
      print
      if (found && depth == 0) { exit }
    }
  ' "$file"
}

# Integration setup: extends base setup with .state.json and hook functions.
integration_setup() {
  setup

  # Source lib.sh for resolve_refs, safe_json_write, normalize_preload_path
  source "$FAKE_HOME/.claude/scripts/lib.sh"

  # Extract _claim_and_preload from the real overflow hook
  eval "$(_extract_function "$_REAL_OVERFLOW_HOOK" "_claim_and_preload")"

  # Create a session directory with .state.json
  TEST_SESSION="$TMP_DIR/sessions/test_session"
  mkdir -p "$TEST_SESSION"
  STATE_FILE="$TEST_SESSION/.state.json"
}

# Helper: create a .state.json with given preloadedFiles and pendingPreloads
_write_state() {
  local preloaded="${1:-[]}" pending="${2:-[]}"
  cat > "$STATE_FILE" <<STATEOF
{
  "lifecycle": "active",
  "skill": "test",
  "currentPhase": "0: Setup",
  "preloadedFiles": $preloaded,
  "pendingPreloads": $pending
}
STATEOF
}

test_integration_claim_and_preload_queues_refs() {
  # 3.A.1/1: Preloading CMD_A (which refs §CMD_B) should queue CMD_B into pendingPreloads
  integration_setup

  cat > "$ENGINE_DIRECTIVES/commands/CMD_A.md" <<'EOF'
# CMD_A
Execute §CMD_B after setup.
EOF
  cat > "$ENGINE_DIRECTIVES/commands/CMD_B.md" <<'EOF'
# CMD_B
A dependency command.
EOF

  local cmd_a_path
  cmd_a_path=$(normalize_preload_path "$ENGINE_DIRECTIVES/commands/CMD_A.md")
  _write_state '[]' '[]'

  _claim_and_preload "$STATE_FILE" <<< "$cmd_a_path"

  # CMD_A should be in preloadedFiles
  local preloaded
  preloaded=$(jq -r '.preloadedFiles[]' "$STATE_FILE" 2>/dev/null | tr '\n' ' ')
  assert_contains "CMD_A.md" "$preloaded" "CMD_A is in preloadedFiles"

  # CMD_B should be in pendingPreloads (queued by resolve_refs)
  local pending
  pending=$(jq -r '.pendingPreloads[]' "$STATE_FILE" 2>/dev/null | tr '\n' ' ')
  assert_contains "CMD_B.md" "$pending" "CMD_B queued in pendingPreloads"

  teardown
}

test_integration_claim_dedup_against_preloaded() {
  # 3.A.1/2: If CMD_B is already in preloadedFiles, resolve_refs should NOT re-queue it
  integration_setup

  cat > "$ENGINE_DIRECTIVES/commands/CMD_A.md" <<'EOF'
# CMD_A
Execute §CMD_B after setup.
EOF
  cat > "$ENGINE_DIRECTIVES/commands/CMD_B.md" <<'EOF'
# CMD_B
Already loaded.
EOF

  local cmd_a_path cmd_b_path
  cmd_a_path=$(normalize_preload_path "$ENGINE_DIRECTIVES/commands/CMD_A.md")
  cmd_b_path=$(normalize_preload_path "$ENGINE_DIRECTIVES/commands/CMD_B.md")

  # Pre-populate preloadedFiles with CMD_B
  _write_state "[\"$cmd_b_path\"]" '[]'

  _claim_and_preload "$STATE_FILE" <<< "$cmd_a_path"

  # pendingPreloads should be empty — CMD_B is already loaded
  local pending_count
  pending_count=$(jq '.pendingPreloads | length' "$STATE_FILE" 2>/dev/null)
  assert_eq "0" "$pending_count" "no refs queued when already preloaded"

  teardown
}

test_integration_claim_ignores_code_fence_refs() {
  # 3.A.1/3: Refs inside code fences should NOT be queued
  integration_setup

  # Create CMD files that would be burst-loaded if code fences weren't filtered
  for name in CMD_STEP1 CMD_STEP2 CMD_STEP3 CMD_STEP4 CMD_STEP5; do
    cat > "$ENGINE_DIRECTIVES/commands/${name}.md" <<EOF
# $name
EOF
  done
  cat > "$ENGINE_DIRECTIVES/commands/CMD_BARE_REF.md" <<'EOF'
# CMD_BARE_REF
A real dependency.
EOF

  # CMD_PIPELINE has 5 refs inside a code fence and 1 bare ref outside
  cat > "$ENGINE_DIRECTIVES/commands/CMD_PIPELINE.md" <<'CMDEOF'
# CMD_PIPELINE
Execute §CMD_BARE_REF first.

```json
{
  "steps": ["§CMD_STEP1", "§CMD_STEP2", "§CMD_STEP3", "§CMD_STEP4", "§CMD_STEP5"]
}
```
CMDEOF

  local pipeline_path
  pipeline_path=$(normalize_preload_path "$ENGINE_DIRECTIVES/commands/CMD_PIPELINE.md")
  _write_state '[]' '[]'

  _claim_and_preload "$STATE_FILE" <<< "$pipeline_path"

  local pending
  pending=$(jq -r '.pendingPreloads[]' "$STATE_FILE" 2>/dev/null | tr '\n' ' ')

  # Only CMD_BARE_REF should be queued, not the 5 code-fence refs
  assert_contains "CMD_BARE_REF.md" "$pending" "bare ref outside code fence is queued"
  assert_not_contains "CMD_STEP1.md" "$pending" "code fence ref STEP1 not queued"
  assert_not_contains "CMD_STEP2.md" "$pending" "code fence ref STEP2 not queued"
  assert_not_contains "CMD_STEP5.md" "$pending" "code fence ref STEP5 not queued"

  teardown
}

test_integration_claim_depth2_chain() {
  # 3.A.1/4: CMD_A → CMD_B → CMD_C should queue both B and C
  integration_setup

  cat > "$ENGINE_DIRECTIVES/commands/CMD_A.md" <<'EOF'
# CMD_A
Execute §CMD_B.
EOF
  cat > "$ENGINE_DIRECTIVES/commands/CMD_B.md" <<'EOF'
# CMD_B
Then execute §CMD_C.
EOF
  cat > "$ENGINE_DIRECTIVES/commands/CMD_C.md" <<'EOF'
# CMD_C
Leaf command.
EOF

  local cmd_a_path
  cmd_a_path=$(normalize_preload_path "$ENGINE_DIRECTIVES/commands/CMD_A.md")
  _write_state '[]' '[]'

  _claim_and_preload "$STATE_FILE" <<< "$cmd_a_path"

  local pending
  pending=$(jq -r '.pendingPreloads[]' "$STATE_FILE" 2>/dev/null | tr '\n' ' ')
  assert_contains "CMD_B.md" "$pending" "depth-1 ref CMD_B queued"
  assert_contains "CMD_C.md" "$pending" "depth-2 ref CMD_C queued"

  teardown
}

test_integration_templates_hook_queues_refs() {
  # 3.A.1/5: Templates hook's resolve_refs path queues refs into pendingPreloads
  integration_setup

  cat > "$ENGINE_DIRECTIVES/commands/CMD_TARGET.md" <<'EOF'
# CMD_TARGET
Referenced by a template-delivered file.
EOF

  # Simulate a template-delivered CMD file that references CMD_TARGET
  local delivered_file="$ENGINE_DIRECTIVES/commands/CMD_DELIVERED.md"
  cat > "$delivered_file" <<'EOF'
# CMD_DELIVERED
After delivery, resolve §CMD_TARGET.
EOF

  local delivered_path
  delivered_path=$(normalize_preload_path "$delivered_file")
  # Mark CMD_DELIVERED as already preloaded (templates hook adds to preloadedFiles first)
  _write_state "[\"$delivered_path\"]" '[]'

  # Simulate the templates hook's resolve_refs integration block:
  #   current_loaded = .preloadedFiles
  #   refs = resolve_refs(file, 2, current_loaded)
  #   queue refs into pendingPreloads via jq
  source "$FAKE_HOME/.claude/scripts/lib.sh"
  local current_loaded
  current_loaded=$(jq '.preloadedFiles // []' "$STATE_FILE" 2>/dev/null)
  local abs_path="${delivered_path/#\~/$HOME}"
  local refs
  refs=$(resolve_refs "$abs_path" 2 "$current_loaded") || true

  if [ -n "$refs" ]; then
    local refs_json="[]"
    while IFS= read -r ref_path; do
      [ -n "$ref_path" ] || continue
      refs_json=$(echo "$refs_json" | jq --arg f "$ref_path" '. + [$f]')
    done <<< "$refs"

    jq --argjson refs "$refs_json" '
      (.preloadedFiles // []) as $pf |
      (.pendingPreloads //= []) |
      reduce ($refs[]) as $r (.;
        if ($pf | any(. == $r)) then .
        elif (.pendingPreloads | index($r)) then .
        else .pendingPreloads += [$r]
        end
      )
    ' "$STATE_FILE" | safe_json_write "$STATE_FILE"
  fi

  local pending
  pending=$(jq -r '.pendingPreloads[]' "$STATE_FILE" 2>/dev/null | tr '\n' ' ')
  assert_contains "CMD_TARGET.md" "$pending" "templates hook path queues refs into pendingPreloads"

  teardown
}

test_integration_claim_silent_skip_unresolvable() {
  # 3.A.1/6: Unresolvable refs should be silently skipped, no error
  integration_setup

  cat > "$ENGINE_DIRECTIVES/commands/CMD_WITH_MISSING.md" <<'EOF'
# CMD_WITH_MISSING
Depends on §CMD_DOES_NOT_EXIST which has no file.
EOF

  local cmd_path
  cmd_path=$(normalize_preload_path "$ENGINE_DIRECTIVES/commands/CMD_WITH_MISSING.md")
  _write_state '[]' '[]'

  # Should not fail
  _claim_and_preload "$STATE_FILE" <<< "$cmd_path"
  local exit_code=$?

  assert_eq "0" "$exit_code" "no error on unresolvable ref"

  # pendingPreloads should be empty (nothing to resolve)
  local pending_count
  pending_count=$(jq '.pendingPreloads | length' "$STATE_FILE" 2>/dev/null)
  assert_eq "0" "$pending_count" "no refs queued for unresolvable"

  teardown
}

# --- SKILL.md Pipeline Integration Tests ---
# These tests verify that the templates hook (post-tool-use-templates.sh) scans
# SKILL.md bare §CMD_* refs and queues discovered files into pendingPreloads.

# Helper: set up a fake skill directory with SKILL.md and mock the templates hook env
_setup_skill_fixture() {
  local skill_name="${1:-fake-skill}"
  local skill_dir="$FAKE_HOME/.claude/skills/$skill_name"
  mkdir -p "$skill_dir"
  FIXTURE_SKILL_DIR="$skill_dir"
  FIXTURE_SKILL_NAME="$skill_name"
}

# Helper: simulate the templates hook's SKILL.md scanning block (the fix under test)
# This mirrors the fixed code in post-tool-use-templates.sh lines 77-116
_simulate_skill_md_scanning() {
  local state_file="$1"
  local skill_name="$2"
  local preload_paths="$3"

  local all_new_refs=""
  local current_loaded
  current_loaded=$(jq '.preloadedFiles // []' "$state_file" 2>/dev/null || echo '[]')

  # Build scan list: Phase 0 CMDs + SKILL.md itself (the fix)
  local scan_paths="$preload_paths"
  local skill_md_path="$FAKE_HOME/.claude/skills/$skill_name/SKILL.md"
  if [ -f "$skill_md_path" ]; then
    local skill_md_norm
    skill_md_norm=$(normalize_preload_path "$skill_md_path")
    scan_paths="${scan_paths}
${skill_md_norm}"
  fi

  while IFS= read -r norm_path; do
    [ -n "$norm_path" ] || continue
    local abs_path="${norm_path/#\~/$HOME}"
    [ -f "$abs_path" ] || continue
    local refs
    refs=$(resolve_refs "$abs_path" 2 "$current_loaded") || true
    if [ -n "$refs" ]; then
      all_new_refs="${all_new_refs}${all_new_refs:+
}${refs}"
      while IFS= read -r rpath; do
        [ -n "$rpath" ] || continue
        current_loaded=$(echo "$current_loaded" | jq --arg p "$rpath" '. + [$p]')
      done <<< "$refs"
    fi
  done <<< "$scan_paths"

  if [ -n "$all_new_refs" ]; then
    local refs_json="[]"
    while IFS= read -r ref_path; do
      [ -n "$ref_path" ] || continue
      refs_json=$(echo "$refs_json" | jq --arg f "$ref_path" '. + [$f]')
    done <<< "$all_new_refs"

    jq --argjson refs "$refs_json" '
      (.preloadedFiles // []) as $pf |
      (.pendingPreloads //= []) |
      reduce ($refs[]) as $r (.;
        if ($pf | any(. == $r)) then .
        elif (.pendingPreloads | index($r)) then .
        else .pendingPreloads += [$r]
        end
      )
    ' "$state_file" | safe_json_write "$state_file"
  fi
}

test_integration_templates_hook_scans_skill_md_refs() {
  # 1.4/1: SKILL.md bare §CMD_* refs should be queued into pendingPreloads
  integration_setup
  _setup_skill_fixture "test-skill"

  # Create CMD file that SKILL.md references
  cat > "$ENGINE_DIRECTIVES/commands/CMD_EXECUTE_SKILL_PHASES.md" <<'EOF'
# CMD_EXECUTE_SKILL_PHASES
Boot sector command.
EOF

  # Create fixture SKILL.md with a bare §CMD_ ref
  cat > "$FIXTURE_SKILL_DIR/SKILL.md" <<'EOF'
# Test Skill
Execute §CMD_EXECUTE_SKILL_PHASES.
EOF

  local skill_md_norm
  skill_md_norm=$(normalize_preload_path "$FIXTURE_SKILL_DIR/SKILL.md")
  # SKILL.md already in preloadedFiles (delivered by UserPromptSubmit)
  _write_state "[\"$skill_md_norm\"]" '[]'

  # No Phase 0 CMDs (empty preload paths)
  _simulate_skill_md_scanning "$STATE_FILE" "$FIXTURE_SKILL_NAME" ""

  local pending
  pending=$(jq -r '.pendingPreloads[]' "$STATE_FILE" 2>/dev/null | tr '\n' ' ')
  assert_contains "CMD_EXECUTE_SKILL_PHASES.md" "$pending" "SKILL.md bare ref queued in pendingPreloads"

  teardown
}

test_integration_skill_md_not_requeued_in_pending() {
  # 1.4/2: SKILL.md itself should NOT appear in pendingPreloads
  integration_setup
  _setup_skill_fixture "test-skill"

  cat > "$ENGINE_DIRECTIVES/commands/CMD_FOO.md" <<'EOF'
# CMD_FOO
EOF

  cat > "$FIXTURE_SKILL_DIR/SKILL.md" <<'EOF'
# Test Skill
Execute §CMD_FOO.
EOF

  local skill_md_norm
  skill_md_norm=$(normalize_preload_path "$FIXTURE_SKILL_DIR/SKILL.md")
  _write_state "[\"$skill_md_norm\"]" '[]'

  _simulate_skill_md_scanning "$STATE_FILE" "$FIXTURE_SKILL_NAME" ""

  local pending
  pending=$(jq -r '.pendingPreloads[]' "$STATE_FILE" 2>/dev/null | tr '\n' ' ')
  assert_contains "CMD_FOO.md" "$pending" "CMD_FOO ref is queued"
  assert_not_contains "SKILL.md" "$pending" "SKILL.md itself NOT in pendingPreloads"

  teardown
}

test_integration_resolve_refs_no_debug_output() {
  # 1.4/3: resolve_refs stdout should contain only file paths, no debug lines
  integration_setup

  cat > "$ENGINE_DIRECTIVES/commands/CMD_FOO.md" <<'EOF'
# CMD_FOO
Execute §CMD_BAR.
EOF
  cat > "$ENGINE_DIRECTIVES/commands/CMD_BAR.md" <<'EOF'
# CMD_BAR
EOF

  local test_file="$TMP_DIR/test_input.md"
  cat > "$test_file" <<'EOF'
# Test
Execute §CMD_FOO.
EOF

  source "$FAKE_HOME/.claude/scripts/lib.sh"
  local output
  output=$(resolve_refs "$test_file" 2 '[]')

  # Check every line is a valid path (contains / or ~)
  local bad_lines=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *"/"*|"~"*) ;; # valid path
      *) bad_lines="${bad_lines}${line}\n" ;;
    esac
  done <<< "$output"

  assert_empty "$bad_lines" "no debug output in resolve_refs stdout"

  # Explicitly check for known debug patterns
  assert_not_contains "folder=" "$output" "no folder= debug output"
  assert_not_contains "normalized=" "$output" "no normalized= debug output"
  assert_not_contains "prefix=" "$output" "no prefix= debug output"

  teardown
}

test_integration_skill_md_backtick_refs_not_queued() {
  # 1.4/4: SKILL.md with only backtick-escaped refs should NOT queue anything
  integration_setup
  _setup_skill_fixture "test-skill"

  cat > "$ENGINE_DIRECTIVES/commands/CMD_FOO.md" <<'EOF'
# CMD_FOO
EOF

  # All refs are backtick-escaped
  printf '# Test Skill\nSee `§CMD_FOO` for reference.\n' > "$FIXTURE_SKILL_DIR/SKILL.md"

  local skill_md_norm
  skill_md_norm=$(normalize_preload_path "$FIXTURE_SKILL_DIR/SKILL.md")
  _write_state "[\"$skill_md_norm\"]" '[]'

  _simulate_skill_md_scanning "$STATE_FILE" "$FIXTURE_SKILL_NAME" ""

  local pending_count
  pending_count=$(jq '.pendingPreloads | length' "$STATE_FILE" 2>/dev/null)
  assert_eq "0" "$pending_count" "backtick-escaped refs in SKILL.md not queued"

  teardown
}

test_integration_full_pipeline_cmds_and_skill_refs() {
  # 1.4/5: Phase 0 CMDs AND SKILL.md refs both resolved in single pipeline run
  integration_setup
  _setup_skill_fixture "test-skill"

  # Phase 0 CMD (delivered directly by extract_skill_preloads)
  cat > "$ENGINE_DIRECTIVES/commands/CMD_SETUP.md" <<'EOF'
# CMD_SETUP
Phase 0 command.
EOF

  # CMD referenced only in SKILL.md body (not in Phase 0)
  cat > "$ENGINE_DIRECTIVES/commands/CMD_EXECUTE_SKILL_PHASES.md" <<'EOF'
# CMD_EXECUTE_SKILL_PHASES
Boot sector.
EOF

  cat > "$FIXTURE_SKILL_DIR/SKILL.md" <<'EOF'
# Test Skill
Execute §CMD_EXECUTE_SKILL_PHASES.
EOF

  local cmd_setup_norm skill_md_norm
  cmd_setup_norm=$(normalize_preload_path "$ENGINE_DIRECTIVES/commands/CMD_SETUP.md")
  skill_md_norm=$(normalize_preload_path "$FIXTURE_SKILL_DIR/SKILL.md")
  # Both SKILL.md and CMD_SETUP already in preloadedFiles
  _write_state "[\"$skill_md_norm\", \"$cmd_setup_norm\"]" '[]'

  # CMD_SETUP is in the preload paths (Phase 0 CMDs)
  _simulate_skill_md_scanning "$STATE_FILE" "$FIXTURE_SKILL_NAME" "$cmd_setup_norm"

  local pending
  pending=$(jq -r '.pendingPreloads[]' "$STATE_FILE" 2>/dev/null | tr '\n' ' ')
  assert_contains "CMD_EXECUTE_SKILL_PHASES.md" "$pending" "SKILL.md body ref discovered"
  assert_not_contains "CMD_SETUP.md" "$pending" "Phase 0 CMD not re-queued (already preloaded)"

  teardown
}

test_integration_templates_hook_valid_json_output() {
  # 1.4/6: The templates hook produces valid JSON additionalContext output
  integration_setup
  _setup_skill_fixture "test-skill"

  cat > "$ENGINE_DIRECTIVES/commands/CMD_FOO.md" <<'EOF'
# CMD_FOO
A test command.
EOF

  cat > "$FIXTURE_SKILL_DIR/SKILL.md" <<'EOF'
# Test Skill
Execute §CMD_FOO.
EOF

  # Simulate building additionalContext (mirrors hook lines 41-51)
  local cmd_foo_norm
  cmd_foo_norm=$(normalize_preload_path "$ENGINE_DIRECTIVES/commands/CMD_FOO.md")
  local abs_path="${cmd_foo_norm/#\~/$HOME}"
  local content
  content=$(cat "$abs_path" 2>/dev/null || true)
  local additional_context="[Preloaded: $cmd_foo_norm]\n$content"

  # Build JSON output like the hook does (lines 122-129)
  local json_output
  json_output=$(cat <<HOOKEOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $(printf '%s' "$additional_context" | jq -Rs .)
  }
}
HOOKEOF
)

  # Validate it's proper JSON
  echo "$json_output" | jq empty 2>/dev/null
  local jq_exit=$?
  assert_eq "0" "$jq_exit" "hook output is valid JSON"

  # Validate structure
  local event_name
  event_name=$(echo "$json_output" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)
  assert_eq "PostToolUse" "$event_name" "hookEventName is PostToolUse"

  local has_context
  has_context=$(echo "$json_output" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  assert_not_empty "$has_context" "additionalContext is present"

  teardown
}

# --- Run all tests ---
run_test test_resolve_refs_finds_bare_cmd_references
run_test test_resolve_refs_ignores_backtick_escaped
run_test test_resolve_refs_respects_depth_limit
run_test test_resolve_refs_dedup_against_already_loaded
run_test test_resolve_refs_resolves_skill_md_cmd_refs
run_test test_resolve_refs_finds_fmt_references
run_test test_resolve_refs_walk_up_local_override
run_test test_resolve_refs_no_references
run_test test_resolve_refs_only_section_sign_not_pilcrow
run_test test_resolve_refs_skill_md_allows_all_refs
run_test test_resolve_refs_nonexistent_file
run_test test_resolve_refs_zero_depth
run_test test_resolve_refs_dedup_within_output
run_test test_resolve_refs_inv_prefix
run_test test_resolve_refs_skips_code_fence_content
run_test test_resolve_refs_unresolvable_ref
# Integration tests
run_test test_integration_claim_and_preload_queues_refs
run_test test_integration_claim_dedup_against_preloaded
run_test test_integration_claim_ignores_code_fence_refs
run_test test_integration_claim_depth2_chain
run_test test_integration_templates_hook_queues_refs
run_test test_integration_claim_silent_skip_unresolvable
# SKILL.md pipeline integration tests (templates hook scanning)
run_test test_integration_templates_hook_scans_skill_md_refs
run_test test_integration_skill_md_not_requeued_in_pending
run_test test_integration_resolve_refs_no_debug_output
run_test test_integration_skill_md_backtick_refs_not_queued
run_test test_integration_full_pipeline_cmds_and_skill_refs
run_test test_integration_templates_hook_valid_json_output
exit_with_results
