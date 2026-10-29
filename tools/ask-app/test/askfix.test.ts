/**
 * ASKFIX: meta:engine's review of the ask-app client (askclient_REVIEW.md), item by item. Server-side
 * render only (react-dom/server); effects never run, so the probe and the frame are tested through the
 * seams App.tsx exports for them (runProbe, paneFramed, PaneFrame, RelatedPane's initialProbe).
 */
import { describe, expect, it, vi } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { parseAskFile, visibleQuestions } from "../src/lib/format.ts";
import {
  acceptAll, askRow, batchConfirmation, buildAnswers, restoreUnsent, rowInFilter, sendConfirmation, unansweredForks, visibleSuggestionsFor,
} from "../src/client/model.ts";
import { paneTrust } from "../src/client/related.ts";
import { Rich } from "../src/client/rich.tsx";
import { clampSide } from "../src/client/layout.tsx";

const head = (extra = "") => `---\nid: a1\nto: operator\nfrom: idealic:ui\nstatus: open\nrevision: 1\ncreated: 2026-10-29T10:00:00.000Z\n${extra}---\n\n`;
const stored = (text: string, seat = "idealic:ui") => ({ ...parseAskFile(text), seat, file: "/x.md", mtimeMs: 0 });
const FOUR = head() + "## ¶ASK_F1: Choose one: One?\n- [ ] [A] a\n- [ ] [B] b\n\n## ¶ASK_F2: Choose one: Two?\n- [ ] [A] a\n- [ ] [B] b\n\n## ¶ASK_F3: Choose one: Three?\n- [ ] [A] a\n- [ ] [B] b\n\n## ¶ASK_F4: Choose one: Four?\n- [ ] [A] a\n- [ ] [B] b\n";
// MF-2: B is hidden until A = X, and leans P.
const DEP = head() + "## ¶ASK_A: Choose one: First?\nLean: X — because\n- [ ] [X] x\n- [ ] [Y] y\n\n## ¶ASK_B: Choose one: Second?\nDependsOn: ASK_A=X\nLean: P — also\n- [ ] [P] p\n- [ ] [Q] q\n";

describe("MF-1: a send settles the whole ask, and a partial send is confirmed", () => {
  it("names the visible forks left unpicked, and a note is not a pick", () => {
    const a = stored(FOUR);
    expect(unansweredForks(a, { F2: ["A"] })).toEqual(["F1", "F3", "F4"]);
    expect(unansweredForks(a, { "F1.other": "a note" })).toEqual(["F1", "F2", "F3", "F4"]);
    expect(unansweredForks(a, { F1: ["A"], F2: ["A"], F3: ["B"], F4: ["A"] })).toEqual([]);
  });

  it("asks 'N questions unanswered — send anyway?' with the forks named, and nothing when all are picked", () => {
    expect(sendConfirmation(["F1", "F3", "F4"])).toMatch(/^3 questions unanswered \(F1, F3, F4\) — send anyway\?/);
    expect(sendConfirmation(["F1"])).toMatch(/^1 question unanswered \(F1\) — send anyway\?/);
    expect(sendConfirmation([])).toBeUndefined();
  });

  it("the batch tray confirms a partial draft and a notes-only draft, never a decline or a full one", () => {
    const draft = (answers: string, extra = "") => stored(FOUR.replace("status: open", "status: open\ndraft: 2026-10-29T11:00:00.000Z") + `\n\`\`\`json draft\n{"answers":${answers},"answeredBy":"operator","basedOn":1,"savedAt":"2026-10-29T11:00:00.000Z"${extra}}\n\`\`\`\n`);
    const ref = (a: { header: { id?: string } }) => `s/${a.header.id}`;
    expect(batchConfirmation([draft('{"F2":["A"]}')], ref)).toBe("3 questions unanswered — send anyway? Each ask is settled when sent. s/a1: F1, F3, F4");
    expect(batchConfirmation([draft('{"F1.other":"just a note"}')], ref)).toMatch(/^4 questions unanswered/);
    expect(batchConfirmation([draft('{"F1":["A"],"F2":["A"],"F3":["A"],"F4":["A"]}')], ref)).toBeUndefined();
    expect(batchConfirmation([draft("{}", ',"declined":true,"reason":"no"')], ref)).toBeUndefined();
  });

  it("the answer bar says sending settles the ask and names what reaches the asker unanswered; it never says forks stay open", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const a = stored(FOUR.replace("status: open", "status: open\ndraft: 2026-10-29T11:00:00.000Z") + '\n```json draft\n{"answers":{"F2":["A"]},"answeredBy":"operator","basedOn":1,"savedAt":"2026-10-29T11:00:00.000Z"}\n```\n');
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    expect(html).toContain("Sending settles this ask: the asker gets 1 of 4 forks answered, and F1, F3, F4 reach the asker unanswered.");
    expect(html).not.toContain("stay open");
  });
});

