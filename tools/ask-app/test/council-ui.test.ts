/**
 * COUNCILUI (IDE-338, the client half): a fork's council report is a link beside its panel reads,
 * the reads are readable without hovering (a visible per-option count and a lens → pick — why
 * disclosure), and what attach-panel records — who attached a read, when, from which report, and
 * the options a panel proposed — is shown. Server-side render only (react-dom/server).
 */
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { appendPanelEntry, parseAskFile } from "../src/lib/format.ts";
import { councilRef, forkCouncils, optionTally, tallyText } from "../src/client/panel.ts";

const head = () => `---\nid: a1\nto: operator\nfrom: idealic:ui\nstatus: open\nrevision: 1\ncreated: 2026-10-29T10:00:00.000Z\n---\n\n`;
const stored = (text: string) => ({ ...parseAskFile(text), seat: "idealic:ui", file: "/x.md", mtimeMs: 0 });
const URL1 = "http://127.0.0.1:9440/proofs/fund-council-1.html";
const URL2 = "http://127.0.0.1:9440/proofs/fund-council-2.html";

const THREE = "## ¶ASK_A: Choose one: Which root?\nPanel: Security → B — a separate root keeps the blast small\nPanel: Economist → A — one root is simpler to audit\nPanel: Operator → B — fewer pages at 3am\nCouncil: " + URL1 + "\n- [ ] [A] One root\n- [ ] [B] A separate root\n- [ ] [C] No root\n";

async function render(text: string) {
  const { AskDetail } = await import("../src/client/App.tsx");
  const ask = stored(text);
  return renderToStaticMarkup(createElement(AskDetail, { ask, all: [ask], onChanged: () => {} }));
}
/** The markup of one option row, from its code chip to the next one (or the card's end). */
function optionHtml(html: string, code: string): string {
  const at = html.indexOf(`<code class="okey">${code}</code>`);
  const next = html.indexOf('<code class="okey">', at + 1);
  return html.slice(at, next < 0 ? undefined : next);
}

describe("councilRef: only an http(s) value is a link", () => {
  it("a URL links; a markdown link keeps its label; a path or a javascript: value stays text", () => {
    expect(councilRef(URL1)).toEqual({ href: URL1, label: "Council report" });
    expect(councilRef(`[Fund council](${URL2})`)).toEqual({ href: URL2, label: "Fund council" });
    expect(councilRef("sessions/x/COUNCIL_REPORT.md")).toEqual({ label: "sessions/x/COUNCIL_REPORT.md" });
    expect(councilRef("javascript:alert(1)")).toEqual({ label: "javascript:alert(1)" });
    expect(councilRef("[x](javascript:alert(1))")).toEqual({ label: "[x](javascript:alert(1))" });
  });
});

describe("forkCouncils and the tally", () => {
  it("lists the fork's Council: first, then each attached report once", () => {
    let text = head() + THREE;
    text = appendPanelEntry(text, { fork: "A", title: "Which root?", panel: [{ lens: "Auditor", pick: "A", why: "fewer moving parts" }], proposals: [], council: URL2, by: "manager:director", at: "2026-10-30T22:00:00.000Z" });
    text = appendPanelEntry(text, { fork: "A", title: "Which root?", panel: [{ lens: "Skeptic", pick: "C", why: "no root at all" }], proposals: [], council: URL1, by: "manager:director", at: "2026-10-30T22:05:00.000Z" });
    const q = parseAskFile(text).questions[0];
    expect(forkCouncils(q)).toEqual([URL1, URL2]);
  });

  it("counts the lenses that picked an option, by code or by label", () => {
    const q = parseAskFile(head() + THREE).questions[0];
    expect(optionTally(q, q.options[1])).toEqual({ picked: 2, of: 3, reads: [q.panel[0], q.panel[2]] });
    expect(optionTally(q, q.options[2]).picked).toBe(0);
    expect(tallyText(2, 3)).toBe("2 of 3 lenses picked this");
    expect(tallyText(1, 1)).toBe("1 of 1 lens picked this");
    expect(tallyText(0, 3)).toBe("No lens of 3 picked this");
  });
});

