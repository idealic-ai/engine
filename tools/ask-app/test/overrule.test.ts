/**
 * IDE-339 (server half): an operator's answer over a seat's settled answer is an OVERRULE — stamped
 * `overruled: <prior answerer>` and pushed as `[ask-overruled]` — every earlier answer is kept whole
 * in ONE ```json history``` fence, and a manager's answer may carry a grant class (A–D) that only the
 * CLI writes. Existing ask files (no history fence, no overruled header) read and settle as before.
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { bodyDigest, parseAskFile, STAMP_FIELDS, writeAnswer, writeDecline, writeDraft, type AskAnswer } from "../src/lib/format.ts";
import { answerAsk, batchMessage, deliveryMessage, newAsk, saveDraft } from "../src/lib/store.ts";
import { rewriteSeatRefs } from "../src/lib/rename-seat.ts";

const FIX = path.join(path.dirname(fileURLToPath(import.meta.url)), "fixtures");
const LEGACY = fs.readFileSync(path.join(FIX, "legacy-answered.md"), "utf8");
/** What settle() wrote for LEGACY before IDE-339 (captured from origin/main 9abeea6). */
const LEGACY_SETTLED_BEFORE = fs.readFileSync(path.join(FIX, "legacy-answered.settled-before.md"), "utf8");
/** The settled text with its history block (and the blank line settle() puts before it) taken out. */
const stripHistory = (t: string) => t.replace(/\n```json history\n[\s\S]*?\n```\n/, "");
const historyFenceCount = (t: string) => (t.match(/^```json history$/gm) ?? []).length;

describe("compatibility: an ask written before IDE-339", () => {
  it("reads as before: same header, questions and answer, an empty history, no overruled", () => {
    const a = parseAskFile(LEGACY);
    expect(a.history).toEqual([]);
    expect(a.header.overruled).toBeUndefined();
    expect(a.answer?.answeredBy).toBe("manager:core");
    expect(a.answer?.revision).toBe(2);
    expect(a.questions.map((q) => q.askName)).toEqual(["RESUMELANES", "NOCHECKOUT"]);
    expect(bodyDigest(LEGACY)).toBe("a7a7a3d9");
  });

  it("settles by its own answerer exactly as before, plus one history fence holding the prior record", () => {
    const out = writeAnswer(LEGACY, { answers: { RESUMELANES: ["DECLINE"] }, answeredBy: "manager:core", answeredVia: "cli", answeredAt: "2026-10-30T00:00:00.000Z" }, 2);
    expect(stripHistory(out)).toBe(LEGACY_SETTLED_BEFORE);
    expect(historyFenceCount(out)).toBe(1);
    const a = parseAskFile(out);
    expect(a.header.overruled).toBeUndefined();
    expect(a.history).toEqual([parseAskFile(LEGACY).answer]);
    expect(a.answer?.revision).toBe(3);
  });
});

const ASK = `---
id: go
to: manager:docs
from: docs:handbook
status: open
revision: 1
---

## ¶ASK_GO: Choose one: Ship it?
- [ ] [YES] Yes
- [ ] [NO] No
`;
const SEAT_A: AskAnswer = { answers: { GO: ["YES"] }, answeredBy: "manager:docs", answeredVia: "cli", answeredAt: "2026-10-30T01:00:00.000Z" };
const OP_A: AskAnswer = { answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: "browser", answeredAt: "2026-10-30T02:00:00.000Z" };

describe("settle: overruled", () => {
  it("is stamped with the prior answerer when a different answerer replaces the answer", () => {
    const t1 = writeAnswer(ASK, SEAT_A, 1);
    expect(parseAskFile(t1).header.overruled).toBeUndefined();
    const t2 = writeAnswer(t1, OP_A, 2);
    expect(parseAskFile(t2).header.overruled).toBe("manager:docs");
    expect(parseAskFile(t2).header.replaced).toContain("by manager:docs");
  });

  it("is cleared when the same answerer changes its answer again", () => {
    const t2 = writeAnswer(writeAnswer(ASK, SEAT_A, 1), OP_A, 2);
    const t3 = writeAnswer(t2, { ...OP_A, answers: { GO: ["YES"] } }, 3);
    expect(parseAskFile(t3).header.overruled).toBeUndefined();
  });

  it("is never stamped on a self-change", () => {
    const t2 = writeAnswer(writeAnswer(ASK, SEAT_A, 1), { ...SEAT_A, answers: { GO: ["NO"] } }, 2);
    expect(parseAskFile(t2).header.overruled).toBeUndefined();
    expect(t2).not.toMatch(/^overruled:/m);
  });

  it("a decline over a seat's answer by the operator overrules too", () => {
    const t2 = writeDecline(writeAnswer(ASK, SEAT_A, 1), { reason: "not now", answeredBy: "operator", answeredVia: "browser" }, 2);
    expect(parseAskFile(t2).header.overruled).toBe("manager:docs");
  });

  it("is a store-written stamp", () => {
    expect(STAMP_FIELDS).toContain("overruled");
  });
});

describe("settle: history", () => {
  it("keeps every prior answer whole, oldest first, in ONE fence before the answer fence", () => {
    const t1 = writeAnswer(ASK, SEAT_A, 1);
    const t2 = writeAnswer(t1, OP_A, 2);
    const t3 = writeAnswer(t2, { ...OP_A, answers: { GO: ["YES"] }, note: "changed my mind" }, 3);
    const a = parseAskFile(t3);
    expect(a.history).toEqual([{ ...SEAT_A, revision: 2 }, { ...OP_A, revision: 3 }]);
    expect(a.answer?.revision).toBe(4);
    expect(a.answer?.note).toBe("changed my mind");
    expect(historyFenceCount(t3)).toBe(1);
    expect(t3.indexOf("```json history")).toBeLessThan(t3.indexOf("```json answer"));
    expect(t3.trimEnd().endsWith("```")).toBe(true);
  });

  it("a first answer writes no history fence", () => {
    const t1 = writeAnswer(ASK, SEAT_A, 1);
    expect(historyFenceCount(t1)).toBe(0);
    expect(parseAskFile(t1).history).toEqual([]);
  });

  it("bodyDigest ignores the history fence, as it ignores the answer fence", () => {
    const t3 = writeAnswer(writeAnswer(writeAnswer(ASK, SEAT_A, 1), OP_A, 2), OP_A, 3);
    expect(bodyDigest(t3)).toBe(bodyDigest(ASK));
  });

  it("the history fence is not body: the questions parse the same", () => {
    const t3 = writeAnswer(writeAnswer(ASK, SEAT_A, 1), OP_A, 2);
    expect(parseAskFile(t3).questions).toEqual(parseAskFile(ASK).questions);
    expect(parseAskFile(t3).preamble).toBe(parseAskFile(ASK).preamble);
  });

  it("an operator's draft on its own answer is still honoured after a history fence", () => {
    const t2 = writeAnswer(writeAnswer(ASK, SEAT_A, 1), OP_A, 2);
    const d = writeDraft(t2, { answers: { GO: ["YES"] }, answeredBy: "operator", savedAt: "2026-10-30T03:00:00.000Z" }, 3);
    expect(parseAskFile(d).draft?.answers).toEqual({ GO: ["YES"] });
    expect(parseAskFile(d).history).toHaveLength(1);
  });
});

