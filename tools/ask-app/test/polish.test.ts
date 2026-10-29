/**
 * IDE-304: the operator's polish round on the live ask app (01:19 and 01:21). Server-side render only;
 * the stylesheet is checked as text where the fix is CSS.
 */
import { describe, expect, it, vi } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import { parseAskFile } from "../src/lib/format.ts";
import { answerInWords, askRow } from "../src/client/model.ts";
import { blocks, displayTitle, inlineTokens, linksIn } from "../src/client/md.ts";
import { Rich } from "../src/client/rich.tsx";

const head = (extra = "") => `---\nid: a1\nto: operator\nfrom: domain:language\nstatus: open\nrevision: 1\ncreated: 2026-10-29T10:00:00.000Z\n${extra}---\n\n`;
const stored = (text: string) => ({ ...parseAskFile(text), seat: "domain:language", file: "/x.md", mtimeMs: 0 });
const css = fs.readFileSync(path.join(import.meta.dirname, "../src/client/styles.css"), "utf8");
/** The declarations of the rule whose selector list is exactly `sel` (last one wins, as in the cascade). */
const rule = (sel: string) => {
  const esc = sel.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const all = [...css.matchAll(new RegExp(`(?:^|\\n)${esc}\\s*\\{([^}]*)\\}`, "g"))];
  return all.map((m) => m[1]).join(";");
};
const R = (text: string) => renderToStaticMarkup(createElement(Rich, { text }));

const TWO = "## ¶ASK_EL: Choose one: Where?\n- [ ] [ELEM] On the element\n- [ ] [DOC] On the document\n\n## ¶ASK_N: Choose one: Notes?\n- [ ] [KEEP] Keep\n- [ ] [DROP] Drop\n";
const ANSWERED = head().replace("status: open", "status: answered") + TWO + '\n```json answer\n{"answers":{"EL":["ELEM"],"EL.other":"only for the inline case — a long note that used to widen the pane"},"answeredBy":"operator","note":"thanks"}\n```\n';

describe("item 1: the shell is the viewport, each column scrolls alone", () => {
  it("page level: html/body/#root fill the viewport and never scroll; the app is exactly 100dvh", () => {
    expect(rule("html, body, #root")).toMatch(/height:\s*100%/);
    expect(rule("html, body, #root")).toMatch(/overflow:\s*hidden/);
    expect(rule(".app")).toMatch(/height:\s*100dvh/);
    expect(rule(".app")).toMatch(/overflow:\s*hidden/);
  });
  it("the list and the ask are the scroll containers, vertical only, and contain their absolutely placed children", () => {
    for (const sel of [".side", ".detail"]) {
      expect(rule(sel)).toMatch(/overflow-y:\s*auto/);
      expect(rule(sel)).toMatch(/overflow-x:\s*hidden/);
      expect(rule(sel)).toMatch(/position:\s*relative/);
    }
  });
});