describe("MF-2: Accept all accepts only visible suggestions, and its label names exactly those", () => {
  it("the reviewer's case: A leans X, B (hidden until A=X) leans P; accepting gives A only", () => {
    const a = stored(DEP);
    const visible = visibleQuestions(a.questions, {});
    expect(visibleSuggestionsFor(a, {}, visible).map((s) => `${s.label} ${s.code}`)).toEqual(["A X"]);
    const after = acceptAll(a, {}, visible);
    expect(after).toEqual({ A: ["X"] });
    // B shows its own dashed suggestion once A is picked; a second accept is a second explicit act.
    const nowVisible = visibleQuestions(a.questions, buildAnswers(a, after, {}, a.questions));
    expect(visibleSuggestionsFor(a, after, nowVisible).map((s) => `${s.label} ${s.code}`)).toEqual(["B P"]);
  });

  it("the button's label lists what it accepts", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const a = stored(DEP);
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    expect(html).toContain("Accept all 1 suggestion: A X</button>");
  });

  it("NIT: a lean on a nested option also picks its parent", () => {
    const a = stored(head() + "## ¶ASK_N: Choose one: Nested?\nLean: KID — why\n- [ ] [TOP] top\n  - [ ] [KID] kid\n- [ ] [OTHER] other\n");
    expect(acceptAll(a, {}, a.questions)).toEqual({ N: ["TOP", "KID"] });
  });
});

describe("SF-1: the pane opens by itself only the proof server and named hosts", () => {
  const app = "http://127.0.0.1:4977";
  it("refuses the app on any loopback alias", () => {
    for (const u of ["http://127.0.0.1:4977/", "http://localhost:4977/", "http://[::1]:4977/x"]) expect(paneTrust(u, app)).toBe("refuse");
    expect(paneTrust("http://127.0.0.1:4977/", "http://localhost:4977")).toBe("refuse");
  });
  it("auto-opens loopback :9440 and a VITE_PROOF_ORIGINS host; every other loopback port asks", () => {
    expect(paneTrust("http://localhost:9440/proofs/a.html", app)).toBe("auto");
    expect(paneTrust("https://proofs.example.com/a.html", app, ["https://proofs.example.com"])).toBe("auto");
    for (const u of ["http://localhost:3000/", "http://127.0.0.1:5173/x.html", "http://[::1]:8080/"]) expect(paneTrust(u, app)).toBe("ask");
  });
});

