/**
 * IDE-339, the client half: the operator overrules a seat's ruling from the card, the card and the
 * sidebar say an answer overruled someone, every earlier answer is listed (newest first, with the
 * old server's one-line `replaced:` as the fallback), the grant class shows beside the answerer, and
 * no request the client sends carries a `grantClass` (the server's aa0f255 refuses one with a 400).
 */
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import { parseAskFile } from "../src/lib/format.ts";
import { askRow, answererText, earlierAnswers } from "../src/client/model.ts";
import { changeAnswerStart, changeMode, draftBody, mayChangeAnswer, overruleBody, overruleOutcome, requestSend, sendRoute, withoutGrant } from "../src/client/reanswer.ts";
import { sendProvisional } from "../src/client/loop.ts";

const head = (extra = "", status = "answered", id = "a1") =>
  `---\nid: ${id}\nto: operator\nfrom: docs:handbook\nstatus: ${status}\nrevision: 4\ncreated: 2026-10-29T10:00:00.000Z\n${extra}---\n\n`;
const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes, ship\n- [ ] [NO] No, hold\n";
const block = (a: object) => `\n\`\`\`json answer\n${JSON.stringify(a)}\n\`\`\`\n`;
const hist = (h: object[]) => `\n\`\`\`json history\n${JSON.stringify(h)}\n\`\`\`\n`;
/** As /api/asks sends it: the history parsed beside the rest (the lib on this branch does not parse the fence). */
const stored = (text: string, history?: object[]) => ({ ...parseAskFile(text), seat: "docs:handbook", file: "/x.md", mtimeMs: 0, ...(history ? { history } : {}) });
/** As the old server sends it: no history field at all (aa0f255's parseAskFile always returns one, so it is taken off). */
const oldServer = (text: string) => {
  const { history: _h, ...rest } = stored(text) as ReturnType<typeof stored> & { history?: unknown };
  return rest as ReturnType<typeof stored>;
};
const src = (f: string) => fs.readFileSync(path.join(import.meta.dirname, "../src/client", f), "utf8");

const MGR = { answers: { GO: ["YES"] }, note: "ship it", answeredBy: "manager:docs", answeredVia: "cli", answeredAt: "2026-10-29T11:00:00.000Z", grantClass: "B" as const, revision: 4 };
const ruled = stored(head() + BODY + block(MGR));
const ruledDeclined = stored(head("", "declined") + BODY + block({ declined: true, reason: "not now", answeredBy: "manager:docs", revision: 4 }));
const own = stored(head() + BODY + block({ answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: "browser", revision: 4 }));
const superseded = stored(head("superseded-by: docs:handbook/a2\n", "superseded") + BODY + block(MGR));
const supersededOwn = stored(head("superseded-by: docs:handbook/a2\n", "superseded") + BODY + block({ answers: { GO: ["NO"] }, answeredBy: "operator", revision: 4 }));

const FIRST = { answers: { GO: ["NO"] }, answeredBy: "manager:docs", answeredVia: "cli", answeredAt: "2026-10-29T09:00:00.000Z", revision: 2 };
const SECOND = { answers: { GO: ["YES"] }, note: "changed my mind", answeredBy: "manager:docs", answeredVia: "cli", answeredAt: "2026-10-29T10:30:00.000Z", grantClass: "C" as const, revision: 3 };
const overruled = stored(
  head("overruled: manager:docs\nreplaced: revision 3 by manager:docs at 2026-10-29T10:30:00.000Z; was GO=YES\n") + BODY + block({ answers: { GO: ["NO"] }, note: "hold", answeredBy: "operator", answeredVia: "browser", answeredAt: "2026-10-29T12:00:00.000Z", revision: 4 }),
  [FIRST, SECOND],
);
/** The old server: a `replaced:` line, no history field at all. */
const legacy = oldServer(head("replaced: revision 3 by operator at 2026-10-29T10:30:00.000Z; was GO=YES\n") + BODY + block({ answers: { GO: ["NO"] }, answeredBy: "operator", revision: 4 }));

