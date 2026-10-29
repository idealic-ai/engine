/**
 * Round 4 (a): /api/proofs, ported from the ASKDESIGN prototype. The proof store is a fake: an env
 * script and an `aws` on PATH that prints a listing. Nothing reads the live store.
 */
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { BUILD_ID_FILE, computeBuildId } from "../src/build-id.ts";

const TOKEN = "t0k3n-r4";
let base: string, port: number, proc: ChildProcess, fakeEnv: Record<string, string>;

const LISTING = {
  Contents: [
    { Key: "proofs/invizko/older-page-1a2b3c4d.html", LastModified: "2026-10-28T10:00:00.000Z", Size: 100 },
    { Key: "proofs/invizko/newest-page-9f8e7d6c.html", LastModified: "2026-10-29T20:00:00.000Z", Size: 200 },
    { Key: "proofs/invizko/assets/logo.html", LastModified: "2026-10-29T21:00:00.000Z", Size: 5 },
    { Key: "proofs/invizko/note.txt", LastModified: "2026-10-29T22:00:00.000Z", Size: 5 },
    { Key: "proofs/meta/board/index.html", LastModified: "2026-10-29T12:00:00.000Z", Size: 300 },
  ],
};

function fakeDist(b: string): string {
  const d = path.join(b, "dist");
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, "index.html"), "<!doctype html><html><head><title>ask-app</title></head><body></body></html>\n");
  fs.writeFileSync(path.join(d, BUILD_ID_FILE), `${computeBuildId()}\n`);
  return d;
}

beforeAll(async () => {
  base = fs.mkdtempSync(path.join("/tmp", "asksrv4-"));
  // The fake proof store: the env script the prove skill would source, and an aws that prints a listing.
  const bin = path.join(base, "bin");
  fs.mkdirSync(bin);
  fs.writeFileSync(path.join(base, "listing.json"), JSON.stringify(LISTING));
  // Each run of the fake aws leaves a line in spawns.log, and takes a moment, so overlapping requests overlap.
  fs.writeFileSync(path.join(bin, "aws"), `#!/bin/sh\necho run >> "${path.join(base, "spawns.log")}"\nsleep 0.4\ncat "${path.join(base, "listing.json")}"\n`, { mode: 0o755 });
  const envSh = path.join(base, "prove-env.sh");
  fs.writeFileSync(envSh, `PROVE_S3_ENDPOINT_URL=http://127.0.0.1:1\nPROVE_S3_PUBLIC_URL=http://127.0.0.1:1\nPROVE_S3_BUCKET=proofs\nPROVE_S3_PREFIX=proofs\nENDPOINT_ARG=()\nPROFILE_ARG=()\n`);
  fakeEnv = { ASK_PROVE_ENV_SH: envSh, PATH: `${bin}:${process.env.PATH}` };
  port = 30000 + Math.floor(Math.random() * 20000);
  const env: NodeJS.ProcessEnv = { ...process.env, ...fakeEnv, ASK_SESSIONS_DIR: path.join(base, "s"), ASK_LINEAR_ENV: "/dev/null", ASK_APP_DIST: fakeDist(base) };
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

describe("(a) /api/proofs", () => {
  it("lists the store's .html pages newest first, skipping assets and non-pages, with public URLs", async () => {
    const r = await req("/api/proofs?fresh", { headers: { "x-ask-token": TOKEN } });
    expect(r.status).toBe(200);
    const j = JSON.parse(r.body);
    expect(j.ok).toBe(true);
    expect(j.bucket).toBe("proofs");
    expect(j.proofs.map((p: { key: string }) => p.key)).toEqual([
      "proofs/invizko/newest-page-9f8e7d6c.html",
      "proofs/meta/board/index.html",
      "proofs/invizko/older-page-1a2b3c4d.html",
    ]);
    expect(j.proofs[0]).toMatchObject({ owner: "invizko", slug: "newest-page-9f8e7d6c.html", title: "newest page", url: "http://127.0.0.1:1/proofs/proofs/invizko/newest-page-9f8e7d6c.html" });
    // An index.html page is named by its folder.
    expect(j.proofs[1]).toMatchObject({ owner: "meta", slug: "board" });
    expect(j.total).toBe(3);
  });

  it("refuses a foreign Host like every route", async () => {
    const r = await new Promise<number>((resolve, reject) => {
      const q = http.request({ host: "127.0.0.1", port, path: "/api/proofs", headers: { host: "evil.example" } }, (res) => resolve(res.statusCode!));
      q.on("error", reject);
      q.end();
    });
    expect(r).toBe(403);
  });
});

describe("SF-6: /api/proofs is gated like /api/broadcasts", () => {
  const spawns = () => (fs.existsSync(path.join(base, "spawns.log")) ? fs.readFileSync(path.join(base, "spawns.log"), "utf8").split("\n").filter(Boolean).length : 0);

  it("refuses a request with no token or a wrong one, and spawns nothing for it", async () => {
    const before = spawns();
    expect((await req("/api/proofs?fresh")).status).toBe(403);
    expect((await req("/api/proofs?fresh", { headers: { "x-ask-token": "nope" } })).status).toBe(403);
    expect(spawns()).toBe(before);
  });

  it("answers GET only: a POST, even with the token, is no such endpoint", async () => {
    const before = spawns();
    const r = await req("/api/proofs?fresh", { method: "POST", headers: { "x-ask-token": TOKEN, "content-type": "text/plain", origin: "https://evil.example" } });
    expect(r.status).toBe(404);
    expect(spawns()).toBe(before);
  });

  it("refuses a foreign Origin even with the token", async () => {
    const r = await req("/api/proofs?fresh", { headers: { "x-ask-token": TOKEN, origin: "https://evil.example" } });
    expect(r.status).toBe(403);
    expect((await req("/api/proofs", { headers: { "x-ask-token": TOKEN, origin: `http://127.0.0.1:${port}` } })).status).toBe(200);
  });

  it("?fresh joins a listing already running: five at once spawn one", async () => {
    const before = spawns();
    const rs = await Promise.all(Array.from({ length: 5 }, () => req("/api/proofs?fresh", { headers: { "x-ask-token": TOKEN } })));
    expect(rs.map((r) => r.status)).toEqual([200, 200, 200, 200, 200]);
    expect(spawns() - before).toBe(1);
  });
});

describe("NIT-B1: a failed listing names no path", () => {
  it("reports a fixed message with the exit code, never the env script's path", async () => {
    const dir = fs.mkdtempSync(path.join("/tmp", "askproofs-"));
    const envSh = path.join(dir, "secret-place-env.sh");
    fs.writeFileSync(envSh, "exit 1\n");
    const saved = process.env.ASK_PROVE_ENV_SH;
    process.env.ASK_PROVE_ENV_SH = envSh;
    try {
      vi.resetModules();
      const { listProofs } = await import("../src/lib/proofs.ts");
      const out = await listProofs(true);
      expect(out.ok).toBe(false);
      expect(out.error).toMatch(/^proof store not reachable \(/);
      expect(JSON.stringify(out)).not.toContain(dir);
      expect(JSON.stringify(out)).not.toContain("secret-place");
    } finally {
      if (saved === undefined) delete process.env.ASK_PROVE_ENV_SH;
      else process.env.ASK_PROVE_ENV_SH = saved;
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
});
