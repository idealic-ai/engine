/**
 * ASKLISTUI: the client half of ASKLIST (src/lib/settle.ts). The server says on each /api/asks row
 * whether the ask is `settled` (nothing is owed) and, when not, what is `owed` and by whom. The list
 * reads those two fields and never works settlement out for itself: Open is what is not settled,
 * split into what waits on you and what waits on someone else, and ⏳ marks only an `owed` row.
 * Every seat and id here is synthetic.
 */
import { describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { parseAskFile } from "../src/lib/format.ts";
import { askRow, followUpOf, listSections, owedWords, rowInFilter, type Filter, type StoredAsk } from "../src/client/model.ts";
import { sidebarView } from "../src/client/search.ts";
import type { Settlement } from "../src/lib/settle.ts";

const NOW = Date.parse("2026-11-01T12:00:00.000Z");
const FILTERS: Filter[] = ["open", "ruled", "settled", "all"];

function file(o: { id?: string; status?: string; from?: string; to?: string; extra?: string; answeredAt?: string; note?: string } = {}) {
  const head = `---\nid: ${o.id ?? "t1"}\nto: ${o.to ?? "operator"}\nfrom: ${o.from ?? "test:asker"}\nstatus: ${o.status ?? "answered"}\nrevision: 1\ncreated: 2026-10-30T10:00:00.000Z\n${o.extra ?? ""}---\n\n## Choose one: ¶ASK_GO — ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n`;
  if ((o.status ?? "answered") === "open") return head;
  const answer = { answers: { q0: "YES" }, answeredBy: "operator", answeredVia: "browser", answeredAt: o.answeredAt ?? "2026-10-30T11:00:00.000Z", revision: 1, ...(o.note ? { note: o.note } : {}) };
  return `${head}\n\`\`\`json answer\n${JSON.stringify(answer, null, 2)}\n\`\`\`\n`;
}
const stored = (text: string, s?: Settlement, seat = "test:asker"): StoredAsk => ({ ...parseAskFile(text), seat, file: "/x.md", mtimeMs: 0, ...(s ?? {}) });
const filters = (a: StoredAsk) => FILTERS.filter((f) => rowInFilter(askRow(a, NOW, [a]), f));

async function rowHtml(a: StoredAsk, all: StoredAsk[] = [a]) {
  const { AskListItem } = await import("../src/client/App.tsx");
  return renderToStaticMarkup(createElement(AskListItem, { r: askRow(a, NOW, all), current: false, onPick: () => {}, slim: false, onChanged: () => {} }));
}
/** The part of the main (Open) list the ask lands in, or undefined when it is not in Open at all. */
const sectionOf = (a: StoredAsk) => listSections([askRow(a, NOW, [a])].filter((r) => rowInFilter(r, "open")), "open").find((s) => s.rows.length)?.name;

const FOLLOW: Settlement = { settled: false, owed: { kind: "follow-up", by: "test:asker", why: "a provisional answer: the asker owes a follow-up ask" } };
const PROVISIONAL = file({ note: "request: reword — say which box" });

describe("the row reads settled and owed from the server", () => {
  it("copies both fields onto the row", () => {
    const r = askRow(stored(PROVISIONAL, FOLLOW), NOW);
    expect(r.settled).toBe(false);
    expect(r.owed).toEqual(FOLLOW.owed);
  });
  it("an old server that sends no `settled` falls back to answered-or-declined", () => {
    expect(askRow(stored(file({ status: "answered" })), NOW).settled).toBe(true);
    expect(askRow(stored(file({ status: "declined" })), NOW).settled).toBe(true);
    expect(askRow(stored(file({ status: "open" })), NOW).settled).toBe(false);
    expect(askRow(stored(file({ status: "open" })), NOW).owed).toBeUndefined();
  });
  it("an old server: a provisional answer nobody followed up is not settled, and is once its asker comes back", () => {
    const p = stored(file({ id: "p1", note: "request: reword — say which" }));
    expect(askRow(p, NOW, [p]).settled).toBe(false);
    expect(rowInFilter(askRow(p, NOW, [p]), "open")).toBe(true);
    const f = stored(file({ id: "f1", status: "open", extra: "previous: test:asker/p1\n" }).replace("created: 2026-10-30T10:00", "created: 2026-10-30T12:00"));
    expect(askRow(p, NOW, [p, f]).settled).toBe(true);
    expect(rowInFilter(askRow(p, NOW, [p, f]), "settled")).toBe(true);
  });
  it("the server's word wins over the status: an answered ask the server calls unsettled stays unsettled", () => {
    expect(askRow(stored(file({ status: "answered" }), { settled: false, owed: { kind: "delivery", by: "test:asker", why: "undelivered: no pane" } }), NOW).settled).toBe(false);
  });
});

describe("an owed follow-up", () => {
  it("is in the main list, under Waiting on someone else, with ⏳ and the follow-up words", async () => {
    const a = stored(PROVISIONAL, FOLLOW);
    expect(filters(a)).toEqual(["open", "all"]);
    expect(sectionOf(a)).toBe("Waiting on someone else");
    const html = await rowHtml(a);
    expect(html).toContain("⏳");
    expect(html).toContain("Waiting on test:asker to follow up on your provisional answer");
    expect(html).toContain("row other");
  });
  it("the same row with settled: true is under Answered only, with no ⏳", async () => {
    const a = stored(PROVISIONAL, { settled: true });
    expect(filters(a)).toEqual(["settled", "all"]);
    expect(sectionOf(a)).toBeUndefined();
    expect(await rowHtml(a)).not.toContain("⏳");
  });
});

describe("delivery", () => {
  it("a delivered answer nobody has read yet is under Answered only", async () => {
    const a = stored(file({ extra: "delivery: delivered\n" }), { settled: true });
    expect(filters(a)).toEqual(["settled", "all"]);
    expect(await rowHtml(a)).not.toContain("⏳");
  });
  it("a partial delivery is in the main list with the delivery words, naming the seat it missed", async () => {
    const owed = { kind: "delivery" as const, by: "test:forwarder", why: "partial: test:forwarder: no pane" };
    const a = stored(file({ extra: "delivery: partial\ndeliveryNote: test:forwarder: no pane\n" }), { settled: false, owed });
    expect(filters(a)).toEqual(["open", "all"]);
    expect(sectionOf(a)).toBe("Waiting on someone else");
    const html = await rowHtml(a);
    expect(html).toContain("⏳");
    expect(html).toContain("Your answer has not reached test:forwarder: partial: test:forwarder: no pane");
  });
  it("a pending push younger than about 5 s shows no ⏳; an older one does", async () => {
    const owed = { kind: "delivery" as const, by: "test:asker", why: "pending" };
    const young = stored(file({ extra: "delivery: pending\n", answeredAt: new Date(NOW - 2000).toISOString() }), { settled: false, owed });
    const old = stored(file({ extra: "delivery: pending\n", answeredAt: new Date(NOW - 10_000).toISOString() }), { settled: false, owed });
    expect(await rowHtml(young)).not.toContain("⏳");
    expect(sectionOf(young)).toBe("Waiting on someone else");
    expect(await rowHtml(old)).toContain("⏳");
  });
});

describe("⏳ is the server's owed, never the client's draftSent", () => {
  it("a provisional row the server sends with nothing owed has no ⏳", async () => {
    const a = stored(PROVISIONAL, { settled: true });
    expect(askRow(a, NOW).draftSent).toBe(true);
    expect(await rowHtml(a)).not.toContain("⏳");
  });
  it("settled wins over a stray owed: no ⏳ and no owed on the row", async () => {
    const a = stored(PROVISIONAL, { settled: true, owed: FOLLOW.owed });
    const r = askRow(a, NOW);
    expect(r.owed).toBeUndefined();
    expect(r.waitMark).toBeUndefined();
    expect(await rowHtml(a)).not.toContain("⏳");
  });
  it("owedWords says each kind", () => {
    expect(owedWords({ kind: "follow-up", by: "test:a", why: "x" })).toBe("Waiting on test:a to follow up on your provisional answer");
    expect(owedWords({ kind: "delivery", by: "test:b, test:c", why: "undelivered: gone" })).toBe("Your answer has not reached test:b, test:c: undelivered: gone");
  });
});

describe("the main list's two parts", () => {
  it("open asks wait on you, owed ones on someone else, settled ones are in neither", () => {
    const you = stored(file({ id: "y1", status: "open" }), { settled: false });
    const other = stored(file({ id: "o1", note: "request: reword — more" }), FOLLOW);
    const done = stored(file({ id: "d1" }), { settled: true });
    const rows = [you, other, done].map((a) => askRow(a, NOW));
    const parts = listSections(rows.filter((r) => rowInFilter(r, "open")), "open");
    expect(parts.map((s) => [s.name, s.rows.map((r) => r.id)])).toEqual([
      ["Waiting on you", ["y1"]],
      ["Waiting on someone else", ["o1"]],
    ]);
  });
  it("an open ask addressed to another seat waits on someone else, and Waiting on you counts what the header counts", () => {
    const mine = stored(file({ id: "y1", status: "open" }), { settled: false });
    const theirs = stored(file({ id: "m1", status: "open", to: "manager:test" }), { settled: false });
    const owed = stored(file({ id: "o1", note: "request: reword — more" }), FOLLOW);
    const asks = [mine, theirs, owed];
    const rows = asks.map((a) => askRow(a, NOW, asks));
    const { inFilter, waiting } = sidebarView(rows, asks, undefined, "open");
    const parts = listSections(inFilter, "open");
    expect(parts.map((s) => [s.name, s.rows.map((r) => r.id)])).toEqual([
      ["Waiting on you", ["y1"]],
      ["Waiting on someone else", ["m1", "o1"]],
    ]);
    expect(parts[0].rows.length).toBe(waiting);
  });
  it("any other filter is one unnamed part", () => {
    const rows = [stored(file({ id: "d1" }), { settled: true })].map((a) => askRow(a, NOW));
    expect(listSections(rows, "settled")).toEqual([{ name: "", rows }]);
  });
  it("withdrawn and superseded are in All only, whatever the server says", () => {
    expect(filters(stored(file({ status: "withdrawn" }), { settled: true }))).toEqual(["all"]);
    expect(filters(stored(file({ status: "superseded" }), { settled: true }))).toEqual(["all"]);
    expect(filters(stored(file({ status: "superseded" })))).toEqual(["all"]);
  });
});

describe("followUpOf folds case", () => {
  it("a follow-up from domain:Language naming domain:Language/p1 follows up domain:language's p1", () => {
    const p = stored(file({ id: "p1", from: "domain:language", note: "request: reword — say which" }), undefined, "domain:language");
    const f = stored(
      `---\nid: f1\nto: operator\nfrom: domain:Language\nstatus: open\nrevision: 1\ncreated: 2026-10-30T12:00:00.000Z\nprevious: domain:Language/p1\n---\n\n## Choose one: ¶ASK_GO — again?\n- [ ] [YES] Yes\n`,
      undefined,
      "domain:Language",
    );
    expect(followUpOf(p, [p, f])).toBe("domain:Language/f1");
  });
  it("the mirror: a provisional ask under domain:Language, followed up by a ref written domain:language/p1", () => {
    const p = stored(file({ id: "p1", from: "domain:Language", note: "request: reword — say which" }), undefined, "domain:Language");
    const f = stored(
      `---\nid: f1\nto: operator\nfrom: domain:language\nstatus: open\nrevision: 1\ncreated: 2026-10-30T12:00:00.000Z\nprevious: domain:language/p1\n---\n\n## Choose one: ¶ASK_GO — again?\n- [ ] [YES] Yes\n`,
      undefined,
      "domain:language",
    );
    expect(followUpOf(p, [p, f])).toBe("domain:language/f1");
  });
});

describe("source pins", () => {
  const src = (f: string) => fs.readFileSync(path.join(__dirname, "..", "src", "client", f), "utf8");
  it("model.ts imports settle.ts only as a type: settle.ts imports model.ts at runtime, so a value import would close a cycle", () => {
    const m = src("model.ts");
    const lines = m.split("\n").filter((l) => /from "\.\.\/lib\/settle\.ts"/.test(l));
    expect(lines.length).toBeGreaterThan(0);
    for (const l of lines) expect(l).toMatch(/^import type \{[^}]*\} from "\.\.\/lib\/settle\.ts";$/);
  });
  it("a group inside a part of the list is an h3 under the part's h2", () => {
    const app = src("App.tsx");
    expect(app).toMatch(/<h2 className="part-name">/);
    expect(app).toMatch(/<h3 className="group-name">/);
    expect(app).not.toMatch(/<h2 className="group-name">/);
  });
});
