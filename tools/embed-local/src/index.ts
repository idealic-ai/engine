export type { EmbedConfig, EmbedErrorCode, EmbedHealth, EmbedRole, EmbeddingClient } from "./contract.ts";
export { EMBED_LOCAL_DEFAULTS, EMBED_LOCAL_ENV, resolveEmbedConfig } from "./config.ts";
export { EmbedLocalError, isEmbedLocalError } from "./errors.ts";
export {
  createLocalEmbeddingClient,
  ollamaDownloadInFlight,
  INDEXER_EMBED_RETRY,
  RETRYABLE_EMBED_CODES,
  retryDelayMs,
  type EmbedRetryPolicy,
  type LocalEmbeddingClient,
  type LocalEmbeddingClientOptions,
} from "./client.ts";
