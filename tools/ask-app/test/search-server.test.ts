/**
 * IDE-334 (RAGPROOFS): GET /api/search on a real server process, against a fake Ollama, a fake proof store
 * (an env script whose `aws` prints a listing, and pages served over HTTP), and temp asks, broadcasts and
 * builds/ dirs. Covers the shape, the kind filter, the 400s, the 503s, and the refresh without a timer.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import type { AddressInfo } from "node:net";
import os from "node:os";
import path from "node:path";
import { newAsk } from "../src/lib/store.ts";
import { BUILD_ID_FILE, computeBuildId } from "../src/build-id.ts";
import { fakeEmbedder } from "./fixtures/fake-embedder.ts";

const TOKEN = "search-token";
const ASK = (t: string) => `## ¶ASK_GO: Choose one: ${t}\nContext: c\n- [ ] [YES] Yes\n  Picks YES.\n- [ ] [NO] No\n  Picks NO.\n`;
const PAGE = (t: string, p: string) => `<html><head><title>${t}</title></head><body><h1>${t}</h1><p>${p} ${"padding words for a real section ".repeat(5)}</p></body></html>`;

let base: string;
let fake: http.Server;
let fakePort: number;
let embedDown = false;
const procs: ChildProcess[] = [];

async function startFake() {
  const e = fakeEmbedder();
  fake = http.createServer(async (req, res) => {
    let body = "";
    for await (const c of req) body += c;
    if (req.url === "/api/embed") {
      if (embedDown) {
        res.writeHead(404, { "content-type": "application/json" });
        return res.end(JSON.stringify({ error: "model not found" }));
      }
      const input = JSON.parse(body).input as string[];
      const v = await e.embedTexts(input);
      res.writeHead(200, { "content-type": "application/json" });
      return res.end(JSON.stringify({ embeddings: v.map((x) => Array.from(x)) }));
    }
    const page = req.url?.match(/^\/proofs\/proofs\/invizko\/(.+)$/)?.[1];
    if (page === "ledger-1.html") {
      res.writeHead(200, { "content-type": "text/html" });
      return res.end(PAGE("Ledger reconciliation", "the ledger reconciles every payout against the bank statement"));
    }
    if (req.url === "/api/tags" || req.url === "/api/ps") {
      res.writeHead(200, { "content-type": "application/json" });
      return res.end(JSON.stringify({ models: [] }));
    }
    res.writeHead(404);
    res.end();
  });
  await new Promise<void>((r) => fake.listen(0, "127.0.0.1", () => r()));
  fakePort = (fake.address() as AddressInfo).port;
}

/** A proof-store env script whose `aws` prints one page; lib/proofs.ts sources it in place of the real one. */
function proveEnv(dir: string): string {
  const f = path.join(dir, "prove-env.sh");
  const listing = JSON.stringify({ Contents: [{ Key: "proofs/invizko/ledger-1.html", LastModified: "2026-10-30T10:00:00Z", Size: 100 }] });
  fs.writeFileSync(
    f,
    `PROVE_S3_ENDPOINT_URL=http://127.0.0.1:${fakePort}\nPROVE_S3_PUBLIC_URL=http://127.0.0.1:${fakePort}\nPROVE_S3_BUCKET=proofs\nPROVE_S3_PREFIX=proofs\nENDPOINT_ARG=()\nPROFILE_ARG=()\naws() { cat <<'JSON'\n${listing}\nJSON\n}\n`,
  );
  return f;
}

type Srv = { port: number; root: string; bdir: string; get: (p: string, h?: Record<string, string>) => Promise<{ status: number; body: string; headers: http.IncomingHttpHeaders }> };

