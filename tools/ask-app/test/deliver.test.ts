import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { createHash } from "node:crypto";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { findSeatSocket, pushToSeat } from "../src/lib/deliver.ts";

let dir: string;
let servers: net.Server[] = [];

beforeEach(() => {
  // Unix socket paths are capped near 104 bytes, so keep the fixture short.
  dir = fs.mkdtempSync(path.join("/tmp", "askt-"));
});
afterEach(async () => {
  await Promise.all(servers.map((s) => new Promise((r) => s.close(() => r(null)))));
  servers = [];
  fs.rmSync(dir, { recursive: true, force: true });
});

function registry(name: string, pid: number, sock: string, updatedAt = 1) {
  fs.writeFileSync(
    path.join(dir, `${pid}.json`),
    JSON.stringify({ pid, name, messagingSocketPath: sock, updatedAt }),
  );
}

function listen(sock: string): Promise<{ lines: () => string[] }> {
  const got: string[] = [];
  return new Promise((resolve) => {
    const srv = net.createServer((c) => {
      let buf = "";
      c.on("data", (d) => (buf += d.toString()));
      c.on("end", () => got.push(...buf.split("\n").filter(Boolean)));
    });
    servers.push(srv);
    srv.listen(sock, () => resolve({ lines: () => got }));
  });
}

describe("findSeatSocket", () => {
  it("maps a seat name to the live session's socket, case-insensitively", () => {
    registry("manager:Director", process.pid, path.join(dir, "a.sock"));
    expect(findSeatSocket("manager:director", { sessionsDir: dir })?.socketPath).toBe(
      path.join(dir, "a.sock"),
    );
  });

  it("skips a registry entry whose pid is dead", () => {
    registry("manager:director", 2 ** 22 + 12345, path.join(dir, "dead.sock"));
    expect(findSeatSocket("manager:director", { sessionsDir: dir })).toBeUndefined();
  });

  it("returns undefined for a seat nobody holds", () => {
    registry("manager:app", process.pid, path.join(dir, "a.sock"));
    expect(findSeatSocket("manager:director", { sessionsDir: dir })).toBeUndefined();
  });
});

describe("pushToSeat", () => {
  it("writes the auth line and then one user message line to the seat's socket", async () => {
    const sock = path.join(dir, "s.sock");
    const srv = await listen(sock);
    registry("idealic:kernel", process.pid, sock);
    const keyName = `${process.pid}.${createHash("sha256").update(sock).digest("hex")}.key`;
    fs.writeFileSync(path.join(dir, keyName), JSON.stringify({ peerToken: "tok123" }));

    const res = await pushToSeat("idealic:kernel", "hello there", { sessionsDir: dir });
    expect(res.status).toBe("delivered");
    await new Promise((r) => setTimeout(r, 50));
    const lines = srv.lines().map((l) => JSON.parse(l));
    expect(lines[0]).toEqual({ type: "auth", token: "tok123" });
    expect(lines[1]).toEqual({ type: "user", message: { role: "user", content: "hello there" } });
  });

  it("omits the auth line when no key file is readable", async () => {
    const sock = path.join(dir, "s.sock");
    const srv = await listen(sock);
    registry("idealic:kernel", process.pid, sock);
    const res = await pushToSeat("idealic:kernel", "hi", { sessionsDir: dir });
    expect(res.status).toBe("delivered");
    await new Promise((r) => setTimeout(r, 50));
    expect(srv.lines().map((l) => JSON.parse(l).type)).toEqual(["user"]);
  });

  it("reports undelivered with a reason when the seat is not found", async () => {
    const res = await pushToSeat("nobody:here", "hi", { sessionsDir: dir });
    expect(res.status).toBe("undelivered");
    expect(res.reason).toMatch(/no live session/);
  });

  it("reports undelivered when the socket refuses the connection", async () => {
    registry("idealic:kernel", process.pid, path.join(dir, "missing.sock"));
    const res = await pushToSeat("idealic:kernel", "hi", { sessionsDir: dir });
    expect(res.status).toBe("undelivered");
    expect(res.reason).toMatch(/ENOENT|ECONNREFUSED/);
  });
});

describe("ambiguous seats and timeouts", () => {
  it("refuses to push when two live sessions match the seat, even by case only", async () => {
    registry("docs", process.pid, path.join(dir, "a.sock"), 100);
    fs.writeFileSync(path.join(dir, "2.json"), JSON.stringify({ pid: process.ppid, name: "Docs", messagingSocketPath: path.join(dir, "b.sock"), updatedAt: 200 }));
    const res = await pushToSeat("docs", "hi", { sessionsDir: dir });
    expect(res.status).toBe("undelivered");
    expect(res.reason).toMatch(/ambiguous seat docs/);
    expect(res.reason).toContain(String(process.ppid));
  });

  it("reports undelivered when the connection never completes within timeoutMs", async () => {
    registry("idealic:kernel", process.pid, path.join(dir, "s.sock"));
    const { Duplex } = await import("node:stream");
    const never = () => new Duplex({ read() {}, write(_c, _e, cb) { cb(); } }) as unknown as net.Socket;
    const res = await pushToSeat("idealic:kernel", "hi", { sessionsDir: dir, timeoutMs: 50, connect: never });
    expect(res.status).toBe("undelivered");
    expect(res.reason).toMatch(/timed out/);
  });
});
