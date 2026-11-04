/**
 * TELL: /api/comms, the feed of tells, broadcasts and asks for the Comms tab. Records are written
 * in the exact shape scripts/broadcast.sh writes (see scripts/tests/test-tell.sh for the writer's
 * own tests); everything lives in temp dirs, and the route is checked to write nothing.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { BUILD_ID_FILE, computeBuildId } from "../src/build-id.ts";
import { listComms, listRecords, parseRecord } from "../src/lib/comms.ts";

const TOKEN = "t0k3n-comms";
let base: string, port: number, proc: ChildProcess, bdir: string, askRoot: string;

const REC = (o: { id: string; from: string; at: string; audience: string; extra?: string; text: string; delivery: string; tail?: string }) => `# Broadcast ${o.id}

id: ${o.id}
from: ${o.from}
sent-by: ${o.from}
at: ${o.at}
scope: to:${o.audience.replace(/ /g, ",")}
sticky: no
expires: -
audience: ${o.audience}
${o.extra ?? ""}
## Text

${o.text}

## Delivery

${o.delivery}
${o.tail ?? ""}`;

function write(dir: string, id: string, body: string, acks: string[] = []) {
  fs.writeFileSync(path.join(dir, `${id}.md`), body);
  if (acks.length) {
    fs.mkdirSync(path.join(dir, `${id}.acks.d`), { recursive: true });
    for (const a of acks) fs.writeFileSync(path.join(dir, `${id}.acks.d`, a.toLowerCase()), `${a}\t2026-11-04T10:00:00Z\n`);
  }
}

function fakeDist(b: string): string {
  const d = path.join(b, "dist");
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, "index.html"), "<!doctype html><html><head><title>ask-app</title></head><body></body></html>\n");
  fs.writeFileSync(path.join(d, BUILD_ID_FILE), `${computeBuildId()}\n`);
  return d;
}

function snapshot(dir: string): string {
  const walk = (d: string): string[] =>
    fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => {
      const p = path.join(d, e.name);
      const st = fs.statSync(p);
      return e.isDirectory() ? [`${p}/ ${st.mtimeMs}`, ...walk(p)] : [`${p} ${st.mtimeMs} ${st.size}`];
    });
  return walk(dir).sort().join("\n");
}

function fixtures() {
  // An align tell, its managers' notice, a withdrawn lazy tell, a plain wake broadcast, an acked note.
  write(bdir, "a1", REC({ id: "a1", from: "app:ask", at: "2026-11-04T10:05:00Z", audience: "domain:stats",
    extra: "message: tell\ntier: align\nsubject: stats schema moved\nnotice: a1.align\n", text: "stats schema moved\nsee the commit",
    delivery: "queued domain:stats pid=2007 idle=30m via=status\ndone: rc=0 delivered=0 undelivered=0 queued=1 at 2026-11-04T10:05:01Z" }));
  write(bdir, "a1.align", REC({ id: "a1.align", from: "app:ask", at: "2026-11-04T10:05:01Z", audience: "manager:app manager:domain",
    extra: "message: tell\ntier: note\nsubject: these two are talking: stats schema moved\nnotice-of: a1\n", text: "app:ask is telling domain:stats directly",
    delivery: "queued manager:app pid=2002 tier=note\nqueued manager:domain pid=2003 tier=note" }));
  write(bdir, "d1", REC({ id: "d1", from: "app:ask", at: "2026-11-04T09:00:00Z", audience: "app:ui",
    extra: "message: tell\ntier: lazy\nsubject: ignore me\n", text: "ignore me",
    delivery: "queued app:ui pid=2005 idle=60m via=status", tail: "\n## Withdrawn\n\nwithdrawn: by manager:app at 2026-11-04T09:01:00Z — sent to the wrong seat\n" }));
  write(bdir, "bw", REC({ id: "bw", from: "manager:director", at: "2026-11-03T12:00:00Z", audience: "app:ask app:ui",
    extra: "kind: wake\nwake-reason: operator: resume\n", text: "Resume.\n## Withdrawn\nwithdrawn: by nobody at x — a line in the text is not a withdrawal",
    delivery: "delivered app:ask pid=2004\nundelivered app:ui — no session" }));
  write(bdir, "n1", REC({ id: "n1", from: "manager:app", at: "2026-11-04T08:00:00Z", audience: "app:ask app:ui",
    extra: "message: tell\ntier: note\nsubject: lease is free\n", text: "lease is free",
    delivery: "queued app:ask pid=2004 tier=note\nqueued app:ui pid=2005 tier=note" }), ["app:ask", "app:ui"]);
  // One ask, withdrawn.
  fs.mkdirSync(path.join(askRoot, "app:ask"), { recursive: true });
  fs.writeFileSync(path.join(askRoot, "app:ask", "20261104-q1.md"), `---
id: 20261104-q1
to: manager:app
from: app:ask
topic: parser order
status: withdrawn
revision: 2
created: 2026-11-04T10:10:00.000Z
withdrawn-actor: app:ask
withdrawn-at: 2026-11-04T10:11:00.000Z
withdrawn-reason: moot
---

## Which parser goes first?

- [ ] [A] Ours
- [ ] [B] Theirs
`);
}

beforeAll(async () => {
  base = fs.mkdtempSync(path.join("/tmp", "askcomms-"));
  bdir = path.join(base, "broadcasts");
  askRoot = path.join(base, "asks");
  fs.mkdirSync(bdir);
  fs.mkdirSync(askRoot);
  fixtures();
  port = 30000 + Math.floor(Math.random() * 20000);
  const env: NodeJS.ProcessEnv = { ...process.env, BROADCAST_DIR: bdir, ASK_SESSIONS_DIR: path.join(base, "s"), ASK_LINEAR_ENV: "/dev/null", ASK_APP_DIST: fakeDist(base) };
  delete env.LINEAR_API_KEY;
  proc = spawn(process.execPath, ["--no-warnings", "src/server.ts", "--root", askRoot, "--port", String(port), "--token", TOKEN], { env, stdio: "ignore" });
  for (let i = 0; i < 100; i++) {
    try {
      if ((await req("/api/health")).status === 200) return;
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

function req(p: string, headers: Record<string, string> = {}): Promise<{ status: number; body: string }> {
  return new Promise((resolve, reject) => {
    const r = http.request({ host: "127.0.0.1", port, path: p, method: "GET", headers: { host: `127.0.0.1:${port}`, ...headers } }, (res) => {
      let b = "";
      res.on("data", (d) => (b += d));
      res.on("end", () => resolve({ status: res.statusCode!, body: b }));
    });
    r.on("error", reject);
    r.end();
  });
}

describe("comms rows from records", () => {
  it("reads a tell's tier, subject, notice link and per-seat state", () => {
    const rows = listRecords(bdir);
    const a1 = rows.find((r) => r.id === "a1")!;
    expect(a1).toMatchObject({ kind: "tell", tier: "align", subject: "stats schema moved", notice: "a1.align", noticeOf: null, state: "queued", to: ["domain:stats"] });
    expect(a1.seats).toEqual([{ seat: "domain:stats", state: "queued" }]);
    expect(rows.find((r) => r.id === "a1.align")).toMatchObject({ tier: "note", noticeOf: "a1", to: ["manager:app", "manager:domain"] });
  });

  it("reads a withdrawal from after the delivery log only", () => {
    const rows = listRecords(bdir);
    expect(rows.find((r) => r.id === "d1")).toMatchObject({ state: "withdrawn", withdrawn: { by: "manager:app", at: "2026-11-04T09:01:00Z", reason: "sent to the wrong seat" } });
    const bw = rows.find((r) => r.id === "bw")!;
    expect(bw.withdrawn).toBeNull(); // its text holds a Withdrawn heading and line (S4)
    expect(bw).toMatchObject({ kind: "broadcast", tier: "wake", state: "delivered", subject: "Resume." });
    expect(bw.seats).toEqual([{ seat: "app:ask", state: "delivered" }, { seat: "app:ui", state: "undelivered" }]);
  });

  it("marks a record read once every recipient acked it", () => {
    expect(listRecords(bdir).find((r) => r.id === "n1")).toMatchObject({ state: "read", tier: "note" });
  });

  it("a broadcast with no tier and no wake reads as lazy", () => {
    const r = parseRecord("x", REC({ id: "x", from: "a:b", at: "2026-11-01T00:00:00Z", audience: "c:d", text: "hi", delivery: "delivered c:d pid=1" }), [], "/x.md");
    expect(r).toMatchObject({ kind: "broadcast", tier: "lazy", state: "delivered" });
  });
});

describe("an ask withdrawn with no record of who (meta:utils 5)", () => {
  it("reads null fields, not empty strings", async () => {
    const { askRow } = await import("../src/lib/comms.ts");
    const r = askRow({ header: { id: "q9", from: "a:b", to: "c:d", status: "withdrawn" }, preamble: "", questions: [], history: [], seat: "a:b", file: "/x/q9.md", mtimeMs: 0 } as never);
    expect(r.withdrawn).toEqual({ by: null, at: null, reason: null });
  });
});

describe("listComms filters", () => {
  const asks = () => [] as never[];
  it("filters by seat across from, to and for, newest first", () => {
    const ids = listComms(asks(), { seat: "manager:domain" }, bdir).map((r) => r.id);
    expect(ids).toEqual(["a1.align"]);
    expect(listComms(asks(), { seat: "app:ui" }, bdir).map((r) => r.id)).toEqual(["d1", "n1", "bw"]);
  });
  it("filters by tier, kind and since, and bounds the count", () => {
    expect(listComms(asks(), { tier: "note" }, bdir).map((r) => r.id)).toEqual(["a1.align", "n1"]);
    expect(listComms(asks(), { kind: "broadcast" }, bdir).map((r) => r.id)).toEqual(["bw"]);
    expect(listComms(asks(), { since: "2026-11-04T09:30:00Z" }, bdir).map((r) => r.id)).toEqual(["a1.align", "a1"]);
    expect(listComms(asks(), { limit: 2 }, bdir)).toHaveLength(2);
  });
});

describe("GET /api/comms", () => {
  it("needs the page's token", async () => {
    expect((await req("/api/comms")).status).toBe(403);
    expect((await req("/api/comms", { "x-ask-token": "wrong" })).status).toBe(403);
  });

  it("returns tells, broadcasts and asks in one feed, newest first, and writes nothing", async () => {
    const before = snapshot(bdir) + snapshot(askRoot);
    const r = await req("/api/comms", { "x-ask-token": TOKEN });
    expect(r.status).toBe(200);
    const rows = JSON.parse(r.body).rows as { id: string; kind: string; state: string; withdrawn: unknown; ref: string; subject: string; tier: string }[];
    expect(rows.map((x) => x.id)).toEqual(["app:ask/20261104-q1", "a1.align", "a1", "d1", "n1", "bw"]);
    expect(rows[0]).toMatchObject({ kind: "ask", state: "withdrawn", tier: null, subject: "parser order", ref: "/a/app%3Aask/20261104-q1", withdrawn: { by: "app:ask", reason: "moot" } });
    expect(snapshot(bdir) + snapshot(askRoot)).toBe(before);
  });

  it("takes seat, tier, kind, since and limit", async () => {
    const q = async (s: string) => (JSON.parse((await req(`/api/comms?${s}`, { "x-ask-token": TOKEN })).body).rows as { id: string }[]).map((x) => x.id);
    expect(await q("seat=manager%3Aapp")).toEqual(["app:ask/20261104-q1", "a1.align", "n1"]);
    expect(await q("tier=align,wake")).toEqual(["a1", "bw"]);
    expect(await q("kind=ask")).toEqual(["app:ask/20261104-q1"]);
    expect(await q("since=2026-11-04T10:06:00Z")).toEqual(["app:ask/20261104-q1"]);
    expect(await q("limit=1")).toEqual(["app:ask/20261104-q1"]);
  });

  it("refuses a bad since, limit, kind, tier or id", async () => {
    expect((await req("/api/comms?since=yesterday", { "x-ask-token": TOKEN })).status).toBe(400);
    expect((await req("/api/comms?limit=0", { "x-ask-token": TOKEN })).status).toBe(400);
    expect((await req("/api/comms?kind=tells", { "x-ask-token": TOKEN })).status).toBe(400);
    expect((await req("/api/comms?tier=urgent", { "x-ask-token": TOKEN })).status).toBe(400);
    expect((await req("/api/comms?id=..%2Fx", { "x-ask-token": TOKEN })).status).toBe(400);
  });

  it("refuses a foreign Origin (N6)", async () => {
    expect((await req("/api/comms", { "x-ask-token": TOKEN, origin: "http://evil.example" })).status).toBe(403);
    expect((await req("/api/comms", { "x-ask-token": TOKEN, origin: `http://127.0.0.1:${port}` })).status).toBe(200);
  });

  it("looks rows up by id, past every other filter (meta:utils 2)", async () => {
    const q = async (s: string) => (JSON.parse((await req(`/api/comms?${s}`, { "x-ask-token": TOKEN })).body).rows as { id: string }[]).map((x) => x.id);
    expect(await q("seat=domain%3Astats&id=a1.align")).toEqual(["a1.align"]);
    expect(await q("id=a1,app%3Aask%2F20261104-q1")).toEqual(["app:ask/20261104-q1", "a1"]);
  });

  it("an ask has no tier, so a tier filter leaves it out (S7)", async () => {
    const rows = JSON.parse((await req("/api/comms?tier=lazy,note,align,escalate,wake", { "x-ask-token": TOKEN })).body).rows as { kind: string }[];
    expect(rows.some((r) => r.kind === "ask")).toBe(false);
  });

  it("sends a comms event when a record lands, and none for queue churn (meta:utils 1)", async () => {
    const events: string[] = [];
    await new Promise<void>((resolve, reject) => {
      const r = http.request({ host: "127.0.0.1", port, path: "/api/events", headers: { host: `127.0.0.1:${port}` } }, (res) => {
        res.on("data", (d) => events.push(String(d)));
        setTimeout(() => {
          fs.mkdirSync(path.join(bdir, "queued", "app:ui"), { recursive: true });
          fs.writeFileSync(path.join(bdir, "queued", "app:ui", "zz"), "");
        }, 200);
        setTimeout(() => {
          const quiet = events.join("").includes("event: comms");
          write(bdir, "late", REC({ id: "late", from: "app:ui", at: "2026-11-04T11:00:00Z", audience: "app:ask", extra: "message: tell\ntier: lazy\nsubject: late\n", text: "late", delivery: "queued app:ask pid=2004 idle=1m" }));
          setTimeout(() => {
            r.destroy();
            try {
              expect(quiet).toBe(false);
              expect(events.join("")).toContain("event: comms");
              resolve();
            } catch (e) {
              reject(e);
            }
          }, 1800);
        }, 1600);
      });
      r.on("error", () => {});
      r.end();
    });
  });
});
