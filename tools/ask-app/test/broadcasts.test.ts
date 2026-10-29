/**
 * Round 4 (b): the read-only /api/broadcasts. Broadcasts live in a temp dir named by BROADCAST_DIR;
 * nothing reads the live store, and the test checks that nothing in that dir is written.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { BUILD_ID_FILE, computeBuildId } from "../src/build-id.ts";
import { listBroadcasts, parseBroadcast } from "../src/lib/broadcasts.ts";

const TOKEN = "t0k3n-r4b";
let base: string, port: number, proc: ChildProcess, bdir: string;

const BCAST = (id: string, at: string, sticky: string, expires: string, text: string) => `# Broadcast ${id}

id: ${id}
from: manager:director
sent-by: manager:director
at: ${at}
scope: all
sticky: ${sticky}
expires: ${expires}
audience: meta:utils idealic:ui domain:storage

## Text

${text}

## Delivery

delivered meta:utils pid=1
delivered idealic:ui pid=2
`;

function fakeDist(b: string): string {
  const d = path.join(b, "dist");
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, "index.html"), "<!doctype html><html><head><title>ask-app</title></head><body></body></html>\n");
  fs.writeFileSync(path.join(d, BUILD_ID_FILE), `${computeBuildId()}\n`);
  return d;
}

/** Every file under a dir with its mtime and size: the "nothing was written" control. */
function snapshot(dir: string): string {
  const walk = (d: string): string[] =>
    fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => {
      const p = path.join(d, e.name);
      const st = fs.statSync(p);
      return e.isDirectory() ? [`${p}/ ${st.mtimeMs}`, ...walk(p)] : [`${p} ${st.mtimeMs} ${st.size}`];
    });
  return walk(dir).sort().join("\n");
}

beforeAll(async () => {
  base = fs.mkdtempSync(path.join("/tmp", "asksrv4-"));
  // Broadcasts: one sticky, one expired, one expiring tomorrow, with acks.
  bdir = path.join(base, "broadcasts");
  fs.mkdirSync(bdir);
  fs.writeFileSync(path.join(bdir, "hold.md"), BCAST("hold", "2026-10-29T13:33:32Z", "yes", "-", "Hold: do not run `engine ask serve`."));
  fs.writeFileSync(path.join(bdir, "old.md"), BCAST("old", "2026-10-27T09:00:00Z", "no", "2026-10-28T00:00:00Z", "An old notice."));
  fs.writeFileSync(path.join(bdir, "soon.md"), BCAST("soon", "2026-10-29T20:00:00Z", "no", "2999-01-01T00:00:00Z", "Still in force.\n\nSecond paragraph."));
  fs.mkdirSync(path.join(bdir, "hold.acks.d"));
  fs.writeFileSync(path.join(bdir, "hold.acks.d", "meta:utils"), "meta:utils\t2026-10-29T13:34:00Z\n");
  fs.writeFileSync(path.join(bdir, "hold.acks.d", "idealic:ui"), "idealic:ui\t2026-10-29T13:35:00Z\n");

  port = 30000 + Math.floor(Math.random() * 20000);
  const env: NodeJS.ProcessEnv = { ...process.env, BROADCAST_DIR: bdir, ASK_SESSIONS_DIR: path.join(base, "s"), ASK_LINEAR_ENV: "/dev/null", ASK_APP_DIST: fakeDist(base) };
  delete env.LINEAR_API_KEY;
  proc = spawn(process.execPath, ["--no-warnings", "src/server.ts", "--root", path.join(base, "asks"), "--port", String(port), "--token", TOKEN], { env, stdio: "ignore" });
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

function req(p: string, opts: { method?: string; headers?: Record<string, string> } = {}): Promise<{ status: number; body: string }> {
  return new Promise((resolve, reject) => {
    const r = http.request({ host: "127.0.0.1", port, path: p, method: opts.method ?? "GET", headers: { host: `127.0.0.1:${port}`, ...opts.headers } }, (res) => {
      let b = "";
      res.on("data", (d) => (b += d));
      res.on("end", () => resolve({ status: res.statusCode!, body: b }));
    });
    r.on("error", reject);
    r.end();
  });
}

describe("(b) /api/broadcasts", () => {
  it("needs the page's token", async () => {
    expect((await req("/api/broadcasts")).status).toBe(403);
    expect((await req("/api/broadcasts", { headers: { "x-ask-token": "wrong" } })).status).toBe(403);
  });

  it("lists broadcasts newest first with text, audience, acks, sticky, expiry and in force; and writes nothing", async () => {
    const before = snapshot(bdir);
    const r = await req("/api/broadcasts", { headers: { "x-ask-token": TOKEN } });
    expect(r.status).toBe(200);
    const list = JSON.parse(r.body).broadcasts as { id: string; text: string; audience: string[]; acks: string[]; sticky: boolean; expires: string; inForce: boolean; from: string; at: string }[];
    expect(list.map((b) => b.id)).toEqual(["soon", "hold", "old"]);
    const hold = list.find((b) => b.id === "hold")!;
    expect(hold).toMatchObject({ from: "manager:director", at: "2026-10-29T13:33:32Z", sticky: true, expires: "", inForce: true, acks: ["idealic:ui", "meta:utils"] });
    expect(hold.audience).toEqual(["meta:utils", "idealic:ui", "domain:storage"]);
    expect(hold.text).toBe("Hold: do not run `engine ask serve`.");
    expect(hold.text).not.toContain("delivered");
    expect(list.find((b) => b.id === "soon")).toMatchObject({ inForce: true, text: "Still in force.\n\nSecond paragraph.", acks: [] });
    expect(list.find((b) => b.id === "old")).toMatchObject({ inForce: false, sticky: false });
    expect(snapshot(bdir)).toBe(before);
  });

  it("accepts no writes", async () => {
    for (const method of ["POST", "PUT", "DELETE"]) {
      const r = await req("/api/broadcasts", { method, headers: { "x-ask-token": TOKEN, "content-type": "application/json", origin: `http://127.0.0.1:${port}` } });
      expect(r.status).toBe(404);
    }
  });

  it("a missing directory is an empty list; the parser reads one file on its own", () => {
    expect(listBroadcasts(path.join(base, "nope"))).toEqual([]);
    const b = parseBroadcast("x", BCAST("x", "2026-10-29T00:00:00Z", "no", "2026-10-30T00:00:00Z", "T"), [], Date.parse("2026-10-29T12:00:00Z"));
    expect(b.inForce).toBe(true);
    expect(parseBroadcast("x", BCAST("x", "2026-10-29T00:00:00Z", "no", "2026-10-30T00:00:00Z", "T"), [], Date.parse("2026-10-31T00:00:00Z")).inForce).toBe(false);
  });
});

describe("client paths are served the page (the URL is the app's state)", () => {
  it("/a/…, /proofs, /proofs/<key>, /broadcasts and /broadcasts/<id> all get index.html with the token", async () => {
    for (const p of ["/a/manager:domain/opforks-1029", "/proofs", "/proofs/proofs/invizko/x-1a2b3c4d.html?pane=off", "/broadcasts", "/broadcasts/ask-serve-hold#F2"]) {
      const r = await req(p);
      expect(r.status, p).toBe(200);
      expect(r.body, p).toContain(`<meta name="ask-token" content="${TOKEN}">`);
    }
  });
});
