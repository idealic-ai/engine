#!/bin/bash
# ~/.claude/scripts/doctor.sh — Unified engine diagnostic tool
#
# Validates structural health of the entire workflow engine ecosystem.
# Six check categories: installation, skills, CMD files, directives, sessions, sigil cross-refs.
# Absorbs and replaces skill-doctor.sh.
#
# Usage: doctor.sh [-v|--verbose] [<dir>]
#   No args:  Full ecosystem check (~/.claude/)
#   <dir>:    Auto-detect directory type and run appropriate checks
#   -v:       Show all checks including PASS (default: only WARN/FAIL)
# Exit:  0 = all checks pass, 1 = any FAIL detected

set -euo pipefail

# --- Args ---
VERBOSE=0
TARGET_DIR=""
for arg in "$@"; do
  case "$arg" in
    -v|--verbose) VERBOSE=1 ;;
    -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
    *) TARGET_DIR="$arg" ;;
  esac
done

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Counters ---
PASSES=0
WARNS=0
FAILS=0

# --- Per-section issue buffer (for quiet mode) ---
SECTION_HEADER=""

# --- Output helpers ---
pass() {
  PASSES=$((PASSES + 1))
  if [ "$VERBOSE" -eq 1 ]; then
    printf "  ${GREEN}PASS${NC}  %-7s %s\n" "$1" "$2"
  fi
}
warn() {
  WARNS=$((WARNS + 1))
  if [ "$VERBOSE" -eq 0 ] && [ -n "$SECTION_HEADER" ]; then
    printf "%s\n" "$SECTION_HEADER"
    SECTION_HEADER=""
  fi
  printf "  ${YELLOW}WARN${NC}  %-7s %s\n" "$1" "$2"
}
fail() {
  FAILS=$((FAILS + 1))
  if [ "$VERBOSE" -eq 0 ] && [ -n "$SECTION_HEADER" ]; then
    printf "%s\n" "$SECTION_HEADER"
    SECTION_HEADER=""
  fi
  printf "  ${RED}FAIL${NC}  %-7s %s\n" "$1" "$2"
}

section() {
  SECTION_HEADER=$(printf "${BOLD}=== %s ===${NC}" "$1")
  if [ "$VERBOSE" -eq 1 ]; then printf "%s\n" "$SECTION_HEADER"; SECTION_HEADER=""; fi
}

section_end() {
  if [ "$VERBOSE" -eq 1 ]; then echo; fi
  SECTION_HEADER=""
}

# --- Resolve engine paths ---
ENGINE_DIR="$HOME/.claude/engine"
ENGINE_SKILLS="$ENGINE_DIR/skills"
if [ ! -d "$ENGINE_SKILLS" ]; then
  ENGINE_SKILLS="$HOME/.claude/skills"
fi
CMD_DIR="$ENGINE_DIR/.directives/commands"
DIRECTIVES_DIR="$ENGINE_DIR/.directives"
SCHEMA_FILE="$ENGINE_DIR/tools/json-schema-validate/schemas/skill-manifest.json"
VALIDATE_SH="$ENGINE_DIR/tools/json-schema-validate/validate.sh"

# Temp file for JSON extraction (cleaned up on exit)
TMP_JSON=$(mktemp /tmp/doctor-XXXXXX.json)
trap 'rm -f "$TMP_JSON"' EXIT

# ============================================================
# SHARED HELPERS
# ============================================================

# --- Extract YAML frontmatter field ---
frontmatter_field() {
  local file="$1" field="$2"
  awk '/^---$/{n++; next} n==1{print}' "$file" | (grep "^${field}:" || true) | sed "s/^${field}:[[:space:]]*//" | sed 's/^["'"'"']//' | sed 's/["'"'"']$//'
}

# --- Extract first ```json block from a Markdown file ---
extract_json_block() {
  local file="$1"
  awk '/^```json$/{found=1;next} found && /^```$/{exit} found{print}' "$file" > "$TMP_JSON"
  if [ -s "$TMP_JSON" ] && jq empty "$TMP_JSON" 2>/dev/null; then
    return 0
  fi
  return 1
}

# --- Extract proof schema JSON from a CMD_*.md file ---
extract_proof_schema() {
  local cmd_file="$1"
  awk '/## PROOF FOR/,0{if(/```json/){f=1;next}if(/```/){f=0;next}if(f)print}' "$cmd_file" 2>/dev/null || echo ""
}

# --- Resolve §CMD_* reference to a definition ---
# Resolution: CMD file → COMMANDS.md → SIGILS.md → SKILL.md local
resolve_cmd() {
  local cmd_name="$1" skill_file="${2:-}"
  [ -f "$CMD_DIR/CMD_${cmd_name}.md" ] && return 0
  grep -qE "[§¶]CMD_${cmd_name}" "$DIRECTIVES_DIR/COMMANDS.md" 2>/dev/null && return 0
  grep -qE "[§¶]CMD_${cmd_name}" "$DIRECTIVES_DIR/SIGILS.md" 2>/dev/null && return 0
  [ -n "$skill_file" ] && grep -q "¶CMD_${cmd_name}" "$skill_file" 2>/dev/null && return 0
  return 1
}

