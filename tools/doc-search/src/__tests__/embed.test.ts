import { describe, it, expect } from "vitest";
import { createEmbeddingClient } from "../embed.js";

// The tool's client is the shared tools/embed-local one: local model, 768-d,
// document role for stored text. No network — fetch is injected.
describe("doc-search embed wiring", () => {
  it("is embeddinggemma at 768 and embeds stored text in the document role", async () => {
    const bodies: Array<{ model: string; input: string[] }> = [];
    const fetchImpl = (async (_url: string | URL | Request, init?: RequestInit) => {
      const body = JSON.parse(String(init?.body)) as { model: string; input: string[] };
      bodies.push(body);
      return new Response(JSON.stringify({ embeddings: body.input.map(() => new Array(768).fill(0.5)) }));
    }) as typeof fetch;

    const client = createEmbeddingClient({ fetchImpl });
    const [v] = await client.embedTexts(["a doc"]);

    expect(client.model).toBe("embeddinggemma");
    expect(client.dimensions).toBe(768);
    expect(v.length).toBe(768);
    expect(bodies[0]).toEqual({ model: "embeddinggemma", input: ["title: none | text: a doc"] });
  });
});
