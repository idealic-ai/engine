/**
 * The shape every engine embedding consumer imports.
 *
 * Owner of `EmbeddingClient` for the engine: tools/session-search,
 * tools/doc-search and the director's ASKGROOM lane all take this one shape
 * from here. Do not restate it locally — a copy drifts the first time this
 * file changes.
 *
 * Ported from ideas/ai/embed (contract.ts, local-provider.ts), local half only.
 * There is no remote provider and no fallback to one (operator ruling,
 * 2026-10-29 03:02): a runner that has gone missing is a named failure, never
 * a quiet switch to vectors of another width.
 */

/** What a text is embedded FOR. embeddinggemma is asymmetric and must be told. */
export type EmbedRole = "document" | "query";

export interface EmbedConfig {
  /** Ollama model tag, e.g. "embeddinggemma". */
  model: string;
  /** Width every vector from this configuration must have. */
  dimensions: number;
  /** Base URL of the runner, no trailing slash. */
  endpoint: string;
  /** Texts per `/api/embed` request in `embedTexts`. */
  batchSize: number;
  /** Prefix stapled to a stored document before embedding. */
  documentPrefix: string;
  /** Prefix stapled to a search query before embedding. */
  queryPrefix: string;
}

/**
 * The client both search tools use.
 *
 * `embedTexts` embeds in the DOCUMENT role (what gets stored); `embedSingle`
 * embeds in the QUERY role (what gets compared against the store). `model`
 * and `dimensions` are what a caller writes beside each stored vector, so an
 * index can tell its own rows from a previous generation's.
 */
export interface EmbeddingClient {
  readonly model: string;
  readonly dimensions: number;
  embedTexts(texts: string[]): Promise<Float32Array[]>;
  embedSingle(text: string): Promise<Float32Array>;
}

/**
 * The failure vocabulary. `RUNNER_ABSENT`, `MODEL_ABSENT` and `MODEL_LOADING`
 * stay three states because they ask a human for three different things:
 * start something, download something, or wait.
 */
export type EmbedErrorCode =
  /** A configuration value was present and unusable. */
  | "CONFIG_INVALID"
  /** Nothing is answering at the endpoint. */
  | "RUNNER_ABSENT"
  /** The runner answered and does not have the model. */
  | "MODEL_ABSENT"
  /** The model is not ready and a download is in flight. */
  | "MODEL_LOADING"
  /** The runner is up and was started without embedding support. */
  | "RUNNER_LACKS_EMBEDDINGS"
  /** The runner's queue is full. */
  | "RUNNER_BUSY"
  /** The runner answered with something this client cannot use. */
  | "PROVIDER_ERROR"
  /** A vector came back at a width the configuration does not promise. */
  | "DIMENSION_UNEXPECTED"
  /** Nothing to embed. */
  | "EMPTY_TEXTS";

/** How the runner reports readiness without embedding anything. */
export interface EmbedHealth {
  model: string;
  dimensions: number;
  endpoint: string;
  state: "ready" | "runner_absent" | "model_absent" | "model_loading" | "unknown";
  /** One line a human can act on. */
  detail: string;
}
