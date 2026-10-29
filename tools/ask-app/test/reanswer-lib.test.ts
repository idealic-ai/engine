/**
 * IDE-304, the store's side of a changed answer: the asker is told the answer CHANGED and what it
 * replaced, and the file keeps a one-line `replaced:` trace. A re-push of a pending answer stays
 * distinguishable from a fresh change.
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { parseAskFile, replacedSummary, setHeaderField } from "../src/lib/format.ts";
import { answerAsk, newAsk, repushPending, saveDraft, sendBatch } from "../src/lib/store.ts";

let root: string;
beforeEach(() => {
  root = path.join(fs.mkdtempSync(path.join("/tmp", "asks-relib-")), "asks");
});
afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));

const SEAT = "manager:docs";
const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n\n## ¶ASK_WHY: Choose one: Why?\n- [ ] [A] a\n- [ ] [B] b\n";
const file = () => path.join(root, SEAT, "go.md");
const read = () => parseAskFile(fs.readFileSync(file(), "utf8"));
let pushes: { seat: string; content: string }[] = [];
const push = async (seat: string, content: string) => (pushes.push({ seat, content }), { status: "delivered" as const });
const OP = { answeredBy: "operator", answeredVia: "browser" };
const REQ = "request: proof:explore — map the doc trees first";

beforeEach(() => {
  pushes = [];
  newAsk(root, { from: SEAT, to: "operator", id: "go" }, BODY);
});

describe("answerAsk: a second answer is a change", () => {
  it("the first answer is a plain [ask-answer] and leaves no replaced: field", async () => {
    await answerAsk(root, SEAT, "go", { answers: { GO: ["YES"] }, ...OP }, { expectedRevision: 1, push });
    expect(pushes[0].content.split("\n")[0]).toBe(`[ask-answer] from operator via ask-app: ${SEAT}/go is answered`);
    expect(read().header.replaced).toBeUndefined();
  });

  it("the change push says CHANGED and what it replaced, and the file keeps a replaced: line", async () => {
    await answerAsk(root, SEAT, "go", { answers: { GO: ["YES"], WHY: ["A"] }, ...OP, answeredAt: "2026-10-30T01:00:00.000Z" }, { expectedRevision: 1, push });
    pushes = [];
    await answerAsk(root, SEAT, "go", { answers: { GO: ["NO"] }, ...OP }, { expectedRevision: 2, push });
    const lines = pushes[0].content.split("\n");
    expect(lines[0]).toBe(`[ask-answer-changed] from operator via ask-app: ${SEAT}/go is answered again; this answer replaces the earlier one`);
    expect(lines[1]).toBe("Replaced: revision 2 by operator at 2026-10-30T01:00:00.000Z; was GO YES, WHY A");
    expect(pushes[0].content).toContain("Ship it? → No");
    expect(read().header.replaced).toBe("revision 2 by operator at 2026-10-30T01:00:00.000Z; was GO YES, WHY A");
  });

  it("a replaced decline and a replaced request are named as such", async () => {
    await answerAsk(root, SEAT, "go", { declined: true, reason: "not now", ...OP, answeredAt: "2026-10-30T01:00:00.000Z" }, { expectedRevision: 1, push });
    await answerAsk(root, SEAT, "go", { answers: { GO: ["YES"] }, note: `${REQ}\nkeep handbook`, ...OP, answeredAt: "2026-10-30T02:00:00.000Z" }, { expectedRevision: 2, push });
    expect(pushes[1].content.split("\n")[1]).toBe("Replaced: revision 2 by operator at 2026-10-30T01:00:00.000Z; was a decline: not now");
    await answerAsk(root, SEAT, "go", { answers: { GO: ["NO"] }, ...OP }, { expectedRevision: 3, push });
    expect(read().header.replaced).toBe(`revision 3 by operator at 2026-10-30T02:00:00.000Z; was a request: proof:explore — map the doc trees first (with GO YES)`);
  });

  it("replacedSummary is undefined for an open ask", () => {
    expect(replacedSummary(read())).toBeUndefined();
  });
});

describe("sendBatch: a draft sent over an answer is a change too", () => {
  it("the batch push marks the changed item and the file keeps replaced:", async () => {
    await answerAsk(root, SEAT, "go", { answers: { GO: ["YES"] }, ...OP, answeredAt: "2026-10-30T01:00:00.000Z" }, { expectedRevision: 1, push });
    pushes = [];
    await saveDraft(root, SEAT, "go", { answers: { GO: ["NO"] }, ...OP }, 2);
    const out = await sendBatch(root, [`${SEAT}/go`], { by: "operator", push });
    expect(out.settled).toHaveLength(1);
    expect(pushes[0].content).toContain(`- [ask-answer-changed] ${SEAT}/go replaces revision 2 by operator at 2026-10-30T01:00:00.000Z; was GO YES`);
    expect(read().header.replaced).toBe("revision 2 by operator at 2026-10-30T01:00:00.000Z; was GO YES");
  });

  it("a first answer through the batch carries no change marker", async () => {
    await saveDraft(root, SEAT, "go", { answers: { GO: ["NO"] }, ...OP }, 1);
    await sendBatch(root, [`${SEAT}/go`], { by: "operator", push });
    expect(pushes[0].content).not.toContain("ask-answer-changed");
  });
});

describe("repushPending: a re-push is never mistaken for a fresh change", () => {
  it("a changed answer left pending by a dead writer is re-sent marked Re-sent", async () => {
    await answerAsk(root, SEAT, "go", { answers: { GO: ["YES"] }, ...OP }, { expectedRevision: 1, push });
    await answerAsk(root, SEAT, "go", { answers: { GO: ["NO"] }, ...OP }, { expectedRevision: 2, push });
    const fresh = pushes[1].content;
    pushes = [];
    // A writer that died between settling and stamping the delivery.
    let text = fs.readFileSync(file(), "utf8");
    text = setHeaderField(setHeaderField(text, "delivery", "pending"), "deliveryWriter", "999999@2026-10-30T01:00:00.000Z");
    fs.writeFileSync(file(), text);
    const out = await repushPending(root, { push });
    expect(out).toHaveLength(1);
    expect(pushes[0].content).not.toBe(fresh);
    expect(pushes[0].content).toContain("Re-sent: an earlier push of this answer may not have arrived; nothing changed since.");
    expect(pushes[0].content).toContain("Replaced: revision 2 by operator");
  });
});

describe("writeDraft: the operator may draft a change over their own answer", () => {
  it("an operator draft on an operator-answered ask is kept; the ask stays answered until it is sent", async () => {
    await answerAsk(root, SEAT, "go", { answers: { GO: ["YES"] }, ...OP }, { expectedRevision: 1, push });
    await saveDraft(root, SEAT, "go", { answers: { GO: ["NO"] }, ...OP }, 2);
    expect(read().header.status).toBe("answered");
    expect(read().draft?.answers).toEqual({ GO: ["NO"] });
    expect(read().answer?.answers).toEqual({ GO: ["YES"] });
  });

  it("is refused at a stale revision, on a seat-ruled answer, and for a seat", async () => {
    await answerAsk(root, SEAT, "go", { answers: { GO: ["YES"] }, ...OP }, { expectedRevision: 1, push });
    await expect(saveDraft(root, SEAT, "go", { answers: { GO: ["NO"] }, ...OP }, 1)).rejects.toThrow(/revision/i);
    newAsk(root, { from: SEAT, to: "manager:director", id: "ruled" }, BODY);
    await answerAsk(root, SEAT, "ruled", { answers: { GO: ["YES"] }, answeredBy: "manager:director" }, { expectedRevision: 1, push });
    await expect(saveDraft(root, SEAT, "ruled", { answers: { GO: ["NO"] }, ...OP }, 2)).rejects.toThrow(/only an open ask, or the operator's own answer, takes a draft/);
    newAsk(root, { from: SEAT, to: "manager:director", id: "own" }, BODY);
    await answerAsk(root, SEAT, "own", { answers: { GO: ["YES"] }, ...OP }, { expectedRevision: 1, push });
    await expect(saveDraft(root, SEAT, "own", { answers: { GO: ["NO"] }, answeredBy: "manager:director" }, 2)).rejects.toThrow(/only an open ask, or the operator's own answer, takes a draft/);
  });
});

describe("discardDraft on a settled ask", () => {
  it("drops the change draft and leaves the recorded answer", async () => {
    const { discardDraft } = await import("../src/lib/store.ts");
    await answerAsk(root, SEAT, "go", { answers: { GO: ["YES"] }, ...OP }, { expectedRevision: 1, push });
    await saveDraft(root, SEAT, "go", { answers: { GO: ["NO"] }, ...OP }, 2);
    await discardDraft(root, SEAT, "go", "operator");
    expect(read().draft).toBeUndefined();
    expect(read().answer?.answers).toEqual({ GO: ["YES"] });
    expect(read().header.status).toBe("answered");
  });
});
