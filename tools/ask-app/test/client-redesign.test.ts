/**
 * ASKCLIENT: the redesigned client's pure helpers and its rendered markup. Server-side render only
 * (react-dom/server), so no DOM library is needed.
 */
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { parseAskFile } from "../src/lib/format.ts";
import { acceptAll, askRow, buildAnswers, clickPicks, groupRows, headerLeanEntries, leanCodeFor, leanFor, nextFork, parseHash, resolveFork, saysMore, sortRows, suggestionsFor, tradeoff } from "../src/client/model.ts";
import { paneTrust, proofOriginsFromEnv } from "../src/client/related.ts";
import { clampRatio, clampSide, sideDefault, Split, SIDE_MIN, SIDE_MAX } from "../src/client/layout.tsx";
import { escDepth, pushEsc } from "../src/client/esc.ts";
import { isNavigation, parseRoute, serializeRoute, type Route } from "../src/client/route.ts";
import { briefFor, isProofUrl, proofLinks } from "../src/client/related.ts";
import { blocks, inlineTokens, Rich } from "../src/client/rich.tsx";

const head = (extra = "") => `---\nid: a1\nto: operator\nfrom: idealic:ui\nstatus: open\nrevision: 1\ncreated: 2026-10-29T10:00:00.000Z\n${extra}---\n\n`;
const stored = (text: string, seat = "idealic:ui") => ({ ...parseAskFile(text), seat, file: "/x.md", mtimeMs: 0 });
const NOW = Date.parse("2026-10-29T13:00:00.000Z");

const TWO = "## ¶ASK_A: Choose one: First?\nLean: X — because\n- [ ] [X] x\n  Effort: S\n  Cost: a day\n- [ ] [Y] y\n  Effort: L\n  Cost: a week\n\n## ¶ASK_B: Choose one: Second?\n- [ ] [P] p\n- [ ] [Q] q\n";

describe("sidebar rows", () => {
  it("one row per ask: title, seat, age, N of M left, importance and markers", () => {
    const a = stored(head("importance: high\nreserved-for: operator\n") + TWO);
    const r = askRow(a, NOW);
    expect(r.title).toBe("First?");
    expect(r.seat).toBe("idealic:ui");
    expect(r.age).toBe("3h");
    expect([r.left, r.total]).toEqual([2, 2]);
    expect(r.high).toBe(true);
    expect(r.reserved).toBe("operator");
    expect(r.waitingOnYou).toBe(true);
  });

  it("an operator draft counts its answered forks; a settled ask has none left", () => {
    const text = head("draft: 2026-10-29T11:00:00.000Z\n") + TWO + '\n```json draft\n{"answers":{"A":["X"]},"answeredBy":"operator","basedOn":1,"savedAt":"2026-10-29T11:00:00.000Z"}\n```\n';
    const r = askRow(stored(text), NOW);
    expect([r.left, r.total, r.draft]).toEqual([1, 2, true]);
    const done = askRow(stored(head().replace("status: open", "status: answered") + TWO), NOW);
    expect(done.left).toBe(0);
    expect(done.waitingOnYou).toBe(false);
  });

  it("sorts waiting-on-you first, then high importance, then oldest first", () => {
    const mk = (id: string, extra: string, created: string) =>
      askRow(stored(head(extra).replace("id: a1", `id: ${id}`).replace(/created: .*/, `created: ${created}`) + TWO), NOW);
    const notMine = mk("seat", "", "2026-10-28T00:00:00.000Z");
    notMine.waitingOnYou = false;
    const rows = [notMine, mk("new", "", "2026-10-29T12:00:00.000Z"), mk("old", "", "2026-10-29T01:00:00.000Z"), mk("hi", "importance: high\n", "2026-10-29T12:30:00.000Z")];
    expect(sortRows(rows).map((r) => r.id)).toEqual(["hi", "old", "new", "seat"]);
  });

  it("groups by seat or by topic, with a No topic group", () => {
    const a = askRow(stored(head("topic: proofs\n") + TWO), NOW);
    const b = askRow(stored(head().replace("from: idealic:ui", "from: meta:utils") + TWO, "meta:utils"), NOW);
    expect(groupRows([a, b], "seat").map((g) => g.name)).toEqual(["idealic:ui", "meta:utils"]);
    expect(groupRows([a, b], "topic").map((g) => g.name)).toEqual(["proofs", "No topic"]);
  });
});

