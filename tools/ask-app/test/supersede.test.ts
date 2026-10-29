/**
 * `engine ask supersede`: one ask replaces another, so a re-filed copy and its original can never
 * both be answered (IDE-261: the copy was answered DONE and the original later got a different
 * answer, and the ticket flip-flopped).
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { answerAsk, forwardAsk, listAsks, newAsk, saveDraft, sendBatch, supersedeAsk } from "../src/lib/store.ts";
import { parseAskFile, SupersededError, writeAnswer, writeDraft } from "../src/lib/format.ts";

let root: string;
beforeEach(() => {
  const base = fs.mkdtempSync(path.join("/tmp", "asks-sup-"));
  root = path.join(base, "asks");
});
afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));

const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n";
const ASKER = "idealic:kernel";
const file = (seat: string, id: string) => path.join(root, seat, `${id}.md`);
const read = (seat: string, id: string) => parseAskFile(fs.readFileSync(file(seat, id), "utf8"));
const pushes: { seat: string; content: string }[] = [];
const push = async (seat: string, content: string) => {
  pushes.push({ seat, content });
  return { status: "delivered" as const };
};
function pair(extra: Record<string, string> = {}) {
  newAsk(root, { from: ASKER, to: "manager:idealic", id: "old", ...extra }, BODY);
  newAsk(root, { from: ASKER, to: "manager:idealic", id: "new" }, BODY);
}
const OLD = { seat: ASKER, id: "old" };
const NEW = { seat: ASKER, id: "new" };

describe("supersedeAsk: the happy path", () => {
  beforeEach(() => (pushes.length = 0));

  it("marks the old ask superseded with a pointer and a time, and the new ask points back", async () => {
    pair();
    await supersedeAsk(root, OLD, NEW, { by: ASKER, now: "2026-10-30T01:00:00.000Z", push });
    const old = read(ASKER, "old");
    expect(old.header.status).toBe("superseded");
    expect(old.header["superseded-by"]).toBe(`${ASKER}/new`);
    expect(old.header["superseded-at"]).toBe("2026-10-30T01:00:00.000Z");
    expect(old.header["superseded-actor"]).toBe(ASKER);
    // revise's rule: the revision moves and `revisions:` records what changed.
    expect(old.header.revision).toBe("2");
    expect(old.header.revisions).toBe("2@2026-10-30T01:00:00.000Z:superseded");
    const neu = read(ASKER, "new");
    expect(neu.header.supersedes).toBe(`${ASKER}/old`);
    expect(neu.header.status).toBe("open");
    // The new ask's question did not change, so its revision does not move.
    expect(neu.header.revision).toBe("1");
  });

  it("works across seats, and the holder of the old ask hears one notice naming the new ask", async () => {
    newAsk(root, { from: ASKER, to: "manager:idealic", id: "old" }, BODY);
    newAsk(root, { from: "manager:idealic", to: "operator", id: "n2" }, BODY);
    await supersedeAsk(root, OLD, { seat: "manager:idealic", id: "n2" }, { by: "operator", push });
    expect(read(ASKER, "old").header["superseded-by"]).toBe("manager:idealic/n2");
    expect(read("manager:idealic", "n2").header.supersedes).toBe(`${ASKER}/old`);
    expect(pushes.map((p) => p.seat)).toEqual(["manager:idealic"]);
    expect(pushes[0].content).toContain("[ask-superseded]");
    expect(pushes[0].content).toContain("manager:idealic/n2");
  });

  it("drops a draft saved on the old ask: it can never be sent", async () => {
    pair();
    await saveDraft(root, ASKER, "old", { answers: { GO: ["YES"] }, answeredBy: "manager:idealic" }, 1);
    await supersedeAsk(root, OLD, NEW, { by: ASKER, push });
    expect(fs.readFileSync(file(ASKER, "old"), "utf8")).not.toContain("```json draft");
    expect(read(ASKER, "old").header.draft).toBeUndefined();
  });

  it("the operator, and a manager of the asker, may supersede; a reserved ask may be superseded", async () => {
    pair({ "reserved-for": "operator" });
    await supersedeAsk(root, OLD, NEW, { by: "manager:idealic", manages: ["kernel"], push });
    expect(read(ASKER, "old").header.status).toBe("superseded");
    newAsk(root, { from: ASKER, to: "manager:idealic", id: "old2" }, BODY);
    await supersedeAsk(root, { seat: ASKER, id: "old2" }, NEW, { by: "operator", push });
    expect(read(ASKER, "old2").header.status).toBe("superseded");
  });

  it("an answered copy may supersede its open original (the IDE-261 clean-up)", async () => {
    pair();
    await answerAsk(root, ASKER, "new", { answers: { GO: ["YES"] }, answeredBy: "manager:idealic" }, { expectedRevision: 1, push });
    await supersedeAsk(root, OLD, NEW, { by: ASKER, push });
    expect(read(ASKER, "old").header.status).toBe("superseded");
    expect(read(ASKER, "new").header.status).toBe("answered");
    expect(read(ASKER, "new").answer?.answers).toEqual({ GO: ["YES"] });
  });
});

describe("supersedeAsk: refusals", () => {
  it("refuses a missing old or new ask, and writes nothing", async () => {
    pair();
    await expect(supersedeAsk(root, { seat: ASKER, id: "nope" }, NEW, { by: ASKER, push })).rejects.toThrow(/no ask idealic:kernel\/nope/);
    await expect(supersedeAsk(root, OLD, { seat: ASKER, id: "nope" }, { by: ASKER, push })).rejects.toThrow(/no ask idealic:kernel\/nope/);
    expect(read(ASKER, "old").header.status).toBe("open");
  });

  it("refuses an ask superseding itself", async () => {
    pair();
    await expect(supersedeAsk(root, OLD, OLD, { by: ASKER, push })).rejects.toThrow(/cannot supersede itself/);
    expect(read(ASKER, "old").header.status).toBe("open");
  });

  it("refuses an answered or declined old ask: answered asks are history", async () => {
    pair();
    await answerAsk(root, ASKER, "old", { answers: { GO: ["NO"] }, answeredBy: "operator" }, { expectedRevision: 1, push });
    await expect(supersedeAsk(root, OLD, NEW, { by: ASKER, push })).rejects.toThrow(/answered asks are history.*file a new one instead/);
    expect(read(ASKER, "old").header.status).toBe("answered");
    expect(read(ASKER, "new").header.supersedes).toBeUndefined();
  });

  it("refuses an old ask that is already superseded, naming what replaced it", async () => {
    pair();
    newAsk(root, { from: ASKER, to: "manager:idealic", id: "third" }, BODY);
    await supersedeAsk(root, OLD, NEW, { by: ASKER, push });
    await expect(supersedeAsk(root, OLD, { seat: ASKER, id: "third" }, { by: ASKER, push })).rejects.toThrow(/already superseded by idealic:kernel\/new/);
  });

  it("refuses a replacement that is itself superseded", async () => {
    pair();
    newAsk(root, { from: ASKER, to: "manager:idealic", id: "third" }, BODY);
    await supersedeAsk(root, NEW, { seat: ASKER, id: "third" }, { by: ASKER, push });
    await expect(supersedeAsk(root, OLD, NEW, { by: ASKER, push })).rejects.toThrow(/idealic:kernel\/new is itself superseded/);
    expect(read(ASKER, "old").header.status).toBe("open");
  });

  it("refuses a seat that is neither the asker nor its manager — even the holder", async () => {
    pair();
    await expect(supersedeAsk(root, OLD, NEW, { by: "manager:idealic", push })).rejects.toThrow(/only the asker \(idealic:kernel\), its manager or the operator/);
    await expect(supersedeAsk(root, OLD, NEW, { by: "app:writer", manages: ["writer", "deploy"], push })).rejects.toThrow(/only the asker/);
    expect(read(ASKER, "old").header.status).toBe("open");
  });

  it("refuses an actor-less call", async () => {
    pair();
    await expect(supersedeAsk(root, OLD, NEW, { by: "", push })).rejects.toThrow(/must name who/);
  });
});

describe("a superseded ask takes no answer, draft or send", () => {
  beforeEach(async () => {
    pair();
    await saveDraft(root, ASKER, "old", { answers: { GO: ["YES"] }, answeredBy: "manager:idealic" }, 1);
    await supersedeAsk(root, OLD, NEW, { by: ASKER, push });
  });

  it("answerAsk is refused with a SupersededError naming the new ask, at any revision", async () => {
    for (const rev of [1, 2]) {
      const p = answerAsk(root, ASKER, "old", { answers: { GO: ["YES"] }, answeredBy: "manager:idealic" }, { expectedRevision: rev, push });
      await expect(p).rejects.toBeInstanceOf(SupersededError);
      await expect(answerAsk(root, ASKER, "old", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { expectedRevision: rev, push })).rejects.toThrow(/superseded by idealic:kernel\/new; answer that one instead/);
    }
    expect(read(ASKER, "old").header.status).toBe("superseded");
  });

  it("a decline is refused too", async () => {
    await expect(answerAsk(root, ASKER, "old", { declined: true, reason: "x", answeredBy: "operator" }, { expectedRevision: 2, push })).rejects.toBeInstanceOf(SupersededError);
  });

  it("saveDraft is refused naming the new ask", async () => {
    await expect(saveDraft(root, ASKER, "old", { answers: { GO: ["YES"] }, answeredBy: "operator" }, 2)).rejects.toThrow(/superseded by idealic:kernel\/new/);
  });

  it("sendBatch refuses the ref naming the new ask, and settles nothing", async () => {
    const out = await sendBatch(root, [`${ASKER}/old`], { by: "manager:idealic", push });
    expect(out.settled).toEqual([]);
    expect(out.refused[0].error).toMatch(/superseded by idealic:kernel\/new/);
  });

  it("the file-level writers refuse it as well (defence below the store)", () => {
    const text = fs.readFileSync(file(ASKER, "old"), "utf8");
    expect(() => writeAnswer(text, { answers: { GO: ["YES"] }, answeredBy: "operator" })).toThrow(SupersededError);
    expect(() => writeDraft(text, { answers: { GO: ["YES"] }, answeredBy: "operator" }, 2)).toThrow(SupersededError);
  });

  it("a superseded ask cannot be forwarded", async () => {
    await expect(forwardAsk(root, ASKER, "old", { to: "operator", by: "manager:idealic" })).rejects.toThrow(/superseded/);
  });

  it("the open list no longer holds it; status superseded does", () => {
    const open = listAsks(root).filter((a) => a.header.status === "open").map((a) => a.header.id);
    expect(open).toEqual(["new"]);
    expect(listAsks(root).filter((a) => a.header.status === "superseded").map((a) => a.header.id)).toEqual(["old"]);
  });
});

describe("the supersede fields are the store's", () => {
  it("new refuses them", () => {
    for (const k of ["superseded-by", "superseded-at", "superseded-actor", "supersedes"]) {
      expect(() => newAsk(root, { from: ASKER, to: "operator", id: `x-${k}`, [k]: "a/b" }, BODY)).toThrow(/written by the store/);
    }
  });
});