describe("the fork's panel strip", () => {
  it("links the council report beside the reads and lists lens → pick — why in a disclosure", async () => {
    const html = await render(head() + THREE);
    const strip = html.slice(html.indexOf('class="panel-line"'));
    expect(strip).toMatch(new RegExp(`<a href="${URL1.replace(/[.?]/g, "\\$&")}"[^>]*class="proof-link"`));
    expect(strip).toContain("Council report");
    expect(strip).toMatch(/<details class="panel-reads"><summary>/);
    const reads = strip.slice(strip.indexOf('class="panel-reads"'), strip.indexOf("</details>"));
    expect(reads).toContain("<b>Security</b>");
    expect(reads).toContain("<code>B</code>");
    expect(reads).toContain("a separate root keeps the blast small");
    expect(reads).toContain("one root is simpler to audit");
  });

  it("shows the council link even when the fork has no Panel: lines", async () => {
    const html = await render(head() + "## ¶ASK_A: Choose one: Which root?\nCouncil: " + URL1 + "\n- [ ] [A] a\n- [ ] [B] b\n");
    expect(html).toContain('class="panel-line"');
    expect(html).toMatch(/<a href="http:\/\/127\.0\.0\.1:9440\/proofs\/fund-council-1\.html"/);
    expect(html).toContain("no lens reads recorded on this fork");
  });

  it("a Council: path is plain text, never a link", async () => {
    const html = await render(head() + "## ¶ASK_A: Choose one: Which root?\nPanel: Security → A — small\nCouncil: sessions/x/COUNCIL.md\n- [ ] [A] a\n- [ ] [B] b\n");
    const strip = html.slice(html.indexOf('class="panel-line"'), html.indexOf("</p>", html.indexOf('class="panel-line"')));
    expect(strip).toContain("sessions/x/COUNCIL.md");
    expect(strip).not.toContain("<a ");
  });

  it("an attached read says who attached it, when, and from which report", async () => {
    const text = appendPanelEntry(head() + THREE, { fork: "A", title: "Which root?", panel: [{ lens: "Auditor", pick: "A", why: "fewer moving parts" }], proposals: [], council: URL2, by: "manager:director", at: "2026-10-30T22:00:00.000Z" });
    const html = await render(text);
    const reads = html.slice(html.indexOf('class="panel-reads"'), html.indexOf("</details>", html.indexOf('class="panel-reads"')));
    expect(reads).toContain("<b>Auditor</b>");
    expect(reads).toContain("attached by manager:director");
    expect(reads).toContain("2026-10-30");
    expect(reads).toContain(`href="${URL2}"`);
  });
});

describe("the option rows", () => {
  it("each option shows a visible count, not only hover marks", async () => {
    const html = await render(head() + THREE);
    expect(optionHtml(html, "B")).toContain("2 of 3 lenses picked this");
    expect(optionHtml(html, "A")).toContain("1 of 3 lenses picked this");
    expect(optionHtml(html, "C")).toContain("No lens of 3 picked this");
  });

  it("the pinned popover names attach-panel as the source of an attached read", async () => {
    const text = appendPanelEntry(head() + THREE, { fork: "A", title: "Which root?", panel: [{ lens: "Auditor", pick: "C", why: "none" }], proposals: [], council: URL2, by: "manager:director", at: "2026-10-30T22:00:00.000Z" });
    const c = optionHtml(await render(text), "C");
    expect(c).toContain("Attached by manager:director");
    expect(c).not.toContain("From the fork&#x27;s Panel: line");
  });
});

describe("options a panel proposed", () => {
  it("are listed apart from the fork's options, with the lens, the why and the report", async () => {
    const text = appendPanelEntry(head() + THREE, { fork: "A", title: "Which root?", panel: [], proposals: [{ lens: "Designer", label: "A root per tenant", why: "isolates each tenant" }], council: URL2, by: "manager:director", at: "2026-10-30T22:00:00.000Z" });
    const html = await render(text);
    const prop = html.slice(html.indexOf('class="panel-proposals"'));
    expect(html).toContain('class="panel-proposals"');
    expect(prop).toContain("A root per tenant");
    expect(prop).toContain("<b>Designer</b>");
    expect(prop).toContain("isolates each tenant");
    expect(prop).toContain("not an option here");
    // never a radio: a proposal cannot be answered
    expect(prop.slice(0, prop.indexOf("</details>"))).not.toContain('type="radio"');
  });
});
