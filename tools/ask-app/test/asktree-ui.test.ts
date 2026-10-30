/**
 * ASKTREEUI: more context per answer. The per-option fields the parser reads (Cost, Effort, Unblocks,
 * Then and Elegance, lib/format.ts AskOption) are drawn under each option, Elegance as a first-class
 * line beside Cost; an option shows the forks that picking it opens (derived from DependsOn); a fork
 * whose own Reversible: says no gets a one-way badge; a fork can lay its options side by side; and an
 * ask with several forks gets an outline. Real asks from ~/.claude/data/yarik/asks are rendered from
 * test/fixtures/asktreeui. Server-side render only (react-dom/server).
 */
import { describe, expect, it, vi } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseAskFile, ticketKeys } from "../src/lib/format.ts";
import { compareRows, forkGivesElegance, isOneWay, markReached, opensUnder, outlineOf, anyAnswerOpens } from "../src/client/tree.ts";

const here = path.dirname(fileURLToPath(import.meta.url));
const fixture = (name: string) => fs.readFileSync(path.join(here, "fixtures", "asktreeui", `${name}.md`), "utf8");
const head = (status = "open") => `---\nid: t1\nto: operator\nfrom: idealic:ui\nstatus: ${status}\nrevision: 1\ncreated: 2026-10-30T10:00:00.000Z\n---\n\n`;
const stored = (text: string, seat = "idealic:ui") => ({ ...parseAskFile(text), seat, file: "/x.md", mtimeMs: 0 });

