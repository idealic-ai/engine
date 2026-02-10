#!/bin/bash
# ~/.claude/scripts/skill-doctor.sh — Skill ecosystem diagnostic tool
#
# Validates structural health of all skills in the engine.
# Checks YAML frontmatter, boot sequences, modes, templates,
# phase structure, Next Skill Options, and cross-skill consistency.
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

# --- Resolve engine skills directory ---
ENGINE_SKILLS="$HOME/.claude/engine/skills"
if [ ! -d "$ENGINE_SKILLS" ]; then
  ENGINE_SKILLS="$HOME/.claude/skills"
fi

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
  # Extract between first --- and second ---
  awk '/^---$/{n++; next} n==1{print}' "$file" | (grep "^${field}:" || true) | sed "s/^${field}:[[:space:]]*//" | sed 's/^["'"'"']//' | sed 's/["'"'"']$//'
}

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
      protocol|lightweight|utility) pass "DR-A3" "Tier is valid: $fm_tier" ;;
      *) fail "DR-A3" "Invalid tier: '$fm_tier' (expected: protocol, lightweight, utility)" ;;
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

# --- Check: Category B — Boot Sequence ---
check_boot() {
  local skill_dir="$1" skill_file="$skill_dir/SKILL.md" name
  name=$(basename "$skill_dir")

  # DR-B1: Boot sequence present
  if grep -q 'CRITICAL BOOT SEQUENCE' "$skill_file"; then
    pass "DR-B1" "Boot sequence block present"
  else
    fail "DR-B1" "Missing boot sequence block"
  fi

  # DR-B2: Gate check present
  if grep -q 'GATE CHECK' "$skill_file"; then
    pass "DR-B2" "Gate check block present"
  else
    fail "DR-B2" "Missing gate check block"
  fi

  # DR-B3: References all 3 standards (skip for dehydrate)
  if [ "$name" != "dehydrate" ]; then
    local has_cmd has_inv has_tag
    has_cmd=$(grep -c 'COMMANDS\.md' "$skill_file" || true)
    has_inv=$(grep -c 'INVARIANTS\.md' "$skill_file" || true)
    has_tag=$(grep -c 'TAGS\.md' "$skill_file" || true)

    if [ "$has_cmd" -gt 0 ] && [ "$has_inv" -gt 0 ] && [ "$has_tag" -gt 0 ]; then
      pass "DR-B3" "References all 3 standards files"
    else
      local missing=""
      if [ "$has_cmd" -eq 0 ]; then missing="${missing}COMMANDS.md "; fi
      if [ "$has_inv" -eq 0 ]; then missing="${missing}INVARIANTS.md "; fi
      if [ "$has_tag" -eq 0 ]; then missing="${missing}TAGS.md "; fi
      warn "DR-B3" "Missing references: ${missing}"
    fi
  fi

  # DR-B4: Uses correct paths (.directives/ not standards/)
  if grep -q 'standards/COMMANDS\|standards/INVARIANTS\|standards/TAGS' "$skill_file"; then
    fail "DR-B4" "Uses wrong path: ~/.claude/standards/ (should be ~/.claude/.directives/)"
  else
    pass "DR-B4" "Correct directive paths"
  fi
}


# --- Check: Category D — Mode Rules (protocol-tier only) ---
check_modes() {
  local skill_dir="$1" tier="$2"
  [ "$tier" = "protocol" ] || return 0

  local name
  name=$(basename "$skill_dir")

  # DR-D1: Has modes/ directory
  if [ -d "$skill_dir/modes" ]; then
    pass "DR-D1" "modes/ directory exists"
  else
    fail "DR-D1" "Missing modes/ directory (protocol-tier requires modes)"
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

  # Check custom.md specifically
  if [ -f "$skill_dir/modes/custom.md" ]; then
    pass "DR-D2b" "custom.md exists"
  else
    fail "DR-D2b" "Missing custom.md in modes/"
  fi

  # DR-D3: Mode Presets table in SKILL.md
  if grep -qi 'Mode Presets\|Mode.*Table\|mode.*selection\|Mode.*Description.*When' "$skill_dir/SKILL.md"; then
    pass "DR-D3" "Mode presets table found"
  else
    warn "DR-D3" "No mode presets table detected in SKILL.md"
  fi
}

