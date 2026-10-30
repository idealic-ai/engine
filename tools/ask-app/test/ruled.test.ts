/**
 * "Ruled below you" (operator 01:56): the filter tab that replaced Drafts, its URL, the drafts still
 * reachable, and the card's "Ruled by <seat> · <time>".
 */
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import { parseAskFile } from "../src/lib/format.ts";
import { askRow, rowInFilter, ruledBelow, sortRuled } from "../src/client/model.ts";
import { parseRoute, serializeRoute } from "../src/client/route.ts";

const head = (status: string, extra = "") => `---\nid: a1\nto: operator\nfrom: idealic:ui\nstatus: ${status}\nrevision: 2\ncreated: 2026-10-29T10:00:00.000Z\n${extra}---\n\n`;
const BODY = "## ¶ASK_A: Choose one: First?\n- [ ] [X] x\n- [ ] [Y] y\n";
const answered = (answer: object, id = "a1", extra = "") =>
  ({ ...parseAskFile(head("answered", extra).replace("id: a1", `id: ${id}`) + BODY + "\n```json answer\n" + JSON.stringify(answer) + "\n```\n"), seat: "idealic:ui", file: "/x.md", mtimeMs: 0 });
const NOW = Date.parse("2026-10-29T13:00:00.000Z");
const src = (f: string) => fs.readFileSync(path.join(import.meta.dirname, "../src/client", f), "utf8");