# Collect all valid skill names for cross-reference
collect_skill_names() {
  ALL_SKILL_NAMES=()
  for dir in "$ENGINE_SKILLS"/*/; do
    [ -d "$dir" ] || continue
    local name
    name=$(basename "$dir")
    if [ -f "$dir/SKILL.md" ]; then
      ALL_SKILL_NAMES+=("$name")
    fi
  done
}

# ============================================================
# CATEGORY 1: INSTALLATION
# ============================================================

check_installation() {
  section "Installation"

  # IN-01: engine on PATH
  if command -v engine &>/dev/null; then
    pass "IN-01" "engine command on PATH"
  else
    fail "IN-01" "engine command not on PATH"
  fi

  # IN-02: Required tools
  for tool in jq node; do
    if command -v "$tool" &>/dev/null; then
      pass "IN-02" "$tool available"
    else
      fail "IN-02" "$tool not found on PATH"
    fi
  done

  # IN-03: Engine directory exists
  if [ -d "$ENGINE_DIR" ]; then
    pass "IN-03" "Engine directory exists: $ENGINE_DIR"
  else
    fail "IN-03" "Engine directory missing: $ENGINE_DIR"
    section_end
    return
  fi

  # IN-04: Key directories exist
  for subdir in scripts skills hooks .directives tools; do
    if [ -d "$HOME/.claude/$subdir" ]; then
      pass "IN-04" "$subdir/ directory exists"
    else
      fail "IN-04" "$subdir/ directory missing"
    fi
  done

  # IN-05: lib.sh accessible
  if [ -f "$HOME/.claude/scripts/lib.sh" ]; then
    pass "IN-05" "lib.sh accessible"
  else
    fail "IN-05" "lib.sh not found at ~/.claude/scripts/lib.sh"
  fi

  # IN-06: validate.sh accessible
  if [ -x "$VALIDATE_SH" ]; then
    pass "IN-06" "JSON Schema validator accessible"
  else
    warn "IN-06" "JSON Schema validator not found (some checks will be skipped)"
  fi

  # IN-07: All hook paths in settings.json resolve to existing files
  local settings_file=""
  for candidate in "$PWD/.claude/settings.json" "$HOME/.claude/settings.json"; do
    [ -f "$candidate" ] && settings_file="$candidate" && break
  done
  if [ -n "$settings_file" ]; then
    local hook_paths
    hook_paths=$(jq -r '
      .hooks // {} | to_entries[] |
      .key as $event |
      .value[]? | .hooks[]? |
      "\($event)|\(.command)"
    ' "$settings_file" 2>/dev/null || echo "")
    local broken_hooks=""
    local hooks_checked=0
    while IFS='|' read -r event cmd_path; do
      [ -n "$cmd_path" ] || continue
      hooks_checked=$((hooks_checked + 1))
      # Resolve tilde
      local resolved="${cmd_path/#\~/$HOME}"
      if [ -f "$resolved" ]; then
        pass "IN-07" "$event: $(basename "$cmd_path")"
      else
        broken_hooks="${broken_hooks}${event}:$(basename "$cmd_path") "
        fail "IN-07" "$event: $cmd_path does not exist"
      fi
    done <<< "$hook_paths"
    if [ -n "$broken_hooks" ]; then
      fail "IN-07" "Broken hook paths: ${broken_hooks}"
    elif [ "$hooks_checked" -gt 0 ]; then
      pass "IN-07" "All $hooks_checked hook paths resolve"
    fi
  fi

  section_end
}

# ============================================================
# CATEGORY 2: SKILLS (absorbed from skill-doctor.sh)
# ============================================================

check_skills() {
  section "Skills"
  collect_skill_names

  local skills_checked=0
  for skill_dir in "$ENGINE_SKILLS"/*/; do
    [ -d "$skill_dir" ] || continue
    local name
    name=$(basename "$skill_dir")
    case "$name" in
      node_modules|_shared|.directives) continue ;;
    esac

    skills_checked=$((skills_checked + 1))
    check_single_skill "$skill_dir"
  done

  # Skills-level directives
  SECTION_HEADER=$(printf "${BOLD}--- Skills Directives ---${NC}")
  if [ "$VERBOSE" -eq 1 ]; then printf "%s\n" "$SECTION_HEADER"; SECTION_HEADER=""; fi

  local skill_directives="$ENGINE_SKILLS/.directives"
  if [ -d "$skill_directives" ]; then
    for directive in CHECKLIST.md TESTING.md; do
      if [ -f "$skill_directives/$directive" ]; then
        pass "SK-D" "$directive exists in skills/.directives/"
      else
        warn "SK-D" "Missing $directive in skills/.directives/"
      fi
    done
  else
    warn "SK-D" "Missing .directives/ directory under skills/"
  fi

  if [ "$VERBOSE" -eq 1 ]; then echo; fi
  printf "  ${CYAN}Skills checked: %d${NC}\n" "$skills_checked"
  section_end
}

