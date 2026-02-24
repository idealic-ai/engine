/**
 * Shared test helpers for mocking the Gemini client in RPC handler tests.
 *
 * These factories return mock implementations for vi.mock("../gemini-client.js").
 * Both ai.generate and ai.embed test files use these.
 */
import { vi } from "vitest";
import type { GeminiClient, GenerateResult, EmbedResult } from "../gemini-client.js";

/**
 * Create a mock GeminiClient where generateContent resolves with the given result.
 */
export function mockGeminiGenerate(result: GenerateResult): GeminiClient {
  return {
    generateContent: vi.fn().mockResolvedValue(result),
    embedContent: vi.fn().mockRejectedValue(new Error("embedContent not expected")),
  };
}

/**
 * Create a mock GeminiClient where embedContent resolves with the given result.
 */
export function mockGeminiEmbed(result: EmbedResult): GeminiClient {
  return {
    generateContent: vi.fn().mockRejectedValue(new Error("generateContent not expected")),
    embedContent: vi.fn().mockResolvedValue(result),
  };
}

/**
 * Create a mock GeminiClient where the specified method throws a GeminiError.
 */
export function mockGeminiError(
  method: "generate" | "embed",
  statusCode: number,
  message: string,
): GeminiClient {
  const { GeminiError } = require("../gemini-client.js");
  const error = new GeminiError(statusCode, message);

  if (method === "generate") {
    return {
      generateContent: vi.fn().mockRejectedValue(error),
      embedContent: vi.fn().mockRejectedValue(new Error("embedContent not expected")),
    };
  } else {
    return {
      generateContent: vi.fn().mockRejectedValue(new Error("generateContent not expected")),
      embedContent: vi.fn().mockRejectedValue(error),
    };
  }
}

/**
 * Default successful generate response for quick tests.
 */
export const DEFAULT_GENERATE_RESULT: GenerateResult = {
  text: "Generated text",
  model: "gemini-3-pro-preview",
  usage: {
    promptTokenCount: 10,
    candidatesTokenCount: 5,
    totalTokenCount: 15,
  },
};

/**
 * Default successful embed response for quick tests.
 */
export const DEFAULT_EMBED_RESULT: EmbedResult = {
  embedding: Array.from({ length: 10 }, (_, i) => i * 0.1),
};
