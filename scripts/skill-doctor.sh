#!/bin/bash
# ~/.claude/scripts/skill-doctor.sh — Skill ecosystem diagnostic tool
#
# Validates structural health of all skills in the engine.
# Checks YAML frontmatter, boot sector, JSON manifest schema,
# phase structure, §CMD_* cross-references, modes, templates,
# protocol completeness, and next-skill routing.
#
# Usage: skill-doctor.sh [-v|--verbose]
#   Default: only shows WARN/FAIL and summary
#   -v:      shows all checks including PASS
# Exit:  0 = all checks pass, 1 = any FAIL detected

set -euo pipefail

# --- Args ---
VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    -v|--verbose) VERBOSE=1 ;;
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
SKILLS_CHECKED=0

# --- Per-skill issue buffer (for quiet mode) ---
SKILL_ISSUES=""
SKILL_HEADER=""

# --- Output helpers ---
pass() {
  PASSES=$((PASSES + 1))
  if [ "$VERBOSE" -eq 1 ]; then
    printf "  ${GREEN}PASS${NC}  %-7s %s\n" "$1" "$2"
  fi
}
warn() {
  WARNS=$((WARNS + 1))
  if [ "$VERBOSE" -eq 0 ] && [ -n "$SKILL_HEADER" ]; then
    printf "%s\n" "$SKILL_HEADER"
    SKILL_HEADER=""
  fi
  printf "  ${YELLOW}WARN${NC}  %-7s %s\n" "$1" "$2"
}
fail() {
  FAILS=$((FAILS + 1))
  if [ "$VERBOSE" -eq 0 ] && [ -n "$SKILL_HEADER" ]; then
    printf "%s\n" "$SKILL_HEADER"
    SKILL_HEADER=""
  fi
  printf "  ${RED}FAIL${NC}  %-7s %s\n" "$1" "$2"
}

# --- Resolve engine paths ---
ENGINE_SKILLS="$HOME/.claude/engine/skills"
if [ ! -d "$ENGINE_SKILLS" ]; then
  ENGINE_SKILLS="$HOME/.claude/skills"
fi

ENGINE_DIR="$HOME/.claude/engine"
CMD_DIR="$ENGINE_DIR/.directives/commands"
SCHEMA_FILE="$ENGINE_DIR/tools/json-schema-validate/schemas/skill-manifest.json"
VALIDATE_SH="$ENGINE_DIR/tools/json-schema-validate/validate.sh"

# Temp file for JSON extraction (cleaned up on exit)
TMP_JSON=$(mktemp /tmp/skill-doctor-XXXXXX.json)
trap 'rm -f "$TMP_JSON"' EXIT

# Collect all valid skill names (directories with SKILL.md) for cross-reference
ALL_SKILL_NAMES=()
for dir in "$ENGINE_SKILLS"/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  if [ -f "$dir/SKILL.md" ]; then
    ALL_SKILL_NAMES+=("$name")
  fi
done

# Also check ~/.claude/skills/ for project-local skills
LOCAL_SKILLS="$HOME/.claude/skills"
if [ -d "$LOCAL_SKILLS" ] && [ "$LOCAL_SKILLS" != "$ENGINE_SKILLS" ]; then
  for dir in "$LOCAL_SKILLS"/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    if [ -f "$dir/SKILL.md" ]; then
      # Only add if not already in engine
      found=0
      for existing in "${ALL_SKILL_NAMES[@]}"; do
        if [ "$existing" = "$name" ]; then found=1; break; fi
      done
      if [ "$found" -eq 0 ]; then ALL_SKILL_NAMES+=("$name"); fi
    fi
  done
fi

# --- Extract YAML frontmatter field ---
# Usage: frontmatter_field SKILL_FILE FIELD
frontmatter_field() {
  local file="$1" field="$2"
  awk '/^---$/{n++; next} n==1{print}' "$file" | (grep "^${field}:" || true) | sed "s/^${field}:[[:space:]]*//" | sed 's/^["'"'"']//' | sed 's/["'"'"']$//'
}

