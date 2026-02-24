import { describe, it, expect, beforeEach } from "vitest";
import type { RpcRequest, RpcResponse } from "../dispatch.js";
import type { RpcContext } from "../context.js";
import {
  registerMiddleware,
  clearMiddlewares,
  runMiddlewareChain,
  type RpcMiddleware,
} from "../middleware.js";

// ── Helpers ──────────────────────────────────────────────

function okResponse(data: Record<string, unknown> = {}): RpcResponse {
  return { ok: true, data };
}

function errorResponse(error: string, message: string): RpcResponse {
  return { ok: false, error, message };
}

const dummyRequest: RpcRequest = { cmd: "test.dummy", args: {} };
const dummyCtx = {} as RpcContext;

// ── Section 1: Middleware chain mechanics ─────────────────

describe("middleware chain — registration & execution", () => {
  beforeEach(() => {
    clearMiddlewares();
  });

  it("runs handler directly when no middleware is registered", async () => {
    const handler = async () => okResponse({ direct: true });
    const result = await runMiddlewareChain(dummyRequest, dummyCtx, handler);
    expect(result).toEqual(okResponse({ direct: true }));
  });

  it("runs a single middleware wrapping the handler", async () => {
    const order: string[] = [];

    registerMiddleware(async (_req, _ctx, next) => {
      order.push("before");
      const result = await next();
      order.push("after");
      return result;
    });

    const handler = async () => {
      order.push("handler");
      return okResponse();
    };

    await runMiddlewareChain(dummyRequest, dummyCtx, handler);
    expect(order).toEqual(["before", "handler", "after"]);
  });

  it("runs multiple middlewares in registration order (onion model)", async () => {
    const order: string[] = [];

    registerMiddleware(async (_req, _ctx, next) => {
      order.push("A-before");
      const result = await next();
      order.push("A-after");
      return result;
    });

    registerMiddleware(async (_req, _ctx, next) => {
      order.push("B-before");
      const result = await next();
      order.push("B-after");
      return result;
    });

    const handler = async () => {
      order.push("handler");
      return okResponse();
    };

    await runMiddlewareChain(dummyRequest, dummyCtx, handler);
    expect(order).toEqual([
      "A-before",
      "B-before",
      "handler",
      "B-after",
      "A-after",
    ]);
  });

  it("passes request and ctx through the chain", async () => {
    const req: RpcRequest = { cmd: "test.ctx.pass", args: { x: 1 } };
    const ctx = { db: "mock-db" } as unknown as RpcContext;

    let capturedReq: RpcRequest | null = null;
    let capturedCtx: RpcContext | null = null;

    registerMiddleware(async (r, c, next) => {
      capturedReq = r;
      capturedCtx = c;
      return next();
    });

    await runMiddlewareChain(req, ctx, async () => okResponse());
    expect(capturedReq).toBe(req);
    expect(capturedCtx).toBe(ctx);
  });

  it("middleware can short-circuit without calling next()", async () => {
    const handlerCalled = { value: false };

    registerMiddleware(async () => {
      return errorResponse("BLOCKED", "middleware blocked this");
    });

    const handler = async () => {
      handlerCalled.value = true;
      return okResponse();
    };

    const result = await runMiddlewareChain(dummyRequest, dummyCtx, handler);
    expect(result.ok).toBe(false);
    expect(handlerCalled.value).toBe(false);
  });

  it("middleware can modify the response from next()", async () => {
    registerMiddleware(async (_req, _ctx, next) => {
      const result = await next();
      if (result.ok) {
        return { ...result, data: { ...result.data, injected: true } };
      }
      return result;
    });

    const handler = async () => okResponse({ original: true });
    const result = await runMiddlewareChain(dummyRequest, dummyCtx, handler);
    expect(result).toEqual(okResponse({ original: true, injected: true }));
  });

  it("propagates errors thrown by middleware", async () => {
    registerMiddleware(async () => {
      throw new Error("middleware exploded");
    });

    const handler = async () => okResponse();
    await expect(
      runMiddlewareChain(dummyRequest, dummyCtx, handler),
    ).rejects.toThrow("middleware exploded");
  });

  it("propagates errors thrown by handler through middleware", async () => {
    const rollbackCalled = { value: false };

    registerMiddleware(async (_req, _ctx, next) => {
      try {
        return await next();
      } catch (err) {
        rollbackCalled.value = true;
        throw err;
      }
    });

    const handler = async () => {
      throw new Error("handler exploded");
    };

    await expect(
      runMiddlewareChain(dummyRequest, dummyCtx, handler),
    ).rejects.toThrow("handler exploded");
    expect(rollbackCalled.value).toBe(true);
  });

  it("clearMiddlewares removes all registered middlewares", async () => {
    registerMiddleware(async () => errorResponse("BLOCKED", "should not run"));

    clearMiddlewares();

    const result = await runMiddlewareChain(
      dummyRequest,
      dummyCtx,
      async () => okResponse({ cleared: true }),
    );
    expect(result).toEqual(okResponse({ cleared: true }));
  });
});

