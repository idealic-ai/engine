/**
 * Ask v2 over HTTP: drafts, the batch send (refs only), NEW-3, and linked tickets fetched
 * server-side with a Linear key that must never reach a response. Linear is a local fake here.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { newAsk } from "../src/lib/store.ts";
import { parseAskFile } from "../src/lib/format.ts";
import { BUILD_ID_FILE, computeBuildId } from "../src/build-id.ts";

/** A stand-in client, stamped with the build id the server needs: no test reads or builds the live dist/. */
function fakeDist(base: string): string {
  const d = path.join(base, "dist");
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, "index.html"), "<!doctype html><html><head><title>ask-app</title></head><body><div id=\"root\"></div></body></html>\n");
  fs.writeFileSync(path.join(d, BUILD_ID_FILE), `${computeBuildId()}\n`);
  return d;
}

const KEY = "lin_api_TESTSECRET_0123456789abcdef";
const TOKEN = "t0k3n-v2";
const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n";
let base: string, root: string, port: number, proc: ChildProcess;
let linear: http.Server, linearPort: number;
const linearSeen: { auth?: string; body: string }[] = [];

beforeAll(async () => {
  base = fs.mkdtempSync(path.join("/tmp", "asksrv2-"));
  root = path.join(base, "asks");
  fs.mkdirSync(path.join(base, "sessions"));
  linear = http.createServer((req, res) => {
    let b = "";
    req.on("data", (d) => (b += d));
    req.on("end", () => {
      linearSeen.push({ auth: req.headers.authorization, body: b });
      const id = JSON.parse(b).variables.id;
      res.writeHead(200, { "content-type": "application/json" });
      if (id === "IDE-404") return res.end(JSON.stringify({ data: { issue: null }, errors: [{ message: "Entity not found" }] }));
      res.end(JSON.stringify({ data: { issue: {
        identifier: id, title: "ASK v2", url: `https://linear.app/x/issue/${id}`,
        description: `**In plain terms:** Make the app easier to trust. The key ${KEY} must not leak.\n\nMore.`,
        state: { name: "In Progress", type: "started" }, assignee: { name: "Yaroslaff" },
        createdAt: "2026-10-28T00:00:00Z", updatedAt: "2026-10-29T00:00:00Z", startedAt: "2026-10-29T00:30:00Z", completedAt: null, canceledAt: null,
        secretField: KEY,
      } } }));
    });
  });
  await new Promise((r) => linear.listen(0, "127.0.0.1", () => r(null)));
  linearPort = (linear.address() as { port: number }).port;
  // The key reaches the server through a file named in the environment, never argv.
  const envFile = path.join(base, "linear.env");
  fs.writeFileSync(envFile, `OTHER=1\nLINEAR_API_KEY=${KEY}\n`);
  port = 30000 + Math.floor(Math.random() * 20000);
  const env: NodeJS.ProcessEnv = { ...process.env, ASK_SESSIONS_DIR: path.join(base, "sessions"), ASK_LINEAR_ENV: envFile, ASK_LINEAR_ENDPOINT: `http://127.0.0.1:${linearPort}/graphql`, ASK_APP_DIST: fakeDist(base) };
  delete env.LINEAR_API_KEY;
  proc = spawn(process.execPath, ["--no-warnings", "src/server.ts", "--root", root, "--port", String(port), "--token", TOKEN], { env, stdio: "ignore" });
  for (let i = 0; i < 100; i++) {
    try {
      if ((await req("GET", "/api/health")).status === 200) return;
    } catch {
      // not up yet
    }
    await new Promise((r) => setTimeout(r, 50));
  }
  throw new Error("server did not start");
});
afterAll(() => {
  proc.kill();
  linear.close();
  fs.rmSync(base, { recursive: true, force: true });
});

