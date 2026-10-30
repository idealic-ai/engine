/**
 * COUNCILUI (IDE-338, the client half): a fork's council report is a link beside its panel reads,
 * the reads are readable without hovering (a visible per-option count and a lens → pick — why
 * disclosure), and what attach-panel records — who attached a read, when, from which report, and
 * the options a panel proposed — is shown. Server-side render only (react-dom/server).
 */
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import { appendPanelEntry, parseAskFile } from "../src/lib/format.ts";
import { councilRef, forkCouncils, namedReport, optionTally, tallyText } from "../src/client/panel.ts";

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
    expect(councilRef(URL1)).toEqual({ href: URL1, label: "fund-council-1.html" });
    expect(councilRef("https://proofs.example.com/")).toEqual({ href: "https://proofs.example.com/", label: "proofs.example.com" });
    expect(councilRef("https://proofs.example.com/runs/42/")).toEqual({ href: "https://proofs.example.com/runs/42/", label: "proofs.example.com/…/42" });
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
    expect(optionTally(q, q.options[1])).toMatchObject({ picked: 2, under: 0, of: 3, reads: [q.panel[0], q.panel[2]] });
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
    expect(strip).toContain(">fund-council-1.html</a>");
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

describe("S4: several report links are told apart", () => {
  it("a fork's Council: and two attached reports carry three different labels", async () => {
    let text = head() + THREE.replace("Council: " + URL1, "Council: [Fund council](" + URL1 + ")");
    text = appendPanelEntry(text, { fork: "A", title: "Which root?", panel: [{ lens: "Auditor", pick: "A", why: "x" }], proposals: [], council: URL2, by: "manager:director", at: "2026-10-30T22:00:00.000Z" });
    text = appendPanelEntry(text, { fork: "A", title: "Which root?", panel: [{ lens: "Skeptic", pick: "B", why: "y" }], proposals: [], council: "http://127.0.0.1:9440/runs/7/", by: "manager:director", at: "2026-10-30T22:05:00.000Z" });
    const html = await render(text);
    const line = html.slice(html.indexOf('class="panel-line"'), html.indexOf("</p>", html.indexOf('class="panel-line"')));
    const labels = [...line.matchAll(/<a [^>]*>(?:<span[^>]*>[^<]*<\/span>)?([^<]+)<\/a>/g)].map((m) => m[1]);
    expect(labels).toEqual(["Fund council", "fund-council-2.html", "127.0.0.1:9440/…/7"]);
  });
});

describe("S1: a council named in prose, with no reads recorded", () => {
  const real = fs.readFileSync(path.join(import.meta.dirname, "fixtures/voice-v2-202610300727.md"), "utf8");

  it("the real voice-v2 ask (answered; the panel ran in prose only) says so on the fork that names it", async () => {
    const ask = parseAskFile(real);
    expect(ask.questions[0].panel).toEqual([]);
    expect(ask.questions[0].council).toBeUndefined();
    expect(namedReport(ask, 0)).toEqual({ named: true, report: "builds/VOICE_COUNCIL.md" });
    expect(namedReport(ask, 1)).toEqual({ named: false });
    const html = await render(real);
    const v2 = html.slice(html.indexOf("Land draft 2"), html.indexOf("What should change?"));
    expect(v2).toContain("A council is named here, but no lens reads were recorded on this question.");
    expect(v2).toContain('<code class="council-ref">builds/VOICE_COUNCIL.md</code>');
    expect(html.slice(html.indexOf("What should change?"))).not.toContain("A council is named here");
  });

  it("an http(s) report named in the fork is linked", async () => {
    const html = await render(head() + "## ¶ASK_A: Choose one: Ship it?\nContext: the council's verdict is at " + URL1 + "\n- [ ] [A] a\n- [ ] [B] b\n");
    const line = html.slice(html.indexOf("A council is named here"));
    expect(line).toMatch(/<a href="http:\/\/127\.0\.0\.1:9440\/proofs\/fund-council-1\.html"/);
  });

  it("a council named only above the forks (preamble or header) is said once, on the first fork", async () => {
    const text = head() + "The council's verdict: sound (report: builds/X_COUNCIL.md).\n\n## ¶ASK_A: Choose one: First?\n- [ ] [A] a\n- [ ] [B] b\n\n## ¶ASK_B: Choose one: Second?\n- [ ] [P] p\n- [ ] [Q] q\n";
    const ask = parseAskFile(text);
    expect(namedReport(ask, 0)).toEqual({ named: true, report: "builds/X_COUNCIL.md" });
    expect(namedReport(ask, 1)).toEqual({ named: false });
    const html = await render(text);
    expect(html.split("A council is named here").length - 1).toBe(1);
    // and not when some fork already carries reads
    expect(namedReport(parseAskFile(text.replace("- [ ] [P] p", "Panel: Security → P — x\n- [ ] [P] p")), 0)).toEqual({ named: false });
  });

  it("a fork that only proposes a council, or carries reads, gets no such line", async () => {
    expect(await render(head() + "## ¶ASK_A: Choose one: Run a council per question?\n- [ ] [A] a\n- [ ] [B] b\n")).not.toContain("A council is named here");
    expect(await render(head() + "## ¶ASK_A: Choose one: Ship?\nContext: the council's verdict is in\nPanel: Security → A — small\n- [ ] [A] a\n- [ ] [B] b\n")).not.toContain("A council is named here");
  });
});