describe("lean code", () => {
  it("reads Lean: CODE, then a header lean naming the fork, then a (lean) label suffix", () => {
    const a = stored(head("lean: B Q; C N\n") + TWO + "\n## ¶ASK_C: Choose one: Third?\n- [ ] [M] m\n- [ ] [N] n (lean)\n");
    expect(leanCodeFor(a, 0)).toBe("X");
    expect(leanCodeFor(a, 1)).toBe("Q");
    expect(leanCodeFor(a, 2)).toBe("N");
    const lbl = stored(head() + "## ¶ASK_F2: Choose one: node-xattr?\n- [ ] [DECL] Declare\n- [ ] [DEGR] Runs without types (lean)\n");
    expect(leanCodeFor(lbl, 0)).toBe("DEGR");
    const colon = stored(head("lean: XNOTE: KEEP. XLOSS: DOC — say so\n") + "## ¶ASK_XLOSS: Choose one: Loss?\n- [ ] [DOC] d\n- [ ] [KEEP] k\n");
    expect(leanCodeFor(colon, 0)).toBe("DOC");
  });

  it("the card starts from the file only; a lean is a suggestion beside it (M1)", async () => {
    const { initialValues } = await import("../src/client/App.tsx");
    const open = stored(head() + TWO);
    expect(initialValues(open).values).toEqual({});
    expect(suggestionsFor(open, {})).toEqual({ A: "X" });
    const answered = head().replace("status: open", "status: answered") + TWO + '\n```json answer\n{"answers":{"A":["Y"]},"answeredBy":"operator"}\n```\n';
    expect(initialValues(stored(answered)).values).toEqual({ A: ["Y"] });
    expect(suggestionsFor(stored(answered), {})).toEqual({});
  });
});

describe("trade-off strip", () => {
  it("always has the same shape, risk · effort · cost (+ ★), and marks the dimensions every option shares (S8)", () => {
    const a = stored(head() + TWO);
    const t = tradeoff(a.questions[0].options, "X");
    expect(t.dims).toEqual(["blast", "effort", "cost", "lean"]);
    expect(t.same).toEqual(["blast"]);
    expect(t.rows.X.effort?.glyph).toBe("Ⓢ");
    expect(t.rows.Y.effort?.glyph).toBe("Ⓛ");
    expect(t.rows.X.lean?.glyph).toBe("★");
    const same = stored(head() + "## ¶ASK_A: Choose one: A?\n- [ ] [X] x\n  Effort: M\n- [ ] [Y] y\n  Effort: M\n");
    const s2 = tradeoff(same.questions[0].options, undefined);
    expect(s2.dims).toEqual(["blast", "effort", "cost"]);
    expect(s2.same).toEqual(["blast", "effort", "cost"]);
  });

  it("reads effort words and blast levels, and leaves an unreadable value as text", () => {
    const a = stored(head() + "## ¶ASK_A: Choose one: A?\n- [ ] [X] x\n  Effort: about a day\n  Blast: low\n- [ ] [Y] y\n  Effort: large\n  Blast: high — every CI box\n");
    const t = tradeoff(a.questions[0].options, undefined);
    expect(t.rows.X.effort).toEqual({ glyph: "", text: "about a day" });
    expect(t.rows.Y.effort?.glyph).toBe("Ⓛ");
    expect(t.rows.X.blast?.glyph).toBe("△");
    expect(t.rows.Y.blast?.glyph).toBe("▲");
    expect(saysMore("high — every CI box")).toBe(true);
    expect(saysMore("M")).toBe(false);
  });
});

