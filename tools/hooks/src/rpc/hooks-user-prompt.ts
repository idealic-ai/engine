/**
 * hooks.userPrompt — RPC for UserPromptSubmit hook.
 *
 * Assembles the compact session context line injected into the agent's context
 * when the user sends a message. Also triggers transcript ingestion.
 *
 * Input:  hookSchema({ prompt })
 * Output: { sessionContext, effortId, sessionId, taskDir, skill, phase, heartbeat }
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import { hookSchema } from "./hook-base-schema.js";
import { resolveEngineIds } from "./resolve-engine-ids.js";

const DEFAULT_BLOCK_AFTER = 10;

const schema = hookSchema({
  prompt: z.string(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ sessionContext: string; effortId: number | null; sessionId: number | null; taskDir: string | null; skill: string | null; phase: string | null; heartbeat: string }>> {
  // Resolve engine IDs from cwd
  const { effortId, engineSessionId } = await resolveEngineIds(args.cwd, ctx);

  if (!effortId) {
    return {
      ok: true,
      data: {
        sessionContext: "",
        effortId: null,
        sessionId: null,
        taskDir: null,
        skill: null,
        phase: null,
        heartbeat: `0/${DEFAULT_BLOCK_AFTER}`,
      },
    };
  }

  const { effort } = await ctx.db.effort.get({ id: effortId });

  if (!effort) {
    return {
      ok: true,
      data: {
        sessionContext: "",
        effortId: null,
        sessionId: null,
        taskDir: null,
        skill: null,
        phase: null,
        heartbeat: `0/${DEFAULT_BLOCK_AFTER}`,
      },
    };
  }

  const taskDir = effort.taskId;
  const skill = effort.skill;
  const phase = effort.currentPhase ?? "none";

  // Parse threshold from effort metadata (auto-parsed by db-wrapper)
  let blockAfter = DEFAULT_BLOCK_AFTER;
  if (effort.metadata) {
    const meta = effort.metadata as Record<string, unknown>;
    if (meta && typeof meta.blockAfter === "number") {
      blockAfter = meta.blockAfter;
    }
  }
  const { session } = await ctx.db.session.find({ effortId });
  const sessionId = session ? session.id : null;
  const heartbeatCounter = session ? session.heartbeatCounter : 0;

  const heartbeat = `${heartbeatCounter}/${blockAfter}`;
  const timestamp = new Date().toISOString();

  const sessionContext =
    `[Session Context] Time: ${timestamp}` +
    ` | Session: ${taskDir}` +
    ` | Skill: ${skill}` +
    ` | Phase: ${phase}` +
    ` | Heartbeat: ${heartbeat}`;

  // Transcript ingestion — fire and forget, never block context delivery.
  if (engineSessionId) {
    ctx.agent?.messages?.ingest({
      sessionId: engineSessionId,
      transcriptPath: args.transcriptPath,
    })?.catch(() => {});
  }

  return {
    ok: true,
    data: {
      sessionContext,
      effortId,
      sessionId,
      taskDir,
      skill,
      phase,
      heartbeat,
    },
  };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "hooks.userPrompt": typeof handler;
  }
}

registerCommand("hooks.userPrompt", { schema, handler });
