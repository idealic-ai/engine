/**
 * ASKFOLLOW: the card's "Send follow-up" control over the ASKFOLLOWUP server (/api/followup).
 * - a follow-up is a question back or "do this first", optionally about one fork, optionally carrying
 *   the operator's current picks; the delivery result is said, and earlier follow-ups are listed with
 *   whether the asker has addressed them;
 * - a 409 goes through conflictStep (superseded, withdrawn, stale); a closed ask says so and reloads;
 * - unsent follow-up text survives a remount, kept in the card's one snapshot (cardUnsent);
 * - a 200 bumps the revision, so the card's unsent copy saved at the revision it sent from is re-based
 *   onto the new one, as the server re-bases the draft: the operator's own follow-up never reads as
 *   "the ask changed under you".
 */
import { afterEach, describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import { parseAskFile } from "../src/lib/format.ts";
import { cardUnsent, forgetMemory, keptDraftLines, loadUnsent, saveUnsent } from "../src/client/unsent.ts";
import {
  FOLLOWUP_KIND_OPTIONS,
  followupBody,
  followupConflict,
  followupLine,
  followupOutcome,
  followupResultFor,
  followupsOf,
  mayFollowUp,
  rebaseAfterFollowup,
  rememberFollowupResult,
  forgetFollowupResult,
  subscribeFollowupResults,
  FOLLOWUP_PENDING,
  adoptAfterFollowup,
  followupBumpOf,
  forkOnOpen,
  keepsOver,
} from "../src/client/followup.ts";

const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes, ship\n- [ ] [NO] No, hold\n\n## ¶ASK_WHEN: Choose one: When?\n- [ ] [NOW] Now\n- [ ] [LATER] Later\n";
const head = (status = "open", rev = 3, extra = "") => `---\nid: f1\nto: operator\nfrom: idealic:kernel\nstatus: ${status}\nrevision: ${rev}\ncreated: 2026-10-30T10:00:00.000Z\n${extra}---\n\n`;
const fence = (f: object) => `\n## Follow-up ${(f as { n: number }).n}\n\n\`\`\`json followup\n${JSON.stringify(f, null, 2)}\n\`\`\`\n`;
const answer = (a: object) => `\n\`\`\`json answer\n${JSON.stringify(a)}\n\`\`\`\n`;
const stored = (text: string, history?: object[]) => ({ ...parseAskFile(text), seat: "idealic:kernel", file: "/x.md", mtimeMs: 0, ...(history ? { history } : {}) });
const REF = "idealic:kernel/f1";
const src = (f: string) => fs.readFileSync(path.join(import.meta.dirname, "../src/client", f), "utf8");

const F1 = { n: 1, at: "2026-10-30T11:00:00.000Z", by: "operator", via: "browser", kind: "question", fork: "GO", text: "what does NO hold for?", delivery: "delivered", addressedIn: 3, addressedBy: "idealic:kernel", addressedAt: "2026-10-30T11:30:00.000Z" };
const F2 = { n: 2, at: "2026-10-30T12:00:00.000Z", by: "operator", via: "browser", kind: "first", text: "run the migration dry-run first", picks: { GO: ["YES"] }, delivery: "undelivered", deliveryNote: "no live session named idealic:kernel" };
const open = stored(head() + BODY);
const withFollowups = stored(head("open", 4) + BODY + fence(F1) + fence(F2), [{ type: "followup", ...F1 }, { type: "followup", ...F2 }]);

async function render(ask: ReturnType<typeof stored>) {
  const { AskDetail } = await import("../src/client/App.tsx");
  return renderToStaticMarkup(createElement(AskDetail, { ask, all: [ask], onChanged: () => {}, onSent: () => {} }));
}

afterEach(() => forgetMemory());

describe("the two kinds", () => {
  it("are a question back and do-this-first, in the operator's words", () => {
    expect(FOLLOWUP_KIND_OPTIONS.map((k) => [k.kind, k.label])).toEqual([["question", "Ask a question"], ["first", "Do this first"]]);
  });
});

describe("followupBody: what /api/followup is sent", () => {
  it("carries seat, id, the revision read, the kind and the text; a blank fork is omitted", () => {
    const b = followupBody(open, { kind: "question", fork: "", text: "why NO?", attachPicks: false }, { GO: ["YES"] });
    expect(b).toEqual({ seat: "idealic:kernel", id: "f1", expectedRevision: 3, kind: "question", text: "why NO?" });
    expect("fork" in b).toBe(false);
    expect("picks" in b).toBe(false);
  });

  it("names the fork it is about, and carries the picks only when attached and there are some", () => {
    expect(followupBody(open, { kind: "first", fork: "WHEN", text: "check the calendar", attachPicks: true }, { GO: ["YES"], "GO.other": "or ship half" })).toEqual({
      seat: "idealic:kernel", id: "f1", expectedRevision: 3, kind: "first", fork: "WHEN", text: "check the calendar", picks: { GO: ["YES"], "GO.other": "or ship half" },
    });
    expect("picks" in followupBody(open, { kind: "first", fork: "", text: "x", attachPicks: true }, {})).toBe(false);
  });
});

describe("followupOutcome: the delivery result, said", () => {
  it("a 200 delivered names the follow-up, the asker, and that the ask stays open", () => {
    expect(followupOutcome(open, 200, { revision: 4, followup: { n: 1 }, delivery: { status: "delivered" } })).toEqual({
      sent: true,
      revision: 4,
      text: "Follow-up 1 sent to idealic:kernel: delivered. The ask stays open; answer it as usual.",
    });
  });

  it("a 200 undelivered or partial still wrote it, and says why the push did not land", () => {
    expect(followupOutcome(open, 200, { revision: 4, followup: { n: 2 }, delivery: { status: "undelivered", reason: "no live session named idealic:kernel" } }).text).toBe(
      "Follow-up 2 is in the file, but undelivered (no live session named idealic:kernel). The asker's /next picks it up from the file.",
    );
    // NIT-1: no reason, no empty brackets.
    expect(followupOutcome(open, 200, { revision: 4, followup: { n: 2 }, delivery: { status: "undelivered" } }).text).toBe("Follow-up 2 is in the file, but undelivered. The asker's /next picks it up from the file.");
    expect(followupOutcome(open, 200, { revision: 4, followup: { n: 2 }, delivery: { status: "partial", reason: "one of two" } }).text).toBe(
      "Follow-up 2 is in the file, but partial (one of two). The asker's /next picks it up from the file.",
    );
  });

  it("a 400 is not sent and shows the server's words", () => {
    expect(followupOutcome(open, 400, { error: "unknown fork: Q9" })).toEqual({ sent: false, text: "Not sent: unknown fork: Q9" });
  });
});

describe("followupConflict: a 409 through conflictStep", () => {
  const W = { error: "x", status: "withdrawn", withdrawnBy: "idealic:kernel", withdrawnAt: "2026-10-30T16:20:00.000Z", withdrawnReason: "moot" };
  it("withdrawn, superseded and stale are conflictStep's own steps", async () => {
    const { conflictStep } = await import("../src/client/supersede.ts");
    expect(followupConflict(W, "here", "open")).toEqual(conflictStep(W, "here", "open"));
    expect(followupConflict({ status: "superseded", supersededBy: "a/b" }, "here", "open")).toEqual(conflictStep({ status: "superseded", supersededBy: "a/b" }, "here", "open"));
  });

  it("SHOULD-3: a stale revision is the follow-up's own line: not sent, the ask changed, re-read it", () => {
    expect(followupConflict({ revision: 7 }, "here", "open")).toEqual({ text: "Not sent: the ask changed (now revision 7). Re-read it, then send again.", reload: true });
    expect(followupConflict({}, "here", "open").text).toBe("Not sent: the ask changed. Re-read it, then send again.");
  });

  it("SHOULD-3: no follow-up 409 line says moved", () => {
    const W = { status: "withdrawn", withdrawnBy: "idealic:kernel", withdrawnReason: "moot" };
    for (const j of [W, { status: "superseded", supersededBy: "a/b" }, { status: "superseded" }, { revision: 7 }, {}, { status: "answered" }, { status: "declined" }]) {
      expect(followupConflict(j, "here", "open").text).not.toMatch(/moved/);
    }
  });

  it("an ask closed since it was read (answered, declined) says so, keeps the text and reloads", () => {
    expect(followupConflict({ error: "ask f1 is answered; a follow-up goes only to an open ask", status: "answered" }, "here", "open")).toEqual({
      text: "Not sent: this ask is answered now, and a follow-up goes only to an open ask. Your text is kept here.",
      keepUnder: "here",
      reload: true,
    });
  });
});

describe("earlier follow-ups, with their addressed state", () => {
  it("are read from /api/asks' history entries of type followup, oldest first", () => {
    expect(followupsOf(withFollowups).map((f) => f.n)).toEqual([1, 2]);
  });

  it("fall back to the parsed follow-ups when the history carries none (a server before ASKFOLLOWUP's history)", () => {
    const { history: _h, ...noHistory } = withFollowups;
    expect(followupsOf({ ...noHistory, history: [] }).map((f) => f.n)).toEqual([1, 2]);
  });

  it("a line says kind, fork, delivery and whether it was addressed (addressedIn set), by whom", () => {
    const [a, b] = followupsOf(withFollowups);
    expect(followupLine(withFollowups, a)).toBe("Follow-up 1 · Ask a question · about GO: Ship it? · delivered · addressed in revision 3 by idealic:kernel");
    expect(followupLine(withFollowups, b)).toBe("Follow-up 2 · Do this first · with your picks GO YES · undelivered (no live session named idealic:kernel) · not addressed yet");
  });

  it("an open card lists them; so does a settled one, since the dialogue outlives the answer", async () => {
    const h = await render(withFollowups);
    expect(h).toContain("Follow-ups (2)");
    expect(h).toContain("addressed in revision 3 by idealic:kernel");
    expect(h).toContain("what does NO hold for?");
    expect(h).toContain("not addressed yet");
    const settled = stored(head("answered", 5) + BODY + fence(F1) + answer({ answers: { GO: ["YES"], WHEN: ["NOW"] }, answeredBy: "operator", revision: 5 }), [{ type: "followup", ...F1 }]);
    expect(await render(settled)).toContain("Follow-ups (1)");
  });
});

describe("the Send follow-up control", () => {
  it("is offered only on an open ask", () => {
    expect(mayFollowUp(open)).toBe(true);
    expect(mayFollowUp(stored(head("answered") + BODY + answer({ answers: { GO: ["YES"] }, answeredBy: "operator", revision: 3 })))).toBe(false);
    expect(mayFollowUp(stored(head("withdrawn", 3, "withdrawn-actor: idealic:kernel\n") + BODY))).toBe(false);
    expect(mayFollowUp(stored(head("superseded", 3, "superseded-by: idealic:kernel/f2\n") + BODY))).toBe(false);
  });

  it("the open card has the button; a settled card does not", async () => {
    expect(await render(open)).toMatch(/<button[^>]*aria-controls="followup-f1"[^>]*>Send follow-up ▾<\/button>/);
    const settled = stored(head("answered") + BODY + answer({ answers: { GO: ["YES"] }, answeredBy: "operator", revision: 3 }));
    expect(await render(settled)).not.toContain("Send follow-up");
  });

  it("opened with kept text, it shows both kinds, the fork selector, the picks box and the text", async () => {
    saveUnsent(REF, cardUnsent("3", { values: {}, text: {}, note: "", need: "", followup: "which region does NO hold?" }));
    const h = await render(open);
    expect(h).toContain("which region does NO hold?</textarea>");
    // React writes `checked` before `value`; match the tag on both, in any order.
    expect(h).toMatch(/<input type="radio"(?=[^>]*value="question")(?=[^>]*checked="")[^>]*>/);
    expect(h).not.toMatch(/<input type="radio"(?=[^>]*value="first")(?=[^>]*checked="")[^>]*>/);
    expect(h).toContain(">Ask a question<");
    expect(h).toContain(">Do this first<");
    expect(h).toMatch(/<select id="followup-fork-f1"/);
    expect(h).toContain('<option value="" selected="">The whole ask</option>');
    expect(h).toContain('<option value="GO">GO: Ship it?</option>');
    expect(h).toContain('<option value="WHEN">WHEN: When?</option>');
    expect(h).toMatch(/<input type="checkbox"[^>]*disabled=""/); // no picks to attach yet
    expect(h).toMatch(/<button class="btn primary"[^>]*>Send follow-up<\/button>/);
  });
});

describe("unsent follow-up text survives a remount (cardUnsent)", () => {
  const fakeStore = () => {
    const m = new Map<string, string>();
    return { m, s: { getItem: (k: string) => m.get(k) ?? null, setItem: (k: string, v: string) => void m.set(k, v), removeItem: (k: string) => void m.delete(k) } };
  };

  it("cardUnsent keeps it, and leaves a blank one out", () => {
    expect(cardUnsent("3", { values: {}, text: {}, note: "", need: "", followup: "why?" })).toEqual({ revision: "3", values: {}, text: {}, note: "", followup: "why?" });
    expect(cardUnsent("3", { values: {}, text: {}, note: "", need: "", followup: "  " })).toEqual({ revision: "3", values: {}, text: {}, note: "" });
  });

  it("follow-up text alone is worth keeping in storage, and comes back after a reload", () => {
    const { m, s } = fakeStore();
    saveUnsent(REF, cardUnsent("3", { values: {}, text: {}, note: "", need: "", followup: "two lines\nof follow-up" }), s);
    expect(m.size).toBe(1);
    forgetMemory();
    expect(loadUnsent(REF, s)?.followup).toBe("two lines\nof follow-up");
  });

  it("a stored copy whose follow-up is not text is refused", () => {
    const { m, s } = fakeStore();
    m.set(`askclient.unsent.${REF}`, JSON.stringify({ revision: "3", values: {}, text: {}, note: "", followup: 5 }));
    expect(loadUnsent(REF, s)).toBeUndefined();
  });

  it("a withdrawn ask's kept lines include the follow-up text", () => {
    expect(keptDraftLines(open, cardUnsent("3", { values: {}, text: {}, note: "", need: "", followup: "why NO?" }))).toEqual(["Follow-up: why NO?"]);
  });

  it("App's one snapshot holds the follow-up text", () => {
    expect(src("App.tsx")).toMatch(/const snap = \(\) => cardUnsent\(revision, \{ values, text, note, need: needText, (?:needKind, )?followup: followText(?:, followKind, followFork, followAttach: attachPicks)? \}\);/);
  });
});

describe("MUST-FIX-1 by adoption (delta SHOULD-A/B): the card at N+1 adopts the copy left at N only after this follow-up", () => {
  const F = (n: number, text: string) => fence({ n, at: "2026-10-30T12:00:00.000Z", by: "operator", kind: "question", text, delivery: "pending" });
  const afterFollowup = (text = "why NO?") => stored(head("open", 4, "revisions: 4@2026-10-30T12:00:00.000Z:followup 1\n") + BODY + F(1, text));
  const copyAt3 = (followup = "why NO?") => cardUnsent("3", { values: { GO: ["NO"] }, text: {}, note: "", need: "", followup, followKind: "first", followFork: "GO", followAttach: true });

  it("followupBumpOf reads the revisions tail only when it names the current revision", () => {
    expect(followupBumpOf(afterFollowup())).toEqual({ from: "3", n: 1, text: "why NO?" });
    // A later bump that wrote no revisions entry (forward, act) leaves an older tail: not a follow-up bump.
    expect(followupBumpOf(stored(head("open", 5, "revisions: 4@2026-10-30T12:00:00.000Z:followup 1\n") + BODY + F(1, "why NO?")))).toBeUndefined();
    expect(followupBumpOf(stored(head("open", 4, "revisions: 2@x:followup 1 ; 4@2026-10-30T12:00:00.000Z:body\n") + BODY))).toBeUndefined();
    expect(followupBumpOf(open)).toBeUndefined();
  });

  it("adopts the copy one behind, dropping the follow-up it sent with its kind, fork and attach box", () => {
    expect(adoptAfterFollowup(copyAt3(), afterFollowup())).toEqual({ revision: "4", values: { GO: ["NO"] }, text: {}, note: "" });
    // Different text was not this follow-up: it is kept, at the new revision, with its settings.
    expect(adoptAfterFollowup(copyAt3("another thing"), afterFollowup())).toMatchObject({ revision: "4", followup: "another thing", followKind: "first" });
  });

  it("does not adopt two behind, or a copy already current, or nothing", () => {
    const two = cardUnsent("2", { values: { GO: ["NO"] }, text: {}, note: "", need: "" });
    expect(adoptAfterFollowup(two, afterFollowup())).toBe(two);
    const cur = cardUnsent("4", { values: { GO: ["NO"] }, text: {}, note: "", need: "" });
    expect(adoptAfterFollowup(cur, afterFollowup())).toBe(cur);
    expect(adoptAfterFollowup(undefined, afterFollowup())).toBeUndefined();
  });

  it("case 1, the connection drops mid-push after the write: the copy left at N (with the sent text) comes back at N+1 with picks and without the text", async () => {
    saveUnsent(REF, copyAt3());
    const h = await render(afterFollowup());
    expect(h).not.toContain("The ask changed under you");
    expect(h.match(/class="optwrap on/g)).toHaveLength(1);
    expect(h).not.toContain("why NO?</textarea>");
    expect(h).not.toMatch(/aria-controls="followup-f1"[^>]*aria-expanded="true"|aria-expanded="true"[^>]*aria-controls="followup-f1"/);
  });

  it("case 2, a revise lands before the click and the post gets a stale 409: the card at N+1 does not adopt, says the ask changed, and keeps the text", async () => {
    saveUnsent(REF, copyAt3());
    const revised = stored(head("open", 4, "revisions: 4@2026-10-30T12:00:00.000Z:body\n") + BODY);
    rememberFollowupResult(REF, ["3", "4"], "Not sent: the ask changed (now revision 4). Re-read it, then send again.");
    const h = await render(revised);
    expect(h).toContain("The ask changed under you");
    expect(h).toContain("why NO?</textarea>");
    expect(h).toContain("Not sent: the ask changed (now revision 4). Re-read it, then send again.");
    expect(h).not.toContain(FOLLOWUP_PENDING);
  });

  it("case 3, no false line: the pending words never claim a write", () => {
    expect(FOLLOWUP_PENDING).toBe("Sending the follow-up to the asker…");
    expect(FOLLOWUP_PENDING).not.toMatch(/written|file/);
  });

  it("keepsOver: a card never writes its copy over one a newer card saved", () => {
    expect(keepsOver(undefined, "3")).toBe(true);
    expect(keepsOver(cardUnsent("3", { values: {}, text: {}, note: "", need: "" }), "3")).toBe(true);
    expect(keepsOver(cardUnsent("2", { values: {}, text: {}, note: "", need: "" }), "3")).toBe(true);
    expect(keepsOver(cardUnsent("4", { values: {}, text: {}, note: "", need: "" }), "3")).toBe(false);
  });

  it("the result store: a line for several revisions, a subscription, a forget", () => {
    const seen: number[] = [];
    const off = subscribeFollowupResults(() => seen.push(1));
    rememberFollowupResult(REF, ["3", 4], "x");
    expect(followupResultFor(REF, "3")).toBe("x");
    expect(followupResultFor(REF, "4")).toBe("x");
    expect(followupResultFor(REF, "5")).toBeUndefined();
    forgetFollowupResult(REF);
    expect(followupResultFor(REF, "4")).toBeUndefined();
    expect(seen.length).toBe(2);
    off();
  });

  it("App: nothing is re-based before the post; every outcome is said for N and N+1; keep is guarded; the card adopts", () => {
    const app = src("App.tsx");
    const fn = app.slice(app.indexOf("async function sendFollowup("), app.indexOf("async function sendFollowup(") + 2600);
    expect(app).toContain("async function sendFollowup(");
    expect(app).not.toContain("rebaseAfterFollowup(");
    expect(fn).toContain("const say = (t: string) => {\n      setResult(t);\n      rememberFollowupResult(ref, [revision, next], t);\n    };");
    expect(fn).toContain("const keep = () => {\n      if (keepsOver(loadUnsent(keyFor(false)), revision)) saveUnsent(keyFor(false), snap());\n    };");
    expect(fn.indexOf("say(FOLLOWUP_PENDING);")).toBeLessThan(fn.indexOf('post("/api/followup"'));
    expect(fn).toMatch(/if \(r\.restarted\) \{\s*keep\(\);\s*return say\(/);
    expect(fn).toMatch(/if \(r\.status === 409\) \{\s*keep\(\);\s*const step = followupConflict\(r\.json, keyFor\(false\), unsentKey\(ref, false\)\);\s*rememberFollowupResult\(ref, \[revision, next\], step\.text\);\s*return applyConflict\(step, conflictDeps\);/);
    expect(fn).toMatch(/if \(!out\.sent\) \{\s*keep\(\);\s*return say\(out\.text\);/);
    expect(fn).toMatch(/catch \(e\) \{\s*keep\(\);\s*say\(/);
    expect(app).toContain("const [openKept] = useState(() => (open ? adoptAfterFollowup(loadUnsent(ref), ask) : undefined));");
    expect(app).toContain("restoreUnsent(init, openKept, revision, keys)");
    expect(app).toContain("const [keptCopy] = useState(() => (followable ? openKept : undefined));");
  });

  it("App: the card reads the result store by subscription", () => {
    const app = src("App.tsx");
    expect(app).toContain("const readFollowResult = () => followupResultFor(ref, revision);");
    expect(app).toContain("const followResult = useSyncExternalStore(subscribeFollowupResults, readFollowResult, readFollowResult);");
  });
});

describe("SHOULD-C and NIT-A: the fork follows the focus when the panel opens blank; inputs wait for the send", () => {
  it("forkOnOpen: blank text takes the focused fork, typed text keeps its fork", () => {
    expect(forkOnOpen("", "WHEN", "GO")).toBe("WHEN");
    expect(forkOnOpen("  ", undefined, "GO")).toBe("");
    expect(forkOnOpen("why?", "WHEN", "GO")).toBe("GO");
  });
  it("App: the toggle opens through forkOnOpen with the current focus", () => {
    const app = src("App.tsx");
    expect(app).toContain("if (!followOpen) setFollowFork(forkOnOpen(followText, focused === undefined ? undefined : keys[focused], followFork));");
  });
  it("the follow-up inputs are disabled while a send is in flight", () => {
    const app = src("App.tsx");
    const panel = app.slice(app.indexOf('<div className="need followup"'), app.indexOf('<div className="need followup"') + 3000);
    expect(panel.match(/disabled=\{busy\}/g)?.length).toBeGreaterThanOrEqual(3); // radios, select, textarea
    expect(panel).toContain("disabled={busy || nothing}");
  });
});

describe("SHOULD-2: the follow-up starts from the question you are on, with your picks, and keeps its settings", () => {
  it("cardUnsent keeps kind, fork and the attach box beside the text, and none of them without it", () => {
    expect(cardUnsent("3", { values: {}, text: {}, note: "", need: "", followup: "why?", followKind: "first", followFork: "WHEN", followAttach: false })).toEqual({
      revision: "3", values: {}, text: {}, note: "", followup: "why?", followKind: "first", followFork: "WHEN", followAttach: false,
    });
    expect(cardUnsent("3", { values: {}, text: {}, note: "", need: "", followup: " ", followKind: "first", followFork: "WHEN", followAttach: false })).toEqual({ revision: "3", values: {}, text: {}, note: "" });
  });

  it("a remount brings back Do this first, the fork and an unticked attach box", async () => {
    saveUnsent(REF, cardUnsent("3", { values: { GO: ["YES"] }, text: {}, note: "", need: "", followup: "check the bill", followKind: "first", followFork: "WHEN", followAttach: false }));
    const h = await render(open);
    expect(h).toMatch(/<input type="radio"(?=[^>]*value="first")(?=[^>]*checked="")[^>]*>/);
    expect(h).toContain('<option value="WHEN" selected="">WHEN: When?</option>');
    expect(h).toMatch(/<input type="checkbox"(?![^>]*checked="")[^>]*>/);
  });

  it("with no kept copy, the fork is the focused one and the picks are attached by default", async () => {
    saveUnsent(REF, cardUnsent("3", { values: { GO: ["YES"] }, text: {}, note: "", need: "", followup: "x" }));
    const { AskDetail } = await import("../src/client/App.tsx");
    const h = renderToStaticMarkup(createElement(AskDetail, { ask: open, all: [open], onChanged: () => {}, onSent: () => {}, focusFork: "q2" }));
    expect(h).toContain('<option value="WHEN" selected="">WHEN: When?</option>');
    expect(h).toMatch(/<input type="checkbox"(?=[^>]*checked="")(?![^>]*disabled="")[^>]*>/);
  });
});
