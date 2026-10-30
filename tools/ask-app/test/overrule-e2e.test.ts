/**
 * IDE-339 end to end: the client's overrule against the real server (src/server.ts over a temp root). A
 * manager's ruling with a grant class renders with it and offers Overrule; the draft path is refused on it,
 * which is why the overrule posts /api/answer; a grantClass never reaches the server; afterwards the card
 * shows the stamp and the earlier answer.
 */
import { afterAll, beforeAll, expect, it } from "vitest";
import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { answerAsk, newAsk } from "../src/lib/store.ts";
import { BUILD_ID_FILE, computeBuildId } from "../src/build-id.ts";
import { draftBody, overruleBody, withoutGrant } from "../src/client/reanswer.ts";

const TOKEN = "t0k3n-e2e";
const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes, ship\n- [ ] [NO] No, hold\n";
const SEAT = "docs:handbook", MGR = "manager:docs";
let base: string, root: string, port: number, proc: ChildProcess;
function req(method: string, p: string, body?: unknown): Promise<{ status: number; json: any }> {
  return new Promise((resolve, reject) => {
    const headers: Record<string, string> = { host: `127.0.0.1:${port}` };
    if (body !== undefined) Object.assign(headers, { "content-type": "application/json", origin: `http://127.0.0.1:${port}`, "x-ask-token": TOKEN });
    const r = http.request({ host: "127.0.0.1", port, path: p, method, headers }, (res) => {
      let b = ""; res.on("data", (d) => (b += d)); res.on("end", () => resolve({ status: res.statusCode!, json: b ? JSON.parse(b) : undefined }));
    });
    r.on("error", reject); if (body !== undefined) r.write(JSON.stringify(body)); r.end();
  });
}
const askOf = async () => ({ ...(await req("GET", "/api/asks")).json.asks.find((a: any) => a.header.id === "g1") });
const render = async (ask: any) => { const { AskDetail } = await import("../src/client/App.tsx"); return renderToStaticMarkup(createElement(AskDetail, { ask, all: [ask], onChanged: () => {} })); };

beforeAll(async () => {
  base = fs.mkdtempSync(path.join("/tmp", "askovr-e2e-"));
  root = path.join(base, "asks"); fs.mkdirSync(path.join(base, "sessions"));
  const d = path.join(base, "dist"); fs.mkdirSync(d);
  fs.writeFileSync(path.join(d, "index.html"), "<!doctype html><html><body></body></html>\n"); fs.writeFileSync(path.join(d, BUILD_ID_FILE), `${computeBuildId()}\n`);
  newAsk(root, { from: SEAT, to: MGR, id: "g1" }, BODY);
  await answerAsk(root, SEAT, "g1", { answers: { GO: ["YES"] }, note: "ship it", answeredBy: MGR, answeredVia: "cli", grantClass: "B" }, { expectedRevision: 1, push: async () => ({ status: "delivered" as const }), answererManages: [SEAT] });
  port = 30000 + Math.floor(Math.random() * 20000);
  const env: NodeJS.ProcessEnv = { ...process.env, ASK_SESSIONS_DIR: path.join(base, "sessions"), ASK_LINEAR_ENV: "/dev/null", ASK_APP_DIST: d };
  delete env.LINEAR_API_KEY;
  proc = spawn(process.execPath, ["--no-warnings", "src/server.ts", "--root", root, "--port", String(port), "--token", TOKEN], { env, stdio: "ignore" });
  for (let i = 0; i < 100; i++) { try { if ((await req("GET", "/api/health")).status === 200) return; } catch {} await new Promise((r) => setTimeout(r, 50)); }
  throw new Error("server did not start");
});
afterAll(() => { proc.kill(); fs.rmSync(base, { recursive: true, force: true }); });

it("the seat's ruling renders with its grant class and offers Overrule", async () => {
  const a = await askOf();
  expect(a.history).toEqual([]);
  const h = await render(a);
  expect(h).toContain("<b>Ruled by manager:docs · class B</b>");
  expect(h).toMatch(/<button[^>]*>Overrule<\/button>/);
  expect(h).not.toContain("Earlier answers");
});

it("the draft path is refused on a seat's ruling, which is why the overrule posts /api/answer", async () => {
  const a = await askOf();
  const r = await req("POST", "/api/draft", draftBody(a, "send-now", { answers: { GO: ["NO"] }, note: "" }));
  expect(r.json?.error).toMatch(/only an open ask, or the operator's own answer, takes a draft/);
  expect(r.status).toBe(400);
});

it("a grantClass smuggled into a body is dropped by withoutGrant, so the server takes it", async () => {
  const a = await askOf();
  const raw = { ...overruleBody(a, "send", { answers: { GO: ["NO"] }, note: "hold" }), grantClass: "A" };
  expect((await req("POST", "/api/answer", raw)).status).toBe(400); // the server's own refusal, for contrast
  const r = await req("POST", "/api/answer", withoutGrant(raw));
  expect(r.status).toBe(200);
});

it("after the overrule: the stamp, the history with the class, and the card", async () => {
  const a = await askOf();
  expect(a.header.overruled).toBe(MGR);
  expect(a.history).toHaveLength(1);
  expect(a.history[0]).toMatchObject({ answeredBy: MGR, grantClass: "B" });
  expect(a.answer.grantClass).toBeUndefined();
  const h = await render(a);
  expect(h).toContain("Overruled manager:docs’s ruling");
  expect(h).toMatch(/<summary>Earlier answers \(1\)<\/summary>/);
  expect(h).toContain("manager:docs · class B");
  expect(h).toContain("YES · Yes, ship");
  expect(h).toContain("ship it");
  expect(h).toMatch(/<button[^>]*>Change answer<\/button>/);
  expect(h).not.toContain("ruled-by");
});