function req(method: string, p: string, opts: { headers?: Record<string, string>; body?: string } = {}): Promise<{ status: number; body: string }> {
  return new Promise((resolve, reject) => {
    const r = http.request({ host: "127.0.0.1", port, path: p, method, headers: { host: `127.0.0.1:${port}`, ...opts.headers } }, (res) => {
      let b = "";
      res.on("data", (d) => (b += d));
      res.on("end", () => resolve({ status: res.statusCode!, body: b }));
    });
    r.on("error", reject);
    if (opts.body) r.write(opts.body);
    r.end();
  });
}
const GOOD = () => ({ "content-type": "application/json", origin: `http://127.0.0.1:${port}`, "x-ask-token": TOKEN });
const post = (p: string, body: unknown, headers = GOOD()) => req("POST", p, { headers, body: JSON.stringify(body) });
let n = 0;
const fresh = (extra: Record<string, string> = {}) => {
  const id = `v${++n}`;
  newAsk(root, { from: "idealic:kernel", to: "operator", id, ...extra }, BODY);
  return id;
};
const fileOf = (id: string) => parseAskFile(fs.readFileSync(path.join(root, "idealic:kernel", `${id}.md`), "utf8"));

describe("drafts and the batch over HTTP (acceptance 1)", () => {
  it("saves a draft, then the batch sends it — and the batch ignores answers in its body", async () => {
    const id = fresh();
    expect((await post("/api/draft", { seat: "idealic:kernel", id, expectedRevision: 1, answers: { GO: ["YES"] } })).status).toBe(200);
    expect(fileOf(id).header.status).toBe("open");
    const r = await post("/api/send", { refs: [`idealic:kernel/${id}`], answers: { GO: ["NO"] } });
    expect(r.status).toBe(200);
    expect(JSON.parse(r.body).settled[0].ref).toBe(`idealic:kernel/${id}`);
    expect(fileOf(id).answer?.answers).toEqual({ GO: ["YES"] });
  });

  it("stamps the identity the server established, not one the body claims (R4)", async () => {
    const id = fresh();
    await post("/api/draft", { seat: "idealic:kernel", id, expectedRevision: 1, answers: { GO: ["YES"] }, by: "manager:director", answeredBy: "manager:director" });
    await post("/api/send", { refs: [`idealic:kernel/${id}`] });
    expect(fileOf(id).answer).toMatchObject({ answeredBy: "operator", answeredVia: "browser" });
  });

  it("the batch refuses without the token, and writes nothing", async () => {
    const id = fresh();
    await post("/api/draft", { seat: "idealic:kernel", id, expectedRevision: 1, answers: { GO: ["YES"] } });
    expect((await post("/api/send", { refs: [`idealic:kernel/${id}`] }, { ...GOOD(), "x-ask-token": "nope" })).status).toBe(403);
    expect((await post("/api/draft", { seat: "idealic:kernel", id, expectedRevision: 1, answers: { GO: ["NO"] } }, { ...GOOD(), origin: "https://evil.example" })).status).toBe(403);
    expect(fileOf(id).header.status).toBe("open");
    expect(fileOf(id).draft?.answers).toEqual({ GO: ["YES"] });
  });

  it("a stale draft save is a 409", async () => {
    const id = fresh();
    expect((await post("/api/draft", { seat: "idealic:kernel", id, expectedRevision: 5, answers: { GO: ["YES"] } })).status).toBe(409);
  });

  it("discard removes the draft", async () => {
    const id = fresh();
    await post("/api/draft", { seat: "idealic:kernel", id, expectedRevision: 1, answers: { GO: ["YES"] } });
    expect((await post("/api/discard", { seat: "idealic:kernel", id })).status).toBe(200);
    expect(fileOf(id).draft).toBeUndefined();
  });
});

describe("NEW-3: a decline must carry a string reason", () => {
  it.each([[null], [false], [{}], [["x"]]])("refuses decline: %j with 400 and writes nothing", async (decline) => {
    const id = fresh();
    const r = await post("/api/answer", { seat: "idealic:kernel", id, expectedRevision: 1, decline });
    expect(r.status).toBe(400);
    expect(fileOf(id).header.status).toBe("open");
    const d = await post("/api/draft", { seat: "idealic:kernel", id, expectedRevision: 1, decline });
    expect(d.status).toBe(400);
  });
});