// ── Section 2: txMiddleware ──────────────────────────────

describe("txMiddleware", () => {
  // Mock db with tracked SQL calls
  function createMockDb() {
    const calls: string[] = [];
    return {
      calls,
      run: async (sql: string) => {
        calls.push(sql);
        return { changes: 0 };
      },
    };
  }

  it("wraps handler in BEGIN/COMMIT on success", async () => {
    const mockDb = createMockDb();
    const ctx = { db: mockDb } as unknown as RpcContext;
    const order: string[] = [];

    const { txMiddleware } = await import("../middleware.js");

    const result = await txMiddleware(dummyRequest, ctx, async () => {
      order.push("handler");
      mockDb.calls.push("INSERT");
      return okResponse({ done: true });
    });

    expect(result).toEqual(okResponse({ done: true }));
    expect(mockDb.calls).toEqual(["BEGIN", "INSERT", "COMMIT"]);
    expect(order).toEqual(["handler"]);
  });

  it("does BEGIN/ROLLBACK when handler throws", async () => {
    const mockDb = createMockDb();
    const ctx = { db: mockDb } as unknown as RpcContext;

    const { txMiddleware } = await import("../middleware.js");

    await expect(
      txMiddleware(dummyRequest, ctx, async () => {
        mockDb.calls.push("INSERT");
        throw new Error("handler threw");
      }),
    ).rejects.toThrow("handler threw");

    expect(mockDb.calls).toEqual(["BEGIN", "INSERT", "ROLLBACK"]);
  });

  it("does BEGIN/COMMIT when handler returns {ok: false} (no throw)", async () => {
    // Guard-before-mutate: handler returns error without throwing.
    // This means no mutations happened — COMMIT is safe (read-only tx).
    const mockDb = createMockDb();
    const ctx = { db: mockDb } as unknown as RpcContext;

    const { txMiddleware } = await import("../middleware.js");

    const result = await txMiddleware(dummyRequest, ctx, async () => {
      return errorResponse("NOT_FOUND", "thing not found");
    });

    expect(result.ok).toBe(false);
    expect(mockDb.calls).toEqual(["BEGIN", "COMMIT"]);
  });
});

// ── Section 3: fsBufferMiddleware ─────────────────────────

