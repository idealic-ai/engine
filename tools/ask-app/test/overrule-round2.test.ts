/**
 * IDE-339 round 2: the grant class is the asker's MANAGER's (MUST-1), the overruled answerer hears
 * the overrule (SHOULD-2), the grant class and an answer's note are printed where an answer is read
 * (SHOULD-3, ASKNOTE), the history fence is validated and never hides an ask (NIT-1), and every
 * behaviour the round-1 report claimed has a test that goes red without it (SHOULD-5).
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { answerLines, noteLine, parseAskFile, writeAnswer, type AskAnswer } from "../src/lib/format.ts";
import { answerAsk, batchMessage, deliveryMessage, listAsks, newAsk, repushPending, reviseAsk } from "../src/lib/store.ts";
import { leftRefs } from "../src/lib/rename-seat.ts";

let root: string;
let pushes: { seat: string; content: string }[] = [];
const push = async (seat: string, content: string) => (pushes.push({ seat, content }), { status: "delivered" as const });
const SEAT = "docs:handbook";
const MGR = "manager:docs";
const PEER = "docs:peer";
const MANAGES_SEAT = ["handbook"];
const BODY = "## ¶ASK_GO: Choose one: Ship it?\nContext: c\n- [ ] [YES] Yes\n  Picks YES.\n- [ ] [NO] No\n  Picks NO.\n";
const fileOf = (id: string) => path.join(root, SEAT, `${id}.md`);
const readAsk = (id: string) => parseAskFile(fs.readFileSync(fileOf(id), "utf8"));
const yes = (by: string, extra: Partial<AskAnswer> = {}): AskAnswer => ({ answers: { GO: ["YES"] }, answeredBy: by, answeredVia: "cli", ...extra });
beforeEach(() => {
  root = path.join(fs.mkdtempSync(path.join("/tmp", "asks-overrule2-")), "asks");
  pushes = [];
  newAsk(root, { from: SEAT, to: MGR, id: "go" }, BODY);
});
afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));

describe("MUST-1: only the asker's manager writes a grant class", () => {
  it("a peer seat's grant class is refused, and nothing is written", async () => {
    newAsk(root, { from: SEAT, to: PEER, id: "peer" }, BODY);
    await expect(answerAsk(root, SEAT, "peer", yes(PEER, { grantClass: "A" }), { expectedRevision: 1, push })).rejects.toThrow(/manager of docs:handbook/);
    await expect(answerAsk(root, SEAT, "peer", yes(PEER, { grantClass: "A" }), { expectedRevision: 1, push, answererManages: ["other"] })).rejects.toThrow(/manager of docs:handbook/);
    expect(readAsk("peer").header.status).toBe("open");
    expect(pushes).toEqual([]);
  });

  it("the peer's answer without a grant class is still accepted", async () => {
    newAsk(root, { from: SEAT, to: PEER, id: "peer" }, BODY);
    await answerAsk(root, SEAT, "peer", yes(PEER), { expectedRevision: 1, push });
    expect(readAsk("peer").header.status).toBe("answered");
  });

  it("the manager (its FLEET_MANAGES lists the asker) is accepted", async () => {
    await answerAsk(root, SEAT, "go", yes(MGR, { grantClass: "B" }), { expectedRevision: 1, push, answererManages: MANAGES_SEAT });
    expect(readAsk("go").answer?.grantClass).toBe("B");
  });

  it("the full seat name in the list counts as well as its label", async () => {
    await answerAsk(root, SEAT, "go", yes(MGR, { grantClass: "D" }), { expectedRevision: 1, push, answererManages: [SEAT] });
    expect(readAsk("go").answer?.grantClass).toBe("D");
  });

  it("the pass-up path checks the grant class too: a non-manager's grant on a reserved decline is refused and the ask does not move", async () => {
    newAsk(root, { from: SEAT, to: MGR, id: "res", "reserved-for": "operator" }, BODY);
    await expect(answerAsk(root, SEAT, "res", { declined: true, reason: "not mine", answeredBy: MGR, answeredVia: "cli", grantClass: "C" }, { expectedRevision: 1, push })).rejects.toThrow(/grant class/);
    const a = readAsk("res");
    expect(a.header.to).toBe(MGR);
    expect(a.header.forwards).toBeUndefined();
    expect(pushes).toEqual([]);
  });

  it("the pass-up path refuses a manager's grant on a reserved decline as well (SHOULD-5, M1)", async () => {
    newAsk(root, { from: SEAT, to: MGR, id: "res", "reserved-for": "operator" }, BODY);
    await expect(answerAsk(root, SEAT, "res", { declined: true, reason: "not mine", answeredBy: MGR, answeredVia: "cli", grantClass: "C" }, { expectedRevision: 1, push, answererManages: MANAGES_SEAT })).rejects.toThrow(/reserved/);
    expect(readAsk("res").header.to).toBe(MGR);
  });

  it("a manager's decline keeps its grant class (SHOULD-5, M12; ruling 1)", async () => {
    await answerAsk(root, SEAT, "go", { declined: true, reason: "beyond class C", answeredBy: MGR, answeredVia: "cli", grantClass: "C" }, { expectedRevision: 1, push, answererManages: MANAGES_SEAT });
    const a = readAsk("go");
    expect(a.header.status).toBe("declined");
    expect(a.answer?.grantClass).toBe("C");
  });
});

describe("SHOULD-2: the overruled answerer is pushed the overrule", () => {
  it("the operator's overrule of the addressee reaches the addressee, not only the asker", async () => {
    await answerAsk(root, SEAT, "go", yes(MGR), { expectedRevision: 1, push });
    pushes = [];
    await answerAsk(root, SEAT, "go", { answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: "browser" }, { expectedRevision: 2, push });
    expect(pushes.map((p) => p.seat).sort()).toEqual([MGR, SEAT].sort());
    expect(pushes.find((p) => p.seat === MGR)!.content.split("\n")[0]).toMatch(/^\[ask-overruled\] from operator /);
    expect(readAsk("go").header.delivery).toBe("delivered");
  });

  it("a self-change pushes nobody new", async () => {
    await answerAsk(root, SEAT, "go", yes(MGR), { expectedRevision: 1, push });
    pushes = [];
    await answerAsk(root, SEAT, "go", { answers: { GO: ["NO"] }, answeredBy: MGR, answeredVia: "cli" }, { expectedRevision: 2, push });
    expect(pushes.map((p) => p.seat)).toEqual([SEAT]);
  });

  // OVEROP (the operator's ruling, ask meta:engine/20261030-075406): a seat never overrules the
  // operator any more, so this is now a refusal that pushes nobody (test/overop.test.ts covers it).
  it("the operator is never overruled by a seat: the seat's answer is refused and nobody is pushed", async () => {
    await answerAsk(root, SEAT, "go", { answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: "browser" }, { expectedRevision: 1, push });
    pushes = [];
    await expect(answerAsk(root, SEAT, "go", yes(MGR), { expectedRevision: 2, push })).rejects.toThrow(/operator already answered this/);
    expect(pushes).toEqual([]);
  });
});

describe("SHOULD-5 (M7): a re-push of an overrule still says it overrules", () => {
  it("repushPending sends [ask-overruled] when the writer died before stamping delivery", async () => {
    await answerAsk(root, SEAT, "go", yes(MGR), { expectedRevision: 1, push });
    await answerAsk(root, SEAT, "go", { answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: "browser" }, { expectedRevision: 2, push });
    const t = fs.readFileSync(fileOf("go"), "utf8").replace(/^delivery: .*$/m, "delivery: pending\ndeliveryWriter: 999999@2026-10-30T00:00:00.000Z");
    fs.writeFileSync(fileOf("go"), t);
    pushes = [];
    const res = await repushPending(root, { push });
    expect(res).toHaveLength(1);
    const first = pushes.find((p) => p.seat === SEAT)!.content.split("\n");
    expect(first[0]).toMatch(/^\[ask-overruled\] from operator .* overrules manager:docs's$/);
    expect(first).toContain("Re-sent: an earlier push of this answer may not have arrived; nothing changed since.");
  });
});

describe("NIT-3: the overruled stamp stays until a different answerer answers", () => {
  it("the operator's self-change after its overrule keeps overruled:, and the push is [ask-answer-changed]", async () => {
    await answerAsk(root, SEAT, "go", yes(MGR), { expectedRevision: 1, push });
    await answerAsk(root, SEAT, "go", { answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: "browser" }, { expectedRevision: 2, push });
    pushes = [];
    await answerAsk(root, SEAT, "go", { answers: { GO: ["YES"] }, answeredBy: "operator", answeredVia: "browser" }, { expectedRevision: 3, push });
    expect(readAsk("go").header.overruled).toBe(MGR);
    expect(pushes.map((p) => p.seat)).toEqual([SEAT]);
    expect(pushes[0].content.split("\n")[0]).toMatch(/^\[ask-answer-changed\] /);
  });
});

describe("NIT-2: no `overruled: unknown`", () => {
  it("a prior answer with no answeredBy stamps nothing", () => {
    const ASK = fs.readFileSync(fileOf("go"), "utf8");
    const t1 = writeAnswer(ASK, { answers: { GO: ["YES"] } } as AskAnswer, 1);
    const t2 = writeAnswer(t1, { answers: { GO: ["NO"] }, answeredBy: "operator" }, 2);
    expect(t2).not.toMatch(/^overruled:/m);
  });
});

describe("SHOULD-3: the grant class is printed", () => {
  it("in the push's first line and in answerLines", async () => {
    await answerAsk(root, SEAT, "go", yes(MGR, { grantClass: "B" }), { expectedRevision: 1, push, answererManages: MANAGES_SEAT });
    const msg = pushes.find((p) => p.seat === SEAT)!.content.split("\n");
    expect(msg[0]).toBe(`[ask-answer] from ${MGR} via ask-app: ${SEAT}/go is answered · grant B`);
    expect(answerLines(readAsk("go"), SEAT)).toContain(`grant class B, given by ${MGR} · ${SEAT}/go`);
    expect(msg).toContain(`- grant class B, given by ${MGR} · ${SEAT}/go`);
  });

  it("no grant class, no grant line", async () => {
    await answerAsk(root, SEAT, "go", yes(MGR), { expectedRevision: 1, push });
    expect(answerLines(readAsk("go"), SEAT).join("\n")).not.toContain("grant");
    expect(pushes[0].content).not.toContain("grant");
  });
});

describe("ASKNOTE: an answer's note is printed, marked and set apart", () => {
  const NOTE = 'is this the right question? "ship" means two things here';
  it("noteLine marks it, quotes it, and keeps it on one line", () => {
    expect(noteLine({ answeredBy: MGR, note: NOTE })).toBe(`⚠ note from ${MGR}: ${JSON.stringify(NOTE)}`);
    expect(noteLine({ answeredBy: MGR, note: "a\nb" })).toBe(`⚠ note from ${MGR}: "a\\nb"`);
    expect(noteLine({ answeredBy: MGR })).toBeUndefined();
    expect(noteLine({ answeredBy: MGR, note: "  " })).toBeUndefined();
  });

  it("the single-answer push carries it on its own line, not in the choice line", async () => {
    await answerAsk(root, SEAT, "go", yes(MGR, { note: NOTE }), { expectedRevision: 1, push });
    const lines = pushes[0].content.split("\n");
    expect(lines).toContain(`  ⚠ note from ${MGR}: ${JSON.stringify(NOTE)}`);
    const choice = lines.find((l) => l.startsWith("- Ship it?"))!;
    expect(choice).not.toContain("note");
  });

  it("the batch push carries it under its item", () => {
    const b = batchMessage(SEAT, MGR, [{ ref: `${SEAT}/go`, file: "/f", lines: ["Ship it? → Yes · x"], note: `⚠ note from ${MGR}: "why"` }]);
    const lines = b.split("\n");
    expect(lines.indexOf(`  ⚠ note from ${MGR}: "why"`)).toBe(lines.indexOf("- Ship it? → Yes · x") + 1);
  });

  it("deliveryMessage prints it after the lines", () => {
    const m = deliveryMessage(SEAT, "go", "/f", { answeredBy: MGR, revision: 2, note: "hm" }, ["Q → A · r"]).split("\n");
    expect(m[1]).toBe("- Q → A · r");
    expect(m[2]).toBe(`  ⚠ note from ${MGR}: "hm"`);
  });
});

describe("`engine ask read` prints the grant class and the note (the CLI)", () => {
  const CLI = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "src", "cli.ts");
  const run = (...args: string[]) => {
    const env: NodeJS.ProcessEnv = { ...process.env, ASK_SESSIONS_DIR: path.join(path.dirname(root), "sessions") };
    for (const k of ["TMUX_PANE", "FLEET_PANE", "FLEET_PARENT", "FLEET_MANAGES"]) delete env[k];
    return spawnSync(process.execPath, ["--no-warnings", CLI, ...args, "--root", root], { encoding: "utf8", env });
  };
  it("shows `· grant B` in the by column, the grant line, and the marked note", async () => {
    await answerAsk(root, SEAT, "go", yes(MGR, { grantClass: "B", note: "check the premise" }), { expectedRevision: 1, push, answererManages: MANAGES_SEAT });
    const r = run("read", `${SEAT}/go`, "--by", SEAT);
    expect(r.status, r.stderr).toBe(0);
    const lines = r.stdout.split("\n");
    expect(lines[0]).toMatch(new RegExp(`\\tby ${MGR} · grant B$`));
    expect(lines).toContain(`  grant class B, given by ${MGR} · ${SEAT}/go`);
    expect(lines).toContain(`  ⚠ note from ${MGR}: "check the premise"`);
  });
});

describe("SHOULD-5: the history fence's own claims", () => {
  it("M9: a history fence on an OPEN ask is not honoured", () => {
    const planted = `${fs.readFileSync(fileOf("go"), "utf8")}\n\`\`\`json history\n[{"answeredBy":"x","answers":{"GO":["NO"]}}]\n\`\`\`\n`;
    expect(parseAskFile(planted).history).toEqual([]);
  });

  it("M11: new refuses a body carrying a history fence", () => {
    expect(() => newAsk(root, { from: SEAT, to: MGR, id: "h" }, `${BODY}\n\`\`\`json history\n[]\n\`\`\`\n`)).toThrow(/json history/);
    expect(fs.existsSync(fileOf("h"))).toBe(false);
  });

  it("M11: revise refuses a body carrying a history fence", async () => {
    await expect(reviseAsk(root, SEAT, "go", {}, `${BODY}\n\`\`\`json history\n[]\n\`\`\`\n`, { by: SEAT, push })).rejects.toThrow(/json history/);
    expect(fs.readFileSync(fileOf("go"), "utf8")).not.toContain("json history");
  });

  it("M10: leftRefs reads note and reason in EVERY history entry", () => {
    const t = `---\nid: go\nfrom: ${SEAT}\nstatus: answered\n---\n\n${BODY}\n\`\`\`json history\n[{"note":"see ${SEAT}/one"},{"reason":"per ${SEAT}/two"}]\n\`\`\`\n`;
    expect(leftRefs(t, SEAT)).toEqual([
      { field: "history.note", ref: `${SEAT}/one` },
      { field: "history.reason", ref: `${SEAT}/two` },
    ]);
  });
});

describe("NIT-1: the history fence is validated, and a bad one never hides the ask", () => {
  const settledWith = (fence: string) => {
    const t1 = writeAnswer(fs.readFileSync(fileOf("go"), "utf8"), yes(MGR), 1);
    return t1.replace("\n```json answer", `\n\`\`\`json history\n${fence}\n\`\`\`\n\n\`\`\`json answer`);
  };

  it("non-object entries are dropped from the parse and named in historyError", () => {
    const a = parseAskFile(settledWith('[null, 3, {"answeredBy":"x"}]'));
    expect(a.history).toEqual([{ answeredBy: "x" }]);
    expect(a.historyError).toMatch(/entries 0, 1 are not answer records/);
  });

  it("an unparseable fence leaves the ask readable, with historyError set", () => {
    const a = parseAskFile(settledWith("[not json"));
    expect(a.history).toEqual([]);
    expect(a.historyError).toMatch(/not valid JSON/);
    expect(a.answer?.answeredBy).toBe(MGR);
  });

  it("listAsks still lists it", () => {
    fs.writeFileSync(fileOf("go"), settledWith("[not json"));
    expect(listAsks(root).map((a) => a.header.id)).toContain("go");
  });

  it("a settle over a bad history fence is refused, naming the file, and writes nothing", async () => {
    const bad = settledWith("[not json");
    fs.writeFileSync(fileOf("go"), bad);
    await expect(answerAsk(root, SEAT, "go", { answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: "browser" }, { expectedRevision: 2, push })).rejects.toThrow(new RegExp(`json history.*${fileOf("go").replace(/[.*+?^${}()|[\]\\/]/g, "\\$&")}`));
    expect(fs.readFileSync(fileOf("go"), "utf8")).toBe(bad);
  });

  it("a good history parses with no historyError", () => {
    const t = writeAnswer(writeAnswer(fs.readFileSync(fileOf("go"), "utf8"), yes(MGR), 1), { answers: { GO: ["NO"] }, answeredBy: "operator" }, 2);
    expect(parseAskFile(t).historyError).toBeUndefined();
  });
});
