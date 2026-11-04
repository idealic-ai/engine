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
import { queueNotice, recordEvents } from "../src/lib/notice-queue.ts";
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
    expect(first).toMatch(/revised by manager:docs to revision 2 .*; superseded by manager:docs\/outline2/);
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
  }, 60_000);
});
