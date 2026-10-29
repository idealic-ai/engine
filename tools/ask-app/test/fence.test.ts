/**
 * Fence round (IDE-304): fenced code in option descriptions, CommonMark fence closing, code inside an
 * option card, and the lens popover kept inside the ask pane.
 */
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import { parseAskFile } from "../src/lib/format.ts";
import { blocks, closesFence } from "../src/client/md.ts";

const dir = path.join(import.meta.dirname, "../src/client");
const css = fs.readFileSync(path.join(dir, "styles.css"), "utf8");
// meta:engine's parser (4a9fcd3) keeps a fence verbatim in AskOption.description, "\n\n"-separated.
const FENCED = "The caller destructures it.\n\n```ts\nconst [ok, err] = run();\n```";
const FENCED_THEN_PROSE = "The caller destructures it.\n\n```ts\nconst [ok, err] = run();\n\nif (err) throw err;\n```\n\nAfter the fence, a **second** paragraph.";

describe("item 1: an option description renders its blocks", () => {
  it("the exact fixture: a paragraph, then the fence verbatim", async () => {
    expect(blocks(FENCED)).toEqual([{ t: "p", text: "The caller destructures it." }, { t: "pre", lang: "ts", code: "const [ok, err] = run();" }]);
    const { OptionDescription } = await import("../src/client/App.tsx");
    const html = renderToStaticMarkup(createElement(OptionDescription, { text: FENCED }));
    expect(html).toBe('<span class="opt-desc opt-desc-blocks"><div class="rich"><p><span>The caller destructures it.</span></p><pre class="code"><code>const [ok, err] = run();</code></pre></div></span>');
  });

  it("prose after the fence is its own paragraph; blank lines inside the fence stay", async () => {
    expect(blocks(FENCED_THEN_PROSE)).toEqual([
      { t: "p", text: "The caller destructures it." },
      { t: "pre", lang: "ts", code: "const [ok, err] = run();\n\nif (err) throw err;" },
      { t: "p", text: "After the fence, a **second** paragraph." },
    ]);
    const { OptionDescription } = await import("../src/client/App.tsx");
    const html = renderToStaticMarkup(createElement(OptionDescription, { text: FENCED_THEN_PROSE }));
    expect(html).toContain("<code>const [ok, err] = run();\n\nif (err) throw err;</code>");
    expect(html).toContain("<p><span>After the fence, a </span><strong><span>second</span></strong><span> paragraph.</span></p>");
  });

  it("a description with no fence renders exactly as before: one inline span", async () => {
    const { OptionDescription } = await import("../src/client/App.tsx");
    expect(renderToStaticMarkup(createElement(OptionDescription, { text: "Keeps `x` and links ENG-12" }))).toBe(
      '<span class="opt-desc"><span>Keeps </span><code class="ic">x</code><span> and links </span><span class="ticket" data-ticket="ENG-12"><a href="#ticket-ENG-12" target="_blank" rel="noreferrer">ENG-12</a></span></span>',
    );
  });

  it("in the card: the top row and its strip are unchanged, and the code sits in the description", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const head = "---\nid: a1\nto: operator\nfrom: x\nstatus: open\nrevision: 1\n---\n\n";
    const a = { ...parseAskFile(head + "## ¶ASK_R: Choose one: Return shape?\nLean: TUP — simple\n- [ ] [TUP] Tuple\n  Effort: S\n- [ ] [OBJ] Object\n  Effort: M\n"), seat: "x", file: "/x.md", mtimeMs: 0 };
    a.questions[0].options[0].description = FENCED;
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    const tup = html.slice(html.indexOf('<code class="okey">TUP</code>'), html.indexOf('<code class="okey">OBJ</code>'));
    expect(tup).toMatch(/^<code class="okey">TUP<\/code><span class="opt-text"><span>Tuple<\/span><\/span>.*?<span class="strip"/);
    expect(tup.indexOf('class="strip"')).toBeLessThan(tup.indexOf("opt-desc"));
    expect(tup).toContain('<pre class="code"><code>const [ok, err] = run();</code></pre>');
  });
});