describe("item 2: one scroll per column", () => {
  it("a <pre> wraps its long lines instead of scrolling on its own", () => {
    expect(rule("pre.code")).toMatch(/white-space:\s*pre-wrap/);
    expect(rule("pre.code")).toMatch(/overflow-wrap:\s*anywhere/);
    expect(rule("pre.code")).not.toMatch(/overflow(-x)?:\s*auto/);
    expect(rule("pre.code code")).toMatch(/white-space:\s*pre-wrap/);
  });
  it("no rule in the sheet but the three columns (and the page level) sets a scroll container", () => {
    const scrollers = [...css.matchAll(/(?:^|\n)([^{}\n]+)\{[^}]*overflow(?:-[xy])?:\s*(?:auto|scroll)/g)].map((m) => m[1].trim());
    expect(scrollers.sort()).toEqual([".detail", ".pane-body", ".side"]);
  });
  it("grid children of the answer bar and the ask head may shrink below their content", () => {
    expect(css).toMatch(/\.ask-head > \*, \.answerbar > \*[^{]*\{\s*min-width:\s*0;/);
  });
});

describe("item 3: a pick shows at once", () => {
  it("the option input's click is not default-prevented, and the pick runs synchronously in the click", async () => {
    const { optionInputHandlers } = await import("../src/client/App.tsx");
    const click = vi.fn();
    const preventDefault = vi.fn();
    optionInputHandlers(click).onClick({ preventDefault });
    expect(click).toHaveBeenCalledTimes(1);
    expect(preventDefault).not.toHaveBeenCalled();
  });
  it("the picked option renders checked with the picked class in the same render as its handler", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const a = stored(head("draft: 2026-10-29T11:00:00.000Z\n") + TWO + '\n```json draft\n{"answers":{"EL":["DOC"]},"answeredBy":"operator","basedOn":1,"savedAt":"2026-10-29T11:00:00.000Z"}\n```\n');
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    const doc = html.match(/<div class="optwrap on[^"]*"><label class="opt"[^>]*><input[^>]*>/)?.[0] ?? "";
    expect(doc).toContain('checked=""');
    expect(doc).toContain('aria-checked="true"');
    expect(html.match(/<div class="optwrap on/g)).toHaveLength(1);
  });
  it("on an answered ask the recorded pick renders as picked, not faded", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const a = stored(ANSWERED);
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    const elem = html.match(/<div class="optwrap on[^"]*readonly[^"]*"><label class="opt"[^>]*><input[^>]*>/)?.[0] ?? "";
    expect(elem).toContain('checked=""');
    expect(html).not.toContain("optwrap suggested");
    expect(rule(".optwrap.readonly > .opt input:disabled")).toMatch(/opacity:\s*1/);
    expect(rule(".optwrap.readonly.on > .opt")).toMatch(/background:\s*var\(--accent-soft\)/);
  });
  it("no transition on the option's checked state", () => {
    expect(css).not.toMatch(/\.opt[^{]*\{[^}]*transition:\s*(all|box-shadow|background|border)/);
  });
});

describe("item 4: markdown", () => {
  it("bold inside an ordered list item", () => {
    const html = R("1. **On the element:** the attribute sits on it\n2. second");
    expect(html).toContain("<ol><li><strong><span>On the element:</span></strong><span> the attribute sits on it</span></li><li><span>second</span></li></ol>");
    expect(html).not.toContain("**");
  });
  it("italic with * and _, but not inside snake_case or a lone asterisk", () => {
    expect(inlineTokens("an *aside* and _this_")).toEqual([{ t: "text", v: "an " }, { t: "em", v: "aside" }, { t: "text", v: " and " }, { t: "em", v: "this" }]);
    expect(inlineTokens("keep snake_case_name and 2 * 3 * 4")).toEqual([{ t: "text", v: "keep snake_case_name and 2 * 3 * 4" }]);
    expect(R("__bold__ and *em*")).toContain("<strong><span>bold</span></strong><span> and </span><em><span>em</span></em>");
  });
  it("a horizontal rule is a rule, in each spelling, and never a list", () => {
    for (const hr of ["---", "***", "___", "- - -"]) {
      expect(blocks(`above\n\n${hr}\n\nbelow`)).toEqual([{ t: "p", text: "above" }, { t: "hr" }, { t: "p", text: "below" }]);
    }
    expect(R("a\n\n---\n\nb")).toContain("<hr/>");
  });
  it("headings render quieter than the fork title, with the ¶ASK_ anchor dropped", () => {
    expect(R("## Context\n\ntext")).toContain('<h4 class="md-h"><span>Context</span></h4>');
    expect(R("### ¶ASK_MFP: Fix F1 first")).toContain('<h5 class="md-h"><span>Fix F1 first</span></h5>');
  });
  it("sidebar titles and fork titles drop a raw ¶ASK_NAME: prefix", async () => {
    expect(displayTitle("¶ASK_MFP: Fix F1 before F2")).toBe("Fix F1 before F2");
    expect(displayTitle("ASK_MFP: Fix")).toBe("Fix");
    expect(displayTitle("Plain title: with a colon")).toBe("Plain title: with a colon");
    const a = stored(head() + "## Choose one: ¶ASK_MFP: Fix F1 first?\n- [ ] [A] a\n- [ ] [B] b\n");
    expect(askRow(a).title).not.toMatch(/ASK_/);
    const { AskDetail } = await import("../src/client/App.tsx");
    expect(renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }))).not.toMatch(/<h3 class="fork-q">[^<]*<span>¶?ASK_/);
  });
  it("links, inside bold too, are links (and found for the pane)", () => {
    expect(R("see [the page](https://x.example/p.html)")).toContain('href="https://x.example/p.html"');
    expect(linksIn("**see [it](https://x.example/a.html)**")).toEqual([{ href: "https://x.example/a.html", label: "it" }]);
  });
  it("nested lists nest, an ordered list keeps its start, and a lazy line continues its item", () => {
    const b = blocks("- one\n  - one.a\n  - one.b\n- two\n  continued");
    expect(b).toEqual([{ t: "list", ordered: false, items: ["one", "two continued"], nested: ["- one.a\n- one.b", ""] }]);
    const html = R("- one\n  - one.a\n- two");
    expect(html).toMatch(/<ul><li><span>one<\/span><div class="rich nested-md"><ul><li><span>one\.a<\/span><\/li><\/ul><\/div><\/li><li><span>two<\/span><\/li><\/ul>/);
    expect(R("3. three\n4. four")).toContain('<ol start="3">');
    const loose = blocks("1. a\n\n2. b\n\nafter");
    expect(loose[0]).toMatchObject({ t: "list", items: ["a", "b"] });
    expect(loose[1]).toEqual({ t: "p", text: "after" });
  });
  it("blockquotes and fenced code still render, inside a list item too", () => {
    expect(R("> quoted **bold**")).toContain("<blockquote><div class=\"rich\"><p><span>quoted </span><strong><span>bold</span></strong></p></div></blockquote>");
    expect(R("```\n**not bold** <b>\n```")).toContain("<pre class=\"code\"><code>**not bold** &lt;b&gt;</code></pre>");
    expect(R("- item\n  ```\n  code\n  ```")).toContain('<pre class="code"><code>code</code></pre>');
    expect(R("`**x**`")).toContain('<code class="ic">**x**</code>');
  });
  it("still renders no live link for a script URL", () => {
    expect(R("**[x](javascript:alert(1))**")).not.toMatch(/href="javascript/i);
  });
});

describe("item 5: the recorded answer, in words, above a closed block", () => {
  it("each fork reads as its picked option label and note; an untouched fork says not answered", () => {
    const a = stored(ANSWERED);
    expect(answerInWords(a, a.answer)).toEqual([
      { label: "EL", title: "Where?", picks: ["ELEM · On the element"], note: "only for the inline case — a long note that used to widen the pane", unanswered: false },
      { label: "N", title: "Notes?", picks: [], note: undefined, unanswered: true },
    ]);
  });
  it("renders the words, and the raw block is closed by default", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const a = stored(ANSWERED);
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    expect(html).toContain('<dl class="answer-words"');
    expect(html).toContain("<b>ELEM · On the element</b>");
    expect(html).toContain("not answered");
    expect(html).toMatch(/<details class="raw-answer"><summary>Recorded answer block<\/summary>/);
    expect(html.indexOf("answer-words")).toBeLessThan(html.indexOf("Recorded answer block"));
  });
});

describe("item 6: the Proofs tab says why it is empty", () => {
  it("shows the server's error text, in the list and in the main area", async () => {
    const { ProofRows, ProofStatus } = await import("../src/client/feeds.tsx");
    const down = { ok: false, total: 0, at: "", proofs: [], error: "proof store not reachable (its settings could not be read)" };
    const side = renderToStaticMarkup(createElement(ProofRows, { list: down, busy: false, onOpen: () => {}, onReload: () => {}, slim: true }));
    expect(side).toContain('role="alert">proof store not reachable (its settings could not be read)');
    const main = renderToStaticMarkup(createElement(ProofStatus, { list: down }));
    expect(main).toContain("The proof list could not be read");
    expect(main).toContain("proof store not reachable (its settings could not be read)");
  });
  it("says the store answered with no pages, naming where it looked", async () => {
    const { ProofStatus } = await import("../src/client/feeds.tsx");
    const html = renderToStaticMarkup(createElement(ProofStatus, { list: { ok: true, total: 0, at: "", proofs: [], bucket: "proofs", prefix: "proofs" } }));
    expect(html).toContain("The proof store answered with no pages");
    expect(html).toContain("proofs/proofs");
  });
});
