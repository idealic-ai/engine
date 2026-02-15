# Contributing — Skills

Quality gates and tooling for creating or modifying skills in `engine/skills/`.

## Skill Doctor

Run the engine doctor before shipping any skill changes:

```bash
engine doctor              # quiet — shows only WARN/FAIL
engine doctor -v           # verbose — shows all checks including PASS
engine doctor <dir>        # target a specific directory (auto-detects type)
```

The doctor validates 6 check categories across the entire engine ecosystem: installation, skills (DR-A through DR-I), CMD files, directives, sessions, and sigil cross-references. It is tier-aware: protocol-tier skills get full checks (manifest, modes, phases, protocol completeness), while utility/lightweight skills get basic structural checks only.

### Check Categories

| Category | What it checks |
|----------|---------------|
| DR-A | YAML frontmatter (fields, tier enum, name match) |
| DR-B | Boot sector, deprecated blocks, directive paths |
| DR-C | JSON manifest schema, phase headers, `§CMD_*` cross-references |
| DR-D | Mode files (count, custom.md, JSON-to-disk match) |
| DR-E | Templates (REQUEST/RESPONSE pairing, manifest paths) |
| DR-F | Protocol completeness (REPORT_INTENT, EXECUTE_PHASE_STEPS, synthesis) |
| DR-G | nextSkills (present, valid references) |
| DR-I | Cross-skill (SKILL.md exists, .directives/) |

### Result Levels

*   **PASS**: Check passed
*   **WARN**: Non-critical issue (e.g., missing optional `§CMD_PRESENT_NEXT_STEPS`)
*   **FAIL**: Structural defect that must be fixed
*   **Exit code**: 0 if no FAILs, 1 if any FAIL detected

## JSON Schema Validation

Protocol-tier skills must include a JSON manifest block that passes `skill-manifest.json` schema validation. The schema lives at:

```
engine/tools/json-schema-validate/schemas/skill-manifest.json
```

Required fields: `taskType`, `phases` (with `label`, `name`, `steps`, `commands` per phase), `nextSkills`. Optional: `directives`, `modes`, template paths.

## Skill Tiers

| Tier | Characteristics | Doctor Checks |
|------|----------------|---------------|
| `protocol` | Full session lifecycle, phases, modes, synthesis | All categories (DR-A through DR-I) |
| `lightweight` | Session-aware but no phases/modes | DR-A, DR-B, DR-I |
| `utility` | Sessionless, no logging | DR-A, DR-B, DR-I |
| `suggest` | Auto-suggested by hooks | DR-A, DR-B, DR-I |
