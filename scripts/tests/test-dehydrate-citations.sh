#!/bin/bash
# test-dehydrate-citations.sh — the checks that make /dehydrate's design premise falsifiable.
#
# /dehydrate deliberately CITES rules it does not restate (HANDOFF.md's hand-over sequence,
# TEMPLATE_LOOM_INHERITANCE.md's address, §CMD_DEHYDRATE's JSON shape). A citation that no
# longer resolves is the one failure mode that design buys, and nothing else in the engine
# reddens on it. These arms do.
#
# DECLARED BOUNDARY (¶INV_A_NEGATIVE_ONLY_CHECK_SAYS_SO): the citation arm reads only paths
# rooted at the engine's own top-level directories — skills/, .directives/, scripts/.
# Session-relative paths the skill names (builds/sweep-findings.md, "$SESSION_DIR"/LOOM_LOG.md)
# are NOT checked, because they exist only inside a live session. A clean citation arm is a
# claim about engine-rooted paths and nothing more.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENGINE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL="$ENGINE_DIR/skills/dehydrate/SKILL.md"

# Files used as positive controls. Neither was written by the lane that wrote the skill, so a
# control firing on one is a reading of the instrument rather than a confirmation of an edit
# (¶INV_A_CONTROL_DRAWN_FROM_WHAT_YOU_JUST_FIXED_IS_NOT_A_CONTROL).
CONTROL_TABLES="$ENGINE_DIR/skills/session/SKILL.md"
CONTROL_SCHEMA="$ENGINE_DIR/.directives/commands/CMD_DEHYDRATE.md"

extract_engine_paths() {
  grep -oE '`(skills|\.directives|scripts)/[A-Za-z0-9._/-]+\.(md|sh|json)`' "$1" \
    | tr -d '`' | sort -u
}

extract_sigils() {
  grep -oE '[¶§](CMD|INV|PTF)_[A-Z0-9_]+' "$1" | sed 's/^.//' | sort -u
}

count_md_tables() {
  grep -cE '^\|' "$1" || true
}

# ------------------------------------------------------------
test_skill_exists() {
  if [ -f "$SKILL" ]; then
    pass "skills/dehydrate/SKILL.md exists"
  else
    fail "skills/dehydrate/SKILL.md exists" "a file" "nothing at $SKILL"
    return
  fi
  if grep -q '^tier: lightweight$' "$SKILL"; then
    pass "declares tier: lightweight (a sessionless utility, like /sweep and /session)"
  else
    fail "declares tier: lightweight" "tier: lightweight" "$(grep -m1 '^tier:' "$SKILL")"
  fi
}

# ------------------------------------------------------------
# Arm 1 — every engine-rooted path the skill cites resolves.
test_cited_paths_resolve() {
  local found=0 broken=0 p
  while read -r p; do
    [ -z "$p" ] && continue
    found=$((found + 1))
    [ -e "$ENGINE_DIR/$p" ] || { echo "  broken citation: $p"; broken=$((broken + 1)); }
  done < <(extract_engine_paths "$SKILL")

  if [ "$found" -eq 0 ]; then
    fail "the extractor found engine-rooted citations to check" "at least one" "none — extractor is dead"
    return
  fi
  if [ "$broken" -eq 0 ]; then
    pass "every engine-rooted path /dehydrate cites resolves (checked $found)"
  else
    fail "every engine-rooted path /dehydrate cites resolves" "0 broken" "$broken broken of $found"
  fi
}

# Control for arm 1: the existence assertion must be able to go red.
test_cited_paths_control() {
  local tmp; tmp=$(mktemp)
  { cat "$SKILL"; echo 'A citation that cannot resolve: `skills/no-such-skill/SKILL.md`'; } > "$tmp"
  local broken=0 p
  while read -r p; do
    [ -e "$ENGINE_DIR/$p" ] || broken=$((broken + 1))
  done < <(extract_engine_paths "$tmp")
  rm -f "$tmp"
  if [ "$broken" -ge 1 ]; then
    pass "control: arm 1 flags an injected non-existent engine path"
  else
    fail "control: arm 1 flags an injected non-existent engine path" ">=1 broken" "$broken"
  fi
}