describe("SF-2: the M2 safety properties, guarded where they act", () => {
  it("a javascript: link renders as text, never as an href", () => {
    for (const src of ["[x](javascript:alert(1))", "[x](JaVaScRiPt:alert(1))", "[x](data:text/html,hi)"]) {
      const html = renderToStaticMarkup(createElement(Rich, { text: src }));
      expect(html).not.toMatch(/href="(javascript|data)/i);
      expect(html).not.toContain("<a ");
    }
  });

  it("the frame the pane draws carries the sandbox, without top navigation, forms or sandbox escape", async () => {
    const { RelatedPane, PaneFrame } = await import("../src/client/App.tsx");
    const html = renderToStaticMarkup(createElement(RelatedPane, { pane: { url: "http://127.0.0.1:9440/proofs/a.html", label: "P", source: "link", trust: "auto" }, onClose: () => {}, initialProbe: { state: "ok" } }));
    const frame = html.match(/<iframe[^>]*>/)?.[0];
    expect(frame).toBeDefined();
    const sandbox = frame!.match(/sandbox="([^"]*)"/)?.[1];
    expect(sandbox?.split(" ").sort()).toEqual(["allow-popups", "allow-same-origin", "allow-scripts"]);
    expect(frame).toMatch(/referrerpolicy="no-referrer"/i);
    expect(frame).not.toMatch(/allow-top-navigation|allow-forms|allow-popups-to-escape-sandbox/);
    expect(renderToStaticMarkup(createElement(PaneFrame, { url: "http://x/", title: "t" }))).toMatch(/sandbox="allow-scripts allow-same-origin allow-popups"/);
  });

  it("the app's own origin is never framed, even when a check is said to have passed", async () => {
    const { RelatedPane, paneFramed } = await import("../src/client/App.tsx");
    const trust = paneTrust("http://localhost:4977/", "http://127.0.0.1:4977");
    const html = renderToStaticMarkup(createElement(RelatedPane, { pane: { url: "http://localhost:4977/", label: "P", source: "link", trust }, onClose: () => {}, initialProbe: { state: "ok" } }));
    expect(html).not.toContain("<iframe");
    expect(paneFramed("refuse", true, true, "ok")).toBe(false);
  });

  it("a host that is not allowlisted is neither probed nor framed until the operator clicks", async () => {
    const { RelatedPane, runProbe } = await import("../src/client/App.tsx");
    const probe = vi.fn(async () => ({ state: "ok" as const }));
    const on = { probe, result: () => {}, slow: () => {} };
    expect(runProbe({ url: "https://evil.example/p.html", trust: "ask" }, false, on)).toBeUndefined();
    expect(runProbe({ url: "http://localhost:4977/", trust: "refuse" }, true, on)).toBeUndefined();
    expect(probe).not.toHaveBeenCalled();
    const stop = runProbe({ url: "http://127.0.0.1:9440/a.html", trust: "auto" }, true, on);
    expect(probe).toHaveBeenCalledWith("http://127.0.0.1:9440/a.html");
    stop?.();
    const html = renderToStaticMarkup(createElement(RelatedPane, { pane: { url: "http://localhost:3000/a.html", label: "P", source: "link", trust: paneTrust("http://localhost:3000/a.html", "http://127.0.0.1:4977") }, onClose: () => {}, initialProbe: { state: "ok" } }));
    expect(html).toContain("Open in pane");
    expect(html).not.toContain("<iframe");
  });

  it("a hidden dependent's stale pick is dropped from what is sent", () => {
    const a = stored(DEP);
    const visible = visibleQuestions(a.questions, { A: ["Y"] });
    expect(buildAnswers(a, { A: ["Y"], B: ["P"] }, { B: "note" }, visible)).toEqual({ A: ["Y"] });
  });
});

describe("SF-3: a suggested radio is not checked", () => {
  it("renders unchecked with aria-checked=false and the visible suggested style", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const a = stored(DEP);
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    const wrap = html.match(/<div class="optwrap suggested[^"]*">.*?<\/label>/)?.[0] ?? "";
    expect(wrap).not.toContain("Suggested · click to confirm");
    expect(wrap).toContain('title="Suggested by the asker · click to confirm"');
    expect(wrap).toMatch(/<span class="sr-only">Suggested by the asker, not picked\. Click to confirm\.<\/span>/);
    const input = wrap.match(/<input[^>]*>/)![0];
    expect(input).not.toMatch(/checked=""/);
    expect(input).toContain('aria-checked="false"');
  });
});

