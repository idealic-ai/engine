# Checklist — Skill Quality Gates

Pre-flight checks when creating or modifying skills in `engine/skills/`.

## Structure

- [ ] I DID create or modify SKILL.md
  - [ ] YAML frontmatter has `name`, `description`, `version`, `tier`
  - [ ] Boot Sequence block is present (load standards, guard, gate check)
  - [ ] `assets/` directory exists with `TEMPLATE_*_LOG.md` and `TEMPLATE_*.md` (debrief)
  - [ ] Phases array is declared for `§CMD_PARSE_PARAMETERS` (protocol-tier skills)
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
  - [ ] Every phase has `§CMD_REPORT_INTENT_TO_USER` intent block
  - [ ] Phase transitions use `AskUserQuestion` (not bare text gates)
  - [ ] Synthesis phase calls steps in order: checklists, debrief, directives, artifacts, summary
  - [ ] Next Skill Options section defines exactly 4 options for `§CMD_CLOSE_SESSION`
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

- [ ] I DID run `engine skill-doctor`
  - [ ] Exit code 0 (no FAILs)
  - [ ] All FAIL results addressed (DR-A through DR-I rule categories)
  - [ ] WARN results reviewed (acceptable WARNs documented in commit message)
  - [ ] New skills appear in doctor output with correct tier classification
- [ ] I DID NOT run `engine skill-doctor`
  - [ ] Changes are minor enough to skip automated validation