describe("fsBufferMiddleware", () => {
  function createMockDb() {
    const calls: string[] = [];
    return {
      calls,
      run: async (sql: string) => {
        calls.push(sql);
        return { changes: 0 };
      },
    };
  }

  it("initializes _pendingFs array on ctx before handler runs", async () => {
    const mockDb = createMockDb();
    const ctx = { db: mockDb } as unknown as RpcContext & { _pendingFs?: unknown[] };

    const { fsBufferMiddleware } = await import("../middleware.js");

    let pendingDuringHandler: unknown[] | undefined;
    await fsBufferMiddleware(dummyRequest, ctx, async () => {
      pendingDuringHandler = ctx._pendingFs;
      return okResponse();
    });

    expect(pendingDuringHandler).toEqual([]);
  });

  it("flushes buffered ops on success", async () => {
    const mockDb = createMockDb();
    const flushed: Array<{ op: string; path: string }> = [];
    const ctx = { db: mockDb } as unknown as RpcContext & { _pendingFs: Array<{ op: string; path: string; content?: string }> };

    const { fsBufferMiddleware, setFsExecutor } = await import("../middleware.js");

    setFsExecutor(async (op) => {
      flushed.push({ op: op.op, path: op.path });
    });

    const result = await fsBufferMiddleware(dummyRequest, ctx, async () => {
      ctx._pendingFs.push({ op: "write", path: "/tmp/a.txt", content: "hello" });
      ctx._pendingFs.push({ op: "mkdir", path: "/tmp/dir" });
      return okResponse({ wrote: true });
    });

    expect(result).toEqual(okResponse({ wrote: true }));
    expect(flushed).toEqual([
      { op: "write", path: "/tmp/a.txt" },
      { op: "mkdir", path: "/tmp/dir" },
    ]);

    // Cleanup
    setFsExecutor(undefined);
  });

  it("discards buffered ops when handler returns {ok: false}", async () => {
    const mockDb = createMockDb();
    const flushed: string[] = [];
    const ctx = { db: mockDb } as unknown as RpcContext & { _pendingFs: Array<{ op: string; path: string; content?: string }> };

    const { fsBufferMiddleware, setFsExecutor } = await import("../middleware.js");

    setFsExecutor(async (op) => {
      flushed.push(op.path);
    });

    const result = await fsBufferMiddleware(dummyRequest, ctx, async () => {
      ctx._pendingFs.push({ op: "write", path: "/tmp/should-not-flush.txt", content: "nope" });
      return errorResponse("FAILED", "handler failed");
    });

    expect(result.ok).toBe(false);
    expect(flushed).toEqual([]); // Nothing flushed

    setFsExecutor(undefined);
  });

  it("discards buffered ops when handler throws", async () => {
    const mockDb = createMockDb();
    const flushed: string[] = [];
    const ctx = { db: mockDb } as unknown as RpcContext & { _pendingFs: Array<{ op: string; path: string }> };

    const { fsBufferMiddleware, setFsExecutor } = await import("../middleware.js");

    setFsExecutor(async (op) => {
      flushed.push(op.path);
    });

    await expect(
      fsBufferMiddleware(dummyRequest, ctx, async () => {
        ctx._pendingFs.push({ op: "write", path: "/tmp/should-not-flush.txt" });
        throw new Error("handler threw");
      }),
    ).rejects.toThrow("handler threw");

    expect(flushed).toEqual([]);

    setFsExecutor(undefined);
  });

  it("logs and continues on flush failure (does not throw)", async () => {
    const mockDb = createMockDb();
    const ctx = { db: mockDb } as unknown as RpcContext & { _pendingFs: Array<{ op: string; path: string; content?: string }> };

    const { fsBufferMiddleware, setFsExecutor } = await import("../middleware.js");

    let secondCalled = false;
    setFsExecutor(async (op) => {
      if (op.path === "/tmp/fail.txt") {
        throw new Error("disk full");
      }
      secondCalled = true;
    });

    const result = await fsBufferMiddleware(dummyRequest, ctx, async () => {
      ctx._pendingFs.push({ op: "write", path: "/tmp/fail.txt", content: "x" });
      ctx._pendingFs.push({ op: "write", path: "/tmp/ok.txt", content: "y" });
      return okResponse();
    });

    // Should not throw — log-and-continue
    expect(result.ok).toBe(true);
    // Second op still executed despite first failing
    expect(secondCalled).toBe(true);

    setFsExecutor(undefined);
  });
});