describe("S2: a read on a nested option counts on its parent", () => {
  const NESTED = "## ¶ASK_A: Choose one: Which root?\nPanel: Security → A2 — the second sub-root\n- [ ] [A] Rooted\n  - [ ] [A1] one\n  - [ ] [A2] two\n- [ ] [B] Flat\n";

  it("the tally carries the picks under an option", () => {
    const q = parseAskFile(head() + NESTED).questions[0];
    expect(optionTally(q, q.options[0])).toMatchObject({ picked: 0, under: 1, of: 1 });
    expect(optionTally(q, q.options[1])).toMatchObject({ picked: 0, under: 0, of: 1 });
    expect(tallyText(0, 1, 1)).toBe("1 of 1 lens picked an option under this");
    expect(tallyText(1, 3, 1)).toBe("1 of 3 lenses picked this · 1 picked an option under this");
  });

  it("with the children hidden, the parent row does not say no lens picked it", async () => {
    const html = await render(head() + NESTED);
    expect(html).not.toContain('<code class="okey">A2</code>'); // child rows hidden until A is picked
    expect(optionHtml(html, "A")).toContain("1 of 1 lens picked an option under this");
    expect(optionHtml(html, "A")).not.toContain("No lens");
    expect(optionHtml(html, "B")).toContain("No lens of 1 picked this");
  });
});

describe("N1: stale reads", () => {
  it("leave the count and are listed as picking no current option", async () => {
    // an attached read whose pick the asker has since removed (revise), kept in the record
    const text = appendPanelEntry(head() + THREE, { fork: "A", title: "Which root?", panel: [{ lens: "Auditor", pick: "Z", why: "gone" }], proposals: [], council: URL2, by: "manager:director", at: "2026-10-30T22:00:00.000Z" });
    const q = parseAskFile(text).questions[0];
    expect(optionTally(q, q.options[1]).of).toBe(3);
    const html = await render(text);
    expect(optionHtml(html, "B")).toContain("2 of 3 lenses picked this");
    const reads = html.slice(html.indexOf('class="panel-reads"'), html.indexOf("</details>", html.indexOf('class="panel-reads"')));
    expect(reads).toMatch(/<b>Auditor<\/b>[\s\S]*picks no current option/);
  });
});

describe("N2: a proposal label's leading code", () => {
  it("is not rendered as a bold option code", async () => {
    const text = appendPanelEntry(head() + THREE, { fork: "A", title: "Which root?", panel: [], proposals: [{ lens: "Designer", label: "[D] A root per tenant", why: "isolates" }], council: URL2, by: "manager:director", at: "2026-10-30T22:00:00.000Z" });
    const prop = (await render(text)).slice(0);
    const list = prop.slice(prop.indexOf('class="panel-proposals"'), prop.indexOf("</details>", prop.indexOf('class="panel-proposals"')));
    expect(list).toContain("A root per tenant");
    expect(list).not.toContain("[D]");
    expect(list).not.toMatch(/<(?:b|strong)>[^<]*A root per tenant/);
    expect(list).not.toContain('class="pp-label"');
  });
});

describe("S3: answered, ruled and nested cards show the panel too", () => {
  const settled = (by: string) => head().replace("status: open", "status: answered") + THREE + "\n```json answer\n" + JSON.stringify({ answers: { A: ["B"] }, answeredBy: by, answeredAt: "2026-10-30T12:00:00Z" }) + "\n```\n";

  it("an answered card keeps its counts, its strip and its report link", async () => {
    const html = await render(settled("operator"));
    expect(html).toContain('class="panel-line"');
    expect(html).toContain(">fund-council-1.html</a>");
    expect(optionHtml(html, "B")).toContain("2 of 3 lenses picked this");
    expect(optionHtml(html, "C")).toContain("No lens of 3 picked this");
  });

  it("a ruled card (answered by a seat) keeps them too", async () => {
    const { ruledBelow } = await import("../src/client/model.ts");
    const text = settled("manager:meta");
    expect(ruledBelow(parseAskFile(text))).toBe(true);
    const html = await render(text);
    expect(html).toContain('class="panel-reads"');
    expect(optionHtml(html, "A")).toContain("1 of 3 lenses picked this");
  });

  it("an answered nested card shows the child's own count once its parent is the answer", async () => {
    const text = head().replace("status: open", "status: answered") + "## ¶ASK_A: Choose one: Which root?\nPanel: Security → A2 — the second sub-root\n- [ ] [A] Rooted\n  - [ ] [A1] one\n  - [ ] [A2] two\n- [ ] [B] Flat\n" + "\n```json answer\n" + JSON.stringify({ answers: { A: ["A", "A2"] }, answeredBy: "operator" }) + "\n```\n";
    const html = await render(text);
    expect(optionHtml(html, "A")).toContain("1 of 1 lens picked an option under this");
    expect(optionHtml(html, "A2")).toContain("1 of 1 lens picked this");
  });
});
