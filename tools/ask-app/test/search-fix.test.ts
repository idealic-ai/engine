/**
 * SEARCHFIX (IDE-334 follow-up): the gaps meta:utils found running its client against the real server.
 *   - a relevance floor: `minScore`, with a default only for the model it was measured on
 *   - the reason order: a dead embedder is the cause, an empty index its symptom, so the cause is reported
 *   - unpublished builds/ proof copies (no url, no appPath) are left out unless the caller asks for `local`
 *   - the broadcasts directory defaults beside the asks root, with no operator name in the source
 * Nothing here reaches Ollama or the proof store.
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { newAsk } from "../src/lib/store.ts";
import { openSearchDb, type SearchDb } from "../src/search/db.ts";
import { indexSources } from "../src/search/indexer.ts";
import { DEFAULT_MIN_SCORE, defaultMinScore, search, SEARCH_KINDS, wordIn } from "../src/search/query.ts";
import { ASK_BODY_VERSION, askSource, broadcastSource, proofFileSource, type Source } from "../src/search/sources.ts";
import { defaultBroadcastDir } from "../src/lib/broadcasts.ts";
import { fakeEmbedder } from "./fixtures/fake-embedder.ts";

const ASK = (title: string) => `## ¶ASK_GO: Choose one: ${title}\nContext: c\n- [ ] [YES] Yes\n  Picks YES.\n- [ ] [NO] No\n  Picks NO.\n`;
const PAGE = (h1: string, para: string) => `<!doctype html><html><head><title>${h1}</title></head><body><h1>${h1}</h1><p>${para} ${"filler words about the page ".repeat(6)}</p></body></html>`;

let base: string;
let root: string;
let bdir: string;
let pdir: string;
let db: SearchDb;

beforeEach(() => {
  base = fs.mkdtempSync(path.join(os.tmpdir(), "searchfix-"));
  root = path.join(base, "asks");
  bdir = path.join(base, "broadcasts");
  pdir = path.join(base, "sessions");
  fs.mkdirSync(root);
  fs.mkdirSync(bdir);
  fs.mkdirSync(path.join(pdir, "S1", "builds"), { recursive: true });
  newAsk(root, { from: "meta:engine", to: "manager:meta", id: "ship-cache", why: "the warmer cache decides latency" }, ASK("Ship the warmer cache tonight?"));
  fs.writeFileSync(path.join(pdir, "S1", "builds", "rollout_PROOF.html"), PAGE("Canary rollout", "the canary rollout of the warmer cache held latency flat"));
  db = openSearchDb(path.join(base, "index.db"));
});
afterEach(() => {
  db.close();
  fs.rmSync(base, { recursive: true, force: true });
});

const sources = (): Source[] => [askSource(root), broadcastSource(root, bdir), proofFileSource([pdir])];

describe("which reason a refusal names: the cause before the symptom", () => {
  it("empty index, embedder down → embedder-unavailable (the index is empty because nothing can embed)", async () => {
    const e = fakeEmbedder();
    e.fail = true;
    await expect(search(db, e, { q: "anything" })).rejects.toMatchObject({ reason: "embedder-unavailable", code: "RUNNER_ABSENT" });
  });
  it("empty index, embedder up → index-empty", async () => {
    await expect(search(db, fakeEmbedder(), { q: "anything" })).rejects.toMatchObject({ reason: "index-empty" });
  });
  it("populated index, embedder down → embedder-unavailable", async () => {
    const e = fakeEmbedder();
    await indexSources(db, sources(), e);
    e.fail = true;
    await expect(search(db, e, { q: "anything" })).rejects.toMatchObject({ reason: "embedder-unavailable" });
  });
  it("unreadable index, embedder down → index-error (a broken file is its own cause)", async () => {
    db.exec("DROP TABLE chunks; DROP TABLE items;");
    const e = fakeEmbedder();
    e.fail = true;
    await expect(search(db, e, { q: "anything" })).rejects.toMatchObject({ reason: "index-error" });
  });
  it("unreadable index, embedder up → index-error", async () => {
    db.exec("DROP TABLE chunks; DROP TABLE items;");
    await expect(search(db, fakeEmbedder(), { q: "anything" })).rejects.toMatchObject({ reason: "index-error" });
  });
});

describe("the relevance floor", () => {
  it("has a default only for the model it was measured on", () => {
    expect(DEFAULT_MIN_SCORE).toBe(0.4);
    expect(defaultMinScore("embeddinggemma")).toBe(0.4);
    expect(defaultMinScore("embeddinggemma:latest")).toBe(0.4);
    expect(defaultMinScore("fake")).toBe(0);
    expect(defaultMinScore("nomic-embed-text")).toBe(0);
  });

  it("drops every hit under minScore, so a query nothing is about answers []", async () => {
    const e = fakeEmbedder();
    await indexSources(db, sources(), e);
    const all = await search(db, e, { q: "warmer cache", minScore: 0 });
    expect(all.length).toBeGreaterThan(0);
    const floor = all[0].score - 0.0001;
    const kept = await search(db, e, { q: "warmer cache", minScore: floor });
    expect(kept.length).toBeGreaterThan(0);
    expect(kept.every((h) => h.score >= floor)).toBe(true);
    expect(await search(db, e, { q: "warmer cache", minScore: all[0].score + 0.01 })).toEqual([]);
  });

  it("applies the model's default when the caller gives none (the fake model has none)", async () => {
    const e = fakeEmbedder();
    await indexSources(db, sources(), e);
    const a = await search(db, e, { q: "warmer cache", kinds: ["ask", "local"] });
    const b = await search(db, e, { q: "warmer cache", kinds: ["ask", "local"], minScore: 0 });
    expect(a).toEqual(b);
  });
});

describe("unpublished builds/ proof copies", () => {
  it("are left out by default and by kind=proof, since they have no url or appPath to open", async () => {
    const e = fakeEmbedder();
    await indexSources(db, sources(), e);
    const def = await search(db, e, { q: "canary rollout warmer cache" });
    expect(def.some((h) => h.status === "local")).toBe(false);
    expect(def.length).toBeGreaterThan(0); // the ask is still there
    const proof = await search(db, e, { q: "canary rollout", kinds: ["proof"] });
    expect(proof.some((h) => h.status === "local")).toBe(false);
  });

  it("come back with kind=local, alone or beside other kinds, still as kind proof with status local", async () => {
    const e = fakeEmbedder();
    await indexSources(db, sources(), e);
    expect(SEARCH_KINDS).toEqual(["ask", "proof", "broadcast", "local"]);
    const local = await search(db, e, { q: "canary rollout", kinds: ["local"] });
    expect(local.map((h) => [h.kind, h.status, h.url, h.appPath])).toEqual([["proof", "local", null, null]]);
    const both = await search(db, e, { q: "canary rollout warmer cache", kinds: ["ask", "local"] });
    expect(new Set(both.map((h) => h.status))).toEqual(new Set(["open", "local"]));
  });
});

describe("the broadcasts directory default", () => {
  const saved = { ASK_ROOT: process.env.ASK_ROOT, BROADCAST_DIR: process.env.BROADCAST_DIR };
  afterEach(() => {
    for (const [k, v] of Object.entries(saved)) if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  });

  it("sits beside the asks root, so ASK_ROOT (which `engine ask path` prints) moves both", () => {
    delete process.env.BROADCAST_DIR;
    process.env.ASK_ROOT = "/data/someone/asks";
    expect(defaultBroadcastDir()).toBe("/data/someone/broadcasts");
    expect(defaultBroadcastDir("/elsewhere/asks")).toBe("/elsewhere/broadcasts");
  });

  it("BROADCAST_DIR still wins", () => {
    process.env.BROADCAST_DIR = "/b";
    process.env.ASK_ROOT = "/data/someone/asks";
    expect(defaultBroadcastDir()).toBe("/b");
  });

  it("names no operator in its source", () => {
    const src = fs.readFileSync(new URL("../src/lib/broadcasts.ts", import.meta.url), "utf8");
    expect(src).not.toMatch(/yarik/);
  });
});

describe("every option field is indexed", () => {
  it("reversible, unblocks, then, elegance, cost, effort and blast radius sit in the fork's section", async () => {
    const text =
      "## ¶ASK_PICK: Choose one: Which store for the session cache?\nContext: c\n" +
      "- [ ] [RED] Redis cluster\n  Picks Redis.\n  Reversible: only by draining every shard first\n  Unblocks: the eviction work\n" +
      "  Then: the ops runbook grows a failover page\n  Elegance: one moving part\n  Cost: three nodes\n  Effort: two days\n  Blast radius: every session\n" +
      "- [ ] [MEM] Memcached pool\n  Picks Memcached.\n";
    newAsk(root, { from: "meta:engine", to: "manager:meta", id: "store-pick", why: "w" }, text);
    const e = fakeEmbedder();
    await indexSources(db, sources(), e);
    const body = (db.prepare("SELECT group_concat(body, '\n') AS b FROM chunks WHERE item_key LIKE '%store-pick%'").get() as { b: string }).b;
    for (const s of ["draining every shard", "the eviction work", "failover page", "one moving part", "three nodes", "two days", "every session"]) expect(body).toContain(s);
    const hits = await search(db, e, { q: "draining every shard", kinds: ["ask"] });
    expect(hits[0]).toMatchObject({ id: "store-pick" });
  });
});

describe("SEARCHFIX round 2", () => {
  const forkBody = () => (db.prepare("SELECT group_concat(body, '\n') AS b FROM chunks WHERE item_key LIKE '%opt-m%'").get() as { b: string }).b;

  it("S1: a short field value that merely occurs in the description is still indexed; an echoed line is not doubled", async () => {
    const text =
      "## ¶ASK_PICK: Choose one: Which store?\nContext: c\n" +
      "- [ ] [RED] Redis\n  Moves sessions to Redis.\n  Effort: M\n  Reversible: only by draining every shard\n" +
      "- [ ] [MEM] Memcached\n  Plain.\n  Effort: M\n";
    newAsk(root, { from: "meta:engine", to: "manager:meta", id: "opt-m", why: "w" }, text);
    await indexSources(db, sources(), fakeEmbedder());
    const body = forkBody();
    expect(body.match(/Effort: M/g)).toHaveLength(2); // RED's description holds an "M" (in "Moves"); MEM's does not
    expect(body.match(/Reversible: only by draining every shard/g)).toHaveLength(1);
  });

  it("S2: the ask stamp carries ASK_BODY_VERSION, so an ask indexed under an older askBody is re-read on the next pass", async () => {
    const e = fakeEmbedder();
    await indexSources(db, sources(), e);
    const row = db.prepare("SELECT stamp FROM items WHERE key LIKE 'ask:%'").get() as { stamp: string };
    expect(row.stamp.endsWith(`:${ASK_BODY_VERSION}`)).toBe(true);
    const quiet = await indexSources(db, sources(), e);
    expect(quiet.changed + quiet.touched + quiet.added).toBe(0);
    // An index written before the version existed: stamps without it.
    db.prepare("UPDATE items SET stamp = substr(stamp, 1, length(stamp) - ?) WHERE key LIKE 'ask:%'").run(ASK_BODY_VERSION.length + 1);
    const again = await indexSources(db, sources(), e);
    expect(again.changed + again.touched).toBeGreaterThanOrEqual(1);
  });

  it("S3: the literal-word bonus counts whole words only: 'lease' does not match 'release'", async () => {
    expect(wordIn("we release on friday", "lease")).toBe(false);
    expect(wordIn("take the lease, then push", "lease")).toBe(true);
    expect(wordIn("see ide-334.", "ide-334")).toBe(true);
    expect(wordIn("ide-3345", "ide-334")).toBe(false);
    newAsk(root, { from: "meta:engine", to: "manager:meta", id: "rel", why: "w" }, ASK("When do we release the build?"));
    newAsk(root, { from: "meta:engine", to: "manager:meta", id: "lea", why: "w" }, ASK("When do we take the lease?"));
    const e = fakeEmbedder();
    await indexSources(db, sources(), e);
    const hits = await search(db, e, { q: "lease", kinds: ["ask"], minScore: 0 });
    const rel = hits.find((h) => h.id === "rel");
    const lea = hits.find((h) => h.id === "lea")!;
    // The fake embedder hashes whole words, so "release" shares no vector weight with "lease": without a bonus it
    // scores at most its cosine, and the bonus would be the only thing lifting it.
    expect(lea.score).toBeGreaterThan(0.1);
    expect(rel).toBeDefined();
    expect(rel!.score).toBeLessThan(0.1);
  });
});
