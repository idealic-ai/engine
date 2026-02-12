# Checklist — Skill Quality Gates

Pre-flight checks when creating or modifying skills in `engine/skills/`.

### Structure
- [ ] SKILL.md has YAML frontmatter with `name`, `description`, `version`, `tier`
- [ ] SKILL.md has Boot Sequence block (load standards, guard, gate check)
- [ ] `assets/` directory exists with at minimum `TEMPLATE_*_LOG.md` and `TEMPLATE_*.md` (debrief)
- [ ] `modes/` directory exists with 3 named modes + custom (if modal skill)
- [ ] Phases array is declared for `§CMD_PARSE_PARAMETERS` (protocol-tier skills)

### Protocol Compliance
- [ ] Every phase has `§CMD_REPORT_INTENT_TO_USER` intent block
- [ ] Every phase has `§CMD_VERIFY_PHASE_EXIT` proof block
- [ ] Phase transitions use `AskUserQuestion` (not bare text gates)
- [ ] Synthesis phase calls steps in order: checklists, debrief, directives, artifacts, summary
- [ ] Next Skill Options section defines exactly 4 options for `§CMD_CLOSE_SESSION`

### Templates
- [ ] Log template schemas match the log types used in the Operation phase
- [ ] Debrief template has `**Tags**: #needs-review` on line 2
- [ ] Plan template (if applicable) has `**Depends**:` and `**Files**:` fields per operation
- [ ] Request/Response templates exist if the skill supports delegation (`¶INV_DELEGATION_VIA_TEMPLATES`)

### Cross-Cutting
- [ ] All `§CMD_*` and `¶INV_*` references use backtick formatting
- [ ] No hardcoded paths — use `~/.claude/` prefix for shared engine files
- [ ] Mode files define Role, Goal, Mindset, and Approach sections
- [ ] Interrogation phase (if present) has depth selection and exit gate

### Automated Validation
- [ ] Run `engine skill-doctor` — exit code 0 (no FAILs)
- [ ] All FAIL results addressed (DR-A through DR-I rule categories)
- [ ] WARN results reviewed (acceptable WARNs documented in commit message)
- [ ] New skills appear in doctor output with correct tier classification
