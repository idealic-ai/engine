/**
 * RPC Dispatch — re-export shim from engine-shared.
 *
 * db handlers import from "./dispatch.js" for historical reasons.
 * This file re-exports from the shared dispatch module so all
 * handlers register into the same global registry.
 */
export {
  registerCommand,
  getCommand,
  clearRegistry,
  dispatch,
  type RpcCommand,
  type RpcRequest,
  type RpcResponse,
  type RpcSuccess,
  type RpcError,
} from "engine-shared/dispatch";
