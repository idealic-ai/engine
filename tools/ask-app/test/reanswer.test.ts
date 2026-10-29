/**
 * IDE-304: the operator changes an answer they already gave. A settled or provisional ask whose
 * recorded answer is the operator's own shows "Change answer"; the form reopens pre-filled and the
 * new answer goes through /api/answer at the current revision, replacing the earlier one.
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { parseAskFile } from "../src/lib/format.ts";
import { actedAsk, answerAsk, newAsk, readAsk } from "../src/lib/store.ts";
import { isProvisional } from "../src/client/loop.ts";
import { CHANGE_WORDING, changeAnswerStart, mayChangeAnswer, sendChangedAnswer } from "../src/client/reanswer.ts";

const head = (extra = "", status = "answered") =>
  `---\nid: a1\nto: operator\nfrom: manager:docs\nstatus: ${status}\nrevision: 4\ncreated: 2026-10-29T10:00:00.000Z\n${extra}---\n\n`;
const BODY = "## ¶ASK_Q1: Choose one: Where?\n- [ ] [HB] handbook\n- [ ] [DOCS] docs\n\n## ¶ASK_Q2: Choose one: Second?\n- [ ] [P] p\n- [ ] [Q] q\n";
const block = (a: object) => `\n\`\`\`json answer\n${JSON.stringify(a)}\n\`\`\`\n`;
const stored = (text: string) => ({ ...parseAskFile(text), seat: "manager:docs", file: "/x.md", mtimeMs: 0 });

const REQ = "request: proof:explore — map the doc trees first";
const provisional = stored(head() + BODY + block({ answers: { Q1: ["HB"], "Q2.other": REQ }, note: `${REQ}\nkeep handbook`, answeredBy: "operator", answeredVia: "browser", answeredAt: "2026-10-29T19:30:00.000Z", revision: 4 }));
const plain = stored(head() + BODY + block({ answers: { Q1: ["DOCS"], Q2: ["P"] }, note: "fine", answeredBy: "operator", answeredVia: "browser", revision: 4 }));
const ruled = stored(head() + BODY + block({ answers: { Q1: ["DOCS"] }, answeredBy: "manager:director", revision: 4 }));
const superseded = stored(head("superseded-by: manager:docs/a2\n", "superseded") + BODY + block({ answers: { Q1: ["HB"] }, answeredBy: "operator", revision: 4 }));
const openAsk = stored(head("", "open") + BODY);

async function render(ask: ReturnType<typeof stored>, extra: Record<string, unknown> = {}) {
  const { AskDetail } = await import("../src/client/App.tsx");
  return renderToStaticMarkup(createElement(AskDetail, { ask, all: [ask], onChanged: () => {}, ...extra }));
}

describe("which asks offer Change answer", () => {
  it("the operator's provisional answer and a plain answered one do; a seat-ruled, superseded or open ask does not", () => {
    expect(isProvisional(provisional)).toBe(true);
    expect(mayChangeAnswer(provisional)).toBe(true);
    expect(mayChangeAnswer(plain)).toBe(true);
    expect(mayChangeAnswer(ruled)).toBe(false);
    expect(mayChangeAnswer(superseded)).toBe(false);
    expect(mayChangeAnswer(openAsk)).toBe(false);
  });

  it("the answer bar shows the button on the operator's answers and not elsewhere", async () => {
    expect(await render(provisional)).toMatch(/<button[^>]*>Change answer<\/button>/);
    expect(await render(plain)).toMatch(/<button[^>]*>Change answer<\/button>/);
    expect(await render(ruled)).not.toContain("Change answer");
    expect(await render(superseded)).not.toContain("Change answer");
    expect(await render(openAsk)).not.toContain("Change answer");
  });
});

describe("the reopened form", () => {
  it("starts from the recorded picks and note, without the loop lines", () => {
    expect(changeAnswerStart(provisional)).toEqual({ values: { Q1: ["HB"] }, text: {}, note: "keep handbook" });
    expect(changeAnswerStart(plain)).toEqual({ values: { Q1: ["DOCS"], Q2: ["P"] }, text: {}, note: "fine" });
  });

  it("renders pre-filled and editable, says it replaces the earlier answer, and offers Cancel", async () => {
    const html = await render(provisional, { startChanging: true });
    expect(html).toContain("Change your answer · revision 4");
    expect(html).toMatch(/<input type="radio"[^>]*aria-checked="true" checked=""\/><span class="opt-body"><span class="opt-label"><code class="okey">HB<\/code>/);
    expect(html).toMatch(/aria-checked="false"\/><span class="opt-body"><span class="opt-label"><code class="okey">DOCS<\/code>/);
    expect(html).not.toMatch(/type="radio"[^>]*disabled=""/);
    expect(html).toMatch(/<textarea[^>]*>keep handbook<\/textarea>/);
    expect(html).not.toContain("request: proof:explore");
    expect(html).toContain(CHANGE_WORDING);
    expect(html).toMatch(/<button[^>]*>Send changed answer<\/button>/);
    expect(html).toMatch(/<button[^>]*>Cancel<\/button>/);
    expect(html).not.toContain("Waiting on the asker: draft sent");
  });

  it("the wording is honest: it replaces the answer and the asker gets it new and unread", () => {
    expect(CHANGE_WORDING).toMatch(/replaces your earlier answer/);
    expect(CHANGE_WORDING).toMatch(/new and unread/);
  });
});

describe("sendChangedAnswer posts /api/answer at the current revision", () => {
  it("sends the picks, the plain note and expectedRevision", async () => {
    const calls: { url: string; body: any }[] = [];
    const post = async (url: string, body: unknown) => (calls.push({ url, body: body as any }), { status: 200, json: { revision: 5 } });
    const out = await sendChangedAnswer(post, { seat: "manager:docs", id: "a1", expectedRevision: 4, answers: { Q1: ["DOCS"] }, note: `${REQ}\nchanged` });
    expect(out.ok).toBe(true);
    expect(calls).toEqual([{ url: "/api/answer", body: { seat: "manager:docs", id: "a1", expectedRevision: 4, answers: { Q1: ["DOCS"] }, note: "changed" } }]);
  });

  it("a stale revision shows the existing 'the ask moved' message", async () => {
    const post = async () => ({ status: 409, json: { error: "stale", revision: 6, status: "answered" } });
    const out = await sendChangedAnswer(post, { seat: "s", id: "a", expectedRevision: 4, answers: { Q1: ["HB"] }, note: "" });
    expect(out).toEqual({ ok: false, message: "Not saved: the ask moved (now revision 6). Read the current state before answering again." });
  });

  it("a superseded ask names its replacement", async () => {
    const post = async () => ({ status: 409, json: { status: "superseded", supersededBy: "manager:docs/a2" } });
    const out = await sendChangedAnswer(post, { seat: "s", id: "a", expectedRevision: 4, answers: { Q1: ["HB"] }, note: "" });
    expect(out).toMatchObject({ ok: false, supersededBy: "manager:docs/a2" });
  });
});

describe("the store already takes a re-answer (no server change needed)", () => {
  let root: string;
  beforeEach(() => {
    root = path.join(fs.mkdtempSync(path.join("/tmp", "asks-reans-")), "asks");
  });
  afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));
  const push = async () => ({ status: "delivered" as const });
  const ONE = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n";
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
