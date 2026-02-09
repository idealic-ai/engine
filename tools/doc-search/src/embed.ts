import { GoogleGenAI } from "@google/genai";

const EMBEDDING_MODEL = "gemini-embedding-001";
const EMBEDDING_DIMENSIONS = 3072;
const TASK_TYPE = "SEMANTIC_SIMILARITY";
const BATCH_SIZE = 100;
const BATCH_DELAY_MS = 500;

export interface EmbeddingClient {
  embedTexts(texts: string[]): Promise<Float32Array[]>;
  embedSingle(text: string): Promise<Float32Array>;
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Create a Gemini embedding client.
 * Requires GEMINI_API_KEY environment variable.
 */
export function createEmbeddingClient(): EmbeddingClient {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    throw new Error(
      "GEMINI_API_KEY environment variable is required for embedding"
    );
  }

  const ai = new GoogleGenAI({ apiKey });

  async function embedSingle(text: string): Promise<Float32Array> {
    const result = await ai.models.embedContent({
      model: EMBEDDING_MODEL,
      contents: text,
      config: {
        taskType: TASK_TYPE,
        outputDimensionality: EMBEDDING_DIMENSIONS,
      },
    });

    const values = result.embeddings?.[0]?.values;
    if (!values) {
      throw new Error("No embedding values returned from Gemini API");
    }

    return new Float32Array(values);
  }

  async function embedTexts(texts: string[]): Promise<Float32Array[]> {
    const results: Float32Array[] = [];

    for (let i = 0; i < texts.length; i += BATCH_SIZE) {
      const batch = texts.slice(i, i + BATCH_SIZE);

      // Embed each text individually within the batch
      // (Gemini embedContent supports single text, we batch manually)
      const batchResults = await Promise.all(
        batch.map((text) => embedSingle(text))
      );

      results.push(...batchResults);

      // Rate limiting: delay between batches
      if (i + BATCH_SIZE < texts.length) {
        await delay(BATCH_DELAY_MS);
      }
    }

    return results;
  }

  return { embedTexts, embedSingle };
}

export { EMBEDDING_DIMENSIONS };
