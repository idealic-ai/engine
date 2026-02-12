# [PACKAGE_NAME] Checklist

<!-- Pre-close verification items. Agents MUST evaluate these before finishing work. -->
<!-- This file blocks session deactivation (¶INV_CHECKLIST_BEFORE_CLOSE). -->
<!-- Use checkbox format: - [ ] Item description -->
<!-- Group by category for readability. -->

## Code Quality

- [ ] All new public functions/types are exported from the barrel file
- [ ] No `any` types introduced (use `unknown` + narrowing)
- [ ] No dead code or commented-out blocks

## Schema Quality

<!-- Adapt this section to your package's domain -->
- [ ] All fields have `.describe()` with clear instructions
- [ ] Objects use `.strict()` to prevent extra fields
- [ ] Complex types use `.nullable()` not `.optional()`

## Testing

- [ ] New code has corresponding tests
- [ ] Edge cases covered (null, empty, boundary values)
- [ ] Tests pass locally: `yarn workspace [PACKAGE] test`

## Naming

- [ ] All identifiers use camelCase (¶INV_CAMELCASE_EVERYWHERE)
- [ ] Variable/function names are descriptive, not abbreviated

## Example: @finch/estimate CHECKLIST.md

A good checklist:
- Categories: Schema Quality, Naming, Testing, Exports
- Each item is a concrete, verifiable action (not vague guidance)
- ~15-25 items — enough to catch real issues, not so many that it's ignored
- Items reference invariants where applicable (e.g., ¶INV_CAMELCASE_EVERYWHERE)
