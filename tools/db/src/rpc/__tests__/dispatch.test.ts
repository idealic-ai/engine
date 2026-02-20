import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { Database } from "sql.js";
import { z } from "zod/v4";
import {
  dispatch,
  registerCommand,
  clearRegistry,
  type RpcResponse,
} from "../dispatch.js";
import { createTestDb } from "../../__tests__/helpers.js";

let db: Database;

beforeEach(async () => {
  clearRegistry();
  db = await createTestDb();
});

afterEach(() => {
  db.close();
});

describe("dispatch", () => {
  it("should return UNKNOWN_COMMAND for unregistered commands", () => {
    const result = dispatch({ cmd: "nonexistent.command" }, db);

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toBe("UNKNOWN_COMMAND");
      expect(result.message).toContain("nonexistent.command");
    }
  });

  it("should dispatch to registered command handler", () => {
    registerCommand("test.echo", {
      schema: z.object({ value: z.string() }),
      handler: (args) => ({ ok: true, data: { echoed: args.value } }),
    });

    const result = dispatch({ cmd: "test.echo", args: { value: "hello" } }, db);

    expect(result).toEqual({ ok: true, data: { echoed: "hello" } });
  });

  it("should validate args with Zod and reject invalid input", () => {
    registerCommand("test.strict", {
      schema: z.object({ count: z.number() }),
      handler: (args) => ({ ok: true, data: { count: args.count } }),
    });

    const result = dispatch(
      { cmd: "test.strict", args: { count: "not-a-number" } },
      db
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toBe("VALIDATION_ERROR");
      expect(result.message).toContain("test.strict");
    }
  });

  it("should reject missing required fields", () => {
    registerCommand("test.required", {
      schema: z.object({ name: z.string(), age: z.number() }),
      handler: (args) => ({ ok: true, data: args }),
    });

    const result = dispatch(
      { cmd: "test.required", args: { name: "Alice" } },
      db
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toBe("VALIDATION_ERROR");
    }
  });

  it("should default to empty object when args omitted", () => {
    registerCommand("test.noargs", {
      schema: z.object({}),
      handler: () => ({ ok: true, data: { worked: true } }),
    });

    const result = dispatch({ cmd: "test.noargs" }, db);

    expect(result).toEqual({ ok: true, data: { worked: true } });
  });

  it("should catch handler exceptions and return HANDLER_ERROR", () => {
    registerCommand("test.throw", {
      schema: z.object({}),
      handler: () => {
        throw new Error("something broke");
      },
    });

    const result = dispatch({ cmd: "test.throw", args: {} }, db);

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toBe("HANDLER_ERROR");
      expect(result.message).toContain("something broke");
    }
  });

  it("should pass db to handler", () => {
    registerCommand("test.dbcheck", {
      schema: z.object({}),
      handler: (_args, handlerDb) => {
        // Verify we can query the DB
        const result = handlerDb.exec("SELECT COUNT(*) FROM tasks");
        const count = result[0].values[0][0] as number;
        return { ok: true, data: { taskCount: count } };
      },
    });

    const result = dispatch({ cmd: "test.dbcheck", args: {} }, db) as RpcResponse & { ok: true };

    expect(result.ok).toBe(true);
    expect(result.data.taskCount).toBe(0);
  });

  it("should include details in validation errors", () => {
    registerCommand("test.details", {
      schema: z.object({ x: z.number(), y: z.number() }),
      handler: (args) => ({ ok: true, data: args }),
    });

    const result = dispatch(
      { cmd: "test.details", args: { x: "bad", y: "also bad" } },
      db
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.details).toBeDefined();
      expect(result.details!.issues).toBeDefined();
    }
  });
});
