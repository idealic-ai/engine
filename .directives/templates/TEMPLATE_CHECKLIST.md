# [PACKAGE_NAME] Checklist

<!-- Pre-close verification items. Agents MUST evaluate these before finishing work. -->
<!-- This file blocks session deactivation (¶INV_CHECKLIST_BEFORE_CLOSE). -->
<!-- Only enforced when the active skill declares CHECKLIST.md in its directives array. -->
<!-- Uses branching DID/DID NOT format: check exactly one branch per category, then all its children. -->

## Code Quality

- [ ] I DID add new public functions/types
  - [ ] All are exported from the barrel file
  - [ ] No `any` types introduced (use `unknown` + narrowing)
  - [ ] No dead code or commented-out blocks
- [ ] I DID NOT add new public functions/types
  - [ ] Confirmed no new exports needed

## Schema Quality

<!-- Adapt this section to your package's domain -->
- [ ] I DID modify schemas
  - [ ] All fields have `.describe()` with clear instructions
  - [ ] Objects use `.strict()` to prevent extra fields
  - [ ] Complex types use `.nullable()` not `.optional()`
- [ ] I DID NOT modify schemas
  - [ ] Confirmed no schema changes needed

## Testing

- [ ] I DID write or modify tests
  - [ ] Edge cases covered (null, empty, boundary values)
  - [ ] Tests pass locally: `yarn workspace [PACKAGE] test`
- [ ] I DID NOT write or modify tests
  - [ ] Confirmed existing tests cover the changes
  - [ ] No new code paths were introduced

## Naming

- [ ] I DID introduce new identifiers
  - [ ] All use camelCase (`¶INV_CAMELCASE_EVERYWHERE`)
  - [ ] Names are descriptive, not abbreviated
- [ ] I DID NOT introduce new identifiers
  - [ ] Confirmed no naming review needed

## Branching Format Guide

<!-- Delete this section when creating a real checklist -->
Each category uses the DID / DID NOT branching pattern:
- Check exactly ONE branch parent per category (`[x]`)
- Check ALL children under the checked parent
- Leave the other branch and its children unchecked
- Validation: `engine session check` enforces one parent checked, all children under it checked
- ~15-25 items across all categories — enough to catch real issues, not so many that it's ignored
- Items reference invariants where applicable (e.g., `¶INV_CAMELCASE_EVERYWHERE`)