describe("linked tickets (acceptance 6)", () => {
  it("returns whitelisted ticket details, fetched with the key, and never the key", async () => {
    const r = await req("GET", "/api/ticket/IDE-253", { headers: { "x-ask-token": TOKEN } });
    expect(r.status).toBe(200);
    const j = JSON.parse(r.body);
    expect(j).toMatchObject({ key: "IDE-253", title: "ASK v2", status: "In Progress", statusSince: "2026-10-29T00:30:00Z", assignee: "Yaroslaff", url: "https://linear.app/x/issue/IDE-253" });
    expect(j.summary).toMatch(/^In plain terms: Make the app easier to trust\./);
    expect(Object.keys(j).sort()).toEqual(["assignee", "key", "status", "statusSince", "statusType", "summary", "title", "url"]);
    expect(r.body).not.toContain("TESTSECRET");
    expect(linearSeen.at(-1)!.auth).toBe(KEY);
  });

  it("caches: a second hover does not call Linear again", async () => {
    const before = linearSeen.length;
    await req("GET", "/api/ticket/IDE-253", { headers: { "x-ask-token": TOKEN } });
    expect(linearSeen.length).toBe(before);
  });

  it("a missing ticket is a 404 that says so, without the key", async () => {
    const r = await req("GET", "/api/ticket/IDE-404", { headers: { "x-ask-token": TOKEN } });
    expect(r.status).toBe(404);
    expect(r.body).not.toContain("TESTSECRET");
  });

  it("refuses a malformed key, a missing token and a foreign Host", async () => {
    expect((await req("GET", "/api/ticket/not-a-key", { headers: { "x-ask-token": TOKEN } })).status).toBe(400);
    expect((await req("GET", "/api/ticket/IDE-253")).status).toBe(403);
    expect((await req("GET", "/api/ticket/IDE-253", { headers: { "x-ask-token": TOKEN, host: "evil.example" } })).status).toBe(403);
  });

  it("the key appears in no response, the page, the asks, or any ask file", async () => {
    const id = fresh({ tickets: "IDE-253" });
    await post("/api/draft", { seat: "idealic:kernel", id, expectedRevision: 1, answers: { GO: ["YES"] } });
    await post("/api/send", { refs: [`idealic:kernel/${id}`] });
    for (const p of ["/", "/api/health", "/api/asks"]) expect((await req("GET", p)).body).not.toContain("TESTSECRET");
    const files = fs.readdirSync(root, { recursive: true }) as string[];
    for (const f of files) {
      const full = path.join(root, f);
      if (fs.statSync(full).isFile()) expect(fs.readFileSync(full, "utf8")).not.toContain("TESTSECRET");
    }
    const ps = await new Promise<string>((r) => {
      const c = spawn("ps", ["-o", "command=", "-p", String(proc.pid)]);
      let o = "";
      c.stdout.on("data", (d) => (o += d));
      c.on("close", () => r(o));
    });
    expect(ps).not.toContain("TESTSECRET");
  });
});