describe("item 2: a fence closes only on a run as long as its opener (CommonMark)", () => {
  it("``` fences", () => {
    expect(blocks("```\na\n```\nafter")).toEqual([{ t: "pre", lang: "", code: "a" }, { t: "p", text: "after" }]);
    expect(blocks("```\na\n`````\nafter")[0]).toEqual({ t: "pre", lang: "", code: "a" }); // a longer run closes
  });
  it("a ```` fence holds a ``` line", () => {
    expect(blocks("````md\nText\n```js\nx()\n```\n````\nafter")).toEqual([{ t: "pre", lang: "md", code: "Text\n```js\nx()\n```" }, { t: "p", text: "after" }]);
  });
  it("~~~ and ``` never close each other", () => {
    expect(blocks("~~~\n```\nin\n```\n~~~")).toEqual([{ t: "pre", lang: "", code: "```\nin\n```" }]);
    expect(blocks("```\n~~~\nin\n```")).toEqual([{ t: "pre", lang: "", code: "~~~\nin" }]);
  });
  it("a line with an info string never closes; an unclosed fence runs to the end", () => {
    expect(closesFence("```js", "```")).toBe(false);
    expect(closesFence("  ```  ", "```")).toBe(true);
    expect(closesFence("```", "````")).toBe(false);
    expect(blocks("```\nopen\n```ts\nstill")).toEqual([{ t: "pre", lang: "", code: "open\n```ts\nstill" }]);
  });
});

describe("item 3: code in an option card", () => {
  const el = (tag: string, inPre: boolean) => ({ tagName: tag, closest: (s: string) => (s === "pre" && inPre ? {} : null) }) as unknown as Element;
  it("a click inside the code, or one ending a selection, does not pick; the radio and the label do", async () => {
    const { ignoreOptionClick } = await import("../src/client/App.tsx");
    expect(ignoreOptionClick(el("CODE", true), "")).toBe(true);
    expect(ignoreOptionClick(el("SPAN", false), "selected words")).toBe(true);
    expect(ignoreOptionClick(el("SPAN", false), "")).toBe(false);
    expect(ignoreOptionClick(el("INPUT", false), "selected words")).toBe(false); // the label's own forwarded click
  });
  it("the option's label wires the guard", () => {
    expect(fs.readFileSync(path.join(dir, "App.tsx"), "utf8")).toMatch(/className="opt"[\s\S]{0,200}onClick=\{\(e\) => \{\s*if \(ignoreOptionClick\(/);
  });
  it("the code wraps inside itself, reads as text and takes the theme's code tokens", () => {
    const rule = css.match(/\n\.opt-desc pre\.code \{([^}]*)\}/)?.[1] ?? "";
    expect(rule).toMatch(/white-space: pre-wrap/);
    expect(rule).toMatch(/overflow-wrap: anywhere/);
    expect(rule).toMatch(/max-width: 100%/);
    expect(rule).toMatch(/cursor: text/);
    expect(rule).toMatch(/background: var\(--code-bg\)/);
    expect(rule).toMatch(/color: var\(--ink\)/);
    const theme = fs.readFileSync(path.join(dir, "theme.css"), "utf8");
    expect((theme.match(/--code-bg:/g) ?? []).length).toBeGreaterThanOrEqual(3); // light, dark by preference, dark by choice
  });
});

describe("item 4: token.ts says the retry is a backstop", () => {
  it("no longer claims a new token on every start", () => {
    const src = fs.readFileSync(path.join(dir, "token.ts"), "utf8");
    expect(src).not.toMatch(/mints a new token on every start/);
    expect(src).toMatch(/backstop/);
  });
});

describe("item 5: the lens popover stays inside the ask pane", () => {
  const r = (left: number, top: number, right: number, bottom: number) => ({ left, top, right, bottom });
  it("shifts left by what runs past the pane's right edge, never past its left edge", async () => {
    const { fitPopover } = await import("../src/client/App.tsx");
    const pane = r(300, 0, 1000, 800);
    expect(fitPopover(r(800, 100, 1160, 200), pane, r(800, 80, 900, 96))).toEqual({ dx: -168, above: false });
    expect(fitPopover(r(320, 100, 1400, 200), pane, r(320, 80, 400, 96)).dx).toBe(-12);
    expect(fitPopover(r(400, 100, 700, 200), pane, r(400, 80, 500, 96))).toEqual({ dx: 0, above: false });
  });
  it("flips above its mark when it would run past the bottom and there is room above", async () => {
    const { fitPopover } = await import("../src/client/App.tsx");
    const pane = r(0, 0, 1000, 800);
    expect(fitPopover(r(100, 760, 400, 900), pane, r(100, 740, 200, 756)).above).toBe(true);
    expect(fitPopover(r(100, 60, 400, 900), pane, r(100, 40, 200, 56)).above).toBe(false); // no room above either
  });
  it("the stylesheet places a flipped popover above, outside the phone layout", () => {
    expect(css).toMatch(/@media \(min-width: 561px\) \{\s*\.lens-pop\.above \{ top: auto; bottom: calc\(100% \+ 6px\); \}/);
  });
});
