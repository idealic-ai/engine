/**
 * `engine ask withdraw` (ASKWITHDRAW): the asker takes a question back. Distinct from supersede: no
 * newer ask replaces it, so nothing is left to answer and nobody is asked to confirm anything (the
 * operator, 2026-10-30: withdrawals left "confirm withdrawal" asks in the queue).
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { answerAsk, listAsks, newAsk, readAsk, renameSeat, saveDraft, sendBatch, supersedeAsk, withdrawAsk } from "../src/lib/store.ts";
import { assertLive, parseAskFile, WithdrawnError } from "../src/lib/format.ts";
import { SEAT_FIELDS } from "../src/lib/rename-seat.ts";
import { askRow, rowInFilter } from "../src/client/model.ts";
import { conflictMessage, withdrawnInfo } from "../src/client/supersede.ts";

let root: string;
beforeEach(() => {
  const base = fs.mkdtempSync(path.join("/tmp", "asks-wd-"));
  root = path.join(base, "asks");
  pushes.length = 0;
});
afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));

const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n";
const ASKER = "idealic:kernel";
const HOLDER = "manager:idealic";
const file = (id: string, seat = ASKER) => path.join(root, seat, `${id}.md`);
const text = (id: string, seat = ASKER) => fs.readFileSync(file(id, seat), "utf8");
const read = (id: string, seat = ASKER) => parseAskFile(text(id, seat));
const pushes: { seat: string; content: string }[] = [];
const push = async (seat: string, content: string) => {
  pushes.push({ seat, content });
  return { status: "delivered" as const };
};
const REF = { seat: ASKER, id: "w1" };
function ask(id = "w1", extra: Record<string, string> = {}) {
  newAsk(root, { from: ASKER, to: HOLDER, id, ...extra }, BODY);
}
const AT = "2026-10-30T16:20:00.000Z";

describe("withdrawAsk: the asker takes its question back", () => {
  it("stamps status withdrawn with who, when and the reason; the revision moves", async () => {
    ask();
    const r = await withdrawAsk(root, REF, { by: ASKER, reason: "the ticket was closed", now: AT, push });
    const h = read("w1").header;
    expect(h.status).toBe("withdrawn");
    expect(h["withdrawn-actor"]).toBe(ASKER);
    expect(h["withdrawn-at"]).toBe(AT);
    expect(h["withdrawn-reason"]).toBe("the ticket was closed");
    expect(h.revision).toBe("2");
    expect(h.revisions).toBe(`2@${AT}:withdrawn`);
    expect(r.revision).toBe(2);
    // It is not a supersede: nothing names a replacement.
    expect(h["superseded-by"]).toBeUndefined();
  });

  it("a multi-line reason is kept on one header line", async () => {
    ask();
    await withdrawAsk(root, REF, { by: ASKER, reason: "first\nsecond", push });
    expect(read("w1").header["withdrawn-reason"]).toBe("first second");
  });

  it("status and reason survive a re-read: listAsks and readAsk see the same", async () => {
    ask();
    await withdrawAsk(root, REF, { by: ASKER, reason: "moot", push });
    const listed = listAsks(root).find((a) => a.header.id === "w1")!;
    expect(listed.header.status).toBe("withdrawn");
    expect(listed.header["withdrawn-reason"]).toBe("moot");
    const r = await readAsk(root, ASKER, "w1", { by: ASKER });
    expect(r.ask.header.status).toBe("withdrawn");
    expect(r.why).toContain("withdrawn");
  });

  it("the holder hears one notice that says no action is needed and asks for no acknowledgement", async () => {
    ask();
    await withdrawAsk(root, REF, { by: ASKER, reason: "moot", push });
    expect(pushes.map((p) => p.seat)).toEqual([HOLDER]);
    const c = pushes[0].content;
    expect(c).toMatch(/^\[ask-withdrawn\] from idealic:kernel via ask-app: idealic:kernel\/w1 is withdrawn: moot/);
    expect(c).toContain("No action needed");
    expect(c).toMatch(/do not acknowledge/i);
    expect(c).toContain(file("w1"));
  });

  it("when the operator withdraws, the holder and the asker both hear it; the operator is never pushed", async () => {
    ask("w1", { to: "operator" } as never);
    newAsk(root, { from: ASKER, to: HOLDER, id: "w2" }, BODY);
    await withdrawAsk(root, { seat: ASKER, id: "w2" }, { by: "operator", reason: "moot", push });
    expect(pushes.map((p) => p.seat)).toEqual([HOLDER, ASKER]);
    pushes.length = 0;
    await withdrawAsk(root, REF, { by: ASKER, reason: "moot", push });
    expect(pushes).toEqual([]);
  });

  it("a saved draft is discarded, and the withdrawal records whose it was", async () => {
    ask();
    await saveDraft(root, ASKER, "w1", { answers: { GO: ["YES"] }, answeredBy: HOLDER }, 1);
    await withdrawAsk(root, REF, { by: ASKER, reason: "moot", push });
    expect(text("w1")).not.toContain("```json draft");
    expect(read("w1").draft).toBeUndefined();
    expect(read("w1").header["withdrawn-draft-of"]).toBe(HOLDER);
    expect(pushes[0].content).toContain(`A draft saved by ${HOLDER} on it was discarded`);
  });

  it("with no draft, no draft field is written", async () => {
    ask();
    await withdrawAsk(root, REF, { by: ASKER, reason: "moot", push });
    expect(read("w1").header["withdrawn-draft-of"]).toBeUndefined();
  });
});

describe("withdrawAsk: who may withdraw (the supersede set; pending an operator WHO ruling)", () => {
  it("the asker, its manager (FLEET_MANAGES) and the operator may", async () => {
    ask("a");
    ask("m");
    ask("o", { "reserved-for": "operator" });
    await withdrawAsk(root, { seat: ASKER, id: "a" }, { by: ASKER, reason: "r", push });
    await withdrawAsk(root, { seat: ASKER, id: "m" }, { by: "manager:idealic", manages: ["kernel"], reason: "r", push });
    await withdrawAsk(root, { seat: ASKER, id: "o" }, { by: "operator", reason: "r", push });
    expect(["a", "m", "o"].map((id) => read(id).header["withdrawn-actor"])).toEqual([ASKER, "manager:idealic", "operator"]);
  });

  it("a peer, and the holder that does not manage the asker, are refused and nothing is written", async () => {
    ask();
    const before = text("w1");
    await expect(withdrawAsk(root, REF, { by: "idealic:runner", reason: "r", push })).rejects.toThrow(/only the asker \(idealic:kernel\), its manager or the operator withdraws/);
    await expect(withdrawAsk(root, REF, { by: HOLDER, manages: ["runner"], reason: "r", push })).rejects.toThrow(/only the asker/);
    expect(text("w1")).toBe(before);
    expect(pushes).toEqual([]);
  });
});

describe("withdrawAsk: refusals", () => {
  it("refuses with no actor, no reason or a blank reason", async () => {
    ask();
    await expect(withdrawAsk(root, REF, { by: "", reason: "r", push })).rejects.toThrow(/must name who/);
    await expect(withdrawAsk(root, REF, { by: ASKER, reason: "  ", push })).rejects.toThrow(/needs a reason/);
    await expect(withdrawAsk(root, REF, { by: ASKER, reason: undefined as never, push })).rejects.toThrow(/needs a reason/);
    expect(read("w1").header.status).toBe("open");
  });

  it("refuses a missing ask", async () => {
    await expect(withdrawAsk(root, { seat: ASKER, id: "nope" }, { by: ASKER, reason: "r", push })).rejects.toThrow(/no ask idealic:kernel\/nope/);
  });

  it("refuses an answered ask: that one is history; its answer and history fences are untouched", async () => {
    newAsk(root, { from: ASKER, to: HOLDER, id: "h1" }, BODY);
    // IDE-339: a seat's answer, overruled by the operator, is kept in the history fence.
    await answerAsk(root, ASKER, "h1", { answers: { GO: ["YES"] }, answeredBy: HOLDER }, { expectedRevision: 1, push: async () => ({ status: "delivered" }) } as never);
    await answerAsk(root, ASKER, "h1", { answers: { GO: ["NO"] }, answeredBy: "operator" }, { expectedRevision: 2, push: async () => ({ status: "delivered" }) } as never);
    const before = text("h1");
    expect(before).toContain("```json history");
    expect(before).toContain("overruled: manager:idealic");
    await expect(withdrawAsk(root, { seat: ASKER, id: "h1" }, { by: ASKER, reason: "r", push })).rejects.toThrow(/is answered: that one is history/);
    expect(text("h1")).toBe(before);
  });

  it("refuses a declined ask as history", async () => {
    ask();
    await answerAsk(root, ASKER, "w1", { declined: true, reason: "no", answeredBy: "operator" }, { expectedRevision: 1, push: async () => ({ status: "delivered" }) } as never);
    await expect(withdrawAsk(root, REF, { by: ASKER, reason: "r", push })).rejects.toThrow(/is declined: that one is history/);
  });

  it("refuses an already superseded ask, naming its replacement", async () => {
    ask("old");
    ask("new");
    await supersedeAsk(root, { seat: ASKER, id: "old" }, { seat: ASKER, id: "new" }, { by: ASKER, push });
    await expect(withdrawAsk(root, { seat: ASKER, id: "old" }, { by: ASKER, reason: "r", push })).rejects.toThrow(/already superseded by idealic:kernel\/new/);
  });

  it("refuses an already withdrawn ask", async () => {
    ask();
    await withdrawAsk(root, REF, { by: ASKER, reason: "first", push });
    await expect(withdrawAsk(root, REF, { by: ASKER, reason: "again", push })).rejects.toThrow(/already withdrawn by idealic:kernel/);
    expect(read("w1").header["withdrawn-reason"]).toBe("first");
  });

  it("a withdrawn ask is not a replacement for supersede", async () => {
    ask("old");
    ask("gone");
    await withdrawAsk(root, { seat: ASKER, id: "gone" }, { by: ASKER, reason: "r", push });
    await expect(supersedeAsk(root, { seat: ASKER, id: "old" }, { seat: ASKER, id: "gone" }, { by: ASKER, push })).rejects.toThrow(/withdrawn/);
    expect(read("old").header.status).toBe("open");
  });
});

describe("a withdrawn ask takes no answer, draft or send", () => {
  async function withdrawn() {
    ask();
    await saveDraft(root, ASKER, "w1", { answers: { GO: ["YES"] }, answeredBy: HOLDER }, 1);
    await withdrawAsk(root, REF, { by: ASKER, reason: "moot", push });
  }

  it("assertLive throws a WithdrawnError carrying who and why", () => {
    const a = parseAskFile(BODY.replace(/^/, "---\nid: x\nstatus: withdrawn\nwithdrawn-actor: idealic:kernel\nwithdrawn-reason: moot\n---\n"));
    try {
      assertLive(a);
      throw new Error("did not throw");
    } catch (e) {
      expect(e).toBeInstanceOf(WithdrawnError);
      expect((e as WithdrawnError).actor).toBe("idealic:kernel");
      expect((e as WithdrawnError).reason).toBe("moot");
      expect((e as Error).message).toBe("ask x is withdrawn by idealic:kernel (moot): there is nothing to answer");
    }
  });

  it("an answer after withdraw is refused, at the old revision or the new one", async () => {
    await withdrawn();
    for (const rev of [1, 2]) {
      await expect(answerAsk(root, ASKER, "w1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { expectedRevision: rev, push } as never)).rejects.toThrow(WithdrawnError);
    }
    await expect(answerAsk(root, ASKER, "w1", { declined: true, reason: "no", answeredBy: "operator" }, { expectedRevision: 2, push } as never)).rejects.toThrow(/withdrawn/);
    expect(read("w1").header.status).toBe("withdrawn");
  });

  it("a draft is refused", async () => {
    await withdrawn();
    await expect(saveDraft(root, ASKER, "w1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, 2)).rejects.toThrow(WithdrawnError);
  });

  it("a batch send naming it is refused", async () => {
    await withdrawn();
    const r = await sendBatch(root, [`${ASKER}/w1`], { by: HOLDER, push });
    expect(r.settled).toEqual([]);
    expect(r.refused).toEqual([{ ref: `${ASKER}/w1`, error: "ask w1 is withdrawn by idealic:kernel (moot): there is nothing to answer" }]);
    expect(read("w1").header.status).toBe("withdrawn");
  });
});

describe("the operator's lists", () => {
  it("a withdrawn ask is in All only: not Open, not Settled, not Ruled", async () => {
    ask();
    await withdrawAsk(root, REF, { by: ASKER, reason: "moot", push });
    const row = askRow(listAsks(root)[0]);
    expect(row.status).toBe("withdrawn");
    expect(row.waitingOnYou).toBe(false);
    for (const f of ["open", "settled", "ruled"] as const) expect(rowInFilter(row, f)).toBe(false);
    expect(rowInFilter(row, "all")).toBe(true);
  });

  it("the client reads who withdrew it and why; a 409 says there is nothing to answer", () => {
    const a = parseAskFile("---\nid: x\nstatus: withdrawn\nwithdrawn-actor: idealic:kernel\nwithdrawn-at: 2026-10-30T16:20:00.000Z\nwithdrawn-reason: moot\n---\n" + BODY);
    expect(withdrawnInfo(a.header)).toEqual({ actor: "idealic:kernel", at: "2026-10-30T16:20:00.000Z", reason: "moot" });
    expect(withdrawnInfo(parseAskFile("---\nid: x\nstatus: open\n---\n" + BODY).header)).toBeUndefined();
    const c = conflictMessage({ status: "withdrawn", withdrawnBy: "idealic:kernel", withdrawnReason: "moot" } as never);
    expect(c.text).toBe("This ask was withdrawn by idealic:kernel (moot). There is nothing to answer; your picks are kept here.");
    expect(c.withdrawn).toBe(true);
  });
});

describe("rename-seat rewrites the withdrawal's seat fields", () => {
  it("withdrawn-actor and withdrawn-draft-of are seat fields", async () => {
    expect(SEAT_FIELDS).toContain("withdrawn-actor");
    expect(SEAT_FIELDS).toContain("withdrawn-draft-of");
    ask();
    await saveDraft(root, ASKER, "w1", { answers: { GO: ["YES"] }, answeredBy: HOLDER }, 1);
    await withdrawAsk(root, REF, { by: ASKER, reason: "moot", push });
    await renameSeat(root, HOLDER, "manager:kit", { by: "operator" });
    await renameSeat(root, ASKER, "idealic:core", { by: "operator" });
    const h = parseAskFile(fs.readFileSync(path.join(root, "idealic:core", "w1.md"), "utf8")).header;
    expect(h["withdrawn-actor"]).toBe("idealic:core");
    expect(h["withdrawn-draft-of"]).toBe("manager:kit");
    expect(h.status).toBe("withdrawn");
  });
});
