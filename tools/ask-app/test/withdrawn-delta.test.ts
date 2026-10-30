/**
 * ASKWITHDRAWN delta critique (builds/ASKWITHDRAWN_DELTA_CRITIQUE.md), closed in the ASKFOLLOW lane:
 * - SHOULD-1: a 409's apply step is a pure applyConflict(step, deps), tested with spies; App's wiring is
 *   pinned whole, so the critic's plants A–D (a second setBatchResult, the wrong open key, a dropped
 *   reload, a dropped keep) each go red; Send batch writes its line once, from a helper.
 * - P13 / Q4: WithdrawnBar's state is a pure barStep reducer; only "yes" clears; Forget dispatches "forget".
 * - NIT-A: the kept-in-browser words say what is kept (a request too), and a request keeps its kind.
 */
import { afterEach, describe, expect, it, vi } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import { parseAskFile } from "../src/lib/format.ts";
import { applyConflict, conflictStep } from "../src/client/supersede.ts";
import { batchOutcome, batchResultLine } from "../src/client/next.ts";
import { RELOAD_RESTARTED, RELOAD_UPDATED } from "../src/client/token.ts";
import { barStep, cardUnsent, forgetMemory, keptDraftLines, keptSentence, saveUnsent } from "../src/client/unsent.ts";

const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes, ship\n- [ ] [NO] No, hold\n";
const head = (extra = "", status = "withdrawn") => `---\nid: w1\nto: operator\nfrom: idealic:kernel\nstatus: ${status}\nrevision: 5\ncreated: 2026-10-30T10:00:00.000Z\n${extra}---\n\n`;
const W = "withdrawn-at: 2026-10-30T16:20:00.000Z\nwithdrawn-actor: idealic:kernel\nwithdrawn-reason: moot\n";
const stored = (text: string) => ({ ...parseAskFile(text), seat: "idealic:kernel", file: "/x.md", mtimeMs: 0 });
const withdrawn = stored(head(W) + BODY);
const open = stored(head("", "open") + BODY);
const REF = "idealic:kernel/w1";
const app = fs.readFileSync(path.join(import.meta.dirname, "../src/client/App.tsx"), "utf8");
const fnBody = (start: string, len = 1200) => {
  // NIT-B (delta): a start that is not in App fails here rather than slicing "" and passing on nothing.
  if (!app.includes(start)) throw new Error(`fnBody: ${start} is not in App.tsx`);
  return app.slice(app.indexOf(start), app.indexOf(start) + len);
};

afterEach(() => forgetMemory());

describe("SHOULD-1: applyConflict applies a step, and nothing else", () => {
  const deps = () => ({ save: vi.fn(), setReplacedBy: vi.fn(), reload: vi.fn(), setResult: vi.fn() });
  const C409 = { status: "withdrawn", withdrawnBy: "idealic:kernel", withdrawnReason: "moot" };

  it("a withdrawal keeps under the open key, reloads, names no replacement, and shows the text (plants C, D)", () => {
    const d = deps();
    const s = conflictStep(C409, "change:x", "x");
    applyConflict(s, d);
    expect(d.save.mock.calls).toEqual([["x"]]);
    expect(d.reload).toHaveBeenCalledTimes(1);
    expect(d.setReplacedBy).not.toHaveBeenCalled();
    expect(d.setResult.mock.calls).toEqual([[s.text]]);
  });

  it("a supersede keeps here, names the replacement, does not reload", () => {
    const d = deps();
    applyConflict(conflictStep({ status: "superseded", supersededBy: "a/b" }, "here", "open"), d);
    expect(d.save.mock.calls).toEqual([["here"]]);
    expect(d.setReplacedBy.mock.calls).toEqual([["a/b"]]);
    expect(d.reload).not.toHaveBeenCalled();
  });

  it("a stale revision only shows the text", () => {
    const d = deps();
    applyConflict(conflictStep({ revision: 7 }, "here", "open"), d);
    expect(d.save).not.toHaveBeenCalled();
    expect(d.setReplacedBy).not.toHaveBeenCalled();
    expect(d.reload).not.toHaveBeenCalled();
    expect(d.setResult).toHaveBeenCalledTimes(1);
  });
});

