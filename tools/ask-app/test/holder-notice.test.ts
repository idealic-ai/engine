/**
 * AUTOWAKE (operator ruling ask-wakes-holder, 2026-11-04 ~10:02): "every new ask pushes a short
 * notice to its holder's session, waking it if idle; asks to you are never pushed."
 *
 * Library half: noticeHolder pushes one notice to the `to:` seat through the same push seam the
 * answer and wake tests use, never to `operator`, and records the outcome in the header
 * (newDelivery, newDeliverySeat, newDeliveryAt, newDeliveryNote) without moving the revision. A
 * forward notices the new holder; the reserved-decline pass-up already pushed, and records the same
 * fields. The stamps are store fields: `new` and `revise` refuse them.
 *
 * CLI half: `engine ask new` and `engine ask forward` against a fixture sessions dir — a real unix
 * socket this test listens on for the delivered arm, an empty registry for the failed arm. A failed
 * push never fails the command: the ask is filed, stdout is unchanged, stderr says why.
 */
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { answerAsk, forwardAsk, newAsk, renameSeat, reviseAsk } from "../src/lib/store.ts";
import { AskFormatError, parseAskFile, STAMP_FIELDS } from "../src/lib/format.ts";
import { holderNoticeMessage, noticeHolder, NOTICE_FIELDS } from "../src/lib/holder-notice.ts";
import { wakeView } from "../src/lib/wake.ts";

const BODY = "## ¶ASK_GO: Choose one: Ship it?\nContext: c\n- [ ] [YES] Yes\n  Picks YES.\n- [ ] [NO] No\n  Picks NO.\n";
const ASKER = "domain:security";
const HOLDER = "manager:domain";
const PARENT = "manager:director";
const CLI = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "src", "cli.ts");

type Pushed = { seat: string; content: string };