check_single_skill() {
  local skill_dir="$1"
  local name
  name=$(basename "$skill_dir")

  if [ ! -f "$skill_dir/SKILL.md" ]; then
    SECTION_HEADER=$(printf "${BOLD}--- %s (???) ---${NC}" "$name")
    fail "SK-A" "Missing SKILL.md"
    SECTION_HEADER=""
    return
  fi

  local tier
  tier=$(frontmatter_field "$skill_dir/SKILL.md" "tier")
  if [ -z "$tier" ]; then tier="unknown"; fi

  SECTION_HEADER=$(printf "${BOLD}--- %s (%s) ---${NC}" "$name" "$tier")
  if [ "$VERBOSE" -eq 1 ]; then printf "%s\n" "$SECTION_HEADER"; SECTION_HEADER=""; fi

  extract_json_block "$skill_dir/SKILL.md" || true

  # --- Frontmatter checks (DR-A) ---
  if head -1 "$skill_dir/SKILL.md" | grep -q '^---$'; then
    pass "SK-A1" "YAML frontmatter present"
  else
    fail "SK-A1" "Missing YAML frontmatter"
    SECTION_HEADER=""
    return
  fi

  local fm_name fm_desc fm_version fm_tier
  fm_name=$(frontmatter_field "$skill_dir/SKILL.md" "name")
  fm_desc=$(frontmatter_field "$skill_dir/SKILL.md" "description")
  fm_version=$(frontmatter_field "$skill_dir/SKILL.md" "version")
  fm_tier=$(frontmatter_field "$skill_dir/SKILL.md" "tier")

  local missing=""
  [ -z "$fm_name" ] && missing="${missing}name "
  [ -z "$fm_desc" ] && missing="${missing}description "
  [ -z "$fm_version" ] && missing="${missing}version "
  [ -z "$fm_tier" ] && missing="${missing}tier "
  if [ -z "$missing" ]; then
    pass "SK-A2" "Required fields: name, description, version, tier"
  else
    fail "SK-A2" "Missing fields: ${missing}"
  fi

  if [ -n "$fm_tier" ]; then
    case "$fm_tier" in
      protocol|lightweight|utility|suggest) pass "SK-A3" "Tier is valid: $fm_tier" ;;
      *) fail "SK-A3" "Invalid tier: '$fm_tier'" ;;
    esac
  fi

  if [ -n "$fm_name" ] && [ "$fm_name" = "$name" ]; then
    pass "SK-A6" "Name matches directory"
  elif [ -n "$fm_name" ]; then
    fail "SK-A6" "Name mismatch: frontmatter='$fm_name' dir='$name'"
  fi

  # --- Boot sector checks (DR-B) ---
  if grep -q 'CRITICAL BOOT SEQUENCE' "$skill_dir/SKILL.md"; then
    fail "SK-B1" "Deprecated boot sequence block still present"
  else
    pass "SK-B1" "No deprecated boot sequence"
  fi

  if [ "$tier" = "protocol" ]; then
    if grep -q '§CMD_EXECUTE_SKILL_PHASES' "$skill_dir/SKILL.md"; then
      pass "SK-B2" "Boot sector present"
    else
      fail "SK-B2" "Missing §CMD_EXECUTE_SKILL_PHASES"
    fi
  fi

  if grep -q 'standards/COMMANDS\|standards/INVARIANTS\|standards/TAGS' "$skill_dir/SKILL.md"; then
    fail "SK-B3" "Uses wrong path: standards/ (should be .directives/)"
  else
    pass "SK-B3" "Correct directive paths"
  fi

  # --- JSON manifest & phases (DR-C, protocol-tier only) ---
  if [ "$tier" = "protocol" ]; then
    if [ ! -s "$TMP_JSON" ] || ! jq empty "$TMP_JSON" 2>/dev/null; then
      fail "SK-C1" "No valid JSON manifest block"
    else
      pass "SK-C1" "JSON manifest extracted"

      # Schema validation
      if [ -f "$SCHEMA_FILE" ] && [ -f "$VALIDATE_SH" ]; then
        local schema_errors
        schema_errors=$("$VALIDATE_SH" "$SCHEMA_FILE" "$TMP_JSON" 2>&1) || true
        if [ -z "$schema_errors" ]; then
          pass "SK-C2" "JSON manifest passes schema"
        else
          local preview
          preview=$(echo "$schema_errors" | head -3 | tr '\n' '; ')
          fail "SK-C2" "Schema failed: $preview"
        fi
      fi

      # §CMD_* steps resolve
      local all_steps
      all_steps=$(jq -r '.phases[]?.steps[]? // empty' "$TMP_JSON" 2>/dev/null | sort -u || echo "")
      if [ -n "$all_steps" ]; then
        local missing_cmds=""
        while IFS= read -r step; do
          [ -n "$step" ] || continue
          local cmd_name="${step#§CMD_}"
          if ! resolve_cmd "$cmd_name" "$skill_dir/SKILL.md"; then
            missing_cmds="${missing_cmds}${step} "
          fi
        done <<< "$all_steps"
        if [ -z "$missing_cmds" ]; then
          pass "SK-C4" "All §CMD_* steps resolve"
        else
          fail "SK-C4" "Unresolved: ${missing_cmds}"
        fi
      fi

      # commands[] entries resolve
      local all_commands
      all_commands=$(jq -r '.phases[]?.commands[]? // empty' "$TMP_JSON" 2>/dev/null | sort -u || echo "")
      if [ -n "$all_commands" ]; then
        local missing_refs=""
        while IFS= read -r cmd; do
          [ -n "$cmd" ] || continue
          local cmd_name="${cmd#§CMD_}"
          if ! resolve_cmd "$cmd_name" "$skill_dir/SKILL.md"; then
            missing_refs="${missing_refs}${cmd} "
          fi
        done <<< "$all_commands"
        if [ -z "$missing_refs" ]; then
          pass "SK-C5" "All phase commands resolve"
        else
          warn "SK-C5" "Unresolved: ${missing_refs}"
        fi
      fi

      # --- Mode checks (DR-D) ---
      local has_modes_json=0
      jq -e '.modes' "$TMP_JSON" >/dev/null 2>&1 && has_modes_json=1
      if [ "$has_modes_json" -eq 1 ]; then
        if [ -d "$skill_dir/modes" ]; then
          pass "SK-D1" "modes/ directory exists"
          local mode_count
          mode_count=$(find "$skill_dir/modes" -name '*.md' -maxdepth 1 | wc -l | tr -d ' ')
          if [ "$mode_count" -eq 4 ]; then
            pass "SK-D2" "Correct mode count: 4"
          else
            fail "SK-D2" "Expected 4 mode files, found $mode_count"
          fi
          if [ -f "$skill_dir/modes/custom.md" ]; then
            pass "SK-D2b" "custom.md exists"
          else
            fail "SK-D2b" "Missing custom.md"
          fi
        else
          fail "SK-D1" "Manifest declares modes but modes/ missing"
        fi
      fi

      # --- Template checks (DR-E) ---
      if [ -s "$TMP_JSON" ]; then
        local template_fields=("logTemplate" "debriefTemplate" "planTemplate" "requestTemplate" "responseTemplate")
        local missing_templates=""
        for field in "${template_fields[@]}"; do
          local tpl_path
          tpl_path=$(jq -r ".${field} // empty" "$TMP_JSON" 2>/dev/null || echo "")
          if [ -n "$tpl_path" ]; then
            if [ ! -f "${skill_dir}${tpl_path}" ]; then
              missing_templates="${missing_templates}${field} "
            fi
          fi
        done
        if [ -z "$missing_templates" ]; then
          pass "SK-E3" "All template paths exist"
        else
          fail "SK-E3" "Templates missing: ${missing_templates}"
        fi
      fi

      # --- Protocol completeness (DR-F) ---
      local has_synthesis has_close has_debrief
      has_synthesis=$(jq -r '.phases[]?.steps[]? // empty' "$TMP_JSON" 2>/dev/null | grep -c '§CMD_RUN_SYNTHESIS_PIPELINE' || true)
      has_close=$(jq -r '.phases[]?.steps[]? // empty' "$TMP_JSON" 2>/dev/null | grep -c '§CMD_CLOSE_SESSION' || true)
      has_debrief=$(jq -r '.phases[]?.steps[]? // empty' "$TMP_JSON" 2>/dev/null | grep -c '§CMD_GENERATE_DEBRIEF' || true)

      [ "$has_synthesis" -gt 0 ] && pass "SK-F3a" "Has §CMD_RUN_SYNTHESIS_PIPELINE" || fail "SK-F3a" "Missing §CMD_RUN_SYNTHESIS_PIPELINE"
      [ "$has_close" -gt 0 ] && pass "SK-F3b" "Has §CMD_CLOSE_SESSION" || fail "SK-F3b" "Missing §CMD_CLOSE_SESSION"
      [ "$has_debrief" -gt 0 ] && pass "SK-F3d" "Has §CMD_GENERATE_DEBRIEF" || fail "SK-F3d" "Missing §CMD_GENERATE_DEBRIEF"

      # --- Next skills (DR-G) ---
      local next_skills
      next_skills=$(jq -r '.nextSkills[]? // empty' "$TMP_JSON" 2>/dev/null || echo "")
      if [ -z "$next_skills" ]; then
        fail "SK-G1" "Missing nextSkills array"
      else
        pass "SK-G1" "nextSkills present"
        local invalid_refs=""
        while IFS= read -r skill_ref; do
          [ -n "$skill_ref" ] || continue
          local ref_name="${skill_ref#/}"
          local found=0
          for known in "${ALL_SKILL_NAMES[@]+"${ALL_SKILL_NAMES[@]}"}"; do
            [ "$known" = "$ref_name" ] && { found=1; break; }
          done
          [ "$found" -eq 0 ] && invalid_refs="${invalid_refs}${skill_ref} "
        done <<< "$next_skills"
        if [ -z "$invalid_refs" ]; then
          pass "SK-G2" "All nextSkills reference valid skills"
        else
          fail "SK-G2" "Invalid: ${invalid_refs}"
        fi
      fi
    fi
  fi

  SECTION_HEADER=""
}

