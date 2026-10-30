/**
 * IDE-334 (RAGPROOFS): the incremental indexer (add, change, delete, prune, dedupe) and the query over it,
 * against temp dirs and a fake embedder. Nothing here reaches Ollama or the proof store.
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { newAsk } from "../src/lib/store.ts";
import { openSearchDb, type SearchDb } from "../src/search/db.ts";
import { indexSources, tryIndexLock } from "../src/search/indexer.ts";
import { search, SearchUnavailable } from "../src/search/query.ts";
import { askSource, broadcastSource, proofBody, proofFileSource, type Source } from "../src/search/sources.ts";
import { fakeEmbedder } from "./fixtures/fake-embedder.ts";

const ASK = (title: string, second: string) =>
  `## ¶ASK_GO: Choose one: ${title}\nContext: c\n- [ ] [YES] Yes\n  Picks YES.\n- [ ] [NO] No\n  Picks NO.\n\n## ¶ASK_CACHE: Choose one: ${second}\nContext: c\n- [ ] [KEEP] Keep\n  Picks KEEP.\n- [ ] [DROP] Drop\n  Picks DROP.\n`;

const PAGE = (h1: string, para: string) => `<!doctype html><html><head><title>${h1}</title></head><body><h1>${h1}</h1><p>${para} ${"filler words about the page ".repeat(6)}</p><h2>Evidence</h2><p>${"the evidence section holds measured output ".repeat(5)}</p></body></html>`;

let base: string;
let root: string;
let bdir: string;
let pdir: string;
let db: SearchDb;

beforeEach(() => {
  base = fs.mkdtempSync(path.join(os.tmpdir(), "asksearch-"));
  root = path.join(base, "asks");
  bdir = path.join(base, "broadcasts");
  pdir = path.join(base, "sessions");
  fs.mkdirSync(root);
  fs.mkdirSync(bdir);
  fs.mkdirSync(path.join(pdir, "S1", "builds"), { recursive: true });
  newAsk(root, { from: "meta:engine", to: "manager:meta", id: "ship-cache", why: "the warmer cache decides latency" }, ASK("Ship the warmer cache tonight?", "Keep the old eviction policy?"));
  fs.writeFileSync(path.join(bdir, "freeze.md"), "id: freeze\nfrom: director\nat: 2026-10-30T10:00:00Z\naudience: all\nsticky: yes\n\n## Text\nCode freeze on the kernel until the migration lands. No pushes to kernel main.\n");
  fs.writeFileSync(path.join(pdir, "S1", "builds", "otlayer_PROOF.html"), PAGE("Merge convergence", "does any merge run converge on the operational transform layer"));
  db = openSearchDb(path.join(base, "index.db"));
});
afterEach(() => {
  db.close();
  fs.rmSync(base, { recursive: true, force: true });
});

const sources = (): Source[] => [askSource(root), broadcastSource(root, bdir), proofFileSource([pdir])];
const count = (sql: string) => (db.prepare(sql).get() as { n: number }).n;

describe("indexSources", () => {
  it("adds every source, an ask cut by fork", async () => {
    const e = fakeEmbedder();
    const r = await indexSources(db, sources(), e);
    expect(r.error).toBeUndefined();
    expect(r.added).toBe(3);
    expect(r.sources).toMatchObject({ asks: { ok: true, listed: 1 }, broadcasts: { ok: true, listed: 1 }, "proof-files": { ok: true, listed: 1 } });
    const sections = (db.prepare("SELECT section FROM chunks WHERE item_key = 'ask:meta:engine/ship-cache'").all() as { section: string }[]).map((s) => s.section);
    expect(sections).toContain("Ship the warmer cache tonight?");
    expect(sections).toContain("Ship the warmer cache tonight? > Ship the warmer cache tonight?");
    expect(sections).toContain("Ship the warmer cache tonight? > Keep the old eviction policy?");
    expect(r.embeddingsCreated).toBe(count("SELECT count(*) AS n FROM embeddings"));
  });

  it("leaves an unchanged index alone: nothing read, nothing embedded", async () => {
    const e = fakeEmbedder();
    await indexSources(db, sources(), e);
    const before = e.texts;
    const r = await indexSources(db, sources(), e);
    expect(r).toMatchObject({ added: 0, changed: 0, deleted: 0, unchanged: 3, embeddingsCreated: 0 });
    expect(e.texts).toBe(before);
  });

  it("re-embeds only the sections of a changed item that changed", async () => {
    const e = fakeEmbedder();
    await indexSources(db, sources(), e);
    const file = path.join(root, "meta:engine", "ship-cache.md");
    fs.writeFileSync(file, fs.readFileSync(file, "utf8").replace("Keep the old eviction policy?", "Keep the LRU eviction policy?"));
    const r = await indexSources(db, sources(), e);
    expect(r.changed).toBe(1);
    expect(r.unchanged).toBe(2);
    // The second fork's section changed; the card and first fork did not.
    expect(r.embeddingsCreated).toBe(1);
    expect(r.embeddingsReused).toBeGreaterThan(0);
    expect(r.embeddingsPruned).toBe(1);
  });

  it("refreshes a touched file without re-embedding it", async () => {
    const e = fakeEmbedder();
    await indexSources(db, sources(), e);
    const file = path.join(root, "meta:engine", "ship-cache.md");
    const later = new Date(Date.now() + 5000);
    fs.utimesSync(file, later, later);
    const r = await indexSources(db, sources(), e);
    expect(r).toMatchObject({ touched: 1, changed: 0, embeddingsCreated: 0 });
  });

  it("deletes an item whose file is gone and prunes the embeddings nothing refers to", async () => {
    const e = fakeEmbedder();
    await indexSources(db, sources(), e);
    const embeddings = count("SELECT count(*) AS n FROM embeddings");
    fs.unlinkSync(path.join(bdir, "freeze.md"));
    const r = await indexSources(db, sources(), e);
    expect(r.deleted).toBe(1);
    expect(count("SELECT count(*) AS n FROM items WHERE key = 'broadcast:freeze'")).toBe(0);
    expect(count("SELECT count(*) AS n FROM chunks WHERE item_key = 'broadcast:freeze'")).toBe(0);
    expect(r.embeddingsPruned).toBeGreaterThan(0);
    expect(count("SELECT count(*) AS n FROM embeddings")).toBe(embeddings - r.embeddingsPruned);
    expect(count("SELECT count(*) AS n FROM embeddings WHERE content_hash NOT IN (SELECT content_hash FROM chunks)")).toBe(0);
  });

  it("prunes nothing from a source whose listing failed", async () => {
    const e = fakeEmbedder();
    await indexSources(db, sources(), e);
    const down: Source = { name: "broadcasts", kind: "broadcast", list: async () => ({ ok: false, error: "dir not readable", items: [] }) };
    const r = await indexSources(db, [askSource(root), down, proofFileSource([pdir])], e);
    expect(r.deleted).toBe(0);
    expect(r.sources.broadcasts).toEqual({ ok: false, error: "dir not readable", listed: 0 });
    expect(count("SELECT count(*) AS n FROM items WHERE key = 'broadcast:freeze'")).toBe(1);
  });

  it("stops on an embedding failure, keeps what it had, and retries the rest next pass", async () => {
    const e = fakeEmbedder();
    e.fail = true;
    const r = await indexSources(db, sources(), e);
    expect(r.error).toMatch(/nothing listening/);
    expect(count("SELECT count(*) AS n FROM items")).toBe(0);
    e.fail = false;
    const r2 = await indexSources(db, sources(), e);
    expect(r2.error).toBeUndefined();
    expect(r2.added).toBe(3);
  });

  it("keeps a builds/ copy of a published page as a duplicate, and indexes it again when the page goes", async () => {
    const e = fakeEmbedder();
    const html = PAGE("Merge convergence", "does any merge run converge on the operational transform layer");
    const published = html.replace("<body>", '<body><!--prove-seat-strip:begin--><div data-seat="meta:engine">Published by meta:engine</div><!--prove-seat-strip:end-->');
    let listed = true;
    const bucket: Source = {
      name: "proof-bucket",
      kind: "proof",
      list: async () => ({
        ok: true,
        items: listed ? [{ key: "proof:proofs/invizko/otlayer-1.html", stamp: "t1:1", read: async () => proofBody(published, { id: "proofs/invizko/otlayer-1.html", fallbackTitle: "x", seat: "invizko", status: "published", url: "http://store/otlayer-1.html", appPath: "/proofs/proofs/invizko/otlayer-1.html" }) }] : [],
      }),
    };
    const r = await indexSources(db, [bucket, proofFileSource([pdir])], e);
    expect(r.duplicates).toBe(1);
    const file = db.prepare("SELECT dup_of FROM items WHERE source = 'proof-files'").get() as { dup_of: string };
    expect(file.dup_of).toBe("proof:proofs/invizko/otlayer-1.html");
    expect(count("SELECT count(*) AS n FROM chunks c JOIN items i ON i.key = c.item_key WHERE i.source = 'proof-files'")).toBe(0);
    const hits = await search(db, e, { q: "merge converge", kinds: ["proof"] });
    expect(hits).toHaveLength(1);
    expect(hits[0]).toMatchObject({ seat: "meta:engine", status: "published", url: "http://store/otlayer-1.html" });

    listed = false;
    const r2 = await indexSources(db, [bucket, proofFileSource([pdir])], e);
    expect(r2.deleted).toBe(1);
    expect(r2.added + r2.changed).toBe(1);
    const again = await search(db, e, { q: "merge converge", kinds: ["proof"] });
    expect(again).toHaveLength(1);
    expect(again[0]).toMatchObject({ status: "local", url: null, id: "S1/otlayer_PROOF.html" });
  });
});

describe("search", () => {
  it("answers one hit per item with the contract's fields, best first, and filters by kind", async () => {
    const e = fakeEmbedder();
    await indexSources(db, sources(), e);
    const hits = await search(db, e, { q: "keep the old eviction policy", limit: 5 });
    expect(hits[0]).toMatchObject({ kind: "ask", seat: "meta:engine", id: "ship-cache", title: "Ship the warmer cache tonight?", status: "open", appPath: "/a/meta:engine/ship-cache" });
    expect(hits[0].url).toMatch(/^http:\/\/127\.0\.0\.1:\d+\/a\/meta:engine\/ship-cache$/);
    expect(hits[0].section).toBe("Ship the warmer cache tonight? > Keep the old eviction policy?");
    expect(hits[0].excerpt).toContain("eviction");
    expect(typeof hits[0].score).toBe("number");
    expect(new Set(hits.map((h) => h.id)).size).toBe(hits.length);
    for (let i = 1; i < hits.length; i++) expect(hits[i - 1].score).toBeGreaterThanOrEqual(hits[i].score);
    const b = await search(db, e, { q: "kernel code freeze", kinds: ["broadcast"] });
    expect(b.map((h) => h.kind)).toEqual(["broadcast"]);
    expect(b[0]).toMatchObject({ seat: "director", id: "freeze", status: "in-force", appPath: "/broadcasts/freeze" });
  });

  it("refuses rather than answering empty: an empty index, and an embedder that is down", async () => {
    const e = fakeEmbedder();
    await expect(search(db, e, { q: "anything" })).rejects.toMatchObject({ reason: "index-empty" });
    await indexSources(db, sources(), e);
    e.fail = true;
    const err = await search(db, e, { q: "anything" }).catch((x) => x);
    expect(err).toBeInstanceOf(SearchUnavailable);
    expect(err).toMatchObject({ reason: "embedder-unavailable", code: "RUNNER_ABSENT" });
  });
});

describe("tryIndexLock", () => {
  it("lets one holder in, and takes over a lock whose holder is dead", () => {
    const f = path.join(base, "index.db");
    const release = tryIndexLock(f)!;
    expect(release).toBeTypeOf("function");
    expect(tryIndexLock(f)).toBeNull();
    release();
    fs.writeFileSync(`${f}.lock`, "999999");
    const again = tryIndexLock(f);
    expect(again).toBeTypeOf("function");
    again!();
  });
});
