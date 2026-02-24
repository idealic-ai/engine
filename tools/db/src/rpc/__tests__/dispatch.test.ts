import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../db-wrapper.js";
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import {
  dispatch,
  registerCommand,
  clearRegistry,
  type RpcResponse,
} from "../dispatch.js";
import { createTestDb } from "../../__tests__/helpers.js";

let db: DbConnection;

beforeEach(async () => {
  clearRegistry();
  db = await createTestDb();
});

afterEach(async () => {
  await db.close();
});

describe("dispatch", () => {
  it("should return UNKNOWN_COMMAND for unregistered commands", async () => {
    const result = await dispatch({ cmd: "nonexistent.command" }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toBe("UNKNOWN_COMMAND");
      expect(result.message).toContain("nonexistent.command");
    }
  });

  it("should dispatch to registered command handler", async () => {
    registerCommand("test.echo", {
      schema: z.object({ value: z.string() }),
      handler: (args) => ({ ok: true, data: { echoed: args.value } }),
    });

    const result = await dispatch({ cmd: "test.echo", args: { value: "hello" } },  { db } as unknown as RpcContext);

    expect(result).toEqual({ ok: true, data: { echoed: "hello" } });
  });

  it("should validate args with Zod and reject invalid input", async () => {
    registerCommand("test.strict", {
      schema: z.object({ count: z.number() }),
      handler: (args) => ({ ok: true, data: { count: args.count } }),
    });

    const result = await dispatch(
      { cmd: "test.strict", args: { count: "not-a-number" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toBe("VALIDATION_ERROR");
      expect(result.message).toContain("test.strict");
    }
  });

  it("should reject missing required fields", async () => {
    registerCommand("test.required", {
      schema: z.object({ name: z.string(), age: z.number() }),
      handler: (args) => ({ ok: true, data: args }),
    });

    const result = await dispatch(
      { cmd: "test.required", args: { name: "Alice" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toBe("VALIDATION_ERROR");
    }
  });

  it("should default to empty object when args omitted", async () => {
    registerCommand("test.noargs", {
      schema: z.object({}),
      handler: () => ({ ok: true, data: { worked: true } }),
    });

    const result = await dispatch({ cmd: "test.noargs" }, { db } as unknown as RpcContext);

    expect(result).toEqual({ ok: true, data: { worked: true } });
  });

  it("should catch handler exceptions and return HANDLER_ERROR", async () => {
    registerCommand("test.throw", {
      schema: z.object({}),
      handler: () => {
        throw new Error("something broke");
      },
    });

    const result = await dispatch({ cmd: "test.throw", args: {} },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toBe("HANDLER_ERROR");
      expect(result.message).toContain("something broke");
    }
  });

  it("should pass ctx to handler", async () => {
    registerCommand("test.dbcheck", {
      schema: z.object({}),
      handler: async (_args, ctx: RpcContext) => {
        // Verify we can query the DB via ctx.db
        const row = await ctx.db.get<{ count: number }>("SELECT COUNT(*) as count FROM tasks");
        const count = row?.count ?? 0;
        return { ok: true, data: { taskCount: count } };
      },
    });

    const result = await dispatch({ cmd: "test.dbcheck", args: {} },  { db } as unknown as RpcContext) as RpcResponse & { ok: true };

    expect(result.ok).toBe(true);
    expect(result.data.taskCount).toBe(0);
  });

  it("should include details in validation errors", async () => {
    registerCommand("test.details", {
      schema: z.object({ x: z.number(), y: z.number() }),
      handler: (args) => ({ ok: true, data: args }),
    });

    const result = await dispatch(
      { cmd: "test.details", args: { x: "bad", y: "also bad" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.details).toBeDefined();
      expect(result.details!.issues).toBeDefined();
    }
  });
});
