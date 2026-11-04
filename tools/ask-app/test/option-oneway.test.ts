/**
 * WAKEUI 2: an option's own `Reversible:` line (AskOption.reversible, ASKDEPS) is drawn by the card, so
 * it no longer needs echoing in the description. One-way options get a badge of their own, the
 * fork-level badge stays, every option's line stays readable, and the compare view gets a row.
 */
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { parseAskFile } from "../src/lib/format.ts";
import { compareRows } from "../src/client/tree.ts";

const HEAD = "---\nid: t1\nto: operator\nfrom: test:asker\nstatus: open\nrevision: 1\ncreated: 2026-10-30T10:00:00.000Z\n---\n\n";
const FORK = HEAD + [
  "## ¶ASK_M: Choose one: Migrate?",
  "Reversible: no — the fork as a whole",
  "- [ ] [DROP] Drop the column",
  "  Removes it for good.",
  "  Reversible: no — the data is gone",
  "  Cost: an hour",
  "- [ ] [KEEP] Keep it",
  "  Leaves it alone.",
  "  Reversible: yes, within the day",
  "  Cost: nothing",
  "- [ ] [PARK] Park it",
  "  Cost: nothing",
  "",
].join("\n");
const stored = (text: string) => ({ ...parseAskFile(text), seat: "test:asker", file: "/x.md", mtimeMs: 0 });
async function render(text: string) {
  const { AskDetail } = await import("../src/client/App.tsx");
  const ask = stored(text);
  return renderToStaticMarkup(createElement(AskDetail, { ask, all: [ask], onChanged: () => {} }));
}
const optionHtml = (html: string, code: string) => {
  const at = html.indexOf(`<code class="okey">${code}</code>`, html.indexOf('class="fork"'));
  expect(at, `option ${code} is drawn`).toBeGreaterThan(-1);
  return html.slice(at, html.indexOf("</label>", at));
};
const BADGE = (line: string) => `<span class="chip oneway" title="Reversible: ${line}">One-way</span>`;

describe("the parser no longer echoes an option's Reversible: into its description", () => {
  const [drop, keep] = parseAskFile(FORK).questions[0].options;
  it("the field holds the line and the description does not", () => {
    expect(drop.reversible).toBe("no — the data is gone");
    expect(drop.description).toBe("Removes it for good.");
    expect(keep.description).toBe("Leaves it alone.");
  });
});

describe("the per-option badge", () => {
  it("a one-way option carries its own badge, with its own line as the tooltip", async () => {
    expect(optionHtml(await render(FORK), "DROP")).toContain(BADGE("no — the data is gone"));
  });
  it("an option that says yes, or says nothing, gets no badge", async () => {
    const html = await render(FORK);
    expect(optionHtml(html, "KEEP")).not.toContain("chip oneway");
    expect(optionHtml(html, "PARK")).not.toContain("chip oneway");
  });
  it("the fork-level badge stays, with the fork's own line", async () => {
    const html = await render(FORK);
    const headEnd = html.indexOf('<h3 class="fork-q"');
    expect(html.slice(html.indexOf('class="fork"'), headEnd)).toContain(BADGE("no — the fork as a whole"));
  });
  it("a fork with no line of its own has no fork badge, though one option is one-way", async () => {
    const html = await render(FORK.replace("Reversible: no — the fork as a whole\n", ""));
    expect(html.slice(html.indexOf('class="fork"'), html.indexOf('<h3 class="fork-q"'))).not.toContain("chip oneway");
    expect(optionHtml(html, "DROP")).toContain("chip oneway");
  });
  it("a nested option's own line is parsed onto it, and leaves its description the same way", () => {
    const nested = HEAD + "## ¶ASK_N: Choose one: Nested?\n- [ ] [TOP] Top\n  Cost: x\n  - [ ] [SUB] Sub\n    Said plainly.\n    Reversible: irreversible once sent\n- [ ] [ALT] Other\n";
    const sub = parseAskFile(nested).questions[0].options[0].children![0];
    expect(sub.reversible).toBe("irreversible once sent");
    expect(sub.description).toBe("Said plainly.");
  });
});

describe("the line stays on the card now the description has dropped it", () => {
  it("a reversible option's line is still readable, as its own line", async () => {
    const opt = optionHtml(await render(FORK), "KEEP");
    expect(opt).toContain('<span class="opt-line opt-reversible"><b>Reversible</b>');
    expect(opt).toContain("yes, within the day");
  });
  it("the one-way option's words are on the card too, not only in the tooltip", async () => {
    const opt = optionHtml(await render(FORK), "DROP");
    expect(opt.replace(/title="[^"]*"/g, "")).toContain("no — the data is gone");
  });
  it("an option with no line draws none", async () => {
    expect(optionHtml(await render(FORK), "PARK")).not.toContain("opt-reversible");
  });
});

describe("the compare view has a Reversible row", () => {
  it("one cell per option, an empty cell where the option says nothing", () => {
    const row = compareRows(parseAskFile(FORK).questions[0]).rows.find((r) => r.label === "Reversible");
    expect(row?.cells).toEqual(["no — the data is gone", "yes, within the day", undefined]);
  });
  it("is drawn in the open table", async () => {
    const { CompareView } = await import("../src/client/App.tsx");
    const html = renderToStaticMarkup(createElement(CompareView, { q: parseAskFile(FORK).questions[0], initialOpen: true }));
    expect(html).toContain('data-field="Reversible"');
  });
  it("Reversible is never asked of an option, so a fork with none does not list it as not given", () => {
    const q = parseAskFile(HEAD + "## ¶ASK_P: Choose one: Plain?\n- [ ] [A] One\n  Cost: x\n- [ ] [B] Two\n  Cost: y\n").questions[0];
    const { rows, omitted } = compareRows(q);
    expect(rows.map((r) => r.label)).not.toContain("Reversible");
    expect(omitted).not.toContain("Reversible");
  });
});
