/**
 * ASKFOLLOW end to end: the card's helpers (followup.ts, reanswer.ts draftBody) against the real
 * server, so the client's reading of /api/followup, /api/asks and /api/draft is the server's.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { answerAsk, followupAsk, newAsk, reviseAsk, supersedeAsk, withdrawAsk } from "../src/lib/store.ts";
import { parseAskFile } from "../src/lib/format.ts";
import { adoptAfterFollowup, followupBody, followupBumpOf, followupConflict, followupOutcome, followupsOf, isAddressed } from "../src/client/followup.ts";
import { cardUnsent } from "../src/client/unsent.ts";
import { draftBody } from "../src/client/reanswer.ts";
import { BUILD_ID_FILE, computeBuildId } from "../src/build-id.ts";

function fakeDist(base: string): string {
  const d = path.join(base, "dist");
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, "index.html"), "<!doctype html><html><head><title>ask-app</title></head><body><div id=\"root\"></div></body></html>\n");
  fs.writeFileSync(path.join(d, BUILD_ID_FILE), `${computeBuildId()}\n`);
  return d;
}

const TOKEN = "t0k3n-followup-client";
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
const post = (p: string, body: unknown, headers = GOOD()) => req("POST", p, { headers, body: JSON.stringify(body) });
const fileOf = (id: string) => path.join(root, SEAT, `${id}.md`);

beforeAll(async () => {
  base = fs.mkdtempSync(path.join("/tmp", "asksrv-followup-client-"));
  root = path.join(base, "asks");
  fs.mkdirSync(path.join(base, "sessions"));
  for (const id of ["f1", "f2", "done", "old", "repl", "gone", "ovr"]) newAsk(root, { from: SEAT, to: MGR, id }, BODY);
  const quiet = async () => ({ status: "delivered" as const });
  await supersedeAsk(root, { seat: SEAT, id: "old" }, { seat: SEAT, id: "repl" }, { by: SEAT, push: quiet });
  await withdrawAsk(root, { seat: SEAT, id: "gone" }, { by: SEAT, reason: "no longer asked", push: quiet, now: "2026-10-30T10:00:00.000Z" });
  await answerAsk(root, SEAT, "ovr", { answers: { GO: ["YES"] }, answeredBy: MGR }, { expectedRevision: 1, push: async () => ({ status: "delivered" as const }) });
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


type Json = Record<string, unknown> & { error?: string };
const asks = async () => JSON.parse((await req("GET", "/api/asks")).body).asks as (ReturnType<typeof parseAskFile> & { seat: string; file: string; mtimeMs: number })[];
const askOf = async (id: string) => (await asks()).find((a) => a.header.id === id)!;
const send = async (p: string, body: unknown) => {
  const r = await post(p, body);
  return { status: r.status, json: JSON.parse(r.body) as Json };
};

describe("the card's follow-up against the server", () => {
  it("followupBody is accepted; followupOutcome reads the 200; /api/asks lists it, not addressed; a revise marks it addressed", async () => {
    const a = await askOf("f1");
    const r = await send("/api/followup", followupBody(a, { kind: "question", fork: "", text: "why NO?", attachPicks: true }, { GO: ["YES"] }));
    expect(r.status).toBe(200);
    const out = followupOutcome(a, r.status, r.json as never);
    expect(out.sent).toBe(true);
    expect(out.sent && out.revision).toBe(2);
    // No live session in the test's sessions dir: written, and said undelivered.
    expect(out.text).toMatch(/^Follow-up 1 is in the file, but undelivered \(/);
    const after = await askOf("f1");
    const fs1 = followupsOf(after);
    expect(fs1.map((f) => [f.n, f.kind, f.fork, f.picks, f.delivery])).toEqual([[1, "question", undefined, { GO: ["YES"] }, "undelivered"]]);
    expect(isAddressed(fs1[0])).toBe(false);
    // The asker answers it; the card reads it addressed.
    await reviseAsk(root, SEAT, "f1", {}, undefined, { by: SEAT, answersFollowup: [1], push: async () => ({ status: "delivered" as const }) });
    const done = followupsOf(await askOf("f1"))[0];
    expect(isAddressed(done)).toBe(true);
    expect(done.addressedBy).toBe(SEAT);
  });

  it("a draft saved at the revision read stays sendable after the operator's follow-up (the server re-bases it)", async () => {
    const a = await askOf("f2");
    expect((await send("/api/draft", draftBody(a, "draft", { answers: { GO: ["NO"] }, note: "" }))).status).toBe(200);
    expect((await send("/api/followup", followupBody(a, { kind: "first", fork: "GO", text: "check the bill first", attachPicks: false }, {}))).status).toBe(200);
    const b = await askOf("f2");
    expect(b.draft?.basedOn).toBe(Number(b.header.revision));
    const sent = await send("/api/send", { refs: [`${SEAT}/f2`] });
    expect(sent.status).toBe(200);
    expect((await askOf("f2")).header.status).toBe("answered");
  });

  it("a 409 is conflictStep's: withdrawn keeps under the open key and reloads, superseded names the replacement, a closed ask says so", async () => {
    const gone = await send("/api/followup", followupBody(await askOf("gone"), { kind: "question", fork: "", text: "x", attachPicks: false }, {}));
    expect(gone.status).toBe(409);
    expect(followupConflict(gone.json as never, "here", "open")).toMatchObject({ keepUnder: "open", reload: true });
    const old = await send("/api/followup", followupBody(await askOf("old"), { kind: "question", fork: "", text: "x", attachPicks: false }, {}));
    expect(followupConflict(old.json as never, "here", "open")).toMatchObject({ replacedBy: `${SEAT}/repl`, keepUnder: "here" });
    const done = await send("/api/followup", followupBody(await askOf("done"), { kind: "question", fork: "", text: "x", attachPicks: false }, {}));
    expect(followupConflict(done.json as never, "here", "open").text).toBe("Not sent: this ask is answered now, and a follow-up goes only to an open ask. Your text is kept here.");
  });

  it("the overrule form's Save draft is stored over a seat's ruling, and Send batch then overrules", async () => {
    const a = await askOf("ovr");
    const d = await send("/api/draft", draftBody(a, "draft", { answers: { GO: ["NO"] }, note: "" }));
    expect(d.status).toBe(200);
    const s = await send("/api/send", { refs: [`${SEAT}/ovr`] });
    expect(s.status).toBe(200);
    const b = await askOf("ovr");
    expect(b.answer).toMatchObject({ answeredBy: "operator", answers: { GO: ["NO"] } });
    expect(b.header.overruled).toBe(MGR);
  });
});

describe("MUST-FIX-1: a slow push lets the file change reach the page before the 200", () => {
  it("with a push that sleeps 300 ms, the file is written (and /api/events would fire 100 ms later) well before followupAsk returns", async () => {
    newAsk(root, { from: SEAT, to: MGR, id: "slow" }, BODY);
    let pushStartedAt = 0;
    let pushedAt = 0;
    let revisionAtPush = "";
    const slowPush = async () => {
      pushStartedAt = Date.now();
      revisionAtPush = parseAskFile(fs.readFileSync(path.join(root, SEAT, "slow.md"), "utf8")).header.revision ?? "";
      await new Promise((r) => setTimeout(r, 300));
      pushedAt = Date.now();
      return { status: "undelivered" as const, reason: "slow seat" };
    };
    const out = await followupAsk(root, SEAT, "slow", { by: "operator", via: "browser", kind: "question", text: "why?" }, { expectedRevision: 1, push: slowPush });
    const answeredAt = Date.now();
    expect(out.revision).toBe(2);
    // The write lands before the push starts (read at the push, not timed, so load cannot flake it): the server's SSE debounce (100 ms) fires a `change` while the 200 is still 300 ms away,
    // so the card reloads and remounts at revision 2 first.
    expect(revisionAtPush).toBe("2");
    expect(pushedAt - pushStartedAt).toBeGreaterThanOrEqual(290);
    // So the server's watcher (what /api/events debounces by 100 ms) sees the write with the whole push still
    // to run. Not timed with fs.watch here: its delivery on macOS is late or lost under load (it flaked).
    expect(answeredAt - pushStartedAt).toBeGreaterThanOrEqual(290);
    // What the remounted card reads at that moment: revision 2, the follow-up pending. The client saved
    // nothing before it posted; the card adopts the copy left at 1 (below).
    const mid = parseAskFile(fs.readFileSync(path.join(root, SEAT, "slow.md"), "utf8"));
    expect(mid.header.revision).toBe("2");
    // Delta SHOULD-A/B (b): the real writer's `revisions:` tail lets that card adopt the copy left at 1,
    // without the text it sent; this is also what a reload finds after the connection drops mid-push.
    expect(followupBumpOf(mid)).toEqual({ from: "1", n: 1, text: "why?" });
    expect(adoptAfterFollowup(cardUnsent("1", { values: { GO: ["NO"] }, text: {}, note: "", need: "", followup: "why? " }), mid)).toEqual({ revision: "2", values: { GO: ["NO"] }, text: {}, note: "" });
  });

  it("a revise just before the click: the follow-up is refused stale and the bumped ask is no follow-up bump, so nothing is adopted", async () => {
    newAsk(root, { from: SEAT, to: MGR, id: "race" }, BODY);
    await reviseAsk(root, SEAT, "race", { why: "sharper" }, undefined, { by: SEAT, push: async () => ({ status: "delivered" as const }) });
    await expect(followupAsk(root, SEAT, "race", { by: "operator", kind: "question", text: "why?" }, { expectedRevision: 1, push: async () => ({ status: "delivered" as const }) })).rejects.toThrow(/revision/i);
    const now = parseAskFile(fs.readFileSync(path.join(root, SEAT, "race.md"), "utf8"));
    expect(now.header.revision).toBe("2");
    expect(followupBumpOf(now)).toBeUndefined();
    const copy = cardUnsent("1", { values: { GO: ["NO"] }, text: {}, note: "", need: "", followup: "why?" });
    expect(adoptAfterFollowup(copy, now)).toBe(copy);
  });
});
