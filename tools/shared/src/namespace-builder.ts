/**
 * Namespace Builder — runtime factory that constructs typed namespace proxy objects.
 *
 * Given a prefix like "db" and the handler registry, builds a nested object:
 *   { effort: { start(args) {...}, list(args) {...} }, session: { start(args) {...}, ... } }
 *
 * Each method is a thin wrapper over dispatch() that:
 *   1. Calls dispatch({cmd: "prefix.group.method", args}, ctx)
 *   2. Throws on error (like the rpc() helper in commands handlers)
 *   3. Returns .data on success (unwrapped from RpcResponse envelope)
 */
import { dispatch, type RpcCommand } from "./dispatch.js";
import type { RpcContext } from "./context.js";

/**
 * Build a namespace proxy object from registry entries matching a prefix.
 *
 * @param prefix - Namespace prefix (e.g., "db", "commands")
 * @param registry - The command registry Map<string, RpcCommand>
 * @param ctx - The RpcContext to pass through to dispatch
 * @returns Nested object with methods for each command
 *
 * Example: buildNamespace("db", registry, ctx) produces:
 *   { effort: { start(args), list(args), ... }, session: { start(args), ... } }
 */
export function buildNamespace(
  prefix: string,
  registry: ReadonlyMap<string, RpcCommand>,
  ctx: RpcContext,
): Record<string, Record<string, (args: Record<string, unknown>) => Promise<Record<string, unknown>>>> {
  const namespace: Record<string, Record<string, (args: Record<string, unknown>) => Promise<Record<string, unknown>>>> = {};
  const dotPrefix = `${prefix}.`;

  for (const [cmd] of registry) {
    if (!cmd.startsWith(dotPrefix)) continue;

    const suffix = cmd.slice(dotPrefix.length);
    const dotIndex = suffix.indexOf(".");
    if (dotIndex === -1) continue; // skip commands without a sub-group (shouldn't exist)

    const group = suffix.slice(0, dotIndex);
    const method = suffix.slice(dotIndex + 1);

    if (!namespace[group]) {
      namespace[group] = {};
    }

    namespace[group][method] = async (args: Record<string, unknown>) => {
      const result = await dispatch.internal({ cmd, args }, ctx);
      if (!result.ok) {
        throw new Error(`${cmd} failed: ${(result as { message: string }).message}`);
      }
      return result.data;
    };
  }

  return namespace;
}

/**
 * Build a flat namespace proxy from registry entries matching a prefix.
 *
 * For 2-level command names (prefix.method) like config.set, config.get.
 *
 * Example: buildFlatNamespace("config", registry, ctx) produces:
 *   { set(args), get(args), list(args), setBatch(args) }
 */
export function buildFlatNamespace(
  prefix: string,
  registry: ReadonlyMap<string, RpcCommand>,
  ctx: RpcContext,
): Record<string, (args: Record<string, unknown>) => Promise<Record<string, unknown>>> {
  const namespace: Record<string, (args: Record<string, unknown>) => Promise<Record<string, unknown>>> = {};
  const dotPrefix = `${prefix}.`;

  for (const [cmd] of registry) {
    if (!cmd.startsWith(dotPrefix)) continue;

    const method = cmd.slice(dotPrefix.length);
    // Skip 3-level commands (those belong to buildNamespace)
    if (method.includes(".")) continue;

    namespace[method] = async (args: Record<string, unknown>) => {
      const result = await dispatch.internal({ cmd, args }, ctx);
      if (!result.ok) {
        throw new Error(`${cmd} failed: ${(result as { message: string }).message}`);
      }
      return result.data;
    };
  }

  return namespace;
}

/** Expose the registry for buildNamespace to iterate */
export { getRegistry } from "./dispatch.js";
