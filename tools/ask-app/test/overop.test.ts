/**
 * IDE-339 OVEROP (the operator's ruling, ask meta:engine/20261030-075406): a seat never replaces an
 * answer the operator gave — not by answering, declining, passing up, drafting or batch-sending over
 * it. The refusal names the operator's answer (its choice and time). The operator changing its own
 * answer stays allowed, and a relay of the operator by a seat with standing counts as the operator.
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { AnsweredByOperatorError, parseAskFile, type AskAnswer } from "../src/lib/format.ts";
import { answerAsk, newAsk, saveDraft, sendBatch } from "../src/lib/store.ts";

let root: string;
let pushes: { seat: string; content: string }[] = [];
const push = async (seat: string, content: string) => (pushes.push({ seat, content }), { status: "delivered" as const });
const SEAT = "docs:handbook";
const MGR = "manager:docs";
const BODY = "## ¶ASK_GO: Choose one: Ship it?\nContext: c\n- [ ] [YES] Yes\n  Picks YES.\n- [ ] [NO] No\n  Picks NO.\n";
const OP_AT = "2026-10-30T08:00:00.000Z";
const fileOf = (id: string) => path.join(root, SEAT, `${id}.md`);
const readAsk = (id: string) => parseAskFile(fs.readFileSync(fileOf(id), "utf8"));
const pick = (by: string, code: string, extra: Partial<AskAnswer> = {}): AskAnswer => ({ answers: { GO: [code] }, answeredBy: by, answeredVia: "cli", ...extra });
const operatorAnswered = async (id = "go", extra: Record<string, string> = {}) => {
  newAsk(root, { from: SEAT, to: MGR, id, ...extra }, BODY);
  await answerAsk(root, SEAT, id, pick("operator", "NO", { answeredVia: "browser", answeredAt: OP_AT }), { expectedRevision: 1, push });
  pushes = [];
};
const refusal = /operator already answered this at 2026-10-30T08:00:00\.000Z \(GO NO\); a seat cannot replace it — send a follow-up instead/;

beforeEach(() => {
  root = path.join(fs.mkdtempSync(path.join("/tmp", "asks-overop-")), "asks");
  pushes = [];
});
afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));

describe("OVEROP: a seat cannot replace the operator's answer", () => {
  it("a manager's re-answer over the operator is refused, naming the operator's choice and time, and writes and pushes nothing", async () => {
    await operatorAnswered();
    const before = fs.readFileSync(fileOf("go"), "utf8");
    const err = await answerAsk(root, SEAT, "go", pick(MGR, "YES"), { expectedRevision: 2, push }).catch((e) => e);
    expect(err).toBeInstanceOf(AnsweredByOperatorError);
    expect(err.message).toMatch(refusal);
    expect(err.answeredAt).toBe(OP_AT);
    expect(err.answeredBy).toBe("operator");
    expect(fs.readFileSync(fileOf("go"), "utf8")).toBe(before);
    expect(pushes).toEqual([]);
  });

  it("a seat's decline over the operator's answer is refused the same way", async () => {
    await operatorAnswered();
    await expect(answerAsk(root, SEAT, "go", { declined: true, reason: "not this", answeredBy: MGR }, { expectedRevision: 2, push })).rejects.toThrow(refusal);
    expect(readAsk("go").answer?.answers).toEqual({ GO: ["NO"] });
  });

  it("over the operator's DECLINE, the refusal names the decline as its choice", async () => {
    newAsk(root, { from: SEAT, to: MGR, id: "dec" }, BODY);
    await answerAsk(root, SEAT, "dec", { declined: true, reason: "out of scope", answeredBy: "operator", answeredAt: OP_AT }, { expectedRevision: 1, push });
    await expect(answerAsk(root, SEAT, "dec", pick(MGR, "YES"), { expectedRevision: 2, push })).rejects.toThrow(/at 2026-10-30T08:00:00\.000Z \(a decline: out of scope\)/);
  });

  it("the pass-up path: a seat's decline of a reserved ask the operator answered is refused naming the operator's answer", async () => {
    await operatorAnswered("res", { "reserved-for": "operator" });
    await expect(answerAsk(root, SEAT, "res", { declined: true, reason: "not mine", answeredBy: MGR }, { expectedRevision: 2, push, passUpTo: "manager:director" })).rejects.toThrow(refusal);
    expect(readAsk("res").header.status).toBe("answered");
    expect(readAsk("res").header.to).toBe(MGR);
  });

  it("a seat's draft over the operator's answer is refused naming the operator's answer", async () => {
    await operatorAnswered();
    await expect(saveDraft(root, SEAT, "go", pick(MGR, "YES"), 2)).rejects.toThrow(refusal);
    expect(readAsk("go").header.draft).toBeUndefined();
  });

  it("batch send: a seat's draft saved while open, then the operator answered, is refused naming the operator's answer", async () => {
    newAsk(root, { from: SEAT, to: MGR, id: "go" }, BODY);
    await saveDraft(root, SEAT, "go", pick(MGR, "YES"), 1);
    await answerAsk(root, SEAT, "go", pick("operator", "NO", { answeredVia: "browser", answeredAt: OP_AT }), { expectedRevision: 1, push });
    const out = await sendBatch(root, [`${SEAT}/go`], { by: MGR, push });
    expect(out.settled).toEqual([]);
    expect(out.refused).toHaveLength(1);
    expect(out.refused[0].error).toMatch(refusal);
    expect(readAsk("go").answer?.answers).toEqual({ GO: ["NO"] });
  });

  it("an unpermitted relay of the operator does not count as the operator: it is refused", async () => {
    await operatorAnswered();
    await expect(answerAsk(root, SEAT, "go", pick("operator", "YES", { answeredVia: "relay:docs:stranger" }), { expectedRevision: 2, push })).rejects.toThrow(/may not relay/);
  });
});

describe("OVEROP: what stays allowed", () => {
  it("the operator changes its own answer", async () => {
    await operatorAnswered();
    await answerAsk(root, SEAT, "go", pick("operator", "YES", { answeredVia: "browser" }), { expectedRevision: 2, push });
    expect(readAsk("go").answer?.answers).toEqual({ GO: ["YES"] });
  });

  it("the operator drafts a change to its own answer", async () => {
    await operatorAnswered();
    await saveDraft(root, SEAT, "go", pick("operator", "YES", { answeredVia: "browser" }), 2);
    expect(readAsk("go").draft?.answers).toEqual({ GO: ["YES"] });
  });

  it("a permitted relay of the operator (the addressee relays) counts as the operator", async () => {
    await operatorAnswered();
    await answerAsk(root, SEAT, "go", pick("operator", "YES", { answeredVia: `relay:${MGR}`, note: "operator in chat" }), { expectedRevision: 2, push });
    expect(readAsk("go").answer?.answers).toEqual({ GO: ["YES"] });
  });

  it("a seat re-answering over a SEAT's answer is not this refusal", async () => {
    newAsk(root, { from: SEAT, to: MGR, id: "go" }, BODY);
    await answerAsk(root, SEAT, "go", pick(MGR, "NO"), { expectedRevision: 1, push });
    await answerAsk(root, SEAT, "go", pick(MGR, "YES"), { expectedRevision: 2, push });
    expect(readAsk("go").answer?.answers).toEqual({ GO: ["YES"] });
  });
});

describe("OVEROP: the server maps the refusal to 409 with structured fields", () => {
  it("/api/answer and /api/draft answer 409 {status: answered-by-operator, answeredAt, answeredBy}", () => {
    const src = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "src", "server.ts"), "utf8");
    expect(src).toMatch(
      /if \(e instanceof AnsweredByOperatorError\) return send\(res, 409, \{ error: e\.message, status: "answered-by-operator", answeredAt: e\.answeredAt, answeredBy: e\.answeredBy \}\);/,
    );
    // in the answer/draft route's catch, before the AskFormatError 400 it extends
    const route = src.indexOf("await answerAsk(root, b.seat, b.id");
    const mine = src.indexOf("e instanceof AnsweredByOperatorError", route);
    expect(route).toBeGreaterThan(-1);
    expect(mine).toBeGreaterThan(route);
    expect(mine).toBeLessThan(src.indexOf("if (e instanceof AskFormatError) return send(res, 400", route));
  });
});