# ============================================================
# CATEGORY 3: CMD FILES
# ============================================================

check_cmds() {
  section "CMD Files"

  if [ ! -d "$CMD_DIR" ]; then
    warn "CMD-0" "Commands directory not found: $CMD_DIR"
    section_end
    return
  fi

  local cmd_count=0
  for cmd_file in "$CMD_DIR"/CMD_*.md; do
    [ -f "$cmd_file" ] || continue
    cmd_count=$((cmd_count + 1))
    local cmd_name
    cmd_name=$(basename "$cmd_file" .md)

    # CM-01: Has PROOF FOR section
    if grep -q '## PROOF FOR' "$cmd_file"; then
      pass "CM-01" "$cmd_name has PROOF FOR section"
    else
      warn "CM-01" "$cmd_name missing PROOF FOR section"
      continue
    fi

    # CM-02: Proof schema is valid JSON
    local proof_json
    proof_json=$(extract_proof_schema "$cmd_file")
    if [ -z "$proof_json" ]; then
      fail "CM-02" "$cmd_name has PROOF FOR but no JSON Schema block"
      continue
    fi

    if ! echo "$proof_json" | jq empty 2>/dev/null; then
      fail "CM-02" "$cmd_name proof schema is invalid JSON"
      continue
    fi
    pass "CM-02" "$cmd_name proof schema is valid JSON"

    # CM-03: Schema has required structure
    local has_type has_props
    has_type=$(echo "$proof_json" | jq 'has("type")' 2>/dev/null || echo "false")
    has_props=$(echo "$proof_json" | jq 'has("properties")' 2>/dev/null || echo "false")

    if [ "$has_type" = "true" ] && [ "$has_props" = "true" ]; then
      pass "CM-03" "$cmd_name schema has type + properties"
    else
      local missing_schema=""
      [ "$has_type" = "false" ] && missing_schema="${missing_schema}type "
      [ "$has_props" = "false" ] && missing_schema="${missing_schema}properties "
      fail "CM-03" "$cmd_name schema missing: ${missing_schema}"
    fi

    # CM-04: Schema has required array
    local has_required
    has_required=$(echo "$proof_json" | jq 'has("required")' 2>/dev/null || echo "false")
    if [ "$has_required" = "true" ]; then
      pass "CM-04" "$cmd_name has required array"
    else
      warn "CM-04" "$cmd_name missing required array"
    fi
  done

  printf "  ${CYAN}CMD files checked: %d${NC}\n" "$cmd_count"
  section_end
}

