/**
 * WAKEBTN: the operator wakes the seat an ask is waiting on, from the ask app.
 *
 * Library half (wakeAsk / wakeView): the target is the `to:` seat, or the newest `forwards:` target
 * once the ask was passed up; each refusal arm (operator, closed, no-pane, cooldown) with its code;
 * the record (wokenAt, wokenBy, wokenSeat, wakeDelivery) is written without moving the revision.
 * The push is stubbed through the same `push` seam the answer tests use, and seat liveness is read
 * from a fixture sessions dir whose registry names this test's own (live) pid.
 *
 * HTTP half: POST /api/asks/<seat>/<id>/wake on a real server, the guards /api/answer uses, the
 * real pushToSeat into a unix socket this test listens on, and /api/asks rows carrying the state.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { execFileSync, spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import net from "node:net";
import path from "node:path";
import { answerAsk, forwardAsk, newAsk, renameSeat, reviseAsk } from "../src/lib/store.ts";
import { AskFormatError, parseAskFile, setHeaderField } from "../src/lib/format.ts";
import { WAKE_COOLDOWN_MS, WAKE_PENDING_HOLD_MS, WakeRefused, wakeAsk, wakeTarget, wakeView } from "../src/lib/wake.ts";
import { BUILD_ID_FILE, computeBuildId } from "../src/build-id.ts";

const BODY = "## ¶ASK_GO: Choose one: Ship it?\nContext: c\n- [ ] [YES] Yes\n  Picks YES.\n- [ ] [NO] No\n  Picks NO.\n";
const ASKER = "domain:security";
const HOLDER = "manager:domain";
const PARENT = "manager:director";
const T0 = Date.parse("2026-10-31T00:00:00.000Z");

type Pushed = { seat: string; content: string };

describe("wakeAsk and wakeView (library)", () => {
  let base: string, root: string, sessions: string;
  let pushed: Pushed[];
  const push = async (seat: string, content: string) => {
    pushed.push({ seat, content });
    return { status: "delivered" as const };
  };
  const live = (seat: string) =>
    fs.writeFileSync(path.join(sessions, `${process.pid}.json`), JSON.stringify({ pid: process.pid, name: seat, messagingSocketPath: path.join(sessions, "x.sock") }));
  const file = (id: string) => path.join(root, ASKER, `${id}.md`);
  const read = (id: string) => parseAskFile(fs.readFileSync(file(id), "utf8"));
  const refusal = async (p: Promise<unknown>) => {
    try {
      await p;
    } catch (e) {
      if (e instanceof WakeRefused) return e;
      throw e;
    }
    throw new Error("expected a WakeRefused");
  };

  beforeEach(() => {
    base = fs.mkdtempSync(path.join("/tmp", "askwake-"));
    root = path.join(base, "asks");
    sessions = path.join(base, "sessions");
    fs.mkdirSync(sessions);
    pushed = [];
  });

  it("targets the to: seat, pushes it a wake that names the ask, and records the wake without moving the revision", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "a1" }, BODY);
    live(HOLDER);
    expect(wakeTarget(read("a1"))).toBe(HOLDER);
    const out = await wakeAsk(root, ASKER, "a1", { by: "operator", now: T0, push, sessionsDir: sessions });
    expect(out).toMatchObject({ target: HOLDER, wokenAt: new Date(T0).toISOString(), wokenBy: "operator", delivery: { status: "delivered" } });
    expect(out.wakeAfter).toBe(new Date(T0 + WAKE_COOLDOWN_MS).toISOString());
    expect(pushed).toHaveLength(1);
    expect(pushed[0].seat).toBe(HOLDER);
    expect(pushed[0].content).toContain(`operator woke you for ask ${ASKER}/a1`);
    expect(pushed[0].content).toContain("read your asks");
    expect(pushed[0].content).toContain(`engine ask list --to ${HOLDER} --status open`);
    expect(pushed[0].content).not.toContain("--seat");
    const h = read("a1").header;
    expect(h).toMatchObject({ wokenAt: new Date(T0).toISOString(), wokenBy: "operator", wokenSeat: HOLDER, wakeDelivery: "delivered" });
    expect(h.revision).toBe("1");
    expect(h.status).toBe("open");
  });

  it("targets the newest forwards: target once the ask was passed up", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "fw" }, BODY);
    await forwardAsk(root, ASKER, "fw", { to: PARENT, by: HOLDER, now: "2026-10-30T23:00:00.000Z" });
    live(PARENT);
    const ask = read("fw");
    expect(ask.header.forwards).toContain(`${HOLDER}→${PARENT}`);
    expect(wakeTarget(ask)).toBe(PARENT);
    const out = await wakeAsk(root, ASKER, "fw", { by: "operator", now: T0, push, sessionsDir: sessions });
    expect(out.target).toBe(PARENT);
    expect(pushed.map((p) => p.seat)).toEqual([PARENT]);
  });

  it("refuses with code operator when the ask waits on the operator, and pushes nothing", async () => {
    newAsk(root, { from: ASKER, to: "operator", id: "op" }, BODY);
    const e = await refusal(wakeAsk(root, ASKER, "op", { by: "operator", now: T0, push, sessionsDir: sessions }));
    expect(e.code).toBe("operator");
    expect(e.message).toMatch(/operator/);
    expect(pushed).toEqual([]);
    expect(read("op").header.wokenAt).toBeUndefined();
  });

  it("refuses with code closed when the ask is not open", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "done" }, BODY);
    await answerAsk(root, ASKER, "done", { answers: { GO: ["YES"] }, answeredBy: HOLDER }, { expectedRevision: 1, push: async () => ({ status: "delivered" as const }) });
    live(HOLDER);
    const e = await refusal(wakeAsk(root, ASKER, "done", { by: "operator", now: T0, push, sessionsDir: sessions }));
    expect(e.code).toBe("closed");
    expect(e.message).toMatch(/answered/);
    expect(pushed).toEqual([]);
  });

  it("refuses with code no-pane when no live session holds the seat, and when two do", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "np" }, BODY);
    const e = await refusal(wakeAsk(root, ASKER, "np", { by: "operator", now: T0, push, sessionsDir: sessions }));
    expect(e.code).toBe("no-pane");
    expect(e.message).toMatch(/no live session/);
    // Two live sessions answering to one seat: never guessed between.
    live(HOLDER);
    fs.writeFileSync(path.join(sessions, `${process.ppid}.json`), JSON.stringify({ pid: process.ppid, name: HOLDER, messagingSocketPath: path.join(sessions, "y.sock") }));
    const e2 = await refusal(wakeAsk(root, ASKER, "np", { by: "operator", now: T0, push, sessionsDir: sessions }));
    expect(e2.code).toBe("no-pane");
    expect(e2.message).toMatch(/more than one/);
    expect(pushed).toEqual([]);
    expect(read("np").header.wokenAt).toBeUndefined();
  });

  it("refuses a re-wake within five minutes with code cooldown and wakeAfter, and allows it after", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "cd" }, BODY);
    live(HOLDER);
    await wakeAsk(root, ASKER, "cd", { by: "operator", now: T0, push, sessionsDir: sessions });
    const e = await refusal(wakeAsk(root, ASKER, "cd", { by: "operator", now: T0 + WAKE_COOLDOWN_MS - 1, push, sessionsDir: sessions }));
    expect(e.code).toBe("cooldown");
    expect(e.wakeAfter).toBe(new Date(T0 + WAKE_COOLDOWN_MS).toISOString());
    expect(pushed).toHaveLength(1);
    const again = await wakeAsk(root, ASKER, "cd", { by: "operator", now: T0 + WAKE_COOLDOWN_MS, push, sessionsDir: sessions });
    expect(again.wokenAt).toBe(new Date(T0 + WAKE_COOLDOWN_MS).toISOString());
    expect(pushed).toHaveLength(2);
  });

  it("records a push that failed as undelivered, with its reason, and starts no cooldown", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "fail" }, BODY);
    live(HOLDER);
    const bad = async () => ({ status: "undelivered" as const, reason: "ECONNREFUSED: socket closed" });
    const out = await wakeAsk(root, ASKER, "fail", { by: "operator", now: T0, push: bad, sessionsDir: sessions });
    expect(out.delivery).toEqual({ status: "undelivered", reason: "ECONNREFUSED: socket closed" });
    expect(out.wakeAfter).toBeUndefined();
    expect(read("fail").header).toMatchObject({ wakeDelivery: "undelivered", wakeDeliveryNote: "ECONNREFUSED: socket closed" });
    const retry = await wakeAsk(root, ASKER, "fail", { by: "operator", now: T0 + 1000, push, sessionsDir: sessions });
    expect(retry.delivery.status).toBe("delivered");
    expect(read("fail").header.wakeDeliveryNote).toBeUndefined();
  });

  it("the list command in the message, run as the woken seat would run it, lists the ask it was woken for", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "cmd" }, BODY);
    newAsk(root, { from: HOLDER, to: ASKER, id: "mine" }, BODY); // an ask the holder RAISED: `--seat` would list this one
    live(HOLDER);
    await wakeAsk(root, ASKER, "cmd", { by: "operator", now: T0, push, sessionsDir: sessions });
    const cmd = pushed[0].content.match(/`engine ask list ([^`]+)`/)?.[1];
    expect(cmd).toBe(`--to ${HOLDER} --status open`);
    const out = execFileSync(process.execPath, ["--no-warnings", "src/cli.ts", "list", ...cmd!.split(" "), "--root", root], { encoding: "utf8" });
    expect(out).toContain(`${ASKER}/cmd`);
    expect(out).not.toContain(`${HOLDER}/mine`);
  });

  it("a forward after a wake lets the new holder be woken at once; the old holder's cooldown does not carry over", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "fwa" }, BODY);
    live(HOLDER);
    await wakeAsk(root, ASKER, "fwa", { by: "operator", now: T0, push, sessionsDir: sessions });
    await forwardAsk(root, ASKER, "fwa", { to: PARENT, by: HOLDER, now: new Date(T0 + 60_000).toISOString() });
    live(PARENT);
    const view = wakeView(read("fwa"), { now: T0 + 61_000, sessionsDir: sessions });
    expect(view).toMatchObject({ wakeTarget: PARENT, wokenSeat: HOLDER });
    expect(view.wakeBlocked).toBeUndefined();
    expect(view.wakeAfter).toBeUndefined();
    const out = await wakeAsk(root, ASKER, "fwa", { by: "operator", now: T0 + 61_000, push, sessionsDir: sessions });
    expect(out.target).toBe(PARENT);
    expect(pushed.map((p) => p.seat)).toEqual([HOLDER, PARENT]);
    // ...and now the new holder is the one under cooldown.
    const e = await refusal(wakeAsk(root, ASKER, "fwa", { by: "operator", now: T0 + 62_000, push, sessionsDir: sessions }));
    expect(e.code).toBe("cooldown");
  });

  it("two quick clicks push once: the second is refused with cooldown while the first is still pushing", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "dbl" }, BODY);
    live(HOLDER);
    const slow = async (seat: string, content: string) => {
      await new Promise((r) => setTimeout(r, 50));
      return push(seat, content);
    };
    const [a, b] = await Promise.allSettled([
      wakeAsk(root, ASKER, "dbl", { by: "operator", now: T0, push: slow, sessionsDir: sessions }),
      wakeAsk(root, ASKER, "dbl", { by: "operator", now: T0 + 10, push: slow, sessionsDir: sessions }),
    ]);
    const settled = [a, b];
    expect(settled.filter((x) => x.status === "fulfilled")).toHaveLength(1);
    const rejected = settled.find((x) => x.status === "rejected") as PromiseRejectedResult;
    expect(rejected.reason).toBeInstanceOf(WakeRefused);
    expect((rejected.reason as WakeRefused).code).toBe("cooldown");
    expect(pushed).toHaveLength(1);
  });

  it("NOTIFYQ (b): a pending whose outcome stamp never landed holds the cooldown only for the push bound, not five minutes", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "stuck" }, BODY);
    live(HOLDER);
    // A wake claimed and pushed, but its outcome stamp failed: the record still says pending.
    let t = fs.readFileSync(file("stuck"), "utf8");
    for (const [k, v] of [["wokenAt", new Date(T0).toISOString()], ["wokenBy", "operator"], ["wokenSeat", HOLDER], ["wakeDelivery", "pending"]]) t = setHeaderField(t, k, v);
    fs.writeFileSync(file("stuck"), t);
    // Inside the bound it is a push in flight: a second click is still refused.
    expect(wakeView(read("stuck"), { now: T0 + WAKE_PENDING_HOLD_MS - 1, sessionsDir: sessions }).wakeBlocked).toBe("cooldown");
    // Past it, nothing holds the button.
    const view = wakeView(read("stuck"), { now: T0 + WAKE_PENDING_HOLD_MS, sessionsDir: sessions });
    expect(view.wakeBlocked).toBeUndefined();
    expect(view.wakeAfter).toBeUndefined();
    const out = await wakeAsk(root, ASKER, "stuck", { by: "operator", now: T0 + WAKE_PENDING_HOLD_MS, push, sessionsDir: sessions });
    expect(out.delivery.status).toBe("delivered");
    expect(pushed).toHaveLength(1);
  });

  it("NOTIFYQ (c): a wake has one target, so a push reporting partial is recorded as undelivered and starts no cooldown", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "part" }, BODY);
    live(HOLDER);
    const partial = async () => ({ status: "partial" as const, reason: "half" });
    const out = await wakeAsk(root, ASKER, "part", { by: "operator", now: T0, push: partial, sessionsDir: sessions });
    expect(out.delivery.status).toBe("undelivered");
    expect(out.delivery.reason).toMatch(/one target; the push reported partial \(half\)/);
    expect(out.wakeAfter).toBeUndefined();
    expect(read("part").header.wakeDelivery).toBe("undelivered");
  });

  it("a later wake's record is kept: an earlier wake's stamp never overwrites it", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "late" }, BODY);
    live(HOLDER);
    const later = new Date(T0 + 1000).toISOString();
    // While the first wake's push is in flight, a later wake claims the record.
    const racing = async (seat: string, content: string) => {
      let t = fs.readFileSync(file("late"), "utf8");
      t = setHeaderField(setHeaderField(t, "wokenAt", later), "wakeDelivery", "pending");
      fs.writeFileSync(file("late"), t);
      pushed.push({ seat, content });
      return { status: "undelivered" as const, reason: "first push failed" };
    };
    const out = await wakeAsk(root, ASKER, "late", { by: "operator", now: T0, push: racing, sessionsDir: sessions });
    expect(out.delivery.status).toBe("undelivered");
    const h = read("late").header;
    expect(h.wokenAt).toBe(later);
    expect(h.wakeDelivery).toBe("pending");
    expect(h.wakeDeliveryNote).toBeUndefined();
  });

  it("a wake that reached the seat is reported delivered even when its stamp cannot be written", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "gone" }, BODY);
    live(HOLDER);
    // The seat folder disappears while the push is in flight, so the stamp's lock fails.
    const moving = async (seat: string, content: string) => {
      fs.renameSync(path.join(root, ASKER), path.join(base, "moved-away"));
      return push(seat, content);
    };
    const out = await wakeAsk(root, ASKER, "gone", { by: "operator", now: T0, push: moving, sessionsDir: sessions });
    expect(out.delivery.status).toBe("delivered");
    expect(out.wakeAfter).toBe(new Date(T0 + WAKE_COOLDOWN_MS).toISOString());
  });

  it("a seat renamed while the push is in flight gets the stamp at its new path", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "ren" }, BODY);
    live(HOLDER);
    const renaming = async (seat: string, content: string) => {
      await renameSeat(root, ASKER, "domain:safety", { by: "operator" });
      return push(seat, content);
    };
    const out = await wakeAsk(root, ASKER, "ren", { by: "operator", now: T0, push: renaming, sessionsDir: sessions });
    expect(out.delivery.status).toBe("delivered");
    const moved = parseAskFile(fs.readFileSync(path.join(root, "domain:safety", "ren.md"), "utf8")).header;
    expect(moved).toMatchObject({ wokenAt: new Date(T0).toISOString(), wakeDelivery: "delivered" });
  });

  it("the wake fields are store stamps: new and revise refuse them, and rename-seat rewrites wokenSeat", async () => {
    for (const k of ["wokenAt", "wokenBy", "wokenSeat", "wakeDelivery", "wakeDeliveryNote"]) {
      expect(() => newAsk(root, { from: ASKER, to: HOLDER, id: `st-${k.toLowerCase()}`, [k]: "x" }, BODY)).toThrow(AskFormatError);
    }
    newAsk(root, { from: ASKER, to: HOLDER, id: "rev" }, BODY);
    await expect(reviseAsk(root, ASKER, "rev", { wakeDelivery: "undelivered" }, undefined, { by: ASKER, push })).rejects.toThrow(/not revisable/);
    live(HOLDER);
    await wakeAsk(root, ASKER, "rev", { by: "operator", now: T0, push, sessionsDir: sessions });
    await renameSeat(root, HOLDER, "manager:domains", { by: "operator" });
    expect(read("rev").header.wokenSeat).toBe("manager:domains");
  });

  it("wakeView reports the state a list row shows, without trying: target, woken, wakeAfter and the blocking code", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "v" }, BODY);
    newAsk(root, { from: ASKER, to: "operator", id: "vop" }, BODY);
    const opts = { now: T0, sessionsDir: sessions };
    expect(wakeView(read("v"), opts)).toMatchObject({ wakeTarget: HOLDER, wakeBlocked: "no-pane" });
    expect(wakeView(read("vop"), opts)).toMatchObject({ wakeTarget: "operator", wakeBlocked: "operator" });
    live(HOLDER);
    const free = wakeView(read("v"), opts);
    expect(free.wakeBlocked).toBeUndefined();
    expect(free.wokenAt).toBeUndefined();
    await wakeAsk(root, ASKER, "v", { by: "operator", now: T0, push, sessionsDir: sessions });
    expect(wakeView(read("v"), { now: T0 + 60_000, sessionsDir: sessions })).toMatchObject({
      wakeTarget: HOLDER,
      wokenAt: new Date(T0).toISOString(),
      wokenBy: "operator",
      wakeDelivery: "delivered",
      wakeBlocked: "cooldown",
      wakeAfter: new Date(T0 + WAKE_COOLDOWN_MS).toISOString(),
    });
    // Past the cooldown the row is wakeable again, and still says when it was last woken.
    const later = wakeView(read("v"), { now: T0 + WAKE_COOLDOWN_MS, sessionsDir: sessions });
    expect(later.wakeBlocked).toBeUndefined();
    expect(later.wokenAt).toBe(new Date(T0).toISOString());
  });
});

// ── HTTP ──────────────────────────────────────────────────────────────────

function fakeDist(base: string): string {
  const d = path.join(base, "dist");
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, "index.html"), "<!doctype html><html><head><title>ask-app</title></head><body></body></html>\n");
  fs.writeFileSync(path.join(d, BUILD_ID_FILE), `${computeBuildId()}\n`);
  return d;
}

describe("POST /api/asks/<seat>/<id>/wake (server)", () => {
  const TOKEN = "t0k3n-wake";
  let base: string, root: string, sessions: string, port: number, proc: ChildProcess, sock: net.Server;
  const got: string[] = [];

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
  const wake = (seat: string, id: string, headers = GOOD()) => req("POST", `/api/asks/${encodeURIComponent(seat)}/${encodeURIComponent(id)}/wake`, { headers, body: "{}" });
  const row = async (id: string) => (JSON.parse((await req("GET", "/api/asks")).body).asks as Record<string, unknown>[]).find((a) => (a.header as Record<string, string>).id === id)!;

  beforeAll(async () => {
    base = fs.mkdtempSync(path.join("/tmp", "askwk-"));
    root = path.join(base, "asks");
    sessions = path.join(base, "s");
    fs.mkdirSync(sessions);
    const sockPath = path.join(base, "h.sock");
    sock = net.createServer((c) => {
      let buf = "";
      c.on("data", (d) => (buf += d.toString()));
      c.on("end", () => got.push(buf));
    });
    await new Promise<void>((r) => sock.listen(sockPath, () => r()));
    // The holder's seat is this test process, listening on its own socket.
    fs.writeFileSync(path.join(sessions, `${process.pid}.json`), JSON.stringify({ pid: process.pid, name: HOLDER, messagingSocketPath: sockPath }));
    for (const id of ["h1", "h2", "nobody"]) newAsk(root, { from: ASKER, to: id === "nobody" ? "domain:ghost" : HOLDER, id }, BODY);
    newAsk(root, { from: ASKER, to: "operator", id: "hop" }, BODY);
    newAsk(root, { from: ASKER, to: HOLDER, id: "hdone" }, BODY);
    await answerAsk(root, ASKER, "hdone", { answers: { GO: ["NO"] }, answeredBy: HOLDER }, { expectedRevision: 1, push: async () => ({ status: "delivered" as const }) });
    port = 30000 + Math.floor(Math.random() * 20000);
    const env: NodeJS.ProcessEnv = { ...process.env, ASK_SESSIONS_DIR: sessions, ASK_LINEAR_ENV: "/dev/null", ASK_APP_DIST: fakeDist(base) };
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
  afterAll(async () => {
    proc.kill();
    await new Promise((r) => sock.close(() => r(null)));
    fs.rmSync(base, { recursive: true, force: true });
  });

  it("wakes the holder: 200 with the record, the push reaches the seat's socket, and the file carries the wake", async () => {
    const r = await wake(ASKER, "h1");
    expect(r.status).toBe(200);
    const b = JSON.parse(r.body);
    expect(b).toMatchObject({ ref: `${ASKER}/h1`, target: HOLDER, wokenBy: "operator", delivery: { status: "delivered" } });
    expect(Date.parse(b.wakeAfter) - Date.parse(b.wokenAt)).toBe(WAKE_COOLDOWN_MS);
    await new Promise((res) => setTimeout(res, 100));
    expect(got.join("\n")).toContain(`operator woke you for ask ${ASKER}/h1`);
    const h = parseAskFile(fs.readFileSync(path.join(root, ASKER, "h1.md"), "utf8")).header;
    expect(h).toMatchObject({ wokenBy: "operator", wokenSeat: HOLDER, wakeDelivery: "delivered", revision: "1" });
  });

  it("refuses each arm with 409 and a stable code", async () => {
    const op = await wake(ASKER, "hop");
    expect(op.status).toBe(409);
    expect(JSON.parse(op.body)).toMatchObject({ code: "operator" });
    const done = await wake(ASKER, "hdone");
    expect(done.status).toBe(409);
    expect(JSON.parse(done.body)).toMatchObject({ code: "closed" });
    const none = await wake(ASKER, "nobody");
    expect(none.status).toBe(409);
    expect(JSON.parse(none.body)).toMatchObject({ code: "no-pane" });
    const cool = await wake(ASKER, "h1");
    expect(cool.status).toBe(409);
    const cb = JSON.parse(cool.body);
    expect(cb.code).toBe("cooldown");
    expect(Date.parse(cb.wakeAfter)).toBeGreaterThan(Date.now());
    for (const x of [op, done, none, cool]) expect(JSON.parse(x.body).error).toMatch(/\S/);
  });

  it("follows /api/answer's rule for who may act: token, JSON content type and this origin", async () => {
    expect((await wake(ASKER, "h2", { ...GOOD(), "x-ask-token": "wrong" })).status).toBe(403);
    expect((await wake(ASKER, "h2", { ...GOOD(), origin: "http://evil.example" })).status).toBe(403);
    expect((await wake(ASKER, "h2", { ...GOOD(), "content-type": "text/plain" })).status).toBe(415);
    expect((await req("GET", `/api/asks/${encodeURIComponent(ASKER)}/h2/wake`)).status).toBe(404);
    expect((await wake(ASKER, "missing")).status).toBe(404);
    expect((await wake("../x", "h2")).status).toBe(400);
    expect(parseAskFile(fs.readFileSync(path.join(root, ASKER, "h2.md"), "utf8")).header.wokenAt).toBeUndefined();
  });

  it("/api/asks rows carry the target, the wake record, wakeAfter and the blocking code", async () => {
    expect(await row("h1")).toMatchObject({ wakeTarget: HOLDER, wokenBy: "operator", wakeDelivery: "delivered", wakeBlocked: "cooldown" });
    expect(typeof (await row("h1")).wakeAfter).toBe("string");
    const free = await row("h2");
    expect(free).toMatchObject({ wakeTarget: HOLDER });
    expect(free.wakeBlocked).toBeUndefined();
    expect(await row("hop")).toMatchObject({ wakeTarget: "operator", wakeBlocked: "operator" });
    expect(await row("hdone")).toMatchObject({ wakeBlocked: "closed" });
    expect(await row("nobody")).toMatchObject({ wakeTarget: "domain:ghost", wakeBlocked: "no-pane" });
  });
});
