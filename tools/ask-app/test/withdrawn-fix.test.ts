/**
 * ASKWITHDRAWN-UI fix round (critique of fa9ce6d):
 * - MF-1: text typed in "Need something first" is kept with the picks and notes, and shown on withdrawal;
 * - S-1: what the operator reads after a 409 and after a Send batch comes from pure helpers, tested
 *   on their output; App only calls them (the pins below go red on the critic's two plants);
 * - S-2: "Copied." only after a copy that succeeded; Forget asks first;
 * - NIT-2/3/4: the overrule 409 keeps its copy where WithdrawnBar reads it; a batch withdrawal gets its
 *   own line; kept lines print option labels.
 */
import { afterEach, describe, expect, it, vi } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import { parseAskFile } from "../src/lib/format.ts";
import { conflictStep } from "../src/client/supersede.ts";
import { batchResultLine } from "../src/client/next.ts";
import { unsentKey } from "../src/client/reanswer.ts";
import { cardUnsent, clearUnsent, copyText, forgetMemory, forgetWords, keptDraftLines, loadUnsent, saveUnsent } from "../src/client/unsent.ts";

const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes, ship\n- [ ] [NO] No, hold\n";
const head = (extra = "", status = "withdrawn") =>
  `---\nid: w1\nto: operator\nfrom: idealic:kernel\nstatus: ${status}\nrevision: 5\ncreated: 2026-10-30T10:00:00.000Z\n${extra}---\n\n`;
const W = "withdrawn-at: 2026-10-30T16:20:00.000Z\nwithdrawn-actor: idealic:kernel\nwithdrawn-reason: moot: the kernel shipped the other way\n";
const stored = (text: string) => ({ ...parseAskFile(text), seat: "idealic:kernel", file: "/x.md", mtimeMs: 0 });
const withdrawn = stored(head(W) + BODY);
const open = stored(head("", "open") + BODY);
const REF = "idealic:kernel/w1";
const C409 = { error: "ask w1 is withdrawn by idealic:kernel (moot: the kernel shipped the other way): there is nothing to answer", status: "withdrawn", withdrawnBy: "idealic:kernel", withdrawnAt: "2026-10-30T16:20:00.000Z", withdrawnReason: "moot: the kernel shipped the other way" };
const NOTICE = "Not saved: this ask was withdrawn by idealic:kernel: moot: the kernel shipped the other way. There is nothing to answer; your picks and notes are kept in this browser.";

const fakeStore = () => {
  const m = new Map<string, string>();
  return { m, s: { getItem: (k: string) => m.get(k) ?? null, setItem: (k: string, v: string) => void m.set(k, v), removeItem: (k: string) => void m.delete(k) } };
};

async function render(ask: ReturnType<typeof stored>) {
  const { AskDetail } = await import("../src/client/App.tsx");
  return renderToStaticMarkup(createElement(AskDetail, { ask, all: [ask], onChanged: () => {}, onSent: () => {} }));
}

afterEach(() => {
  clearUnsent(REF);
  forgetMemory();
});

