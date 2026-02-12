# [DIRECTORY_NAME] File Templates

<!-- Scaffolding for new files in this directory and (optionally) subdirectories. -->
<!-- Agents use this when creating new source files to ensure consistent structure. -->
<!-- A single TEMPLATE.md can host multiple templates (e.g., code + test). -->

## Scope

<!-- Does this template apply to subdirectories too, or just this directory? -->
**Applies to**: This directory and all subdirectories
<!-- OR: **Applies to**: This directory only (subdirectories have their own TEMPLATE.md) -->

## [File Type] Template

<!-- Code template with placeholders. Show the expected structure for new files of this type. -->

```typescript
/**
 * [Description of what this module does]
 *
 * @see ¶INV_RELEVANT_INVARIANT
 */

import { SharedType } from '@finch/shared';

// --- Types ---

export interface [Name]Config {
  /** [Field description] */
  fieldName: string;
}

// --- Implementation ---

export function [name](config: [Name]Config): Result {
  // Implementation
}
```

## Test Template

<!-- Companion test template — shown alongside the code template -->

```typescript
import { describe, it, expect } from 'vitest';
import { [name] } from '../[module]';

describe('[name]', () => {
  it('should [expected behavior]', () => {
    const result = [name]({ /* config */ });
    expect(result).toEqual(/* expected */);
  });

  it('should handle [edge case]', () => {
    // Edge case test
  });
});
```

## Conventions

<!-- Naming, import, and structural conventions for new files -->
- File naming: `[feature-name].ts` (kebab-case for files, camelCase for exports)
- Tests: `__tests__/[feature-name].test.ts` (mirror source structure)
- Exports: Add to barrel file (`index.ts`) if public

## Example: Schema Package TEMPLATE.md

A good TEMPLATE.md for a schema-heavy directory:
- Zod schema template with `.describe()` on every field, `.strict()` on objects
- Companion test template showing parse/safeParse patterns
- Export convention: add to `schemas/index.ts`
- Scope: applies to `src/schemas/` and subdirectories
