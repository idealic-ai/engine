/**
 * RAGSEARCH-UI: the client's fetchSemantic against the real server and the REAL local embedder (no fake
 * Ollama), over temp asks only: no proof store (an `aws` stub that lists nothing), no proof dirs, an
 * empty broadcast dir. Skipped, with the reason, when the local embedder does not answer, since then
 * the only thing to see is a 503 embedder-unavailable, which ragsearch-ui.test.ts already covers.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { newAsk } from "../src/lib/store.ts";
import { BUILD_ID_FILE, computeBuildId } from "../src/build-id.ts";
import { createLocalEmbeddingClient, resolveEmbedConfig } from "../../embed-local/src/index.ts";
import { resetTokenState } from "../src/client/token.ts";
import { fetchSemantic, mergeResults } from "../src/client/semantic.ts";

const TOKEN = "ragsearch-e2e-token";

async function embedderDown(): Promise<string | null> {
  try {
    await createLocalEmbeddingClient({ config: { ...resolveEmbedConfig(), timeoutMs: 5000 } }).embedSingle("probe");
    return null;
  } catch (e) {
    return `${(e as { code?: string }).code ?? "error"}: ${(e as Error).message}`;
  }
}
const down = await embedderDown();
if (down) console.warn(`ragsearch-e2e skipped: the local embedder does not answer (${down})`);

const ASK = (t: string) => `## ¶ASK_GO: Choose one: ${t}\nContext: c\n- [ ] [YES] Yes\n  Picks YES.\n- [ ] [NO] No\n  Picks NO.\n`;

describe.skipIf(!!down)("the search bar's request against the real server and embedder", () => {
  let dir: string;
  let proc: ChildProcess;
  let port: number;
  const at = (p: string) => `http://127.0.0.1:${port}${p}`;
  const f = (u: string, init?: RequestInit) => fetch(at(u), init);

  beforeAll(async () => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), "ragsearch-e2e-"));
    const root = path.join(dir, "asks");
    const bdir = path.join(dir, "broadcasts");
    const pdir = path.join(dir, "sessions");
    const dist = path.join(dir, "dist");
    for (const d of [root, bdir, pdir, dist]) fs.mkdirSync(d, { recursive: true });
    fs.writeFileSync(path.join(dist, "index.html"), "<!doctype html><html><head></head><body></body></html>\n");
    fs.writeFileSync(path.join(dist, BUILD_ID_FILE), `${computeBuildId()}\n`);
    const envSh = path.join(dir, "prove-env.sh");
    fs.writeFileSync(envSh, `PROVE_S3_BUCKET=none\nPROVE_S3_PREFIX=none\nENDPOINT_ARG=()\nPROFILE_ARG=()\naws() { echo '{"Contents":[]}'; }\n`);
    newAsk(root, { from: "meta:engine", to: "operator", id: "warm-cache", why: "the warmer cache decides cold start latency" }, ASK("Ship the warmer cache tonight?"));
    newAsk(root, { from: "domain:platform", to: "operator", id: "dns-move", why: "move the public hostname to the new load balancer" }, ASK("Cut DNS over to the new balancer?"));
    port = 30000 + Math.floor(Math.random() * 20000);
    const env: NodeJS.ProcessEnv = { ...process.env, ASK_APP_DIST: dist, BROADCAST_DIR: bdir, ASK_SEARCH_PROOF_DIRS: pdir, ASK_PROVE_ENV_SH: envSh, ASK_SEARCH_AUTO: "1", ASK_SEARCH_DEBOUNCE_MS: "50" };
    delete env.ASK_SEARCH_DB;
    proc = spawn(process.execPath, ["--no-warnings", "src/server.ts", "--root", root, "--port", String(port), "--token", TOKEN], { env, stdio: "ignore" });
    const end = Date.now() + 60_000;
    for (;;) {
      try {
        const s = await (await fetch(at("/api/search/status"), { headers: { "x-ask-token": TOKEN } })).json();
        if (s.indexedAt && s.running === null) break;
      } catch {
        /* not up yet */
      }
      if (Date.now() > end) throw new Error("the server did not index in time");
      await new Promise((r) => setTimeout(r, 200));
    }
    resetTokenState(TOKEN);
  }, 90_000);

  afterAll(() => {
    proc?.kill();
    if (dir) fs.rmSync(dir, { recursive: true, force: true });
  });

  it("answers a query by meaning with the asks it holds, the index age, and refreshing off", async () => {
    const a = await fetchSemantic("caching to make startup faster", { fetch: f });
    expect(a.ok).toBe(true);
    if (!a.ok) return;
    expect(a.indexedAt && Number.isFinite(Date.parse(a.indexedAt))).toBe(true);
    expect(a.refreshing).toBe(false);
    expect(a.hits[0]).toMatchObject({ kind: "ask", seat: "meta:engine", id: "warm-cache" });
    const merged = mergeResults([], a.hits);
    expect(merged.items[0]).toMatchObject({ key: "meta:engine/warm-cache", match: "meaning" });
    expect(merged.items[0].excerpt).toBeTruthy();
    // The merge key is the row's ref: what the server's hit names must be what /api/asks's ask is called.
    const asks = (await (await f("/api/asks")).json()).asks as { seat: string; header: { id: string } }[];
    expect(asks.map((x) => `${x.seat}/${x.header.id}`)).toContain(merged.items[0].key);
    expect(mergeResults([{ ref: merged.items[0].key, title: "t", seat: "s", status: "open" } as never], a.hits).items[0].match).toBe("both");
  }, 30_000);

  it("a stale token is refreshed from the served page and the search retried once (token.ts)", async () => {
    resetTokenState("stale");
    try {
      expect(await fetchSemantic("cache", { fetch: f })).toMatchObject({ ok: true, q: "cache" });
    } finally {
      resetTokenState(TOKEN);
    }
  }, 30_000);
});