async function render(ask: ReturnType<typeof stored>, extra: Record<string, unknown> = {}) {
  const { AskDetail } = await import("../src/client/App.tsx");
  return renderToStaticMarkup(createElement(AskDetail, { ask, all: [ask], onChanged: () => {}, ...extra }));
}

describe("Overrule is offered on a seat-ruled ask", () => {
  it("a seat's ruling is overruled, the operator's own answer is changed, a superseded ask is neither", () => {
    expect(changeMode(ruled)).toBe("overrule");
    expect(changeMode(ruledDeclined)).toBe("overrule");
    expect(changeMode(own)).toBe("change");
    expect(changeMode(superseded)).toBeUndefined();
    expect(changeMode(supersededOwn)).toBeUndefined();
    expect(mayChangeAnswer(ruled)).toBe(true);
    expect(mayChangeAnswer(superseded)).toBe(false);
  });

  it("the card's button reads Overrule on a seat's ruling and Change answer on the operator's own; a superseded card has neither", async () => {
    const r = await render(ruled);
    expect(r).toMatch(/<button[^>]*>Overrule<\/button>/);
    expect(r).not.toContain(">Change answer<");
    expect(r).not.toContain("This app has no overrule yet.");
    expect(await render(own)).toMatch(/<button[^>]*>Change answer<\/button>/);
    for (const a of [superseded, supersededOwn]) {
      const h = await render(a);
      expect(h).not.toContain(">Overrule<");
      expect(h).not.toContain(">Change answer<");
    }
  });

  it("the overrule form sends through /api/answer and may Save draft (ASKFOLLOWUP: the store takes the operator's draft over a seat's ruling)", async () => {
    const h = await render(ruled, { startChanging: true });
    expect(h).toContain("Overrule manager:docs");
    expect(h).toMatch(/<button[^>]*>Send a decline<\/button>/);
    expect(h).toMatch(/<button class="btn quiet"[^>]*>Save draft<\/button>/);
    expect(h).toContain("Save draft keeps it in the file and sends nothing; sending that draft overrules.");
    // The provisional sends stay off an overrule: a seat's ruling is not a round to keep open.
    for (const gone of ["Send as draft", "Draft a decline", "Need something first"]) expect(h).not.toContain(gone);
    expect(overruleBody(ruled, "send", { answers: { GO: ["NO"] }, note: "hold" })).toEqual({ seat: "docs:handbook", id: "a1", expectedRevision: 4, answers: { GO: ["NO"] }, note: "hold" });
    expect(overruleBody(ruled, "decline", { answers: {}, note: "not this way" })).toEqual({ seat: "docs:handbook", id: "a1", expectedRevision: 4, decline: "not this way" });
    expect(src("App.tsx")).toContain('post("/api/answer", overruleBody(ask, kind, { answers, note }), keep)');
  });
});

describe("an overrule's sends take Send's after-send path (ASKHL fix round)", () => {
  it("overruleOutcome reads /api/answer as sendOutcome reads /api/send: only a 200 is sent", () => {
    expect(overruleOutcome(ruled, 200, { delivery: { status: "delivered" } })).toEqual({ sent: true, text: `Overruled. Queued at docs:handbook, not read yet. It turns "read" when the seat runs engine ask read.` });
    expect(overruleOutcome(ruled, 200, { delivery: { status: "undelivered", reason: "no live session" } })).toEqual({ sent: true, text: "Overruled. Saved, but undelivered (no live session). The asker's /next picks it up from the file." });
    expect(overruleOutcome(ruled, 200, {})).toEqual({ sent: true, text: "Overruled." });
    expect(overruleOutcome(ruled, 400, { error: "a decline needs a non-empty reason" })).toEqual({ sent: false, text: "Error: a decline needs a non-empty reason" });
    expect(overruleOutcome(ruled, 500, undefined)).toEqual({ sent: false, text: "Error: HTTP 500" });
  });

  it("a failed overrule keeps the unsent copy and never moves on; an accepted one hands App the line through onSent", () => {
    const app = src("App.tsx");
    const fn = app.slice(app.indexOf("async function sendOverrule"), app.indexOf("async function act("));
    expect(fn).toMatch(/const out = overruleOutcome\(ask, r\.status, r\.json\);\s*if \(!out\.sent\) \{\s*keep\(\);\s*setResult\(out\.text\);\s*return onChanged\(\);\s*\}/);
    expect(fn).toMatch(/clearUnsent\(keyFor\(true\)\);\s*onChanged\(\);\s*if \(onSent\) onSent\(out\.text, next\);\s*else if \(out\.text\) setResult\(out\.text\);/);
    expect(fn).not.toContain("onSendNext");
  });

  it("ASKFOLLOWUP brought Save draft back; the comment says why the other three stay hidden", () => {
    expect(src("App.tsx")).not.toContain("they return when the ASKFOLLOWUP round widens writeDraft");
    expect(src("App.tsx")).toContain("ASKFOLLOWUP widened\n                  writeDraft to the operator over a seat's ruling, so Save draft is offered on one.");
  });
});

