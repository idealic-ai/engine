/**
 * ASKFOLLOWUP over HTTP: POST /api/followup writes a follow-up stamped with the server's answerer
 * (the body cannot set `by`), 409 on a stale revision or a closed ask, 400 on empty text, an unknown
 * kind or an unknown fork; /api/asks' `history` carries follow-ups as `{type: "followup", …}`.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { answerAsk, newAsk } from "../src/lib/store.ts";
import { parseAskFile } from "../src/lib/format.ts";
import { BUILD_ID_FILE, computeBuildId } from "../src/build-id.ts";

function fakeDist(base: string): string {
  const d = path.join(base, "dist");
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, "index.html"), "<!doctype html><html><head><title>ask-app</title></head><body><div id=\"root\"></div></body></html>\n");
  fs.writeFileSync(path.join(d, BUILD_ID_FILE), `${computeBuildId()}\n`);
  return d;
}

const TOKEN = "t0k3n-followup";
const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n";
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
const post = (p: string, body: unknown, headers = GOOD()) => req("POST", p, { headers, body: JSON.stringify(body) });
const fileOf = (id: string) => path.join(root, SEAT, `${id}.md`);

beforeAll(async () => {
  base = fs.mkdtempSync(path.join("/tmp", "asksrv-followup-"));
  root = path.join(base, "asks");
  fs.mkdirSync(path.join(base, "sessions"));
  for (const id of ["f1", "f2", "done"]) newAsk(root, { from: SEAT, to: MGR, id }, BODY);
  await answerAsk(root, SEAT, "done", { answers: { GO: ["YES"] }, answeredBy: MGR }, { expectedRevision: 1, push: async () => ({ status: "delivered" as const }) });
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

describe("POST /api/followup", () => {
  it("writes the follow-up, bumps the revision and returns {revision, followup}; `by` is the server's, never the body's", async () => {
    const r = await post("/api/followup", { seat: SEAT, id: "f1", expectedRevision: 1, kind: "first", fork: "GO", text: "rebase first", picks: { GO: ["NO"] }, by: "manager:docs" });
    expect(r.status).toBe(200);
    const b = JSON.parse(r.body);
    expect(b.revision).toBe(2);
    expect(b.followup).toMatchObject({ n: 1, by: "operator", kind: "first", fork: "GO", text: "rebase first", picks: { GO: ["NO"] } });
    expect(typeof b.followup.at).toBe("string");
    const p = parseAskFile(fs.readFileSync(fileOf("f1"), "utf8"));
    expect(p.header.status).toBe("open");
    expect(p.followups[0]).toMatchObject({ n: 1, by: "operator", via: "browser" });
    // No live session in the empty sessions dir: the push failed and the entry says so.
    expect(p.followups[0].delivery).toBe("undelivered");
  });

  it("409 on a stale revision, with the current revision", async () => {
    const r = await post("/api/followup", { seat: SEAT, id: "f1", expectedRevision: 1, kind: "question", text: "x" });
    expect(r.status).toBe(409);
    expect(JSON.parse(r.body).revision).toBe(2);
  });

  it("409 on a closed ask, naming its status; the answer is untouched", async () => {
    const before = fs.readFileSync(fileOf("done"), "utf8");
    const r = await post("/api/followup", { seat: SEAT, id: "done", expectedRevision: 2, kind: "question", text: "x" });
    expect(r.status).toBe(409);
    expect(JSON.parse(r.body)).toMatchObject({ status: "answered" });
    expect(fs.readFileSync(fileOf("done"), "utf8")).toBe(before);
  });

  it("400 on empty text, an unknown kind and an unknown fork, writing nothing", async () => {
    const before = fs.readFileSync(fileOf("f2"), "utf8");
    for (const bad of [{ kind: "question", text: "  " }, { kind: "later", text: "x" }, { kind: "question", fork: "NOPE", text: "x" }, { kind: "question" }]) {
      const r = await post("/api/followup", { seat: SEAT, id: "f2", expectedRevision: 1, ...bad });
      expect(r.status, JSON.stringify(bad)).toBe(400);
    }
    expect(fs.readFileSync(fileOf("f2"), "utf8")).toBe(before);
  });

  it("is gated like every write: no token, no write", async () => {
    const r = await post("/api/followup", { seat: SEAT, id: "f2", expectedRevision: 1, kind: "question", text: "x" }, { "content-type": "application/json" } as never);
    expect(r.status).toBe(403);
  });

  it("404 on an ask that does not exist", async () => {
    const r = await post("/api/followup", { seat: SEAT, id: "nope", expectedRevision: 1, kind: "question", text: "x" });
    expect(r.status).toBe(404);
    expect(JSON.parse(r.body).error).toBe("no such ask");
  });
});

describe("/api/asks history carries follow-ups", () => {
  it("as {type: followup, …} entries beside the replaced answers", async () => {
    const asks = JSON.parse((await req("GET", "/api/asks")).body).asks as { header: Record<string, string>; history: Record<string, unknown>[] }[];
    const f1 = asks.find((a) => a.header.id === "f1")!;
    expect(f1.history).toHaveLength(1);
    expect(f1.history[0]).toMatchObject({ type: "followup", n: 1, kind: "first", text: "rebase first" });
    expect(asks.find((a) => a.header.id === "done")!.history).toEqual([]);
  });
});