describe("SF-4: the Settled count and list read one predicate", () => {
  it("superseded is in All only; Settled is answered or declined", () => {
    const rows = ["open", "answered", "declined", "superseded"].map((status) => ({ status, draft: false }));
    expect(rows.filter((r) => rowInFilter(r, "settled")).map((r) => r.status)).toEqual(["answered", "declined"]);
    expect(rows.filter((r) => rowInFilter(r, "all"))).toHaveLength(4);
    expect(rows.filter((r) => rowInFilter(r, "open")).map((r) => r.status)).toEqual(["open"]);
    expect(rowInFilter(askRow(stored(FOUR.replace("status: open", "status: superseded"))), "settled")).toBe(false);
  });
});

describe("SF-5: unsent notes survive a remount", () => {
  const init = { values: {}, text: {}, note: "" };
  const keys = ["F1", "F2"];
  it("restores notes by fork and the note to the asker, and says so when the revision moved", () => {
    const kept = { revision: "1", values: { F1: ["A"] }, text: { F1: "my fork note", F9: "orphan" }, note: "to the asker" };
    const r = restoreUnsent(init, kept, "2", keys);
    expect(r.text).toEqual({ F1: "my fork note" });
    expect(r.note).toBe("to the asker");
    expect(r.values).toEqual({});
    expect(r.notice).toContain("The ask changed under you (now revision 2): your unsent notes are kept below");
    expect(r.notice).toContain("F9");
    expect(r.notice).toContain("1 unsent pick was cleared");
  });
  it("at the same revision (navigating away and back) restores picks too, silently", () => {
    const r = restoreUnsent(init, { revision: "1", values: { F1: ["A"] }, text: { F2: "n" }, note: "" }, "1", keys);
    expect(r).toEqual({ values: { F1: ["A"] }, text: { F2: "n" }, note: "", notice: "" });
  });
  it("says nothing when what was kept is what the file already holds", () => {
    const saved = { values: { F1: ["A"] }, text: { F1: "n" }, note: "x" };
    expect(restoreUnsent(saved, { revision: "1", ...saved }, "2", keys).notice).toBe("");
    expect(restoreUnsent(init, undefined, "2", keys).notice).toBe("");
  });
});

describe("NITs", () => {
  it("clampSide(NaN) is a width, not NaN", () => {
    expect(Number.isFinite(clampSide(Number.NaN))).toBe(true);
  });
  it("an ask with no status line is answerable from the card", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const a = stored(FOUR.replace("status: open\n", ""));
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    expect(html).toContain("Note to the asker");
  });
});

describe("Operator 00:30: the option card's top row", () => {
  const CARD = head() + "## ¶ASK_J: Choose one: Jobs?\nLean: JOBA — fewer moving parts\n- [ ] [JOBA] Job A\n  Effort: S\n- [ ] [JOBB] Job B\n  Effort: L\n";
  it("the ★ sits in the option's header row beside the code chip, and there is no Recommended chip", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const a = stored(CARD);
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    expect(html).not.toContain("Recommended");
    const top = html.match(/<span class="opt-label"><code class="okey">JOBA<\/code>.*?<\/span><\/span><\/span>/)?.[0] ?? "";
    expect(top).toContain('<span class="strip"');
    expect(top).toContain("★");
    expect((html.match(/★/g) ?? []).length).toBe(2); // the option's ★ and the legend's, nothing else
  });
  it("a dimension given by no option is hidden, and with none given there is no strip or legend", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const a = stored(CARD);
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    expect(html).not.toMatch(/Risk \(blast radius\)/); // no option gives a blast radius
    expect(html).toContain("Effort: ");
    const bare = stored(head() + "## ¶ASK_K: Choose one: Bare?\n- [ ] [P] p\n- [ ] [Q] q\n");
    const b = renderToStaticMarkup(createElement(AskDetail, { ask: bare, all: [bare], onChanged: () => {} }));
    expect(b).not.toContain('class="strip"');
    expect(b).not.toContain('class="legend"');
    expect(b).not.toContain("–");
  });
  it("'Why the lean' never shows a lone separator", async () => {
    const { leanReason } = await import("../src/client/model.ts");
    expect(leanReason(" .")).toBe("");
    expect(leanReason("— fewer moving parts")).toBe("fewer moving parts");
  });
});