# --- Extract first ```json block from SKILL.md ---
# Usage: extract_manifest SKILL_FILE
# Writes to $TMP_JSON, returns 0 if found, 1 if not
extract_manifest() {
  local file="$1"
  awk '/^```json$/{found=1;next} found && /^```$/{exit} found{print}' "$file" > "$TMP_JSON"
  if [ -s "$TMP_JSON" ] && jq empty "$TMP_JSON" 2>/dev/null; then
    return 0
  fi
  return 1
}

# --- Resolve §CMD_* reference to a definition ---
# Usage: resolve_cmd CMD_NAME SKILL_FILE
# Returns 0 if found, 1 if not.
# Resolution order:
#   1. Dedicated CMD file: .directives/commands/CMD_NAME.md
#   2. Shared COMMANDS.md: §CMD_NAME or ¶CMD_NAME
#   3. Skill-local definition: ¶CMD_NAME in SKILL.md (inline command)
resolve_cmd() {
  local cmd_name="$1" skill_file="$2"
  # 1. Dedicated CMD file
  [ -f "$CMD_DIR/CMD_${cmd_name}.md" ] && return 0
  # 2. Shared COMMANDS.md (§ reference or ¶ definition)
  grep -qE "[§¶]CMD_${cmd_name}" "$ENGINE_DIR/.directives/COMMANDS.md" 2>/dev/null && return 0
  # 3. Skill-local ¶CMD_NAME definition in SKILL.md
  grep -q "¶CMD_${cmd_name}" "$skill_file" 2>/dev/null && return 0
  return 1
}

# ============================================================
# CHECK FUNCTIONS
# ============================================================

# --- Check: Category A — YAML Frontmatter ---
check_frontmatter() {
  local skill_dir="$1" skill_file="$skill_dir/SKILL.md" name
  name=$(basename "$skill_dir")

  # DR-A1: Has YAML frontmatter
  if head -1 "$skill_file" | grep -q '^---$'; then
    pass "DR-A1" "YAML frontmatter present"
  else
    fail "DR-A1" "Missing YAML frontmatter (no --- delimiter)"
    return
  fi

  # DR-A2: Required fields
  local fm_name fm_desc fm_version fm_tier
  fm_name=$(frontmatter_field "$skill_file" "name")
  fm_desc=$(frontmatter_field "$skill_file" "description")
  fm_version=$(frontmatter_field "$skill_file" "version")
  fm_tier=$(frontmatter_field "$skill_file" "tier")

  local missing=""
  if [ -z "$fm_name" ]; then missing="${missing}name "; fi
  if [ -z "$fm_desc" ]; then missing="${missing}description "; fi
  if [ -z "$fm_version" ]; then missing="${missing}version "; fi
  if [ -z "$fm_tier" ]; then missing="${missing}tier "; fi

  if [ -z "$missing" ]; then
    pass "DR-A2" "Required fields: name, description, version, tier"
  else
    fail "DR-A2" "Missing fields: ${missing}"
  fi

  # DR-A3: tier is valid enum
  if [ -n "$fm_tier" ]; then
    case "$fm_tier" in
      protocol|lightweight|utility|suggest) pass "DR-A3" "Tier is valid: $fm_tier" ;;
      *) fail "DR-A3" "Invalid tier: '$fm_tier' (expected: protocol, lightweight, utility, suggest)" ;;
    esac
  fi

  # DR-A6: name matches dirname
  if [ -n "$fm_name" ]; then
    if [ "$fm_name" = "$name" ]; then
      pass "DR-A6" "Name matches directory: $fm_name"
    else
      fail "DR-A6" "Name mismatch: frontmatter='$fm_name' dir='$name'"
    fi
  fi
}

# --- Check: Category B — Boot Sector (protocol-tier only) ---
check_boot() {
  local skill_dir="$1" tier="$2" skill_file="$skill_dir/SKILL.md"

  # DR-B1: No deprecated boot sequence block
  if grep -q 'CRITICAL BOOT SEQUENCE' "$skill_file"; then
    fail "DR-B1" "Deprecated boot sequence block still present — remove it"
  else
    pass "DR-B1" "No deprecated boot sequence block"
  fi

  # DR-B2: Boot sector present (protocol-tier only — ¶INV_BOOT_SECTOR_AT_TOP)
  if [ "$tier" = "protocol" ]; then
    if grep -q '§CMD_EXECUTE_SKILL_PHASES' "$skill_file"; then
      pass "DR-B2" "Boot sector: §CMD_EXECUTE_SKILL_PHASES present"
    else
      fail "DR-B2" "Missing boot sector: §CMD_EXECUTE_SKILL_PHASES (¶INV_BOOT_SECTOR_AT_TOP)"
    fi
  fi

  # DR-B3: Uses correct paths (.directives/ not standards/)
  if grep -q 'standards/COMMANDS\|standards/INVARIANTS\|standards/TAGS' "$skill_file"; then
    fail "DR-B3" "Uses wrong path: ~/.claude/standards/ (should be ~/.claude/.directives/)"
  else
    pass "DR-B3" "Correct directive paths"
  fi
}

