# Contributing -- Hook RPC Handlers

How to add or modify hook RPC handlers in `src/rpc/`.

## Adding a New Handler

### 1. Create the handler file

Create `src/rpc/hooks-<event-name>.ts`. Use an existing implemented handler (e.g., `hooks-pre-tool-use.ts`) as a template.

### 2. Define the input schema with `hookSchema()`

Import from `hook-base-schema.ts` and extend with event-specific fields:

```ts
import { z } from "zod/v4";
import { hookSchema } from "./hook-base-schema.js";

const schema = hookSchema({
  toolName: z.string(),
  toolInput: z.record(z.string(), z.unknown()),
  toolUseId: z.string(),
});
```

`hookSchema()` automatically includes the 5 common fields (`sessionId`, `transcriptPath`, `cwd`, `permissionMode`, `hookEventName`) and applies snake_case-to-camelCase transformation. You only declare the event-specific fields.

### 3. Resolve engine IDs inside the handler

Engine IDs (projectId, effortId, engineSessionId) are never accepted as input. Resolve them from `cwd`:

```ts
import { resolveEngineIds } from "./resolve-engine-ids.js";

async function handler(input: z.infer<typeof schema>, ctx: RpcContext) {
  const ids = await resolveEngineIds(input.cwd, ctx);
  if (!ids.effortId) {
    // Fail-open: return permissive default
    return { allow: true };
  }
  // ... use ids.effortId, ids.engineSessionId, ids.projectId
}
```

### 4. Register the command

Use the `registerCommand` + `declare module` pattern:

```ts
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

declare module "engine-shared/dispatch" {
  interface CommandRegistry {
    "hooks.myEvent": {
      input: z.infer<typeof schema>;
      output: TypedRpcResponse<typeof responseShape>;
    };
  }
}

registerCommand("hooks.myEvent", schema, handler);
```

The command name must use the `hooks.` namespace prefix.

### 5. ESM import extensions

All relative imports must use `.js` extensions (ESM requirement):

```ts
// Correct
import { hookSchema } from "./hook-base-schema.js";
import { resolveEngineIds } from "./resolve-engine-ids.js";

// Wrong -- will fail at runtime
import { hookSchema } from "./hook-base-schema";
```

## Modifying Existing Handlers

1. Read `PITFALLS.md` in this directory before making changes.
2. Preserve the fail-open pattern: handlers must return a permissive default when `resolveEngineIds` returns null IDs.
3. Keep `toolInput` as an object (`z.record`). Do not change it to `z.string()`.
4. Remember that `transformKeys` only affects top-level keys. Nested object keys remain snake_case.

## Fail-Open Pattern

Every handler must degrade gracefully when engine IDs are unresolvable:

```ts
const ids = await resolveEngineIds(input.cwd, ctx);
if (!ids.effortId) {
  return { allow: true, reason: "no active effort" };
}
```

This ensures hooks never block the agent when the engine state is incomplete (new project, no active effort, gap between sessions).

## Stub Handlers

Stub handlers (marked `-- STUB` in the README) follow the same pattern but return a no-op response. When implementing a stub:

1. Replace the stub response with real logic.
2. Add `resolveEngineIds` if the handler needs engine state.
3. Update the README to remove the `-- STUB` marker.
4. Add tests in `src/rpc/__tests__/`.
