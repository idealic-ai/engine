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
import { changeAnswerStart, changeMode, draftBody, mayChangeAnswer, overruleBody, requestSend, withoutGrant } from "../src/client/reanswer.ts";
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

  it("the overrule form sends through /api/answer and offers no draft sends, which the store refuses on a seat's ruling", async () => {
    const h = await render(ruled, { startChanging: true });
    expect(h).toContain("Overrule manager:docs");
    expect(h).toMatch(/<button[^>]*>Send a decline<\/button>/);
    for (const gone of ["Save draft", "Send as draft", "Draft a decline", "Need something first"]) expect(h).not.toContain(gone);
    expect(overruleBody(ruled, "send", { answers: { GO: ["NO"] }, note: "hold" })).toEqual({ seat: "docs:handbook", id: "a1", expectedRevision: 4, answers: { GO: ["NO"] }, note: "hold" });
    expect(overruleBody(ruled, "decline", { answers: {}, note: "not this way" })).toEqual({ seat: "docs:handbook", id: "a1", expectedRevision: 4, decline: "not this way" });
    expect(src("App.tsx")).toContain('post("/api/answer", overruleBody(ask, kind, { answers, note }), keep)');
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
    // An empty history is the new server saying nothing was replaced: no fallback to a stale line.
    expect(earlierAnswers({ ...legacy, history: [] } as typeof legacy)).toEqual([]);
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
