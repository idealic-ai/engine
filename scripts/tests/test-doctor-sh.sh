#!/bin/bash
# test-doctor-sh.sh — Tests for doctor.sh (unified engine diagnostic tool)
#
# Tests all 6 check categories: installation, skills, CMD files, directives, sessions, sigils.
# Uses sandbox isolation per §INV_TEST_SANDBOX_ISOLATION.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOCTOR_SH="$SCRIPT_DIR/doctor.sh"

# ============================================================
# Sandbox Setup
# ============================================================

setup() {
  TMP_DIR=$(mktemp -d)
  setup_fake_home "$TMP_DIR"
  disable_fleet_tmux

  # Create minimal engine structure
  ENGINE_DIR="$FAKE_HOME/.claude/engine"
  SKILLS_DIR="$ENGINE_DIR/skills"
  CMD_DIR="$ENGINE_DIR/.directives/commands"
  DIRECTIVES_DIR="$ENGINE_DIR/.directives"

  mkdir -p "$ENGINE_DIR/scripts"
  mkdir -p "$ENGINE_DIR/tools/json-schema-validate/schemas"
  mkdir -p "$SKILLS_DIR"
  mkdir -p "$CMD_DIR"
  mkdir -p "$DIRECTIVES_DIR/templates"
  mkdir -p "$FAKE_HOME/.claude/scripts"
  mkdir -p "$FAKE_HOME/.claude/hooks"
  mkdir -p "$FAKE_HOME/.claude/tools"

  # Symlink lib.sh (read-only, safe to symlink)
  ln -sf "$SCRIPT_DIR/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"

  # Create core directive files
  cat > "$DIRECTIVES_DIR/COMMANDS.md" <<'EOF'
# Commands
### ¶CMD_APPEND_LOG
### ¶CMD_PARSE_PARAMETERS
EOF

  cat > "$DIRECTIVES_DIR/INVARIANTS.md" <<'EOF'
# Invariants
*   **¶INV_CONCISE_CHAT**: Rule.
*   **¶INV_SIGIL_SEMANTICS**: Rule.
EOF

  cat > "$DIRECTIVES_DIR/SIGILS.md" <<'EOF'
# Sigils
EOF

  # Create engine command on PATH
  mkdir -p "$FAKE_HOME/bin"
  cat > "$FAKE_HOME/bin/engine" <<'STUB'
#!/bin/bash
echo "engine stub"
STUB
  chmod +x "$FAKE_HOME/bin/engine"
  export PATH="$FAKE_HOME/bin:$PATH"

  # Work in TMP_DIR
  cd "$TMP_DIR"
}

teardown() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}

# ============================================================
# Helper: Create a minimal valid skill
# ============================================================

create_valid_skill() {
  local name="$1"
  local tier="${2:-utility}"
  local skill_dir="$SKILLS_DIR/$name"
  mkdir -p "$skill_dir"

  cat > "$skill_dir/SKILL.md" <<SKILL
---
name: $name
description: "Test skill"
version: 1.0
tier: $tier
---

Test skill content.
SKILL
}

create_protocol_skill() {
  local name="$1"
  local skill_dir="$SKILLS_DIR/$name"
  mkdir -p "$skill_dir/assets" "$skill_dir/modes"

  cat > "$skill_dir/SKILL.md" <<'SKILL'
---
name: test-proto
description: "Test protocol skill"
version: 1.0
tier: protocol
---

Execute `§CMD_EXECUTE_SKILL_PHASES`.

```json
{
  "taskType": "TEST",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_PARSE_PARAMETERS"],
      "commands": [],
      "proof": []},
    {"label": "1", "name": "Synthesis",
      "steps": ["§CMD_RUN_SYNTHESIS_PIPELINE", "§CMD_CLOSE_SESSION", "§CMD_GENERATE_DEBRIEF"],
      "commands": [],
      "proof": []}
  ],
  "nextSkills": ["/test-util"],
  "logTemplate": "assets/TEMPLATE_TEST_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_TEST.md"
}
```
SKILL
  # Fix skill name in frontmatter
  sed -i '' "s/name: test-proto/name: $name/" "$skill_dir/SKILL.md"

  # Create template files
  echo "# Log" > "$skill_dir/assets/TEMPLATE_TEST_LOG.md"
  echo "# Debrief" > "$skill_dir/assets/TEMPLATE_TEST.md"

  # Create 4 mode files (3 named + custom)
  for mode in general tdd experimentation custom; do
    cat > "$skill_dir/modes/$mode.md" <<MODE
# $mode Mode
## Role
Test role.
## Goal
Test goal.
## Mindset
Test mindset.
## Approach
Test approach.
MODE
  done
}

