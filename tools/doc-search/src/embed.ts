/**
 * The embedding client this tool uses: the engine's one local client,
 * tools/embed-local (Ollama embeddinggemma, 768-d). `embedTexts` embeds in the
 * document role (what is stored), `embedSingle` in the query role. There is no
 * remote fallback — a missing runner or model is a named EmbedLocalError.
 */
import {
  createLocalEmbeddingClient,
  type EmbeddingClient,
  type LocalEmbeddingClientOptions,
} from "../../embed-local/src/index.js";

export type { EmbeddingClient };

export function createEmbeddingClient(options: LocalEmbeddingClientOptions = {}): EmbeddingClient {
  return createLocalEmbeddingClient(options);
}
