/**
 * IDE-334 (RAGPROOFS): the on-demand refresh. No timer: a pass runs on start, when a search finds the index
 * stale, and (debounced) when an ask file changes.
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { openSearchDb, setMeta, type SearchDb } from "../src/search/db.ts";
import { createRefresher } from "../src/search/refresher.ts";
import type { Source } from "../src/search/sources.ts";
import { fakeEmbedder } from "./fixtures/fake-embedder.ts";

let base: string;
let db: SearchDb;
let dbFile: string;
let lists: Record<string, number>;

/** A source that counts its listings and holds one item. */
const counting = (name: string): Source => ({
  name,
  kind: "broadcast",
  list: async () => {
    lists[name] = (lists[name] ?? 0) + 1;
    return { ok: true, items: [{ key: `${name}:1`, stamp: "s", read: async () => ({ kind: "broadcast", seat: "x", id: "1", title: "t", status: "in-force", url: null, appPath: null, textHash: "h", chunks: [{ section: "t", content: `t\n${name} body` }] }) }] };
  },
});

beforeEach(() => {
  base = fs.mkdtempSync(path.join(os.tmpdir(), "asksearch-refresh-"));
  dbFile = path.join(base, "index.db");
  db = openSearchDb(dbFile);
  lists = {};
});
afterEach(() => {
  db.close();
  fs.rmSync(base, { recursive: true, force: true });
});

function make(clock: { t: number }, embedder = fakeEmbedder()) {
  return createRefresher({ db, dbFile, sources: () => [counting("all")], askSources: () => [counting("asks")], embedder, staleMs: 300_000, debounceMs: 20, now: () => clock.t });
}

describe("refresher", () => {
  it("runs a full pass on start, and a search within the stale window starts none", async () => {
    const clock = { t: Date.now() };
    const r = make(clock);
    await r.start();
    expect(lists.all).toBe(1);
    expect(r.state().indexedAt).not.toBeNull();
    clock.t += 60_000;
    expect(r.ensureFresh()).toBe(false);
    await r.idle();
    expect(lists.all).toBe(1);
  });

  it("trusts a fresh index another process built (a CLI `index`): no pass", async () => {
    const clock = { t: Date.now() };
    setMeta(db, "last_index_at", new Date(clock.t - 10_000).toISOString());
    const r = make(clock);
    expect(r.ensureFresh()).toBe(false);
    await r.idle();
    expect(lists.all).toBeUndefined();
  });

  it("starts a pass behind a search once the index is older than the window, and only one", async () => {
    const clock = { t: Date.now() };
    const r = make(clock);
    await r.start();
    clock.t = Date.parse(r.state().indexedAt!) + 300_001;
    expect(r.ensureFresh()).toBe(true);
    expect(r.state().running).toBe("full");
    expect(r.ensureFresh()).toBe(false);
    await r.idle();
    expect(lists.all).toBe(2);
  });

  it("does not retry a failed pass before another window has gone by", async () => {
    const clock = { t: Date.now() };
    const e = fakeEmbedder();
    e.fail = true;
    const r = make(clock, e);
    await r.start();
    expect(r.state().indexedAt).toBeNull();
    expect(r.state().lastReport?.error).toMatch(/nothing listening/);
    clock.t += 1000;
    expect(r.ensureFresh()).toBe(false);
    clock.t += 300_000;
    expect(r.ensureFresh()).toBe(true);
    await r.idle();
  });

  it("folds a burst of ask changes into one asks-only pass", async () => {
    const r = make({ t: Date.now() });
    r.asksChanged();
    r.asksChanged();
    r.asksChanged();
    await new Promise((res) => setTimeout(res, 80));
    await r.idle();
    expect(lists.asks).toBe(1);
    expect(lists.all).toBeUndefined();
  });

  it("skips a pass while another process holds the index lock", async () => {
    fs.writeFileSync(`${dbFile}.lock`, String(process.ppid));
    const r = make({ t: Date.now() });
    await r.start();
    expect(lists.all).toBeUndefined();
    expect(r.state().skippedLocked).toBe(1);
  });
});
