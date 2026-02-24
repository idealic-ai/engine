/**
 * hooks.preCompact — PreCompact hook RPC (stub).
 * Fires before context compaction.
 */
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import { hookSchema } from "./hook-base-schema.js";

const schema = hookSchema({
  trigger: z.string(),
  customInstructions: z.string(),
});

async function handler(): Promise<TypedRpcResponse<Record<string, never>>> {
  return { ok: true, data: {} };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "hooks.preCompact": typeof handler;
  }
}

registerCommand("hooks.preCompact", { schema, handler });