describe("noticeHolder (library)", () => {
  let base: string, root: string;
  let pushed: Pushed[];
  const push = async (seat: string, content: string) => {
    pushed.push({ seat, content });
    return { status: "delivered" as const };
  };
  const file = (id: string) => path.join(root, ASKER, `${id}.md`);
  const read = (id: string) => parseAskFile(fs.readFileSync(file(id), "utf8"));

  beforeEach(() => {
    base = fs.mkdtempSync(path.join("/tmp", "asks-notice-"));
    root = path.join(base, "asks");
    pushed = [];
  });
  afterEach(() => fs.rmSync(base, { recursive: true, force: true }));

  it("pushes one [ask-new] notice to the to: seat and records it without moving the revision", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "n1" }, BODY);
    const out = await noticeHolder(root, ASKER, "n1", { kind: "new", by: ASKER, push, now: "2026-11-04T10:00:00.000Z" });
    expect(out).toMatchObject({ seat: HOLDER, delivery: { status: "delivered" } });
    expect(pushed.map((p) => p.seat)).toEqual([HOLDER]);
    const msg = pushed[0].content;
    expect(msg.split("\n")[0]).toBe(`[ask-new] ${ASKER} asked you: ${ASKER}/n1 "Ship it?"`);
    expect(msg).toContain(`engine ask list --to ${HOLDER} --status open`);
    expect(msg).toContain(`engine ask read ${ASKER}/n1`);
    expect(msg).toContain(file("n1"));
    const h = read("n1").header;
    expect(h).toMatchObject({ newDelivery: "delivered", newDeliverySeat: HOLDER, newDeliveryAt: "2026-11-04T10:00:00.000Z", revision: "1", status: "open" });
    expect(h.newDeliveryNote).toBeUndefined();
  });

  it("pushes nothing for an ask addressed to the operator, and writes no record", async () => {
    newAsk(root, { from: ASKER, to: "operator", id: "op" }, BODY);
    const before = fs.readFileSync(file("op"), "utf8");
    const out = await noticeHolder(root, ASKER, "op", { kind: "new", by: ASKER, push });
    expect(out).toEqual({ seat: "operator", skipped: "operator" });
    expect(pushed).toEqual([]);
    expect(fs.readFileSync(file("op"), "utf8")).toBe(before);
  });

  it("a forward notices the new holder, naming who passed it and who asked", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "f1" }, BODY);
    await noticeHolder(root, ASKER, "f1", { kind: "new", by: ASKER, push });
    await forwardAsk(root, ASKER, "f1", { to: PARENT, by: HOLDER });
    const out = await noticeHolder(root, ASKER, "f1", { kind: "forward", by: HOLDER, push });
    expect(out).toMatchObject({ seat: PARENT, delivery: { status: "delivered" } });
    expect(pushed.map((p) => p.seat)).toEqual([HOLDER, PARENT]);
    expect(pushed[1].content.split("\n")[0]).toBe(`[ask-forwarded] ${HOLDER} passed you ${ASKER}/f1 "Ship it?" (asked by ${ASKER})`);
    expect(read("f1").header).toMatchObject({ newDelivery: "delivered", newDeliverySeat: PARENT, revision: "2" });
  });

  it("a forward to the operator pushes nothing and clears the earlier seat's record", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "f2" }, BODY);
    await noticeHolder(root, ASKER, "f2", { kind: "new", by: ASKER, push });
    await forwardAsk(root, ASKER, "f2", { to: "operator", by: HOLDER });
    const out = await noticeHolder(root, ASKER, "f2", { kind: "forward", by: HOLDER, push });
    expect(out).toEqual({ seat: "operator", skipped: "operator" });
    expect(pushed.map((p) => p.seat)).toEqual([HOLDER]);
    const h = read("f2").header;
    expect(h.newDelivery).toBeUndefined();
    expect(h.newDeliverySeat).toBeUndefined();
  });

  it("a failed push leaves the ask filed and open, with undelivered and the reason recorded", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "x1" }, BODY);
    const bad = async () => ({ status: "undelivered" as const, reason: "no live session named manager:domain" });
    const out = await noticeHolder(root, ASKER, "x1", { kind: "new", by: ASKER, push: bad });
    expect(out).toMatchObject({ seat: HOLDER, delivery: { status: "undelivered", reason: "no live session named manager:domain" } });
    expect(read("x1").header).toMatchObject({ status: "open", revision: "1", newDelivery: "undelivered", newDeliverySeat: HOLDER, newDeliveryNote: "no live session named manager:domain" });
  });

  it("a push that throws is an undelivered notice, never a thrown error", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "x2" }, BODY);
    const boom = async (): Promise<never> => {
      throw new Error("socket exploded\nsecond line");
    };
    const out = await noticeHolder(root, ASKER, "x2", { kind: "new", by: ASKER, push: boom });
    expect(out).toMatchObject({ seat: HOLDER, delivery: { status: "undelivered" } });
    const h = read("x2").header;
    expect(h.newDelivery).toBe("undelivered");
    expect(h.newDeliveryNote).toContain("socket exploded");
    expect(h.newDeliveryNote).not.toContain("\n");
  });

  it("the notice fields are store fields: new and revise refuse them", async () => {
    for (const k of NOTICE_FIELDS) expect(STAMP_FIELDS as readonly string[]).toContain(k);
    expect(() => newAsk(root, { from: ASKER, to: HOLDER, id: "s1", newDelivery: "delivered" }, BODY)).toThrow(AskFormatError);
    newAsk(root, { from: ASKER, to: HOLDER, id: "s2" }, BODY);
    await expect(reviseAsk(root, ASKER, "s2", { newDeliverySeat: "x:y" }, undefined, { by: ASKER, push })).rejects.toThrow(/not revisable/);
  });

  it("the reserved-decline pass-up already pushes, so it records the same fields from that push", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "r1", "reserved-for": "operator" }, BODY);
    const out = await answerAsk(root, ASKER, "r1", { declined: true, reason: "not mine", answeredBy: HOLDER }, { expectedRevision: 1, passUpTo: PARENT, push });
    expect(out.passedUpTo).toBe(PARENT);
    expect(pushed.map((p) => p.seat)).toEqual([PARENT]);
    expect(pushed[0].content).toContain("[ask-passed-up]");
    expect(read("r1").header).toMatchObject({ newDelivery: "delivered", newDeliverySeat: PARENT });
  });

  it("a parent that takes a silent holder's ask (forward --to itself) is not pushed its own move, and the old record is cleared", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "self" }, BODY);
    await noticeHolder(root, ASKER, "self", { kind: "new", by: ASKER, push });
    await forwardAsk(root, ASKER, "self", { to: PARENT, by: PARENT, manages: [HOLDER] });
    expect(read("self").header.to).toBe(PARENT);
    const out = await noticeHolder(root, ASKER, "self", { kind: "forward", by: PARENT, push });
    expect(out).toEqual({ seat: PARENT, skipped: "self" });
    expect(pushed.map((p) => p.seat)).toEqual([HOLDER]);
    expect(read("self").header.newDelivery).toBeUndefined();
    expect(read("self").header.newDeliverySeat).toBeUndefined();
  });

  it("an ask addressed in another spelling of the operator is not pushed either", async () => {
    for (const [id, to] of [["cap", "Operator"], ["rel", "operator (relayed by manager:domain)"]] as const) {
      try {
        newAsk(root, { from: ASKER, to, id }, BODY);
      } catch {
        continue; // a spelling the store refuses as a recipient cannot be pushed to anyway
      }
      expect(await noticeHolder(root, ASKER, id, { kind: "new", by: ASKER, push })).toEqual({ seat: to, skipped: "operator" });
    }
    expect(pushed).toEqual([]);
  });

  it("a reserved pass-up that ends at the operator records no notice, and clears the earlier holder's", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "r2", "reserved-for": "operator" }, BODY);
    await noticeHolder(root, ASKER, "r2", { kind: "new", by: ASKER, push });
    expect(read("r2").header.newDeliverySeat).toBe(HOLDER);
    const out = await answerAsk(root, ASKER, "r2", { declined: true, reason: "the operator's", answeredBy: HOLDER }, { expectedRevision: 1, push });
    expect(out.passedUpTo).toBe("operator");
    expect(pushed.map((p) => p.seat)).toEqual([HOLDER]);
    const h = read("r2").header;
    for (const k of NOTICE_FIELDS) expect(h[k], k).toBeUndefined();
  });

  it("rename-seat rewrites the notice's seat and its note", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "ren" }, BODY);
    const bad = async () => ({ status: "undelivered" as const, reason: `no live session named ${HOLDER}` });
    await noticeHolder(root, ASKER, "ren", { kind: "new", by: ASKER, push: bad });
    await renameSeat(root, HOLDER, "manager:domains", { by: "operator" });
    const h = read("ren").header;
    expect(h.newDeliverySeat).toBe("manager:domains");
    expect(h.newDeliveryNote).toBe("no live session named manager:domains");
  });

  it("wakeView shows the notice beside the wake state, and a notice starts no cooldown", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "wv" }, BODY);
    await noticeHolder(root, ASKER, "wv", { kind: "new", by: ASKER, push, now: "2026-11-04T10:00:00.000Z" });
    const sessions = path.join(base, "sessions");
    fs.mkdirSync(sessions);
    fs.writeFileSync(path.join(sessions, `${process.pid}.json`), JSON.stringify({ pid: process.pid, name: HOLDER, messagingSocketPath: path.join(sessions, "x.sock") }));
    const v = wakeView(read("wv"), { now: Date.parse("2026-11-04T10:00:05.000Z"), sessionsDir: sessions });
    expect(v).toMatchObject({ noticedAt: "2026-11-04T10:00:00.000Z", noticedSeat: HOLDER, noticeDelivery: "delivered" });
    expect(v.noticeDeliveryNote).toBeUndefined();
    expect(v.wakeAfter).toBeUndefined();
    expect(v.wakeBlocked).toBeUndefined();
  });

  it("holderNoticeMessage names the ask by id when it has no question title", () => {
    const ask = parseAskFile(`---\nid: q\nto: ${HOLDER}\nfrom: ${ASKER}\n---\n\nprose only\n`);
    expect(holderNoticeMessage({ kind: "new", seat: ASKER, id: "q", file: "/f", ask, holder: HOLDER, by: ASKER }).split("\n")[0]).toBe(`[ask-new] ${ASKER} asked you: ${ASKER}/q`);
  });
});

