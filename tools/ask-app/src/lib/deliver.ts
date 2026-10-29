/**
 * Delivery adapter: push a message to a Claude Code session addressed by its SEAT NAME, over the
 * cross-session messaging socket. This is the one module that knows the protocol, so it is the one
 * to replace when the protocol changes or a supported channel appears.
 *
 * The protocol is undocumented. What follows was read out of the installed binary (2.1.312) and
 * the files it writes, not from documentation:
 *
 *  - Every live session writes `~/.claude/sessions/<pid>.json` holding `name` (the seat name, e.g.
 *    `manager:director`), `pid`, `updatedAt` and `messagingSocketPath` (`/tmp/cc-socks/<pid>.sock`).
 *    Files for dead pids linger, so the pid is checked for liveness.
 *  - The socket takes JSON lines. An optional first line `{"type":"auth","token":<peerToken>}`, then
 *    `{"type":"user","message":{"role":"user","content":"..."}}`. The binary's own startup log
 *    prints exactly this form. Auth is required only on Windows; it is sent when readable anyway.
 *  - The peer token is published at `~/.claude/sessions/<pid>.<sha256(socketPath)>.key`.
 *
 * "delivered" here means the socket accepted the bytes and closed cleanly. It does NOT prove the
 * agent read them; the build report records what was measured beyond that.
 */
import { createHash } from "node:crypto";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";

export type DeliveryResult = { status: "delivered" | "undelivered"; reason?: string; socketPath?: string };

export type DeliverOptions = {
  sessionsDir?: string;
  timeoutMs?: number;
  /** Test seam: open the connection. Defaults to net.createConnection on the seat's socket path. */
  connect?: (socketPath: string) => net.Socket;
};

const defaultSessionsDir = () => process.env.ASK_SESSIONS_DIR || path.join(os.homedir(), ".claude", "sessions");

function alive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return (e as NodeJS.ErrnoException).code === "EPERM";
  }
}

type Registry = { pid: number; name?: string; messagingSocketPath?: string; updatedAt?: number };

export type SeatLookup =
  | { kind: "found"; pid: number; socketPath: string }
  | { kind: "none" }
  | { kind: "ambiguous"; pids: number[] };

/**
 * The live sessions answering to `seat`, matched case-insensitively. More than one match (two
 * terminals on one seat, or `docs` beside `Docs`) is AMBIGUOUS and is never resolved by guessing:
 * a wrong-seat push reported as delivered is worse than an undelivered one the file still carries.
 */
export function lookupSeat(seat: string, opts: DeliverOptions = {}): SeatLookup {
  const dir = opts.sessionsDir ?? defaultSessionsDir();
  let files: string[];
  try {
    files = fs.readdirSync(dir).filter((f) => /^\d+\.json$/.test(f));
  } catch {
    return { kind: "none" };
  }
  const want = seat.toLowerCase();
  const hits: Registry[] = [];
  for (const f of files) {
    try {
      const r = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")) as Registry;
      if (r.name?.toLowerCase() === want && r.messagingSocketPath && alive(r.pid)) hits.push(r);
    } catch {
      // a half-written registry file is not a seat
    }
  }
  if (hits.length === 0) return { kind: "none" };
  if (hits.length > 1) return { kind: "ambiguous", pids: hits.map((h) => h.pid).sort((a, b) => a - b) };
  return { kind: "found", pid: hits[0].pid, socketPath: hits[0].messagingSocketPath! };
}

/** The single live session holding `seat`, or undefined when there is none or more than one. */
export function findSeatSocket(seat: string, opts: DeliverOptions = {}): { pid: number; socketPath: string } | undefined {
  const r = lookupSeat(seat, opts);
  return r.kind === "found" ? { pid: r.pid, socketPath: r.socketPath } : undefined;
}

function peerToken(dir: string, pid: number, socketPath: string): string | undefined {
  const name = `${pid}.${createHash("sha256").update(socketPath).digest("hex")}.key`;
  try {
    const t = JSON.parse(fs.readFileSync(path.join(dir, name), "utf8")).peerToken;
    return typeof t === "string" ? t : undefined;
  } catch {
    return undefined;
  }
}

export async function pushToSeat(seat: string, content: string, opts: DeliverOptions = {}): Promise<DeliveryResult> {
  const dir = opts.sessionsDir ?? defaultSessionsDir();
  const found = lookupSeat(seat, { ...opts, sessionsDir: dir });
  if (found.kind === "none") return { status: "undelivered", reason: `no live session named ${seat}` };
  if (found.kind === "ambiguous") {
    return { status: "undelivered", reason: `ambiguous seat ${seat}: live sessions ${found.pids.join(", ")} all match; not guessing` };
  }
  const target = found;
  const token = peerToken(dir, target.pid, target.socketPath);
  const lines =
    (token ? JSON.stringify({ type: "auth", token }) + "\n" : "") +
    JSON.stringify({ type: "user", message: { role: "user", content } }) + "\n";
  return new Promise<DeliveryResult>((resolve) => {
    let settled = false;
    const done = (r: DeliveryResult) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      sock.destroy();
      resolve({ ...r, socketPath: target.socketPath });
    };
    const sock = opts.connect ? opts.connect(target.socketPath) : net.createConnection({ path: target.socketPath });
    // A wall-clock bound on connect+write, not an idle timer: a seat that never accepts must not hang the answer.
    const timer = setTimeout(() => done({ status: "undelivered", reason: "socket timed out" }), opts.timeoutMs ?? 3000);
    sock.on("error", (e: NodeJS.ErrnoException) => done({ status: "undelivered", reason: `${e.code ?? "error"}: ${e.message}` }));
    sock.on("connect", () => {
      sock.end(lines, () => done({ status: "delivered" }));
    });
  });
}
