import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { newAsk } from "../src/lib/store.ts";
import { parseAskFile } from "../src/lib/format.ts";

const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n";
const TOKEN = "t0k3n-for-tests";
let base: string;
let root: string;
let port: number;
let proc: ChildProcess;

beforeAll(async () => {
  base = fs.mkdtempSync(path.join("/tmp", "asksrv-"));
  root = path.join(base, "asks");
  fs.mkdirSync(path.join(base, "sessions"));
  port = 30000 + Math.floor(Math.random() * 20000);
  proc = spawn(process.execPath, ["--no-warnings", "src/server.ts", "--root", root, "--port", String(port), "--token", TOKEN], {
    env: { ...process.env, ASK_SESSIONS_DIR: path.join(base, "sessions") },
    stdio: "ignore",
  });
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
let n = 0;
function freshAsk(): string {
  const id = `s${++n}`;
  newAsk(root, { from: "idealic:kernel", to: "operator", id }, BODY);
  return id;
}
const answer = (id: string, extra: Record<string, unknown> = {}) =>
  JSON.stringify({ seat: "idealic:kernel", id, expectedRevision: 1, answers: { GO: ["YES"] }, ...extra });
const statusOf = (id: string) => parseAskFile(fs.readFileSync(path.join(root, "idealic:kernel", `${id}.md`), "utf8")).header.status;

describe("MF-1: the server refuses cross-origin and rebinding requests", () => {
  it("accepts a same-origin json POST carrying the token, and stamps the answerer itself", async () => {
    const id = freshAsk();
    const r = await req("POST", "/api/answer", { headers: GOOD(), body: answer(id, { by: "someone-else" }) });
    expect(r.status).toBe(200);
    expect(statusOf(id)).toBe("answered");
    const ask = parseAskFile(fs.readFileSync(path.join(root, "idealic:kernel", `${id}.md`), "utf8"));
    expect(ask.answer?.answeredBy).toBe("operator");
  });

  it.each([
    ["a text/plain body (no preflight)", { "content-type": "text/plain" }, 415],
    ["a foreign Origin", { origin: "https://evil.example" }, 403],
    ["a missing token", { "x-ask-token": "" }, 403],
    ["a wrong token", { "x-ask-token": "guess" }, 403],
  ])("refuses %s and writes nothing", async (_name, override, code) => {
    const id = freshAsk();
    const r = await req("POST", "/api/answer", { headers: { ...GOOD(), ...override }, body: answer(id) });
    expect(r.status).toBe(code);
    expect(statusOf(id)).toBe("open");
  });

  it("refuses any route whose Host is not the loopback origin (DNS rebinding)", async () => {
    for (const p of ["/api/asks", "/api/health", "/"]) {
      const r = await req("GET", p, { headers: { host: `attacker.example:${port}` } });
      expect(r.status).toBe(403);
    }
    expect((await req("GET", "/api/asks", { headers: { host: `localhost:${port}` } })).status).toBe(200);
  });

  it("hands the token to the page it serves, and nowhere else", async () => {
    const r = await req("GET", "/");
    if (r.status === 503) return; // client not built in this checkout
    expect(r.body).toContain(`<meta name="ask-token" content="${TOKEN}">`);
    expect((await req("GET", "/api/health")).body).not.toContain(TOKEN);
  });
});

describe("MF-3 / MF-4 over HTTP", () => {
  it("refuses an empty answer with 400 and leaves the ask open", async () => {
    const id = freshAsk();
    const r = await req("POST", "/api/answer", { headers: GOOD(), body: answer(id, { answers: {} }) });
    expect(r.status).toBe(400);
    expect(statusOf(id)).toBe("open");
  });

  it("records a decline with a reason", async () => {
    const id = freshAsk();
    const r = await req("POST", "/api/answer", { headers: GOOD(), body: JSON.stringify({ seat: "idealic:kernel", id, expectedRevision: 1, decline: "not mine to rule" }) });
    expect(r.status).toBe(200);
    expect(statusOf(id)).toBe("declined");
  });

  it("refuses a stale revision with 409 and the current answer", async () => {
    const id = freshAsk();
    expect((await req("POST", "/api/answer", { headers: GOOD(), body: answer(id) })).status).toBe(200);
    const r = await req("POST", "/api/answer", { headers: GOOD(), body: answer(id, { answers: { GO: ["NO"] } }) });
    expect(r.status).toBe(409);
    const j = JSON.parse(r.body);
    expect(j.revision).toBe(2);
    expect(j.answer.answers).toEqual({ GO: ["YES"] });
  });
});