describe("engine ask new / forward push the holder's notice (CLI)", () => {
  let base: string, root: string, sessions: string, sockPath: string, sock: net.Server;
  let received: string[];
  const env = (seat: string): NodeJS.ProcessEnv => {
    const e: NodeJS.ProcessEnv = { ...process.env, FLEET_PANE: seat, FLEET_PARENT: "", ASK_SESSIONS_DIR: sessions };
    delete e.TMUX_PANE;
    delete e.FLEET_MANAGES;
    return e;
  };
  const run = (seat: string, args: string[], input?: string) =>
    spawnSync(process.execPath, ["--no-warnings", CLI, ...args, "--root", root], { encoding: "utf8", env: env(seat), input });
  // The holder's live session is this test process, listening on its own socket.
  const holderIsLive = (seat: string) =>
    fs.writeFileSync(path.join(sessions, `${process.pid}.json`), JSON.stringify({ pid: process.pid, name: seat, messagingSocketPath: sockPath }));
  const header = (id: string) => parseAskFile(fs.readFileSync(path.join(root, ASKER, `${id}.md`), "utf8")).header;
  const settle = () => new Promise((r) => setTimeout(r, 150));

  beforeAll(async () => {
    base = fs.mkdtempSync(path.join("/tmp", "asks-notice-cli-"));
    sockPath = path.join(base, "h.sock");
    sock = net.createServer((c) => {
      let buf = "";
      c.on("data", (d) => (buf += d));
      c.on("end", () => received.push(buf));
    });
    await new Promise<void>((r) => sock.listen(sockPath, () => r()));
  });
  afterAll(async () => {
    await new Promise((r) => sock.close(() => r(null)));
    fs.rmSync(base, { recursive: true, force: true });
  });
  beforeEach(() => {
    root = fs.mkdtempSync(path.join(base, "asks-"));
    sessions = fs.mkdtempSync(path.join(base, "sessions-"));
    received = [];
  });

  it("new: the holder's socket receives the [ask-new] notice; stdout is still the path and the URL", async () => {
    holderIsLive(HOLDER);
    const r = run(ASKER, ["new", "--to", HOLDER, "--id", "c1"], BODY);
    expect(r.status).toBe(0);
    expect(r.stdout.trim().split("\n")).toHaveLength(2);
    expect(r.stderr).toContain(`notice delivered to ${HOLDER}`);
    await settle();
    expect(received).toHaveLength(1);
    expect(received[0]).toContain(`[ask-new] ${ASKER} asked you: ${ASKER}/c1`);
    expect(header("c1")).toMatchObject({ newDelivery: "delivered", newDeliverySeat: HOLDER });
  });

  it("new: with nobody live, the ask is filed, exit 0, and stderr says the notice did not reach the seat and why", async () => {
    const r = run(ASKER, ["new", "--to", HOLDER, "--id", "c2"], BODY);
    expect(r.status).toBe(0);
    expect(fs.existsSync(path.join(root, ASKER, "c2.md"))).toBe(true);
    expect(r.stderr).toMatch(new RegExp(`notice did not reach ${HOLDER}: no live session named ${HOLDER}`));
    expect(header("c2")).toMatchObject({ status: "open", newDelivery: "undelivered", newDeliveryNote: `no live session named ${HOLDER}` });
  });

  it("new --to operator: nothing is pushed, even with a live session named operator, and no record is written", async () => {
    holderIsLive("operator");
    const r = run(ASKER, ["new", "--to", "operator", "--id", "c3"], BODY);
    expect(r.status).toBe(0);
    await settle();
    expect(received).toEqual([]);
    expect(r.stderr).not.toContain("notice");
    expect(header("c3").newDelivery).toBeUndefined();
  });

  it("new --to Operator: the capitalised spelling is the operator too, so the live session named operator gets nothing", async () => {
    holderIsLive("operator");
    const r = run(ASKER, ["new", "--to", "Operator", "--id", "c3b"], BODY);
    expect(r.status).toBe(0);
    await settle();
    expect(received).toEqual([]);
    expect(header("c3b").newDelivery).toBeUndefined();
  });

  it("forward: the new holder's socket receives the [ask-forwarded] notice", async () => {
    expect(run(ASKER, ["new", "--to", HOLDER, "--id", "c4"], BODY).status).toBe(0);
    holderIsLive(PARENT);
    const r = run(HOLDER, ["forward", `${ASKER}/c4`, "--to", PARENT]);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain(`forwarded\t${ASKER}/c4 → ${PARENT}`);
    await settle();
    expect(received).toHaveLength(1);
    expect(received[0]).toContain(`[ask-forwarded] ${HOLDER} passed you ${ASKER}/c4`);
    expect(header("c4")).toMatchObject({ to: PARENT, newDelivery: "delivered", newDeliverySeat: PARENT });
  });
});
