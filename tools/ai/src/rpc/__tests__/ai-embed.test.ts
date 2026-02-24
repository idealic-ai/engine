import { describe, it, expect, vi, beforeEach } from "vitest";
import { dispatch } from "../../../../shared/src/dispatch.js";

// Mock gemini-client module
const mockCreateGeminiClient = vi.fn();
vi.mock("../../gemini-client.js", () => ({
  createGeminiClient: (...args: unknown[]) => mockCreateGeminiClient(...args),
  GeminiError: class GeminiError extends Error {
    statusCode: number;
    constructor(statusCode: number, message: string) {
      super(`Gemini API error ${statusCode}: ${message}`);
      this.name = "GeminiError";
      this.statusCode = statusCode;
    }
  },
}));

// Import the handler AFTER the mock is set up
import "../ai-embed.js";

// Helper to set up embed mock
function setupEmbedMock(embeddings: number[][] = [[0.1, 0.2, 0.3]]) {
  let callIndex = 0;
  const mockEmbed = vi.fn().mockImplementation(async () => ({
    embedding: embeddings[callIndex++] ?? embeddings[embeddings.length - 1],
  }));
  mockCreateGeminiClient.mockReturnValue({
    generateContent: vi.fn(),
    embedContent: mockEmbed,
  });
  return mockEmbed;
}

const db = null as any;
const ORIGINAL_ENV = process.env.GEMINI_API_KEY;

beforeEach(() => {
  vi.clearAllMocks();
  process.env.GEMINI_API_KEY = "test-api-key";
});

import { afterAll } from "vitest";
afterAll(() => {
  if (ORIGINAL_ENV) {
    process.env.GEMINI_API_KEY = ORIGINAL_ENV;
  } else {
    delete process.env.GEMINI_API_KEY;
  }
});

describe("ai.embed", () => {
  it("should embed a single text", async () => {
    setupEmbedMock([[0.1, 0.2, 0.3]]);

    const result = await dispatch(
      { cmd: "ai.embed", args: { texts: ["Hello world"] } },
      db,
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.embeddings).toHaveLength(1);
    expect(result.data.embeddings[0]).toEqual([0.1, 0.2, 0.3]);
    expect(result.data.model).toBe("gemini-embedding-001");
  });

  it("should embed multiple texts (batch)", async () => {
    setupEmbedMock([
      [0.1, 0.2, 0.3],
      [0.4, 0.5, 0.6],
      [0.7, 0.8, 0.9],
    ]);

    const result = await dispatch(
      { cmd: "ai.embed", args: { texts: ["one", "two", "three"] } },
      db,
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.embeddings).toHaveLength(3);
    expect(result.data.embeddings[0]).toEqual([0.1, 0.2, 0.3]);
    expect(result.data.embeddings[1]).toEqual([0.4, 0.5, 0.6]);
    expect(result.data.embeddings[2]).toEqual([0.7, 0.8, 0.9]);
  });

  it("should pass correct params to embedContent", async () => {
    const mockEmbed = setupEmbedMock();

    await dispatch(
      { cmd: "ai.embed", args: { texts: ["test text"] } },
      db,
    );

    expect(mockEmbed).toHaveBeenCalledOnce();
    const callArgs = mockEmbed.mock.calls[0][0];
    expect(callArgs.text).toBe("test text");
    expect(callArgs.model).toBe("gemini-embedding-001");
    expect(callArgs.dimensions).toBe(3072);
    expect(callArgs.taskType).toBe("SEMANTIC_SIMILARITY");
  });

  it("should use custom model when specified", async () => {
    const mockEmbed = setupEmbedMock();

    await dispatch(
      {
        cmd: "ai.embed",
        args: { texts: ["test"], model: "custom-embed-model" },
      },
      db,
    );

    const callArgs = mockEmbed.mock.calls[0][0];
    expect(callArgs.model).toBe("custom-embed-model");
  });

  it("should use custom dimensions when specified", async () => {
    const mockEmbed = setupEmbedMock();

    await dispatch(
      { cmd: "ai.embed", args: { texts: ["test"], dimensions: 768 } },
      db,
    );

    const callArgs = mockEmbed.mock.calls[0][0];
    expect(callArgs.dimensions).toBe(768);
  });

  it("should use custom taskType when specified", async () => {
    const mockEmbed = setupEmbedMock();

    await dispatch(
      {
        cmd: "ai.embed",
        args: { texts: ["test"], taskType: "RETRIEVAL_DOCUMENT" },
      },
      db,
    );

    const callArgs = mockEmbed.mock.calls[0][0];
    expect(callArgs.taskType).toBe("RETRIEVAL_DOCUMENT");
  });

  it("should return error when API key is missing", async () => {
    delete process.env.GEMINI_API_KEY;

    const result = await dispatch(
      { cmd: "ai.embed", args: { texts: ["test"] } },
      db,
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("API_KEY_MISSING");
    expect(result.message).toMatch(/GEMINI_API_KEY/);
  });

  it("should return error on rate limit (429)", async () => {
    const { GeminiError } = await import("../../gemini-client.js");
    mockCreateGeminiClient.mockReturnValue({
      generateContent: vi.fn(),
      embedContent: vi.fn().mockRejectedValue(
        new GeminiError(429, "Rate limit exceeded"),
      ),
    });

    const result = await dispatch(
      { cmd: "ai.embed", args: { texts: ["test"] } },
      db,
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("RATE_LIMIT");
  });

  it("should return error on auth failure (401)", async () => {
    const { GeminiError } = await import("../../gemini-client.js");
    mockCreateGeminiClient.mockReturnValue({
      generateContent: vi.fn(),
      embedContent: vi.fn().mockRejectedValue(
        new GeminiError(401, "API key invalid"),
      ),
    });

    const result = await dispatch(
      { cmd: "ai.embed", args: { texts: ["test"] } },
      db,
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("AUTH_ERROR");
  });

  it("should fail validation when texts is missing", async () => {
    const result = await dispatch(
      { cmd: "ai.embed", args: {} },
      db,
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("VALIDATION_ERROR");
  });

  it("should fail validation when texts is empty array", async () => {
    const result = await dispatch(
      { cmd: "ai.embed", args: { texts: [] } },
      db,
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("EMPTY_TEXTS");
    expect(result.message).toMatch(/empty/i);
  });
});