# ============================================================
# CATEGORY 4: DIRECTIVES
# ============================================================

check_directives() {
  section "Directives"

  if [ ! -d "$DIRECTIVES_DIR" ]; then
    fail "DR-01" "Engine .directives/ not found"
    section_end
    return
  fi
  pass "DR-01" ".directives/ exists"

  # DR-02: Core directive files exist
  for core_file in COMMANDS.md INVARIANTS.md SIGILS.md; do
    if [ -f "$DIRECTIVES_DIR/$core_file" ]; then
      pass "DR-02" "$core_file exists"
    else
      fail "DR-02" "Missing $core_file"
    fi
  done

  # DR-03: commands/ subdirectory exists
  if [ -d "$CMD_DIR" ]; then
    pass "DR-03" "commands/ subdirectory exists"
    local cmd_count
    cmd_count=$(find "$CMD_DIR" -name 'CMD_*.md' -maxdepth 1 | wc -l | tr -d ' ')
    pass "DR-03b" "$cmd_count CMD files found"
  else
    fail "DR-03" "commands/ subdirectory missing"
  fi

  # DR-04: templates/ exists (for directive scaffolding)
  if [ -d "$DIRECTIVES_DIR/templates" ]; then
    pass "DR-04" "templates/ subdirectory exists"
  else
    warn "DR-04" "templates/ subdirectory missing"
  fi

  section_end
}

# ============================================================
# CATEGORY 5: SESSIONS
# ============================================================