describe("MF-1: the request text is kept with the picks", () => {
  it("cardUnsent carries the request text, and drops a blank one", () => {
    expect(cardUnsent("4", { values: {}, text: {}, note: "", need: "is BIND worth it?" })).toEqual({ revision: "4", values: {}, text: {}, note: "", need: "is BIND worth it?" });
    expect(cardUnsent("4", { values: {}, text: {}, note: "", need: "  " })).toEqual({ revision: "4", values: {}, text: {}, note: "" });
  });

  it("a copy holding only request text is stored, survives a reload, and is listed", () => {
    const { m, s } = fakeStore();
    saveUnsent(REF, cardUnsent("4", { values: {}, text: {}, note: "", need: "two lines\nof request" }), s);
    expect(m.has(`askclient.unsent.${REF}`)).toBe(true);
    forgetMemory();
    const back = loadUnsent(REF, s);
    expect(back?.need).toBe("two lines\nof request");
    expect(keptDraftLines(withdrawn, back!)).toEqual(["Request: two lines\nof request"]);
  });

  it("route 1, the remount: what the open card saved at revision 4 is shown on the withdrawn card at revision 5", async () => {
    saveUnsent(unsentKey(REF, false), cardUnsent("4", { values: { GO: "YES" }, text: {}, note: "", need: "is BIND worth the migration?" }));
    // The remount in one session: memory holds it (the storage round trip is the test above).
    const html = await render(withdrawn);
    expect(html).toContain("You were answering this ask when it was withdrawn");
    expect(html).toContain("Request: is BIND worth the migration?");
    expect(html).toContain("GO: Yes, ship");
  });

  it("route 2, a 409 on Send request: the step keeps the copy under the key WithdrawnBar reads and reloads", () => {
    const st = conflictStep(C409, unsentKey(REF, false), unsentKey(REF, false));
    expect(st.keepUnder).toBe(unsentKey(REF, false));
    expect(st.reload).toBe(true);
  });

  it("an open card that remounts gets its request text back", async () => {
    saveUnsent(REF, cardUnsent("5", { values: {}, text: {}, note: "", need: "is BIND worth the migration?" }));
    const html = await render(open);
    expect(html).toContain("is BIND worth the migration?</textarea>");
  });

  it("App saves one snapshot everywhere, and it holds the request text", () => {
    const app = fs.readFileSync(path.join(import.meta.dirname, "../src/client/App.tsx"), "utf8");
    const calls = app.match(/saveUnsent\(/g) ?? [];
    // ASKFOLLOW: a copy re-based after a follow-up is still the one snapshot, moved to the new revision.
    const viaSnap = app.match(/saveUnsent\([^()]*(?:\([^()]*\))?[^()]*, (?:snap\(\)|rebaseAfterFollowup\(snap\(\), [^()]*\))\)/g) ?? [];
    expect(calls.length).toBeGreaterThan(0);
    expect(viaSnap.length).toBe(calls.length);
    expect(app).toMatch(/const snap = \(\) => cardUnsent\(revision, \{ values, text, note, need: needText(?:, needKind)?(?:, followup: followText)?(?:, followKind, followFork, followAttach: attachPicks)? \}\);/);
  });
});

describe("S-1: what the operator reads after a 409", () => {
  it("a withdrawal: the withdrawn notice, keep under the open form's key, reload", () => {
    expect(conflictStep(C409, "here", "open")).toEqual({ text: NOTICE, keepUnder: "open", reload: true });
    expect(conflictStep(C409, "here", "open").text).not.toMatch(/moved|revision/);
  });
  it("a supersede: names the replacement, keeps here, no reload", () => {
    expect(conflictStep({ status: "superseded", supersededBy: "a/b" }, "here", "open")).toEqual({ text: "This ask was replaced by a/b. Your picks are kept here; open the new ask to answer.", keepUnder: "here", replacedBy: "a/b", reload: false });
    expect(conflictStep({ status: "superseded" }, "here", "open").replacedBy).toBe("");
  });
  it("the ask moving on: says so, keeps nothing extra, no reload", () => {
    expect(conflictStep({ revision: 6 }, "here", "open")).toEqual({ text: "Not saved: the ask moved (now revision 6). Read the current state before answering again.", reload: false });
  });
  it("NIT-2: an overrule's 409 withdrawal keeps the copy where WithdrawnBar reads it, not under change:", () => {
    expect(conflictStep(C409, unsentKey(REF, true), unsentKey(REF, false)).keepUnder).toBe(REF);
  });
});

describe("S-1 / NIT-3: the Send batch line", () => {
  const json = {
    settled: ["a/b"],
    pushes: [{ seat: "a", refs: ["a/b"], delivery: { status: "delivered" } }],
    refused: [{ ref: REF, error: C409.error }, { ref: "c/d", error: "c/d has no draft to send" }],
  };
  it("a withdrawal is on its own line, says the picks are kept, and is never under Refused", () => {
    expect(batchResultLine(json)).toBe(
      "Sent 1. a: queued, not read yet — 1 answer in one message · Refused: c/d: c/d has no draft to send\n" +
        `${REF}: withdrawn by idealic:kernel: moot: the kernel shipped the other way; your picks are kept in this browser`,
    );
    expect(batchResultLine(json)).not.toMatch(/moved/);
  });
  it("only withdrawals: no Refused heading at all", () => {
    expect(batchResultLine({ ...json, refused: [json.refused[0]] })).toBe(
      "Sent 1. a: queued, not read yet — 1 answer in one message\n" + `${REF}: withdrawn by idealic:kernel: moot: the kernel shipped the other way; your picks are kept in this browser`,
    );
  });
  it("nothing refused: the line as before", () => {
    expect(batchResultLine({ ...json, refused: [] })).toBe("Sent 1. a: queued, not read yet — 1 answer in one message");
    expect(batchResultLine({ settled: [], pushes: [{ seat: "s", refs: ["x", "y"], delivery: { status: "failed", reason: "no pane" } }], refused: [] })).toBe("Sent 0. s: failed (no pane) — 2 answers in one message");
  });
});

/**
 * App's handlers need a browser to click. The helpers above decide every word; these pins hold App to
 * calling them and saying nothing of its own. Each goes red on one of the critic's plants (see the log).
 */
describe("App says only what the helpers say", () => {
  const app = fs.readFileSync(path.join(import.meta.dirname, "../src/client/App.tsx"), "utf8");
  it("every 409 branch is one call to onConflict", () => {
    const all = app.match(/status === 409/g) ?? [];
    const one = app.match(/if \(r\.status === 409\) return onConflict\(r\.json, keyFor\((?:true|changing)\)\);/g) ?? [];
    // ASKFOLLOW: the follow-up's 409 is conflictStep's too, through followupConflict and the same apply step.
    const follow = app.match(/if \(r\.status === 409\) \{\s*keep\(\);\s*const step = followupConflict\(r\.json, keyFor\(false\), unsentKey\(ref, false\)\);[^}]*return applyConflict\(step, conflictDeps\);\s*\}/g) ?? [];
    expect(all.length).toBe(3);
    expect(one.length + follow.length).toBe(all.length);
    expect(follow.length).toBe(1);
  });
  // SHOULD-1 (ASKWITHDRAWN delta): onConflict's apply step is supersede.ts applyConflict, spy-tested and
  // pinned whole in withdrawn-delta.test.ts.
  it("onConflict applies the step through applyConflict", () => {
    expect(app).toMatch(/const onConflict = \(json: Parameters<typeof conflictStep>\[0\], here: string\) => applyConflict\(conflictStep\(json, here, unsentKey\(ref, false\)\), conflictDeps\);/);
  });
  it("the batch line is the helper's, unaltered", () => {
    expect(app).toMatch(/setBatchResult\(line\);/);
    expect(app).not.toMatch(/batchResultLine\(/);
    expect(app).not.toMatch(/\.map\(refusedLine\)/);
  });
  it("App never words a conflict itself", () => {
    expect(app).not.toMatch(/ask moved/);
    expect(app).not.toMatch(/c\.withdrawn|\.withdrawn\) return/);
  });
});

