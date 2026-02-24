/**
 * ai.generate — Text generation via Gemini REST API.
 *
 * Provider-agnostic RPC handler. Model string determines the provider
 * (currently only Gemini). Supports structured output via responseSchema.
 *
 * This handler does NOT use the db parameter — it's a pure AI namespace RPC.
 * The handler signature stays uniform (args, db) per ¶INV_RPC_SELF_REGISTERING.
 */
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { RpcContext } from "engine-shared/context";
import { createGeminiClient, GeminiError } from "../gemini-client.js";

const DEFAULT_MODEL = "gemini-3-pro-preview";
const DEFAULT_TEMPERATURE = 0.3;

const schema = z.object({
  prompt: z.string(),
  system: z.string().optional(),
  model: z.string().optional(),
  temperature: z.number().optional(),
  responseSchema: z.record(z.string(), z.unknown()).optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, _ctx: RpcContext): Promise<TypedRpcResponse<{ text: string; model: string; usage: unknown; json?: unknown }>> {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return {
      ok: false,
      error: "API_KEY_MISSING",
      message: "GEMINI_API_KEY environment variable is required for ai.generate",
    };
  }

  const model = args.model ?? DEFAULT_MODEL;
  const temperature = args.temperature ?? DEFAULT_TEMPERATURE;

  try {
    const client = createGeminiClient(apiKey);
    const result = await client.generateContent({
      prompt: args.prompt,
      system: args.system,
      model,
      temperature,
      responseSchema: args.responseSchema,
    });

    // If structured output was requested, parse the JSON
    if (args.responseSchema) {
      let json: unknown;
      try {
        json = JSON.parse(result.text);
      } catch {
        return {
          ok: false,
          error: "PARSE_ERROR",
          message: `Failed to parse structured JSON output: ${result.text.slice(0, 200)}`,
        };
      }

      return {
        ok: true,
        data: {
          json,
          text: result.text,
          model: result.model,
          usage: result.usage,
        },
      };
    }

    return {
      ok: true,
      data: {
        text: result.text,
        model: result.model,
        usage: result.usage,
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

    throw err; // Let dispatch's catch handler wrap unknown errors
  }
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "ai.generate": typeof handler;
  }
}

registerCommand("ai.generate", { schema, handler });