describe("related pane sources", () => {
  it("a brief: header wins; else the first proof URL in context, evidence or a fork's Evidence", () => {
    expect(briefFor(stored(head("brief: http://127.0.0.1:9440/proofs/b.html\ncontext: http://127.0.0.1:9440/proofs/c.html\n") + TWO))).toEqual({ url: "http://127.0.0.1:9440/proofs/b.html", source: "brief" });
    expect(briefFor(stored(head("context: http://127.0.0.1:9440/proofs/c.html (source: x)\n") + TWO))?.url).toBe("http://127.0.0.1:9440/proofs/c.html");
    const ev = stored(head() + "## ¶ASK_A: Choose one: A?\nEvidence: design/x.ts:3\nEvidence: [map](http://127.0.0.1:9440/proofs/m.html)\n- [ ] [X] x\n");
    expect(briefFor(ev)).toEqual({ url: "http://127.0.0.1:9440/proofs/m.html", source: "first proof link" });
    expect(briefFor(stored(head() + TWO))).toBeUndefined();
  });

  it("lists every proof link once with its label", () => {
    const a = stored(head("evidence: a ; proof http://127.0.0.1:9440/proofs/p.html\n") + "## ¶ASK_A: Choose one: A?\nEvidence: [map](http://127.0.0.1:9440/proofs/m.html)\nEvidence: [again](http://127.0.0.1:9440/proofs/m.html)\n- [ ] [X] x\n");
    expect(proofLinks(a)).toEqual([
      { url: "http://127.0.0.1:9440/proofs/p.html", label: "p.html" },
      { url: "http://127.0.0.1:9440/proofs/m.html", label: "map" },
    ]);
    expect(isProofUrl("https://linear.app/x/issue/IDE-1")).toBe(false);
  });
});

describe("prose rendering", () => {
  it("splits inline code, markdown links, bare URLs and ticket keys", () => {
    expect(inlineTokens("see `a.ts` and [map](http://h/p.html), IDE-221 or http://h/q.html.")).toEqual([
      { t: "text", v: "see " },
      { t: "code", v: "a.ts" },
      { t: "text", v: " and " },
      { t: "link", label: "map", href: "http://h/p.html" },
      { t: "text", v: ", " },
      { t: "ticket", key: "IDE-221" },
      { t: "text", v: " or " },
      { t: "link", label: "http://h/q.html", href: "http://h/q.html" },
      { t: "text", v: "." },
    ]);
    expect(inlineTokens("[IDE-261](https://linear.app/i/issue/IDE-261)")).toEqual([{ t: "ticket", key: "IDE-261" }]);
    expect(inlineTokens("code `IDE-1` stays code")[1]).toEqual({ t: "code", v: "IDE-1" });
  });

  it("fenced code is one block, blank lines and all; callouts collect their quoted lines", () => {
    const b = blocks("Why.\n\n```ts\nconst x = 1;\n\nconst y = 2;\n```\n> [!term] What 'xattr' means\n> Extended attributes.\n>\n> Second para.\nAfter.");
    expect(b.map((x) => x.t)).toEqual(["p", "pre", "callout", "p"]);
    expect(b[1]).toEqual({ t: "pre", lang: "ts", code: "const x = 1;\n\nconst y = 2;" });
    expect(b[2]).toEqual({ t: "callout", kind: "term", title: "What 'xattr' means", body: "Extended attributes.\n\nSecond para." });
  });

  it("renders a callout collapsed, code as <pre>, tickets as hover links", () => {
    const html = renderToStaticMarkup(createElement(Rich, { text: "Blocks IDE-258.\n\n```\nx  y\n```\n> [!background] Why now\n> Because." }));
    expect(html).toContain('<pre class="code"><code>x  y</code></pre>');
    expect(html).toMatch(/<details class="callout k-background"><summary>/);
    expect(html).not.toContain("<details class=\"callout k-background\" open");
    expect(html).toContain('class="ticket"');
    expect(html).toContain("IDE-258");
  });
});

