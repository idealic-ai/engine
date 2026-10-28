/**
 * A dependency-free client for Ollama's `/api/embed`, ported from
 * ideas/ai/embed/local-provider.ts.
 *
 * Batched (one request per `batchSize` texts), width-checked (every vector must
 * be exactly `dimensions` wide, or the whole call fails), and every failure is
 * thrown as an `EmbedLocalError` with a named code. The same request works
 * against `llama-server --embeddings`; point ENGINE_EMBED_ENDPOINT at it.
 */
import { existsSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { EmbedConfig, EmbedHealth, EmbedRole, EmbeddingClient } from "./contract.js";
import { resolveEmbedConfig } from "./config.js";
import { EmbedLocalError } from "./errors.js";

interface EmbedResponseBody {
  embeddings?: unknown;
  error?: string;
}

interface TagsResponseBody {
  models?: Array<{ name?: string; model?: string }>;
}

export interface LocalEmbeddingClientOptions {
  /** Defaults to `resolveEmbedConfig(process.env)`. */
  config?: EmbedConfig;
  fetchImpl?: typeof fetch;
  /** Whether a model download is in flight. Defaults to an Ollama blobs heuristic. */
  isDownloading?: () => boolean;
  /** Called after every batch of `embedTexts`, with texts done so far and the total. */
  onProgress?: (done: number, total: number) => void;
}

export interface LocalEmbeddingClient extends EmbeddingClient {
  readonly config: EmbedConfig;
  /** Embed in an explicit role; `embedTexts`/`embedSingle` are the two fixed-role forms. */
  embed(texts: string[], role: EmbedRole): Promise<Float32Array[]>;
  health(): Promise<EmbedHealth>;
}

/**
 * Whether Ollama is part-way through fetching something. It reads a private
 * detail (`*-partial` blobs) and cannot tell WHICH model is downloading, so
 * callers phrase it as "a model download is in progress". Unreadable reads as
 * not downloading, which degrades the report to MODEL_ABSENT.
 */
export function ollamaDownloadInFlight(): boolean {
  const blobs = join(process.env.OLLAMA_MODELS ?? join(homedir(), ".ollama", "models"), "blobs");
  try {
    if (!existsSync(blobs)) return false;
    return readdirSync(blobs).some((name) => name.includes("-partial"));
  } catch {
    return false;
  }
}

/** A refused or unresolvable connection means the runner is not there. */
function isConnectionRefused(err: unknown): boolean {
  if (!(err instanceof Error)) return false;
  const cause: unknown = (err as { cause?: unknown }).cause;
  const code =
    typeof cause === "object" && cause !== null && "code" in cause
      ? (cause as { code?: unknown }).code
      : undefined;
  return code === "ECONNREFUSED" || code === "ENOTFOUND" || code === "ECONNRESET";
}

function runnerAbsentMessage(endpoint: string): string {
  return (
    `No embedding runner is answering at ${endpoint}. Start one (\`ollama serve\`, or the Ollama app), ` +
    `or point ENGINE_EMBED_ENDPOINT at a running llama-server. There is no remote fallback.`
  );
}

export function createLocalEmbeddingClient(options: LocalEmbeddingClientOptions = {}): LocalEmbeddingClient {
  const config = options.config ?? resolveEmbedConfig(process.env);
  const fetchImpl = options.fetchImpl ?? fetch;
  const isDownloading = options.isDownloading ?? ollamaDownloadInFlight;
  const onProgress = options.onProgress;

  function prefixed(texts: string[], role: EmbedRole): string[] {
    const prefix = role === "query" ? config.queryPrefix : config.documentPrefix;
    return prefix === "" ? texts : texts.map((t) => prefix + t);
  }

  async function requestBatch(texts: string[], role: EmbedRole): Promise<Float32Array[]> {
    let response: Response;
    try {
      response = await fetchImpl(`${config.endpoint}/api/embed`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ model: config.model, input: prefixed(texts, role) }),
      });
    } catch (err: unknown) {
      if (isConnectionRefused(err)) {
        throw new EmbedLocalError("RUNNER_ABSENT", runnerAbsentMessage(config.endpoint));
      }
      throw new EmbedLocalError(
        "PROVIDER_ERROR",
        `The embedding request to ${config.endpoint} failed: ${err instanceof Error ? err.message : String(err)}`
      );
    }

    if (response.status === 404) {
      if (isDownloading()) {
        throw new EmbedLocalError(
          "MODEL_LOADING",
          `${config.model} is not ready and a model download is in progress. ` +
            `Wait for \`ollama pull ${config.model}\` to finish, then retry.`
        );
      }
      throw new EmbedLocalError(
        "MODEL_ABSENT",
        `The runner at ${config.endpoint} does not have ${config.model}. ` +
          `Fetch it once with \`ollama pull ${config.model}\`.`
      );
    }
    if (response.status === 501) {
      throw new EmbedLocalError(
        "RUNNER_LACKS_EMBEDDINGS",
        `The runner at ${config.endpoint} is up but has no embedding support ` +
          `(a llama.cpp server needs --embeddings).`
      );
    }
    if (response.status === 503) {
      throw new EmbedLocalError(
        "RUNNER_BUSY",
        `The runner at ${config.endpoint} refused work because its queue is full. Retry, or lower ENGINE_EMBED_BATCH.`
      );
    }
    if (!response.ok) {
      const detail = await response.text().catch(() => "");
      throw new EmbedLocalError(
        "PROVIDER_ERROR",
        `The runner at ${config.endpoint} answered ${response.status}. ${detail}`.trim()
      );
    }

    let body: EmbedResponseBody;
    try {
      body = (await response.json()) as EmbedResponseBody;
    } catch {
      throw new EmbedLocalError("PROVIDER_ERROR", `The runner at ${config.endpoint} answered with a body that is not JSON.`);
    }
    const embeddings = body.embeddings;
    if (!Array.isArray(embeddings) || embeddings.length !== texts.length) {
      throw new EmbedLocalError(
        "PROVIDER_ERROR",
        `The runner returned ${Array.isArray(embeddings) ? String(embeddings.length) : "no"} vectors for ` +
          `${String(texts.length)} texts.`
      );
    }

    return embeddings.map((vector: unknown) => {
      if (!Array.isArray(vector) || vector.length !== config.dimensions) {
        const width = Array.isArray(vector) ? String(vector.length) : "non-array";
        throw new EmbedLocalError(
          "DIMENSION_UNEXPECTED",
          `${config.model} returned a ${width}-wide vector where this configuration promises ` +
            `${String(config.dimensions)}. If that is the model's real width set ENGINE_EMBED_DIMENSIONS, ` +
            `and rebuild the index: rows of another width are not ranked.`
        );
      }
      return Float32Array.from(vector as number[]);
    });
  }

  async function embed(texts: string[], role: EmbedRole): Promise<Float32Array[]> {
    if (texts.length === 0) {
      throw new EmbedLocalError("EMPTY_TEXTS", "texts is empty — provide at least one text to embed.");
    }
    const out: Float32Array[] = [];
    for (let i = 0; i < texts.length; i += config.batchSize) {
      const batch = texts.slice(i, i + config.batchSize);
      out.push(...(await requestBatch(batch, role)));
      onProgress?.(out.length, texts.length);
    }
    return out;
  }

  async function embedTexts(texts: string[]): Promise<Float32Array[]> {
    // An empty corpus slice is not an error for an indexer; it has nothing to send.
    if (texts.length === 0) return [];
    return embed(texts, "document");
  }

  async function embedSingle(text: string): Promise<Float32Array> {
    const [vector] = await embed([text], "query");
    return vector;
  }

  async function health(): Promise<EmbedHealth> {
    const base = { model: config.model, dimensions: config.dimensions, endpoint: config.endpoint };
    let response: Response;
    try {
      response = await fetchImpl(`${config.endpoint}/api/tags`);
    } catch (err: unknown) {
      if (isConnectionRefused(err)) {
        return { ...base, state: "runner_absent", detail: runnerAbsentMessage(config.endpoint) };
      }
      return {
        ...base,
        state: "unknown",
        detail: `Could not read the runner's model list: ${err instanceof Error ? err.message : String(err)}`,
      };
    }
    if (!response.ok) {
      return { ...base, state: "unknown", detail: `The runner at ${config.endpoint} answered ${response.status} for its model list.` };
    }
    const body = (await response.json().catch(() => ({}))) as TagsResponseBody;
    const names = (body.models ?? []).flatMap((m) =>
      [m.name, m.model].filter((n): n is string => typeof n === "string")
    );
    // Ollama resolves an untagged name to ":latest"; any other tag is a different model.
    const wanted = config.model.includes(":") ? [config.model] : [config.model, `${config.model}:latest`];
    if (names.some((n) => wanted.includes(n))) {
      return { ...base, state: "ready", detail: `${config.model} is available at ${config.endpoint}.` };
    }
    if (isDownloading()) {
      return { ...base, state: "model_loading", detail: `${config.model} is not available yet; a model download is in progress.` };
    }
    return { ...base, state: "model_absent", detail: `${config.model} is not on this machine. Fetch it with \`ollama pull ${config.model}\`.` };
  }

  return {
    config,
    model: config.model,
    dimensions: config.dimensions,
    embed,
    embedTexts,
    embedSingle,
    health,
  };
}