describe("the overruled stamp", () => {
  it("the card says whose ruling the answer overruled, as a quiet chip", async () => {
    expect(await render(overruled)).toContain(`<span class="chip quiet overruled">Overruled manager:docs’s ruling</span>`);
    expect(await render(own)).not.toContain("Overruled");
  });

  it("the sidebar row carries it as a quiet mark with the same words", async () => {
    const row = askRow(overruled);
    expect(row.overruled).toBe("manager:docs");
    expect(askRow(own).overruled).toBeUndefined();
    const { AskRowButton } = await import("../src/client/App.tsx");
    const h = renderToStaticMarkup(createElement(AskRowButton, { r: row, current: false, onPick: () => {}, slim: false }));
    expect(h).toMatch(/<span class="mk-i ovr" title="Overruled manager:docs’s ruling" aria-label="Overruled manager:docs’s ruling">/);
  });
});

describe("earlier answers", () => {
  it("lists the history newest first, each record whole", () => {
    const e = earlierAnswers(overruled);
    expect(e.map((x) => (x.kind === "record" ? x.answer.revision : x.text))).toEqual([3, 2]);
  });

  it("falls back to the one-line replaced: when the server sends no history", () => {
    expect(earlierAnswers(legacy)).toEqual([{ kind: "summary", text: "revision 3 by operator at 2026-10-29T10:30:00.000Z; was GO=YES" }]);
    // ASKOVR SHOULD-2: the new server sends `history: []` for a file with no history fence, and it writes
    // `replaced:` only beside a non-empty history, so an empty one with a `replaced:` line is a file
    // changed before IDE-339: the line stands in.
    expect(earlierAnswers({ ...legacy, history: [] } as typeof legacy)).toEqual([{ kind: "summary", text: "revision 3 by operator at 2026-10-29T10:30:00.000Z; was GO=YES" }]);
    // Empty history and no `replaced:` line: nothing was replaced.
    expect(earlierAnswers({ ...own, history: [] })).toEqual([]);
    expect(earlierAnswers(own)).toEqual([]);
  });

  it("leaves out follow-up entries, which are not answers", () => {
    const withFollow = { ...overruled, history: [FIRST, { type: "followup", ref: "docs:handbook/a2" }, SECOND] };
    expect(earlierAnswers(withFollow as typeof overruled)).toHaveLength(2);
  });

  it("renders a collapsed 'Earlier answers (N)' list: who, when, via, class, the picks in words and the note", async () => {
    const h = await render(overruled);
    expect(h).toMatch(/<details class="earlier-answers"><summary>Earlier answers \(2\)<\/summary>/);
    const second = h.indexOf("revision 3");
    const first = h.indexOf("revision 2");
    expect(second).toBeGreaterThan(-1);
    expect(second).toBeLessThan(first);
    const entry = h.slice(second, first);
    expect(entry).toContain("manager:docs · class C");
    expect(entry).toContain("via cli");
    expect(entry).toContain("2026-10-29 10:30");
    expect(entry).toContain("YES · Yes, ship");
    expect(entry).toContain("changed my mind");
    expect(h.slice(first)).toContain("NO · No, hold");
  });

  it("renders the replaced: line alone for the old server", async () => {
    const h = await render(legacy);
    expect(h).toMatch(/<details class="earlier-answers"><summary>Earlier answers \(1\)<\/summary>/);
    expect(h).toContain("revision 3 by operator at 2026-10-29T10:30:00.000Z; was GO=YES");
    expect(await render(own)).not.toContain("Earlier answers");
  });
});