describe("the redesigned card", () => {
  it("every card links its own tickets; lens marks are buttons described by their popover; the lean is the one ★ (Operator 00:30: no Recommended chip)", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const text = head("tickets: IDE-1\n") + "## ¶ASK_A: Choose one: First?\n- [ ] [X] x\n\n## ¶ASK_B: Choose one: Second blocks IDE-222?\nPanel: Minimalist → P — fewest lines\nLean: P — short\n- [ ] [P] p\n- [ ] [Q] q\n";
    const ask = stored(text);
    const html = renderToStaticMarkup(createElement(AskDetail, { ask, all: [ask], onChanged: () => {} }));
    const second = html.slice(html.indexOf("Second blocks"));
    expect(second).toContain("IDE-222");
    expect(second).toMatch(/<button[^>]*class="lens-mark"[^>]*aria-describedby="lens-/);
    expect(second).toContain("fewest lines");
    expect(second).not.toContain("Recommended");
    expect(second).toContain('aria-label="the asker&#x27;s lean">★');
    expect(html).not.toContain("callout caution");
  });

  it("main.tsx no longer imports the board kit sheets", async () => {
    const fs = await import("node:fs");
    const main = fs.readFileSync(new URL("../src/client/main.tsx", import.meta.url), "utf8");
    expect(main).not.toMatch(/proof-theme|proof-blocks|board-widgets|board-warm-overrides/);
    expect(main).toContain("theme.css");
  });
});

// ── round 2 ────────────────────────────────────────────────

const OPF = head("lean: F1 ALL; F2 DEGR; F3 WAIT\n") +
  "## ¶ASK_F1: Choose one: Verbs?\n- [ ] [ALL] All\n- [ ] [MAP] Map\n\n## ¶ASK_F2: Choose one: xattr?\n- [ ] [DECL] Declare\n- [ ] [DEGR] Degrade\n\n## ¶ASK_F3: Choose one: FUSE?\n- [ ] [HOST] Host\n- [ ] [WAIT] Wait\n";

