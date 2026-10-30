/**
 * IDE-339 over HTTP: the browser never writes a grant class (`/api/answer` and `/api/draft` refuse
 * one, and the file is left as it was), and `/api/asks` returns each ask's history as a parsed array.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { answerAsk, newAsk } from "../src/lib/store.ts";
import { BUILD_ID_FILE, computeBuildId } from "../src/build-id.ts";

function fakeDist(base: string): string {
  const d = path.join(base, "dist");
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, "index.html"), "<!doctype html><html><head><title>ask-app</title></head><body><div id=\"root\"></div></body></html>\n");
  fs.writeFileSync(path.join(d, BUILD_ID_FILE), `${computeBuildId()}\n`);
  return d;
}

const TOKEN = "t0k3n-overrule";
const BODY = "## ¶ASK_GO: Choose one: Ship it?\nContext: c\n- [ ] [YES] Yes\n  Picks YES.\n- [ ] [NO] No\n  Picks NO.\n";
const SEAT = "docs:handbook";
const MGR = "manager:docs";
let base: string, root: string, port: number, proc: ChildProcess;

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
const post = (p: string, body: unknown) => req("POST", p, { headers: GOOD(), body: JSON.stringify(body) });

beforeAll(async () => {
  base = fs.mkdtempSync(path.join("/tmp", "asksrv-overrule-"));
  root = path.join(base, "asks");
  fs.mkdirSync(path.join(base, "sessions"));
  newAsk(root, { from: SEAT, to: MGR, id: "g1" }, BODY);
  newAsk(root, { from: SEAT, to: MGR, id: "h1" }, BODY);
  const push = async () => ({ status: "delivered" as const });
  await answerAsk(root, SEAT, "h1", { answers: { GO: ["YES"] }, answeredBy: MGR, answeredVia: "cli", grantClass: "B" }, { expectedRevision: 1, push, answererManages: [SEAT] });
  await answerAsk(root, SEAT, "h1", { answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: "browser" }, { expectedRevision: 2, push });
  port = 30000 + Math.floor(Math.random() * 20000);
  const env: NodeJS.ProcessEnv = { ...process.env, ASK_SESSIONS_DIR: path.join(base, "sessions"), ASK_LINEAR_ENV: "/dev/null", ASK_APP_DIST: fakeDist(base) };
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
  fs.rmSync(base, { recursive: true, force: true });
});

describe("the browser never writes a grant class", () => {
  it("/api/answer refuses a grantClass and writes nothing", async () => {
    const before = fs.readFileSync(path.join(root, SEAT, "g1.md"), "utf8");
    const r = await post("/api/answer", { seat: SEAT, id: "g1", expectedRevision: 1, answers: { GO: ["YES"] }, grantClass: "A" });
    expect(r.status).toBe(400);
    expect(JSON.parse(r.body).error).toMatch(/grant class/);
    expect(fs.readFileSync(path.join(root, SEAT, "g1.md"), "utf8")).toBe(before);
  });

  it("/api/draft refuses one too", async () => {
    const r = await post("/api/draft", { seat: SEAT, id: "g1", expectedRevision: 1, answers: { GO: ["YES"] }, grantClass: "D" });
    expect(r.status).toBe(400);
  });

  it("/api/answer without one still answers", async () => {
    const r = await post("/api/answer", { seat: SEAT, id: "g1", expectedRevision: 1, answers: { GO: ["YES"] } });
    expect(r.status).toBe(200);
  });
});

describe("/api/asks carries history", () => {
  it("as a parsed array of the prior answer records, with the overrule stamp", async () => {
    const r = await req("GET", "/api/asks");
    const asks = JSON.parse(r.body).asks as { header: Record<string, string>; history: Record<string, unknown>[]; answer: Record<string, unknown> }[];
    const h1 = asks.find((a) => a.header.id === "h1")!;
    expect(Array.isArray(h1.history)).toBe(true);
    expect(h1.history).toHaveLength(1);
    expect(h1.history[0]).toMatchObject({ answeredBy: MGR, grantClass: "B", revision: 2, answers: { GO: ["YES"] } });
    expect(h1.header.overruled).toBe(MGR);
    expect(h1.answer).toMatchObject({ answeredBy: "operator", revision: 3 });
    const g1 = asks.find((a) => a.header.id === "g1")!;
    expect(g1.history).toEqual([]);
  });
});
