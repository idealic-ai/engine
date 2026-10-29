/**
 * The operator's ruling (2026-10-30 02:03): on an ask `reserved-for: operator`, a decline by anyone
 * but the operator does not close the ask. It is passed up one rung — to the decliner's own parent,
 * `operator` when it has none — with the reason on the forward hop, and the ask stays open.
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { answerAsk, newAsk } from "../src/lib/store.ts";
import { forwardChain, parseAskFile } from "../src/lib/format.ts";

let root: string;
beforeEach(() => {
  root = path.join(fs.mkdtempSync(path.join("/tmp", "asks-pu-")), "asks");
});
afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));

const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n";
const ASKER = "idealic:kernel";
const read = (id: string) => parseAskFile(fs.readFileSync(path.join(root, ASKER, `${id}.md`), "utf8"));
const pushes: { seat: string; content: string }[] = [];
const push = async (seat: string, content: string) => {
  pushes.push({ seat, content });
  return { status: "delivered" as const };
};
beforeEach(() => (pushes.length = 0));

describe("a reserved ask declined by a seat is passed up, not closed", () => {
  it("forwards to the decliner's parent with the reason, and stays open", async () => {
    newAsk(root, { from: ASKER, to: "manager:idealic", id: "r1", "reserved-for": "operator" }, BODY);
    const out = await answerAsk(root, ASKER, "r1", { declined: true, reason: "not my call; needs the budget owner", answeredBy: "manager:idealic" }, { expectedRevision: 1, passUpTo: "manager:director", push });
    expect(out.passedUpTo).toBe("manager:director");
    const a = read("r1");
    expect(a.header.status).toBe("open");
    expect(a.header.to).toBe("manager:director");
    expect(a.answer).toBeUndefined();
    expect(a.header.revision).toBe("2");
    const hops = forwardChain(a.header);
    expect(hops).toHaveLength(1);
    expect(hops[0]).toMatchObject({ from: "manager:idealic", to: "manager:director", reason: "not my call, needs the budget owner" });
    expect(a.header.forwards).toContain("[declined: not my call, needs the budget owner]");
    // The next holder hears it, with the reason; the decliner does not hear its own pass-up.
    expect(pushes.map((p) => p.seat)).toEqual(["manager:director"]);
    expect(pushes[0].content).toContain("[ask-passed-up]");
    expect(pushes[0].content).toContain("not my call, needs the budget owner");
  });

  it("goes to the operator when the decliner has no parent, and pushes nobody", async () => {
    newAsk(root, { from: ASKER, to: "manager:director", id: "r2", "reserved-for": "operator" }, BODY);
    const out = await answerAsk(root, ASKER, "r2", { declined: true, reason: "the operator's", answeredBy: "manager:director" }, { expectedRevision: 1, push });
    expect(out.passedUpTo).toBe("operator");
    expect(read("r2").header.to).toBe("operator");
    expect(read("r2").header.status).toBe("open");
    expect(pushes).toEqual([]);
  });

  it("keeps a reason holding `@` or `;` from breaking the hop", async () => {
    newAsk(root, { from: ASKER, to: "manager:idealic", id: "r3", "reserved-for": "operator" }, BODY);
    await answerAsk(root, ASKER, "r3", { declined: true, reason: "ask bob@x; or carol", answeredBy: "manager:idealic" }, { expectedRevision: 1, passUpTo: "manager:director", push });
    const [hop] = forwardChain(read("r3").header);
    expect(hop.from).toBe("manager:idealic");
    expect(hop.to).toBe("manager:director");
    expect(hop.at).toMatch(/^\d{4}-\d\d-\d\dT/);
  });

  it("is still compare-and-swap: a stale revision moves nothing", async () => {
    newAsk(root, { from: ASKER, to: "manager:idealic", id: "r4", "reserved-for": "operator" }, BODY);
    await expect(answerAsk(root, ASKER, "r4", { declined: true, reason: "x", answeredBy: "manager:idealic" }, { expectedRevision: 7, passUpTo: "manager:director", push })).rejects.toThrow(/stale revision/);
    expect(read("r4").header.to).toBe("manager:idealic");
  });

  it("a bystander still may not decline it", async () => {
    newAsk(root, { from: ASKER, to: "manager:idealic", id: "r5", "reserved-for": "operator" }, BODY);
    await expect(answerAsk(root, ASKER, "r5", { declined: true, reason: "x", answeredBy: "app:writer" }, { expectedRevision: 1, passUpTo: "manager:app", push })).rejects.toThrow(/only the holder/);
    expect(read("r5").header.to).toBe("manager:idealic");
  });

  it("a seat's answer (not a decline) on a reserved ask is still refused", async () => {
    newAsk(root, { from: ASKER, to: "manager:idealic", id: "r6", "reserved-for": "operator" }, BODY);
    await expect(answerAsk(root, ASKER, "r6", { answers: { GO: ["YES"] }, answeredBy: "manager:idealic" }, { expectedRevision: 1, passUpTo: "manager:director", push })).rejects.toThrow(/reserved for operator/);
  });
});

describe("other declines behave as before", () => {
  it("the operator's decline of a reserved ask closes it", async () => {
    newAsk(root, { from: ASKER, to: "manager:idealic", id: "o1", "reserved-for": "operator" }, BODY);
    const out = await answerAsk(root, ASKER, "o1", { declined: true, reason: "no", answeredBy: "operator" }, { expectedRevision: 1, passUpTo: "manager:director", push });
    expect(out.passedUpTo).toBeUndefined();
    expect(read("o1").header.status).toBe("declined");
    expect(read("o1").header.to).toBe("manager:idealic");
  });

  it("a seat's decline of an unreserved ask closes it", async () => {
    newAsk(root, { from: ASKER, to: "manager:idealic", id: "u1" }, BODY);
    const out = await answerAsk(root, ASKER, "u1", { declined: true, reason: "no", answeredBy: "manager:idealic" }, { expectedRevision: 1, passUpTo: "manager:director", push });
    expect(out.passedUpTo).toBeUndefined();
    expect(read("u1").header.status).toBe("declined");
    expect(read("u1").header.forwards).toBeUndefined();
  });
});