describe("round 2: the layout never covers the ask", () => {
  it("the sidebar width is clamped, never zero, and starts slim on a phone", () => {
    expect(clampSide(10)).toBe(SIDE_MIN);
    expect(clampSide(9999)).toBe(SIDE_MAX);
    expect(sideDefault(390)).toBeLessThan(180);
    expect(sideDefault(390)).toBeGreaterThanOrEqual(SIDE_MIN);
    expect(sideDefault(1440)).toBe(300);
    expect(clampRatio(0)).toBe(0.2);
    expect(clampRatio(Number.NaN)).toBe(0.5);
  });

  it("with a page open the work area is a two-track split with a separator; without one the ask has it all", () => {
    const main = createElement("main", { className: "detail" }, "ASK");
    const pane = createElement("aside", { className: "pane" }, "PAGE");
    const cols = renderToStaticMarkup(createElement(Split, { mode: "columns", ratio: 0.6, onRatio: () => {}, main, pane }));
    expect(cols).toContain('class="work split split-columns"');
    expect(cols).toContain("grid-template-columns:minmax(0, 0.600fr) 8px minmax(0, 0.400fr)");
    expect(cols).toMatch(/role="separator"[^>]*aria-orientation="vertical"/);
    expect(cols.indexOf("ASK")).toBeLessThan(cols.indexOf("PAGE"));
    const rows = renderToStaticMarkup(createElement(Split, { mode: "rows", ratio: 0.55, onRatio: () => {}, main, pane }));
    expect(rows).toContain("grid-template-rows:minmax(0, 0.550fr) 8px minmax(0, 0.450fr)");
    expect(rows).toMatch(/aria-orientation="horizontal"/);
    const solo = renderToStaticMarkup(createElement(Split, { mode: "columns", ratio: 0.5, onRatio: () => {}, main, pane: null }));
    expect(solo).toContain('class="work solo"');
    expect(solo).not.toContain("separator");
  });

  it("the stylesheet has no drawer, no sheet and nothing fixed over the ask but the phone lens card", async () => {
    const fs = await import("node:fs");
    const css = fs.readFileSync(new URL("../src/client/styles.css", import.meta.url), "utf8");
    expect(css).not.toMatch(/drawer|\.sheet|side-toggle|\.scrim/);
    expect((css.match(/position:\s*fixed/g) ?? []).length).toBe(1);
    expect(css).toMatch(/\.lens-pop \{ position: fixed/);
  });
});

describe("round 2: forks, deep links and confirm", () => {
  it("#Q1 and #q1 count from 1 and ignore case; an ask name in any case works; an unknown one does not", () => {
    const a = stored(OPF);
    expect(resolveFork(a, "f2")).toBe(1);
    expect(resolveFork(a, "F3")).toBe(2);
    expect(resolveFork(a, "q1")).toBe(0);
    expect(resolveFork(a, "Q3")).toBe(2);
    expect(resolveFork(a, "Q9")).toBeUndefined();
    const unnamed = stored(head() + "## Choose one: A?\n- [ ] [X] x\n\n## Choose one: B?\n- [ ] [Y] y\n");
    expect(resolveFork(unnamed, "Q2")).toBe(1);
    expect(resolveFork(unnamed, "q0")).toBeUndefined();
  });

  it("the fragment carries an ask, an ask and a fork, or a fork alone", () => {
    expect(parseHash("#manager:domain/opforks-1029")).toEqual({ ref: "manager:domain/opforks-1029" });
    expect(parseHash("#manager:domain/opforks-1029/F3")).toEqual({ ref: "manager:domain/opforks-1029", fork: "F3" });
    expect(parseHash("#manager%3Adomain%2Fopforks-1029%2Fq2")).toEqual({ ref: "manager:domain/opforks-1029", fork: "q2" });
    expect(parseHash("#Q1")).toEqual({ fork: "Q1" });
    expect(parseHash("")).toEqual({});
  });

  it("clicking the picked radio confirms it and never clears it; a checkbox still toggles", () => {
    expect(clickPicks(["DEGR"], "DEGR", false, ["DECL", "DEGR"])).toEqual({ picks: ["DEGR"], confirm: true });
    expect(clickPicks(["DEGR"], "DECL", false, ["DECL", "DEGR"])).toEqual({ picks: ["DECL"], confirm: false });
    expect(clickPicks(["A", "B"], "A", true, [])).toEqual({ picks: ["B"], confirm: false });
    const a = stored(OPF);
    expect(nextFork(a, 0, a.questions)).toBe(1);
    expect(nextFork(a, 2, a.questions)).toBeUndefined();
  });

  it("a header lean naming several forks is split: each fork sees only its own entry", async () => {
    const a = stored(OPF);
    expect([...headerLeanEntries(a)]).toEqual([[0, { code: "ALL", text: "" }], [1, { code: "DEGR", text: "" }], [2, { code: "WAIT", text: "" }]]);
    expect(leanFor(a, 0)).toEqual({ code: "ALL", text: "" });
    expect(leanFor(a, 1)?.code).toBe("DEGR");
    const x = stored(head("lean: XNOTE: KEEP. XLOSS: DOC — degraded mode means types are not kept\n") + "## ¶ASK_XNOTE: Choose one: N?\n- [ ] [KEEP] k\n- [ ] [DROP] d\n\n## ¶ASK_XLOSS: Choose one: L?\n- [ ] [DOC] d\n- [ ] [FIX] f\n");
    expect(leanFor(x, 0)).toEqual({ code: "KEEP", text: "" });
    expect(leanFor(x, 1)).toEqual({ code: "DOC", text: "degraded mode means types are not kept" });
    // N3: a fork name inside prose is not an entry.
    expect(headerLeanEntries(stored(head("lean: for F1 A beats B\n") + "## ¶ASK_F1: Choose one: ?\n- [ ] [A] a\n- [ ] [B] b\n")).size).toBe(0);
    const { AskDetail } = await import("../src/client/App.tsx");
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    // The raw header still shows under "Ask header and file"; no fork card repeats it.
    const cards = html.slice(0, html.indexOf('class="askmeta"'));
    expect(cards).not.toContain("F1 ALL; F2 DEGR");
    expect(html.slice(html.indexOf('class="askmeta"'))).toContain("F1 ALL; F2 DEGR");
  });
});

// ── round 3 ────────────────────────────────────────────────

describe("round 3 M1: a suggestion is never an answer", () => {
  it("an untouched card cannot save or send, and says nothing is picked", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const a = stored(OPF);
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    expect(html).toMatch(/<button class="btn primary" disabled="">Send answers<\/button>/);
    expect(html).toMatch(/<button class="btn quiet" disabled="">Save draft<\/button>/);
    expect(html).toContain("Nothing picked yet. Suggestions are not sent.");
    expect(html).toContain("Accept all 3 suggestions: F1 ALL · F2 DEGR · F3 WAIT");
    expect(html).toContain('class="optwrap suggested is-lean"');
  });

  it("answering one fork sends only that fork", () => {
    const a = stored(OPF);
    expect(buildAnswers(a, { F2: ["DECL"] }, {}, a.questions)).toEqual({ F2: ["DECL"] });
    expect(buildAnswers(a, {}, {}, a.questions)).toEqual({});
  });

  it("Accept all sends exactly the leans, and keeps a fork the operator already picked", () => {
    const a = stored(OPF);
    expect(buildAnswers(a, acceptAll(a, {}, a.questions), {}, a.questions)).toEqual({ F1: ["ALL"], F2: ["DEGR"], F3: ["WAIT"] });
    expect(buildAnswers(a, acceptAll(a, { F1: ["MAP"] }, a.questions), {}, a.questions)).toEqual({ F1: ["MAP"], F2: ["DEGR"], F3: ["WAIT"] });
  });

  it("S1: the row counts a suggested fork as still left", () => {
    expect(askRow(stored(OPF), NOW)).toMatchObject({ left: 3, total: 3 });
  });
});