async function render(text: string, seat?: string) {
  const { AskDetail } = await import("../src/client/App.tsx");
  const ask = stored(text, seat);
  return renderToStaticMarkup(createElement(AskDetail, { ask, all: [ask], onChanged: () => {} }));
}
/** The markup of one option row, from its code chip to the next one (or the card's end). */
function optionHtml(html: string, code: string): string {
  const at = html.indexOf(`<code class="okey">${code}</code>`);
  expect(at, `option ${code} is drawn`).toBeGreaterThan(-1);
  return html.slice(at, html.indexOf("</label>", at));
}
/** Markup as the reader sees it: tags dropped, the few entities React writes decoded. */
const textOf = (html: string) => html.replace(/<[^>]+>/g, "").replace(/&#x27;/g, "'").replace(/&quot;/g, '"').replace(/&amp;/g, "&");
/** The markup of one fork card. */
function forkHtml(html: string, label: string): string {
  const at = html.indexOf(`<article class="fork" id="fork-`);
  const start = html.indexOf(`-${label}" data-kind=`, at);
  expect(start, `fork ${label} is drawn`).toBeGreaterThan(-1);
  const end = html.indexOf("</article>", start);
  return html.slice(start, end);
}

const MIXED = head() + [
  "## ¶ASK_PICK: Choose one: Which way?",
  "Context: two ways in.",
  "- [ ] [A] The first way",
  "  It does a thing.",
  "  Cost: a day",
  "  Elegance: high — one path",
  "- [ ] [B] The second way",
  "  It does another thing.",
  "  Cost: an hour",
  "",
].join("\n");

describe("1. per-option fields: Cost, Effort, Unblocks, Then and Elegance under each option", () => {
  it("real ask council-panel-picks: every option shows its Cost, Elegance, Unblocks and Then lines", async () => {
    const html = await render(fixture("council-panel-picks"), "meta:utils");
    const count = optionHtml(html, "COUNT");
    expect(count).toContain('class="opt-elegance"');
    expect(textOf(count)).toContain("Elegance one meaning per place");
    expect(textOf(count)).toContain("Unblocks nothing; this is what's built");
    expect(textOf(count)).toContain("Then no change");
    expect(textOf(count)).toContain("Cost you read the panel");
    const attach = textOf(optionHtml(html, "ATTACH"));
    expect(attach).toContain("Elegance complete history, at the cost of editing settled records");
    expect(attach).toContain("Then meta:engine or I run it");
  });

  it("S5: Elegance sits straight under the label, before the description and Cost, so a long description never pushes it down", async () => {
    const html = await render(fixture("raisehome"), "core:kernel");
    const o = optionHtml(html, "IDE17");
    const label = o.indexOf('class="opt-text"');
    const eleg = o.indexOf('class="opt-elegance');
    const desc = o.indexOf('class="opt-desc');
    const cost = o.indexOf('class="opt-cost');
    const then = o.indexOf("<b>Then</b>");
    expect(label).toBeGreaterThan(-1);
    expect(desc).toBeGreaterThan(-1);
    expect(eleg).toBeGreaterThan(label);
    expect(desc).toBeGreaterThan(eleg);
    expect(cost).toBeGreaterThan(desc);
    expect(then).toBeGreaterThan(cost);
    expect(textOf(o)).toContain("Elegance high, because IDE-17 already names this work.");
  });

  it("the fields are no longer echoed into the description text, so each is drawn once", async () => {
    const q = parseAskFile(fixture("council-panel-picks")).questions[0];
    expect(q.options[0].description).toBe('The dashed "Suggested picks" bar keeps meaning the asker\'s own lean. The panel\'s view sits beside each option as "N of M lenses picked this".');
    expect(q.options[0].elegance).toBe("one meaning per place");
    const html = await render(fixture("council-panel-picks"), "meta:utils");
    expect(optionHtml(html, "COUNT").match(/one meaning per place/g)).toHaveLength(1);
  });

  it("a ticket named only in an option's Unblocks: is still one of the ask's tickets", () => {
    const t = head() + "## ¶ASK_X: Choose one: Go?\n- [ ] [GO] Go\n  Cost: a day\n  Unblocks: IDE-901\n- [ ] [NO] Not yet\n  Cost: none\n";
    expect(ticketKeys(parseAskFile(t))).toContain("IDE-901");
  });

  it("on a fork where some options give Elegance and others don't, the others say \"no elegance given\"", async () => {
    const html = await render(MIXED);
    expect(textOf(optionHtml(html, "A"))).toContain("Elegance high — one path");
    expect(optionHtml(html, "A")).not.toContain("no elegance given");
    expect(optionHtml(html, "B")).toMatch(/class="opt-elegance none"[^>]*><b>Elegance<\/b> <span class="muted">no elegance given<\/span>/);
    expect(forkGivesElegance(parseAskFile(MIXED).questions[0])).toBe(true);
  });

  it("a fork where no option gives Elegance draws no Elegance line at all", async () => {
    const html = await render(fixture("broken-worktrees"), "manager:director");
    expect(html).not.toContain("opt-elegance");
    expect(html).not.toContain("no elegance given");
  });
});

describe("2. SHOWFOLLOW: under an option, the forks that picking it opens", () => {
  it("opensUnder derives them from DependsOn on the other forks", () => {
    const ask = parseAskFile(fixture("broken-worktrees"));
    const [dispose] = ask.questions;
    const cen = dispose.options.find((o) => o.code === "CEN")!;
    const all = dispose.options.find((o) => o.code === "ALL")!;
    expect(opensUnder(ask.questions, dispose, cen)).toEqual([{ index: 1, label: "WHO", title: "Who runs it?" }]);
    expect(opensUnder(ask.questions, dispose, all)).toEqual([]);
  });

  it("real ask broken-worktrees: CEN says it opens ¶ASK_WHO, before anything is picked; ALL and LVE say nothing", async () => {
    const html = await render(fixture("broken-worktrees"), "manager:director");
    const cen = optionHtml(html, "CEN");
    expect(cen).toMatch(/class="opt-opens"/);
    expect(cen).toMatch(/Opens <a [^>]*href="#manager:director\/broken-worktrees\/WHO"[^>]*>¶ASK_WHO<\/a>/);
    expect(cen).toContain("Who runs it?");
    expect(optionHtml(html, "ALL")).not.toContain("opt-opens");
    expect(optionHtml(html, "LVE")).not.toContain("opt-opens");
  });

  it("real ask asktree-build: TRAPS opens ¶ASK_TREEORDER", async () => {
    const html = await render(fixture("asktree-build"), "meta:utils");
    expect(optionHtml(html, "TRAPS")).toContain("¶ASK_TREEORDER");
    expect(optionHtml(html, "FLOOR")).not.toContain("opt-opens");
  });

  it("two forks hanging off one option read \"+2 follow-ups\" and name both", async () => {
    const t = head() + [
      "## ¶ASK_P: Choose one: Which?",
      "- [ ] [X] Ex",
      "  Cost: a",
      "- [ ] [Y] Why",
      "  Cost: b",
      "",
      "## ¶ASK_C1: Choose one: First child?",
      "DependsOn: ASK_P=X",
      "- [ ] [A] a",
      "- [ ] [B] b",
      "",
      "## ¶ASK_C2: Text: Second child?",
      "DependsOn: ASK_P=X",
      "",
    ].join("\n");
    const html = await render(t);
    const x = optionHtml(html, "X");
    expect(x).toContain("+2 follow-ups");
    expect(x).toContain("¶ASK_C1");
    expect(x).toContain("¶ASK_C2");
    expect(optionHtml(html, "Y")).not.toContain("follow-up");
  });

  it("a fork that follows any answer is named once on its parent fork, never under each option", async () => {
    const t = head() + "## ¶ASK_P: Choose one: Which?\n- [ ] [X] Ex\n- [ ] [Y] Why\n\n## ¶ASK_C: Text: Then what?\nDependsOn: ASK_P\n";
    const ask = parseAskFile(t);
    expect(anyAnswerOpens(ask.questions, ask.questions[0])).toEqual([{ index: 1, label: "C", title: "Then what?" }]);
    expect(opensUnder(ask.questions, ask.questions[0], ask.questions[0].options[0])).toEqual([]);
    const html = await render(t);
    expect(forkHtml(html, "P")).toMatch(/Any answer opens <a [^>]*>¶ASK_C<\/a>/);
    expect(optionHtml(html, "X")).not.toContain("opt-opens");
  });

  it("nested options under an option stay as they are: shown only once it is picked", async () => {
    const t = head() + "## ¶ASK_N: Choose one: Nest?\n- [ ] [P] Parent\n  - [ ] [C] Child\n- [ ] [Q] Other\n";
    const html = await render(t);
    expect(html).not.toContain('<code class="okey">C</code>');
  });
});

describe("3. one-way badge: only where the data marks it", () => {
  it("isOneWay reads the fork's own Reversible: value, never option prose", () => {
    expect(isOneWay("no — a landed commit on main is reverted, not undone")).toBe(true);
    expect(isOneWay("No, once ¶concurrent leaves the language")).toBe(true);
    expect(isOneWay("one-way after reflog expiry")).toBe(true);
    expect(isOneWay("irreversible")).toBe(true);
    expect(isOneWay("yes")).toBe(false);
    expect(isOneWay("yes until IDE-99 moves the rows; after that, changing the partition means a migration")).toBe(false);
    expect(isOneWay("a comment can be followed by a separate ticket later; a filed ticket can be closed as a duplicate.")).toBe(false);
    expect(isOneWay("nothing is lost")).toBe(false);
    // Real values (packages:converge/afford-design, core:ops/ide311-stage-or-live): a later "no" is not the answer.
    expect(isOneWay("yes — no npm name has been used, and nothing moves under CLEANUP")).toBe(false);
    expect(isOneWay("yes for the design; no for any single release published live.")).toBe(false);
    expect(isOneWay(undefined)).toBe(false);
  });

  it("real ask mergefest-permission (Reversible: no — …) gets the one-way badge in its fork head", async () => {
    const html = await render(fixture("mergefest-permission"), "domain:Agent");
    const fork = forkHtml(html, "FEST");
    expect(fork).toMatch(/<span class="chip oneway" title="Reversible: no — a landed commit on main is reverted, not undone">One-way<\/span>/);
  });

  it("real ask raisehome (Reversible: a comment can be followed…) gets no badge; neither does an option whose prose says one-way", async () => {
    expect(await render(fixture("raisehome"), "core:kernel")).not.toContain("chip oneway");
    const t = head() + "## ¶ASK_R: Choose one: Re-chain?\n- [ ] [B] Re-chain now\n  One-way: a withdrawn root cannot be reissued.\n  Cost: big\n- [ ] [L] Later\n  Cost: none\n";
    expect(await render(t)).not.toContain("chip oneway");
  });
});

describe("4. COMPARE: a fork's options side by side, one row per field", () => {
  it("compareRows: Cost, Elegance, Effort, Unblocks, Then, with the empty rows named, not drawn", () => {
    const q = parseAskFile(fixture("council-panel-picks")).questions[0];
    const { columns, rows, omitted } = compareRows(q);
    expect(columns.map((c) => c.code)).toEqual(["COUNT", "MAJORITY"]);
    expect(rows.map((r) => r.label)).toEqual(["Cost", "Elegance", "Effort", "Unblocks", "Then"]);
    expect(rows.find((r) => r.label === "Elegance")!.cells).toEqual(["one meaning per place", "convenient, but the bar stops meaning one thing"]);
    expect(rows.find((r) => r.label === "Effort")!.same).toBe(true);
    expect(omitted).toEqual(["Panel"]);
  });

  it("an option with no Elegance on a fork that gives it reads \"no elegance given\" in its cell", () => {
    const { rows } = compareRows(parseAskFile(MIXED).questions[0]);
    expect(rows.find((r) => r.label === "Elegance")!.cells).toEqual(["high — one path", undefined]);
    expect(rows.find((r) => r.label === "Elegance")!.missing).toBe("no elegance given");
  });

  it("a fork with panel reads gets a Panel row from panel.ts's tally", () => {
    const t = head() + "## ¶ASK_A: Choose one: Which root?\nPanel: Security → B — small blast\nPanel: Economist → A — simpler\nPanel: Operator → B — fewer pages\n- [ ] [A] One root\n  Cost: x\n- [ ] [B] A separate root\n  Cost: y\n";
    const { rows } = compareRows(parseAskFile(t).questions[0]);
    expect(rows.find((r) => r.label === "Panel")!.cells).toEqual(["1 of 3 lenses picked this", "2 of 3 lenses picked this"]);
  });

  it("the fork offers a Compare toggle, off by default; opened, it draws the table with a column per option", async () => {
    const html = await render(fixture("council-panel-picks"), "meta:utils");
    expect(forkHtml(html, "SUGGEST")).toMatch(/<button type="button" class="chip toggle compare-toggle" aria-pressed="false"[^>]*>⇆ Compare side by side<\/button>/);
    expect(html).not.toContain('<table class="compare"');
    const { CompareView } = await import("../src/client/App.tsx");
    const q = parseAskFile(fixture("council-panel-picks")).questions[0];
    const open = renderToStaticMarkup(createElement(CompareView, { q, initialOpen: true }));
    expect(open).toContain('aria-pressed="true"');
    expect(open).toContain('<table class="compare"');
    expect(open).toMatch(/<th scope="col"[^>]*><code class="okey">COUNT<\/code>/);
    expect(open).toMatch(/<th scope="row">Elegance<\/th>/);
    // Stacked on a narrow screen: each cell carries its option, for the stacked layout to label it.
    // S6: stacked, each value is labelled with its option's code and label.
    expect(open).toContain('<td data-opt="MAJORITY · Yes, the panel&#x27;s majority pick joins the bar, …">');
    expect(open).toContain('<td data-opt="COUNT · No, show them only as the count and the …">');
  });

  it("S6: the compare table stacks on the card's width (a container query), sooner the more options it has", () => {
    const css = fs.readFileSync(path.join(here, "..", "src", "client", "styles.css"), "utf8");
    expect(css).toMatch(/\.compare-view \{[^}]*container: cmp \/ inline-size/);
    const narrow = css.match(/@container cmp \(max-width: 560px\) \{[^@]*table\.compare[^@]*\}/);
    expect(narrow?.[0]).toMatch(/display: block/);
    expect(narrow?.[0]).toMatch(/attr\(data-opt\)/);
    expect(css).toMatch(/@container cmp \(max-width: 720px\) \{[^@]*\[data-cols="4"\][^@]*display: block/);
    expect(css).toMatch(/@container cmp \(max-width: 900px\) \{[^@]*\[data-cols="5"\][^@]*display: block/);
    expect(css).not.toMatch(/@media[^{]*\{[^}]*table\.compare/);
  });

  it("S6: the compare view says how many options it lays out, capped at 5", async () => {
    const { CompareView } = await import("../src/client/App.tsx");
    const two = parseAskFile(fixture("council-panel-picks")).questions[0];
    const six = parseAskFile(fixture("asktree-build")).questions[0];
    expect(renderToStaticMarkup(createElement(CompareView, { q: two }))).toContain('<div class="compare-view" data-cols="2">');
    expect(renderToStaticMarkup(createElement(CompareView, { q: six }))).toContain('<div class="compare-view" data-cols="5">');
  });

  it("a fork of one option, or a free-text fork, offers no compare", async () => {
    const t = head() + "## ¶ASK_T: Text: Why?\n\n## ¶ASK_O: Choose one: Only?\n- [ ] [A] Only one\n";
    expect(await render(t)).not.toContain("compare-toggle");
  });
});

describe("5. outline: an ask with several forks lists them at the top", () => {
  it("outlineOf: each fork's label, title, answered or not, and what it waits on", () => {
    const ask = parseAskFile(fixture("asktree-build"));
    expect(outlineOf(ask.questions, {})).toEqual([
      { index: 0, label: "TREEFIX", title: "Which parts do we build first?", answered: false, waiting: false, picked: [], picks: [], after: undefined, opens: ["TREEORDER"] },
      { index: 1, label: "TREEORDER", title: "Should the parser also accept the name after the kind word?", answered: false, waiting: true, picked: [], picks: [], after: "ASK_TREEFIX=TRAPS", opens: [] },
    ]);
    const done = outlineOf(ask.questions, ask.answer!.answers!);
    expect(done.map((e) => [e.label, e.answered, e.waiting, e.picked])).toEqual([
      ["TREEFIX", true, false, ["TRAPS", "FLOOR", "SHOWFOLLOW", "FIELDS", "TEACH", "COMPARE"]],
      ["TREEORDER", true, false, ["REFUSE"]],
    ]);
    // N4: the picks' labels, as the options word them.
    expect(done[1].picks).toEqual([{ value: "REFUSE", label: "No, refuse that order and keep one form (recommended)" }]);
  });

  it("S2: a fork whose parent was answered with another code is not opened, not waiting", () => {
    const ask = parseAskFile(fixture("broken-worktrees"));
    const [, who] = outlineOf(ask.questions, ask.answer!.answers!);
    expect(who.waiting).toBe(false);
    expect(who.notOpened).toBe("ASK_DISPOSE = ALL");
    const before = outlineOf(ask.questions, {})[1];
    expect(before.waiting).toBe(true);
    expect(before.notOpened).toBeUndefined();
    const opened = outlineOf(ask.questions, { DISPOSE: ["CEN"] })[1];
    expect(opened.waiting).toBe(false);
    expect(opened.notOpened).toBeUndefined();
  });

  it("S5: an answered entry carries each pick's Elegance where the option states one", () => {
    const ask = parseAskFile(fixture("raisehome"));
    expect(outlineOf(ask.questions, { RAISEHOME: ["IDE17"] })[0].picks).toEqual([
      { value: "IDE17", label: "Post the checkpoint on IDE-17", elegance: "high, because IDE-17 already names this work." },
    ]);
  });

  it("S5/N4: the outline names picks by label with their Elegance, and past two says how many more", async () => {
    const two = head() + "## ¶ASK_A: Choose one: First?\n- [ ] [X] Ex way\n  Cost: a\n  Elegance: high — one path\n- [ ] [Y] Why way\n  Cost: b\n  Elegance: low\n\n## ¶ASK_B: Choose: Second?\n- [ ] [P] Pe\n- [ ] [Q] Qu\n- [ ] [R] Ar\n";
    const answered = two.replace("status: open", "status: answered") + '\n```json answer\n{"answers":{"A":["X"],"B":["P","Q","R"]},"answeredBy":"operator","answeredAt":"2026-10-30T10:00:00.000Z","revision":1}\n```\n';
    const html = await render(answered);
    const nav = textOf(html.slice(html.indexOf('<nav class="outline"'), html.indexOf("</nav>")));
    expect(nav).toContain("answered · Ex way (Elegance: high — one path)");
    expect(nav).toContain("answered · Pe, Qu +1 more");
    expect(nav).not.toMatch(/answered · X\b/);
  });

  it("real ask asktree-build: the outline sits at the top, each entry a link that focuses its fork", async () => {
    const html = await render(fixture("asktree-build"), "meta:utils");
    const at = html.indexOf('<nav class="outline"');
    expect(at).toBeGreaterThan(-1);
    expect(at).toBeLessThan(html.indexOf('<article class="fork"'));
    const nav = html.slice(at, html.indexOf("</nav>", at));
    expect(nav).toMatch(/<a [^>]*href="#meta:utils\/asktree-build\/TREEFIX"/);
    expect(nav).toMatch(/<a [^>]*href="#meta:utils\/asktree-build\/TREEORDER"/);
    expect(nav).toContain("after ASK_TREEFIX=TRAPS");
    expect(nav).toContain("answered");
    expect(nav).toContain("Which parts do we build first?");
  });

  it("S2, real ask broken-worktrees: the dependent fork the answer never opened reads \"not opened (ASK_DISPOSE = ALL)\"", async () => {
    const html = await render(fixture("broken-worktrees"), "manager:director");
    const nav = html.slice(html.indexOf('<nav class="outline"'), html.indexOf("</nav>"));
    expect(nav).toMatch(/data-state="answered"[^]*DISPOSE/);
    expect(nav).toMatch(/data-state="not-opened"[^]*WHO/);
    expect(textOf(nav)).toContain("not opened (ASK_DISPOSE = ALL)");
    expect(nav).not.toContain('data-state="waiting"');
  });

  it("N2: an outline click marks the fork it reached, then lets go", () => {
    vi.useFakeTimers();
    const seen: string[] = [];
    const el = { classList: { add: (c: string) => seen.push(`+${c}`), remove: (c: string) => seen.push(`-${c}`) } };
    markReached(el, 1500);
    expect(seen).toEqual(["-reached", "+reached"]);
    vi.advanceTimersByTime(1499);
    expect(seen).toHaveLength(2);
    vi.advanceTimersByTime(1);
    expect(seen).toEqual(["-reached", "+reached", "-reached"]);
    vi.useRealTimers();
    expect(() => markReached(null)).not.toThrow();
  });

  it("N2: the stylesheet draws a visible ring on a reached fork", () => {
    const css = fs.readFileSync(path.join(here, "..", "src", "client", "styles.css"), "utf8");
    expect(css).toMatch(/\.fork\.reached \{[^}]*outline: 2px solid var\(--accent\)/);
  });

  it("an ask of one fork draws no outline", async () => {
    expect(await render(fixture("raisehome"), "core:kernel")).not.toContain('class="outline"');
  });
});
