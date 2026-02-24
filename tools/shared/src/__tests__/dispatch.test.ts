import { describe, it, expect } from "vitest";
import { z } from "zod/v4";
import {
  dispatch,
  registerCommand,
  getCommand,
  clearRegistry,
} from "../dispatch.js";
import type { RpcContext } from "../context.js";

describe("dispatch — error paths & edge cases", () => {
  it("A/1: returns HANDLER_ERROR when handler throws synchronously", async () => {
    registerCommand("test.sync.throw", {
      schema: z.object({}),
      handler: () => {
        throw new Error("sync kaboom");
      },
    });

    const result = await dispatch({ cmd: "test.sync.throw", args: {} }, {} as RpcContext);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("HANDLER_ERROR");
    expect(result.message).toContain("sync kaboom");
  });

  it("A/2: returns HANDLER_ERROR when async handler rejects", async () => {
    registerCommand("test.async.reject", {
      schema: z.object({}),
      handler: async () => {
        throw new Error("async kaboom");
      },
    });

    const result = await dispatch({ cmd: "test.async.reject", args: {} }, {} as RpcContext);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("HANDLER_ERROR");
    expect(result.message).toContain("async kaboom");
  });

  it("A/3: defaults args to {} when request.args is undefined", async () => {
    // Register a handler with a required field — omitting args should yield VALIDATION_ERROR, not crash
    registerCommand("test.needs.args", {
      schema: z.object({ required: z.string() }),
      handler: (args) => ({ ok: true as const, data: { got: args.required } }),
    });

    const result = await dispatch({ cmd: "test.needs.args" }, {} as RpcContext);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("VALIDATION_ERROR");
    // Key: it did NOT crash — the ?? {} fallback worked, then Zod caught the missing field
  });

  it("A/4: supports getCommand() and clearRegistry() lifecycle", () => {
    const testCmd = "test.lifecycle.probe";
    registerCommand(testCmd, {
      schema: z.object({}),
      handler: () => ({ ok: true as const, data: {} }),
    });

    // Found before clear
    expect(getCommand(testCmd)).toBeDefined();

    clearRegistry();

    // Gone after clear
    expect(getCommand(testCmd)).toBeUndefined();

    // Re-register to avoid polluting other tests
    // (side-effect imports will re-register on next import, but clearRegistry is destructive)
  });
});