// ── the store: pushes and the grant class ─────────────────

let root: string;
let pushes: { seat: string; content: string }[] = [];
const push = async (seat: string, content: string) => (pushes.push({ seat, content }), { status: "delivered" as const });
const SEAT = "docs:handbook";
const MGR = "manager:docs";
const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n";
const fileOf = (id: string) => path.join(root, SEAT, `${id}.md`);
const readAsk = (id: string) => parseAskFile(fs.readFileSync(fileOf(id), "utf8"));
beforeEach(() => {
  root = path.join(fs.mkdtempSync(path.join("/tmp", "asks-overrule-")), "asks");
  pushes = [];
  newAsk(root, { from: SEAT, to: MGR, id: "go" }, BODY);
});
afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));

describe("the push: [ask-overruled]", () => {
  it("leads with [ask-overruled] when the operator overrules a seat, and keeps Replaced:", async () => {
    await answerAsk(root, SEAT, "go", { answers: { GO: ["YES"] }, answeredBy: MGR, answeredVia: "cli", answeredAt: "2026-10-30T01:00:00.000Z" }, { expectedRevision: 1, push });
    pushes = [];
    await answerAsk(root, SEAT, "go", { answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: "browser" }, { expectedRevision: 2, push });
    const lines = pushes.find((p) => p.seat === SEAT)!.content.split("\n");
    expect(lines[0]).toBe(`[ask-overruled] from operator via ask-app: ${SEAT}/go is answered again; this answer overrules ${MGR}'s`);
    expect(lines[1]).toBe(`Replaced: revision 2 by ${MGR} at 2026-10-30T01:00:00.000Z; was GO YES`);
    expect(pushes.map((p) => p.content).join("\n")).not.toContain("[ask-answer-changed]");
    expect(readAsk("go").header.overruled).toBe(MGR);
  });

  it("a seat changing its own answer is still [ask-answer-changed]", async () => {
    await answerAsk(root, SEAT, "go", { answers: { GO: ["YES"] }, answeredBy: MGR, answeredVia: "cli" }, { expectedRevision: 1, push });
    pushes = [];
    await answerAsk(root, SEAT, "go", { answers: { GO: ["NO"] }, answeredBy: MGR, answeredVia: "cli" }, { expectedRevision: 2, push });
    expect(pushes[0].content.split("\n")[0]).toMatch(/^\[ask-answer-changed\] /);
    expect(readAsk("go").header.overruled).toBeUndefined();
  });

  it("deliveryMessage and batchMessage name the overrule", () => {
    const m = deliveryMessage(SEAT, "go", "/f", { answeredBy: "operator", revision: 3 }, [], { replaced: "revision 2 by x; was A", overruled: "x" });
    expect(m.split("\n").slice(0, 2)).toEqual([`[ask-overruled] from operator via ask-app: ${SEAT}/go is answered again; this answer overrules x's`, "Replaced: revision 2 by x; was A"]);
    const b = batchMessage(SEAT, "operator", [{ ref: `${SEAT}/go`, file: "/f", lines: [], replaced: "revision 2 by x; was A", overruled: "x" }]);
    expect(b).toContain(`- [ask-overruled] ${SEAT}/go overrules x; replaces revision 2 by x; was A`);
    expect(b).not.toContain("[ask-answer-changed]");
  });
});

