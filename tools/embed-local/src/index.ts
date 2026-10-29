export type { EmbedConfig, EmbedErrorCode, EmbedHealth, EmbedRole, EmbeddingClient } from "./contract.js";
export { EMBED_LOCAL_DEFAULTS, EMBED_LOCAL_ENV, resolveEmbedConfig } from "./config.js";
export { EmbedLocalError, isEmbedLocalError } from "./errors.js";
export {
  createLocalEmbeddingClient,
  ollamaDownloadInFlight,
  INDEXER_EMBED_RETRY,
  RETRYABLE_EMBED_CODES,
  retryDelayMs,
  type EmbedRetryPolicy,
  type LocalEmbeddingClient,
  type LocalEmbeddingClientOptions,
} from "./client.js";
