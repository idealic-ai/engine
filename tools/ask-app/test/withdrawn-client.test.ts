/**
 * ASKWITHDRAWN-UI, the client half of `engine ask withdraw` (meta:engine's server commit 53670c0):
 * a withdrawn ask reads as withdrawn (who, when, why), is never under Open, offers no answer controls,
 * a 409 or a send refusal says "withdrawn by X: reason" rather than a generic error, and the operator's
 * unsent picks and notes on it are kept and shown rather than dropped without a word.
 */
import { afterEach, describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { parseAskFile } from "../src/lib/format.ts";
import { askRow, rowInFilter } from "../src/client/model.ts";
import { changeMode, mayChangeAnswer } from "../src/client/reanswer.ts";
import { conflictMessage, refusalWords, withdrawnInfo, withdrawnWords } from "../src/client/supersede.ts";
import { sendOutcome } from "../src/client/next.ts";
import { sendProvisional } from "../src/client/loop.ts";
import { clearUnsent, forgetMemory, keptDraftLines, saveUnsent } from "../src/client/unsent.ts";

const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes, ship\n- [ ] [NO] No, hold\n";
const head = (extra = "", status = "withdrawn") =>
  `---\nid: w1\nto: operator\nfrom: idealic:kernel\nstatus: ${status}\nrevision: 5\ncreated: 2026-10-30T10:00:00.000Z\n${extra}---\n\n`;
const W = "withdrawn-at: 2026-10-30T16:20:00.000Z\nwithdrawn-actor: idealic:kernel\nwithdrawn-reason: moot: the kernel shipped the other way\n";
const stored = (text: string) => ({ ...parseAskFile(text), seat: "idealic:kernel", file: "/x.md", mtimeMs: 0 });
const withdrawn = stored(head(W) + BODY);
const withdrawnDraft = stored(head(W + "withdrawn-draft-of: operator\n") + BODY);
const bare = stored(head() + BODY);
const open = stored(head("", "open") + BODY);
/** As /api/answer and /api/draft send it (server.ts in 53670c0). */
const C409 = { error: "ask w1 is withdrawn by idealic:kernel (moot: the kernel shipped the other way): there is nothing to answer", status: "withdrawn", withdrawnBy: "idealic:kernel", withdrawnAt: "2026-10-30T16:20:00.000Z", withdrawnReason: "moot: the kernel shipped the other way" };
/** As sendBatch puts it in refused[]: WithdrawnError's message, nothing structured. */
const REFUSED = { ref: "idealic:kernel/w1", error: C409.error };

async function render(ask: ReturnType<typeof stored>, extra: Record<string, unknown> = {}) {
  const { AskDetail } = await import("../src/client/App.tsx");
  return renderToStaticMarkup(createElement(AskDetail, { ask, all: [ask], onChanged: () => {}, onSent: () => {}, ...extra }));
}

afterEach(() => {
  clearUnsent("idealic:kernel/w1");
  forgetMemory();
});

describe("the withdrawal as the client reads it", () => {
  it("withdrawnInfo reads who, when, why and whose draft was discarded; undefined on any other status", () => {
    expect(withdrawnInfo(withdrawn.header)).toEqual({ actor: "idealic:kernel", at: "2026-10-30T16:20:00.000Z", reason: "moot: the kernel shipped the other way" });
    expect(withdrawnInfo(withdrawnDraft.header)?.draftOf).toBe("operator");
    expect(withdrawnInfo(bare.header)).toEqual({});
    expect(withdrawnInfo(open.header)).toBeUndefined();
  });

  it("withdrawnWords says 'withdrawn by X: reason', and leaves out what is missing", () => {
    expect(withdrawnWords({ actor: "idealic:kernel", reason: "moot" })).toBe("withdrawn by idealic:kernel: moot");
    expect(withdrawnWords({ actor: "idealic:kernel" })).toBe("withdrawn by idealic:kernel");
    expect(withdrawnWords({ reason: "moot" })).toBe("withdrawn: moot");
    expect(withdrawnWords({})).toBe("withdrawn");
  });
});

describe("a withdrawn ask is never under Open", () => {
  it("is in All only, even if a stale row still says a draft was sent", () => {
    const row = askRow(withdrawn);
    expect(row.status).toBe("withdrawn");
    expect(row.waitingOnYou).toBe(false);
    for (const f of ["open", "settled", "ruled"] as const) expect(rowInFilter(row, f)).toBe(false);
    expect(rowInFilter(row, "all")).toBe(true);
    // A row built before the withdrawal discarded the draft: still never Open.
    expect(rowInFilter({ ...row, draftSent: true }, "open")).toBe(false);
    expect(rowInFilter({ ...row, draftSent: true }, "all")).toBe(true);
  });

  it("offers neither Change answer nor Overrule", () => {
    expect(changeMode(withdrawn)).toBeUndefined();
    expect(mayChangeAnswer(withdrawn)).toBe(false);
    // Even with an answer block left in the file, a withdrawn ask is not reopened.
    const odd = stored(head(W) + BODY + "\n```json answer\n" + JSON.stringify({ answers: { GO: ["YES"] }, answeredBy: "manager:idealic", revision: 4 }) + "\n```\n");
    expect(changeMode(odd)).toBeUndefined();
  });
});

describe("a refusal says who withdrew it and why", () => {
  it("a 409 from /api/answer or /api/draft is a withdrawal notice, never a revision conflict", () => {
    const c = conflictMessage(C409);
    expect(c.text).toBe("Not saved: this ask was withdrawn by idealic:kernel: moot: the kernel shipped the other way. There is nothing to answer; your picks and notes are kept in this browser.");
    expect(c.withdrawn).toEqual({ actor: "idealic:kernel", at: "2026-10-30T16:20:00.000Z", reason: "moot: the kernel shipped the other way" });
    expect(c.supersededBy).toBeUndefined();
    expect(c.text).not.toMatch(/revision|moved/);
    // The ordinary conflict is unchanged.
    expect(conflictMessage({ revision: 6 }).withdrawn).toBeUndefined();
  });

  it("refusalWords reads WithdrawnError's message, a reason with parentheses and colons included", () => {
    expect(refusalWords(C409.error)).toEqual({ actor: "idealic:kernel", reason: "moot: the kernel shipped the other way" });
    expect(refusalWords("ask w1 is withdrawn by idealic:kernel (moot (see IDE-1)): there is nothing to answer")).toEqual({ actor: "idealic:kernel", reason: "moot (see IDE-1)" });
    expect(refusalWords("ask w1 is withdrawn: there is nothing to answer")).toEqual({});
    expect(refusalWords("idealic:kernel/w1 has no draft to send")).toBeUndefined();
    expect(refusalWords("ask w1 is superseded by x/y")).toBeUndefined();
  });

  it("a send whose ask is in refused[] says it was withdrawn, keeps the copy and does not move on", () => {
    const out = sendOutcome(200, { refused: [REFUSED], pushes: [] });
    expect(out.sent).toBe(false);
    expect(out.text).toBe("Not sent: this ask was withdrawn by idealic:kernel: moot: the kernel shipped the other way. There is nothing to answer; your picks and notes are kept in this browser.");
    expect(out.text).not.toMatch(/^Refused|Error/);
    // Any other refusal reads as before.
    expect(sendOutcome(200, { refused: [{ ref: "a/b", error: "a/b has no draft to send" }] }).text).toBe("Refused: a/b has no draft to send");
  });

  it("Send as draft on a withdrawn ask says withdrawn, not 'the ask moved'", async () => {
    const post = async () => ({ status: 409, json: C409 });
    const out = await sendProvisional(post as never, async () => undefined, { seat: "idealic:kernel", id: "w1", expectedRevision: 4, answers: { GO: ["YES"] }, note: "" });
    expect(out.ok).toBe(false);
    expect(out.message).toMatch(/^Not sent: this ask was withdrawn by idealic:kernel: moot/);
    expect(out.withdrawn).toBe(true);
  });

  it("Send batch names each withdrawn ask in its own words", async () => {
    const { refusedLine } = await import("../src/client/supersede.ts");
    expect(refusedLine(REFUSED)).toBe("idealic:kernel/w1: withdrawn by idealic:kernel: moot: the kernel shipped the other way");
    expect(refusedLine({ ref: "a/b", error: "stale" })).toBe("a/b: stale");
  });
});

describe("the withdrawn card", () => {
  it("shows the withdrawn chip with who, when and why, and no answer controls", async () => {
    const html = await render(withdrawn);
    expect(html).toContain('class="superseded withdrawn"');
    expect(html).toContain("<b>Withdrawn</b> by idealic:kernel");
    expect(html).toContain('dateTime="2026-10-30T16:20:00.000Z"');
    expect(html).toContain(": moot: the kernel shipped the other way");
    expect(html).toContain("nothing to answer");
    for (const word of [">Send", "Send as draft", "Save draft", "Need something first", "Draft a decline", ">Overrule<", ">Change answer<", "Note to the asker"]) expect(html).not.toContain(word);
    // Not misread as an answered ask.
    expect(html).not.toMatch(/<h3>Answered/);
    expect(html).toMatch(/<h3>Withdrawn · revision 5<\/h3>/);
    // The forks are read-only: every input and textarea is disabled.
    expect(html).not.toMatch(/<(?:textarea|input)(?![^>]*disabled)[^>]*>/i);
  });

  it("an open card still has its controls (the control for the test above)", async () => {
    const html = await render(open);
    expect(html).toContain("Note to the asker");
    expect(html).toContain("Send as draft");
    expect(html).not.toContain("superseded withdrawn");
  });

  it("the operator's unsent picks and notes on it are shown as kept, never dropped without a word", async () => {
    saveUnsent("idealic:kernel/w1", { revision: "4", values: { GO: "YES" }, text: { GO: "because the kernel needs it" }, note: "ship today" });
    const html = await render(withdrawn);
    expect(html).toContain("You were answering this ask when it was withdrawn");
    expect(html).toContain("Nothing was sent");
    expect(html).toContain("GO: YES; because the kernel needs it");
    expect(html).toContain("Note: ship today");
    expect(html).toContain(">Copy<");
    expect(html).toContain(">Forget them<");
  });

  it("with no unsent copy, a saved draft the withdrawal discarded is still named", async () => {
    const html = await render(withdrawnDraft);
    expect(html).toContain("Your saved draft on this ask was discarded when it was withdrawn");
    expect(html).not.toContain("You were answering this ask");
    // Someone else's discarded draft is not the operator's news.
    const seat = await render(stored(head(W + "withdrawn-draft-of: manager:idealic\n") + BODY));
    expect(seat).not.toContain("Your saved draft");
  });

  it("keptDraftLines lists each fork's picks and text by its name, then the note", () => {
    expect(keptDraftLines(withdrawn, { revision: "4", values: { GO: ["YES", "NO"] }, text: { GO: "and more" }, note: "n" })).toEqual(["GO: YES, NO; and more", "Note: n"]);
    expect(keptDraftLines(withdrawn, { revision: "4", values: {}, text: { GO: "  " }, note: "" })).toEqual([]);
  });

  it("the sidebar row says withdrawn, not 'N of M left'", async () => {
    const { AskRowButton } = await import("../src/client/App.tsx");
    const html = renderToStaticMarkup(createElement(AskRowButton, { r: askRow(withdrawn), current: false, onPick: () => {}, slim: false }));
    expect(html).toContain("withdrawn by idealic:kernel");
    expect(html).not.toMatch(/of \d+ left/);
  });
});