# Control for arm 1's extractor: it finds citations in a file this lane did not write.
test_extractor_control() {
  local n; n=$(extract_engine_paths "$ENGINE_DIR/.directives/HANDOFF.md" | wc -l | tr -d ' ')
  if [ "$n" -ge 1 ]; then
    pass "control: the path extractor finds engine citations in HANDOFF.md ($n)"
  else
    fail "control: the path extractor finds engine citations in HANDOFF.md" ">=1" "$n"
  fi
}

# ------------------------------------------------------------
# Arm 2 — every sigil the skill cites is defined somewhere in the engine's directives.
test_cited_sigils_defined() {
  local found=0 undefined=0 s
  while read -r s; do
    [ -z "$s" ] && continue
    found=$((found + 1))
    grep -rqlE "[¶§]$s\b" "$ENGINE_DIR/.directives/" 2>/dev/null \
      || { echo "  undefined sigil: $s"; undefined=$((undefined + 1)); }
  done < <(extract_sigils "$SKILL")

  if [ "$found" -eq 0 ]; then
    fail "the extractor found sigils to check" "at least one" "none — extractor is dead"
    return
  fi
  if [ "$undefined" -eq 0 ]; then
    pass "every sigil /dehydrate cites appears in .directives/ (checked $found)"
  else
    fail "every sigil /dehydrate cites appears in .directives/" "0 undefined" "$undefined of $found"
  fi
}

test_cited_sigils_control() {
  local tmp; tmp=$(mktemp)
  { cat "$SKILL"; echo 'An invented rule: §INV_THIS_SIGIL_IS_NOT_DEFINED_ANYWHERE'; } > "$tmp"
  local undefined=0 s
  while read -r s; do
    grep -rqlE "[¶§]$s\b" "$ENGINE_DIR/.directives/" 2>/dev/null || undefined=$((undefined + 1))
  done < <(extract_sigils "$tmp")
  rm -f "$tmp"
  if [ "$undefined" -ge 1 ]; then
    pass "control: arm 2 flags an invented sigil"
  else
    fail "control: arm 2 flags an invented sigil" ">=1 undefined" "$undefined"
  fi
}

# ------------------------------------------------------------
# Arm 3 — the mechanical half of the sweep is invocable. The skill's loom branch runs it.
test_sweep_check_present() {
  if [ -x "$ENGINE_DIR/scripts/sweep-check.sh" ]; then
    pass "scripts/sweep-check.sh is present and executable"
  else
    fail "scripts/sweep-check.sh is present and executable" "an executable" "missing or not +x"
  fi
}

# ------------------------------------------------------------
# Arm 4 — ¶INV_LISTS_INSTEAD_OF_TABLES.
test_no_markdown_tables() {
  local n; n=$(count_md_tables "$SKILL")
  if [ "$n" -eq 0 ]; then
    pass "no markdown tables in the skill (¶INV_LISTS_INSTEAD_OF_TABLES)"
  else
    fail "no markdown tables in the skill" "0 table rows" "$n"
  fi
}

test_no_markdown_tables_control() {
  local n; n=$(count_md_tables "$CONTROL_TABLES")
  if [ "$n" -ge 1 ]; then
    pass "control: the table pattern fires on skills/session/SKILL.md ($n rows)"
  else
    skip "control: the table pattern fires on a file with tables" "session/SKILL.md no longer has any — pick another control"
  fi
}

