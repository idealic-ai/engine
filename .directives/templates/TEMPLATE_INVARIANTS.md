# [PACKAGE_NAME] Invariants

<!-- Rules that must always hold when working in this directory. -->
<!-- Use ¶INV_ prefix for each invariant. Format: Name → Rule → Reason. -->
<!-- These extend (never replace) the shared invariants in ~/.claude/.directives/INVARIANTS.md -->

## Must Do

- **¶INV_EXAMPLE_NAME**: One-line rule summary
  - *Rule*: Detailed explanation of what must be done and when
  - *Reason*: Why this matters — what breaks if violated

- **¶INV_ANOTHER_RULE**: One-line rule summary
  - *Rule*: Detailed explanation
  - *Reason*: Consequence of violation

## Must Not Do

- **No [anti-pattern]**: What to avoid
  - *Why*: What goes wrong if you do this
  - *Alternative*: What to do instead

## Patterns to Follow

<!-- Recurring conventions specific to this package -->
- Pattern description → when to apply it
- Another pattern → its scope

## Example: @finch/estimate INVARIANTS.md

A good package INVARIANTS.md:
- Groups into "Must Do" (positive rules) and "Must Not Do" (prohibitions)
- Each invariant: `¶INV_NAME` prefix, one-line summary, detailed Rule, Reason
- "Patterns to Follow" section for conventions that aren't strict rules
- "Anti-Patterns to Avoid" for common mistakes
- ~20-40 lines — tight, scannable, every line carries information
