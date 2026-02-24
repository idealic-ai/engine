import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createGeminiClient, type GeminiClient } from "../gemini-client.js";

// Mock global fetch
const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

beforeEach(() => {
  mockFetch.mockReset();
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("createGeminiClient", () => {
  it("should throw if no API key provided", () => {
    expect(() => createGeminiClient("")).toThrow("API key is required");
  });

  it("should return an object with generateContent and embedContent", () => {
    const client = createGeminiClient("test-key");
    expect(typeof client.generateContent).toBe("function");
    expect(typeof client.embedContent).toBe("function");
  });
});

describe("generateContent", () => {
  let client: GeminiClient;

  beforeEach(() => {
    client = createGeminiClient("test-key");
  });

  it("should call Gemini REST API with correct URL and body", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        candidates: [
          {
            content: { parts: [{ text: "Hello from Gemini" }] },
          },
        ],
        usageMetadata: {
          promptTokenCount: 10,
          candidatesTokenCount: 5,
          totalTokenCount: 15,
        },
      }),
    });

    const result = await client.generateContent({
      prompt: "Say hello",
      model: "gemini-3-pro-preview",
      temperature: 0.3,
    });

    expect(mockFetch).toHaveBeenCalledOnce();
    const [url, options] = mockFetch.mock.calls[0];
    expect(url).toBe(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-preview:generateContent?key=test-key"
    );
    expect(options.method).toBe("POST");
    expect(options.headers["Content-Type"]).toBe("application/json");

    const body = JSON.parse(options.body);
    expect(body.contents[0].parts[0].text).toBe("Say hello");
    expect(body.generationConfig.temperature).toBe(0.3);

    expect(result.text).toBe("Hello from Gemini");
    expect(result.model).toBe("gemini-3-pro-preview");
    expect(result.usage).toEqual({
      promptTokenCount: 10,
      candidatesTokenCount: 5,
      totalTokenCount: 15,
    });
  });

  it("should include system instruction when provided", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        candidates: [{ content: { parts: [{ text: "OK" }] } }],
        usageMetadata: { promptTokenCount: 5, candidatesTokenCount: 1, totalTokenCount: 6 },
      }),
    });

    await client.generateContent({
      prompt: "Do something",
      system: "You are a helpful assistant",
      model: "gemini-3-pro-preview",
      temperature: 0.3,
    });

    const body = JSON.parse(mockFetch.mock.calls[0][1].body);
    expect(body.systemInstruction).toEqual({
      parts: [{ text: "You are a helpful assistant" }],
    });
  });

  it("should add responseSchema for structured output", async () => {
    const schema = { type: "object", properties: { name: { type: "string" } } };
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        candidates: [{ content: { parts: [{ text: '{"name":"test"}' }] } }],
        usageMetadata: { promptTokenCount: 5, candidatesTokenCount: 3, totalTokenCount: 8 },
      }),
    });

    const result = await client.generateContent({
      prompt: "Generate a name",
      model: "gemini-3-pro-preview",
      temperature: 0.3,
      responseSchema: schema,
    });

    const body = JSON.parse(mockFetch.mock.calls[0][1].body);
    expect(body.generationConfig.responseMimeType).toBe("application/json");
    expect(body.generationConfig.responseSchema).toEqual(schema);

    expect(result.text).toBe('{"name":"test"}');
  });

  it("should throw on HTTP error with status and message", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 429,
      json: async () => ({
        error: { message: "Rate limit exceeded", code: 429 },
      }),
    });

    await expect(
      client.generateContent({
        prompt: "test",
        model: "gemini-3-pro-preview",
        temperature: 0.3,
      })
    ).rejects.toThrow(/429.*Rate limit exceeded/);
  });

  it("should throw on network error", async () => {
    mockFetch.mockRejectedValueOnce(new Error("Network failure"));

    await expect(
      client.generateContent({
        prompt: "test",
        model: "gemini-3-pro-preview",
        temperature: 0.3,
      })
    ).rejects.toThrow("Network failure");
  });

  it("should throw on empty candidates", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        candidates: [],
        usageMetadata: { promptTokenCount: 5, candidatesTokenCount: 0, totalTokenCount: 5 },
      }),
    });

    await expect(
      client.generateContent({
        prompt: "test",
        model: "gemini-3-pro-preview",
        temperature: 0.3,
      })
    ).rejects.toThrow(/No content/);
  });
});

describe("embedContent", () => {
  let client: GeminiClient;

  beforeEach(() => {
    client = createGeminiClient("test-key");
  });

  it("should call Gemini embed REST API with correct URL and body", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        embedding: { values: [0.1, 0.2, 0.3] },
      }),
    });

    const result = await client.embedContent({
      text: "Hello world",
      model: "gemini-embedding-001",
      dimensions: 3072,
      taskType: "SEMANTIC_SIMILARITY",
    });

    expect(mockFetch).toHaveBeenCalledOnce();
    const [url, options] = mockFetch.mock.calls[0];
    expect(url).toBe(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent?key=test-key"
    );
    const body = JSON.parse(options.body);
    expect(body.content.parts[0].text).toBe("Hello world");
    expect(body.outputDimensionality).toBe(3072);
    expect(body.taskType).toBe("SEMANTIC_SIMILARITY");

    expect(result.embedding).toEqual([0.1, 0.2, 0.3]);
  });

  it("should throw on HTTP error", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 401,
      json: async () => ({
        error: { message: "API key invalid", code: 401 },
      }),
    });

    await expect(
      client.embedContent({
        text: "test",
        model: "gemini-embedding-001",
        dimensions: 3072,
        taskType: "SEMANTIC_SIMILARITY",
      })
    ).rejects.toThrow(/401.*API key invalid/);
  });

  it("should throw on missing embedding values", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({}),
    });

    await expect(
      client.embedContent({
        text: "test",
        model: "gemini-embedding-001",
        dimensions: 3072,
        taskType: "SEMANTIC_SIMILARITY",
      })
    ).rejects.toThrow(/No embedding/);
  });
});
