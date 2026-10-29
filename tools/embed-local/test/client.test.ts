/**
 * Unit tests for the shared local embedding client. No network: every test
 * passes a fake `fetch`. Runs with vitest globals (see package.json "test"),
 * so this file imports nothing from vitest and embed-local stays dependency-free.
 */
import { createLocalEmbeddingClient, INDEXER_EMBED_RETRY, retryDelayMs } from "../src/client.js";
import { EMBED_LOCAL_DEFAULTS, resolveEmbedConfig } from "../src/config.js";
import type { EmbedConfig } from "../src/contract.js";
import { EmbedLocalError } from "../src/errors.js";

interface Call {
  url: string;
  body: { model: string; input: string[] } | null;
}

function config(overrides: Partial<EmbedConfig> = {}): EmbedConfig {
  return { ...resolveEmbedConfig({}), dimensions: 4, batchSize: 3, ...overrides };
}

/** A fake runner that answers each text with a vector of `width`, recording every request. */
function fakeRunner(width = 4, status = 200) {
  const calls: Call[] = [];
  const fetchImpl = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    const body = init?.body ? (JSON.parse(String(init.body)) as Call["body"]) : null;
    calls.push({ url, body });
    if (status !== 200) return new Response("nope", { status });
    const n = body?.input.length ?? 0;
    const embeddings = Array.from({ length: n }, (_, i) => Array.from({ length: width }, (_, j) => i + j / 10));
    return new Response(JSON.stringify({ embeddings }), { status: 200 });
  }) as typeof fetch;
  return { calls, fetchImpl };
}

async function caught(p: Promise<unknown>): Promise<EmbedLocalError> {
  try {
    await p;
  } catch (err) {
    if (err instanceof EmbedLocalError) return err;
    throw err;
  }
  throw new Error("expected a rejection");
}

describe("config", () => {
  it("defaults to embeddinggemma at 768 on loopback, with ideas' prefixes", () => {
    const c = resolveEmbedConfig({});
    expect(c.model).toBe("embeddinggemma");
    expect(c.dimensions).toBe(768);
    expect(c.endpoint).toBe("http://127.0.0.1:11434");
    expect(c.documentPrefix).toBe("title: none | text: ");
    expect(c.queryPrefix).toBe("task: search result | query: ");
  });

  it("honours endpoint, model, dimensions and batch overrides", () => {
    const c = resolveEmbedConfig({
      ENGINE_EMBED_ENDPOINT: "http://box:9999/",
      ENGINE_EMBED_MODEL: "nomic-embed-text",
      ENGINE_EMBED_DIMENSIONS: "512",
      ENGINE_EMBED_BATCH: "64",
    });
    expect(c).toMatchObject({ endpoint: "http://box:9999", model: "nomic-embed-text", dimensions: 512, batchSize: 64 });
  });

  it("refuses a dimensions value that is not a positive whole number, by name", () => {
    expect(() => resolveEmbedConfig({ ENGINE_EMBED_DIMENSIONS: "wide" })).toThrow(/CONFIG_INVALID/);
    expect(() => resolveEmbedConfig({ ENGINE_EMBED_BATCH: "0" })).toThrow(/CONFIG_INVALID/);
  });
});

describe("batching", () => {
  it("sends ceil(n / batchSize) requests and returns every vector in order", async () => {
    const { calls, fetchImpl } = fakeRunner();
    const progress: Array<[number, number]> = [];
    const client = createLocalEmbeddingClient({
      config: config({ batchSize: 3 }),
      fetchImpl,
      onProgress: (done, total) => progress.push([done, total]),
    });
    const texts = ["a", "b", "c", "d", "e", "f", "g"];
    const out = await client.embedTexts(texts);

    expect(calls).toHaveLength(3);
    expect(calls.map((c) => c.body?.input.length)).toEqual([3, 3, 1]);
    expect(calls.every((c) => c.url === "http://127.0.0.1:11434/api/embed")).toBe(true);
    expect(out).toHaveLength(7);
    expect(out.every((v) => v instanceof Float32Array && v.length === 4)).toBe(true);
    // first vector of the second batch is that batch's index 0 → [0, .1, .2, .3]
    expect(Array.from(out[3])).toEqual(Array.from(Float32Array.from([0, 0.1, 0.2, 0.3])));
    expect(progress).toEqual([[3, 7], [6, 7], [7, 7]]);
  });

  it("embedTexts([]) sends nothing and returns []", async () => {
    const { calls, fetchImpl } = fakeRunner();
    const client = createLocalEmbeddingClient({ config: config(), fetchImpl });
    expect(await client.embedTexts([])).toEqual([]);
    expect(calls).toHaveLength(0);
  });

  it("an explicit empty embed is a named EMPTY_TEXTS failure", async () => {
    const { fetchImpl } = fakeRunner();
    const client = createLocalEmbeddingClient({ config: config(), fetchImpl });
    expect((await caught(client.embed([], "document"))).code).toBe("EMPTY_TEXTS");
  });
});