# ------------------------------------------------------------
# Arm 5 — the atom is composed, not copied. A duplicated JSON schema here is the defect.
test_atom_not_duplicated() {
  local hits
  hits=$(grep -cE '"(summary|lastAction|nextSteps|requiredFiles)":[[:space:]]*\{|maxItems' "$SKILL" || true)
  if [ "$hits" -eq 0 ]; then
    pass "no copy of the atom's JSON schema in the skill (composed, not copied)"
  else
    fail "no copy of the atom's JSON schema in the skill" "0" "$hits schema-shaped lines"
  fi
  if grep -q '§CMD_DEHYDRATE' "$SKILL"; then
    pass "the skill invokes §CMD_DEHYDRATE rather than reimplementing it"
  else
    fail "the skill invokes §CMD_DEHYDRATE" "a reference" "none"
  fi
}

test_atom_not_duplicated_control() {
  local hits
  hits=$(grep -cE '"(summary|lastAction|nextSteps|requiredFiles)":[[:space:]]*\{|maxItems' "$CONTROL_SCHEMA" || true)
  if [ "$hits" -ge 1 ]; then
    pass "control: the schema pattern fires on CMD_DEHYDRATE.md, which owns the schema ($hits)"
  else
    fail "control: the schema pattern fires on CMD_DEHYDRATE.md" ">=1" "$hits"
  fi
}

# ------------------------------------------------------------
# Arm 6 — the atom is LAST. Nothing in the protocol follows its invocation.
test_atom_is_last() {
  local atom_line last_heading
  atom_line=$(grep -nE '^## .*§CMD_DEHYDRATE' "$SKILL" | tail -1 | cut -d: -f1)
  last_heading=$(grep -nE '^## ' "$SKILL" | tail -1 | cut -d: -f1)
  if [ -z "$atom_line" ]; then
    fail "the atom has its own final phase heading" "a '## ' heading naming §CMD_DEHYDRATE" "none"
    return
  fi
  if [ "$atom_line" = "$last_heading" ]; then
    pass "the §CMD_DEHYDRATE phase is the skill's last phase (it kills the process)"
  else
    fail "the §CMD_DEHYDRATE phase is the skill's last phase" "L$last_heading" "atom at L$atom_line"
  fi
}

# ------------------------------------------------------------
# Arm 7 — the trap the brief named, re-asserted as a check: nothing in the skill tells a
# reader to read sessionDir out of .state.json, because that key is absent on a live session.
#
# Read the EXECUTABLE shape, not the vocabulary: the skill legitimately WARNS about sessionDir
# in prose, and a pattern that cannot tell a warning from an instruction counts the warning as
# the defect (the inverse of ¶PTF_AUDITING_A_STRUCTURAL_ELEMENT_BY_ITS_VOCABULARY_COUNTS_PROSE_AS_COMPLIANCE).
# The defect is a `jq` invocation that selects .sessionDir, so that is what this reads.
jq_lines_selecting_sessiondir() {
  grep -cE 'jq[^#]*sessionDir' "$1" || true
}

test_no_sessiondir_state_read() {
  local n; n=$(jq_lines_selecting_sessiondir "$SKILL")
  if [ "$n" -eq 0 ]; then
    pass "no jq invocation in the skill selects .sessionDir (it is absent on a live session)"
  else
    fail "no jq invocation in the skill selects .sessionDir" "0" "$n"
  fi
  if grep -q 'engine session find' "$SKILL"; then
    pass "the skill names engine session find as the resolver"
  else
    fail "the skill names engine session find as the resolver" "a reference" "none"
  fi
}

test_no_sessiondir_state_read_control() {
  local tmp n
  tmp=$(mktemp)
  { cat "$SKILL"; echo 'SESSION_DIR=$(jq -r ".sessionDir" "$STATE")'; } > "$tmp"
  n=$(jq_lines_selecting_sessiondir "$tmp")
  rm -f "$tmp"
  if [ "$n" -ge 1 ]; then
    pass "control: arm 7 flags an injected jq read of .sessionDir"
  else
    fail "control: arm 7 flags an injected jq read of .sessionDir" ">=1" "$n"
  fi
}

# ------------------------------------------------------------
run_discovered_tests
