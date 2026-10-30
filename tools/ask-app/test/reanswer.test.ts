/**
 * IDE-304: the operator changes an answer they already gave. A settled or provisional ask whose
 * recorded answer is the operator's own shows "Change answer"; the open form's full set of sends
 * reopens pre-filled, through the same code paths (clickPlan's confirms, /api/draft then /api/send).
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { parseAskFile } from "../src/lib/format.ts";
import { actedAsk, answerAsk, newAsk, readAsk } from "../src/lib/store.ts";
import { isProvisional } from "../src/client/loop.ts";
import { askRow, rowInFilter } from "../src/client/model.ts";
import { clearUnsent, saveUnsent } from "../src/client/unsent.ts";
import { CHANGE_WORDING, cancelDiscards, changeAnswerStart, draftBody, followUpOf, mayChangeAnswer, planClick, requestSend, staleChangeKeys, unsentKey } from "../src/client/reanswer.ts";

const head = (extra = "", status = "answered", id = "a1", created = "2026-10-29T10:00:00.000Z") =>
  `---\nid: ${id}\nto: operator\nfrom: manager:docs\nstatus: ${status}\nrevision: 4\ncreated: ${created}\n${extra}---\n\n`;
const BODY = "## ¶ASK_Q1: Choose one: Where?\nContext: c\n- [ ] [HB] handbook\n  Picks HB.\n- [ ] [DOCS] docs\n  Picks DOCS.\n\n## ¶ASK_Q2: Choose one: Second?\nContext: c\n- [ ] [P] p\n  Picks P.\n- [ ] [Q] q\n  Picks Q.\n";
const block = (a: object) => `\n\`\`\`json answer\n${JSON.stringify(a)}\n\`\`\`\n`;
const stored = (text: string) => ({ ...parseAskFile(text), seat: "manager:docs", file: "/x.md", mtimeMs: 0 });
const NOW = Date.parse("2026-10-29T13:00:00.000Z");

const REQ = "request: proof:explore — map the doc trees first";
const provisional = stored(head() + BODY + block({ answers: { Q1: ["HB"], "Q2.other": REQ }, note: `${REQ}\nkeep handbook`, answeredBy: "operator", answeredVia: "browser", answeredAt: "2026-10-29T19:30:00.000Z", revision: 4 }));
const plain = stored(head() + BODY + block({ answers: { Q1: ["DOCS"], Q2: ["P"] }, note: "fine", answeredBy: "operator", answeredVia: "browser", revision: 4 }));
const declined = stored(head("", "declined") + BODY + block({ declined: true, reason: "not mine to rule", answeredBy: "operator", answeredVia: "browser", revision: 4 }));
const capital = stored(head() + BODY + block({ answers: { Q1: ["DOCS"] }, answeredBy: "Operator", revision: 4 }));
const ruled = stored(head() + BODY + block({ answers: { Q1: ["DOCS"] }, answeredBy: "manager:director", revision: 4 }));
const superseded = stored(head("superseded-by: manager:docs/a2\n", "superseded") + BODY + block({ answers: { Q1: ["HB"] }, answeredBy: "operator", revision: 4 }));
const openAsk = stored(head("", "open") + BODY);

async function render(ask: ReturnType<typeof stored>, extra: Record<string, unknown> = {}, all = [ask]) {
  const { AskDetail } = await import("../src/client/App.tsx");
  return renderToStaticMarkup(createElement(AskDetail, { ask, all, onChanged: () => {}, ...extra }));
}

describe("which asks offer Change answer", () => {
  it("the operator's own answer does (any case, as ruledBelow reads it); a seat-ruled, superseded or open ask does not", () => {
    expect(isProvisional(provisional)).toBe(true);
    // IDE-339: a seat-ruled ask is now offered too, as Overrule (overrule-client.test.ts covers the button).
    for (const a of [provisional, plain, declined, capital, ruled]) expect(mayChangeAnswer(a)).toBe(true);
    for (const a of [superseded, openAsk]) expect(mayChangeAnswer(a)).toBe(false);
  });

  it("the answer bar shows the button on the operator's answers and not elsewhere", async () => {
    for (const a of [provisional, plain, declined]) expect(await render(a)).toMatch(/<button[^>]*>Change answer<\/button>/);
    for (const a of [ruled, superseded, openAsk]) expect(await render(a)).not.toContain("Change answer");
  });
});

describe("the reopened form", () => {
  it("starts from the recorded picks and note without the loop lines; a decline starts from its reason", () => {
    expect(changeAnswerStart(provisional)).toEqual({ values: { Q1: ["HB"] }, text: {}, note: "keep handbook" });
    expect(changeAnswerStart(plain)).toEqual({ values: { Q1: ["DOCS"], Q2: ["P"] }, text: {}, note: "fine" });
    expect(changeAnswerStart(declined)).toEqual({ values: {}, text: {}, note: "not mine to rule" });
  });

  it("starts from the operator's saved change draft when there is one", () => {
    const withDraft = stored(
      head("draft: 2026-10-29T20:00:00.000Z\n") + BODY + block({ answers: { Q1: ["HB"] }, answeredBy: "operator", revision: 4 }) +
        '\n```json draft\n{"answers":{"Q1":["DOCS"]},"note":"second thoughts","answeredBy":"operator","basedOn":4,"savedAt":"2026-10-29T20:00:00.000Z"}\n```\n',
    );
    expect(withDraft.draft?.answers).toEqual({ Q1: ["DOCS"] });
    expect(changeAnswerStart(withDraft)).toEqual({ values: { Q1: ["DOCS"] }, text: {}, note: "second thoughts" });
  });

  it("renders pre-filled and editable, with the open form's full set of sends plus Cancel", async () => {
    const html = await render(provisional, { startChanging: true });
    expect(html).toContain("Change your answer · revision 4");
    expect(html).toMatch(/<input type="radio"[^>]*aria-checked="true" checked=""\/><span class="opt-body"><span class="opt-label"><code class="okey">HB<\/code>/);
    expect(html).not.toMatch(/type="radio"[^>]*disabled=""/);
    expect(html).toMatch(/<textarea id="change-note-a1"[^>]*>keep handbook<\/textarea>/);
    expect(html).not.toContain(`id="note-a1"`);
    expect(html).not.toContain("request: proof:explore");
    expect(html).toContain(CHANGE_WORDING);
    for (const b of ["Send 1 answer", "Send as draft", "Need something first ▾", "Save draft", "Draft a decline", "Cancel"]) expect(html).toMatch(new RegExp(`<button[^>]*>${b}</button>`));
    expect(html).not.toContain("Waiting on the asker: draft sent");
  });

  it("the wording is honest: it replaces the answer, the asker hears it changed, unread", () => {
    expect(CHANGE_WORDING).toMatch(/replaces your earlier answer/);
    expect(CHANGE_WORDING).toMatch(/told the answer changed/);
    expect(CHANGE_WORDING).toMatch(/unread/);
  });
});

describe("what a change sends (the handlers' decisions, as pure functions)", () => {
  it("draftBody sends the EDITED picks and the plain note at the card's revision, never the recorded ones", () => {
    const edited = { Q1: ["DOCS"] };
    expect(draftBody(provisional, "send-now", { answers: edited, note: `${REQ}\nchanged` })).toEqual({ seat: "manager:docs", id: "a1", expectedRevision: 4, note: "changed", answers: { Q1: ["DOCS"] } });
    expect(draftBody(declined, "draft-decline", { answers: {}, note: "still not mine" })).toEqual({ seat: "manager:docs", id: "a1", expectedRevision: 4, note: "still not mine", decline: "still not mine" });
  });

  it("a partial change gets the same confirm as a partial open send; a full one does not", () => {
    const visible = provisional.questions;
    const p = planClick("send", { ask: provisional, answers: { Q1: ["HB"] }, visible, provisionalKept: true });
    expect(p.confirm).toMatch(/^1 question unanswered \(Q2\) — send anyway\?/);
    expect(planClick("send", { ask: provisional, answers: { Q1: ["HB"], Q2: ["P"] }, visible, provisionalKept: true })).toEqual({});
    // Send as draft is partial on purpose: no "unanswered" confirm.
    expect(planClick("draft", { ask: provisional, answers: { Q1: ["HB"] }, visible, provisionalKept: true })).toEqual({});
  });

  it("changing only the request on a provisional ask keeps the picks and replaces the request line", () => {
    const s = changeAnswerStart(provisional);
    expect(requestSend(provisional, s.values, s.note, "council:critique", "critique the outline")).toEqual({
      answers: { Q1: ["HB"] },
      note: "request: council:critique — critique the outline\nkeep handbook",
    });
  });
});

describe("unsent change edits survive a remount", () => {
  afterEach(() => clearUnsent(unsentKey("manager:docs/a1", true)));

  it("are kept under their own key, and reopen the card changing", async () => {
    expect(unsentKey("manager:docs/a1", true)).toBe("change:manager:docs/a1");
    expect(unsentKey("manager:docs/a1", false)).toBe("manager:docs/a1");
    saveUnsent(unsentKey("manager:docs/a1", true), { revision: "4", values: { Q1: ["DOCS"] }, text: {}, note: "mid-edit" });
    const html = await render(provisional);
    expect(html).toContain("Change your answer · revision 4");
    expect(html).toMatch(/<textarea id="change-note-a1"[^>]*>mid-edit<\/textarea>/);
    expect(html).toMatch(/aria-checked="true" checked=""\/><span class="opt-body"><span class="opt-label"><code class="okey">DOCS<\/code>/);
  });

  it("say so when the ask moved underneath", async () => {
    saveUnsent(unsentKey("manager:docs/a1", true), { revision: "3", values: { Q1: ["DOCS"] }, text: {}, note: "mid-edit" });
    const html = await render(provisional);
    expect(html).toMatch(/The ask changed under you \(now revision 4\): your unsent notes are kept below; your 1 unsent pick was cleared/);
  });
});

describe("a provisional ask whose asker came back", () => {
  const r2 = stored(head("related: manager:docs/a1\n", "open", "r2", "2026-10-29T11:00:00.000Z") + BODY);
  const older = stored(head("previous: manager:docs/a1\n", "open", "r0", "2026-10-29T09:00:00.000Z") + BODY);

  it("with a follow-up it leaves Open for Settled; without one it stays under Open", () => {
    expect(followUpOf(provisional, [provisional, r2])).toBe("manager:docs/r2");
    const followed = askRow(provisional, NOW, [provisional, r2]);
    expect(followed.followedBy).toBe("manager:docs/r2");
    expect(rowInFilter(followed, "open")).toBe(false);
    expect(rowInFilter(followed, "settled")).toBe(true);
    const alone = askRow(provisional, NOW, [provisional, older]);
    expect(followUpOf(provisional, [provisional, older])).toBeUndefined();
    expect(rowInFilter(alone, "open")).toBe(true);
    expect(rowInFilter(alone, "settled")).toBe(false);
  });

  it("`previous:` counts as well as `related:`, and a plain answered ask is not changed by it", () => {
    const next = stored(head("previous: manager:docs/a1\n", "open", "r3", "2026-10-29T12:00:00.000Z") + BODY);
    expect(followUpOf(provisional, [provisional, next])).toBe("manager:docs/r3");
    expect(followUpOf(plain, [plain, next])).toBeUndefined();
  });

  it("round 2: only the same asker's follow-up counts; another seat's related: leaves the row under Open", () => {
    const other = { ...stored(head("related: manager:docs/a1\n", "open", "x1", "2026-10-29T11:00:00.000Z").replace("from: manager:docs", "from: domain:stats") + BODY), seat: "domain:stats" };
    expect(followUpOf(provisional, [provisional, other])).toBeUndefined();
    expect(rowInFilter(askRow(provisional, NOW, [provisional, other]), "open")).toBe(true);
  });

  it("round 2: a missing created: on either side is not a follow-up", () => {
    const undated = stored(head("related: manager:docs/a1\n", "open", "r4", "2026-10-29T11:00:00.000Z").replace(/created: .*\n/, "") + BODY);
    expect(followUpOf(provisional, [provisional, undated])).toBeUndefined();
    const mineUndated = stored(head("", "answered", "a1").replace(/created: .*\n/, "") + BODY + block({ answers: { Q1: ["HB"] }, note: REQ, answeredBy: "operator", answeredVia: "browser", revision: 4 }));
    expect(followUpOf(mineUndated, [mineUndated, r2])).toBeUndefined();
  });

  it("round 2: previous: wins over related:", () => {
    const rel = stored(head("related: manager:docs/a1\n", "open", "rel", "2026-10-29T11:00:00.000Z") + BODY);
    const prev = stored(head("previous: manager:docs/a1\n", "open", "prev", "2026-10-29T12:00:00.000Z") + BODY);
    expect(followUpOf(provisional, [provisional, rel, prev])).toBe("manager:docs/prev");
  });

  it("the card links the follow-up and still offers Change answer", async () => {
    const html = await render(provisional, {}, [provisional, r2]);
    expect(html).toMatch(/followed up by <a class="asklink" href="\/a\/manager:docs\/r2">manager:docs\/r2<\/a>/);
    expect(html).toMatch(/<button[^>]*>Change answer<\/button>/);
  });
});

describe("the store takes a re-answer", () => {
  let root: string;
  beforeEach(() => {
    root = path.join(fs.mkdtempSync(path.join("/tmp", "asks-reans-")), "asks");
  });
  afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));
  const push = async () => ({ status: "delivered" as const });
  const ONE = "## ¶ASK_GO: Choose one: Ship it?\nContext: c\n- [ ] [YES] Yes\n  Picks YES.\n- [ ] [NO] No\n  Picks NO.\n";
  const read = () => parseAskFile(fs.readFileSync(path.join(root, "manager:docs", "go.md"), "utf8"));

  it("re-answering at the current revision replaces the block and clears read and acted", async () => {
    newAsk(root, { from: "manager:docs", to: "operator", id: "go" }, ONE);
    await answerAsk(root, "manager:docs", "go", { answers: { GO: ["YES"] }, note: `${REQ}`, answeredBy: "operator", answeredVia: "browser" }, { expectedRevision: 1, push });
    await readAsk(root, "manager:docs", "go", { by: "manager:docs" });
    await actedAsk(root, "manager:docs", "go", "started the proof", { by: "manager:docs" });
    expect(read().header.readAt).toBeTruthy();
    expect(read().header.acted).toBeTruthy();
    const out = await answerAsk(root, "manager:docs", "go", { answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: "browser" }, { expectedRevision: 2, push });
    expect(out.revision).toBe(3);
    const after = read();
    expect(after.header.status).toBe("answered");
    expect(after.answer?.answers).toEqual({ GO: ["NO"] });
    expect(after.answer?.note).toBeUndefined();
    expect(after.header.readAt).toBeUndefined();
    expect(after.header.acted).toBeUndefined();
    expect(fs.readFileSync(path.join(root, "manager:docs", "go.md"), "utf8").match(/```json answer/g)).toHaveLength(1);
  });

  it("a stale revision is refused and writes nothing", async () => {
    newAsk(root, { from: "manager:docs", to: "operator", id: "go" }, ONE);
    await answerAsk(root, "manager:docs", "go", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { expectedRevision: 1, push });
    await expect(answerAsk(root, "manager:docs", "go", { answers: { GO: ["NO"] }, answeredBy: "operator" }, { expectedRevision: 1, push })).rejects.toThrow(/revision/i);
    expect(read().answer?.answers).toEqual({ GO: ["YES"] });
    expect(read().header.revision).toBe("2");
  });
});

describe("round 2: Cancel and stale change edits", () => {
  const withDraft = stored(
    head("draft: 2026-10-29T20:00:00.000Z\n") + BODY + block({ answers: { Q1: ["HB"] }, answeredBy: "operator", revision: 4 }) +
      '\n```json draft\n{"answers":{"Q1":["DOCS"]},"answeredBy":"operator","basedOn":4,"savedAt":"2026-10-29T20:00:00.000Z"}\n```\n',
  );

  it("Cancel discards a change draft the operator saved on a settled ask, and nothing else", () => {
    expect(cancelDiscards(withDraft)).toBe(true);
    expect(cancelDiscards(plain)).toBe(false);
    expect(cancelDiscards(openAsk)).toBe(false);
  });

  it("change:<ref> entries are dropped for asks that can no longer be changed", () => {
    expect(staleChangeKeys([plain, ruled, superseded, openAsk, provisional])).toEqual([]);
    const seatRuled = { ...ruled, header: { ...ruled.header, id: "r9" } };
    const gone = { ...superseded, header: { ...superseded.header, id: "s9" } };
    // IDE-339: a seat-ruled ask can be overruled, so its change:<ref> edits are kept; a superseded one's go.
    expect(staleChangeKeys([plain, seatRuled, gone], (k) => k === "change:manager:docs/r9" || k === "change:manager:docs/s9" || k === "change:manager:docs/a1")).toEqual([
      "change:manager:docs/s9",
    ]);
  });
});