describe("grantClass", () => {
  it("a manager's answer records the grant class it was given", async () => {
    await answerAsk(root, SEAT, "go", { answers: { GO: ["YES"] }, answeredBy: MGR, answeredVia: "cli", grantClass: "B" }, { expectedRevision: 1, push });
    expect(readAsk("go").answer?.grantClass).toBe("B");
  });

  it("is refused when the answerer is the operator", async () => {
    await expect(answerAsk(root, SEAT, "go", { answers: { GO: ["YES"] }, answeredBy: "operator", answeredVia: "cli", grantClass: "A" }, { expectedRevision: 1, push })).rejects.toThrow(/grant class/);
    expect(readAsk("go").header.status).toBe("open");
  });

  it("is refused on a reserved-for ask", async () => {
    newAsk(root, { from: SEAT, to: MGR, id: "res", "reserved-for": MGR }, BODY);
    await expect(answerAsk(root, SEAT, "res", { answers: { GO: ["YES"] }, answeredBy: MGR, answeredVia: "cli", grantClass: "C" }, { expectedRevision: 1, push })).rejects.toThrow(/reserved/);
    expect(readAsk("res").header.status).toBe("open");
  });

  it("only A, B, C or D", async () => {
    await expect(answerAsk(root, SEAT, "go", { answers: { GO: ["YES"] }, answeredBy: MGR, answeredVia: "cli", grantClass: "E" as never }, { expectedRevision: 1, push })).rejects.toThrow(/A, B, C or D/);
  });

  it("is never drafted", async () => {
    await expect(saveDraft(root, SEAT, "go", { answers: { GO: ["YES"] }, answeredBy: MGR, grantClass: "A" }, 1)).rejects.toThrow(/grant class/);
  });

  it("an answer without one carries no grantClass key", async () => {
    await answerAsk(root, SEAT, "go", { answers: { GO: ["YES"] }, answeredBy: MGR, answeredVia: "cli" }, { expectedRevision: 1, push });
    expect(fs.readFileSync(fileOf("go"), "utf8")).not.toContain("grantClass");
  });
});

describe("rename-seat: the history fence", () => {
  it("rewrites answeredBy, readBy, relayedFrom and actedBy inside the history fence, and the overruled stamp", () => {
    const t1 = writeAnswer(ASK, { ...SEAT_A, readBy: "manager:docs", relayedFrom: "manager:docs", actedBy: "manager:docs" } as AskAnswer, 1);
    const t2 = writeAnswer(t1, OP_A, 2);
    const { text, changes } = rewriteSeatRefs(t2, "manager:docs", "manager:handbook");
    const a = parseAskFile(text);
    const h = a.history[0] as Record<string, unknown>;
    expect(h.answeredBy).toBe("manager:handbook");
    expect(h.readBy).toBe("manager:handbook");
    expect(h.relayedFrom).toBe("manager:handbook");
    expect(h.actedBy).toBe("manager:handbook");
    expect(a.header.overruled).toBe("manager:handbook");
    expect(changes.map((c) => c.field)).toEqual(expect.arrayContaining(["history.answeredBy", "history.readBy", "history.relayedFrom", "history.actedBy", "overruled"]));
    expect(text).not.toContain('"manager:docs"');
  });
});