# --- Check: Category C — JSON Manifest & Phase Structure (protocol-tier only) ---
check_manifest() {
  local skill_dir="$1" tier="$2" skill_file="$skill_dir/SKILL.md"
  [ "$tier" = "protocol" ] || return 0

  # DR-C1: Has extractable JSON manifest
  if ! extract_manifest "$skill_file"; then
    fail "DR-C1" "No valid JSON manifest block found in SKILL.md"
    return
  fi
  pass "DR-C1" "JSON manifest block extracted"

  # DR-C2: JSON schema validation
  if [ -f "$SCHEMA_FILE" ] && [ -f "$VALIDATE_SH" ]; then
    local schema_errors
    schema_errors=$("$VALIDATE_SH" "$SCHEMA_FILE" "$TMP_JSON" 2>&1) || true
    if [ -z "$schema_errors" ]; then
      pass "DR-C2" "JSON manifest passes schema validation"
    else
      # Show first 3 errors max
      local err_count
      err_count=$(echo "$schema_errors" | grep -c '/' || true)
      local preview
      preview=$(echo "$schema_errors" | head -3 | tr '\n' '; ')
      fail "DR-C2" "Schema validation failed ($err_count errors): $preview"
    fi
  else
    warn "DR-C2" "Schema validator not available — skipped"
  fi

  # DR-C3: Phase labels match ## headers in SKILL.md body
  local json_labels
  json_labels=$(jq -r '.phases[]?.label // empty' "$TMP_JSON" 2>/dev/null || echo "")

  # Extract ## N. headers from body (after frontmatter)
  local body_headers
  body_headers=$(awk '
    /^---$/ { n++; next }
    n >= 2 && /^## [0-9]/ {
      sub(/^## /, "", $0)
      # Extract the label prefix (e.g., "0." "3.A." "4.1.")
      match($0, /^[0-9]+(\.[0-9A-Z]+)?\./)
      if (RSTART > 0) {
        label = substr($0, RSTART, RLENGTH - 1)
        print label
      }
    }
  ' "$skill_file")

  local mismatches=0
  while IFS= read -r label; do
    [ -n "$label" ] || continue
    # Only check major phases (no dot) — sub-phases share parent's header
    case "$label" in
      *.*) continue ;;
    esac
    if ! echo "$body_headers" | grep -qx "$label"; then
      fail "DR-C3" "Phase '$label' in JSON but no matching ## $label. header"
      mismatches=$((mismatches + 1))
    fi
  done <<< "$json_labels"

  if [ "$mismatches" -eq 0 ] && [ -n "$json_labels" ]; then
    pass "DR-C3" "Major phase labels match ## section headers"
  fi

  # DR-C4: §CMD_* steps reference existing CMD files (¶INV_STEPS_ARE_COMMANDS)
  # Resolution order: CMD file > COMMANDS.md (§ or ¶) > SKILL.md (¶ definition)
  local all_steps
  all_steps=$(jq -r '.phases[]?.steps[]? // empty' "$TMP_JSON" 2>/dev/null | sort -u || echo "")

  if [ -z "$all_steps" ]; then
    pass "DR-C4" "No steps to cross-reference"
  else
    local missing_cmds=""
    while IFS= read -r step; do
      [ -n "$step" ] || continue
      local cmd_name="${step#§CMD_}"
      if ! resolve_cmd "$cmd_name" "$skill_file"; then
        missing_cmds="${missing_cmds}${step} "
      fi
    done <<< "$all_steps"

    if [ -z "$missing_cmds" ]; then
      pass "DR-C4" "All §CMD_* steps resolve"
    else
      fail "DR-C4" "Unresolved step references: ${missing_cmds}"
    fi
  fi

  # DR-C5: All commands entries are also valid §CMD_* references
  local all_commands
  all_commands=$(jq -r '.phases[]?.commands[]? // empty' "$TMP_JSON" 2>/dev/null | sort -u || echo "")

  if [ -n "$all_commands" ]; then
    local missing_cmd_refs=""
    while IFS= read -r cmd; do
      [ -n "$cmd" ] || continue
      local cmd_name="${cmd#§CMD_}"
      if ! resolve_cmd "$cmd_name" "$skill_file"; then
        missing_cmd_refs="${missing_cmd_refs}${cmd} "
      fi
    done <<< "$all_commands"

    if [ -z "$missing_cmd_refs" ]; then
      pass "DR-C5" "All phase commands resolve"
    else
      warn "DR-C5" "Unresolved command references: ${missing_cmd_refs}"
    fi
  fi
}