describe("round 3 M2: the pane opens only what it should", () => {
  it("refuses the app's own origin, opens loopback and named proof hosts, and asks for any other host", () => {
    const app = "http://127.0.0.1:4992";
    expect(paneTrust("http://127.0.0.1:4992/index.html", app)).toBe("refuse");
    expect(paneTrust("javascript:alert(1)", app)).toBe("refuse");
    expect(paneTrust("http://127.0.0.1:9440/proofs/a.html", app)).toBe("auto");
    expect(paneTrust("http://localhost:9440/proofs/a.html", app)).toBe("auto");
    expect(paneTrust("https://evil.example/proofs/a.html", app)).toBe("ask");
    const known = proofOriginsFromEnv("https://proofs.example.com/base/, not a url");
    expect(known).toEqual(["https://proofs.example.com"]);
    expect(paneTrust("https://proofs.example.com/p/x.html", app, known)).toBe("auto");
  });

  it("the frame is sandboxed without top navigation or forms", async () => {
    const { PANE_SANDBOX } = await import("../src/client/App.tsx");
    expect(PANE_SANDBOX.split(" ").sort()).toEqual(["allow-popups", "allow-same-origin", "allow-scripts"]);
  });

  it("an unknown host renders a click-to-open card and no frame", async () => {
    const { RelatedPane } = await import("../src/client/App.tsx");
    const html = renderToStaticMarkup(createElement(RelatedPane, { pane: { url: "https://evil.example/p.html", label: "Linked proof", source: "link", trust: "ask" }, onClose: () => {} }));
    expect(html).toContain("Open in pane");
    expect(html).toContain("nothing has been fetched from evil.example yet");
    expect(html).not.toContain("<iframe");
  });
});

describe("round 3: popovers", () => {
  it("N6: Esc closes only the newest popover", () => {
    const closed: string[] = [];
    const base = escDepth();
    const popA = pushEsc(() => closed.push("a"));
    const popB = pushEsc(() => closed.push("b"));
    expect(escDepth()).toBe(base + 2);
    popB();
    popA();
    expect(escDepth()).toBe(base);
    expect(closed).toEqual([]);
  });

  it("S4/S5: lens marks carry no aria-expanded; nested option levels get their own radio name", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const text = head() + "## ¶ASK_A: Choose one: A?\nPanel: Minimalist → X — short\n- [ ] [X] x\n  - [ ] [XA] xa\n- [ ] [Y] y\n";
    const draft = text.replace("status: open", "status: open\ndraft: 2026-10-29T11:00:00.000Z") + '\n```json draft\n{"answers":{"A":["X","XA"]},"answeredBy":"operator","basedOn":1,"savedAt":"2026-10-29T11:00:00.000Z"}\n```\n';
    const a = stored(draft);
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    expect(html).not.toContain("aria-expanded");
    const names = [...html.matchAll(/type="radio" name="([^"]+)"/g)].map((m) => m[1]);
    expect(new Set(names).size).toBe(2);
    expect(names).toContain("idealic:ui/a1#A/top/X");
  });
});

