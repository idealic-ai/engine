/**
 * NOTIFYQ: no-action ask notices are queued in the broadcast queue (IDE-352) as one digest per ask,
 * never pushed; notices that ask for action still push live; the drain shows a digest once.
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { beforeEach, describe, expect, it } from "vitest";
import { NOTICE_KEEP_MS, isAskNotice, queueNotice, recordEvents } from "../src/lib/notice-queue.ts";
import { listBroadcasts } from "../src/lib/broadcasts.ts";
import { broadcastSource } from "../src/search/sources.ts";
import { answerAsk, attachPanel, newAsk, reviseAsk, supersedeAsk, withdrawAsk } from "../src/lib/store.ts";

const ENGINE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const ASKER = "manager:docs";
const HOLDER = "app:ask";
const RUNNER = "meta:utils";
const URL1 = "http://127.0.0.1:9440/proofs/proofs/u/council-abc.html";
const FORKS = ["Q8", "Q10", "Q11", "Q12", "Q13", "Q14", "Q16"];
const fork = (k: string) => `## ¶ASK_${k}: Choose one: Outline question ${k}?\nContext: part of the docs outline.\n- [ ] [A] Keep it\n  Keeps the outline.\n- [ ] [B] Cut it\n  Cuts the section.\n`;
const BODY = FORKS.map(fork).join("\n");

let root: string;
let dir: string;
let pushes: { seat: string; content: string }[];
const push = async (seat: string, content: string) => (pushes.push({ seat, content }), { status: "delivered" as const });
const queued = (seat: string) => {
  try {
    return fs.readdirSync(path.join(dir, "queued", seat.toLowerCase())).filter((n) => !n.startsWith("."));
  } catch {
    return [];
  }
};
const record = (id: string) => fs.readFileSync(path.join(dir, `${id}.md`), "utf8");

beforeEach(() => {
  root = fs.mkdtempSync(path.join(os.tmpdir(), "notifyq-asks-"));
  dir = fs.mkdtempSync(path.join(os.tmpdir(), "notifyq-bc-"));
  pushes = [];
  newAsk(root, { from: ASKER, to: HOLDER, id: "outline" }, BODY);
});

describe("a council backfill over seven forks of one ask", () => {
  it("queues one digest for the asker and pushes nothing", async () => {
    for (const k of FORKS) {
      const r = await attachPanel(root, { seat: ASKER, id: "outline" }, { by: RUNNER, fork: k, panel: [{ lens: "Editor", pick: "A", why: "keeps it" }], council: URL1, push, noticeDir: dir });
      expect(r.pushes).toHaveLength(1);
      expect(r.pushes[0].delivery.status).toBe("queued");
    }
    expect(pushes).toEqual([]);
    const q = queued(ASKER);
    expect(q).toHaveLength(1);
    const text = record(q[0]);
    expect(recordEvents(text)).toHaveLength(7);
    expect(text).toMatch(/^kind: ask-notice$/m);
    expect(text).toMatch(/^tier: note$/m);
    expect(text).toContain(`[ask-notices] ${ASKER}/outline: 7 panels attached on forks ${FORKS.join(", ")} (by ${RUNNER}). No action needed`);
    expect(text).toMatch(/^queued manager:docs /m);
    // S1/S4: complete at creation, sent by ask-app, the actor in the body.
    expect(text).toMatch(/^done: rc=0 delivered=0 undelivered=0 queued=1 at /m);
    expect(text).toMatch(/^from: ask-app$/m);
    expect(text).toContain(`panel on fork Q8 from ${RUNNER}`);
  });
});

describe("no-action notices to a seat", () => {
  it("withdraw: the holder's notice is queued, not pushed", async () => {
    const r = await withdrawAsk(root, { seat: ASKER, id: "outline" }, { by: ASKER, reason: "moot", push, noticeDir: dir });
    expect(pushes).toEqual([]);
    expect(r.pushes.map((p) => [p.seat, p.delivery.status])).toEqual([[HOLDER, "queued"]]);
    expect(record(queued(HOLDER)[0])).toContain("withdrawn by manager:docs via the ask CLI: moot");
  });
  it("revise then supersede of one ask collapse into one digest line for the holder", async () => {
    await reviseAsk(root, ASKER, "outline", { why: "sharper" }, undefined, { by: ASKER, push, noticeDir: dir });
    newAsk(root, { from: ASKER, to: HOLDER, id: "outline2" }, BODY);
    await supersedeAsk(root, { seat: ASKER, id: "outline" }, { seat: ASKER, id: "outline2" }, { by: ASKER, push, noticeDir: dir });
    expect(pushes).toEqual([]);
    const q = queued(HOLDER);
    expect(q).toHaveLength(1);
    const first = record(q[0]).split("## Text\n\n")[1].split("\n")[0];
    expect(first).toMatch(/revised by manager:docs to revision 2 .*; superseded by manager:docs\/outline2 \(manager:docs\): answer manager:docs\/outline2 instead/);
    // S2: a superseded digest points at the replacement and never says "no action".
    expect(first).toContain("Answer the replacement named above; do not reply to or ack this notice.");
    expect(first).not.toContain("No action needed");
  });
  it("never queues for the operator", async () => {
    expect(await queueNotice("operator", { ref: "a/b", file: "/x", kind: "panel", by: RUNNER, fork: "Q1", detail: "d" }, { noticeDir: dir })).toMatchObject({ status: "undelivered" });
    expect(fs.existsSync(path.join(dir, "queued", "operator"))).toBe(false);
  });
  it("a drained digest is not merged into: the next notice starts a new one", async () => {
    const a = await queueNotice(HOLDER, { ref: "s/i", file: "/f", kind: "revised", by: ASKER, detail: "one" }, { noticeDir: dir });
    fs.rmSync(path.join(dir, "queued", HOLDER, (a as { id: string }).id)); // the drain claimed it
    const b = await queueNotice(HOLDER, { ref: "s/i", file: "/f", kind: "revised", by: ASKER, detail: "two" }, { noticeDir: dir });
    expect(b).toMatchObject({ status: "queued", merged: false });
    expect((b as { id: string }).id).not.toBe((a as { id: string }).id);
    expect(recordEvents(record((b as { id: string }).id))).toHaveLength(1);
  });
});

describe("where a notice may land (M1, M-R1)", () => {
  it("with BROADCAST_DIR unset, the queue is `broadcasts` beside the ask root, never under HOME", async () => {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), "notifyq-home-"));
    const saved = { HOME: process.env.HOME, BROADCAST_DIR: process.env.BROADCAST_DIR };
    process.env.HOME = home;
    delete process.env.BROADCAST_DIR;
    try {
      const r = await withdrawAsk(root, { seat: ASKER, id: "outline" }, { by: ASKER, reason: "moot", push });
      expect(r.pushes[0].delivery.status).toBe("queued");
      expect(fs.readdirSync(path.join(path.dirname(root), "broadcasts", "queued", HOLDER))).toHaveLength(1);
      expect(fs.existsSync(path.join(home, ".claude"))).toBe(false);
    } finally {
      process.env.HOME = saved.HOME;
      if (saved.BROADCAST_DIR === undefined) delete process.env.BROADCAST_DIR;
      else process.env.BROADCAST_DIR = saved.BROADCAST_DIR;
    }
    expect(pushes).toEqual([]);
  });
  it("queueNotice has no default directory: without one it queues nothing", async () => {
    expect(await queueNotice(HOLDER, { ref: "a/b", file: "/x", kind: "revised", by: ASKER, detail: "d" }, {} as never)).toMatchObject({ status: "undelivered" });
  });
  it("no source file under src/ names an operator, beyond the one pre-existing default ask root", () => {
    const src = path.join(path.dirname(fileURLToPath(import.meta.url)), "../src");
    const hits: string[] = [];
    const walk = (d: string) => {
      for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const f = path.join(d, e.name);
        if (e.isDirectory()) walk(f);
        else if (/\.(ts|tsx|css|html)$/.test(e.name)) {
          fs.readFileSync(f, "utf8").split("\n").forEach((l, i) => {
            if (/yarik/.test(l)) hits.push(`${path.relative(src, f)}:${i + 1}: ${l.trim()}`);
          });
        }
      }
    };
    walk(src);
    // store.ts's defaultAskRoot predates NOTIFYQ (it is main's); it is the only line allowed, and it is pinned exactly.
    expect(hits).toEqual([expect.stringMatching(/^lib\/store\.ts:\d+: process\.env\.ASK_ROOT \|\| path\.join\(os\.homedir\(\), "\.claude", "data", "yarik", "asks"\);$/)]);
  });
});

describe("the merge and the drain do not race (N2)", () => {
  it("a merge holds the entry while it rewrites; a drained digest's delivered line is never overwritten", async () => {
    const a = (await queueNotice(HOLDER, { ref: "s/i", file: "/f", kind: "revised", by: ASKER, detail: "one" }, { noticeDir: dir })) as { id: string; record: string };
    // While held, the entry is a dotfile the drain skips; it is back in place after the merge.
    const b = await queueNotice(HOLDER, { ref: "s/i", file: "/f", kind: "revised", by: ASKER, detail: "two" }, { noticeDir: dir });
    expect(b).toMatchObject({ status: "queued", merged: true, id: a.id });
    expect(fs.readdirSync(path.join(dir, "queued", HOLDER))).toEqual([a.id]);
    // The drain shows it: entry gone, delivered line appended. The next notice must not touch that record.
    fs.rmSync(path.join(dir, "queued", HOLDER, a.id));
    fs.appendFileSync(a.record, `delivered ${HOLDER} at-wake ${new Date().toISOString()} via=queue\n`);
    const before = fs.readFileSync(a.record, "utf8");
    const c = await queueNotice(HOLDER, { ref: "s/i", file: "/f", kind: "revised", by: ASKER, detail: "three" }, { noticeDir: dir });
    expect(c).toMatchObject({ status: "queued", merged: false });
    expect(fs.readFileSync(a.record, "utf8")).toBe(before);
  });
  it("a held entry left by a process that died is put back and shown by the drain", async () => {
    const q = (await queueNotice(ASKER, { ref: `${ASKER}/outline`, file: "/f", kind: "revised", by: HOLDER, detail: "held" }, { noticeDir: dir })) as { id: string };
    const qd = path.join(dir, "queued", ASKER);
    fs.renameSync(path.join(qd, q.id), path.join(qd, `.${q.id}.hold.999999`)); // pid 999999: not alive
    const live = path.join(dir, "live.txt");
    fs.writeFileSync(live, `manager:director %1 -\n${ASKER} %4 manager:director\n`);
    const env: Record<string, string | undefined> = { ...process.env, HOP_LIVE_PANES: live, TMUX_PANE: "%4", BROADCAST_DIR: dir, BROADCAST_LIB: path.join(ENGINE, "scripts/lib.sh") };
    for (const k of ["FLEET_PANE", "FLEET_PARENT", "TMUX", "HOP_TMUX_SOCKET", "FLEET_TMUX_SOCKET", "FLEET_LIVE_PANES"]) delete env[k];
    // `pending --queued` (the prompt hook) exits at its fast path when only a dotfile is left, so the
    // restore is the full `pending` that SessionStart runs; broadcast.sh treats its own dead holds the same way.
    const quick = spawnSync("bash", [path.join(ENGINE, "scripts/broadcast.sh"), "pending", "--queued"], { env, encoding: "utf8" });
    expect(quick.stdout).toBe("");
    const out = spawnSync("bash", [path.join(ENGINE, "scripts/broadcast.sh"), "pending"], { env, encoding: "utf8" });
    expect(out.stdout).toContain(`[ask-notices] ${ASKER}/outline: held`);
  }, 60_000);
  it("prunes a seat's digests delivered more than a day ago and no longer queued", async () => {
    const a = (await queueNotice(HOLDER, { ref: "s/old", file: "/f", kind: "revised", by: ASKER, detail: "old", }, { noticeDir: dir, now: "2026-11-01T00:00:00.000Z" })) as { id: string; record: string };
    fs.rmSync(path.join(dir, "queued", HOLDER, a.id));
    fs.appendFileSync(a.record, `delivered ${HOLDER} at-wake 2026-11-01T00:01:00Z via=queue\n`);
    const later = new Date(Date.parse("2026-11-01T00:01:00Z") + NOTICE_KEEP_MS + 1000).toISOString();
    await queueNotice(HOLDER, { ref: "s/new", file: "/f", kind: "revised", by: ASKER, detail: "new" }, { noticeDir: dir, now: later });
    expect(fs.existsSync(a.record)).toBe(false);
  });
});

describe("readers that skip digests (S3)", () => {
  it("/api/broadcasts and the search index both skip ask-notice records", async () => {
    await queueNotice(HOLDER, { ref: "s/i", file: "/f", kind: "revised", by: ASKER, detail: "one" }, { noticeDir: dir });
    const rec = fs.readdirSync(dir).find((n) => n.endsWith(".md"))!;
    expect(isAskNotice(fs.readFileSync(path.join(dir, rec), "utf8"))).toBe(true);
    expect(listBroadcasts(dir)).toEqual([]);
    const listed = await broadcastSource(root, dir).list();
    expect(listed.items).toEqual([]);
  });
});

describe("a notice that asks for action", () => {
  it("an answer still pushes live and queues nothing", async () => {
    await answerAsk(root, ASKER, "outline", { answers: { Q8: ["A"] }, answeredBy: HOLDER }, { expectedRevision: 1, push } as never);
    expect(pushes.map((p) => p.seat)).toEqual([ASKER]);
    expect(pushes[0].content).toMatch(/^\[ask-answer\]/);
    expect(fs.existsSync(path.join(dir, "queued"))).toBe(false);
  });
});

describe("the drain (scripts/broadcast.sh pending --queued, as the prompt hook runs it)", () => {
  it("shows the digest once, with no ack line, and marks it delivered", async () => {
    for (const k of FORKS.slice(0, 3)) {
      await attachPanel(root, { seat: ASKER, id: "outline" }, { by: RUNNER, fork: k, panel: [{ lens: "Editor", pick: "A", why: "keeps it" }], council: URL1, push, noticeDir: dir });
    }
    const live = path.join(dir, "live.txt");
    fs.writeFileSync(live, `manager:director %1 -\n${ASKER} %4 manager:director\n`);
    const env = { ...process.env, HOP_LIVE_PANES: live, TMUX_PANE: "%4", BROADCAST_DIR: dir, BROADCAST_LIB: path.join(ENGINE, "scripts/lib.sh") };
    for (const k of ["FLEET_PANE", "FLEET_PARENT", "TMUX", "HOP_TMUX_SOCKET", "FLEET_TMUX_SOCKET", "FLEET_LIVE_PANES"]) delete (env as Record<string, string | undefined>)[k];
    const drain = () => spawnSync("bash", [path.join(ENGINE, "scripts/broadcast.sh"), "pending", "--queued"], { env, encoding: "utf8" });
    const one = drain();
    expect(one.status).toBe(0);
    expect(one.stdout.match(/\[ask-notices\]/g)).toHaveLength(1);
    expect(one.stdout).toContain(`3 panels attached on forks Q8, Q10, Q11`);
    expect(one.stdout).toContain("(no action needed: nothing to answer and nothing to ack)");
    expect(one.stdout).not.toContain("engine broadcast ack");
    expect(queued(ASKER)).toEqual([]);
    const id = fs.readdirSync(dir).find((n) => n.startsWith("ask-notice-"))!.replace(/\.md$/, "");
    expect(record(id)).toMatch(/^delivered manager:docs at-wake .* via=queue$/m);
    const two = drain();
    expect(two.status).toBe(0);
    expect(two.stdout).toBe("");
    // S1: status reads it complete, and resend refuses it rather than pushing it live.
    const bc = (...a: string[]) => spawnSync("bash", [path.join(ENGINE, "scripts/broadcast.sh"), ...a], { env, encoding: "utf8" });
    const st = bc("status", id);
    expect(st.stdout).toMatch(/complete: yes \(done: rc=0 /);
    const rs = bc("resend", id);
    expect(rs.status).toBe(2);
    expect(rs.stderr).toContain("is an ask-app no-action digest (kind: ask-notice): it is never resent");
    expect(record(id)).not.toContain("resend:");
  }, 60_000);
});