describe("the rule: answered by a seat itself", () => {
  it("a seat's own answer is ruled below you; the operator's, a relay of the operator's words, or no answer are not", () => {
    expect(ruledBelow(answered({ answers: { A: ["X"] }, answeredBy: "manager:meta", answeredAt: "2026-10-29T12:00:00Z" }))).toBe(true);
    expect(ruledBelow(answered({ declined: true, reason: "out of scope", answeredBy: "manager:meta" }))).toBe(true);
    expect(ruledBelow(answered({ answers: { A: ["X"] }, answeredBy: "operator", answeredVia: "browser" }))).toBe(false);
    expect(ruledBelow(answered({ answers: { A: ["X"] }, answeredBy: "operator", answeredVia: "relay:manager:docs" }))).toBe(false);
    expect(ruledBelow(answered({ answers: { A: ["X"] }, answeredBy: "manager:docs", answeredVia: "relay:manager:docs" }))).toBe(false);
    expect(ruledBelow(parseAskFile(head("open") + BODY))).toBe(false);
  });

  it("the row carries who ruled and when; the filter takes only those, newest ruling first", () => {
    const old = askRow(answered({ answers: { A: ["X"] }, answeredBy: "manager:meta", answeredAt: "2026-10-29T09:00:00Z" }, "old"), NOW);
    const recent = askRow(answered({ answers: { A: ["Y"] }, answeredBy: "manager:domain", answeredAt: "2026-10-29T12:30:00Z" }, "new"), NOW);
    const mine = askRow(answered({ answers: { A: ["X"] }, answeredBy: "operator" }, "mine"), NOW);
    expect(recent).toMatchObject({ ruledBy: "manager:domain", ruledAt: "2026-10-29T12:30:00Z" });
    expect(mine.ruledBy).toBeUndefined();
    const rows = [old, mine, recent];
    expect(sortRuled(rows.filter((r) => rowInFilter(r, "ruled"))).map((r) => r.id)).toEqual(["new", "old"]);
    // The tab's count is the same predicate: 2 here; Settled still counts all three.
    expect(rows.filter((r) => rowInFilter(r, "ruled"))).toHaveLength(2);
    expect(rows.filter((r) => rowInFilter(r, "settled"))).toHaveLength(3);
  });

  it("the tab replaces Drafts, with its count like the others", () => {
    const app = src("App.tsx");
    expect(app).toContain('const FILTERS: Filter[] = ["open", "ruled", "settled", "all"];');
    expect(app).toContain('ruled: "Ruled below you"');
    expect(app).not.toMatch(/"Drafts"/);
    expect(app).toMatch(/\{FILTER_LABEL\[f\]\} <span className="n">\{count\(f\)\}<\/span>/);
    // ASKSEARCH SHOULD-2: the count moved into search.ts's sidebarView, beside the list it must agree with.
    expect(src("search.ts")).toMatch(/const count = \(f: Filter\) => rows\.filter\(\(r\) => rowInFilter\(r, f\)\)\.length;/);
    expect(app).toMatch(/const \{ rows, inFilter, count, waiting \} = useMemo\(\(\) => sidebarView\(/);
  });

  it("a ruled row's meta says who ruled and how long ago", async () => {
    const { AskRowButton } = await import("../src/client/App.tsx");
    const r = askRow(answered({ answers: { A: ["X"] }, answeredBy: "manager:meta", answeredAt: new Date(Date.now() - 5 * 60000).toISOString() }), NOW);
    const html = renderToStaticMarkup(createElement(AskRowButton, { r, current: false, onPick: () => {}, slim: false }));
    expect(html).toMatch(/<span class="left zero ruled" title="[^"]+">ruled by manager:meta · 5m ago<\/span>/);
  });
});

describe("the URL", () => {
  it("?filter=ruled round-trips", () => {
    const r = parseRoute("/", "?filter=ruled", "");
    expect(r).toEqual({ section: "asks", filter: "ruled", group: "none" });
    expect(serializeRoute(r)).toBe("/?filter=ruled");
  });
  it("an old ?filter=drafts link lands on Open with the drafts tray shown", () => {
    const r = parseRoute("/a/idealic:ui/a1", "?filter=drafts&group=seat", "");
    expect(r).toEqual({ section: "asks", ask: "idealic:ui/a1", filter: "open", group: "seat", drafts: true });
    expect(serializeRoute(r)).toBe("/a/idealic:ui/a1?group=seat&drafts=1");
    expect(parseRoute("/", "?drafts=1", "")).toMatchObject({ filter: "open", drafts: true });
  });
});

describe("drafts stay reachable", () => {
  it("the tray still lists the operator's own drafts", async () => {
    const { trayDrafts } = await import("../src/client/App.tsx");
    const d = { ...parseAskFile(head("open", "draft: 2026-10-29T11:00:00.000Z\n") + BODY + '\n```json draft\n{"answers":{"A":["X"]},"answeredBy":"operator","basedOn":2,"savedAt":"2026-10-29T11:00:00.000Z"}\n```\n'), seat: "s", file: "/x", mtimeMs: 0 };
    expect(trayDrafts([d])).toHaveLength(1);
    expect(askRow(d, NOW).draft).toBe(true); // and its row keeps the ✎ mark
  });
  it("the tray can be hidden, the list then offers '✎ N drafts' to bring it back, and ?drafts=1 shows it", () => {
    const app = src("App.tsx");
    expect(app).toMatch(/\{drafts\.length > 0 && !trayHidden && \(\s*<div className="tray"/);
    expect(app).toMatch(/\{drafts\.length > 0 && trayHidden && \(\s*<p className="side-drafts"><button className="linkish" onClick=\{showTray\}>✎ \{drafts\.length\} draft/);
    expect(app).toMatch(/useState\(\(\) => !route\.drafts && store\.get\("askclient\.trayHidden"\) === "1"\)/);
  });
});

describe("the card", () => {
  it("shows 'Ruled by <seat> · <time>' above the answer, and points at Overrule (IDE-339)", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const a = answered({ answers: { A: ["X"] }, answeredBy: "manager:meta", answeredAt: "2026-10-29T12:00:00Z" });
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    expect(html).toMatch(/<p class="ruled-by" role="note"><b>Ruled by manager:meta<\/b> · <time dateTime="2026-10-29T12:00:00Z"[^>]*>2026-10-29 12:00 \(/);
    expect(html).toContain("Overrule it to answer in its place.");
    expect(html.indexOf("ruled-by")).toBeLessThan(html.indexOf("Answered · revision"));
    const own = answered({ answers: { A: ["X"] }, answeredBy: "operator" });
    expect(renderToStaticMarkup(createElement(AskDetail, { ask: own, all: [own], onChanged: () => {} }))).not.toContain("ruled-by");
  });
});
