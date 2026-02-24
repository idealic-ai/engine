# engine-shared

Shared RPC dispatch layer for all daemon namespaces.

## Purpose

Provides the central dispatch mechanism that routes incoming RPC requests
to registered handlers. Every RPC request flows through this path:

```
socket -> JSON parse -> dispatch() -> Zod validate -> handler -> JSON response
```

Handlers self-register via `registerCommand()` at import time. The dispatch
function is the only code that touches the registry -- handlers never call
each other directly.

## Types

### RpcRequest

```typescript
interface RpcRequest {
  cmd: string;       // e.g., "db.task.upsert", "fs.files.read"
  args?: unknown;    // validated by the handler's Zod schema
}
```

### RpcResponse

```typescript
type RpcResponse = RpcSuccess | RpcError;

interface RpcSuccess {
  ok: true;
  data: Record<string, unknown>;
}

interface RpcError {
  ok: false;
  error: string;                     // error code
  message: string;                   // human-readable
  details?: Record<string, unknown>; // optional structured details
}
```

### RpcCommand

```typescript
interface RpcCommand<T = unknown> {
  schema: z.ZodType<T>;
  handler: (args: T, ctx: any) => RpcResponse | Promise<RpcResponse>;
}
```

The `ctx` parameter is typed as `any` to allow heterogeneous handler
signatures. Each handler narrows it to what it needs (e.g., `DbConnection`
for db.* handlers, `void` for fs.* handlers).

## API

### registerCommand(name, command)

Register a handler for an RPC command name. Called at module import time
by each handler file (self-registering pattern).

```typescript
registerCommand("fs.files.read", { schema, handler });
```

### dispatch(request, ctx)

Route an RPC request to its registered handler. Validates args with Zod
before calling the handler. Always returns a Promise.

```typescript
const response = await dispatch({ cmd: "fs.files.read", args: { path: "/tmp/f" } }, ctx);
```

### getCommand(name)

Look up a registered command by name. Returns `undefined` if not found.

### clearRegistry()

Remove all registered commands. Visible for testing only.

## Error Taxonomy

Three error levels, from caller bug to system failure:

| Error Code | Meaning | Cause |
|---|---|---|
| `UNKNOWN_COMMAND` | Command string not in registry | Typo or unregistered handler |
| `VALIDATION_ERROR` | Args failed Zod schema | Caller passed wrong shape |
| `HANDLER_ERROR` | Handler threw an exception | DB constraint, FS error, logic bug |

## Namespace Isolation

The dispatch layer is namespace-agnostic. Namespaces are a naming
convention enforced by handler registration:

- `db.*` -- Pure database handlers (engine-db)
- `fs.*` -- Pure filesystem handlers (engine-fs)
- `agent.*` -- Convention/workspace handlers (engine-agent)

## Files

```
src/
  dispatch.ts       -- Registry, dispatch, types
  rpc-cli.ts        -- CLI entry point for raw RPC calls
  __tests__/        -- Dispatch unit tests
```