check_sessions() {
  section "Sessions"

  # Find sessions directory (may be symlink)
  local sessions_dir=""
  if [ -d "sessions" ]; then
    sessions_dir="sessions"
  elif [ -d "$PWD/sessions" ]; then
    sessions_dir="$PWD/sessions"
  fi

  if [ -z "$sessions_dir" ] || [ ! -d "$sessions_dir" ]; then
    warn "SE-00" "No sessions/ directory found in current project"
    section_end
    return
  fi
  pass "SE-00" "sessions/ directory found"

  local session_count=0
  local stale_count=0
  for state_file in "$sessions_dir"/*/.state.json; do
    [ -f "$state_file" ] || continue
    session_count=$((session_count + 1))
    local session_dir
    session_dir=$(dirname "$state_file")
    local session_name
    session_name=$(basename "$session_dir")

    # SE-01: .state.json is valid JSON
    if ! jq empty "$state_file" 2>/dev/null; then
      fail "SE-01" "$session_name: .state.json is invalid JSON"
      continue
    fi

    # SE-02: Check for stale active sessions (dead PID)
    local lifecycle pid
    lifecycle=$(jq -r '.lifecycle // "unknown"' "$state_file" 2>/dev/null || echo "unknown")
    pid=$(jq -r '.pid // empty' "$state_file" 2>/dev/null || echo "")

    if [ "$lifecycle" = "active" ] && [ -n "$pid" ]; then
      if ! kill -0 "$pid" 2>/dev/null; then
        warn "SE-02" "$session_name: lifecycle=active but PID $pid is dead"
        stale_count=$((stale_count + 1))
      fi
    fi

    # SE-03: Required fields present
    local has_skill has_phase
    has_skill=$(jq 'has("skill")' "$state_file" 2>/dev/null || echo "false")
    has_phase=$(jq 'has("currentPhase")' "$state_file" 2>/dev/null || echo "false")
    if [ "$has_skill" = "true" ] && [ "$has_phase" = "true" ]; then
      pass "SE-03" "$session_name: has skill + currentPhase"
    else
      warn "SE-03" "$session_name: missing skill or currentPhase"
    fi
  done

  printf "  ${CYAN}Sessions checked: %d (stale: %d)${NC}\n" "$session_count" "$stale_count"
  section_end
}

# ============================================================
# CATEGORY 6: GLOBAL SIGIL CROSS-REFERENCE
# ============================================================

check_sigils() {
  section "Sigil Cross-Reference"

  # Collect all §CMD_ references across the engine
  local search_dirs=("$DIRECTIVES_DIR" "$ENGINE_SKILLS")
  [ -d "$ENGINE_DIR/docs" ] && search_dirs+=("$ENGINE_DIR/docs")
  # Also search shared directives and project-local skills for cross-references
  [ -d "$HOME/.claude/.directives" ] && search_dirs+=("$HOME/.claude/.directives")
  [ -d "$HOME/.claude/skills" ] && search_dirs+=("$HOME/.claude/skills")

  # --- §CMD_ cross-reference ---
  local cmd_refs_file
  cmd_refs_file=$(mktemp /tmp/doctor-refs-XXXXXX.txt)

  # For sigil cross-references, every §CMD_ occurrence is a real reference —
  # backtick-escaping and code fences are purely typographic, not semantic.
  # (Contrast with tag discovery in tag.sh, where backtick-escaping IS semantic.)
  for search_dir in "${search_dirs[@]}"; do
    [ -d "$search_dir" ] || continue
    find "$search_dir" -type f \( -name '*.md' -o -name '*.sh' \) -print0 2>/dev/null | \
      xargs -0 grep -ohE '§CMD_[A-Z_]+' 2>/dev/null || true
  done | sort -u > "$cmd_refs_file"

  local total_refs=0
  local broken_refs=0
  local broken_list=""
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    total_refs=$((total_refs + 1))
    local cmd_name="${ref#§CMD_}"
    if ! resolve_cmd "$cmd_name" ""; then
      broken_refs=$((broken_refs + 1))
      broken_list="${broken_list}${ref} "
    fi
  done < "$cmd_refs_file"

  if [ "$broken_refs" -eq 0 ]; then
    pass "SG-01" "All $total_refs §CMD_ references resolve"
  else
    fail "SG-01" "$broken_refs/$total_refs §CMD_ broken: ${broken_list}"
  fi

  # --- §INV_ cross-reference ---
  local inv_refs_file
  inv_refs_file=$(mktemp /tmp/doctor-inv-refs-XXXXXX.txt)

  # For sigil cross-references, every §INV_ occurrence is a real reference —
  # backtick-escaping and code fences are purely typographic, not semantic.
  # (Contrast with tag discovery in tag.sh, where backtick-escaping IS semantic.)
  for search_dir in "${search_dirs[@]}"; do
    [ -d "$search_dir" ] || continue
    find "$search_dir" -type f \( -name '*.md' -o -name '*.sh' \) -print0 2>/dev/null | \
      xargs -0 grep -ohE '§INV_[A-Z_]+' 2>/dev/null || true
  done | sort -u > "$inv_refs_file"

  # Collect all ¶INV_ definitions
  local inv_defs_file
  inv_defs_file=$(mktemp /tmp/doctor-inv-defs-XXXXXX.txt)

  for search_dir in "${search_dirs[@]}"; do
    [ -d "$search_dir" ] || continue
    grep -rhoE '¶INV_[A-Z_]+' "$search_dir" 2>/dev/null || true
  done | sort -u > "$inv_defs_file"

  local total_inv_refs=0
  local broken_inv_refs=0
  local broken_inv_list=""
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    total_inv_refs=$((total_inv_refs + 1))
    local inv_name="${ref#§INV_}"
    if ! grep -q "¶INV_${inv_name}" "$inv_defs_file" 2>/dev/null; then
      broken_inv_refs=$((broken_inv_refs + 1))
      broken_inv_list="${broken_inv_list}${ref} "
    fi
  done < "$inv_refs_file"

  if [ "$broken_inv_refs" -eq 0 ]; then
    pass "SG-02" "All $total_inv_refs §INV_ references resolve"
  else
    fail "SG-02" "$broken_inv_refs/$total_inv_refs §INV_ broken: ${broken_inv_list}"
  fi

  # --- Orphaned definitions (defined but never referenced) ---
  local cmd_defs_file
  cmd_defs_file=$(mktemp /tmp/doctor-cmd-defs-XXXXXX.txt)

  for search_dir in "${search_dirs[@]}"; do
    [ -d "$search_dir" ] || continue
    grep -rhoE '¶CMD_[A-Z_]+' "$search_dir" 2>/dev/null || true
  done | sort -u > "$cmd_defs_file"

  local orphaned_cmds=0
  local orphan_list=""
  while IFS= read -r def; do
    [ -n "$def" ] || continue
    local cmd_name="${def#¶CMD_}"
    if ! grep -q "§CMD_${cmd_name}" "$cmd_refs_file" 2>/dev/null; then
      orphaned_cmds=$((orphaned_cmds + 1))
      orphan_list="${orphan_list}${def} "
    fi
  done < "$cmd_defs_file"

  if [ "$orphaned_cmds" -eq 0 ]; then
    pass "SG-03" "No orphaned ¶CMD_ definitions"
  else
    warn "SG-03" "$orphaned_cmds orphaned ¶CMD_: ${orphan_list}"
  fi

  # --- Wrong-sigil definitions (§ heading where ¶ is expected) ---
  # Markdown headings like "### §CMD_FOO" or "### §INV_FOO" are definition sites
  # and should use ¶ not §. Detect these mismatches.
  local wrong_sigil_file
  wrong_sigil_file=$(mktemp /tmp/doctor-wrong-sigil-XXXXXX.txt)

  for search_dir in "${search_dirs[@]}"; do
    [ -d "$search_dir" ] || continue
    find "$search_dir" -type f -name '*.md' -print0 2>/dev/null | \
      xargs -0 awk '/^ *```/{fence=1-fence;next} fence{next} /^#{1,4} §(CMD|INV)_[A-Z_]+/{print FILENAME ":" NR ":" $0}' 2>/dev/null || true
  done | sort -u > "$wrong_sigil_file"

  local wrong_sigil_count
  wrong_sigil_count=$(wc -l < "$wrong_sigil_file" | tr -d ' ')

  if [ "$wrong_sigil_count" -eq 0 ]; then
    pass "SG-04" "No § headings masquerading as definitions"
  else
    local wrong_list=""
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      # Extract just the sigil name from the line
      local sigil_name
      sigil_name=$(echo "$line" | grep -oE '§(CMD|INV)_[A-Z_]+' | head -1)
      wrong_list="${wrong_list}${sigil_name} "
    done < "$wrong_sigil_file"
    warn "SG-04" "$wrong_sigil_count § headings should use ¶: ${wrong_list}"
  fi

  rm -f "$cmd_refs_file" "$inv_refs_file" "$inv_defs_file" "$cmd_defs_file" "$wrong_sigil_file"

  section_end
}

# ============================================================
# CATEGORY 7: ASK_ TREE VALIDATION
# ============================================================

check_ask_trees() {
  section "ASK_ Trees"

  local search_dirs=("$CMD_DIR" "$ENGINE_SKILLS")
  local tree_count=0
  local files_with_trees=""

  for search_dir in "${search_dirs[@]}"; do
    [ -d "$search_dir" ] || continue
    while IFS= read -r file; do
      [ -n "$file" ] || continue
      check_ask_trees_in_file "$file"
    done < <(grep -rl '### ¶ASK_' "$search_dir" --include='*.md' 2>/dev/null || true)
  done

  printf "  ${CYAN}ASK_ trees checked: %d${NC}\n" "$tree_count"
  section_end
}

check_ask_trees_in_file() {
  local file="$1"

  # Extract all ASK_ tree names from this file
  local tree_names
  tree_names=$(grep '### ¶ASK_' "$file" 2>/dev/null | sed 's/.*¶//' | grep -oE 'ASK_[A-Z_]+' || true)
  [ -n "$tree_names" ] || return

  while IFS= read -r tree_name; do
    [ -n "$tree_name" ] || continue
    tree_count=$((tree_count + 1))

    # ASK-01: Identifier format (UPPER_SNAKE_CASE after ASK_)
    local suffix="${tree_name#ASK_}"
    if echo "$suffix" | grep -qE '^[A-Z][A-Z_]*[A-Z]$'; then
      pass "ASK-01" "$tree_name: valid identifier"
    else
      fail "ASK-01" "$tree_name: invalid identifier suffix '$suffix' (need UPPER_SNAKE)"
    fi

    # Extract block: from the heading line to next ### heading (or EOF)
    # Use grep -n to find line numbers, then sed to extract range
    local start_line end_line block
    start_line=$(grep -n "¶${tree_name}" "$file" | head -1 | cut -d: -f1)
    [ -n "$start_line" ] || continue
    # Find next ### heading after start
    end_line=$(tail -n "+$((start_line + 1))" "$file" | grep -n '^### ' | head -1 | cut -d: -f1 || true)
    if [ -n "$end_line" ]; then
      end_line=$((start_line + end_line - 1))
      block=$(sed -n "${start_line},${end_line}p" "$file")
    else
      block=$(tail -n "+${start_line}" "$file")
    fi

    # ASK-02: Trigger line present
    if echo "$block" | grep -q '^Trigger:'; then
      pass "ASK-02" "$tree_name: has Trigger line"
    else
      fail "ASK-02" "$tree_name: missing Trigger line"
    fi

    # ASK-03: ## Decision: line present
    if echo "$block" | grep -q '^## Decision:'; then
      pass "ASK-03" "$tree_name: has ## Decision line"
    else
      fail "ASK-03" "$tree_name: missing ## Decision line"
    fi

    # Extract decision section only (from ## Decision: to end of block)
    local decision_block
    decision_block=$(echo "$block" | sed -n '/^## Decision:/,$ p')

    # ASK-04: Width check — count top-level options (lines starting with "- [CODE]")
    local top_options
    top_options=$(echo "$decision_block" | grep -cE '^- \[[A-Z]+\]' || true)
    if [ "$top_options" -eq 4 ]; then
      pass "ASK-04" "$tree_name: width = $top_options (3+MORE)"
    elif [ "$top_options" -eq 0 ]; then
      warn "ASK-04" "$tree_name: no top-level options found"
    else
      warn "ASK-04" "$tree_name: width = $top_options (expected 4: 3 named + MORE)"
    fi

    # Check MORE presence
    if echo "$decision_block" | grep -qE '^- \[MORE\]'; then
      pass "ASK-04b" "$tree_name: has [MORE] option"
    else
      warn "ASK-04b" "$tree_name: missing [MORE] option"
    fi

    # ASK-05: Depth — count max indent on option lines (2 spaces per level)
    # macOS awk compatible: count leading spaces manually
    local max_depth
    max_depth=$(echo "$decision_block" | grep -E '^ *- \[[A-Z]+\]' | \
      awk '{sub(/[^ ].*/, ""); d=length/2 + 1; if(d>m)m=d} END{print m+0}' || echo "0")
    if [ "$max_depth" -le 3 ]; then
      pass "ASK-05" "$tree_name: depth = $max_depth (≤ 3)"
    else
      fail "ASK-05" "$tree_name: depth = $max_depth (exceeds limit of 3)"
    fi

    # ASK-06: Sibling uniqueness — top-level codes
    local top_codes dup_codes
    top_codes=$(echo "$decision_block" | grep -oE '^\- \[[A-Z]+\]' | grep -oE '\[[A-Z]+\]' | sort || true)
    dup_codes=$(echo "$top_codes" | uniq -d || true)
    if [ -z "$dup_codes" ]; then
      pass "ASK-06" "$tree_name: sibling codes unique"
    else
      fail "ASK-06" "$tree_name: duplicate codes: $dup_codes"
    fi

  done <<< "$tree_names"
}

