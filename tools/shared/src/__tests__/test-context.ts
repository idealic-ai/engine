/**
 * Test context builder — mirrors daemon.ts ctx construction for test environments.
 *
 * Tests that call dispatch() with commands.* handlers need ctx.db populated
 * with namespace proxies, because those handlers use ctx.db.* for typed RPC calls.
 */
import { getRegistry } from "../dispatch.js";
import { buildNamespace } from "../namespace-builder.js";
import type { RpcContext } from "../context.js";

/**
 * Build a full RpcContext with namespace proxies, matching what daemon.ts does.
 * Pass the result as ctx to dispatch() in tests.
 *
 * @param db - The test database instance (from createTestDb())
 */
export function createTestContext(db: unknown, env?: Partial<import("../context.js").RpcEnv>): RpcContext {
  const ctx = {} as RpcContext;
  const registry = getRegistry();
  ctx.env = { CWD: "/tmp/test", AGENT_ID: "default", ...env };
  const ns = buildNamespace("db", registry, ctx);
  ctx.db = Object.assign(db as object, ns) as unknown as RpcContext["db"];
  return ctx;
}
