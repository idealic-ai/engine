/**
 * RPC Dispatch — shared dispatch mechanism for all daemon namespaces.
 *
 * Two dispatch paths:
 *   dispatch()          — top-level: runs middleware chain → Zod validate → handler
 *   dispatch.internal() — inner: Zod validate → handler (no middleware)
 *
 * Top-level dispatch is used by daemon.ts handleQuery().
 * Internal dispatch is used by namespace-builder for inter-namespace RPC calls.
 *
 * Error taxonomy (3 levels):
 *   UNKNOWN_COMMAND  — cmd string doesn't match any registered handler
 *   VALIDATION_ERROR — args failed Zod schema validation (caller bug)
 *   HANDLER_ERROR    — handler threw (db constraint violation, FS error, logic error)
 *
 * Namespace isolation:
 *   db.*    — pure DB handlers (import from engine-db)
 *   fs.*    — pure FS handlers (import from engine-fs)
 *   agent.* — convention/workspace handlers (import from engine-agent)
 *
 * Callers: daemon.ts (socket server) passes parsed NDJSON requests here.
 */
import { z } from "zod/v4";
import type { RpcContext } from "./context.js";
import { runMiddlewareChain } from "./middleware.js";

// ── Response types ──────────────────────────────────────

export interface RpcSuccess {
  ok: true;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  data: Record<string, any>;
}

export interface RpcError {
  ok: false;
  error: string;
  message: string;
  details?: Record<string, unknown>;
}

export type RpcResponse = RpcSuccess | RpcError;

// ── Command interface ───────────────────────────────────

/**
 * An RPC command: Zod schema for validation + handler function.
 *
 * @param T — validated args type (inferred from schema)
 * @param C — context type passed by the daemon (e.g., Database for db.*, void for fs.*)
 *
 * The ctx parameter is typed as `any` in the registry to allow heterogeneous
 * handler signatures. Each handler narrows it to what it needs.
 */
export interface RpcCommand<T = unknown> {
  schema: z.ZodType<T>;
  handler: (args: T, ctx: RpcContext) => RpcResponse | Promise<RpcResponse>;
}

// ── Registry ────────────────────────────────────────────

const registry = new Map<string, RpcCommand>();

/**
 * Register a command handler.
 *
 * Typed overload: when name matches a key in Registered, handler types are enforced.
 * Untyped fallback: accepts any string name during migration.
 */
export function registerCommand<K extends string, T = unknown>(name: K, command: RpcCommand<T>): void {
  registry.set(name, command as RpcCommand<unknown>);
}

export function getCommand(name: string): RpcCommand | undefined {
  return registry.get(name);
}

/** Visible for testing — clears all registered commands */
export function clearRegistry(): void {
  registry.clear();
}

/** Read-only access to the registry — used by namespace builder */
export function getRegistry(): ReadonlyMap<string, RpcCommand> {
  return registry;
}

// ── Dispatch ────────────────────────────────────────────

export interface RpcRequest {
  cmd: string;
  args?: unknown;
}

/**
 * Internal dispatch — Zod validate → handler. No middleware.
 * Used by namespace-builder for inter-namespace RPC calls.
 */
async function dispatchInternal(request: RpcRequest, ctx: RpcContext): Promise<RpcResponse> {
  const command = registry.get(request.cmd);
  if (!command) {
    return {
      ok: false,
      error: "UNKNOWN_COMMAND",
      message: `Unknown RPC command: ${request.cmd}`,
    };
  }

  // Validate args with Zod
  const parseResult = command.schema.safeParse(request.args ?? {});
  if (!parseResult.success) {
    const issues = parseResult.error.issues.map(
      (i) => `${i.path.join(".")}: ${i.message}`
    );
    return {
      ok: false,
      error: "VALIDATION_ERROR",
      message: `Invalid args for ${request.cmd}: ${issues.join("; ")}`,
      details: { issues },
    };
  }

  try {
    return await command.handler(parseResult.data, ctx);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      ok: false,
      error: "HANDLER_ERROR",
      message: `Handler error in ${request.cmd}: ${message}`,
    };
  }
}

/**
 * Top-level dispatch — runs middleware chain → Zod validate → handler.
 * Used by daemon.ts handleQuery() for incoming RPC requests.
 *
 * The .internal property provides the raw dispatch path (no middleware)
 * for namespace-builder inter-namespace calls.
 */
export async function dispatch(request: RpcRequest, ctx: RpcContext): Promise<RpcResponse> {
  return runMiddlewareChain(request, ctx, () => dispatchInternal(request, ctx));
}

/** Raw dispatch without middleware — for inter-namespace calls */
dispatch.internal = dispatchInternal;