# ============================================================
# Helper: Create a CMD file
# ============================================================

create_cmd_file() {
  local name="$1"
  local valid="${2:-true}"

  if [ "$valid" = "true" ]; then
    cat > "$CMD_DIR/CMD_${name}.md" <<CMD
### ¶CMD_${name}
**Definition**: Test command.

## PROOF FOR §CMD_${name}

\`\`\`json
{
  "\$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "done": {
      "type": "boolean",
      "description": "Whether it completed"
    }
  },
  "required": ["done"],
  "additionalProperties": false
}
\`\`\`
CMD
  else
    cat > "$CMD_DIR/CMD_${name}.md" <<CMD
### ¶CMD_${name}
**Definition**: Test command with no proof section.
CMD
  fi
}

# ============================================================
# CATEGORY 1: INSTALLATION
# ============================================================

test_installation_engine_on_path() {
  local output
  output=$("$DOCTOR_SH" -v 2>&1) || true
  assert_contains "IN-01" "$output" "Installation checks run"
  assert_contains "engine command on PATH" "$output" "engine found on PATH"
}

test_installation_jq_available() {
  local output
  output=$("$DOCTOR_SH" -v 2>&1) || true
  assert_contains "jq available" "$output" "jq detected"
}

test_installation_engine_dir_exists() {
  local output
  output=$("$DOCTOR_SH" -v 2>&1) || true
  assert_contains "Engine directory exists" "$output" "Engine dir detected"
}

# ============================================================
# CATEGORY 2: SKILLS
# ============================================================

test_skills_valid_utility_passes() {
  create_valid_skill "test-util"

  local output
  output=$("$DOCTOR_SH" -v 2>&1) || true
  assert_contains "test-util" "$output" "Skill appears in output"
  assert_contains "YAML frontmatter present" "$output" "Frontmatter detected"
}

test_skills_missing_skillmd_fails() {
  mkdir -p "$SKILLS_DIR/broken-skill"
  # No SKILL.md

  local output
  output=$("$DOCTOR_SH" 2>&1) || true
  assert_contains "Missing SKILL.md" "$output" "Missing SKILL.md detected"
}

test_skills_invalid_tier_fails() {
  local skill_dir="$SKILLS_DIR/bad-tier"
  mkdir -p "$skill_dir"
  cat > "$skill_dir/SKILL.md" <<'EOF'
---
name: bad-tier
description: "Bad tier"
version: 1.0
tier: bogus
---
Content.
EOF

  local output
  output=$("$DOCTOR_SH" 2>&1) || true
  assert_contains "Invalid tier" "$output" "Invalid tier detected"
}

test_skills_name_mismatch_fails() {
  local skill_dir="$SKILLS_DIR/actual-name"
  mkdir -p "$skill_dir"
  cat > "$skill_dir/SKILL.md" <<'EOF'
---
name: wrong-name
description: "Name mismatch"
version: 1.0
tier: utility
---
Content.
EOF

  local output
  output=$("$DOCTOR_SH" 2>&1) || true
  assert_contains "Name mismatch" "$output" "Name mismatch detected"
}

# ============================================================
# CATEGORY 3: CMD FILES
# ============================================================

test_cmd_valid_proof_passes() {
  create_cmd_file "TEST_VALID"

  local output
  output=$("$DOCTOR_SH" -v 2>&1) || true
  assert_contains "CMD_TEST_VALID has PROOF FOR section" "$output" "Valid CMD proof detected"
  assert_contains "CMD_TEST_VALID proof schema is valid JSON" "$output" "Valid CMD JSON detected"
}

test_cmd_missing_proof_warns() {
  create_cmd_file "NO_PROOF" "false"

  local output
  output=$("$DOCTOR_SH" 2>&1) || true
  assert_contains "CMD_NO_PROOF missing PROOF FOR section" "$output" "Missing proof section detected"
}

test_cmd_invalid_json_proof_fails() {
  cat > "$CMD_DIR/CMD_BAD_JSON.md" <<'CMD'
### ¶CMD_BAD_JSON
**Definition**: Bad proof JSON.

## PROOF FOR §CMD_BAD_JSON

```json
{ this is not valid json
```
CMD

  local output
  output=$("$DOCTOR_SH" 2>&1) || true
  assert_contains "CMD_BAD_JSON" "$output" "Bad JSON CMD appears in output"
  assert_contains "FAIL" "$output" "Bad JSON produces FAIL"
}

test_cmd_schema_missing_type_fails() {
  cat > "$CMD_DIR/CMD_NO_TYPE.md" <<'CMD'
### ¶CMD_NO_TYPE
**Definition**: Schema without type field.

## PROOF FOR §CMD_NO_TYPE

```json
{
  "properties": {
    "x": {"type": "string"}
  }
}
```
CMD

  local output
  output=$("$DOCTOR_SH" 2>&1) || true
  assert_contains "CMD_NO_TYPE" "$output" "No-type CMD appears in output"
  assert_contains "schema missing" "$output" "Missing type detected"
}

# ============================================================
# CATEGORY 4: DIRECTIVES
# ============================================================

test_directives_core_files_pass() {
  local output
  output=$("$DOCTOR_SH" -v 2>&1) || true
  assert_contains "COMMANDS.md exists" "$output" "COMMANDS.md found"
  assert_contains "INVARIANTS.md exists" "$output" "INVARIANTS.md found"
  assert_contains "SIGILS.md exists" "$output" "SIGILS.md found"
}

test_directives_missing_core_file_fails() {
  rm "$DIRECTIVES_DIR/SIGILS.md"

  local output
  output=$("$DOCTOR_SH" 2>&1) || true
  assert_contains "Missing SIGILS.md" "$output" "Missing SIGILS.md detected"
}

test_directives_commands_subdir_pass() {
  local output
  output=$("$DOCTOR_SH" -v 2>&1) || true
  assert_contains "commands/ subdirectory exists" "$output" "commands/ subdir found"
}

# ============================================================
# CATEGORY 5: SESSIONS
# ============================================================

test_sessions_no_sessions_dir_warns() {
  # No sessions/ directory in TMP_DIR
  local output
  output=$("$DOCTOR_SH" 2>&1) || true
  assert_contains "No sessions/ directory" "$output" "Missing sessions dir warned"
}

test_sessions_valid_state_passes() {
  mkdir -p "$TMP_DIR/sessions/2026_01_01_TEST"
  cat > "$TMP_DIR/sessions/2026_01_01_TEST/.state.json" <<'JSON'
{
  "skill": "implement",
  "currentPhase": "3: Execution",
  "lifecycle": "completed",
  "pid": 12345
}
JSON

  local output
  output=$("$DOCTOR_SH" -v 2>&1) || true
  assert_contains "has skill + currentPhase" "$output" "Valid session detected"
}

test_sessions_invalid_json_fails() {
  mkdir -p "$TMP_DIR/sessions/2026_01_01_BAD"
  echo "not json" > "$TMP_DIR/sessions/2026_01_01_BAD/.state.json"

  local output
  output=$("$DOCTOR_SH" 2>&1) || true
  assert_contains "invalid JSON" "$output" "Invalid JSON detected"
}

test_sessions_stale_active_warns() {
  mkdir -p "$TMP_DIR/sessions/2026_01_01_STALE"
  cat > "$TMP_DIR/sessions/2026_01_01_STALE/.state.json" <<JSON
{
  "skill": "implement",
  "currentPhase": "3: Execution",
  "lifecycle": "active",
  "pid": 999999999
}
JSON

  local output
  output=$("$DOCTOR_SH" 2>&1) || true
  assert_contains "lifecycle=active but PID" "$output" "Stale active session detected"
}

# ============================================================
# CATEGORY 6: SIGIL CROSS-REFERENCE
# ============================================================

test_sigils_valid_refs_pass() {
  # Create a skill that references §CMD_APPEND_LOG (defined in COMMANDS.md)
  create_valid_skill "test-util"
  echo '§CMD_APPEND_LOG is referenced here.' >> "$SKILLS_DIR/test-util/SKILL.md"

  local output
  output=$("$DOCTOR_SH" -v 2>&1) || true
  assert_contains "§CMD_ references resolve" "$output" "Valid CMD refs pass"
}

test_sigils_broken_cmd_ref_fails() {
  create_valid_skill "test-util"
  echo '§CMD_DOES_NOT_EXIST is referenced here.' >> "$SKILLS_DIR/test-util/SKILL.md"

  local output
  output=$("$DOCTOR_SH" 2>&1) || true
  assert_contains "§CMD_ broken" "$output" "Broken CMD ref detected"
  assert_contains "§CMD_DOES_NOT_EXIST" "$output" "Broken ref name shown"
}

test_sigils_broken_inv_ref_fails() {
  create_valid_skill "test-util"
  echo '§INV_NONEXISTENT_INVARIANT is referenced here.' >> "$SKILLS_DIR/test-util/SKILL.md"

  local output
  output=$("$DOCTOR_SH" 2>&1) || true
  assert_contains "§INV_ broken" "$output" "Broken INV ref detected"
  assert_contains "§INV_NONEXISTENT_INVARIANT" "$output" "Broken inv name shown"
}

test_sigils_orphaned_def_warns() {
  # Define ¶CMD_ORPHAN but never reference it with §CMD_ORPHAN
  # Note: avoid "PROOF FOR §CMD_ORPHAN" heading since that self-references
  cat > "$CMD_DIR/CMD_ORPHAN.md" <<'CMD'
### ¶CMD_ORPHAN
Never referenced anywhere.

## Proof Schema

```json
{"type": "object", "properties": {}, "required": []}
```
CMD

  local output
  output=$("$DOCTOR_SH" 2>&1) || true
  assert_contains "orphaned" "$output" "Orphaned definition warned"
  assert_contains "¶CMD_ORPHAN" "$output" "Orphaned name shown"
}

# ============================================================
# AUTO-DETECTION
# ============================================================

test_autodetect_skill_dir() {
  create_valid_skill "test-util"

  local output
  output=$("$DOCTOR_SH" -v "$SKILLS_DIR/test-util" 2>&1) || true
  assert_contains "test-util" "$output" "Auto-detected skill directory"
  assert_contains "YAML frontmatter present" "$output" "Ran skill checks on targeted dir"
}

test_autodetect_cmd_dir() {
  create_cmd_file "AUTO_TEST"

  local output
  output=$("$DOCTOR_SH" -v "$CMD_DIR" 2>&1) || true
  assert_contains "CMD_AUTO_TEST" "$output" "Auto-detected commands directory"
}

test_autodetect_session_dir() {
  mkdir -p "$TMP_DIR/sessions/2026_01_01_AUTO"
  cat > "$TMP_DIR/sessions/2026_01_01_AUTO/.state.json" <<'JSON'
{
  "skill": "implement",
  "currentPhase": "3: Execution",
  "lifecycle": "completed"
}
JSON

  local output
  output=$("$DOCTOR_SH" -v "$TMP_DIR/sessions/2026_01_01_AUTO" 2>&1) || true
  assert_contains "Session:" "$output" "Auto-detected session directory"
  assert_contains ".state.json is valid JSON" "$output" "Ran session checks"
}

# ============================================================
# SUMMARY & EXIT CODE
# ============================================================

test_exit_0_when_no_fails() {
  # Minimal healthy engine — ensure installation checks pass too
  mkdir -p "$FAKE_HOME/.claude/skills"
  mkdir -p "$FAKE_HOME/.claude/.directives"

  "$DOCTOR_SH" > /dev/null 2>&1
  local exit_code=$?
  assert_eq "0" "$exit_code" "Exit 0 when no FAILs"
}

test_exit_1_when_fails() {
  # Create a skill with invalid tier to force a FAIL
  local skill_dir="$SKILLS_DIR/broken"
  mkdir -p "$skill_dir"
  cat > "$skill_dir/SKILL.md" <<'EOF'
---
name: broken
description: "Broken"
version: 1.0
tier: invalid
---
Content.
EOF

  "$DOCTOR_SH" > /dev/null 2>&1
  local exit_code=$?
  assert_eq "1" "$exit_code" "Exit 1 when FAILs present"
}

test_summary_line_present() {
  local output
  output=$("$DOCTOR_SH" 2>&1) || true
  assert_contains "Summary:" "$output" "Summary line present"
  assert_contains "PASS" "$output" "PASS count in summary"
  assert_contains "WARN" "$output" "WARN count in summary"
  assert_contains "FAIL" "$output" "FAIL count in summary"
}

# ============================================================
# VERBOSE FLAG
# ============================================================

test_verbose_shows_pass() {
  create_cmd_file "VERBOSE_TEST"

  local output_quiet output_verbose
  output_quiet=$("$DOCTOR_SH" 2>&1) || true
  output_verbose=$("$DOCTOR_SH" -v 2>&1) || true

  # Verbose should show PASS lines; quiet should not (for passing checks)
  assert_contains "PASS" "$output_verbose" "Verbose shows PASS"
}

# ============================================================
# Run Tests
# ============================================================

echo "=== test-doctor-sh.sh ==="

# Installation
run_test test_installation_engine_on_path
run_test test_installation_jq_available
run_test test_installation_engine_dir_exists

# Skills
run_test test_skills_valid_utility_passes
run_test test_skills_missing_skillmd_fails
run_test test_skills_invalid_tier_fails
run_test test_skills_name_mismatch_fails

# CMD files
run_test test_cmd_valid_proof_passes
run_test test_cmd_missing_proof_warns
run_test test_cmd_invalid_json_proof_fails
run_test test_cmd_schema_missing_type_fails

# Directives
run_test test_directives_core_files_pass
run_test test_directives_missing_core_file_fails
run_test test_directives_commands_subdir_pass

# Sessions
run_test test_sessions_no_sessions_dir_warns
run_test test_sessions_valid_state_passes
run_test test_sessions_invalid_json_fails
run_test test_sessions_stale_active_warns

# Sigil cross-reference
run_test test_sigils_valid_refs_pass
run_test test_sigils_broken_cmd_ref_fails
run_test test_sigils_broken_inv_ref_fails
run_test test_sigils_orphaned_def_warns

# Auto-detection
run_test test_autodetect_skill_dir
run_test test_autodetect_cmd_dir
run_test test_autodetect_session_dir

# Summary & exit code
run_test test_exit_0_when_no_fails
run_test test_exit_1_when_fails
run_test test_summary_line_present

# Verbose flag
run_test test_verbose_shows_pass

exit_with_results
