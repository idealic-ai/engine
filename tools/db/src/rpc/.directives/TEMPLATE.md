# RPC Handler Template

Every RPC handler file follows this structure. Use this as a scaffold when creating new handlers.

## File-Level JSDoc (Required)

```typescript
/**
 * db.{namespace}.{verb} — {One-line purpose}.
 *
 * {2-3 sentences explaining WHY this RPC exists, not WHAT the code does.
 * The code is self-explanatory — the JSDoc explains the design intent.}
 *
 * {Lifecycle position: where does this RPC sit in the entity lifecycle?
 * What must happen before it? What happens after?}
 *
 * {Key design decisions: idempotency behavior, guard conditions, side effects,
 * invariants it enforces (reference by name, e.g., INV_DAEMON_IS_THE_LOCK).}
 *
 * Callers: {who calls this — bash compound commands, other RPCs, hooks}.
 */
```

## JSDoc Checklist

Every RPC file-level JSDoc MUST answer these 4 questions:

*   **Why**: Why does this RPC exist? What problem does it solve?
*   **Where**: Where in the lifecycle does it sit? (creation → active → finished)
*   **What**: What are the non-obvious behaviors? (idempotency, guards, side effects)
*   **Who**: Who calls it? (bash compound command, hook, other RPC)

## Section Comments (For Complex Handlers)

When a handler has distinct logic blocks (>50 lines), add section comments:

```typescript
// ── Section Name ─────────────────────────────────────────
// 2-3 lines explaining the algorithm or design decision.
// Reference invariants by name when relevant.
```

## File Structure (Strict)

```typescript
/**
 * db.{namespace}.{verb} — {purpose}.
 * {JSDoc body}
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";
import { /* helpers */ } from "./row-helpers.js";

const schema = z.object({ /* Zod schema */ });

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  // Implementation
}

registerCommand("db.{namespace}.{verb}", { schema, handler });
```

## Naming Convention

*   **File**: `db-{namespace}-{verb}.ts` (kebab-case)
*   **RPC command**: `db.{namespace}.{verb}` (dot-separated)
*   **Registration**: always the last line of the file
*   **Registry**: add import to `registry.ts`