# --- Check: Category D — Mode Rules (protocol-tier only) ---
check_modes() {
  local skill_dir="$1" tier="$2"
  [ "$tier" = "protocol" ] || return 0

  local name
  name=$(basename "$skill_dir")

  # Check if manifest declares modes
  local has_modes_json=0
  if [ -s "$TMP_JSON" ] && jq -e '.modes' "$TMP_JSON" >/dev/null 2>&1; then
    has_modes_json=1
  fi

  # DR-D1: Has modes/ directory (only if manifest declares modes)
  if [ "$has_modes_json" -eq 1 ]; then
    if [ -d "$skill_dir/modes" ]; then
      pass "DR-D1" "modes/ directory exists"
    else
      fail "DR-D1" "Manifest declares modes but modes/ directory missing"
      return
    fi

    # DR-D2: Exactly 4 mode files (3 named + custom.md)
    local mode_count
    mode_count=$(find "$skill_dir/modes" -name '*.md' -maxdepth 1 | wc -l | tr -d ' ')

    if [ "$mode_count" -eq 4 ]; then
      pass "DR-D2" "Correct mode count: 4 files"
    else
      fail "DR-D2" "Expected 4 mode files, found $mode_count"
    fi

    # DR-D2b: custom.md specifically
    if [ -f "$skill_dir/modes/custom.md" ]; then
      pass "DR-D2b" "custom.md exists"
    else
      fail "DR-D2b" "Missing custom.md in modes/"
    fi

    # DR-D3: Modes in JSON match files on disk
    local json_mode_files
    json_mode_files=$(jq -r '.modes | to_entries[]? | .value.file // empty' "$TMP_JSON" 2>/dev/null || echo "")
    local missing_mode_files=""
    while IFS= read -r mode_file; do
      [ -n "$mode_file" ] || continue
      # Mode file paths are relative to skill dir
      local full_path="$skill_dir/$mode_file"
      if [ ! -f "$full_path" ]; then
        missing_mode_files="${missing_mode_files}$(basename "$mode_file") "
      fi
    done <<< "$json_mode_files"

    if [ -z "$missing_mode_files" ]; then
      pass "DR-D3" "All mode files in JSON exist on disk"
    else
      fail "DR-D3" "Mode files missing: ${missing_mode_files}"
    fi
  else
    # No modes in manifest — check if modes/ dir exists anyway (stale?)
    if [ -d "$skill_dir/modes" ]; then
      warn "DR-D1" "modes/ directory exists but manifest has no modes object"
    fi
  fi
}

