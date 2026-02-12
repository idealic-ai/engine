# [PACKAGE_NAME] Testing Guide

## Test Location

<!-- Where tests live relative to source -->
Tests live in: `src/**/__tests__/*.test.ts`

## Running Tests

```bash
yarn workspace [PACKAGE_NAME] test           # Run all tests
yarn workspace [PACKAGE_NAME] test:watch     # Watch mode
yarn workspace [PACKAGE_NAME] test -- --grep "pattern"  # Filter
```

## Coverage Requirements

<!-- What must be tested — adapt to your domain -->
- All public functions must have unit tests
- Edge cases: null inputs, empty collections, boundary values
- Error paths: invalid inputs, network failures, timeouts

## Test Patterns

<!-- Common patterns used in this package's tests -->
- **Unit tests**: Pure function in → assert out. No mocks needed.
- **Schema tests**: `schema.parse(valid)` succeeds, `schema.safeParse(invalid)` returns error
- **Integration tests**: Test across module boundaries with real dependencies

## Fixtures & Mocks

<!-- Where test data lives, how to construct it -->
- Fixtures in `src/__tests__/fixtures/`
- Use factory functions for complex test data (never `as` casts)
- Shared factories in `src/__tests__/factories/`

## Edge Cases to Cover

<!-- Domain-specific edge cases agents should test -->
- Empty arrays vs null (different semantics)
- Missing optional fields
- Unicode in text fields
- Concurrent operations (if applicable)

## Example: @finch/estimate TESTING.md

A good testing guide:
- Test location pattern, run commands, coverage requirements
- Test patterns grouped by type (unit, schema, integration, snapshot)
- Fixtures and mocks section with location + construction rules
- Edge cases checklist specific to the package's domain
- ~25-35 lines — practical reference, not a testing textbook