describe("SHOULD-1: App's conflict wiring, pinned whole", () => {
  it("the deps save the one snapshot, reload by onChanged and show by setResult", () => {
    expect(app).toContain("const conflictDeps = { save: (k: string) => saveUnsent(k, snap()), setReplacedBy, reload: onChanged, setResult };");
  });
  it("onConflict hands conflictStep the open form's key, never `here` twice (plant B)", () => {
    expect(app).toContain("const onConflict = (json: Parameters<typeof conflictStep>[0], here: string) => applyConflict(conflictStep(json, here, unsentKey(ref, false)), conflictDeps);");
    expect(app.match(/conflictStep\(/g)).toHaveLength(1);
  });
  it("the follow-up's 409 goes through the same apply", () => {
    expect(app).toMatch(/const step = followupConflict\(r\.json, keyFor\(false\), unsentKey\(ref, false\)\);[^}]*return applyConflict\(step, conflictDeps\);/);
    expect(app.match(/applyConflict\(/g)).toHaveLength(2);
  });
});

describe("SHOULD-1: Send batch writes its line once, from batchOutcome (plant A)", () => {
  it("batchOutcome: a restart, an error, or the batch line", () => {
    expect(batchOutcome({ status: 200, json: {}, restarted: "updated" })).toEqual({ line: RELOAD_UPDATED, reload: false });
    expect(batchOutcome({ status: 200, json: {}, restarted: "restarted" })).toEqual({ line: RELOAD_RESTARTED, reload: false });
    expect(batchOutcome({ status: 500, json: { error: "boom" } })).toEqual({ line: "Error: boom", reload: false });
    const json = { settled: [{}], pushes: [{ seat: "a", refs: ["x"], delivery: { status: "delivered" } }], refused: [] };
    expect(batchOutcome({ status: 200, json })).toEqual({ line: batchResultLine(json), reload: true });
  });
  it("sendBatch calls setBatchResult once, with batchOutcome's line", () => {
    const fn = fnBody("async function sendBatch(", 900);
    expect(fn.match(/setBatchResult\(/g)).toEqual(["setBatchResult("]);
    expect(fn).toContain("line = out.line;");
    expect(fn).toContain("if (out.reload) load();");
    // NIT-5 (ASKFOLLOW critique): a throw replaces the old line too, and the line is written once, last.
    expect(fn).toMatch(/catch \(e\) \{\s*line = `Error: \$\{\(e as Error\)\.message\}`;\s*\} finally \{\s*setSending\(false\);\s*setBatchResult\(line\);/);
  });
  it("NIT-5: the old batch line is not shown while a new batch sends", () => {
    expect(app).toContain('{batchResult && !sending && <p className="tray-result" role="status">{batchResult}</p>}');
  });
  // NIT-4 (ASKFOLLOW critique): the ban is on the conflict paths, where "moved" misnamed a stale revision;
  // the missing-ask line may say moved, since a move to another seat is one of its causes.
  it("App words no move on its conflict paths", () => {
    for (const start of ["async function sendBatch(", "const conflictDeps = ", "const onConflict = ", "async function sendFollowup("]) {
      // NIT-B (delta): a renamed start would slice "" and pass on nothing.
      expect(app).toContain(start);
      expect(fnBody(start, 2400)).not.toMatch(/moved/);
    }
    expect(app).toContain("It may have been moved to another seat, renamed or deleted;");
  });
});

describe("P13: WithdrawnBar's state is the barStep reducer", () => {
  const s0 = { confirming: false };
  it("forget opens the confirm and clears nothing", () => {
    expect(barStep(s0, "forget")).toEqual({ state: { confirming: true }, clear: false });
  });
  it("only yes clears", () => {
    expect(barStep({ confirming: true }, "yes")).toEqual({ state: { confirming: false }, clear: true });
    for (const ev of ["forget", "keep", { copied: true }, { copied: false }] as const) {
      expect(barStep({ confirming: true, copy: "ok" }, ev).clear).toBe(false);
    }
  });
  it("keep closes the confirm; a copy records whether it took", () => {
    expect(barStep({ confirming: true }, "keep")).toEqual({ state: { confirming: false }, clear: false });
    expect(barStep(s0, { copied: true }).state.copy).toBe("ok");
    expect(barStep(s0, { copied: false }).state.copy).toBe("failed");
  });
  it("App: Forget dispatches forget, Yes dispatches yes, and clearUnsent sits behind clear only", () => {
    const bar = fnBody("export function WithdrawnBar(", 3200);
    expect(bar).toContain('onClick={() => dispatch("forget")}>Forget them…</button>');
    expect(bar).toContain('onClick={() => dispatch("yes")}>Yes, forget them</button>');
    expect(bar).toContain('onClick={() => dispatch("keep")}>Keep them</button>');
    expect(bar.match(/clearUnsent\(/g)).toHaveLength(1);
    expect(bar).toMatch(/if \(r\.clear\) \{\s*clearUnsent\(unsentKey\(ref, false\)\);/);
    expect(bar).not.toMatch(/setConfirming|setCopy/);
  });
});

describe("NIT-A: the kept words say what is kept, and a request keeps its kind", () => {
  it("keptSentence names what the copy holds", () => {
    expect(keptSentence(cardUnsent("4", { values: { GO: "YES" }, text: {}, note: "ship", need: "" }))).toBe("Your picks and notes are kept in this browser:");
    expect(keptSentence(cardUnsent("4", { values: {}, text: {}, note: "", need: "is BIND worth it?" }))).toBe("Your request is kept in this browser:");
    expect(keptSentence(cardUnsent("4", { values: { GO: "YES" }, text: {}, note: "", need: "x", followup: "y" }))).toBe("Your picks, request and follow-up are kept in this browser:");
  });
  it("a request line carries its kind", () => {
    expect(keptDraftLines(withdrawn, cardUnsent("4", { values: {}, text: {}, note: "", need: "is BIND worth it?", needKind: "proof:explore" }))).toEqual(["Request (Explore: map the whole): is BIND worth it?"]);
    // A copy kept before the kind was kept reads as it did.
    expect(keptDraftLines(withdrawn, cardUnsent("4", { values: {}, text: {}, note: "", need: "is BIND worth it?" }))).toEqual(["Request: is BIND worth it?"]);
    expect(cardUnsent("4", { values: {}, text: {}, note: "", need: " ", needKind: "proof:explore" })).toEqual({ revision: "4", values: {}, text: {}, note: "" });
  });
  it("the withdrawn card says it with the kind; the open card gets its kind back on a remount", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    saveUnsent(REF, cardUnsent("4", { values: {}, text: {}, note: "", need: "is BIND worth it?", needKind: "proof:explore" }));
    const w = renderToStaticMarkup(createElement(AskDetail, { ask: withdrawn, all: [withdrawn], onChanged: () => {}, onSent: () => {} }));
    expect(w).toContain("Your request is kept in this browser:");
    expect(w).toContain("Request (Explore: map the whole): is BIND worth it?");
    const o = renderToStaticMarkup(createElement(AskDetail, { ask: open, all: [open], onChanged: () => {}, onSent: () => {} }));
    expect(o).toContain('<option value="proof:explore" selected="">');
  });
  it("App's one snapshot holds the request's kind", () => {
    expect(app).toContain("const snap = () => cardUnsent(revision, { values, text, note, need: needText, needKind, followup: followText, followKind, followFork, followAttach: attachPicks });");
  });
});