describe("S-2: Copy tells the truth, and Forget asks first", () => {
  it("copyText is false with no clipboard, false on a rejected write, true on a written one", async () => {
    expect(await copyText("x", undefined)).toBe(false);
    expect(await copyText("x", {} as never)).toBe(false);
    expect(await copyText("x", { writeText: () => Promise.reject(new Error("denied")) })).toBe(false);
    const writeText = vi.fn(() => Promise.resolve());
    expect(await copyText("a\nb", { writeText })).toBe(true);
    expect(writeText).toHaveBeenCalledWith("a\nb");
  });

  it("forgetWords says whether the lines are anywhere else", () => {
    expect(forgetWords(true)).toBe("Forget them? They are on your clipboard; this browser stops keeping them.");
    expect(forgetWords(false)).toBe("Forget them? They were not copied, and nothing else holds them.");
  });

  const bar = async (seed: Record<string, unknown>) => {
    saveUnsent(REF, cardUnsent("4", { values: { GO: "YES" }, text: {}, note: "ship", need: "" }));
    const { WithdrawnBar } = await import("../src/client/App.tsx");
    return renderToStaticMarkup(createElement(WithdrawnBar, { ask: withdrawn, w: { actor: "idealic:kernel" }, seed }));
  };

  it("before any copy: no 'Copied.', and Forget is a first step, not the deletion", async () => {
    const html = await bar({});
    expect(html).not.toContain("Copied.");
    expect(html).toContain(">Forget them…<");
    expect(html).not.toContain("Yes, forget them");
  });
  it("a failed copy says so and shows the text selectable", async () => {
    const html = await bar({ copy: "failed" });
    expect(html).not.toContain("Copied.");
    expect(html).toContain("Copy failed; select the lines below by hand.");
    expect(html).toMatch(/<pre class="kept-copy"[^>]*>GO: Yes, ship\nNote: ship<\/pre>/);
  });
  it("a copy that succeeded says Copied.", async () => {
    const html = await bar({ copy: "ok" });
    expect(html).toContain("Copied.");
    expect(html).not.toContain("kept-copy");
  });
  it("Forget's confirm names what is lost, and offers to keep them", async () => {
    const html = await bar({ confirming: true });
    expect(html).toContain("They were not copied, and nothing else holds them.");
    expect(html).toContain(">Yes, forget them<");
    expect(html).toContain(">Keep them<");
  });
});

describe("NIT-4: kept lines print the option text", () => {
  it("a pick reads as its label; an unknown value as itself", () => {
    expect(keptDraftLines(withdrawn, { revision: "4", values: { GO: ["YES", "NO"] }, text: {}, note: "" })).toEqual(["GO: Yes, ship · No, hold"]);
    expect(keptDraftLines(withdrawn, { revision: "4", values: { GO: "ZZ" }, text: {}, note: "" })).toEqual(["GO: ZZ"]);
  });
});
