/**
 * Ask v2 store: drafts and the batch send, read/acted stamps, the forward chain and the
 * reserved-for rule. Pushes go to a fake seat socket or a recorder, never to a real session.
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import { actedAsk, answerAsk, discardDraft, forwardAsk, newAsk, pickupUnread, readAsk, reviseAsk, saveDraft, sendBatch } from "../src/lib/store.ts";
import { parseAskFile, AskFormatError, StaleRevisionError } from "../src/lib/format.ts";

let root: string;
let sessions: string;
beforeEach(() => {
  const base = fs.mkdtempSync(path.join("/tmp", "asks2-"));
  root = path.join(base, "asks");
  sessions = path.join(base, "s");
  fs.mkdirSync(sessions, { recursive: true });
});
afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));

const GO = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n";
const NAME = "## ¶ASK_NAME: Text: Name it?\n";
const read = (seat: string, id: string) => parseAskFile(fs.readFileSync(path.join(root, seat, `${id}.md`), "utf8"));

type Sent = { seat: string; content: string };
function recorder() {
  const sent: Sent[] = [];
  const push = async (seat: string, content: string) => {
    sent.push({ seat, content });
    return seat === "dead:seat" ? { status: "undelivered" as const, reason: "no live session named dead:seat" } : { status: "delivered" as const };
  };
  return { sent, push };
}

describe("drafts and the batch send (acceptance 1)", () => {
  it("a draft is saved in the file and nothing is pushed", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "a1" }, GO);
    await saveDraft(root, "idealic:kernel", "a1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, 1);
    const a = read("idealic:kernel", "a1");
    expect(a.header.status).toBe("open");
    expect(a.draft?.answers).toEqual({ GO: ["YES"] });
  });

  it("sends ONE message per seat, listing title → answer · id for each settled ask", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "a1" }, GO);
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "a2" }, NAME);
    newAsk(root, { from: "manager:app", to: "operator", id: "b1" }, GO);
    await saveDraft(root, "idealic:kernel", "a1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, 1);
    await saveDraft(root, "idealic:kernel", "a2", { answers: { NAME: "kite" }, answeredBy: "operator" }, 1);
    await saveDraft(root, "manager:app", "b1", { declined: true, reason: "not mine to rule", answeredBy: "operator" }, 1);
    const r = recorder();
    const out = await sendBatch(root, ["idealic:kernel/a1", "idealic:kernel/a2", "manager:app/b1"], { push: r.push, by: "operator" });
    expect(out.settled.map((s) => s.ref)).toEqual(["idealic:kernel/a1", "idealic:kernel/a2", "manager:app/b1"]);
    expect(r.sent.map((s) => s.seat).sort()).toEqual(["idealic:kernel", "manager:app"]);
    const k = r.sent.find((s) => s.seat === "idealic:kernel")!.content;
    expect(k.split("\n")[0]).toBe("[ask-batch] from operator via ask-app: 2 answers for idealic:kernel");
    expect(k).toContain("Ship it? → Yes · idealic:kernel/a1#GO");
    expect(k).toContain('Name it? → "kite" · idealic:kernel/a2#NAME');
    expect(k).toContain("engine ask read");
    expect(r.sent.find((s) => s.seat === "manager:app")!.content).toContain("Ship it? → declined: not mine to rule · manager:app/b1");
    expect(read("idealic:kernel", "a1")).toMatchObject({ header: { status: "answered", revision: "2", delivery: "delivered" } });
    expect(read("idealic:kernel", "a1").draft).toBeUndefined();
    expect(read("manager:app", "b1").header.status).toBe("declined");
  });

  it("sends only what the files hold: an ask without a draft is refused, not invented", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "a1" }, GO);
    const r = recorder();
    const out = await sendBatch(root, ["idealic:kernel/a1"], { push: r.push, by: "operator" });
    expect(out.settled).toEqual([]);
    expect(out.refused[0]).toMatchObject({ ref: "idealic:kernel/a1", error: expect.stringContaining("no draft") });
    expect(r.sent).toEqual([]);
    expect(read("idealic:kernel", "a1").header.status).toBe("open");
  });

  it("S4: a draft whose ask moved (forwarded) after it was saved is refused AS STALE, and the other drafts still go", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "a1" }, GO);
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "a2" }, GO);
    await saveDraft(root, "idealic:kernel", "a1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, 1);
    await saveDraft(root, "idealic:kernel", "a2", { answers: { GO: ["NO"] }, answeredBy: "operator" }, 1);
    await forwardAsk(root, "idealic:kernel", "a1", { to: "operator", by: "manager:idealic" });
    expect(read("idealic:kernel", "a1").header.revision).toBe("2");
    expect(read("idealic:kernel", "a1").draft?.basedOn).toBe(1);
    const r = recorder();
    const out = await sendBatch(root, ["idealic:kernel/a1", "idealic:kernel/a2"], { push: r.push, by: "operator" });
    expect(out.refused).toEqual([{ ref: "idealic:kernel/a1", error: expect.stringMatching(/^stale revision: expected 1, the ask is at revision 2: the ask moved/) }]);
    expect(out.settled.map((x) => x.ref)).toEqual(["idealic:kernel/a2"]);
    expect(read("idealic:kernel", "a1").header.status).toBe("open");
    expect(r.sent).toHaveLength(1);
    expect(r.sent[0].content).not.toContain("a1#");
  });

  it("S4: a draft whose question text was edited after it was saved is refused, not sent against the new text", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "a1" }, GO);
    await saveDraft(root, "idealic:kernel", "a1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, 1);
    const f = path.join(root, "idealic:kernel", "a1.md");
    fs.writeFileSync(f, fs.readFileSync(f, "utf8").replace("Ship it?", "Delete prod?"));
    const out = await sendBatch(root, ["idealic:kernel/a1"], { push: recorder().push, by: "operator" });
    expect(out.refused[0].error).toContain("edited after the draft was saved");
    expect(read("idealic:kernel", "a1").header.status).toBe("open");
  });

  it("S1: with no refs, sends only the SENDER's own drafts, never another answerer's held tray", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "a1" }, GO);
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "a2" }, GO);
    await saveDraft(root, "idealic:kernel", "a1", { answers: { GO: ["YES"] }, answeredBy: "manager:idealic" }, 1);
    await saveDraft(root, "idealic:kernel", "a2", { answers: { GO: ["NO"] }, answeredBy: "operator" }, 1);
    const out = await sendBatch(root, undefined, { push: recorder().push, by: "manager:idealic" });
    expect(out.settled.map((x) => x.ref)).toEqual(["idealic:kernel/a1"]);
    expect(out.refused).toEqual([]); // the operator's draft is not even attempted, so not reported
    expect(read("idealic:kernel", "a2").header.status).toBe("open");
    const named = await sendBatch(root, ["idealic:kernel/a2"], { push: recorder().push, by: "manager:idealic" });
    expect(named.refused[0].error).toContain("only its author sends it");
    await expect(sendBatch(root, undefined, { push: recorder().push, by: "" })).rejects.toThrow("must name its sender");
  });

  it("M3: only a draft's author replaces or discards it", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "a1" }, GO);
    await saveDraft(root, "idealic:kernel", "a1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, 1);
    await expect(saveDraft(root, "idealic:kernel", "a1", { answers: { GO: ["NO"] }, answeredBy: "manager:idealic" }, 1)).rejects.toThrow("only its author");
    await expect(discardDraft(root, "idealic:kernel", "a1", "manager:idealic")).rejects.toThrow("only its author");
    expect(read("idealic:kernel", "a1").draft?.answeredBy).toBe("operator");
  });

  it("discarding a draft leaves the ask open with no draft", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "a1" }, GO);
    await saveDraft(root, "idealic:kernel", "a1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, 1);
    await discardDraft(root, "idealic:kernel", "a1", "operator");
    expect(read("idealic:kernel", "a1").draft).toBeUndefined();
    expect(read("idealic:kernel", "a1").header.draft).toBeUndefined();
  });

  it("an undelivered seat is recorded per file, and a delivered one is not mislabelled", async () => {
    newAsk(root, { from: "dead:seat", to: "operator", id: "d1" }, GO);
    await saveDraft(root, "dead:seat", "d1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, 1);
    await sendBatch(root, ["dead:seat/d1"], { push: recorder().push, by: "operator" });
    expect(read("dead:seat", "d1").header).toMatchObject({ delivery: "undelivered", deliveryNote: expect.stringContaining("dead:seat") });
  });

  it("over a real socket, the seat receives exactly one message for the whole batch", async () => {
    const sock = path.join(sessions, "k.sock");
    const conns: string[] = [];
    const srv = net.createServer((c) => {
      let b = "";
      c.on("data", (d) => (b += d));
      c.on("end", () => conns.push(b));
    });
    await new Promise((r) => srv.listen(sock, () => r(null)));
    fs.writeFileSync(path.join(sessions, "1.json"), JSON.stringify({ pid: process.pid, name: "idealic:kernel", messagingSocketPath: sock }));
    for (const id of ["a1", "a2", "a3"]) {
      newAsk(root, { from: "idealic:kernel", to: "operator", id }, GO);
      await saveDraft(root, "idealic:kernel", id, { answers: { GO: ["YES"] }, answeredBy: "operator" }, 1);
    }
    await sendBatch(root, undefined, { sessionsDir: sessions, by: "operator" });
    await new Promise((r) => setTimeout(r, 50));
    await new Promise((r) => srv.close(() => r(null)));
    expect(conns).toHaveLength(1);
    expect(conns[0].match(/Ship it\? → Yes/g)).toHaveLength(3);
  });
});

describe("read and acted (acceptance 2)", () => {
  async function answered(id = "a1") {
    newAsk(root, { from: "idealic:kernel", to: "operator", id }, GO);
    await answerAsk(root, "idealic:kernel", id, { answers: { GO: ["YES"] }, answeredBy: "operator" }, { push: recorder().push, expectedRevision: 1 });
  }

  it("reading as the asker stamps readAt once and returns the collapsed lines", async () => {
    await answered();
    const r1 = await readAsk(root, "idealic:kernel", "a1", { by: "idealic:kernel", now: "2026-10-29T01:00:00Z" });
    expect(r1.lines).toEqual(["Ship it? → Yes · idealic:kernel/a1#GO"]);
    expect(r1.stamped).toBe(true);
    await readAsk(root, "idealic:kernel", "a1", { by: "idealic:kernel", now: "2026-10-29T02:00:00Z" });
    expect(read("idealic:kernel", "a1").header).toMatchObject({ readAt: "2026-10-29T01:00:00Z", readBy: "idealic:kernel", revision: "2" });
  });

  it("reading by someone the answer was not for does not stamp it read", async () => {
    await answered();
    const r = await readAsk(root, "idealic:kernel", "a1", { by: "operator" });
    expect(r.stamped).toBe(false);
    expect(read("idealic:kernel", "a1").header.readAt).toBeUndefined();
  });

  it("an open ask has nothing to read and is not stamped", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "o1" }, GO);
    const r = await readAsk(root, "idealic:kernel", "o1", { by: "idealic:kernel" });
    expect(r.stamped).toBe(false);
    expect(read("idealic:kernel", "o1").header.readAt).toBeUndefined();
  });

  it("the /next pickup reads every settled, unread ask of the seat — declines included (NEW-4)", async () => {
    await answered("a1");
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "d1" }, GO);
    await answerAsk(root, "idealic:kernel", "d1", { declined: true, reason: "no", answeredBy: "operator" }, { push: recorder().push, expectedRevision: 1 });
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "o1" }, GO);
    const got = await pickupUnread(root, "idealic:kernel", { by: "idealic:kernel" });
    expect(got.map((g) => g.ref).sort()).toEqual(["idealic:kernel/a1", "idealic:kernel/d1"]);
    expect(got.every((g) => g.stamped)).toBe(true);
    expect(await pickupUnread(root, "idealic:kernel", { by: "idealic:kernel" })).toEqual([]);
  });

  it("acted stamps a one-line summary, implies read, and refuses a blank one", async () => {
    await answered();
    await expect(actedAsk(root, "idealic:kernel", "a1", "  ", { by: "idealic:kernel" })).rejects.toThrow("non-blank");
    await actedAsk(root, "idealic:kernel", "a1", "shipped in b07691f", { by: "idealic:kernel", now: "2026-10-29T03:00:00Z" });
    expect(read("idealic:kernel", "a1").header).toMatchObject({ acted: "shipped in b07691f", actedAt: "2026-10-29T03:00:00Z", readAt: "2026-10-29T03:00:00Z" });
  });

  it("a new answer resets read and acted, so an old read is never shown for a new answer", async () => {
    await answered();
    await readAsk(root, "idealic:kernel", "a1", { by: "idealic:kernel" });
    await answerAsk(root, "idealic:kernel", "a1", { answers: { GO: ["NO"] }, answeredBy: "operator" }, { push: recorder().push, expectedRevision: 2 });
    expect(read("idealic:kernel", "a1").header.readAt).toBeUndefined();
  });
});

describe("reserved-for operator (COORDHOP R4)", () => {
  it("refuses an answer, a draft and a send by anyone but the operator", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:director", id: "r1", "reserved-for": "operator" }, GO);
    await expect(answerAsk(root, "idealic:kernel", "r1", { answers: { GO: ["YES"] }, answeredBy: "manager:director" }, { push: recorder().push, expectedRevision: 1 })).rejects.toThrow("reserved for operator");
    await expect(saveDraft(root, "idealic:kernel", "r1", { answers: { GO: ["YES"] }, answeredBy: "manager:director" }, 1)).rejects.toThrow("reserved for operator");
    expect(read("idealic:kernel", "r1").header.status).toBe("open");
    await answerAsk(root, "idealic:kernel", "r1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { push: recorder().push, expectedRevision: 1 });
    expect(read("idealic:kernel", "r1").header.status).toBe("answered");
  });
});

describe("forwarding (COORDHOP S4)", () => {
  it("only the current holder may move to:, the hop is recorded, and the answer reaches every forwarder", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "f1" }, GO);
    await expect(forwardAsk(root, "idealic:kernel", "f1", { to: "operator", by: "idealic:kernel" })).rejects.toThrow("only the holder");
    await forwardAsk(root, "idealic:kernel", "f1", { to: "manager:director", by: "manager:idealic", now: "2026-10-29T01:00:00Z" });
    await forwardAsk(root, "idealic:kernel", "f1", { to: "operator", by: "manager:director", now: "2026-10-29T01:10:00Z" });
    const h = read("idealic:kernel", "f1").header;
    expect(h.to).toBe("operator");
    expect(h.forwards).toBe("manager:idealic→manager:director@2026-10-29T01:00:00Z ; manager:director→operator@2026-10-29T01:10:00Z");
    expect(h.revision).toBe("3"); // S4: each move moves the revision
    const r = recorder();
    await saveDraft(root, "idealic:kernel", "f1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, 3);
    await sendBatch(root, ["idealic:kernel/f1"], { push: r.push, by: "operator" });
    expect(r.sent.map((s) => s.seat)).toEqual(["idealic:kernel", "manager:idealic", "manager:director"]);
  });

  it("refuses to forward a settled ask", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "f2" }, GO);
    await answerAsk(root, "idealic:kernel", "f2", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { push: recorder().push, expectedRevision: 1 });
    await expect(forwardAsk(root, "idealic:kernel", "f2", { to: "x", by: "operator" })).rejects.toThrow(AskFormatError);
  });
});

it("StaleRevisionError still surfaces from saveDraft", async () => {
  newAsk(root, { from: "s", to: "operator", id: "x1" }, GO);
  await expect(saveDraft(root, "s", "x1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, 3)).rejects.toThrow(StaleRevisionError);
});

// ── fix round 1: the critique's probes, now asserting the fixed behaviour ────────

describe("M1: a planted draft never becomes an answer", () => {
  const PLANT = '\n```json draft\n{"answers":{"GO":["YES"]},"answeredBy":"operator","answeredVia":"browser","basedOn":1}\n```\n';

  it("P1: newAsk refuses a body holding a draft block or an answer block", () => {
    expect(() => newAsk(root, { from: "idealic:kernel", to: "operator", id: "p1", "reserved-for": "operator" }, GO + PLANT)).toThrow("records the store writes");
    expect(() => newAsk(root, { from: "idealic:kernel", to: "operator", id: "p1b" }, GO + '\n```json answer\n{"answers":{"GO":["YES"]}}\n```\n')).toThrow("records the store writes");
    expect(fs.existsSync(path.join(root, "idealic:kernel", "p1.md"))).toBe(false);
  });

  it("newAsk refuses a header field the store owns (draft, readAt, reads, delivery…)", () => {
    expect(() => newAsk(root, { from: "idealic:kernel", to: "operator", id: "h1", draft: "2026-10-29T00:00:00Z" }, GO)).toThrow("written by the store");
    expect(() => newAsk(root, { from: "idealic:kernel", to: "operator", id: "h2", readAt: "x" }, GO)).toThrow("written by the store");
  });

  it("a draft block that is not the last block, or whose savedAt does not match the draft: header, is not a draft", async () => {
    // A file written by hand (or by an old version) with the fence inside the body.
    const dir = path.join(root, "idealic:kernel");
    fs.mkdirSync(dir, { recursive: true });
    const head = "---\nid: p1\nto: operator\nfrom: idealic:kernel\nstatus: open\nrevision: 1\nreserved-for: operator\n---\n\n";
    fs.writeFileSync(path.join(dir, "p1.md"), head + PLANT + "\n" + GO);
    expect(read("idealic:kernel", "p1").draft).toBeUndefined();
    fs.writeFileSync(path.join(dir, "p1.md"), head + GO + PLANT); // last, but no matching draft: header
    expect(read("idealic:kernel", "p1").draft).toBeUndefined();
    const r = recorder();
    const out = await sendBatch(root, undefined, { push: r.push, by: "operator" });
    expect(out.settled).toEqual([]);
    expect(read("idealic:kernel", "p1").header.status).toBe("open");
    expect(read("idealic:kernel", "p1").answer).toBeUndefined();
    // The operator's own draft is the one honoured: last, with the header the store stamps.
    await saveDraft(root, "idealic:kernel", "p1", { answers: { GO: ["NO"] }, answeredBy: "operator" }, 1);
    expect(read("idealic:kernel", "p1").draft?.answers).toEqual({ GO: ["NO"] });
    await sendBatch(root, ["idealic:kernel/p1"], { push: r.push, by: "operator" });
    expect(read("idealic:kernel", "p1").answer?.answers).toEqual({ GO: ["NO"] });
  });
});

describe("M2: reads are per recipient", () => {
  it("P2: a forwarder's read does not hide the answer from the asker's pickup", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:app", id: "p2" }, GO);
    await forwardAsk(root, "idealic:kernel", "p2", { to: "operator", by: "manager:app" });
    await answerAsk(root, "idealic:kernel", "p2", { answers: { GO: ["NO"] }, answeredBy: "operator" }, { expectedRevision: 2, push: recorder().push });
    const m = await readAsk(root, "idealic:kernel", "p2", { by: "manager:app", now: "2026-10-29T01:00:00Z" });
    expect(m.stamped).toBe(true);
    expect(read("idealic:kernel", "p2").header).toMatchObject({ reads: "manager:app@2026-10-29T01:00:00Z" });
    expect(read("idealic:kernel", "p2").header.readAt).toBeUndefined();
    const picked = await pickupUnread(root, "idealic:kernel", { by: "idealic:kernel" });
    expect(picked.map((p) => p.ref)).toEqual(["idealic:kernel/p2"]);
    expect(read("idealic:kernel", "p2").header).toMatchObject({ readBy: "idealic:kernel" });
    expect(await pickupUnread(root, "manager:app", { by: "manager:app" })).toEqual([]);
  });

  it("acted needs a recipient (asker, forwarder or the addressed seat), and a forwarder's acted does not hide the asker's pickup", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:app", id: "a1" }, GO);
    await forwardAsk(root, "idealic:kernel", "a1", { to: "operator", by: "manager:app" });
    await answerAsk(root, "idealic:kernel", "a1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { expectedRevision: 2, push: recorder().push });
    await expect(actedAsk(root, "idealic:kernel", "a1", "used it", { by: "idealic:stranger" })).rejects.toThrow("not a recipient");
    await expect(actedAsk(root, "idealic:kernel", "a1", "used it", {})).rejects.toThrow("must name who acted");
    await actedAsk(root, "idealic:kernel", "a1", "relayed", { by: "manager:app" });
    expect(read("idealic:kernel", "a1").header.readAt).toBeUndefined();
    expect((await pickupUnread(root, "idealic:kernel", { by: "idealic:kernel" })).map((p) => p.ref)).toEqual(["idealic:kernel/a1"]);
    await actedAsk(root, "idealic:kernel", "a1", "addressed seat acts", { by: "operator" });
  });

  it("P6/S2: a pickup run for ANOTHER seat stamps the caller's read, never that seat's", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "p6" }, GO);
    await answerAsk(root, "idealic:kernel", "p6", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { expectedRevision: 1, push: recorder().push });
    const looked = await pickupUnread(root, "idealic:kernel", { by: "manager:app" });
    expect(looked.map((p) => [p.ref, p.stamped])).toEqual([["idealic:kernel/p6", false]]);
    expect(read("idealic:kernel", "p6").header.readBy).toBeUndefined();
    expect(read("idealic:kernel", "p6").header.readAt).toBeUndefined();
    const none = await pickupUnread(root, "idealic:kernel");
    expect(none[0].stamped).toBe(false);
    expect(read("idealic:kernel", "p6").header.readAt).toBeUndefined();
  });

  it("P7/S2: a forwarder's own pickup finds the asks it forwarded", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:app", id: "p7" }, GO);
    await forwardAsk(root, "idealic:kernel", "p7", { to: "operator", by: "manager:app" });
    await answerAsk(root, "idealic:kernel", "p7", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { expectedRevision: 2, push: recorder().push });
    const got = await pickupUnread(root, "manager:app", { by: "manager:app" });
    expect(got.map((g) => [g.ref, g.stamped])).toEqual([["idealic:kernel/p7", true]]);
    expect(await pickupUnread(root, "manager:app", { by: "manager:app" })).toEqual([]);
  });
});

describe("M3: only the addressed seat, its forward chain, or the operator answers", () => {
  it("P3: a non-addressed seat cannot answer an un-reserved ask; the asker cannot answer its own", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:app", id: "p3" }, GO);
    await expect(answerAsk(root, "idealic:kernel", "p3", { answers: { GO: ["YES"] }, answeredBy: "idealic:stranger" }, { expectedRevision: 1, push: recorder().push })).rejects.toThrow("may not answer");
    await expect(answerAsk(root, "idealic:kernel", "p3", { answers: { GO: ["YES"] }, answeredBy: "idealic:kernel" }, { expectedRevision: 1, push: recorder().push })).rejects.toThrow("may not answer");
    await expect(answerAsk(root, "idealic:kernel", "p3", { answers: { GO: ["YES"] } }, { expectedRevision: 1, push: recorder().push })).rejects.toThrow("name its answerer");
    expect(read("idealic:kernel", "p3").header.status).toBe("open");
    await answerAsk(root, "idealic:kernel", "p3", { answers: { GO: ["YES"] }, answeredBy: "manager:app" }, { expectedRevision: 1, push: recorder().push });
    expect(read("idealic:kernel", "p3").answer?.answeredBy).toBe("manager:app");
  });

  it("a seat in the forward chain may answer after the ask moved on", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:app", id: "c1" }, GO);
    await forwardAsk(root, "idealic:kernel", "c1", { to: "manager:director", by: "manager:app" });
    await answerAsk(root, "idealic:kernel", "c1", { answers: { GO: ["NO"] }, answeredBy: "manager:app" }, { expectedRevision: 2, push: recorder().push });
    expect(read("idealic:kernel", "c1").header.status).toBe("answered");
  });

  it("P4: a seat's draft cannot be overwritten by a bystander", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "p4" }, GO);
    await saveDraft(root, "idealic:kernel", "p4", { answers: { GO: ["YES"] }, answeredBy: "operator" }, 1);
    await expect(saveDraft(root, "idealic:kernel", "p4", { answers: { GO: ["NO"] }, answeredBy: "idealic:other" }, 1)).rejects.toThrow(AskFormatError);
    expect(read("idealic:kernel", "p4").draft?.answeredBy).toBe("operator");
  });
});

describe("forwarding when the holder is silent (operator's ruling)", () => {
  it("the holder's own parent (FLEET_MANAGES lists the holder) may forward; the hop goes through the parent", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "s1" }, GO);
    await expect(forwardAsk(root, "idealic:kernel", "s1", { to: "operator", by: "manager:director", manages: ["manager:other"] })).rejects.toThrow("neither");
    await forwardAsk(root, "idealic:kernel", "s1", { to: "operator", by: "manager:director", manages: ["manager:idealic", "manager:x"], now: "2026-10-29T01:00:00Z" });
    const h = read("idealic:kernel", "s1").header;
    expect(h.to).toBe("operator");
    expect(h.forwards).toBe("manager:idealic→manager:director@2026-10-29T01:00:00Z ; manager:director→operator@2026-10-29T01:00:00Z");
    const r = recorder();
    await answerAsk(root, "idealic:kernel", "s1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { expectedRevision: 2, push: r.push });
    expect(r.sent.map((s) => s.seat)).toEqual(["idealic:kernel", "manager:idealic", "manager:director"]);
  });

  it("the asker may not forward its own ask, even naming itself a manager of the holder", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "s2" }, GO);
    await expect(forwardAsk(root, "idealic:kernel", "s2", { to: "operator", by: "idealic:kernel", manages: ["manager:idealic"] })).rejects.toThrow("re-pings the holder");
  });

  it("N5: a seat name holding @ survives the forward chain", async () => {
    newAsk(root, { from: "idealic:kernel", to: "team@x", id: "n5" }, GO);
    await forwardAsk(root, "idealic:kernel", "n5", { to: "boss@y", by: "team@x", now: "2026-10-29T01:00:00Z" });
    await answerAsk(root, "idealic:kernel", "n5", { answers: { GO: ["YES"] }, answeredBy: "boss@y" }, { expectedRevision: 2, push: recorder().push });
    const r = recorder();
    await answerAsk(root, "idealic:kernel", "n5", { answers: { GO: ["NO"] }, answeredBy: "operator" }, { expectedRevision: 3, push: r.push });
    expect(r.sent.map((s) => s.seat)).toEqual(["idealic:kernel", "team@x"]);
  });
});

describe("delivery: single-answer lines, self-echo, the stamp guard, and the re-push", () => {
  it("a single answer's push carries its answer lines, like a batch", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "l1" }, GO);
    const r = recorder();
    await answerAsk(root, "idealic:kernel", "l1", { answers: { GO: ["NO"] }, answeredBy: "operator" }, { expectedRevision: 1, push: r.push });
    expect(r.sent[0].content).toContain("- Ship it? → No · idealic:kernel/l1#GO");
  });

  it("no self-echo: the seat that answered is never pushed its own answer, and its delivery is stamped, not pending", async () => {
    // manager:domain held the ask, passed it up, then recorded the answer: it is a recipient (a forwarder) AND the answerer.
    newAsk(root, { from: "idealic:kernel", to: "manager:domain", id: "e1" }, GO);
    await forwardAsk(root, "idealic:kernel", "e1", { to: "operator", by: "manager:domain" });
    const r = recorder();
    const res = await answerAsk(root, "idealic:kernel", "e1", { answers: { GO: ["YES"] }, answeredBy: "manager:domain" }, { expectedRevision: 2, push: r.push });
    expect(r.sent.map((x) => x.seat)).toEqual(["idealic:kernel"]);
    expect(res.delivery.status).toBe("delivered");
    expect(read("idealic:kernel", "e1").header.delivery).toBe("delivered");
    // The batch path too: other recipients are pushed, the answerer is not.
    for (const [from, id] of [["idealic:kernel", "e2"], ["idealic:other", "e3"]]) {
      newAsk(root, { from, to: "manager:domain", id }, GO);
      await forwardAsk(root, from, id, { to: "operator", by: "manager:domain" });
      await saveDraft(root, from, id, { answers: { GO: ["NO"] }, answeredBy: "manager:domain" }, 2);
    }
    const b = recorder();
    await sendBatch(root, undefined, { push: b.push, by: "manager:domain" });
    expect(b.sent.map((x) => x.seat).sort()).toEqual(["idealic:kernel", "idealic:other"]);
    expect(read("idealic:other", "e3").header.delivery).toBe("delivered");
    expect(read("idealic:kernel", "e2").header.delivery).toBe("delivered");
  });

  it("S5: a slow push for revision 2 never overwrites the delivery stamp of a re-answer at revision 3", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "g1" }, GO);
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    const slow = async () => {
      await gate;
      return { status: "undelivered" as const, reason: "slow and lost" };
    };
    const first = answerAsk(root, "idealic:kernel", "g1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { expectedRevision: 1, push: slow });
    for (let i = 0; i < 50 && read("idealic:kernel", "g1").header.revision !== "2"; i++) await new Promise((r) => setTimeout(r, 5));
    await answerAsk(root, "idealic:kernel", "g1", { answers: { GO: ["NO"] }, answeredBy: "operator" }, { expectedRevision: 2, push: recorder().push });
    expect(read("idealic:kernel", "g1").header).toMatchObject({ revision: "3", delivery: "delivered" });
    release();
    await first;
    expect(read("idealic:kernel", "g1").header).toMatchObject({ revision: "3", delivery: "delivered" });
  });

  it("S3: an answer left pending by a dead writer is pushed again on the next send, once", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "c1" }, GO);
    await answerAsk(root, "idealic:kernel", "c1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { expectedRevision: 1, push: recorder().push });
    // Simulate the crash: settled, `pending`, the writer a pid that no longer exists.
    const f = path.join(root, "idealic:kernel", "c1.md");
    const t = fs.readFileSync(f, "utf8").replace(/^delivery: .*$/m, "delivery: pending").replace(/^deliveryNote:.*\n/m, "");
    fs.writeFileSync(f, t.replace(/^status: answered$/m, `status: answered\ndeliveryWriter: 999999@${new Date().toISOString()}`));
    expect(read("idealic:kernel", "c1").header.delivery).toBe("pending");
    const r = recorder();
    const out = await sendBatch(root, undefined, { push: r.push, by: "operator" });
    expect(out.repushed).toEqual([{ ref: "idealic:kernel/c1", delivery: { status: "delivered" } }]);
    expect(r.sent.map((s) => s.seat)).toEqual(["idealic:kernel"]);
    expect(r.sent[0].content).toContain("Ship it? → Yes");
    expect(read("idealic:kernel", "c1").header).toMatchObject({ delivery: "delivered" });
    expect(read("idealic:kernel", "c1").header.deliveryWriter).toBeUndefined();
    const again = recorder();
    await sendBatch(root, undefined, { push: again.push, by: "operator" });
    expect(again.sent).toEqual([]);
  });

  it("S3: a pending whose writer is alive and recent is left alone (no double push)", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "c2" }, GO);
    await answerAsk(root, "idealic:kernel", "c2", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { expectedRevision: 1, push: recorder().push });
    const f = path.join(root, "idealic:kernel", "c2.md");
    const t = fs.readFileSync(f, "utf8").replace(/^delivery: .*$/m, "delivery: pending");
    fs.writeFileSync(f, t.replace(/^status: answered$/m, `status: answered\ndeliveryWriter: ${process.pid}@${new Date().toISOString()}`));
    const r = recorder();
    expect((await sendBatch(root, undefined, { push: r.push, by: "operator" })).repushed).toEqual([]);
    expect(r.sent).toEqual([]);
  });
});

describe("relayed operator answers (conductor add-on)", () => {
  it("a relay on a reserved ask is stamped operator via relay:<seat>, and the relayer is not pushed", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:docs", id: "rl1", "reserved-for": "operator" }, GO);
    await forwardAsk(root, "idealic:kernel", "rl1", { to: "manager:director", by: "manager:docs" });
    const r = recorder();
    await answerAsk(root, "idealic:kernel", "rl1", { answers: { GO: ["YES"] }, answeredBy: "operator", answeredVia: "relay:manager:docs", note: "operator in chat, 02:20" }, { expectedRevision: 2, push: r.push });
    expect(read("idealic:kernel", "rl1").answer).toMatchObject({ answeredBy: "operator", answeredVia: "relay:manager:docs", note: "operator in chat, 02:20" });
    expect(r.sent.map((x) => x.seat)).toEqual(["idealic:kernel"]); // the forwarder that relayed hears nothing back
    expect(read("idealic:kernel", "rl1").header.delivery).toBe("delivered");
    await actedAsk(root, "idealic:kernel", "rl1", "applied the ruling", { by: "idealic:kernel" });
    expect(read("idealic:kernel", "rl1").header.acted).toBe("applied the ruling");
  });
});

describe("revise (conductor add-on)", () => {
  it("the asker revises an open ask: the revision moves, id/from/to/forwards stay, and what changed is recorded", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:app", id: "rv1" }, GO);
    await forwardAsk(root, "idealic:kernel", "rv1", { to: "manager:director", by: "manager:app", now: "2026-10-29T01:00:00Z" });
    const r = recorder();
    const out = await reviseAsk(root, "idealic:kernel", "rv1", { stake: "two lanes stall" }, GO.replace("Ship it?", "Ship it tonight?"), { by: "idealic:kernel", push: r.push, now: "2026-10-29T02:00:00Z" });
    expect(out).toMatchObject({ revision: 3, changed: ["stake", "body"] });
    const a = read("idealic:kernel", "rv1");
    expect(a.header).toMatchObject({ id: "rv1", from: "idealic:kernel", to: "manager:director", revision: "3", stake: "two lanes stall", revisions: "3@2026-10-29T02:00:00Z:stake,body", status: "open" });
    expect(a.header.forwards).toContain("manager:app→manager:director");
    expect(a.questions[0].title).toBe("Ship it tonight?");
    expect(r.sent.map((x) => x.seat).sort()).toEqual(["manager:app", "manager:director"]);
    expect(r.sent[0].content).toContain("[ask-revised]");
  });

  it("a non-asker revising is refused, the forwarder and the operator included", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:app", id: "rv2" }, GO);
    for (const by of ["manager:app", "operator", "idealic:stranger"]) {
      await expect(reviseAsk(root, "idealic:kernel", "rv2", { stake: "x" }, undefined, { by, push: recorder().push })).rejects.toThrow("only the asker");
    }
    expect(read("idealic:kernel", "rv2").header.revision).toBe("1");
  });

  it("a draft saved before a revise is refused as stale; an answer at the old revision too", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "rv3" }, GO);
    await saveDraft(root, "idealic:kernel", "rv3", { answers: { GO: ["YES"] }, answeredBy: "operator" }, 1);
    await reviseAsk(root, "idealic:kernel", "rv3", { stake: "now it matters" }, undefined, { by: "idealic:kernel", push: recorder().push });
    const out = await sendBatch(root, ["idealic:kernel/rv3"], { push: recorder().push, by: "operator" });
    expect(out.refused[0].error).toMatch(/^stale revision: expected 1, the ask is at revision 2/);
    await expect(answerAsk(root, "idealic:kernel", "rv3", { answers: { GO: ["NO"] }, answeredBy: "operator" }, { expectedRevision: 1, push: recorder().push })).rejects.toThrow(StaleRevisionError);
    expect(read("idealic:kernel", "rv3").header.status).toBe("open");
  });

  it("revise refuses identity fields, a planted record and bad option codes", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "rv4" }, GO);
    await expect(reviseAsk(root, "idealic:kernel", "rv4", { to: "x" }, undefined, { by: "idealic:kernel" })).rejects.toThrow("not revisable");
    await expect(reviseAsk(root, "idealic:kernel", "rv4", {}, GO + "\n```json draft\n{}\n```\n", { by: "idealic:kernel" })).rejects.toThrow("records the store writes");
    await expect(reviseAsk(root, "idealic:kernel", "rv4", {}, "## ¶ASK_GO: Choose one: Where?\n- [ ] [OVERLONGCODE1] In a worktree\n", { by: "idealic:kernel" })).rejects.toThrow("[OVERLONGCODE1]");
  });
});

describe("filing checks and acted (conductor add-on)", () => {
  it("new accepts codes up to 12 characters as CODES, and the answer stores the code", async () => {
    const body = "## ¶ASK_F5: Choose one: What now?\n- [ ] [RESCOPE] Rescope it\n- [ ] [KEEPBROAD] Keep it broad\n- [ ] [MARINATE] Let it marinate\n- [ ] [TICKET] File a ticket\n  - [ ] [WORKTREE] In a worktree\n";
    newAsk(root, { from: "domain:stats", to: "operator", id: "cd0" }, body);
    const q = read("domain:stats", "cd0").questions[0];
    expect(q.options.map((o) => [o.code, o.label])).toEqual([["RESCOPE", "Rescope it"], ["KEEPBROAD", "Keep it broad"], ["MARINATE", "Let it marinate"], ["TICKET", "File a ticket"]]);
    await answerAsk(root, "domain:stats", "cd0", { answers: { F5: ["KEEPBROAD"] }, answeredBy: "operator" }, { expectedRevision: 1, push: recorder().push });
    expect(read("domain:stats", "cd0").answer?.answers).toEqual({ F5: ["KEEPBROAD"] });
    // The pre-fix shape — the whole "[CODE] label" stored as the value — is refused for a new answer…
    await expect(answerAsk(root, "domain:stats", "cd0", { answers: { F5: ["[RESCOPE] Rescope it"] }, answeredBy: "operator" }, { expectedRevision: 2, push: recorder().push })).rejects.toThrow("unknown option");
    // …and one already stored that way still reads back as its option's label.
    const f = path.join(root, "domain:stats", "cd0.md");
    fs.writeFileSync(f, fs.readFileSync(f, "utf8").replace('"KEEPBROAD"', '"[KEEPBROAD] Keep it broad"'));
    expect((await readAsk(root, "domain:stats", "cd0", { by: "domain:stats" })).lines).toEqual(["What now? → Keep it broad · domain:stats/cd0#F5"]);
  });

  it("new refuses an option code the grammar cannot read (over 12, or not capitals), naming it", () => {
    const body = "## ¶ASK_WHERE: Choose one: Where?\n- [ ] [THIRTEENCHARS] Too long\n- [ ] [wt] lower\n  - [ ] [OK] fine\n";
    expect(() => newAsk(root, { from: "domain:stats", to: "operator", id: "cd1" }, body)).toThrow(/\[THIRTEENCHARS\].*\[wt\]/);
    expect(fs.existsSync(path.join(root, "domain:stats", "cd1.md"))).toBe(false);
  });

  it("acted on an ask ruled in chat: refused without --ruled-in-chat, closed as ruled with it", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:domain", id: "rc1" }, GO);
    await expect(actedAsk(root, "idealic:kernel", "rc1", "did it", { by: "idealic:kernel" })).rejects.toThrow("--ruled-in-chat");
    await actedAsk(root, "idealic:kernel", "rc1", "did it", { by: "idealic:kernel", ruledInChat: "operator in manager:domain's chat, 2026-10-29 02:30" });
    const a = read("idealic:kernel", "rc1");
    expect(a.header).toMatchObject({ status: "ruled", revision: "2", acted: "did it", ruledInChat: "operator in manager:domain's chat, 2026-10-29 02:30" });
    expect(a.answer).toBeUndefined();
    await expect(actedAsk(root, "idealic:kernel", "rc1", "x", { by: "idealic:stranger", ruledInChat: "me" })).rejects.toThrow();
  });
});
