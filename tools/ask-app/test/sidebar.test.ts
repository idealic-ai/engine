/**
 * Sidebar compact (operator 01:42, ask 133537 fork SIDE): one line per ask with "N of M left", no
 * repeated "needs you" chip, who it waits on shown by the row's style, group-by unchanged.
 */
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import { parseAskFile } from "../src/lib/format.ts";
import { askRow, groupRows, rowInFilter } from "../src/client/model.ts";

const head = (extra = "") => `---\nid: a1\nto: operator\nfrom: idealic:ui\nstatus: open\nrevision: 1\ncreated: 2026-10-29T10:00:00.000Z\n${extra}---\n\n`;
const FIVE = ["A", "B", "C", "D", "E"].map((n) => `## ¶ASK_${n}: Choose one: ${n}?\n- [ ] [X] x\n- [ ] [Y] y\n`).join("\n");
const stored = (text: string, seat = "idealic:ui") => ({ ...parseAskFile(text), seat, file: "/x.md", mtimeMs: 0 });
const NOW = Date.parse("2026-10-29T13:00:00.000Z");
const draft = '\n```json draft\n{"answers":{"A":["X"],"B":["Y"]},"answeredBy":"operator","basedOn":1,"savedAt":"2026-10-29T11:00:00.000Z"}\n```\n';

async function row(text: string, opts: { groupBy?: "none" | "seat" | "topic"; slim?: boolean; seat?: string } = {}) {
  const { AskRowButton } = await import("../src/client/App.tsx");
  const r = askRow(stored(text, opts.seat), NOW);
  return { r, html: renderToStaticMarkup(createElement(AskRowButton, { r, current: false, onPick: () => {}, slim: !!opts.slim, groupBy: opts.groupBy })) };
}

describe("Sidebar compact", () => {
  it("no row renders a 'needs you' text; waiting on you is the row's style", async () => {
    const mine = await row(head("reserved-for: operator\n") + FIVE);
    expect(mine.r.waitingOnYou).toBe(true);
    expect(mine.html).not.toMatch(/needs you/i);
    expect(mine.html).toMatch(/^<button class="row you"/);
    const theirs = await row(head().replace("to: operator", "to: meta:utils") + FIVE);
    expect(theirs.r.waitingOnYou).toBe(false);
    expect(theirs.html).toMatch(/^<button class="row other"/);
    expect(fs.readFileSync(path.join(import.meta.dirname, "../src/client/App.tsx"), "utf8")).not.toMatch(/needs you/);
  });

  it("one title, then one meta line: seat · age · N of M left; no bar, no chip row", async () => {
    const { html } = await row(head("draft: 2026-10-29T11:00:00.000Z\n") + FIVE + draft);
    expect(html).toContain('<span class="row-meta"><span class="seat">idealic:ui</span><span class="age"');
    expect(html).toContain('<span class="left">3 of 5 left</span></span></button>');
    expect(html).not.toContain('class="bar"');
    expect(html).not.toContain('class="marks"');
    expect(html).not.toMatch(/class="mk[ "]/);
    expect((html.match(/class="row-meta"/g) ?? []).length).toBe(1);
  });

  it("reserved and draft are small marks with their words in title and label, never a text chip", async () => {
    const { html } = await row(head("reserved-for: operator\ndraft: 2026-10-29T11:00:00.000Z\n") + FIVE + draft);
    expect(html).toContain('<span class="mk-i res" title="Reserved for you: only you may answer; seats may forward it" aria-label="Reserved for you: only you may answer; seats may forward it">◆</span>');
    expect(html).toContain('<span class="mk-i draft" title="Your draft is saved, not sent" aria-label="Your draft is saved, not sent">✎</span>');
    expect(html).not.toContain(">reserved for you<");
    expect(html).not.toContain(">draft<");
  });

  it("grouped by seat, the row does not repeat the seat its heading names", async () => {
    const { html } = await row(head() + FIVE, { groupBy: "seat" });
    expect(html).not.toContain('class="seat"');
    expect(html).toContain("5 of 5 left");
  });

  it("group-by and the filters are unchanged", () => {
    const a = askRow(stored(head("topic: proofs\n") + FIVE), NOW);
    const b = askRow(stored(head().replace("from: idealic:ui", "from: meta:utils") + FIVE, "meta:utils"), NOW);
    expect(groupRows([a, b], "seat").map((g) => g.name)).toEqual(["idealic:ui", "meta:utils"]);
    expect(groupRows([a, b], "topic").map((g) => g.name)).toEqual(["proofs", "No topic"]);
    expect(groupRows([a, b], "none")).toEqual([{ name: "", rows: [a, b] }]);
    expect([a, b].filter((r) => rowInFilter(r, "open"))).toHaveLength(2);
  });

  it("the stylesheet: two-line title, bold accent bar for you, muted for others, tighter rows", () => {
    const css = fs.readFileSync(path.join(import.meta.dirname, "../src/client/styles.css"), "utf8");
    expect(css).toMatch(/\.row-title \{[^}]*-webkit-line-clamp: 2/);
    expect(css).toMatch(/\.row\.you \{ border-left-color: var\(--accent\); \}/);
    expect(css).toMatch(/\.row\.you \.row-title \{ font-weight: 650;/);
    expect(css).toMatch(/\.row\.other \.row-title \{[^}]*color: var\(--ink-2\)/);
    expect(css).toMatch(/\n\.row \{ gap: 2px; padding: 6px 12px 6px 9px; \}/);
  });
});
