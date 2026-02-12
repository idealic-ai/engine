# [PACKAGE_NAME]

<!-- 1-2 sentence description: what this package/directory does and why it exists -->

## Key Types

<!-- Core types table — what agents need to know to read/write code here -->

| Type | Description |
|------|-------------|
| `ExampleType` | What it represents and when it's used |
| `ExampleConfig` | Configuration shape and key fields |

## Directory Structure

<!-- Where things live — key subdirectories and their roles -->

```
src/
├── lib/          # Core logic
├── schemas/      # Zod schemas (if applicable)
├── __tests__/    # Tests alongside source
└── index.ts      # Public exports
```

## Available Directives

<!-- List other .directives/ files in this directory — helps agents find rules, tests, checklists -->

| Directive | What it covers |
|-----------|---------------|
| `INVARIANTS.md` | Package-specific rules (e.g., schema constraints) |
| `TESTING.md` | Test patterns, fixtures, coverage goals |
| `CHECKLIST.md` | Pre-close verification items |

## Commands

```bash
# Build, test, dev — adapt to your package manager
yarn workspace [PACKAGE_NAME] build
yarn workspace [PACKAGE_NAME] test
```

## Example: @finch/estimate AGENTS.md

A good AGENTS.md for a schema-heavy package:
- Opens with package purpose (1 line)
- Shows the Type + Namespace import pattern
- Core Types table grouped by domain concept
- Pipeline diagram showing data flow
- Key Exports table with module + description
- Docs section linking to architecture/implementation docs