# --- Check: Category E — Template Rules ---
check_templates() {
  local skill_dir="$1" name
  name=$(basename "$skill_dir")

  # Check assets/ exists
  if [ ! -d "$skill_dir/assets" ]; then
    # Not an error for all skills — lightweight may not have assets
    return 0
  fi

  # DR-I5: assets/ not empty
  local asset_count
  asset_count=$(find "$skill_dir/assets" -maxdepth 1 -type f | wc -l | tr -d ' ')
  if [ "$asset_count" -eq 0 ]; then
    warn "DR-I5" "assets/ directory is empty"
  fi

  # DR-E3: REQUEST implies RESPONSE
  local has_request has_response
  has_request=$(find "$skill_dir/assets" -name 'TEMPLATE_*_REQUEST.md' -maxdepth 1 | wc -l | tr -d ' ')
  has_response=$(find "$skill_dir/assets" -name 'TEMPLATE_*_RESPONSE.md' -maxdepth 1 | wc -l | tr -d ' ')

  if [ "$has_request" -gt 0 ]; then
    if [ "$has_response" -gt 0 ]; then
      pass "DR-E3" "REQUEST/RESPONSE templates paired"
    else
      warn "DR-E3" "Has REQUEST template but no RESPONSE template"
    fi
  fi
}

