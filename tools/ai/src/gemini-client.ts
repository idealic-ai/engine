/**
 * gemini-client.ts — Shared Gemini REST API client.
 *
 * Uses raw HTTP (global fetch) instead of @google/genai SDK for provider
 * swappability. The model string determines the provider — currently only
 * Gemini is implemented, but the ai.* RPC namespace is provider-agnostic.
 *
 * Two operations:
 *   generateContent — text generation with optional structured output
 *   embedContent    — single-text embedding
 */

const GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta";

// ── Types ──────────────────────────────────────────────

export interface GenerateParams {
  prompt: string;
  system?: string;
  model: string;
  temperature: number;
  responseSchema?: Record<string, unknown>;
}

export interface GenerateResult {
  text: string;
  model: string;
  usage: {
    promptTokenCount: number;
    candidatesTokenCount: number;
    totalTokenCount: number;
  };
}

export interface EmbedParams {
  text: string;
  model: string;
  dimensions: number;
  taskType: string;
}

export interface EmbedResult {
  embedding: number[];
}

export interface GeminiClient {
  generateContent(params: GenerateParams): Promise<GenerateResult>;
  embedContent(params: EmbedParams): Promise<EmbedResult>;
}

// ── Error class ────────────────────────────────────────

export class GeminiError extends Error {
  constructor(
    public statusCode: number,
    message: string,
  ) {
    super(`Gemini API error ${statusCode}: ${message}`);
    this.name = "GeminiError";
  }
}

// ── Client factory ─────────────────────────────────────

export function createGeminiClient(
  apiKey: string,
  baseUrl: string = GEMINI_BASE_URL,
): GeminiClient {
  if (!apiKey) {
    throw new Error("API key is required");
  }

  async function generateContent(params: GenerateParams): Promise<GenerateResult> {
    const url = `${baseUrl}/models/${params.model}:generateContent?key=${apiKey}`;

    // Build request body
    const body: Record<string, unknown> = {
      contents: [{ parts: [{ text: params.prompt }] }],
      generationConfig: {
        temperature: params.temperature,
        ...(params.responseSchema
          ? {
              responseMimeType: "application/json",
              responseSchema: params.responseSchema,
            }
          : {}),
      },
    };

    if (params.system) {
      body.systemInstruction = { parts: [{ text: params.system }] };
    }

    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({ error: { message: "Unknown error" } }));
      const msg = errorData?.error?.message ?? "Unknown error";
      throw new GeminiError(response.status, msg);
    }

    const data = await response.json();

    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (text === undefined || text === null) {
      throw new Error("No content in Gemini response — empty candidates");
    }

    const usage = data?.usageMetadata ?? {
      promptTokenCount: 0,
      candidatesTokenCount: 0,
      totalTokenCount: 0,
    };

    return {
      text,
      model: params.model,
      usage: {
        promptTokenCount: usage.promptTokenCount ?? 0,
        candidatesTokenCount: usage.candidatesTokenCount ?? 0,
        totalTokenCount: usage.totalTokenCount ?? 0,
      },
    };
  }

  async function embedContent(params: EmbedParams): Promise<EmbedResult> {
    const url = `${baseUrl}/models/${params.model}:embedContent?key=${apiKey}`;

    const body = {
      content: { parts: [{ text: params.text }] },
      outputDimensionality: params.dimensions,
      taskType: params.taskType,
    };

    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({ error: { message: "Unknown error" } }));
      const msg = errorData?.error?.message ?? "Unknown error";
      throw new GeminiError(response.status, msg);
    }

    const data = await response.json();

    const values = data?.embedding?.values;
    if (!values || !Array.isArray(values)) {
      throw new Error("No embedding values in Gemini response");
    }

    return { embedding: values };
  }

  return { generateContent, embedContent };
}