describe("the grant class", () => {
  it("reads beside the answerer: 'manager:docs · class B', and the name alone without one", () => {
    expect(answererText(MGR)).toBe("manager:docs · class B");
    expect(answererText({ answeredBy: "operator" })).toBe("operator");
    expect(answererText({ answeredBy: "manager:docs", grantClass: "Z" } as never)).toBe("manager:docs");
  });

  it("shows on the ruled-by line, the answer block and the sidebar row", async () => {
    const h = await render(ruled);
    expect(h).toContain("<b>Ruled by manager:docs · class B</b>");
    expect(h).toMatch(/<p class="answered-by">by <b>manager:docs<\/b> <span class="chip quiet grant"[^>]*>class B<\/span>/);
    expect(askRow(ruled).ruledClass).toBe("B");
    const { AskRowButton } = await import("../src/client/App.tsx");
    expect(renderToStaticMarkup(createElement(AskRowButton, { r: askRow(ruled), current: false, onPick: () => {}, slim: false }))).toContain("ruled by manager:docs · class B");
  });
});

describe("no send body carries grantClass", () => {
  it("withoutGrant drops a top-level grantClass and keeps the rest", () => {
    expect(withoutGrant({ seat: "s", id: "a", grantClass: "B", answers: { GO: ["YES"] } })).toEqual({ seat: "s", id: "a", answers: { GO: ["YES"] } });
    expect(withoutGrant({ refs: ["s/a"] })).toEqual({ refs: ["s/a"] });
  });

  it("the one request poster passes every body through it", () => {
    expect(src("App.tsx")).toMatch(/body: JSON\.stringify\(withoutGrant\(body\)\)/);
    // And nothing in the client writes one into a body.
    for (const f of fs.readdirSync(path.join(import.meta.dirname, "../src/client"))) {
      if (!/\.tsx?$/.test(f)) continue;
      expect(src(f), f).not.toMatch(/grantClass\s*:/);
    }
  });

  it("every body built from a grant-classed answer leaves it out", async () => {
    const s0 = changeAnswerStart(ruled);
    const answers = s0.values as Record<string, string[]>;
    const bodies: unknown[] = [
      overruleBody(ruled, "send", { answers, note: s0.note }),
      overruleBody(ruled, "decline", { answers, note: "no" }),
      draftBody(ruled, "send-now", { answers, note: s0.note }),
      draftBody(ruled, "draft-decline", { answers, note: "no" }),
      requestSend(ruled, answers, s0.note, "proof:best", "show me"),
    ];
    const sent: unknown[] = [];
    await sendProvisional(async (_u, b) => (sent.push(b), { status: 500, json: { error: "x" } }), async () => undefined, { seat: "docs:handbook", id: "a1", expectedRevision: 4, answers, note: "n" });
    for (const b of [...bodies, ...sent]) expect(JSON.stringify(b)).not.toContain("grantClass");
  });
});

/** ASKOVR critique, SHOULD-1 and SHOULD-3 and NIT-3. */
describe("Overrule is not offered where the store always refuses it (SHOULD-1)", () => {
  // MGR without its grant class: a reserved ask's answer carries none.
  const { grantClass: _g, ...plainMgr } = MGR;
  const reservedForSeat = stored(head("reserved-for: manager:docs\n") + BODY + block(plainMgr));
  const reservedForOperator = stored(head("reserved-for: operator\n") + BODY + block(plainMgr));

  it("an ask reserved for the seat that ruled it gets no Overrule: assertMayAnswer refuses the operator there", async () => {
    expect(changeMode(reservedForSeat)).toBeUndefined();
    expect(mayChangeAnswer(reservedForSeat)).toBe(false);
    const h = await render(reservedForSeat);
    expect(h).not.toContain(">Overrule<");
    expect(h).not.toContain(">Change answer<");
    // ASKOVR fix 2: the ruled-by line offers no Overrule either, and the seat answered in its own place.
    expect(h).toContain("Ruled by manager:docs");
    expect(h).not.toContain("Overrule it");
    expect(h).not.toContain("in your place");
    expect(h).toContain("it was reserved for that seat, which answered.");
    // Positive control: the unreserved ruling, which does offer Overrule, says so on the same line.
    const open = await render(ruled);
    expect(open).toContain(">Overrule<");
    expect(open).toContain("a seat answered in your place. Overrule it to answer in its place.");
  });

  it("an ask reserved for the operator is still overruled, and the operator's own answer is still changed", () => {
    expect(changeMode(reservedForOperator)).toBe("overrule");
    expect(changeMode(stored(head("reserved-for: operator\n") + BODY + block({ answers: { GO: ["NO"] }, answeredBy: "operator", revision: 4 })))).toBe("change");
  });
});