async function startServer(name: string, env: Record<string, string>, seed?: (root: string, bdir: string, pdir: string) => void): Promise<Srv> {
  const dir = path.join(base, name);
  const root = path.join(dir, "asks");
  const bdir = path.join(dir, "broadcasts");
  const pdir = path.join(dir, "sessions");
  fs.mkdirSync(path.join(pdir, "S1", "builds"), { recursive: true });
  fs.mkdirSync(root, { recursive: true });
  fs.mkdirSync(bdir, { recursive: true });
  const dist = path.join(dir, "dist");
  fs.mkdirSync(dist);
  fs.writeFileSync(path.join(dist, "index.html"), "<!doctype html><html><head></head><body></body></html>\n");
  fs.writeFileSync(path.join(dist, BUILD_ID_FILE), `${computeBuildId()}\n`);
  seed?.(root, bdir, pdir);
  const port = 30000 + Math.floor(Math.random() * 20000);
  const proc = spawn(process.execPath, ["--no-warnings", "src/server.ts", "--root", root, "--port", String(port), "--token", TOKEN], {
    env: {
      ...process.env,
      ASK_APP_DIST: dist,
      ENGINE_EMBED_ENDPOINT: `http://127.0.0.1:${fakePort}`,
      ENGINE_EMBED_DIMENSIONS: "64",
      ENGINE_EMBED_MODEL: "fake",
      BROADCAST_DIR: bdir,
      ASK_SEARCH_PROOF_DIRS: pdir,
      ASK_PROVE_ENV_SH: proveEnv(dir),
      ...env,
    },
    stdio: "ignore",
  });
  procs.push(proc);
  const get: Srv["get"] = (p, h = {}) =>
    new Promise((resolve, reject) => {
      const r = http.request({ host: "127.0.0.1", port, path: p, method: "GET", headers: { host: `127.0.0.1:${port}`, "x-ask-token": TOKEN, ...h } }, (res) => {
        let b = "";
        res.on("data", (d) => (b += d));
        res.on("end", () => resolve({ status: res.statusCode!, body: b, headers: res.headers }));
      });
      r.on("error", reject);
      r.end();
    });
  for (let i = 0; i < 200; i++) {
    try {
      if ((await get("/api/health")).status === 200) return { port, root, bdir, get };
    } catch {
      /* not up yet */
    }
    await new Promise((r) => setTimeout(r, 50));
  }
  throw new Error("server did not start");
}

async function until<T>(f: () => Promise<T | undefined>, ms = 15_000): Promise<T> {
  const end = Date.now() + ms;
  for (;;) {
    const v = await f();
    if (v !== undefined) return v;
    if (Date.now() > end) throw new Error("condition not met in time");
    await new Promise((r) => setTimeout(r, 100));
  }
}

let main: Srv;

beforeAll(async () => {
  base = fs.mkdtempSync(path.join(os.tmpdir(), "asksearch-srv-"));
  await startFake();
  main = await startServer("main", { ASK_SEARCH_AUTO: "1", ASK_SEARCH_DEBOUNCE_MS: "50", ASK_SEARCH_STALE_MS: "1500" }, (root, bdir, pdir) => {
    newAsk(root, { from: "meta:engine", to: "manager:meta", id: "warm-cache", why: "the warmer cache decides cold start latency" }, ASK("Ship the warmer cache tonight?"));
    fs.writeFileSync(path.join(bdir, "freeze.md"), "id: freeze\nfrom: director\nat: 2026-10-30T10:00:00Z\naudience: all\nsticky: yes\n\n## Text\nCode freeze on the kernel until the migration lands.\n");
    fs.writeFileSync(path.join(pdir, "S1", "builds", "ledger_PROOF.html"), PAGE("Ledger reconciliation", "the ledger reconciles every payout against the bank statement"));
  });
  await until(async () => {
    const s = JSON.parse((await main.get("/api/search/status")).body);
    return s.indexedAt && s.running === null ? s : undefined;
  });
});

afterAll(() => {
  for (const p of procs) p.kill();
  fake.close();
  fs.rmSync(base, { recursive: true, force: true });
});

