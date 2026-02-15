# Checklist — Skill Quality Gates

Pre-flight checks when creating or modifying skills in `engine/skills/`.

## Structure

- [ ] I DID create or modify SKILL.md
  - [ ] YAML frontmatter has `name`, `description`, `version`, `tier`
  - [ ] Boot sector (`§CMD_EXECUTE_SKILL_PHASES`) present at top (protocol-tier)
  - [ ] JSON manifest block is valid and passes `skill-manifest.json` schema
  - [ ] `assets/` directory exists with log and debrief templates
  - [ ] Phase labels in JSON match `## N.` section headers
- [ ] I DID NOT create or modify SKILL.md
  - [ ] Confirmed changes don't affect skill structure

## Modes

- [ ] I DID create or modify mode files
  - [ ] `modes/` directory has 3 named modes + custom
  - [ ] Each mode file has Role, Goal, Mindset, and Approach sections
  - [ ] No mode file references another mode file (must be self-contained)
- [ ] I DID NOT create or modify mode files
  - [ ] Confirmed no mode changes needed

## Protocol Compliance

- [ ] I DID modify protocol phases
  - [ ] Every major phase has `§CMD_REPORT_INTENT` and `§CMD_EXECUTE_PHASE_STEPS`
  - [ ] Phase transitions use `§CMD_GATE_PHASE` (not bare text gates)
  - [ ] Synthesis phases include `§CMD_RUN_SYNTHESIS_PIPELINE` and `§CMD_CLOSE_SESSION`
  - [ ] All `§CMD_*` step references resolve to CMD files or COMMANDS.md
  - [ ] `nextSkills` array references valid skill directories
- [ ] I DID NOT modify protocol phases
  - [ ] Confirmed phase structure unchanged

## Templates

- [ ] I DID create or modify templates
  - [ ] Log template schemas match the log types used in the Operation phase
  - [ ] Debrief template has `**Tags**: #needs-review` on line 2
  - [ ] Plan template (if applicable) has `**Depends**:` and `**Files**:` fields per operation
  - [ ] Request/Response templates exist if the skill supports delegation (`¶INV_DELEGATION_VIA_TEMPLATES`)
- [ ] I DID NOT create or modify templates
  - [ ] Confirmed no template changes needed

## Cross-Cutting

- [ ] I DID add or modify `§CMD_*` / `¶INV_*` references
  - [ ] All references use backtick formatting
  - [ ] No hardcoded paths — use `~/.claude/` prefix for shared engine files
- [ ] I DID NOT add or modify references
  - [ ] Confirmed no reference changes needed

## Automated Validation

- [ ] I DID run `engine doctor`
  - [ ] Exit code 0 (no FAILs) — or all FAILs are pre-existing
  - [ ] All FAIL results addressed (SK-A through SK-G for skills, CM-* for CMDs, SG-* for sigils)
  - [ ] WARN results reviewed (acceptable WARNs documented in commit message)
  - [ ] New skills appear in doctor output with correct tier classification
  - [ ] JSON schema validation passes for modified skills (SK-C2)
- [ ] I DID NOT run `engine doctor`
  - [ ] Changes are minor enough to skip automated validation