describe("fix round 1 over HTTP", () => {
  it("M3: the browser is stamped operator via browser, and the batch with no refs sends only the operator's drafts", async () => {
    const mine = fresh();
    await post("/api/draft", { seat: "idealic:kernel", id: mine, expectedRevision: 1, answers: { GO: ["YES"] } });
    // A seat's draft (to: that seat), written through the store.
    const theirs = `v${++n}`;
    newAsk(root, { from: "idealic:kernel", to: "manager:app", id: theirs }, BODY);
    const { saveDraft } = await import("../src/lib/store.ts");
    await saveDraft(root, "idealic:kernel", theirs, { answers: { GO: ["NO"] }, answeredBy: "manager:app" }, 1);
    const r = JSON.parse((await post("/api/send", {})).body);
    expect(r.settled.map((x: { ref: string }) => x.ref)).toContain(`idealic:kernel/${mine}`);
    expect(r.settled.map((x: { ref: string }) => x.ref)).not.toContain(`idealic:kernel/${theirs}`);
    expect(fileOf(mine).answer).toMatchObject({ answeredBy: "operator", answeredVia: "browser" });
    expect(fileOf(theirs).header.status).toBe("open");
    // Round 3 (MUST-2): the operator may discard a seat's draft; it just never SENDS it.
    expect((await post("/api/discard", { seat: "idealic:kernel", id: theirs })).status).toBe(200);
    expect(fileOf(theirs).draft).toBeUndefined();
  });

  it("N2: a malformed ticket escape is a 400, and a missing ask is a 404, with no absolute path in any 4xx", async () => {
    const t = await req("GET", "/api/ticket/%E0%A4%A", { headers: { "x-ask-token": TOKEN } });
    expect(t.status).toBe(400);
    const d = await post("/api/discard", { seat: "idealic:kernel", id: "nope" });
    expect(d.status).toBe(404);
    const dup = await post("/api/answer", { seat: "idealic:kernel", id: "nope", expectedRevision: 1, answers: { GO: ["YES"] } });
    expect(dup.status).toBe(404);
    for (const b of [t.body, d.body, dup.body]) {
      expect(b).not.toContain(base);
      expect(b).not.toMatch(/"[^"]*\/(?:tmp|Users|private)\//);
    }
  });
});

describe("S9 (round 2): the server serves only the client its sources build", () => {
  it("a dist with no build id, or another one, is a 503 that says so — never a silent old client", async () => {
    const d = path.join(base, "dist");
    expect((await req("GET", "/")).status).toBe(200);
    const id = fs.readFileSync(path.join(d, BUILD_ID_FILE), "utf8");
    fs.writeFileSync(path.join(d, BUILD_ID_FILE), "0123456789abcdef\n");
    let r = await req("GET", "/");
    expect(r.status).toBe(503);
    expect(r.body).toContain("build mismatch: the built client is build 0123456789abcdef");
    expect(r.body).toContain(`serves only build ${computeBuildId()}`);
    fs.rmSync(path.join(d, BUILD_ID_FILE));
    r = await req("GET", "/");
    expect(r.status).toBe(503);
    expect(r.body).toContain("unstamped (v1 or hand-made) build");
    fs.writeFileSync(path.join(d, BUILD_ID_FILE), id);
    expect((await req("GET", "/")).status).toBe(200);
  });
});

describe("MUST-2 (round 3) over HTTP: a seat's draft never locks the operator out of the app", () => {
  it("/api/draft replaces a seat's relay draft, /api/discard drops a seat's draft", async () => {
    const { saveDraft } = await import("../src/lib/store.ts");
    const a = `v${++n}`;
    newAsk(root, { from: "idealic:kernel", to: "manager:app", id: a, "reserved-for": "operator" }, BODY);
    await saveDraft(root, "idealic:kernel", a, { answers: { GO: ["YES"] }, answeredBy: "operator", answeredVia: "relay:manager:app", note: "n" }, 1);
    expect((await post("/api/draft", { seat: "idealic:kernel", id: a, expectedRevision: 1, answers: { GO: ["NO"] } })).status).toBe(200);
    expect(fileOf(a).draft).toMatchObject({ answers: { GO: ["NO"] }, answeredVia: "browser" });
    expect(JSON.parse((await post("/api/send", { refs: [`idealic:kernel/${a}`] })).body).settled).toHaveLength(1);
    const b = `v${++n}`;
    newAsk(root, { from: "idealic:kernel", to: "manager:app", id: b }, BODY);
    await saveDraft(root, "idealic:kernel", b, { answers: { GO: ["YES"] }, answeredBy: "manager:app" }, 1);
    expect((await post("/api/discard", { seat: "idealic:kernel", id: b })).status).toBe(200);
    expect(fileOf(b).draft).toBeUndefined();
  });
});
