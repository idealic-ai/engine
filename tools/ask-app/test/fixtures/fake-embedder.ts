/** IDE-334 (RAGPROOFS): a stand-in for the embed-local client, so no search test reaches Ollama. */
import { EmbedLocalError, type EmbeddingClient } from "../../../embed-local/src/index.ts";

/** Bag of words hashed into 64 dims: texts sharing words point the same way, which is all a ranking test needs. */
export function fakeEmbedder(): EmbeddingClient & { calls: number; texts: number; fail?: boolean } {
  const vec = (t: string) => {
    const v = new Float32Array(64);
    for (const w of t.toLowerCase().match(/[a-z0-9]+/g) ?? []) {
      let h = 0;
      for (const c of w) h = (h * 31 + c.charCodeAt(0)) >>> 0;
      v[h % 64] += 1;
    }
    return v;
  };
  const e = {
    model: "fake",
    dimensions: 64,
    calls: 0,
    texts: 0,
    fail: false as boolean | undefined,
    async embedTexts(ts: string[]) {
      if (e.fail) throw new EmbedLocalError("RUNNER_ABSENT", "nothing listening");
      e.calls++;
      e.texts += ts.length;
      return ts.map(vec);
    },
    async embedSingle(t: string) {
      if (e.fail) throw new EmbedLocalError("RUNNER_ABSENT", "nothing listening");
      return vec(t);
    },
  };
  return e;
}
