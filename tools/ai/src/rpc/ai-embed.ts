/**
 * ai.embed — Batch text embedding via Gemini REST API.
 *
 * Provider-agnostic RPC handler. Embeds each text individually via
 * the shared Gemini client and returns raw number arrays. Callers
 * convert to Float32Array if needed (e.g., for search.upsert).
 *
 * This handler does NOT use the db parameter — it's a pure AI namespace RPC.
 */
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { RpcContext } from "engine-shared/context";
import { createGeminiClient, GeminiError } from "../gemini-client.js";

const DEFAULT_MODEL = "gemini-embedding-001";
const DEFAULT_DIMENSIONS = 3072;
const DEFAULT_TASK_TYPE = "SEMANTIC_SIMILARITY";

const schema = z.object({
  texts: z.array(z.string()),
  model: z.string().optional(),
  dimensions: z.number().int().positive().optional(),
  taskType: z.string().optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, _ctx: RpcContext): Promise<TypedRpcResponse<{ embeddings: number[][]; model: string }>> {
  if (args.texts.length === 0) {
    return {
      ok: false,
      error: "EMPTY_TEXTS",
      message: "texts array is empty — provide at least one text to embed",
    };
  }

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return {
      ok: false,
      error: "API_KEY_MISSING",
      message: "GEMINI_API_KEY environment variable is required for ai.embed",
    };
  }

  const model = args.model ?? DEFAULT_MODEL;
  const dimensions = args.dimensions ?? DEFAULT_DIMENSIONS;
  const taskType = args.taskType ?? DEFAULT_TASK_TYPE;

  try {
    const client = createGeminiClient(apiKey);

    // Embed each text individually (Gemini embedContent is single-text)
    const embeddings: number[][] = [];
    for (const text of args.texts) {
      const result = await client.embedContent({
        text,
        model,
        dimensions,
        taskType,
      });
      embeddings.push(result.embedding);
    }

    return {
      ok: true,
      data: {
        embeddings,
        model,
      },
    };
  } catch (err: unknown) {
    if (err instanceof GeminiError) {
      const errorType =
        err.statusCode === 429
          ? "RATE_LIMIT"
          : err.statusCode === 401 || err.statusCode === 403
            ? "AUTH_ERROR"
            : "API_ERROR";

      return {
        ok: false,
        error: errorType,
        message: err.message,
      };
    }

    throw err;
  }
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "ai.embed": typeof handler;
  }
}

registerCommand("ai.embed", { schema, handler });