describe("roles", () => {
  it("embedTexts uses the document prefix, embedSingle the query prefix, and the configured model", async () => {
    const { calls, fetchImpl } = fakeRunner();
    const client = createLocalEmbeddingClient({ config: config(), fetchImpl });
    await client.embedTexts(["stored text"]);
    await client.embedSingle("what was decided");

    expect(calls[0].body).toEqual({ model: "embeddinggemma", input: [`${EMBED_LOCAL_DEFAULTS.documentPrefix}stored text`] });
    expect(calls[1].body).toEqual({ model: "embeddinggemma", input: [`${EMBED_LOCAL_DEFAULTS.queryPrefix}what was decided`] });
  });

  it("exposes model and dimensions for callers to store beside each row", () => {
    const client = createLocalEmbeddingClient({ config: config({ dimensions: 768 }), fetchImpl: fakeRunner().fetchImpl });
    expect(client.model).toBe("embeddinggemma");
    expect(client.dimensions).toBe(768);
  });
});

describe("named failures", () => {
  it("a vector of the wrong width is DIMENSION_UNEXPECTED and no vectors are returned", async () => {
    const { fetchImpl } = fakeRunner(3072);
    const client = createLocalEmbeddingClient({ config: config({ dimensions: 768 }), fetchImpl });
    const err = await caught(client.embedTexts(["x"]));
    expect(err.code).toBe("DIMENSION_UNEXPECTED");
    expect(err.message).toMatch(/3072-wide/);
    expect(err.message).toMatch(/768/);
  });

  it("a count mismatch is PROVIDER_ERROR", async () => {
    const fetchImpl = (async () =>
      new Response(JSON.stringify({ embeddings: [[1, 2, 3, 4]] }), { status: 200 })) as typeof fetch;
    const client = createLocalEmbeddingClient({ config: config(), fetchImpl });
    expect((await caught(client.embedTexts(["a", "b"]))).code).toBe("PROVIDER_ERROR");
  });

  it("a refused connection is RUNNER_ABSENT, naming the endpoint", async () => {
    const fetchImpl = (async () => {
      throw Object.assign(new TypeError("fetch failed"), { cause: { code: "ECONNREFUSED" } });
    }) as typeof fetch;
    const client = createLocalEmbeddingClient({ config: config(), fetchImpl });
    const err = await caught(client.embedSingle("q"));
    expect(err.code).toBe("RUNNER_ABSENT");
    expect(err.message).toMatch(/127\.0\.0\.1:11434/);
  });

  it("404 is MODEL_ABSENT, or MODEL_LOADING while a download is in flight", async () => {
    const { fetchImpl } = fakeRunner(4, 404);
    const absent = createLocalEmbeddingClient({ config: config(), fetchImpl, isDownloading: () => false });
    const loading = createLocalEmbeddingClient({ config: config(), fetchImpl, isDownloading: () => true });
    expect((await caught(absent.embedSingle("q"))).code).toBe("MODEL_ABSENT");
    expect((await caught(loading.embedSingle("q"))).code).toBe("MODEL_LOADING");
  });

  it("501 is RUNNER_LACKS_EMBEDDINGS, 503 is RUNNER_BUSY, any other non-2xx is PROVIDER_ERROR", async () => {
    for (const [status, code] of [[501, "RUNNER_LACKS_EMBEDDINGS"], [503, "RUNNER_BUSY"], [500, "PROVIDER_ERROR"]] as const) {
      const client = createLocalEmbeddingClient({ config: config(), fetchImpl: fakeRunner(4, status).fetchImpl });
      expect((await caught(client.embedSingle("q"))).code).toBe(code);
    }
  });
});

