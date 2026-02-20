/**
 * RPC Dispatch — the daemon's single entry point for all commands.
 *
 * Every RPC request flows: socket → JSON parse → dispatch() → Zod validate → handler → JSON response.
 * The dispatch function is the only place that touches the registry — handlers never call each other.
 *
 * Error taxonomy (3 levels):
 *   UNKNOWN_COMMAND  — cmd string doesn't match any registered handler
 *   VALIDATION_ERROR — args failed Zod schema validation (caller bug)
 *   HANDLER_ERROR    — handler threw (db constraint violation, logic error)
 *
 * Callers: daemon.ts (socket server) passes parsed NDJSON requests here.
 * See also: registry.ts (side-effect imports that populate the command map).
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";

// ── Response types ──────────────────────────────────────

export interface RpcSuccess {
  ok: true;
  data: Record<string, unknown>;
}

export interface RpcError {
  ok: false;
  error: string;
  message: string;
  details?: Record<string, unknown>;
}

export type RpcResponse = RpcSuccess | RpcError;

// ── Command interface ───────────────────────────────────

export interface RpcCommand<T = unknown> {
  schema: z.ZodType<T>;
  handler: (args: T, db: Database) => RpcResponse;
}

// ── Registry ────────────────────────────────────────────

const registry = new Map<string, RpcCommand>();

export function registerCommand<T>(name: string, command: RpcCommand<T>): void {
  registry.set(name, command as RpcCommand);
}

export function getCommand(name: string): RpcCommand | undefined {
  return registry.get(name);
}

/** Visible for testing — clears all registered commands */
export function clearRegistry(): void {
  registry.clear();
}

// ── Dispatch ────────────────────────────────────────────

export interface RpcRequest {
  cmd: string;
  args?: unknown;
}

/**
 * Dispatch an RPC request to its registered handler.
 * Validates args with Zod, then calls the handler.
 */
export function dispatch(request: RpcRequest, db: Database): RpcResponse {
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
    return command.handler(parseResult.data, db);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      ok: false,
      error: "HANDLER_ERROR",
      message: `Handler error in ${request.cmd}: ${message}`,
    };
  }
}
