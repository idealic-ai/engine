/**
 * hooks.taskCompleted — TaskCompleted hook RPC.
 * Fires when a Claude Code task (Task tool sub-agent) completes.
 * Logs to messages table.
 *
 * INV_DAEMON_IS_PURE_DB: no filesystem I/O.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import { hookSchema } from "./hook-base-schema.js";
import { resolveEngineIds } from "./resolve-engine-ids.js";

const schema = hookSchema({
  taskId: z.string(),
  taskSubject: z.string(),
  taskDescription: z.string().optional(),
  teammateName: z.string().optional(),
  teamName: z.string().optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ messageLogged: boolean }>> {
  const { engineSessionId } = await resolveEngineIds(args.cwd, ctx);

  if (!engineSessionId) {
    return { ok: true, data: { messageLogged: false } };
  }

  try {
    await ctx.db.run(
      "INSERT INTO messages (session_id, role, content, timestamp) VALUES (?, ?, ?, datetime('now'))",
      [engineSessionId, "system", JSON.stringify({ event: "task_completed", taskId: args.taskId ?? null, taskSubject: args.taskSubject ?? null, teammateName: args.teammateName ?? null })]
    );
    return { ok: true, data: { messageLogged: true } };
  } catch {
    return { ok: true, data: { messageLogged: false } };
  }
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "hooks.taskCompleted": typeof handler;
  }
}

registerCommand("hooks.taskCompleted", { schema, handler });
