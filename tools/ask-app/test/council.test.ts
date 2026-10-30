/**
 * IDE-338 ASKCOUNCIL: a fork carries its council's report as `Council: <path-or-url>` beside its
 * `Panel:` reads, and `engine ask new` / `revise` warn when a fork says a council or panel ran but
 * carries no `Panel:` line, so the reads the app renders are never left in prose.
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { authorWarnings, mentionsPanelReport, parseAskFile } from "../src/lib/format.ts";

const head = "---\nid: c1\nto: operator\nfrom: meta:engine\nstatus: open\n---\n\n";

const withCouncil = `${head}## ¶ASK_FUND: Choose one: What does a world fund its contracts out of?
Lean: B
Panel: Security → B — a separate root keeps the blast small
Council: /Users/x/sessions/S/builds/FUND_COUNCIL_1.md
- [ ] [A] One root
- [ ] [B] A separate root
`;

describe("Council: field", () => {
  it("is parsed per fork and kept out of the fork's prose", () => {
    const q = parseAskFile(withCouncil).questions[0];
    expect(q.council).toBe("/Users/x/sessions/S/builds/FUND_COUNCIL_1.md");
    expect(q.prose ?? "").not.toContain("Council:");
    expect(q.panel).toHaveLength(1);
  });
  it("takes a URL or a markdown link as written", () => {
    const md = withCouncil.replace(/^Council: .*$/m, "Council: [the board](https://x.example/board.html)");
    expect(parseAskFile(md).questions[0].council).toBe("[the board](https://x.example/board.html)");
  });
  it("is absent on a fork without one", () => {
    const q = parseAskFile(`${head}## Choose one: X?\n- [ ] [A] a\n- [ ] [B] b\n`).questions[0];
    expect(q.council).toBeUndefined();
  });
  it("keeps the first of two Council: lines and warns about the second", () => {
    const two = withCouncil.replace(/^(Council: .*)$/m, "$1\nCouncil: https://x.example/second.html");
    const ask = parseAskFile(two);
    expect(ask.questions[0].council).toBe("/Users/x/sessions/S/builds/FUND_COUNCIL_1.md");
    expect(authorWarnings(ask).some((w) => w.includes("more than one Council:"))).toBe(true);
  });
});

describe("a Council: line that names no report (S3)", () => {
  const ask = `${head}## Choose one: Run it?\nLean: A\nCouncil: auto after each PR\n- [ ] [A] a\n- [ ] [B] b\n`;
  it("stays in the fork's prose and sets no council", () => {
    const q = parseAskFile(ask).questions[0];
    expect(q.council).toBeUndefined();
    expect(q.prose).toContain("Council: auto after each PR");
  });
  it("warns that it names no path or URL, and not the panel warning", () => {
    const ws = authorWarnings(parseAskFile(ask));
    expect(ws.some((w) => w.includes("names no report path or URL"))).toBe(true);
    expect(ws.some((w) => w.includes("carries no Panel: line"))).toBe(false);
  });
  it.each(["builds/X_COUNCIL.md", "/Users/x/r.md", "~/r.html", "https://x.example/r.html", "[board](https://x.example/b.html)"])("takes %s as the report", (v) => {
    expect(parseAskFile(ask.replace("auto after each PR", v)).questions[0].council).toBe(v);
  });
});

describe("a Panel: pick that names no option (S2)", () => {
  const ask = (pick: string) => `${head}## Choose one: Land?\nLean: LAND\nPanel: Security → ${pick} — fine\nCouncil: builds/X_COUNCIL.md\n- [ ] [LAND] Land it\n- [ ] [HOLD] Hold it\n`;
  const w = (pick: string) => authorWarnings(parseAskFile(ask(pick))).find((x) => x.includes("names no option"));
  it("warns on a bracketed or unknown code, naming the codes", () => {
    expect(w("[LAND]")).toContain("LAND, HOLD");
    expect(w("LNAD")).toBeDefined();
  });
  it("is silent on a bare code or the option's label", () => {
    expect(w("LAND")).toBeUndefined();
    expect(w("Hold it")).toBeUndefined();
  });
});

describe("a fork that reports a panel without Panel: lines", () => {
  const reported = [
    "The council report: builds/VOICE_COUNCIL.md",
    "Lean: NARROW — unanimous on the panel.",
    "Context: the panel's strongest agreement (all five) is that Language owns it",
    "What the panel found (five experts plus an independent refuter): the shape holds.",
    "A 3-lens council plus refutation read F1.",
    "Evidence: sessions/S/builds/FUND_COUNCIL_2.md",
    "The council's verdict: the section-first shape is sound.",
    // Real asks the first tightening missed (ASKCOUNCIL_CRITIQUE_S3.md S4, live root 2026-10-30).
    "Evidence: [panel report](http://127.0.0.1:9440/proofs/proofs/invizko/fork2-fits-321ace0a.html)",
    "The giant hero requires one metric marked as the figure. That's the council's must-fix.",
    "Stake: the council's rule is that BIND becomes the grade only after a corpus of 30 or more real pages.",
    "why: Re-ask of the outline's open questions; leans updated by the panel, two new questions it surfaced.",
    "Cost: the panel's top style risk.",
    "## ¶ASK_Q16: Choose one: Q16. When does it get its own section? (new, from the panel)",
    "Lean: MOVE — with the panel's condition that the rule is lifted out first.",
    "Context: you approved draft 1 pending the council; draft 2 is that draft with the panel's fixes.",
    "So the panel's \"guests get no state\" holds only for the kernel's answer.",
    "Panel consensus: LAND, 4 of 5 lenses",
    "Council verdict: keep the separate root",
    "A council ran on this: 4 of 5 lenses pick B",
    "the panel unanimously picked LAND",
    "The panel recommends B over A",
  ];
  const proposed = [
    "Context: /council exists and takes a target; nothing groups asks.",
    "- [ ] [BTN] A \"request council\" action on each ask",
    "Stake: a council per question is expensive; batching by topic is the saving.",
    "The app's side panel shows the fork list.",
    "Council auto-after-PR, Interrogation None",
    // The review's probes (ASKCOUNCIL_CRITIQUE.md S1, N3): a UI panel, or a council only proposed.
    "The panel's layout is cramped on mobile.",
    "Move it to the side panel read by the screen reader.",
    "The settings panel found in the sidebar.",
    "Data from the panel on the left.",
    "Council ran out of budget, so none ran.",
    "Should we convene the council?",
    "a 3-lens council would cost too much; propose one",
    "Should we file a council report next week?",
    "the panel reads should show beside each option",
    "Confidence: medium — the panel's view would help",
    // Proposals the corpus holds, which the widening must still leave alone.
    "## ¶ASK_ATTACH: Choose one: Who writes a panel's reads onto an ask the panel's runner did not file?",
    "Cost: a new skill, and a council board per approved set",
  ];
  it.each(reported)("names a panel report: %s", (line) => expect(mentionsPanelReport(line)).toBe(true));
  it.each(proposed)("does not name one: %s", (line) => expect(mentionsPanelReport(line)).toBe(false));

  const fork = (extra: string) => `${head}## ¶ASK_VOICE: Choose one: Land draft 2?\nLean: LAND\n${extra}\n- [ ] [LAND] Land it\n- [ ] [HOLD] Hold it\n`;
  const warning = (ask: string) => authorWarnings(parseAskFile(ask)).find((w) => w.includes("Panel:"));

  it("warns, naming the fork and showing the line format", () => {
    const w = warning(fork("Context: the panel's corrections are folded in (report: builds/VOICE_COUNCIL.md)."));
    expect(w).toContain('"Land draft 2?"');
    expect(w).toContain("Panel: <lens> → <code> — <why>");
    expect(w).toContain("Council: <path-or-url>");
  });
  it("warns on a fork whose Council: line has no Panel: reads", () => {
    expect(warning(fork("Council: builds/VOICE_COUNCIL.md"))).toContain('"Land draft 2?"');
  });
  it("is silent once the fork carries Panel: lines", () => {
    expect(warning(fork("Context: the panel's corrections are folded in.\nPanel: Copywriter → LAND — the rules read the same"))).toBeUndefined();
  });
  it("is silent on a fork that only proposes a council", () => {
    expect(warning(fork("Stake: a council per question is expensive."))).toBeUndefined();
  });
  it("warns once for a preamble that names a report when no fork has Panel: lines", () => {
    const ask = head.replace("\n\n", "\n\nThe five-reviewer panel report behind the outline is linked.\n\n") + "## Choose one: X?\nLean: A\n- [ ] [A] a\n- [ ] [B] b\n";
    const ws = authorWarnings(parseAskFile(ask)).filter((w) => w.includes("Panel:"));
    expect(ws).toHaveLength(1);
    expect(ws[0]).toContain("the text above the first fork");
  });
  it("reads the header's prose fields too (a confidence that cites the council)", () => {
    const ask = head.replace("status: open\n", "status: open\nconfidence: high — a 3-lens council plus refutation\n") + "## Choose one: X?\nLean: A\n- [ ] [A] a\n- [ ] [B] b\n";
    expect(authorWarnings(parseAskFile(ask)).filter((w) => w.includes("Panel:"))).toHaveLength(1);
  });
});

describe("engine ask new: the warning reaches stderr and filing still succeeds", () => {
  it("exits 0, files the ask, and prints the warning", () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "askcouncil-"));
    const asks = path.join(root, "asks");
    fs.mkdirSync(asks);
    const body = path.join(root, "body.md");
    fs.writeFileSync(body, "## ¶ASK_VOICE: Choose one: Land draft 2?\nLean: LAND\nContext: the council's verdict is folded in.\n- [ ] [LAND] Land it\n- [ ] [HOLD] Hold it\n");
    const cli = fileURLToPath(new URL("../src/cli.ts", import.meta.url));
    const env: NodeJS.ProcessEnv = { ...process.env, ASK_SESSIONS_DIR: path.join(root, "sessions") };
    for (const k of ["TMUX_PANE", "FLEET_PANE", "FLEET_PARENT", "FLEET_MANAGES"]) delete env[k];
    const r = spawnSync(process.execPath, ["--no-warnings", cli, "new", "--from", "meta:engine", "--to", "operator", "--id", "c-warn", "--body-file", body, "--root", asks], { encoding: "utf8", env });
    expect(r.status).toBe(0);
    expect(r.stderr).toContain('"Land draft 2?"');
    expect(r.stderr).toContain("Panel: <lens> → <code> — <why>");
    expect(fs.existsSync(path.join(asks, "meta:engine", "c-warn.md"))).toBe(true);
  });
});