# --- Check: Category E — Template Rules ---
check_templates() {
  local skill_dir="$1" tier="$2" name
  name=$(basename "$skill_dir")

  # Check assets/ exists
  if [ ! -d "$skill_dir/assets" ]; then
    return 0
  fi

  # DR-E1: assets/ not empty
  local asset_count
  asset_count=$(find "$skill_dir/assets" -maxdepth 1 -type f | wc -l | tr -d ' ')
  if [ "$asset_count" -eq 0 ]; then
    warn "DR-E1" "assets/ directory is empty"
  fi

  # DR-E2: REQUEST implies RESPONSE (¶INV_DELEGATION_VIA_TEMPLATES)
  local has_request has_response
  has_request=$(find "$skill_dir/assets" -name 'TEMPLATE_*_REQUEST.md' -maxdepth 1 | wc -l | tr -d ' ')
  has_response=$(find "$skill_dir/assets" -name 'TEMPLATE_*_RESPONSE.md' -maxdepth 1 | wc -l | tr -d ' ')

  if [ "$has_request" -gt 0 ]; then
    if [ "$has_response" -gt 0 ]; then
      pass "DR-E2" "REQUEST/RESPONSE templates paired"
    else
      warn "DR-E2" "Has REQUEST template but no RESPONSE template"
    fi
  fi

  # DR-E3: Template paths in manifest match files on disk (protocol-tier)
  if [ "$tier" = "protocol" ] && [ -s "$TMP_JSON" ]; then
    local template_fields=("logTemplate" "debriefTemplate" "planTemplate" "requestTemplate" "responseTemplate")
    local missing_templates=""
    for field in "${template_fields[@]}"; do
      local tpl_path
      tpl_path=$(jq -r ".${field} // empty" "$TMP_JSON" 2>/dev/null || echo "")
      if [ -n "$tpl_path" ]; then
        local full_path="$skill_dir/$tpl_path"
        if [ ! -f "$full_path" ]; then
          missing_templates="${missing_templates}${field}=${tpl_path} "
        fi
      fi
    done

    if [ -z "$missing_templates" ]; then
      pass "DR-E3" "All manifest template paths exist on disk"
    else
      fail "DR-E3" "Template files missing: ${missing_templates}"
    fi
  fi
}

# --- Check: Category F — Protocol Completeness (protocol-tier only) ---
check_protocol() {
  local skill_dir="$1" tier="$2" skill_file="$skill_dir/SKILL.md"
  [ "$tier" = "protocol" ] || return 0

  # DR-F1: §CMD_REPORT_INTENT in phase sections
  # Extract phase labels from JSON
  local json_labels
  json_labels=$(jq -r '.phases[]?.label // empty' "$TMP_JSON" 2>/dev/null || echo "")

  if [ -n "$json_labels" ]; then
    # Check each major phase section for §CMD_REPORT_INTENT
    local missing_intent=""
    local checked=0
    while IFS= read -r label; do
      [ -n "$label" ] || continue
      # Only check major phases (no dot) — sub-phases inherit parent's intent
      case "$label" in
        *.*) continue ;;
      esac
      checked=$((checked + 1))

      # Find the ## N. section and check for REPORT_INTENT before next ## section
      local has_intent
      has_intent=$(awk -v lbl="$label" '
        BEGIN { in_section=0 }
        /^## / {
          if (in_section) exit
          # Match "## N." where N is the label
          if ($0 ~ "^## " lbl "\\.") in_section=1
        }
        in_section && /§CMD_REPORT_INTENT/ { print "found"; exit }
      ' "$skill_file")

      if [ -z "$has_intent" ]; then
        missing_intent="${missing_intent}${label} "
      fi
    done <<< "$json_labels"

    if [ -z "$missing_intent" ]; then
      pass "DR-F1" "§CMD_REPORT_INTENT in all $checked major phases"
    else
      warn "DR-F1" "Missing §CMD_REPORT_INTENT in phases: ${missing_intent}"
    fi
  fi

  # DR-F2: §CMD_EXECUTE_PHASE_STEPS in phase sections
  if [ -n "$json_labels" ]; then
    local missing_steps=""
    local checked=0
    while IFS= read -r label; do
      [ -n "$label" ] || continue
      # Only check major phases
      case "$label" in
        *.*) continue ;;
      esac
      checked=$((checked + 1))

      local has_exec
      has_exec=$(awk -v lbl="$label" '
        BEGIN { in_section=0 }
        /^## / {
          if (in_section) exit
          if ($0 ~ "^## " lbl "\\.") in_section=1
        }
        in_section && /§CMD_EXECUTE_PHASE_STEPS/ { print "found"; exit }
      ' "$skill_file")

      if [ -z "$has_exec" ]; then
        missing_steps="${missing_steps}${label} "
      fi
    done <<< "$json_labels"

    if [ -z "$missing_steps" ]; then
      pass "DR-F2" "§CMD_EXECUTE_PHASE_STEPS in all $checked major phases"
    else
      warn "DR-F2" "Missing §CMD_EXECUTE_PHASE_STEPS in phases: ${missing_steps}"
    fi
  fi

  # DR-F3: Synthesis completeness — check for key synthesis commands in manifest steps
  local has_synthesis has_close
  has_synthesis=$(jq -r '.phases[]?.steps[]? // empty' "$TMP_JSON" 2>/dev/null | grep -c '§CMD_RUN_SYNTHESIS_PIPELINE' || true)
  has_close=$(jq -r '.phases[]?.steps[]? // empty' "$TMP_JSON" 2>/dev/null | grep -c '§CMD_CLOSE_SESSION' || true)

  if [ "$has_synthesis" -gt 0 ]; then
    pass "DR-F3a" "§CMD_RUN_SYNTHESIS_PIPELINE in phase steps"
  else
    fail "DR-F3a" "Missing §CMD_RUN_SYNTHESIS_PIPELINE in synthesis phases"
  fi

  if [ "$has_close" -gt 0 ]; then
    pass "DR-F3b" "§CMD_CLOSE_SESSION in phase steps"
  else
    fail "DR-F3b" "Missing §CMD_CLOSE_SESSION in closing phase"
  fi

  # DR-F3c: §CMD_PRESENT_NEXT_STEPS in closing phase
  local has_next_steps
  has_next_steps=$(jq -r '.phases[]?.steps[]? // empty' "$TMP_JSON" 2>/dev/null | grep -c '§CMD_PRESENT_NEXT_STEPS' || true)
  if [ "$has_next_steps" -gt 0 ]; then
    pass "DR-F3c" "§CMD_PRESENT_NEXT_STEPS in closing phase"
  else
    warn "DR-F3c" "Missing §CMD_PRESENT_NEXT_STEPS in closing phase"
  fi

  # DR-F3d: §CMD_GENERATE_DEBRIEF in debrief phase
  local has_debrief
  has_debrief=$(jq -r '.phases[]?.steps[]? // empty' "$TMP_JSON" 2>/dev/null | grep -c '§CMD_GENERATE_DEBRIEF' || true)
  if [ "$has_debrief" -gt 0 ]; then
    pass "DR-F3d" "§CMD_GENERATE_DEBRIEF in debrief phase"
  else
    fail "DR-F3d" "Missing §CMD_GENERATE_DEBRIEF — no debrief generation"
  fi
}