describe("GET /api/search", () => {
  it("refuses without the page's token, and from a foreign origin", async () => {
    expect((await main.get("/api/search?q=cache", { "x-ask-token": "nope" })).status).toBe(403);
    expect((await main.get("/api/search?q=cache", { origin: "http://evil.example" })).status).toBe(403);
  });

  it("answers 400 for a missing q, a bad limit and an unknown kind", async () => {
    expect((await main.get("/api/search")).status).toBe(400);
    expect((await main.get("/api/search?q=x&limit=0")).status).toBe(400);
    expect((await main.get("/api/search?q=x&limit=abc")).status).toBe(400);
    const k = await main.get("/api/search?q=x&kind=ticket");
    expect(k.status).toBe(400);
    expect(JSON.parse(k.body).error).toMatch(/unknown kind ticket/);
  });

  it("returns [{kind, seat, id, title, status, score, excerpt, url, appPath, section}], one per item", async () => {
    const r = await main.get("/api/search?q=warmer%20cache%20latency&limit=10");
    expect(r.status).toBe(200);
    expect(r.headers["x-search-indexed-at"]).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    const hits = JSON.parse(r.body);
    expect(Array.isArray(hits)).toBe(true);
    expect(Object.keys(hits[0]).sort()).toEqual(["appPath", "excerpt", "id", "kind", "score", "seat", "section", "status", "title", "url"]);
    expect(hits[0]).toMatchObject({ kind: "ask", seat: "meta:engine", id: "warm-cache", status: "open", url: `http://127.0.0.1:4977/a/meta:engine/warm-cache`, appPath: "/a/meta:engine/warm-cache" });
    // The bucket page and its builds/ copy are one proof, the published one.
    const proofs = hits.filter((h: { kind: string }) => h.kind === "proof");
    expect(proofs).toHaveLength(1);
    expect(proofs[0]).toMatchObject({ status: "published", url: `http://127.0.0.1:${fakePort}/proofs/proofs/invizko/ledger-1.html`, appPath: "/proofs/proofs/invizko/ledger-1.html" });
  });

  it("filters by kind", async () => {
    const hits = JSON.parse((await main.get("/api/search?q=ledger%20payout&kind=proof")).body);
    expect(hits.map((h: { kind: string }) => h.kind)).toEqual(["proof"]);
    const two = JSON.parse((await main.get("/api/search?q=kernel%20freeze&kind=broadcast,ask")).body);
    expect(new Set(two.map((h: { kind: string }) => h.kind))).toEqual(new Set(["broadcast", "ask"]));
  });

  it("indexes a new ask within seconds of its file being written, with no timer and no stale pass", async () => {
    // Its own server with a stale window it never reaches, so only the ask-file watcher can index the ask.
    const w = await startServer("watch", { ASK_SEARCH_AUTO: "1", ASK_SEARCH_DEBOUNCE_MS: "50", ASK_SEARCH_STALE_MS: "600000", ASK_SEARCH_SOURCES_OFF: "proof-bucket" }, (root) => {
      newAsk(root, { from: "meta:engine", to: "manager:meta", id: "seed", why: "seed" }, ASK("Seed the index?"));
    });
    await until(async () => {
      const st = JSON.parse((await w.get("/api/search/status")).body);
      return st.indexedAt && st.running === null ? st : undefined;
    });
    newAsk(w.root, { from: "domain:stats", to: "manager:domain", id: "histogram-bins", why: "bin width for the latency histogram" }, ASK("Use logarithmic histogram bins?"));
    const t0 = Date.now();
    const hit = await until(async () => {
      const hits = JSON.parse((await w.get("/api/search?q=logarithmic%20histogram%20bins&kind=ask")).body);
      return hits.find((h: { id: string }) => h.id === "histogram-bins");
    }, 6000);
    expect(hit).toMatchObject({ seat: "domain:stats", status: "open" });
    expect(Date.now() - t0).toBeLessThan(6000);
  });

  it("refreshes a stale index behind a search: a broadcast nobody watches appears on a later search", async () => {
    fs.writeFileSync(path.join(main.bdir, "rotate.md"), "id: rotate\nfrom: director\nat: 2026-10-30T11:00:00Z\naudience: all\nsticky: yes\n\n## Text\nRotate the signing keys for the payments vault on Friday.\n");
    await new Promise((r) => setTimeout(r, 1600)); // older than ASK_SEARCH_STALE_MS
    const first = await main.get("/api/search?q=rotate%20signing%20keys&kind=broadcast");
    expect(first.status).toBe(200);
    expect(first.headers["x-search-refreshing"]).toBe("1");
    const hit = await until(async () => {
      const hits = JSON.parse((await main.get("/api/search?q=rotate%20signing%20keys&kind=broadcast")).body);
      return hits.find((h: { id: string }) => h.id === "rotate");
    });
    expect(hit).toMatchObject({ seat: "director", appPath: "/broadcasts/rotate" });
  });

  it("answers 503 with a reason when the embedder is down, never an empty 200", async () => {
    embedDown = true;
    try {
      const r = await main.get("/api/search?q=cache");
      expect(r.status).toBe(503);
      expect(JSON.parse(r.body)).toMatchObject({ reason: "embedder-unavailable", code: "MODEL_ABSENT" });
    } finally {
      embedDown = false;
    }
  });

  it("answers 503 index-empty from a server whose index has nothing yet", async () => {
    const empty = await startServer("empty", { ASK_SEARCH_AUTO: "0", ASK_SEARCH_SOURCES_OFF: "proof-bucket" });
    const r = await empty.get("/api/search?q=anything");
    expect(r.status).toBe(503);
    expect(JSON.parse(r.body)).toMatchObject({ reason: "index-empty" });
  });
});