# --- Check: Category C — Phase Structure (protocol-tier only) ---
check_phases() {
  local skill_dir="$1" tier="$2" skill_file="$skill_dir/SKILL.md"
  [ "$tier" = "protocol" ] || return 0

  # DR-C1: Has phases JSON array
  if grep -q '"major"' "$skill_file" && grep -q '"minor"' "$skill_file"; then
    pass "DR-C1" "Phases JSON array present"
  else
    fail "DR-C1" "Missing phases JSON array (protocol-tier requires it)"
    return
  fi

  # DR-C2: Phase names in JSON match ## headers
  # Extract phase names from JSON (major.minor: name)
  local json_phases
  json_phases=$(awk '
    /"major"/ { gsub(/[^0-9]/, "", $0); major=$0 }
    /"minor"/ { gsub(/[^0-9]/, "", $0); minor=$0 }
    /"name"/ {
      gsub(/.*"name"[[:space:]]*:[[:space:]]*"/, "", $0)
      gsub(/".*/, "", $0)
      if (minor == 0) print major ". " $0
      else print major "." minor ". " $0
    }
  ' "$skill_file")

  # Extract ## N. headers from body (after frontmatter)
  local body_headers
  body_headers=$(awk '
    /^---$/ { n++; next }
    n >= 2 && /^## [0-9]/ {
      # Strip ## prefix and any trailing text decoration
      sub(/^## /, "", $0)
      # Normalize: extract "N. Name" or "N.M. Name"
      print
    }
  ' "$skill_file")

  # Compare: check each JSON phase has a corresponding header
  local mismatches=0
  while IFS= read -r phase_name; do
    if [ -z "$phase_name" ]; then continue; fi
    # Extract just the number prefix for matching (e.g., "1." or "4.1.")
    local num_prefix
    num_prefix=$(echo "$phase_name" | grep -o '^[0-9.]*\.')
    # Check if any header starts with this number
    if ! echo "$body_headers" | grep -q "^${num_prefix}"; then
      fail "DR-C2" "Phase '$phase_name' in JSON but no matching ## header"
      mismatches=$((mismatches + 1))
    fi
  done <<< "$json_phases"

  if [ "$mismatches" -eq 0 ]; then pass "DR-C2" "Phase JSON names match ## headers"; fi
}

# --- Check: Category G — Next Skill Options (protocol-tier) ---
check_next_skill_options() {
  local skill_dir="$1" tier="$2" skill_file="$skill_dir/SKILL.md"
  [ "$tier" = "protocol" ] || return 0

  # DR-G1: Has Next Skill Options section
  if ! grep -q 'Next Skill Options' "$skill_file"; then
    fail "DR-G1" "Missing Next Skill Options section"
    return
  fi
  pass "DR-G1" "Next Skill Options section present"

  # DR-G2: Exactly 4 options — count table rows with /skillname
  local option_count
  option_count=$(awk '
    /Next Skill Options/,/^---$|^##[^#]/ {
      if (/^\| [0-9]/) count++
    }
    END { print count+0 }
  ' "$skill_file")

  if [ "$option_count" -eq 4 ]; then
    pass "DR-G2" "Exactly 4 options listed"
  else
    fail "DR-G2" "Expected 4 options, found $option_count"
  fi

  # DR-G3: Each option references a valid skill
  local invalid_refs=""
  while IFS= read -r skill_ref; do
    if [ -z "$skill_ref" ]; then continue; fi
    # Strip leading /
    local ref_name="${skill_ref#/}"
    # Check if it's a known skill
    local found=0
    for known in "${ALL_SKILL_NAMES[@]}"; do
      if [ "$known" = "$ref_name" ]; then found=1; break; fi
    done
    if [ "$found" -eq 0 ]; then
      invalid_refs="${invalid_refs}/${ref_name} "
    fi
  done < <(awk '
    /Next Skill Options/,/^---$|^##[^#]/ {
      if (/^\|/) {
        match($0, /`\/[a-z-]+`/)
        if (RSTART > 0) {
          ref = substr($0, RSTART+1, RLENGTH-2)
          print ref
        }
      }
    }
  ' "$skill_file")

  if [ -z "$invalid_refs" ]; then
    pass "DR-G3" "All skill references are valid"
  else
    fail "DR-G3" "Invalid skill references: ${invalid_refs}"
  fi

  # DR-G4: First option marked (Recommended)
  if awk '/Next Skill Options/,/^---$|^##[^#]/ { if (/^\| 1/) print }' "$skill_file" | grep -qi 'recommended'; then
    pass "DR-G4" "First option marked (Recommended)"
  else
    warn "DR-G4" "First option not marked (Recommended)"
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

printf "${BOLD}Skill Doctor v1.0${NC} — Ecosystem Health Check\n"
printf "Engine: %s\n\n" "$ENGINE_SKILLS"

# --- Per-skill checks ---
for skill_dir in "$ENGINE_SKILLS"/*/; do
  [ -d "$skill_dir" ] || continue
  name=$(basename "$skill_dir")

  # Skip non-skill directories
  if [ "$name" = "node_modules" ]; then continue; fi

  SKILLS_CHECKED=$((SKILLS_CHECKED + 1))

  # Check SKILL.md exists first
  if [ ! -f "$skill_dir/SKILL.md" ]; then
    SKILL_HEADER=$(printf "${BOLD}=== %s (???)${NC} ===" "$name")
    fail "DR-I1" "Missing SKILL.md — skill directory exists but no protocol file"
    SKILL_HEADER=""
    continue
  fi

  # Extract tier
  tier=$(frontmatter_field "$skill_dir/SKILL.md" "tier")
  if [ -z "$tier" ]; then tier="unknown"; fi

  SKILL_HEADER=$(printf "${BOLD}=== %s (%s) ===${NC}" "$name" "$tier")
  if [ "$VERBOSE" -eq 1 ]; then printf "%s\n" "$SKILL_HEADER"; SKILL_HEADER=""; fi

  check_frontmatter "$skill_dir"
  check_boot "$skill_dir"
  check_modes "$skill_dir" "$tier"
  check_templates "$skill_dir"
  check_phases "$skill_dir" "$tier"
  check_next_skill_options "$skill_dir" "$tier"
  check_cross_skill "$skill_dir"
  if [ "$VERBOSE" -eq 1 ]; then echo; fi
  SKILL_HEADER=""
done

# --- Also check local skills (e.g., ~/.claude/skills/fleet) ---
if [ -d "$LOCAL_SKILLS" ] && [ "$LOCAL_SKILLS" != "$ENGINE_SKILLS" ]; then
  for skill_dir in "$LOCAL_SKILLS"/*/; do
    [ -d "$skill_dir" ] || continue
    name=$(basename "$skill_dir")
    # Skip if already checked in engine
    if [ -d "$ENGINE_SKILLS/$name" ]; then continue; fi
    if [ ! -f "$skill_dir/SKILL.md" ]; then continue; fi

    SKILLS_CHECKED=$((SKILLS_CHECKED + 1))

    tier=$(frontmatter_field "$skill_dir/SKILL.md" "tier")
    if [ -z "$tier" ]; then tier="unknown"; fi

    SKILL_HEADER=$(printf "${BOLD}=== %s (%s) [local] ===${NC}" "$name" "$tier")
    if [ "$VERBOSE" -eq 1 ]; then printf "%s\n" "$SKILL_HEADER"; SKILL_HEADER=""; fi

    check_frontmatter "$skill_dir"
    check_boot "$skill_dir"
    check_modes "$skill_dir" "$tier"
    check_templates "$skill_dir"
    check_phases "$skill_dir" "$tier"
    check_next_skill_options "$skill_dir" "$tier"
    check_cross_skill "$skill_dir"
    if [ "$VERBOSE" -eq 1 ]; then echo; fi
    SKILL_HEADER=""
  done
fi

# --- Skills-level directives check ---
SKILL_HEADER=$(printf "${BOLD}=== Engine-Level Directives ===${NC}")
if [ "$VERBOSE" -eq 1 ]; then printf "%s\n" "$SKILL_HEADER"; SKILL_HEADER=""; fi
for directive in CHECKLIST.md PITFALLS.md TESTING.md; do
  if [ -f "$ENGINE_SKILLS/$directive" ]; then
    pass "DR-I2" "$directive exists"
  else
    warn "DR-I2" "Missing $directive at skills root"
  fi
done
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