# --- Check: Category G — Next Skills (protocol-tier only) ---
check_next_skills() {
  local skill_dir="$1" tier="$2"
  [ "$tier" = "protocol" ] || return 0
  [ -s "$TMP_JSON" ] || return 0

  # DR-G1: nextSkills array present in manifest
  local next_skills
  next_skills=$(jq -r '.nextSkills[]? // empty' "$TMP_JSON" 2>/dev/null || echo "")

  if [ -z "$next_skills" ]; then
    fail "DR-G1" "Missing nextSkills array in manifest"
    return
  fi
  pass "DR-G1" "nextSkills array present in manifest"

  # DR-G2: Each nextSkill references a valid skill directory
  local invalid_refs=""
  while IFS= read -r skill_ref; do
    [ -n "$skill_ref" ] || continue
    # Strip leading /
    local ref_name="${skill_ref#/}"
    local found=0
    for known in "${ALL_SKILL_NAMES[@]}"; do
      if [ "$known" = "$ref_name" ]; then found=1; break; fi
    done
    if [ "$found" -eq 0 ]; then
      invalid_refs="${invalid_refs}${skill_ref} "
    fi
  done <<< "$next_skills"

  if [ -z "$invalid_refs" ]; then
    pass "DR-G2" "All nextSkills reference valid skill directories"
  else
    fail "DR-G2" "Invalid nextSkill references: ${invalid_refs}"
  fi
}

# --- Check: Category I — Cross-Skill (per-directory) ---
check_cross_skill() {
  local skill_dir="$1"
  local name
  name=$(basename "$skill_dir")

  # DR-I1: Has SKILL.md
  if [ -f "$skill_dir/SKILL.md" ]; then
    pass "DR-I1" "SKILL.md exists"
  else
    fail "DR-I1" "Missing SKILL.md"
  fi
}

# ============================================================
# MAIN
# ============================================================

printf "${BOLD}Skill Doctor v2.0${NC} — Ecosystem Health Check\n"
printf "Engine: %s\n" "$ENGINE_SKILLS"
if [ -f "$SCHEMA_FILE" ]; then
  printf "Schema: %s\n" "$SCHEMA_FILE"
