/**
 * IDE-338 ASKCOUNCIL round 2: `engine ask attach-panel` — any panel runner appends a council's
 * per-fork reads (and the options it proposes) to an ask it did not file. Append-only: the
 * question, its options, its answer, its revision and its body digest never move; each entry
 * records who attached it and when; a withdrawn or superseded ask refuses it.
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { beforeEach, describe, expect, it } from "vitest";
import { authorWarnings, bodyDigest, parseAskFile, parsePanelArg, parseProposalArg, RECORD_FENCE_RE, writeAnswer } from "../src/lib/format.ts";
import { answerAsk, attachPanel, newAsk, renameSeat, reviseAsk, withdrawAsk } from "../src/lib/store.ts";
import { rewriteSeatRefs } from "../src/lib/rename-seat.ts";

const SEAT = "core:kernel";
const RUNNER = "manager:director";
const URL1 = "http://127.0.0.1:9440/proofs/fund-council-1.html";
const BODY = `## ¶ASK_FUND: Choose one: What does a world fund its contracts out of?
Lean: B
- [ ] [A] One root
  Picks A.
- [ ] [B] A separate root
  Picks B.

## ¶ASK_SECOND: Choose one: Second?
Lean: X
- [ ] [X] x
  Picks X.
- [ ] [Y] y
  Picks Y.
`;

let root: string;
let pushes: { seat: string; content: string }[];
const push = async (seat: string, content: string) => (pushes.push({ seat, content }), { status: "delivered" as const });
const file = () => path.join(root, SEAT, "fund.md");
const reads = [
  { lens: "Security", pick: "B", why: "a separate root keeps the blast small" },
  { lens: "Economist", pick: "A", why: "one root is simpler to audit" },
];
const attach = (o: Partial<Parameters<typeof attachPanel>[2]> = {}) =>
  attachPanel(root, { seat: SEAT, id: "fund" }, { by: RUNNER, fork: "FUND", panel: reads, council: URL1, push, now: "2026-10-30T22:00:00.000Z", ...o });

beforeEach(() => {
  root = fs.mkdtempSync(path.join(os.tmpdir(), "attach-panel-"));
  pushes = [];
  newAsk(root, { from: SEAT, to: "operator", id: "fund" }, BODY);
});

describe("attach-panel: append-only", () => {
  it("adds the reads to the fork, each with who attached it, when, and its council URL", async () => {
    await attach();
    const q = parseAskFile(fs.readFileSync(file(), "utf8")).questions[0];
    expect(q.panel).toEqual(reads.map((r) => ({ ...r, attachedBy: RUNNER, attachedAt: "2026-10-30T22:00:00.000Z", council: URL1 })));
    expect(q.council).toBe(URL1);
  });
  it("never changes the question, its options, the revision or the body digest", async () => {
    const before = fs.readFileSync(file(), "utf8");
    const pb = parseAskFile(before);
    await attach();
    const after = fs.readFileSync(file(), "utf8");
    const pa = parseAskFile(after);
    expect(pa.header.revision).toBe(pb.header.revision);
    expect(bodyDigest(after)).toBe(bodyDigest(before));
    expect(pa.questions.map((q) => [q.title, q.options])).toEqual(pb.questions.map((q) => [q.title, q.options]));
    expect(pa.questions[1].panel).toEqual([]);
    expect(after.startsWith(before.replace(/\n*$/, ""))).toBe(true);
  });
  it("a second attach appends; the first entry is kept as written", async () => {
    await attach();
    await attach({ by: "manager:meta", panel: [{ lens: "Skeptic", pick: "A", why: "B is a root again" }], council: "http://127.0.0.1:9440/proofs/fund-council-2.html", now: "2026-10-30T23:00:00.000Z" });
    const ask = parseAskFile(fs.readFileSync(file(), "utf8"));
    expect(ask.panelAttachments.map((e) => e.by)).toEqual([RUNNER, "manager:meta"]);
    expect(ask.questions[0].panel.map((r) => r.lens)).toEqual(["Security", "Economist", "Skeptic"]);
    expect(ask.questions[0].council).toBe(URL1);
  });
  it("keeps the asker's own Panel: lines first and its Council: line", async () => {
    const own = BODY.replace("Lean: B\n", "Lean: B\nPanel: Copywriter → B — reads plainly\nCouncil: https://x.example/own.html\n");
    newAsk(root, { from: SEAT, to: "operator", id: "own" }, own);
    await attachPanel(root, { seat: SEAT, id: "own" }, { by: RUNNER, fork: "FUND", panel: reads, council: URL1, push });
    const q = parseAskFile(fs.readFileSync(path.join(root, SEAT, "own.md"), "utf8")).questions[0];
    expect(q.panel[0]).toEqual({ lens: "Copywriter", pick: "B", why: "reads plainly" });
    expect(q.panel).toHaveLength(3);
    expect(q.council).toBe("https://x.example/own.html");
  });
  it("records the options a panel proposes, apart from the fork's own options", async () => {
    await attach({ panel: [], proposals: [{ lens: "Ideas", label: "Fund from the deployer's root", why: "no new root at all" }] });
    const q = parseAskFile(fs.readFileSync(file(), "utf8")).questions[0];
    expect(q.options.map((o) => o.code)).toEqual(["A", "B"]);
    expect(q.proposals).toEqual([{ lens: "Ideas", label: "Fund from the deployer's root", why: "no new root at all", attachedBy: RUNNER, attachedAt: "2026-10-30T22:00:00.000Z", council: URL1 }]);
  });
  it("tells the asker, and not the runner", async () => {
    const r = await attach();
    expect(r.pushes.map((p) => p.seat)).toEqual([SEAT]);
    expect(pushes[0].content).toContain("[ask-panel]");
    expect(pushes[0].content).toContain(URL1);
    pushes = [];
    await attachPanel(root, { seat: SEAT, id: "fund" }, { by: SEAT, fork: "FUND", panel: reads, council: URL1, push });
    expect(pushes).toEqual([]);
  });
});

describe("attach-panel: refusals", () => {
  it("refuses a fork the ask does not have, naming the ones it has", async () => {
    await expect(attach({ fork: "NOPE" })).rejects.toThrow(/no fork NOPE.*FUND, SECOND/);
  });
  it("refuses a read whose pick names no option of the fork", async () => {
    await expect(attach({ panel: [{ lens: "Security", pick: "Z", why: "w" }] })).rejects.toThrow(/Z names no option of FUND \(it has A, B\).*--proposed/);
  });
  it("refuses an entry with no reads and no proposals", async () => {
    await expect(attach({ panel: [], proposals: [] })).rejects.toThrow(/at least one --panel or --proposed/);
  });
  it("refuses a council that is not an http(s) URL", async () => {
    await expect(attach({ council: "builds/FUND_COUNCIL.md" })).rejects.toThrow(/--council must be the published report's http\(s\) URL/);
    await expect(attach({ council: undefined })).rejects.toThrow(/--council/);
  });
  it("refuses a withdrawn ask", async () => {
    await withdrawAsk(root, { seat: SEAT, id: "fund" }, { by: SEAT, reason: "no longer asked", push });
    await expect(attach()).rejects.toThrow(/withdrawn/);
  });
  it("accepts an answered ask, as a record beside the answer", async () => {
    await answerAsk(root, SEAT, "fund", { answers: { FUND: ["B"], SECOND: ["X"] }, answeredBy: "operator", answeredVia: "cli" }, { push, expectedRevision: 1 });
    const before = parseAskFile(fs.readFileSync(file(), "utf8"));
    await attach();
    const after = parseAskFile(fs.readFileSync(file(), "utf8"));
    expect(after.answer).toEqual(before.answer);
    expect(after.header.status).toBe("answered");
    expect(after.questions[0].panel).toHaveLength(2);
  });
});

describe("the panels record survives every other write", () => {
  it("an answer keeps it", async () => {
    await attach();
    const t = writeAnswer(fs.readFileSync(file(), "utf8"), { answers: { FUND: ["A"], SECOND: ["Y"] }, answeredBy: "operator", answeredVia: "cli" });
    expect(parseAskFile(t).questions[0].panel).toHaveLength(2);
  });
  it("a revise keeps it", async () => {
    await attach();
    await reviseAsk(root, SEAT, "fund", {}, BODY.replace("Second?", "Second, reworded?"), { by: SEAT, push });
    const ask = parseAskFile(fs.readFileSync(file(), "utf8"));
    expect(ask.questions[1].title).toBe("Second, reworded?");
    expect(ask.questions[0].panel).toHaveLength(2);
  });
  it("a body that carries a panels fence is refused at filing", () => {
    expect(RECORD_FENCE_RE.test("```json panels\n[]\n```")).toBe(true);
  });
  it("rename-seat rewrites the attaching seat", async () => {
    await attach();
    const r = rewriteSeatRefs(fs.readFileSync(file(), "utf8"), RUNNER, "manager:directors");
    expect(r.changes.some((c) => c.field === "panels.by")).toBe(true);
    expect(parseAskFile(r.text).questions[0].panel[0].attachedBy).toBe("manager:directors");
  });
  it("renameSeat over the root moves the record with it", async () => {
    await attach();
    await renameSeat(root, RUNNER, "manager:directors", { by: "operator" });
    expect(parseAskFile(fs.readFileSync(file(), "utf8")).panelAttachments[0].by).toBe("manager:directors");
  });
});

describe("the --panel and --proposed argument grammar", () => {
  it("reads `<lens> → <code> — <why>`", () => {
    expect(parsePanelArg("Security → B — a separate root keeps the blast small")).toEqual({ lens: "Security", pick: "B", why: "a separate root keeps the blast small" });
    expect(parsePanelArg("no arrow here")).toBeUndefined();
  });
  it("reads `<lens> → <label> — <why>` with a label of several words", () => {
    expect(parseProposalArg("Ideas → Fund from the deployer's root — no new root")).toEqual({ lens: "Ideas", label: "Fund from the deployer's root", why: "no new root" });
  });
});

describe("engine ask attach-panel (CLI)", () => {
  const CLI = fileURLToPath(new URL("../src/cli.ts", import.meta.url));
  const run = (...args: string[]) => {
    const env: NodeJS.ProcessEnv = { ...process.env, ASK_SESSIONS_DIR: path.join(root, "..", "no-sessions") };
    for (const k of ["TMUX_PANE", "FLEET_PANE", "FLEET_PARENT", "FLEET_MANAGES"]) delete env[k];
    return spawnSync(process.execPath, ["--no-warnings", CLI, ...args, "--root", root], { encoding: "utf8", env });
  };
  it("takes repeated --panel flags and prints what it attached", () => {
    const r = run("attach-panel", `${SEAT}/fund`, "--fork", "FUND", "--panel", "Security → B — small blast", "--panel", "Economist → A — simpler audit", "--council", URL1, "--by", RUNNER);
    expect(r.stderr).toBe("");
    expect(r.status).toBe(0);
    expect(r.stdout).toContain(`attached\t${SEAT}/fund#FUND\t2 reads\t0 proposed\t${URL1}`);
    expect(parseAskFile(fs.readFileSync(file(), "utf8")).questions[0].panel.map((x) => x.lens)).toEqual(["Security", "Economist"]);
  });
  it("exits 1 naming a malformed --panel", () => {
    const r = run("attach-panel", `${SEAT}/fund`, "--fork", "FUND", "--panel", "Security picks B", "--council", URL1, "--by", RUNNER);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain('--panel "Security picks B" is not `<lens> → <code> — <why>`');
  });
});

// ── step-3 review (ASKCOUNCIL_CRITIQUE_S3.md) ─────────────

describe("M2: reads stay on the question the panel read", () => {
  const UNNAMED = "## Choose one: Fund?\nContext: c\n- [ ] [A] a\n  Picks A.\n- [ ] [B] b\n  Picks B.\n\n## Choose one: Other?\nContext: c\n- [ ] [X] x\n  Picks X.\n- [ ] [Y] y\n  Picks Y.\n";
  it("refuses an unnamed fork when the ask has more than one fork", async () => {
    newAsk(root, { from: SEAT, to: "operator", id: "anon" }, UNNAMED);
    await expect(attachPanel(root, { seat: SEAT, id: "anon" }, { by: RUNNER, fork: "q0", panel: [{ lens: "Sec", pick: "B", why: "w" }], council: URL1, push })).rejects.toThrow(/no ¶ASK_ name, and the ask has 2 forks/);
  });
  it("takes an unnamed fork when it is the only one", async () => {
    newAsk(root, { from: SEAT, to: "operator", id: "one" }, "## Choose one: Fund?\nContext: c\n- [ ] [A] a\n  Picks A.\n- [ ] [B] b\n  Picks B.\n");
    await attachPanel(root, { seat: SEAT, id: "one" }, { by: RUNNER, fork: "q0", panel: [{ lens: "Sec", pick: "B", why: "w" }], council: URL1, push });
    expect(parseAskFile(fs.readFileSync(path.join(root, SEAT, "one.md"), "utf8")).questions[0].panel).toHaveLength(1);
  });
  it("records the fork's title, and a retitled fork no longer draws the reads but the file keeps them and warns", async () => {
    await attach();
    expect(parseAskFile(fs.readFileSync(file(), "utf8")).panelAttachments[0].title).toBe("What does a world fund its contracts out of?");
    await reviseAsk(root, SEAT, "fund", {}, BODY.replace("What does a world fund its contracts out of?", "Which root pays?"), { by: SEAT, push });
    const ask = parseAskFile(fs.readFileSync(file(), "utf8"));
    expect(ask.questions[0].panel).toHaveLength(0);
    expect(ask.panelAttachments).toHaveLength(1);
    expect(authorWarnings(ask).some((w) => w.includes(`${RUNNER}'s attached panel`) && w.includes("is now \"Which root pays?\""))).toBe(true);
  });
});

describe("S1: a damaged record is never rewritten", () => {
  it("refuses to attach over a record whose JSON does not parse, and leaves it as it was", async () => {
    await attach();
    const broken = fs.readFileSync(file(), "utf8").replace('"fork": "FUND",', '"fork": "FUND",,');
    fs.writeFileSync(file(), broken);
    await expect(attach({ fork: "SECOND", panel: [{ lens: "z", pick: "X", why: "w" }], council: "http://x.example/2.html" })).rejects.toThrow(/panels record does not parse/);
    expect(fs.readFileSync(file(), "utf8")).toBe(broken);
  });
  it("refuses when an entry has no fork, rather than dropping it", async () => {
    await attach();
    fs.writeFileSync(file(), fs.readFileSync(file(), "utf8").replace('"fork": "FUND"', '"forkk": "FUND"'));
    await expect(attach({ fork: "SECOND", panel: [{ lens: "z", pick: "X", why: "w" }], council: "http://x.example/2.html" })).rejects.toThrow(/1 entry with no fork or by/);
  });
});

describe("S2: the same council on the same fork is attached once", () => {
  it("a second identical attach changes nothing and tells nobody", async () => {
    await attach();
    const once = fs.readFileSync(file(), "utf8");
    const n = pushes.length;
    const r = await attach();
    expect(r.already).toBe(true);
    expect(fs.readFileSync(file(), "utf8")).toBe(once);
    expect(pushes.length).toBe(n);
  });
  it("another council's reads on the same fork are still added", async () => {
    await attach();
    await attach({ council: "http://x.example/second.html" });
    expect(parseAskFile(fs.readFileSync(file(), "utf8")).questions[0].panel).toHaveLength(4);
  });
});

describe("S3: a revise that removes a picked option warns", () => {
  it("names who attached the read whose option is gone", async () => {
    await attach();
    await reviseAsk(root, SEAT, "fund", {}, BODY.replace("- [ ] [B] A separate root", "- [ ] [C] A shared root"), { by: SEAT, push });
    const ws = authorWarnings(parseAskFile(fs.readFileSync(file(), "utf8")));
    expect(ws.some((w) => w.includes(`${RUNNER}'s attached read Security → B names an option this fork no longer has`))).toBe(true);
  });
});
