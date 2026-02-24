/**
 * hooks.postToolUse — PostToolUse hook RPC.
 *
 * Called by the PostToolUse bash hook after every successful tool call.
 * Handles four concerns:
 *   1. Read heartbeat counter from the session
 *   2. Read and clear pending injections from effort metadata
 *   3. If toolName is "AskUserQuestion", format dialogue entry for response
 *   4. Trigger transcript ingestion (off the hot path — fire and forget)
 *
 * Returns heartbeat, injections, and dialogue entry so the bash hook can
 * act on them in a single round-trip.
 *
 * Input:  hookSchema({ toolName, toolInput, toolResponse, toolUseId })
 *
 * INV_RPC_GUARD_BEFORE_MUTATE: validates effort/session exist before writes.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import { hookSchema } from "./hook-base-schema.js";
import { resolveEngineIds } from "./resolve-engine-ids.js";

const DEFAULTS = {
  heartbeatCount: 0,
  pendingInjections: [] as Array<{ ruleId: string; content: string }>,
  dialogueEntry: null,
};

const schema = hookSchema({
  toolName: z.string(),
  toolInput: z.record(z.string(), z.unknown()),
  toolResponse: z.unknown(),
  toolUseId: z.string(),
});

type Args = z.infer<typeof schema>;

/**
 * Format AskUserQuestion input/output into a structured dialogue entry.
 */
function formatDialogueEntry(
  toolInput: Record<string, unknown> | undefined,
  toolOutput: string | undefined,
  agentPreamble: string | undefined
): { preamble: string; questions: Array<{ question: string; options: string[]; answer: string }> } | null {
  if (!toolInput?.questions) return null;

  const inputQuestions = toolInput.questions as Array<{
    question: string;
    options?: Array<{ label: string; description?: string }>;
  }>;

  // Parse tool output — array of { question, answer }
  let answers: Array<{ question: string; answer: string }> = [];
  if (toolOutput) {
    try {
      answers = JSON.parse(toolOutput);
    } catch {
      answers = [];
    }
  }

  const questions = inputQuestions.map((q) => {
    const matchingAnswer = answers.find((a) => a.question === q.question);
    return {
      question: q.question,
      options: (q.options ?? []).map((o) => o.label),
      answer: matchingAnswer?.answer ?? "",
    };
  });

  return {
    preamble: agentPreamble ?? "",
    questions,
  };
}

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ heartbeatCount: number; pendingInjections: Array<{ ruleId: string; content: string }>; dialogueEntry: unknown }>> {
  // 1. Resolve engine IDs from cwd
  const { effortId, engineSessionId } = await resolveEngineIds(args.cwd, ctx);

  if (!effortId) {
    return { ok: true, data: { ...DEFAULTS } };
  }

  const { effort } = await ctx.db.effort.get({ id: effortId });
  if (!effort) {
    return { ok: true, data: { ...DEFAULTS } };
  }

  // 2. Resolve session
  if (!engineSessionId) {
    return { ok: true, data: { ...DEFAULTS } };
  }

  const { session } = await ctx.db.session.get({ id: engineSessionId });
  if (!session) {
    return { ok: true, data: { ...DEFAULTS } };
  }

  // 3. Read heartbeat counter
  const heartbeatCount = session.heartbeatCounter ?? 0;

  // 4. Read and clear pending injections from effort metadata (auto-parsed by db-wrapper)
  let pendingInjections: Array<{ ruleId: string; content: string }> = [];

  if (effort.metadata) {
    const meta = effort.metadata as Record<string, unknown>;
    if (meta && Array.isArray(meta.pendingInjections)) {
      pendingInjections = meta.pendingInjections as Array<{ ruleId: string; content: string }>;
      // Clear pendingInjections from metadata
      await ctx.db.effort.updateMetadata({ id: effortId, remove: ["pendingInjections"] });
    }
  }

  // 5. Handle AskUserQuestion dialogue formatting (for response, not DB storage)
  let dialogueEntry: ReturnType<typeof formatDialogueEntry> = null;

  if (args.toolName === "AskUserQuestion") {
    const toolOutputStr = typeof args.toolResponse === "string" ? args.toolResponse : JSON.stringify(args.toolResponse ?? "");
    dialogueEntry = formatDialogueEntry(
      args.toolInput,
      toolOutputStr,
      ""
    );
  }

  // 6. Transcript ingestion — fire and forget, never block hook response.
  //    Messages are populated exclusively from transcript JSONL.
  ctx.agent?.messages?.ingest({
    sessionId: engineSessionId,
    transcriptPath: args.transcriptPath,
  })?.catch(() => {});

  // 7. Build hookSpecificOutput if there's content to inject
  const additionalContextParts: string[] = [];
  if (pendingInjections.length > 0) {
    for (const injection of pendingInjections) {
      additionalContextParts.push(`[Directive: ${injection.ruleId}]\n${injection.content}`);
    }
  }

  // 8. Return aggregated result
  const result: Record<string, unknown> = {
    heartbeatCount,
    pendingInjections,
    dialogueEntry,
  };

  if (additionalContextParts.length > 0) {
    result.hookSpecificOutput = {
      hookEventName: "PostToolUse",
      additionalContext: additionalContextParts.join("\n\n"),
    };
  }

  return { ok: true, data: result };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "hooks.postToolUse": typeof handler;
  }
}

registerCommand("hooks.postToolUse", { schema, handler });