else
  printf "${YELLOW}Schema: not found (DR-C2 will be skipped)${NC}\n"
fi
printf "\n"

# --- Per-skill checks ---
check_skill_dir() {
  local skill_dir="$1" label="${2:-}"

  [ -d "$skill_dir" ] || return 0
  local name
  name=$(basename "$skill_dir")

  # Skip non-skill directories
  case "$name" in
    node_modules|_shared|.directives) return 0 ;;
  esac

  SKILLS_CHECKED=$((SKILLS_CHECKED + 1))

  # Check SKILL.md exists first
  if [ ! -f "$skill_dir/SKILL.md" ]; then
    SKILL_HEADER=$(printf "${BOLD}=== %s (???) %s===${NC}" "$name" "$label")
    fail "DR-I1" "Missing SKILL.md — skill directory exists but no protocol file"
    SKILL_HEADER=""
    return
  fi

  # Extract tier
  local tier
  tier=$(frontmatter_field "$skill_dir/SKILL.md" "tier")
  if [ -z "$tier" ]; then tier="unknown"; fi

  SKILL_HEADER=$(printf "${BOLD}=== %s (%s) %s===${NC}" "$name" "$tier" "$label")
  if [ "$VERBOSE" -eq 1 ]; then printf "%s\n" "$SKILL_HEADER"; SKILL_HEADER=""; fi

  # Extract manifest once for all checks that need it
  extract_manifest "$skill_dir/SKILL.md" || true

  check_frontmatter "$skill_dir"
  check_boot "$skill_dir" "$tier"
  check_manifest "$skill_dir" "$tier"
  check_modes "$skill_dir" "$tier"
  check_templates "$skill_dir" "$tier"
  check_protocol "$skill_dir" "$tier"
  check_next_skills "$skill_dir" "$tier"
  check_cross_skill "$skill_dir"

  if [ "$VERBOSE" -eq 1 ]; then echo; fi
  SKILL_HEADER=""
}

for skill_dir in "$ENGINE_SKILLS"/*/; do
  check_skill_dir "$skill_dir"
done

# Also check local skills
if [ -d "$LOCAL_SKILLS" ] && [ "$LOCAL_SKILLS" != "$ENGINE_SKILLS" ]; then
  for skill_dir in "$LOCAL_SKILLS"/*/; do
    [ -d "$skill_dir" ] || continue
    local_name=$(basename "$skill_dir")
    # Skip if already checked in engine
    if [ -d "$ENGINE_SKILLS/$local_name" ]; then continue; fi
    check_skill_dir "$skill_dir" "[local] "
  done
fi

# --- Skills-level directives check ---
SKILL_HEADER=$(printf "${BOLD}=== Engine-Level Directives ===${NC}")
if [ "$VERBOSE" -eq 1 ]; then printf "%s\n" "$SKILL_HEADER"; SKILL_HEADER=""; fi

# Check .directives/ subfolder (new location)
DIRECTIVES_DIR="$ENGINE_SKILLS/.directives"
if [ -d "$DIRECTIVES_DIR" ]; then
  for directive in CHECKLIST.md TESTING.md; do
    if [ -f "$DIRECTIVES_DIR/$directive" ]; then
      pass "DR-I2" "$directive exists in .directives/"
    else
      warn "DR-I2" "Missing $directive in skills/.directives/"
    fi
  done
else
  warn "DR-I2" "Missing .directives/ directory under skills/"
fi

if [ "$VERBOSE" -eq 1 ]; then echo; fi
SKILL_HEADER=""

# --- Summary ---
total=$((PASSES + WARNS + FAILS))
printf "${BOLD}Summary:${NC} %d skills checked | " "$SKILLS_CHECKED"
printf "${GREEN}%d PASS${NC} | " "$PASSES"
printf "${YELLOW}%d WARN${NC} | " "$WARNS"
if [ "$FAILS" -gt 0 ]; then
  printf "${RED}%d FAIL${NC}\n" "$FAILS"
else
  printf "${GREEN}%d FAIL${NC}\n" "$FAILS"
fi

# Exit code
if [ "$FAILS" -eq 0 ]; then exit 0; else exit 1; fi
