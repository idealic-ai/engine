import { describe, it, expect, afterEach } from "vitest";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { initDb, saveDb, type Database } from "../db.js";
import { reconcileChunks } from "../indexer.js";
import { searchDocs, countForeignEmbeddings } from "../query.js";
import type { DocChunk } from "../chunker.js";
import type { EmbeddingClient } from "../embed.js";

function makeMockEmbedder(model = "embeddinggemma", dimensions = 768): EmbeddingClient & { calls: string[][] } {
  const calls: string[][] = [];
  const vec = (t: string) => Float32Array.from({ length: dimensions }, (_, i) => (t.length + i) / 10000);
  return {
    model,
    dimensions,
    calls,
    async embedTexts(texts: string[]) {
      calls.push(texts);
      return texts.map(vec);
    },
    async embedSingle(text: string) {
      return vec(text);
    },
  };
}

function chunk(title: string, hash: string, mtime = 1): DocChunk {
  return {
    projectName: "proj",
    branch: "main",
    filePath: `docs/${title}.md`,
    sectionTitle: title,
    content: `Content of ${title}.`,
    contentHash: hash,
    mtime,
    snippet: `Content of ${title}.`,
  };
}

describe("doc-search indexer — generation guard", () => {
  const paths: string[] = [];
  async function setupDb(): Promise<Database> {
    const p = path.join(os.tmpdir(), `doc-search-test-${Date.now()}-${Math.random().toString(36).slice(2)}.db`);
    paths.push(p);
    return initDb(p);
  }
  afterEach(() => {
    for (const p of paths) fs.rmSync(p, { force: true });
    paths.length = 0;
  });

  it("stores the embedder's model and width on every embedding row", async () => {
    const db = await setupDb();
    await reconcileChunks(db, [chunk("A", "h_a")], makeMockEmbedder(), "proj", "main");
    expect(db.exec("SELECT model, dimensions, length(embedding) FROM embeddings")[0].values).toEqual([
      ["embeddinggemma", 768, 768 * 4],
    ]);
    db.close();
  });

  it("re-embeds an unchanged (same-mtime) chunk whose embedding another model wrote", async () => {
    const db = await setupDb();
    await reconcileChunks(db, [chunk("A", "h_a")], makeMockEmbedder("old-model", 16), "proj", "main");

    const current = makeMockEmbedder();
    const report = await reconcileChunks(db, [chunk("A", "h_a")], current, "proj", "main");

    expect(report.skipped).toBe(1);
    expect(report.embeddingsCreated).toBe(1);
    expect(current.calls).toEqual([["Content of A."]]);
    expect(db.exec("SELECT model, dimensions FROM embeddings")[0].values).toEqual([["embeddinggemma", 768]]);
    db.close();
  });

  it("does not re-embed content already at the current model and width", async () => {
    const db = await setupDb();
    const current = makeMockEmbedder();
    await reconcileChunks(db, [chunk("A", "h_a")], current, "proj", "main");
    const report = await reconcileChunks(db, [chunk("A", "h_a", 2)], current, "proj", "main");
    expect(report.embeddingsCreated).toBe(0);
    expect(current.calls).toHaveLength(1);
    db.close();
  });

  it("a query ranks only rows of its own generation, and the rest are counted as foreign", async () => {
    const db = await setupDb();
    const current = makeMockEmbedder();
    await reconcileChunks(db, [chunk("Old", "h_old"), chunk("New", "h_new")], current, "proj", "main");
    db.run("UPDATE embeddings SET model = 'old-model', dimensions = 16, embedding = ? WHERE content_hash = 'h_old'", [
      new Uint8Array(16 * 4),
    ]);

    const results = await searchDocs(db, "anything", current, "proj", { branch: "main" }, 10);

    expect(results.map((r) => r.sectionTitle)).toEqual(["New"]);
    expect(countForeignEmbeddings(db, current)).toBe(1);
    db.close();
  });

  it("the schema refuses a blob whose length does not match its declared width", async () => {
    const db = await setupDb();
    expect(() =>
      db.run("INSERT INTO embeddings (content_hash, embedding, model, dimensions) VALUES ('h', ?, 'm', 768)", [
        new Uint8Array(3072 * 4),
      ])
    ).toThrow(/CHECK/);
    db.close();
  });

  it("refuses a schema-1 (Gemini 3072-d) image and leaves the file byte-identical", async () => {
    const p = path.join(os.tmpdir(), `doc-search-test-${Date.now()}-legacy.db`);
    paths.push(p);
    const db1 = await initDb(p);
    db1.run("PRAGMA user_version = 1;");
    saveDb(db1, p);
    db1.close();
    const before = fs.readFileSync(p);

    await expect(initDb(p)).rejects.toThrow(/Gemini-era index \(schema 1\)/);
    expect(fs.readFileSync(p).equals(before)).toBe(true);
  });
});
