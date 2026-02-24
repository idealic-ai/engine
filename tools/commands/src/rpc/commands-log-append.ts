/**
 * commands.log.append — Append content to an effort-prefixed log file.
 *
 * Finds the active effort for a task, derives the effort-prefixed filename,
 * injects a timestamp into the first ## heading, and appends content.
 *
 * Flow:
 *   1. Find active effort for dirPath
 *   2. Derive file path: {dirPath}/{ordinal}_{SKILL_UPPER}_{logType}.md
 *   3. Inject timestamp into first ## heading
 *   4. fs.files.append via dispatch (create file if missing)
 *   5. Reset heartbeat counter
 */
import * as path from "node:path";
import { z } from "zod/v4";
import { registerCommand, dispatch } from "engine-shared/dispatch";
import type { RpcContext } from "engine-shared/context";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { EffortRow } from "../format.js";

const schema = z.object({
  dirPath: z.string(),
  content: z.string(),
  logType: z.string().optional().default("LOG"),
});

type Args = z.infer<typeof schema>;

interface LogAppendData {
  filePath: string;
  effortOrdinal: number;
  skill: string;
}

export async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<LogAppendData>> {
  try {
    // 1. Find active effort
    const listData = await ctx.db.effort.list({ taskId: args.dirPath });
    const efforts = (listData.efforts as EffortRow[]) ?? [];
    const activeEffort = efforts.find((e) => e.lifecycle === "active");

    if (!activeEffort) {
      return {
        ok: false,
        error: "NO_ACTIVE_EFFORT",
        message: `No active effort found for task ${args.dirPath}`,
      };
    }

    // 2. Derive file path
    const skillUpper = activeEffort.skill.toUpperCase();
    const fileName = `${activeEffort.ordinal}_${skillUpper}_${args.logType}.md`;
    const filePath = path.join(args.dirPath, fileName);

    // 3. Inject timestamp into first ## heading
    const now = new Date().toISOString().replace("T", " ").replace(/\.\d+Z$/, "");
    const content = injectTimestamp(args.content, now);

    // 4. Append via fs.files.append RPC (fs.* not typed yet — use dispatch)
    const appendResult = await dispatch({
      cmd: "fs.files.append",
      args: { path: filePath, content },
    }, ctx);

    if (!appendResult.ok) {
      return { ok: false, error: "COMMAND_ERROR", message: `Failed to append: ${(appendResult as { message: string }).message}` };
    }

    // 5. Reset heartbeat — find the active session for this effort
    try {
      const sessionData = await ctx.db.session.find({ effortId: activeEffort.id });
      const session = sessionData.session;
      if (session?.id) {
        await ctx.db.session.heartbeat({ sessionId: session.id });
      }
    } catch {
      // Best-effort heartbeat — don't fail the append
    }

    return {
      ok: true,
      data: {
        filePath,
        effortOrdinal: activeEffort.ordinal,
        skill: activeEffort.skill,
      },
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return { ok: false, error: "COMMAND_ERROR", message };
  }
}

/**
 * Inject timestamp into the first ## heading.
 * "## My Heading" → "## [2026-02-21 02:45:00] My Heading"
 */
function injectTimestamp(content: string, timestamp: string): string {
  return content.replace(
    /^(## )/m,
    `$1[${timestamp}] `
  );
}

/** Exported for testing */
export { injectTimestamp };

registerCommand("commands.log.append", { schema, handler });

declare module "engine-shared/rpc-types" {
  interface Registered {
    "commands.log.append": typeof handler;
  }
}
