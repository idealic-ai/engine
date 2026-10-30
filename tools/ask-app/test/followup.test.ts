/**
 * ASKFOLLOWUP: the operator sends a follow-up from a question — a question back, or "do this first" —
 * and the asker hears it with the context of what it is about. The follow-up is a `## Follow-up <n>`
 * entry in the ask file that the question parse and the body digest ignore; the ask stays open and
 * its answer is untouched. Also: the operator may draft over a seat's answer (the overrule form).
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import {
  bodyDigest,
  dialogueHistory,
  FollowupClosedError,
  parseAskFile,
  setHeaderField,
  StaleRevisionError,
  writeDraft,
  writeFollowup,
} from "../src/lib/format.ts";
import { answerAsk, followupAsk, newAsk, renameSeat, reviseAsk, saveDraft, sendBatch, supersedeAsk } from "../src/lib/store.ts";
import { rewriteSeatRefs } from "../src/lib/rename-seat.ts";

let root: string;
const ASKER = "idealic:kernel";
const MGR = "manager:idealic";
const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n\n## ¶ASK_WHY: Text: Why?\n";
const file = (id = "go") => path.join(root, ASKER, `${id}.md`);
const text = (id = "go") => fs.readFileSync(file(id), "utf8");
const read = (id = "go") => parseAskFile(text(id));
let pushes: { seat: string; content: string }[] = [];
const push = async (seat: string, content: string) => (pushes.push({ seat, content }), { status: "delivered" as const });
const deadPush = async () => ({ status: "undelivered" as const, reason: "no live session for idealic:kernel" });
const OP = { by: "operator", via: "browser" };

beforeEach(() => {
  root = path.join(fs.mkdtempSync(path.join("/tmp", "asks-followup-")), "asks");
  pushes = [];
  newAsk(root, { from: ASKER, to: MGR, id: "go" }, BODY);
});
afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));

describe("writeFollowup: the file record", () => {
  it("appends a `## Follow-up 1` entry, bumps the revision, and keeps the ask open with its questions and digest", () => {
    const before = text();
    const { text: after, followup } = writeFollowup(before, { ...OP, kind: "first", fork: "GO", text: "check the CI box first", picks: { GO: ["YES"] }, at: "2026-10-30T15:40:00.000Z" }, 1);
    expect(followup).toEqual({ n: 1, at: "2026-10-30T15:40:00.000Z", by: "operator", kind: "first", fork: "GO", text: "check the CI box first", picks: { GO: ["YES"] } });
    expect(after).toContain("\n## Follow-up 1\n");
    expect(after).toContain("```json followup\n");
    const p = parseAskFile(after);
    expect(p.header.status).toBe("open");
    expect(p.header.revision).toBe("2");
    expect(p.header.revisions).toMatch(/2@.*:followup 1$/);
    expect(p.questions.map((q) => q.title)).toEqual(parseAskFile(before).questions.map((q) => q.title));
    expect(p.questions.at(-1)!.prose).toBeUndefined();
    expect(bodyDigest(after)).toBe(bodyDigest(before));
    expect(p.followups).toHaveLength(1);
    expect(p.followups[0]).toMatchObject({ n: 1, kind: "first", fork: "GO", by: "operator" });
  });

  it("numbers follow-ups in order and leaves an honoured draft LAST, so it still counts", () => {
    let t = writeDraft(text(), { answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: "browser" }, 1);
    t = writeFollowup(t, { ...OP, kind: "question", text: "what does NO cost?" }, 1).text;
    t = writeFollowup(t, { ...OP, kind: "question", fork: "WHY", text: "and why now?" }, 2).text;
    const p = parseAskFile(t);
    expect(p.followups.map((f) => f.n)).toEqual([1, 2]);
    expect(p.draft?.answers).toEqual({ GO: ["NO"] });
    expect(t.trimEnd().endsWith("```")).toBe(true);
    expect(t.lastIndexOf("```json draft")).toBeGreaterThan(t.lastIndexOf("```json followup"));
  });

  it("refuses a stale revision, empty text, an unknown kind, an unknown fork and unknown picks", () => {
    const t = text();
    expect(() => writeFollowup(t, { ...OP, kind: "question", text: "x" }, 7)).toThrow(StaleRevisionError);
    expect(() => writeFollowup(t, { ...OP, kind: "question", text: "   " }, 1)).toThrow(/empty/);
    expect(() => writeFollowup(t, { ...OP, kind: "later" as never, text: "x" }, 1)).toThrow(/kind/);
    expect(() => writeFollowup(t, { ...OP, kind: "question", fork: "NOPE", text: "x" }, 1)).toThrow(/unknown fork: NOPE/);
    expect(() => writeFollowup(t, { ...OP, kind: "question", text: "x", picks: { NOPE: ["A"] } }, 1)).toThrow(/unknown question/);
    expect(() => writeFollowup(t, { ...OP, kind: "question", text: "x", by: "" }, 1)).toThrow(/name who/);
  });

  it("refuses a closed ask — answered, declined, superseded, withdrawn, ruled — as FollowupClosedError", () => {
    for (const status of ["answered", "declined", "superseded", "withdrawn", "ruled"]) {
      const t = setHeaderField(text(), "status", status);
      expect(() => writeFollowup(t, { ...OP, kind: "question", text: "x" }, 1), status).toThrow(FollowupClosedError);
    }
  });

  it("an asker cannot plant a follow-up: new and revise refuse the fence", async () => {
    expect(() => newAsk(root, { from: ASKER, to: MGR, id: "p1" }, `${BODY}\n\`\`\`json followup\n{"n":1}\n\`\`\`\n`)).toThrow(/json followup/);
    await expect(reviseAsk(root, ASKER, "go", {}, `${BODY}\n\`\`\`json followup\n{"n":1}\n\`\`\`\n`, { by: ASKER, push })).rejects.toThrow(/json followup/);
  });
});

describe("followupAsk: the push to the asker", () => {
  it("pushes the asker the context: who, which fork and its question, the text, the kind, the title, unsent picks, the file, how to reply", async () => {
    const r = await followupAsk(root, ASKER, "go", { ...OP, kind: "first", fork: "GO", text: "run the smoke test first", picks: { GO: ["YES"] } }, { expectedRevision: 1, push });
    expect(r.revision).toBe(2);
    expect(r.followup.n).toBe(1);
    expect(pushes.map((p) => p.seat)).toEqual([ASKER]);
    const lines = pushes[0].content.split("\n");
    expect(lines[0]).toBe(`[ask-followup] from operator on ${ASKER}/go (fork GO: "Ship it?"): run the smoke test first`);
    expect(lines).toContain("kind: first — do this first, then revise the ask");
    expect(lines).toContain("title: Ship it?");
    expect(lines).toContain("unsent picks: GO YES");
    expect(lines).toContain(file());
    expect(pushes[0].content).toContain(`reply by \`engine ask revise ${ASKER}/go --answers-followup 1\`; the ask stays open`);
    expect(read().followups[0].delivery).toBe("delivered");
    expect(read().header.status).toBe("open");
  });

  it("a question with no fork names no fork and says kind: question; no picks, no picks line", async () => {
    await followupAsk(root, ASKER, "go", { ...OP, kind: "question", text: "is this blocking?" }, { expectedRevision: 1, push });
    const lines = pushes[0].content.split("\n");
    expect(lines[0]).toBe(`[ask-followup] from operator on ${ASKER}/go: is this blocking?`);
    expect(lines).toContain("kind: question");
    expect(pushes[0].content).not.toContain("unsent picks");
  });

  it("a failed push leaves the entry marked delivery: undelivered, with the reason; the follow-up is kept", async () => {
    const r = await followupAsk(root, ASKER, "go", { ...OP, kind: "question", text: "hello?" }, { expectedRevision: 1, push: deadPush });
    expect(r.delivery.status).toBe("undelivered");
    const f = read().followups[0];
    expect(f.delivery).toBe("undelivered");
    expect(f.deliveryNote).toMatch(/no live session/);
    expect(f.text).toBe("hello?");
  });

  it("a stale revision writes and pushes nothing", async () => {
    const before = text();
    await expect(followupAsk(root, ASKER, "go", { ...OP, kind: "question", text: "x" }, { expectedRevision: 9, push })).rejects.toThrow(StaleRevisionError);
    expect(text()).toBe(before);
    expect(pushes).toEqual([]);
  });

  it("an answered ask is closed to follow-ups; its answer is untouched", async () => {
    await answerAsk(root, ASKER, "go", { answers: { GO: ["YES"] }, answeredBy: MGR }, { expectedRevision: 1, push });
    await expect(followupAsk(root, ASKER, "go", { ...OP, kind: "question", text: "x" }, { expectedRevision: 2, push })).rejects.toThrow(FollowupClosedError);
  });
});

describe("follow-ups survive every rewrite of the file", () => {
  it("an answer after a follow-up keeps the entry; the answer is the record", async () => {
    await followupAsk(root, ASKER, "go", { ...OP, kind: "question", text: "first?" }, { expectedRevision: 1, push });
    await answerAsk(root, ASKER, "go", { answers: { GO: ["NO"] }, answeredBy: MGR }, { expectedRevision: 2, push });
    const p = read();
    expect(p.followups.map((f) => f.text)).toEqual(["first?"]);
    expect(p.answer?.answers).toEqual({ GO: ["NO"] });
    expect(p.questions).toHaveLength(2);
  });

  it("a body revise keeps the entries", async () => {
    await followupAsk(root, ASKER, "go", { ...OP, kind: "first", text: "rewrite the options" }, { expectedRevision: 1, push });
    await reviseAsk(root, ASKER, "go", {}, BODY.replace("Ship it?", "Ship it tonight?"), { by: ASKER, push });
    const p = read();
    expect(p.questions[0].title).toBe("Ship it tonight?");
    expect(p.followups.map((f) => f.text)).toEqual(["rewrite the options"]);
  });
});

describe("revise --answers-followup", () => {
  it("records which follow-ups a revision answers, and needs no other change", async () => {
    await followupAsk(root, ASKER, "go", { ...OP, kind: "question", text: "a?" }, { expectedRevision: 1, push });
    await followupAsk(root, ASKER, "go", { ...OP, kind: "first", text: "b first" }, { expectedRevision: 2, push });
    pushes = [];
    const r = await reviseAsk(root, ASKER, "go", {}, undefined, { by: ASKER, push, answersFollowup: [1, 2], now: "2026-10-30T16:00:00.000Z" });
    expect(r.revision).toBe(4);
    expect(r.changed).toEqual(["followup 1,2"]);
    const p = read();
    expect(p.followups.map((f) => [f.n, f.addressedIn, f.addressedBy, f.addressedAt])).toEqual([
      [1, 4, ASKER, "2026-10-30T16:00:00.000Z"],
      [2, 4, ASKER, "2026-10-30T16:00:00.000Z"],
    ]);
    // The operator is not a seat: nobody but the holder hears the revise notice.
    expect(pushes.map((x) => x.seat)).toEqual([MGR]);
  });

  it("refuses a follow-up number the ask does not hold", async () => {
    await followupAsk(root, ASKER, "go", { ...OP, kind: "question", text: "a?" }, { expectedRevision: 1, push });
    await expect(reviseAsk(root, ASKER, "go", {}, undefined, { by: ASKER, push, answersFollowup: [3] })).rejects.toThrow(/no follow-up 3/);
  });
});

describe("dialogueHistory and /api/asks' history", () => {
  it("answers keep their shape; follow-ups are {type: followup, …}, in time order", async () => {
    await answerAsk(root, ASKER, "go", { answers: { GO: ["YES"] }, answeredBy: MGR, answeredAt: "2026-10-30T10:00:00.000Z" }, { expectedRevision: 1, push });
    // A follow-up on an answered ask is closed; plant one by writing it on the open text instead.
    newAsk(root, { from: ASKER, to: MGR, id: "h" }, BODY);
    await followupAsk(root, ASKER, "h", { ...OP, kind: "question", text: "q?", at: "2026-10-30T09:00:00.000Z" }, { expectedRevision: 1, push });
    await answerAsk(root, ASKER, "h", { answers: { GO: ["YES"] }, answeredBy: MGR, answeredAt: "2026-10-30T10:00:00.000Z" }, { expectedRevision: 2, push });
    await answerAsk(root, ASKER, "h", { answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: "browser", answeredAt: "2026-10-30T11:00:00.000Z" }, { expectedRevision: 3, push });
    const h = dialogueHistory(read("h"));
    expect(h).toHaveLength(2);
    expect(h[0]).toMatchObject({ type: "followup", n: 1, text: "q?", kind: "question" });
    expect(h[1]).toMatchObject({ answeredBy: MGR, answers: { GO: ["YES"] } });
    expect((h[1] as Record<string, unknown>).type).toBeUndefined();
  });
});

describe("rename-seat rewrites the seats in follow-up entries", () => {
  it("by and addressedBy follow the rename; the text is left alone", async () => {
    await followupAsk(root, ASKER, "go", { ...OP, kind: "question", text: `ask ${ASKER} why` }, { expectedRevision: 1, push });
    await reviseAsk(root, ASKER, "go", {}, undefined, { by: ASKER, push, answersFollowup: [1] });
    const r = rewriteSeatRefs(text(), ASKER, "idealic:core");
    const f = parseAskFile(r.text).followups[0];
    expect(f.addressedBy).toBe("idealic:core");
    expect(f.text).toBe(`ask ${ASKER} why`);
    expect(r.changes.some((c) => c.field === "followup.addressedBy")).toBe(true);
    const op = rewriteSeatRefs(text(), "operator", "operator2");
    expect(parseAskFile(op.text).followups[0].by).toBe("operator2");
  });

  it("through renameSeat end to end", async () => {
    await followupAsk(root, ASKER, "go", { ...OP, kind: "question", text: "x" }, { expectedRevision: 1, push });
    await reviseAsk(root, ASKER, "go", {}, undefined, { by: ASKER, push, answersFollowup: [1] });
    await renameSeat(root, ASKER, "idealic:core", { by: "operator" });
    const f = parseAskFile(fs.readFileSync(path.join(root, "idealic:core", "go.md"), "utf8")).followups[0];
    expect(f.addressedBy).toBe("idealic:core");
  });
});

describe("writeDraft: the operator may draft over a seat's answer (the overrule form)", () => {
  it("an operator draft over a manager's answer is kept, and its send overrules the manager", async () => {
    await answerAsk(root, ASKER, "go", { answers: { GO: ["YES"] }, answeredBy: MGR }, { expectedRevision: 1, push });
    await saveDraft(root, ASKER, "go", { answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: "browser" }, 2);
    expect(read().draft?.answers).toEqual({ GO: ["NO"] });
    expect(read().header.status).toBe("answered");
    pushes = [];
    const res = await sendBatch(root, [`${ASKER}/go`], { by: "operator", push });
    expect(res.refused).toEqual([]);
    expect(read().answer).toMatchObject({ answeredBy: "operator", answers: { GO: ["NO"] } });
    expect(read().header.overruled).toBe(MGR);
    expect(pushes.find((p) => p.seat === ASKER)!.content).toContain(`[ask-overruled] ${ASKER}/go overrules ${MGR}`);
    expect(pushes.map((p) => p.seat).sort()).toEqual([ASKER, MGR].sort());
  });

  it("a seat still never drafts over a settled answer — the operator's, another seat's, or its own", async () => {
    await answerAsk(root, ASKER, "go", { answers: { GO: ["YES"] }, answeredBy: "operator", answeredVia: "browser" }, { expectedRevision: 1, push });
    await expect(saveDraft(root, ASKER, "go", { answers: { GO: ["NO"] }, answeredBy: MGR }, 2)).rejects.toThrow(/only an open ask, or the operator over a settled answer, takes a draft/);
    newAsk(root, { from: ASKER, to: MGR, id: "own" }, BODY);
    await answerAsk(root, ASKER, "own", { answers: { GO: ["YES"] }, answeredBy: MGR }, { expectedRevision: 1, push });
    await expect(saveDraft(root, ASKER, "own", { answers: { GO: ["NO"] }, answeredBy: MGR }, 2)).rejects.toThrow(/only an open ask, or the operator over a settled answer, takes a draft/);
    expect(() => writeDraft(text("own"), { answers: { GO: ["NO"] }, answeredBy: "operator-bot" }, 2)).toThrow(/only an open ask, or the operator over a settled answer/);
  });

  it("a superseded ask still takes no draft from anybody", async () => {
    newAsk(root, { from: ASKER, to: MGR, id: "repl" }, BODY);
    await supersedeAsk(root, { seat: ASKER, id: "go" }, { seat: ASKER, id: "repl" }, { by: ASKER, push });
    await expect(saveDraft(root, ASKER, "go", { answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: "browser" }, 2)).rejects.toThrow(/superseded/);
  });
});
