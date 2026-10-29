/**
 * Which local model runs, read from the environment.
 *
 * Every override is explicit and there is no fallback provider. Changing the
 * model or the width means a new index generation: rows written by another
 * model or width are not ranked against this one (the search tools store
 * both per row).
 */
import type { EmbedConfig } from "./contract.js";
import { EmbedLocalError } from "./errors.js";

/**
 * The default model and its contract. The prefixes are part of embeddinggemma's
 * contract, not decoration — leaving them off costs retrieval quality silently.
 * Same values as ideas/ai/embed/config.ts.
 */
export const EMBED_LOCAL_DEFAULTS = {
  model: "embeddinggemma",
  dimensions: 768,
  endpoint: "http://127.0.0.1:11434",
  batchSize: 32,
  /** Per request. A 64-text batch took 4.3 s at load ~460; a cold model load adds ~2 s. */
  timeoutMs: 120_000,
  documentPrefix: "title: none | text: ",
  queryPrefix: "task: search result | query: ",
} as const;

/** The environment variables this module reads. */
export const EMBED_LOCAL_ENV = {
  endpoint: "ENGINE_EMBED_ENDPOINT",
  model: "ENGINE_EMBED_MODEL",
  dimensions: "ENGINE_EMBED_DIMENSIONS",
  batchSize: "ENGINE_EMBED_BATCH",
  timeoutMs: "ENGINE_EMBED_TIMEOUT_MS",
} as const;

function positiveInt(env: NodeJS.ProcessEnv, key: string, fallback: number): number {
  const raw = env[key]?.trim();
  if (raw === undefined || raw === "") return fallback;
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new EmbedLocalError(
      "CONFIG_INVALID",
      `${key} is set to "${raw}", which is not a positive whole number. Unset it to get ${fallback}.`
    );
  }
  return parsed;
}

export function resolveEmbedConfig(env: NodeJS.ProcessEnv = process.env): EmbedConfig {
  const endpoint = (env[EMBED_LOCAL_ENV.endpoint]?.trim() || EMBED_LOCAL_DEFAULTS.endpoint).replace(/\/+$/, "");
  return {
    model: env[EMBED_LOCAL_ENV.model]?.trim() || EMBED_LOCAL_DEFAULTS.model,
    dimensions: positiveInt(env, EMBED_LOCAL_ENV.dimensions, EMBED_LOCAL_DEFAULTS.dimensions),
    endpoint,
    batchSize: positiveInt(env, EMBED_LOCAL_ENV.batchSize, EMBED_LOCAL_DEFAULTS.batchSize),
    timeoutMs: positiveInt(env, EMBED_LOCAL_ENV.timeoutMs, EMBED_LOCAL_DEFAULTS.timeoutMs),
    documentPrefix: EMBED_LOCAL_DEFAULTS.documentPrefix,
    queryPrefix: EMBED_LOCAL_DEFAULTS.queryPrefix,
  };
}