# ============================================================
# AUTO-DETECTION & MAIN
# ============================================================

detect_and_run() {
  local dir="$1"

  if [ -f "$dir/SKILL.md" ]; then
    # Single skill directory
    section "Skill: $(basename "$dir")"
    collect_skill_names
    check_single_skill "$dir"
    section_end
    return
  fi

  if ls "$dir"/CMD_*.md &>/dev/null 2>&1; then
    # Commands directory
    local saved_cmd_dir="$CMD_DIR"
    CMD_DIR="$dir"
    check_cmds
    CMD_DIR="$saved_cmd_dir"
    return
  fi

  if [ -f "$dir/.state.json" ]; then
    # Single session directory
    section "Session: $(basename "$dir")"
    if jq empty "$dir/.state.json" 2>/dev/null; then
      pass "SE-01" ".state.json is valid JSON"
      local lifecycle skill phase
      lifecycle=$(jq -r '.lifecycle // "unknown"' "$dir/.state.json")
      skill=$(jq -r '.skill // "unknown"' "$dir/.state.json")
      phase=$(jq -r '.currentPhase // "unknown"' "$dir/.state.json")
      printf "  ${CYAN}Skill: %s | Phase: %s | Lifecycle: %s${NC}\n" "$skill" "$phase" "$lifecycle"
    else
      fail "SE-01" ".state.json is invalid JSON"
    fi
    section_end
    return
  fi

  if [ -d "$dir/.directives" ]; then
    local saved_dir="$DIRECTIVES_DIR"
    DIRECTIVES_DIR="$dir/.directives"
    CMD_DIR="$dir/.directives/commands"
    check_directives
    DIRECTIVES_DIR="$saved_dir"
    CMD_DIR="$ENGINE_DIR/.directives/commands"
    return
  fi

  echo "Could not auto-detect directory type for: $dir"
  echo "Expected: SKILL.md (skill), CMD_*.md files (commands), .state.json (session), .directives/ (directives)"
  exit 1
}

# ============================================================
# MAIN
# ============================================================

printf "${BOLD}Engine Doctor v1.0${NC} — Ecosystem Health Check\n"

if [ -n "$TARGET_DIR" ]; then
  # Targeted check
  if [ ! -d "$TARGET_DIR" ]; then
    echo "Directory not found: $TARGET_DIR" >&2
    exit 1
  fi
  printf "Target: %s\n\n" "$TARGET_DIR"
  detect_and_run "$TARGET_DIR"
else
  # Full ecosystem check
  printf "Engine: %s\n\n" "$ENGINE_DIR"
  check_installation
  check_skills
  check_cmds
  check_directives
  check_sessions
  check_sigils
  check_ask_trees
fi

# --- Summary ---
total=$((PASSES + WARNS + FAILS))
printf "\n${BOLD}Summary:${NC} "
printf "${GREEN}%d PASS${NC} | " "$PASSES"
printf "${YELLOW}%d WARN${NC} | " "$WARNS"
if [ "$FAILS" -gt 0 ]; then
  printf "${RED}%d FAIL${NC}\n" "$FAILS"
else
  printf "${GREEN}%d FAIL${NC}\n" "$FAILS"
fi

if [ "$FAILS" -eq 0 ]; then exit 0; else exit 1; fi