describe("where a card's send goes (SHOULD-3)", () => {
  it("an overrule's Send and Send & next go to /api/answer as a send, keeping next", () => {
    expect(sendRoute(true, "send-now")).toEqual({ endpoint: "/api/answer", kind: "send", next: false });
    expect(sendRoute(true, "send-now", true)).toEqual({ endpoint: "/api/answer", kind: "send", next: true });
  });

  it("an overrule's decline goes to /api/answer as a decline, never to the draft the store refuses", () => {
    expect(sendRoute(true, "draft-decline")).toEqual({ endpoint: "/api/answer", kind: "decline", next: false });
  });

  it("the open form and a change take the draft path; a discard goes to /api/discard", () => {
    for (const k of ["draft", "draft-decline", "send-now"] as const) {
      expect(sendRoute(false, k)).toEqual({ endpoint: "/api/draft", kind: k, next: false });
    }
    expect(sendRoute(false, "send-now", true)).toEqual({ endpoint: "/api/draft", kind: "send-now", next: true });
    expect(sendRoute(false, "discard")).toEqual({ endpoint: "/api/discard", kind: "discard", next: false });
    expect(sendRoute(true, "discard")).toEqual({ endpoint: "/api/discard", kind: "discard", next: false });
  });

  it("an overrule's Save draft takes the draft path, where the store keeps it (ASKFOLLOWUP), never /api/answer as a final answer", () => {
    // Save draft is offered on an overrule (pinned above); it saves, and sends nothing.
    expect(sendRoute(true, "draft")).toEqual({ endpoint: "/api/draft", kind: "draft", next: false });
    expect(src("reanswer.ts")).not.toMatch(/store takes no draft over a seat's answer|where the store refuses it/);
  });

  it("an overrule card reopens on its saved draft, overrule mode, with Update draft and Discard draft", async () => {
    const drafted = stored(head("draft: 2026-10-30T09:00:00.000Z\n") + BODY + block(MGR) + `\n\`\`\`json draft\n${JSON.stringify({ answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: "browser", basedOn: 4, savedAt: "2026-10-30T09:00:00.000Z" })}\n\`\`\`\n`);
    expect(drafted.draft?.answers).toEqual({ GO: ["NO"] });
    const h = await render(drafted);
    expect(h).toContain("Overrule manager:docs");
    expect(h).toMatch(/<button class="btn quiet"[^>]*>Update draft<\/button>/);
    expect(h).toMatch(/<button[^>]*>Discard draft<\/button>/);
    expect(h).toContain("against revision 4");
  });

  it("act()'s sends are routed by sendRoute: act hands an /api/answer route to sendOverrule with its next, and nothing else calls it", () => {
    const app = src("App.tsx");
    const act = app.slice(app.indexOf("async function act("), app.indexOf("async function act(") + 400);
    expect(act).toMatch(/const route = sendRoute\(overrule, kind, next\);\s*if \(route\.endpoint === "\/api\/answer"\) return sendOverrule\(route\.kind, route\.next\);/);
    // The draft path posts to the routed endpoint, not a literal one.
    expect(app).toContain("post(route.endpoint, draftBody(ask, kind, { answers, note }), keep)");
    expect(app).not.toContain('post("/api/draft"');
    // One definition, one call (in act): no button reaches sendOverrule around the route.
    expect(app.match(/sendOverrule\(/g)).toHaveLength(2);
    // The decline button is one button on every form, through act; its label says which it does.
    expect(app).toContain('onClick={() => act("draft-decline")}>{overrule ? "Send a decline" : "Draft a decline"}</button>');
  });

  it("an overrule starts with an empty note: the seat's note and reason were its words, not yours; your own answer keeps its note", () => {
    expect(changeAnswerStart(ruled).note).toBe("");
    expect(changeAnswerStart(ruledDeclined).note).toBe("");
    expect(changeAnswerStart(ruled).values).toEqual({ GO: ["YES"] });
    const ownNoted = stored(head() + BODY + block({ answers: { GO: ["NO"] }, note: "hold it", answeredBy: "operator", revision: 4 }));
    expect(changeAnswerStart(ownNoted).note).toBe("hold it");
  });
});

describe("a history the server could not read is said on the card (NIT-3)", () => {
  it("historyError shows beside Earlier answers, with what it means for a second answer", async () => {
    const bad = { ...ruled, history: [], historyError: "the json history block is not valid JSON" };
    const h = await render(bad);
    expect(h).toContain("the json history block is not valid JSON");
    expect(h).toContain("fix or remove it by hand");
    expect(await render(ruled)).not.toContain("history-error");
  });

  it("historyError shows when Earlier answers has entries too, above the list", async () => {
    const h = await render({ ...overruled, historyError: "the json history block is not valid JSON" });
    expect(h).toMatch(/<details class="earlier-answers"><summary>Earlier answers \(2\)<\/summary>/);
    const at = h.indexOf("the json history block is not valid JSON");
    expect(at).toBeGreaterThan(-1);
    expect(at).toBeLessThan(h.indexOf('class="earlier-answers"'));
    expect(h).toContain("fix or remove it by hand");
  });
});

describe("SHOULD-1 (ASKFOLLOW critique): Send batch says which drafts overrule a seat", () => {
  const draftOver = (a: object, status = "answered", id = "a1") =>
    stored(head("draft: 2026-10-30T09:00:00.000Z\n", status, id) + BODY + block(MGR) + `\n\`\`\`json draft\n${JSON.stringify({ answeredBy: "operator", answeredVia: "browser", basedOn: 4, savedAt: "2026-10-30T09:00:00.000Z", ...a })}\n\`\`\`\n`);
  const ref = (a: { header: { id?: string } }) => `${(a as { seat?: string }).seat}/${a.header.id}`;

  it("a complete overrule draft still confirms, naming the ask and the seat it overrules", async () => {
    const { batchConfirmation } = await import("../src/client/model.ts");
    const d = draftOver({ answers: { GO: ["NO"] } });
    expect(d.draft).toBeDefined();
    expect(batchConfirmation([d], ref)).toBe("Sending overrules a seat's ruling: docs:handbook/a1 overrules manager:docs's ruling. The asker and the seat that ruled are told. Send anyway?");
  });

  it("beside unanswered forks, both are said; a draft on an open ask, or over your own answer, is no overrule", async () => {
    const { batchConfirmation } = await import("../src/client/model.ts");
    const over = draftOver({ answers: { GO: ["NO"] } }, "answered", "a2");
    const openPartial = stored(`---\nid: o1\nto: operator\nfrom: docs:handbook\nstatus: open\nrevision: 1\ndraft: 2026-10-30T09:00:00.000Z\ncreated: 2026-10-29T10:00:00.000Z\n---\n\n## ¶ASK_A: Choose one: A?\n- [ ] [Y] y\n\n## ¶ASK_B: Choose one: B?\n- [ ] [Y] y\n` + `\n\`\`\`json draft\n${JSON.stringify({ answers: { A: ["Y"] }, answeredBy: "operator", basedOn: 1, savedAt: "2026-10-30T09:00:00.000Z" })}\n\`\`\`\n`);
    expect(openPartial.draft).toBeDefined();
    const msg = batchConfirmation([openPartial, over], ref);
    expect(msg).toBe("1 question unanswered — send anyway? Each ask is settled when sent. docs:handbook/o1: B Sending overrules a seat's ruling: docs:handbook/a2 overrules manager:docs's ruling. The asker and the seat that ruled are told.");
    expect(batchConfirmation([openPartial], ref)).not.toMatch(/overrule/);
  });
});
