/**
 * RPC Middleware — plugin-based middleware chain for dispatch.
 *
 * Middleware wraps the dispatch handler in an onion model:
 *   outerMiddleware → innerMiddleware → handler → innerMiddleware → outerMiddleware
 *
 * Each middleware receives (request, ctx, next) and decides whether to:
 *   - Call next() to proceed down the chain
 *   - Short-circuit by returning an RpcResponse without calling next()
 *   - Modify the response from next()
 *   - Catch errors from next() for cleanup (e.g., ROLLBACK)
 *
 * Registration order = execution order: first registered = outermost wrapper.
 */
import type { RpcRequest, RpcResponse } from "./dispatch.js";
import type { RpcContext } from "./context.js";

export type RpcNext = () => Promise<RpcResponse>;
export type RpcMiddleware = (
  request: RpcRequest,
  ctx: RpcContext,
  next: RpcNext,
) => Promise<RpcResponse>;

// ── Registry ────────────────────────────────────────────

const middlewares: RpcMiddleware[] = [];

export function registerMiddleware(mw: RpcMiddleware): void {
  middlewares.push(mw);
}

export function getMiddlewares(): readonly RpcMiddleware[] {
  return middlewares;
}

export function clearMiddlewares(): void {
  middlewares.length = 0;
}

// ── Chain runner ────────────────────────────────────────

/**
 * Run the middleware chain, ending with the provided handler.
 * Builds a nested next() chain from the registered middlewares.
 */
export async function runMiddlewareChain(
  request: RpcRequest,
  ctx: RpcContext,
  handler: () => Promise<RpcResponse>,
): Promise<RpcResponse> {
  if (middlewares.length === 0) {
    return handler();
  }

  // Build the chain from inside out:
  // last middleware wraps handler, first middleware is outermost
  let next: RpcNext = handler;

  for (let i = middlewares.length - 1; i >= 0; i--) {
    const mw = middlewares[i];
    const innerNext = next;
    next = () => mw(request, ctx, innerNext);
  }

  return next();
}

// ── Built-in middlewares ────────────────────────────────

/**
 * Transaction middleware — wraps handler in BEGIN/COMMIT/ROLLBACK.
 *
 * On success (handler returns any RpcResponse): COMMIT.
 * On throw (handler throws): ROLLBACK, then re-throw.
 *
 * Handlers that return {ok: false} without throwing get COMMIT —
 * this is correct because guard-before-mutate means no writes happened.
 */
// ── FS Buffer types ─────────────────────────────────────

export interface FsOp {
  op: "write" | "append" | "mkdir" | "unlink";
  path: string;
  content?: string;
}

export type FsExecutor = (op: FsOp) => Promise<void>;

let fsExecutor: FsExecutor | undefined;

/** Set the FS executor for fsBufferMiddleware. Used by daemon startup and tests. */
export function setFsExecutor(executor: FsExecutor | undefined): void {
  fsExecutor = executor;
}

/**
 * FS Buffer middleware — collects FS operations during handler execution.
 *
 * Handlers push FsOp entries to ctx._pendingFs during execution.
 * On success ({ok: true}): flush all ops via the executor (log-and-continue on failure).
 * On error ({ok: false} or throw): discard all ops.
 */
export const fsBufferMiddleware: RpcMiddleware = async (_request, ctx, next) => {
  const ctxAny = ctx as RpcContext & { _pendingFs: FsOp[] };
  ctxAny._pendingFs = [];

  let result: RpcResponse;
  try {
    result = await next();
  } catch (err) {
    // Handler threw — discard buffer
    ctxAny._pendingFs = [];
    throw err;
  }

  if (!result.ok) {
    // Handler returned error — discard buffer
    ctxAny._pendingFs = [];
    return result;
  }

  // Success — flush buffer
  if (fsExecutor) {
    for (const op of ctxAny._pendingFs) {
      try {
        await fsExecutor(op);
      } catch (_err) {
        // Log-and-continue per design decision
      }
    }
  }
  ctxAny._pendingFs = [];
  return result;
};

export const txMiddleware: RpcMiddleware = async (_request, ctx, next) => {
  const conn = (ctx as any).db;
  await conn.run("BEGIN");
  try {
    const result = await next();
    await conn.run("COMMIT");
    return result;
  } catch (err) {
    await conn.run("ROLLBACK");
    throw err;
  }
};