// ── round 4: the Proofs and Broadcasts tabs ─────────────────

describe("round 4 (c): Proofs and Broadcasts views", () => {
  const B = (id: string, at: string, inForce: boolean, acks: string[], extra: Record<string, unknown> = {}) => ({
    id, from: "manager:director", at, audience: ["meta:utils", "idealic:ui", "domain:storage"], text: `Hold: ${id} is in effect. More words follow.\n\nSecond paragraph with \`code\`.`,
    acks, sticky: inForce, expires: "", inForce, ...extra,
  });

  it("counts acks against the audience only, and names who has not acked", async () => {
    const { ackSummary, broadcastHeadline } = await import("../src/client/feeds.tsx");
    expect(ackSummary({ audience: ["a", "b", "c"], acks: ["a", "x"] })).toEqual({ acked: 1, of: 3, missing: ["b", "c"] });
    expect(broadcastHeadline({ id: "hold", text: "Hold: do not run it. Then more." })).toBe("Hold:");
    expect(broadcastHeadline({ id: "x", text: "Plain first sentence. Second." })).toBe("Plain first sentence.");
    expect(broadcastHeadline({ id: "x", text: "" })).toBe("x");
  });

  it("the feed shows each text inline, the ack count over the audience and in force, never the delivery list", async () => {
    const { BroadcastFeed } = await import("../src/client/feeds.tsx");
    const list = [B("soon", "2026-10-29T20:00:00Z", true, ["meta:utils", "idealic:ui", "domain:storage"]), B("old", "2026-10-27T09:00:00Z", false, ["meta:utils"], { expires: "2026-10-28T00:00:00Z" })];
    const html = renderToStaticMarkup(createElement(BroadcastFeed, { list, error: "", now: NOW }));
    expect(html).toContain("2, 1 in force");
    expect(html.indexOf("bc-soon")).toBeLessThan(html.indexOf("bc-old"));
    expect(html).toContain("Second paragraph with </span><code class=\"ic\">code</code>");
    expect(html).toContain("in force · sticky");
    expect(html).toContain("3 of 3 acked");
    expect(html).toContain("1 of 3 acked");
    expect(html).toContain("expired 2026-10-28T00:00:00Z");
    expect(html).toContain("Not acked yet: idealic:ui, domain:storage");
    expect(html).not.toMatch(/delivered|pid=/);
  });

  it("the proof list keeps the server's newest-first order and marks the page open in the pane", async () => {
    const { ProofRows } = await import("../src/client/feeds.tsx");
    const list = { ok: true, total: 2, at: "", proofs: [
      { key: "k1", url: "http://127.0.0.1:9440/proofs/a.html", title: "Newest page", owner: "invizko", slug: "a.html", modified: "2026-10-29T12:00:00Z", size: 1 },
      { key: "k2", url: "http://127.0.0.1:9440/proofs/b.html", title: "Older page", owner: "invizko", slug: "b.html", modified: "2026-10-28T12:00:00Z", size: 1 },
    ] };
    const html = renderToStaticMarkup(createElement(ProofRows, { list, busy: false, onOpen: () => {}, onReload: () => {}, slim: false, current: "http://127.0.0.1:9440/proofs/b.html", now: NOW }));
    expect(html.indexOf("Newest page")).toBeLessThan(html.indexOf("Older page"));
    expect(html).toContain("2 pages");
    expect(html).toMatch(/aria-current="true"[^>]*title="http:\/\/127.0.0.1:9440\/proofs\/b.html"/);
    const down = renderToStaticMarkup(createElement(ProofRows, { list: { ok: false, total: 0, at: "", proofs: [], error: "connection refused" }, busy: false, onOpen: () => {}, onReload: () => {}, slim: false }));
    expect(down).toContain("Proof store not reachable");
    expect(down).toContain("connection refused");
  });

  it("a proof from the store opens in the pane by itself: its host is loopback", () => {
    expect(paneTrust("http://127.0.0.1:9440/proofs/proofs/invizko/a.html", "http://127.0.0.1:4977")).toBe("auto");
  });
});