describe("health", () => {
  it("is ready when the model tag is listed, model_absent when not", async () => {
    const tags = (names: string[]) =>
      (async () => new Response(JSON.stringify({ models: names.map((name) => ({ name })) }), { status: 200 })) as typeof fetch;
    const ready = createLocalEmbeddingClient({ config: config(), fetchImpl: tags(["embeddinggemma:latest"]) });
    const absent = createLocalEmbeddingClient({ config: config(), fetchImpl: tags(["gemma3:27b"]), isDownloading: () => false });
    expect((await ready.health()).state).toBe("ready");
    expect((await absent.health()).state).toBe("model_absent");
    const otherTag = createLocalEmbeddingClient({ config: config(), fetchImpl: tags(["embeddinggemma:300m"]), isDownloading: () => false });
    expect((await otherTag.health()).state).toBe("model_absent");
  });
});

/** A runner that accepts the request and never answers until the request's signal aborts. */
function stallingFetch(stage: "headers" | "body") {
  let calls = 0;
  const fetchImpl = (async (_input: string | URL | Request, init?: RequestInit) => {
    calls++;
    const signal = init?.signal;
    const stall = () =>
      new Promise<never>((_, reject) => {
        if (!signal) return; // no signal: hangs forever, which is the bug under test
        if (signal.aborted) reject(signal.reason);
        signal.addEventListener("abort", () => reject(signal.reason), { once: true });
      });
    if (stage === "headers") return stall();
    const body = new ReadableStream({
      start(controller) {
        signal?.addEventListener("abort", () => controller.error(signal.reason), { once: true });
      },
    });
    return new Response(body, { status: 200 });
  }) as typeof fetch;
  return { fetchImpl, count: () => calls };
}

/** A runner that answers each request with the next status in `statuses` (200 = real vectors). */
function scriptedRunner(statuses: number[], width = 4) {
  let i = 0;
  const fetchImpl = (async (_input: string | URL | Request, init?: RequestInit) => {
    const status = statuses[Math.min(i, statuses.length - 1)];
    i++;
    if (status !== 200) return new Response("busy", { status });
    const n = (JSON.parse(String(init?.body)) as { input: string[] }).input.length;
    return new Response(JSON.stringify({ embeddings: Array.from({ length: n }, () => Array(width).fill(0.5)) }), {
      status: 200,
    });
  }) as typeof fetch;
  return { fetchImpl, count: () => i };
}

/** Bound a test so a missing timeout fails it instead of hanging the suite. */
function within<T>(p: Promise<T>, ms: number): Promise<T> {
  return Promise.race([p, new Promise<T>((_, reject) => setTimeout(() => reject(new Error(`still pending after ${ms} ms`)), ms))]);
}

describe("request timeout", () => {
  it("reads ENGINE_EMBED_TIMEOUT_MS, defaulting to 120 s", () => {
    expect(resolveEmbedConfig({}).timeoutMs).toBe(120_000);
    expect(EMBED_LOCAL_DEFAULTS.timeoutMs).toBe(120_000);
    expect(resolveEmbedConfig({ ENGINE_EMBED_TIMEOUT_MS: "5000" }).timeoutMs).toBe(5000);
    expect(() => resolveEmbedConfig({ ENGINE_EMBED_TIMEOUT_MS: "-1" })).toThrow(/CONFIG_INVALID/);
  });

  it("a runner that accepts and never answers fails as RUNNER_TIMEOUT, naming the env to raise", async () => {
    const { fetchImpl } = stallingFetch("headers");
    const client = createLocalEmbeddingClient({ config: config({ timeoutMs: 50 }), fetchImpl });
    const err = await caught(within(client.embedTexts(["a"]), 3000));
    expect(err.code).toBe("RUNNER_TIMEOUT");
    expect(err.message).toMatch(/50 ms/);
    expect(err.message).toMatch(/ENGINE_EMBED_TIMEOUT_MS/);
  });

  it("a runner that sends headers and stalls the body also fails as RUNNER_TIMEOUT", async () => {
    const { fetchImpl } = stallingFetch("body");
    const client = createLocalEmbeddingClient({ config: config({ timeoutMs: 50 }), fetchImpl });
    const err = await caught(within(client.embedSingle("q"), 3000));
    expect(err.code).toBe("RUNNER_TIMEOUT");
  });

  it("health() on a stalled runner reports unknown instead of hanging", async () => {
    const { fetchImpl } = stallingFetch("headers");
    const client = createLocalEmbeddingClient({ config: config({ timeoutMs: 50 }), fetchImpl });
    const h = await within(client.health(), 3000);
    expect(h.state).toBe("unknown");
    expect(h.detail).toMatch(/within 50 ms/);
  });
});

