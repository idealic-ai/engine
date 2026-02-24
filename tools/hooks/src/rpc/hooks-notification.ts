/**
 * hooks.notification — Notification hook RPC (stub).
 * Fires when Claude Code sends notifications.
 */
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import { hookSchema } from "./hook-base-schema.js";

const schema = hookSchema({
  message: z.string(),
  notificationType: z.string(),
  title: z.string().optional(),
});

async function handler(): Promise<TypedRpcResponse<Record<string, never>>> {
  return { ok: true, data: {} };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "hooks.notification": typeof handler;
  }
}

registerCommand("hooks.notification", { schema, handler });