describe("round 4: the URL is the app's state", () => {
  const cases: Route[] = [
    { section: "asks", filter: "open", group: "none" },
    { section: "asks", ask: "manager:domain/opforks-1029", filter: "settled", group: "topic", fork: "F2" },
    { section: "asks", ask: "idealic:ui/20261029-055903-how-should-the-design-matcher-fi", filter: "open", group: "none", pane: "off" },
    { section: "asks", ask: "meta:utils/x", filter: "all", group: "seat", pane: "http://127.0.0.1:9440/proofs/proofs/invizko/a b?x=1&y=2" },
    { section: "proofs", filter: "open", group: "none" },
    { section: "proofs", proof: "proofs/invizko/fork2-fits-explore-7fc21c59.html", ask: "manager:domain/opforks-1029", filter: "ruled", group: "none" },
    { section: "broadcasts", filter: "open", group: "none" },
    { section: "broadcasts", broadcast: "ask-serve-hold", filter: "open", group: "seat" },
  ];

  it("parse(serialize(route)) gives the route back, for every section and setting", () => {
    for (const r of cases) {
      const u = new URL(serializeRoute(r), "http://127.0.0.1:4977");
      expect(parseRoute(u.pathname, u.search, u.hash)).toEqual(r);
    }
  });

  it("writes readable paths and leaves defaults out", () => {
    expect(serializeRoute(cases[0])).toBe("/");
    expect(serializeRoute(cases[1])).toBe("/a/manager:domain/opforks-1029?filter=settled&group=topic#F2");
    expect(serializeRoute(cases[5])).toBe("/proofs/proofs/invizko/fork2-fits-explore-7fc21c59.html?ask=manager:domain/opforks-1029&filter=ruled");
    expect(serializeRoute(cases[7])).toBe("/broadcasts/ask-serve-hold?group=seat");
  });

  it("reads the round-1/2 fragment links, and ignores unknown filters and groups", () => {
    expect(parseRoute("/", "", "#manager:domain/opforks-1029/F3")).toMatchObject({ section: "asks", ask: "manager:domain/opforks-1029", fork: "F3" });
    expect(parseRoute("/", "?filter=bogus&group=nope", "")).toMatchObject({ filter: "open", group: "none" });
  });

  it("pushes what Back should undo, and replaces small changes", () => {
    const r = cases[1];
    expect(isNavigation(r, { ...r, ask: "meta:utils/x" })).toBe(true);
    expect(isNavigation(r, { ...r, section: "proofs" })).toBe(true);
    expect(isNavigation(r, { ...r, filter: "all" })).toBe(false);
    expect(isNavigation(r, { ...r, group: "seat" })).toBe(false);
    expect(isNavigation(r, { ...r, pane: "off" })).toBe(false);
    expect(isNavigation(r, { ...r, fork: "F1" })).toBe(false);
  });

  it("an unknown ask, proof or broadcast id still parses, so the app can say not found", async () => {
    expect(parseRoute("/a/nobody/nothing", "", "")).toMatchObject({ section: "asks", ask: "nobody/nothing" });
    expect(parseRoute("/proofs/missing.html", "", "")).toMatchObject({ section: "proofs", proof: "missing.html" });
    expect(parseRoute("/broadcasts/gone", "", "")).toMatchObject({ section: "broadcasts", broadcast: "gone" });
    const { BroadcastFeed } = await import("../src/client/feeds.tsx");
    const html = renderToStaticMarkup(createElement(BroadcastFeed, { list: [], error: "", current: "gone" }));
    expect(html).toContain("No broadcast “gone”");
  });

  it("Send is the primary action and says how many answers it sends; Save draft is quiet", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const a = stored(OPF.replace("status: open", "status: open\ndraft: 2026-10-29T11:00:00.000Z") + '\n```json draft\n{"answers":{"F1":["MAP"],"F2":["DEGR"]},"answeredBy":"operator","basedOn":1,"savedAt":"2026-10-29T11:00:00.000Z"}\n```\n');
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    const primary = [...html.matchAll(/<button class="btn primary"[^>]*>([^<]*)<\/button>/g)].map((m) => m[1]);
    expect(primary).toEqual(["Send 2 answers"]);
    expect(html).toMatch(/<button class="btn quiet">Update draft<\/button>/);
  });
});