describe("retry on a busy runner", () => {
  const policy = { attempts: 4, baseDelayMs: 2000, maxDelayMs: 30_000 };

  it("off by default: one 503 is one request and RUNNER_BUSY", async () => {
    const { fetchImpl, count } = scriptedRunner([503, 200]);
    const client = createLocalEmbeddingClient({ config: config(), fetchImpl });
    expect((await caught(client.embedTexts(["a"]))).code).toBe("RUNNER_BUSY");
    expect(count()).toBe(1);
  });

  it("with a policy, retries the busy batch with doubling waits and returns its vectors", async () => {
    const { fetchImpl, count } = scriptedRunner([503, 503, 200]);
    const waits: number[] = [];
    const client = createLocalEmbeddingClient({
      config: config(),
      fetchImpl,
      retry: policy,
      sleep: async (ms) => {
        waits.push(ms);
      },
    });
    const out = await client.embedTexts(["a", "b"]);
    expect(out).toHaveLength(2);
    expect(count()).toBe(3);
    expect(waits).toEqual([2000, 4000]);
  });

  it("is bounded: after `attempts` tries it throws RUNNER_BUSY", async () => {
    const { fetchImpl, count } = scriptedRunner([503]);
    const waits: number[] = [];
    const client = createLocalEmbeddingClient({ config: config(), fetchImpl, retry: policy, sleep: async (ms) => { waits.push(ms); } });
    expect((await caught(client.embedTexts(["a"]))).code).toBe("RUNNER_BUSY");
    expect(count()).toBe(4);
    expect(waits).toEqual([2000, 4000, 8000]);
  });

  it("retries a timed-out batch too, and only that batch", async () => {
    let n = 0;
    const stalled = stallingFetch("headers").fetchImpl;
    const ok = scriptedRunner([200]).fetchImpl;
    const fetchImpl = ((input: string | URL | Request, init?: RequestInit) => (n++ === 1 ? stalled(input, init) : ok(input, init))) as typeof fetch;
    const client = createLocalEmbeddingClient({
      config: config({ batchSize: 1, timeoutMs: 50 }),
      fetchImpl,
      retry: policy,
      sleep: async () => {},
    });
    const out = await within(client.embedTexts(["a", "b", "c"]), 3000);
    expect(out).toHaveLength(3);
    expect(n).toBe(4); // a, b (timed out), b again, c
  });

  it("does not retry a failure a retry cannot cure", async () => {
    const { fetchImpl, count } = scriptedRunner([404, 200]);
    const client = createLocalEmbeddingClient({ config: config(), fetchImpl, isDownloading: () => false, retry: policy, sleep: async () => {} });
    expect((await caught(client.embedTexts(["a"]))).code).toBe("MODEL_ABSENT");
    expect(count()).toBe(1);
  });

  it("the indexers' policy is 4 tries waiting 2 s, 4 s, 8 s", () => {
    expect(INDEXER_EMBED_RETRY).toEqual({ attempts: 4, baseDelayMs: 2000, maxDelayMs: 30_000 });
    expect([1, 2, 3].map((t) => retryDelayMs(INDEXER_EMBED_RETRY, t))).toEqual([2000, 4000, 8000]);
  });
});
