# [PACKAGE_NAME] Architecture

<!-- System overview for agents making structural or cross-cutting changes. -->
<!-- Focus on connections, data flow, and design decisions — not implementation details. -->

## Structure

<!-- Package/directory organization and roles -->

- **`module-a/`**
  Location: `src/module-a/`
  Role: What this module does

- **`module-b/`**
  Location: `src/module-b/`
  Role: What this module does

- **`shared/`**
  Location: `src/shared/`
  Role: Shared utilities and types

## Data Flow

<!-- How data moves through the system — inputs, transformations, outputs -->

```
Input (e.g., API request, file upload)
  → Step 1: [transformation] (module-a)
  → Step 2: [transformation] (module-b)
  → Output (e.g., database write, API response)
```

## Key Design Decisions

<!-- Architectural choices and their rationale -->

- **Decision**: What was chosen (e.g., "Event-driven over request-response")
  - *Why*: Rationale (e.g., "Decouples producers from consumers")
  - *Trade-off*: What was sacrificed (e.g., "Eventual consistency instead of immediate")

## Integration Points

<!-- How this component connects to others -->

- **Upstream**: Who calls this / provides data
- **Downstream**: Who this calls / sends data to
- **External**: Third-party services, APIs, databases

## Example: Root ARCHITECTURE.md

A good architecture doc:
- Monorepo structure table: package name, role, key patterns
- Data flow diagram showing pipeline stages
- Key design decisions with rationale and trade-offs
- Integration points: upstream, downstream, external services
- ~30-50 lines — structural map, not implementation manual
