/**
 * Test context factory — builds an RpcContext with real namespace proxies
 * for agent handler tests that need ctx.fs.*, ctx.env, etc.
 *
 * Registers fs.* handlers, then builds namespace proxies.
 */
import type { RpcContext } from "engine-shared/context";
import { getRegistry } from "engine-shared/dispatch";
import { buildNamespace } from "engine-shared/namespace-builder";

// Register fs.* handlers via side-effect imports
import "../../../../fs/src/rpc/registry.js";

export function createTestCtx(env?: Partial<import("engine-shared/context").RpcEnv>): RpcContext {
  const ctx = {} as RpcContext;
  const registry = getRegistry();

  // Per-request env (defaults for tests)
  ctx.env = { CWD: "/tmp/test", AGENT_ID: "default", ...env };

  // Build 3-level namespace proxies (fs.files.read, fs.dirs.list, etc.)
  const fsNs = buildNamespace("fs", registry, ctx);
  ctx.fs = fsNs as unknown as RpcContext["fs"];

  return ctx;
}
