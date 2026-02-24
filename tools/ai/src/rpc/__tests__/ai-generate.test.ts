import { describe, it, expect, vi, beforeEach } from "vitest";
import { dispatch } from "../../../../shared/src/dispatch.js";

// Mock gemini-client module — all tests use controlled mocks, no real API calls
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

// Import the handler AFTER the mock is set up — registration is a side effect
import "../ai-generate.js";

// Default successful response mock
function setupGenerateMock(text: string = "Hello from Gemini", model: string = "gemini-3-pro-preview") {
  const mockGenerate = vi.fn().mockResolvedValue({
    text,
    model,
    usage: { promptTokenCount: 10, candidatesTokenCount: 5, totalTokenCount: 15 },
  });
  mockCreateGeminiClient.mockReturnValue({
    generateContent: mockGenerate,
    embedContent: vi.fn(),
  });
  return mockGenerate;
}

// No db needed for ai handlers — pass null
const db = null as any;

// Set a test API key
const ORIGINAL_ENV = process.env.GEMINI_API_KEY;

beforeEach(() => {
  vi.clearAllMocks();
  process.env.GEMINI_API_KEY = "test-api-key";
});

// Restore env after tests
import { afterAll } from "vitest";
afterAll(() => {
  if (ORIGINAL_ENV) {
    process.env.GEMINI_API_KEY = ORIGINAL_ENV;
  } else {
    delete process.env.GEMINI_API_KEY;
  }
});

describe("ai.generate", () => {
  it("should generate text with default model and temperature", async () => {
    setupGenerateMock("Generated response");

    const result = await dispatch(
      { cmd: "ai.generate", args: { prompt: "Say hello" } },
      db,
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.text).toBe("Generated response");
    expect(result.data.model).toBe("gemini-3-pro-preview");
    expect(result.data.usage).toBeDefined();
  });

  it("should pass prompt and temperature to gemini client", async () => {
    const mockGenerate = setupGenerateMock();

    await dispatch(
      { cmd: "ai.generate", args: { prompt: "Test prompt", temperature: 0.8 } },
      db,
    );

    expect(mockGenerate).toHaveBeenCalledOnce();
    const callArgs = mockGenerate.mock.calls[0][0];
    expect(callArgs.prompt).toBe("Test prompt");
    expect(callArgs.temperature).toBe(0.8);
  });

  it("should pass system instruction when provided", async () => {
    const mockGenerate = setupGenerateMock();

    await dispatch(
      {
        cmd: "ai.generate",
        args: {
          prompt: "Do something",
          system: "You are a helpful assistant",
        },
      },
      db,
    );

    const callArgs = mockGenerate.mock.calls[0][0];
    expect(callArgs.system).toBe("You are a helpful assistant");
  });

  it("should pass responseSchema for structured output", async () => {
    const schema = { type: "object", properties: { name: { type: "string" } } };
    const mockGenerate = vi.fn().mockResolvedValue({
      text: '{"name":"test"}',
      model: "gemini-3-pro-preview",
      usage: { promptTokenCount: 5, candidatesTokenCount: 3, totalTokenCount: 8 },
    });
    mockCreateGeminiClient.mockReturnValue({
      generateContent: mockGenerate,
      embedContent: vi.fn(),
    });

    const result = await dispatch(
      {
        cmd: "ai.generate",
        args: { prompt: "Generate name", responseSchema: schema },
      },
      db,
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;

    // Should pass responseSchema through to client
    const callArgs = mockGenerate.mock.calls[0][0];
    expect(callArgs.responseSchema).toEqual(schema);

    // Should parse JSON and include in response
    expect(result.data.json).toEqual({ name: "test" });
    expect(result.data.text).toBe('{"name":"test"}');
  });

  it("should use custom model when specified", async () => {
    const mockGenerate = setupGenerateMock("Custom model response", "gemini-2.5-pro");

    await dispatch(
      {
        cmd: "ai.generate",
        args: { prompt: "Test", model: "gemini-2.5-pro" },
      },
      db,
    );

    const callArgs = mockGenerate.mock.calls[0][0];
    expect(callArgs.model).toBe("gemini-2.5-pro");
  });

  it("should use default temperature 0.3 when not specified", async () => {
    const mockGenerate = setupGenerateMock();

    await dispatch(
      { cmd: "ai.generate", args: { prompt: "Test" } },
      db,
    );

    const callArgs = mockGenerate.mock.calls[0][0];
    expect(callArgs.temperature).toBe(0.3);
  });

  it("should return error when API key is missing", async () => {
    delete process.env.GEMINI_API_KEY;

    const result = await dispatch(
      { cmd: "ai.generate", args: { prompt: "Test" } },
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
      generateContent: vi.fn().mockRejectedValue(
        new GeminiError(429, "Rate limit exceeded"),
      ),
      embedContent: vi.fn(),
    });

    const result = await dispatch(
      { cmd: "ai.generate", args: { prompt: "Test" } },
      db,
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("RATE_LIMIT");
    expect(result.message).toMatch(/429/);
  });

  it("should return error on auth failure (401)", async () => {
    const { GeminiError } = await import("../../gemini-client.js");
    mockCreateGeminiClient.mockReturnValue({
      generateContent: vi.fn().mockRejectedValue(
        new GeminiError(401, "API key invalid"),
      ),
      embedContent: vi.fn(),
    });

    const result = await dispatch(
      { cmd: "ai.generate", args: { prompt: "Test" } },
      db,
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("AUTH_ERROR");
    expect(result.message).toMatch(/401/);
  });

  it("should return error on generic API failure", async () => {
    const { GeminiError } = await import("../../gemini-client.js");
    mockCreateGeminiClient.mockReturnValue({
      generateContent: vi.fn().mockRejectedValue(
        new GeminiError(500, "Internal server error"),
      ),
      embedContent: vi.fn(),
    });

    const result = await dispatch(
      { cmd: "ai.generate", args: { prompt: "Test" } },
      db,
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("API_ERROR");
    expect(result.message).toMatch(/500/);
  });

  it("should fail validation when prompt is missing", async () => {
    const result = await dispatch(
      { cmd: "ai.generate", args: {} },
      db,
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("VALIDATION_ERROR");
  });

  it("should handle malformed structured output JSON gracefully", async () => {
    const mockGenerate = vi.fn().mockResolvedValue({
      text: "not valid json",
      model: "gemini-3-pro-preview",
      usage: { promptTokenCount: 5, candidatesTokenCount: 3, totalTokenCount: 8 },
    });
    mockCreateGeminiClient.mockReturnValue({
      generateContent: mockGenerate,
      embedContent: vi.fn(),
    });

    const result = await dispatch(
      {
        cmd: "ai.generate",
        args: {
          prompt: "Generate",
          responseSchema: { type: "object" },
        },
      },
      db,
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("PARSE_ERROR");
    expect(result.message).toMatch(/JSON/i);
  });
});
