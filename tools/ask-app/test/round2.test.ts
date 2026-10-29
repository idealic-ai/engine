/**
 * Ask v2 fix round 2: the re-review's 19 probes (builds/askv2_REREVIEW.md) and its re-push
 * race, ported as assertions of the FIXED behaviour, plus the round's own fixes. A probe the review
 * labelled HOLDS keeps its assertion; one labelled DEFECT now asserts the defect is gone.
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { actedAsk, answerAsk, discardDraft, newAsk, pickupUnread, readAsk, repushPending, reviseAsk, saveDraft, sendBatch } from "../src/lib/store.ts";
import { cardFor, CODE_MAX, parseAskFile, validateAnswer } from "../src/lib/format.ts";

let root: string;
beforeEach(() => {
  root = path.join(fs.mkdtempSync(path.join("/tmp", "asksr2-")), "asks");
});
afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));

const GO = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n";
const file = (seat: string, id: string) => path.join(root, seat, `${id}.md`);
const read = (seat: string, id: string) => parseAskFile(fs.readFileSync(file(seat, id), "utf8"));
function recorder(delayMs = 0) {
  const sent: { seat: string; content: string }[] = [];
  let release: () => void = () => {};
  const gate = new Promise<void>((r) => (release = r));
  const push = async (seat: string, content: string) => {
    sent.push({ seat, content });
    if (delayMs < 0) await gate;
    else if (delayMs) await new Promise((r) => setTimeout(r, delayMs));
    return { status: "delivered" as const };
  };
  return { sent, push, release: () => release() };
}
const relay = (seat: string, extra: Record<string, unknown> = {}) => ({ answeredBy: "operator", answeredVia: `relay:${seat}`, note: "said so in chat", ...extra });

describe("relay (re-review MAJ-2)", () => {
  it("a seat that is not in the chain (a bystander) cannot relay onto an ask, reserved or not", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "r1", "reserved-for": "operator" }, GO);
    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "r1b" }, GO);
    for (const id of ["r1", "r1b"]) {
      await expect(answerAsk(root, "idealic:kernel", id, { answers: { GO: ["NO"] }, ...relay("idealic:stranger") }, { expectedRevision: 1, push: recorder().push })).rejects.toThrow("may not relay");
      expect(read("idealic:kernel", id).header.status).toBe("open");
    }
  });

  it("the ASKER never relays to its own ask (reserved or not), at answer and at draft", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "r2", "reserved-for": "operator" }, GO);
    await expect(answerAsk(root, "idealic:kernel", "r2", { answers: { GO: ["YES"] }, ...relay("idealic:kernel") }, { expectedRevision: 1, push: recorder().push })).rejects.toThrow("never relays");
    await expect(saveDraft(root, "idealic:kernel", "r2", { answers: { GO: ["YES"] }, ...relay("idealic:kernel") }, 1)).rejects.toThrow("never relays");
    // Even a manager of itself: the asker is refused before standing is looked at.
    await expect(answerAsk(root, "idealic:kernel", "r2", { answers: { GO: ["YES"] }, ...relay("idealic:kernel") }, { expectedRevision: 1, push: recorder().push, relayerManages: ["idealic:kernel"] })).rejects.toThrow("never relays");
  });

  it("the addressee, a forwarder, or a manager of the asker may relay; only the operator's answer is relayed", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "r3", "reserved-for": "operator" }, GO);
    await answerAsk(root, "idealic:kernel", "r3", { answers: { GO: ["YES"] }, ...relay("manager:idealic") }, { expectedRevision: 1, push: recorder().push });
    expect(read("idealic:kernel", "r3").answer?.answeredVia).toBe("relay:manager:idealic");
    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "r4" }, GO);
    await expect(answerAsk(root, "idealic:kernel", "r4", { answers: { GO: ["YES"] }, ...relay("manager:director") }, { expectedRevision: 1, push: recorder().push })).rejects.toThrow("may not relay");
    await answerAsk(root, "idealic:kernel", "r4", { answers: { GO: ["YES"] }, ...relay("manager:director") }, { expectedRevision: 1, push: recorder().push, relayerManages: ["idealic:kernel"] });
    expect(read("idealic:kernel", "r4").answer?.answeredVia).toBe("relay:manager:director");
    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "r5" }, GO);
    await expect(answerAsk(root, "idealic:kernel", "r5", { answers: { GO: ["YES"] }, answeredBy: "manager:idealic", answeredVia: "relay:manager:idealic" }, { expectedRevision: 1, push: recorder().push })).rejects.toThrow("records the operator's answer");
  });
});

describe("filing identity (re-review MAJ-2)", () => {
  it("an asker cannot address an ask to itself, nor be its own answerer; operator files nothing", async () => {
    expect(() => newAsk(root, { from: "idealic:kernel", to: "idealic:kernel", id: "self" }, GO)).toThrow("cannot address an ask to itself");
    expect(() => newAsk(root, { from: "operator", to: "manager:app", id: "op1" }, GO)).toThrow("the operator is not one");
    // A file written by hand to itself still never lets the asker answer.
    fs.mkdirSync(path.join(root, "idealic:kernel"), { recursive: true });
    fs.writeFileSync(file("idealic:kernel", "hand"), "---\nid: hand\nto: idealic:kernel\nfrom: idealic:kernel\nstatus: open\nrevision: 1\n---\n\n" + GO);
    await expect(answerAsk(root, "idealic:kernel", "hand", { answers: { GO: ["YES"] }, answeredBy: "idealic:kernel" }, { expectedRevision: 1, push: recorder().push })).rejects.toThrow("may not answer");
  });
});

describe("ruled in chat on a reserved ask (re-review MAJ-2)", () => {
  it("the asker alone cannot close a reserved ask as ruled; a chain seat relaying the operator with a note can", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "rc", "reserved-for": "operator" }, GO);
    await expect(actedAsk(root, "idealic:kernel", "rc", "did it", { by: "idealic:kernel", ruledInChat: "operator, 03:00" })).rejects.toThrow("--relayed-from operator");
    await expect(actedAsk(root, "idealic:kernel", "rc", "did it", { by: "idealic:kernel", ruledInChat: "operator, 03:00", relayedFrom: "operator", note: "in chat" })).rejects.toThrow("never relays");
    await expect(actedAsk(root, "idealic:kernel", "rc", "did it", { by: "manager:idealic", ruledInChat: "operator, 03:00", relayedFrom: "operator" })).rejects.toThrow("--note");
    await expect(actedAsk(root, "idealic:kernel", "rc", "did it", { by: "idealic:stranger", ruledInChat: "operator, 03:00", relayedFrom: "operator", note: "n" })).rejects.toThrow("may not relay");
    expect(read("idealic:kernel", "rc").header.status).toBe("open");
    await actedAsk(root, "idealic:kernel", "rc", "applied", { by: "manager:idealic", ruledInChat: "operator, 03:00", relayedFrom: "operator", note: "in my chat" });
    expect(read("idealic:kernel", "rc").header).toMatchObject({ status: "ruled", ruledInChat: "operator, 03:00 — relayed by manager:idealic: in my chat", actedBy: "manager:idealic" });
  });
});

describe("revise racing an answer", () => {
  it("HOLDS: exactly one of a concurrent revise and answer(rev 1) wins, 30 times out of 30", async () => {
    for (let i = 0; i < 30; i++) {
      const id = `rv${i}`;
      newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id }, GO);
      const [rv, an] = await Promise.allSettled([
        reviseAsk(root, "idealic:kernel", id, { stake: "changed" }, undefined, { by: "idealic:kernel", push: recorder().push }),
        answerAsk(root, "idealic:kernel", id, { answers: { GO: ["YES"] }, answeredBy: "manager:idealic" }, { expectedRevision: 1, push: recorder().push }),
      ]);
      expect([rv.status, an.status].filter((s) => s === "fulfilled")).toHaveLength(1);
      expect(read("idealic:kernel", id).header.status).toBe(an.status === "fulfilled" ? "answered" : "open");
    }
  });
  it("HOLDS: a draft saved, then a revise, then send → refused stale", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "rv-d" }, GO);
    await saveDraft(root, "idealic:kernel", "rv-d", { answers: { GO: ["YES"] }, answeredBy: "operator" }, 1);
    await reviseAsk(root, "idealic:kernel", "rv-d", {}, GO.replace("Ship it?", "Ship it now?"), { by: "idealic:kernel", push: recorder().push });
    const out = await sendBatch(root, undefined, { by: "operator", push: recorder().push });
    expect(out.settled).toEqual([]);
    expect(out.refused[0].error).toMatch(/stale/);
  });
  it("revise keeps the honoured TRAILING draft, never an inline quote of one, and never old body text", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "rv-q" }, GO + "\nQuoted: ````json draft\n{}\n````\n");
    await saveDraft(root, "idealic:kernel", "rv-q", { answers: { GO: ["YES"] }, answeredBy: "operator" }, 1);
    await reviseAsk(root, "idealic:kernel", "rv-q", {}, GO.replace("Ship it?", "Ship it now?"), { by: "idealic:kernel", push: recorder().push });
    const text = fs.readFileSync(file("idealic:kernel", "rv-q"), "utf8");
    expect(text).not.toContain("Quoted:");
    expect(text).toContain("Ship it now?");
    expect(read("idealic:kernel", "rv-q").draft?.answers).toEqual({ GO: ["YES"] });
  });
});

describe("stale-delivery re-push vs a live writer (S3)", () => {
  const pendingWith = (seat: string, id: string, writer: string) => {
    const t = fs.readFileSync(file(seat, id), "utf8").replace(/^delivery: .*$/m, "delivery: pending").replace(/^deliveryWriter:.*\n/m, "");
    fs.writeFileSync(file(seat, id), t.replace(/\n---\n/, `\n${writer ? `deliveryWriter: ${writer}\n` : ""}---\n`));
  };

  it("HOLDS: a live, recent writer is left alone", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "p1" }, GO);
    const slow = recorder(-1);
    const p = answerAsk(root, "idealic:kernel", "p1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { expectedRevision: 1, push: slow.push });
    await new Promise((r) => setTimeout(r, 50));
    const t = fs.readFileSync(file("idealic:kernel", "p1"), "utf8").replace(/deliveryWriter: \d+@/, `deliveryWriter: ${process.ppid}@`);
    fs.writeFileSync(file("idealic:kernel", "p1"), t);
    expect(await repushPending(root, { push: recorder().push })).toEqual([]);
    slow.release();
    await p;
  });

  it("past 10 minutes a still-LIVE writer (a hung push) is NOT pushed over: only a dead pid is taken over", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "p2" }, GO);
    const slow = recorder(-1);
    const p = answerAsk(root, "idealic:kernel", "p2", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { expectedRevision: 1, push: slow.push });
    await new Promise((r) => setTimeout(r, 50));
    const rp = recorder();
    const out = await repushPending(root, { push: rp.push, now: Date.now() + 11 * 60_000 });
    slow.release();
    await p;
    expect(out).toEqual([]);
    expect(slow.sent.length + rp.sent.length).toBe(1);
  });

  it("a v1-style pending (no writer) is re-pushed only for a caller it is FOR, never on a stranger's read", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "p3" }, GO);
    await answerAsk(root, "idealic:kernel", "p3", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { expectedRevision: 1, push: recorder().push });
    pendingWith("idealic:kernel", "p3", "");
    const t = fs.readFileSync(file("idealic:kernel", "p3"), "utf8").replace(/"answeredAt": "[^"]+"/, '"answeredAt": "2026-10-01T00:00:00.000Z"');
    fs.writeFileSync(file("idealic:kernel", "p3"), t);
    const rp = recorder();
    expect(await repushPending(root, { push: rp.push })).toEqual([]);
    expect(await repushPending(root, { push: rp.push, by: "idealic:stranger" })).toEqual([]);
    expect(rp.sent).toEqual([]);
    const out = await repushPending(root, { push: rp.push, by: "idealic:kernel" });
    expect(out.map((x) => x.ref)).toEqual(["idealic:kernel/p3"]);
    expect(rp.sent.map((x) => x.seat)).toEqual(["idealic:kernel"]);
  });

  it("re-review race: three concurrent re-pushers of a dead writer's pending push it exactly once", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "x" }, GO);
    await answerAsk(root, "idealic:kernel", "x", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { expectedRevision: 1, push: recorder().push });
    pendingWith("idealic:kernel", "x", `999999@${new Date().toISOString()}`);
    let n = 0;
    const push = async () => {
      n++;
      await new Promise((r) => setTimeout(r, 30));
      return { status: "delivered" as const };
    };
    await Promise.all([repushPending(root, { push }), repushPending(root, { push }), repushPending(root, { push })]);
    expect(n).toBe(1);
  });

  it("RP1: the claim is RE-CHECKED under the lock — a writer that claims it while we wait for the lock is not pushed over", async () => {
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "rp1" }, GO);
    await answerAsk(root, "idealic:kernel", "rp1", { answers: { GO: ["YES"] }, answeredBy: "operator" }, { expectedRevision: 1, push: recorder().push });
    pendingWith("idealic:kernel", "rp1", `999999@${new Date().toISOString()}`);
    // Hold the file's lock as another process would, so our pre-check passes and we wait at the lock.
    const lock = `${file("idealic:kernel", "rp1")}.lock`;
    fs.mkdirSync(lock);
    const rp = recorder();
    const run = repushPending(root, { push: rp.push });
    await new Promise((r) => setTimeout(r, 40));
    // Meanwhile the other process claims it (a live foreign writer) and releases the lock.
    pendingWith("idealic:kernel", "rp1", `${process.ppid}@${new Date().toISOString()}`);
    fs.rmdirSync(lock);
    expect(await run).toEqual([]);
    expect(rp.sent).toEqual([]);
    expect(read("idealic:kernel", "rp1").header.deliveryWriter).toMatch(new RegExp(`^${process.ppid}@`));
  });
});

describe("drafts smuggled into the body", () => {
  it("HOLDS: a draft inside a ``` fence of another language, or indented, is refused at new", () => {
    const body = GO + '\nExample:\n```markdown\n```json draft\n{"answers":{"GO":["YES"]},"answeredBy":"operator","basedOn":1}\n```\n```\n';
    expect(() => newAsk(root, { from: "idealic:kernel", to: "operator", id: "s1" }, body)).toThrow(/records the store writes/);
  });
  it("a 4-backtick or inline fence passes new, is never a draft, and is SHOWN as written (not silently removed)", () => {
    const planted = '{"answers":{"GO":["YES"]},"answeredBy":"operator","basedOn":1,"savedAt":"x"}';
    const body = `${GO}\nQuoted: \`\`\`\`json draft\n${planted}\n\`\`\`\`\n`;
    const a = parseAskFile(fs.readFileSync(newAsk(root, { from: "idealic:kernel", to: "operator", id: "s2" }, body), "utf8"));
    expect(a.draft).toBeUndefined();
    expect([a.preamble, a.questions[0].prose, a.questions[0].proseAfter].join("\n")).toContain(planted);
  });
  it("HOLDS: the planted 4-backtick fence cannot settle even after the operator saves a real draft", async () => {
    const planted = '{"answers":{"GO":["NO"]},"answeredBy":"operator","basedOn":1,"savedAt":"x"}';
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "s3" }, `${GO}\nQ: \`\`\`\`json draft\n${planted}\n\`\`\`\`\n`);
    await saveDraft(root, "idealic:kernel", "s3", { answers: { GO: ["YES"] }, answeredBy: "operator" }, 1);
    await sendBatch(root, ["idealic:kernel/s3"], { by: "operator", push: recorder().push });
    expect(read("idealic:kernel", "s3").answer?.answers).toEqual({ GO: ["YES"] });
  });
});

describe("codes at the 12-character boundary", () => {
  it("HOLDS: a 12-character code is a code; 13 is refused, naming it", () => {
    const f = newAsk(root, { from: "a:b", to: "operator", id: "c1" }, "## ¶ASK_Q: Choose one: Q?\n- [ ] [ABCDEFGHIJKL] twelve\n- [ ] [B] b\n");
    expect(parseAskFile(fs.readFileSync(f, "utf8")).questions[0].options[0].code).toBe("ABCDEFGHIJKL");
    expect(() => newAsk(root, { from: "a:b", to: "operator", id: "c2" }, "## ¶ASK_Q: Choose one: Q?\n- [ ] [ABCDEFGHIJKLM] thirteen\n")).toThrow(/\[ABCDEFGHIJKLM\]/);
  });
  it("the refusal text states the real rule (12 at most), not 'up to 4 capitals'", () => {
    const go = () => newAsk(root, { from: "a:b", to: "operator", id: "c3" }, "## ¶ASK_Q: Choose one: Q?\n- [ ] [ABCDEFGHIJKLM] thirteen\n");
    expect(go).not.toThrow(/up to 4 capitals/);
    expect(go).toThrow(`up to ${CODE_MAX - 1} capitals or digits (${CODE_MAX} at most)`);
  });
  it("a DependsOn naming a 13-character code is refused at filing, naming it", () => {
    const body = "## ¶ASK_A: Choose one: A?\n- [ ] [ABCDEFGHIJKL] x\n- [ ] [NO] n\n\n## ¶ASK_B: Text: Why?\nDependsOn: ASK_A=ABCDEFGHIJKLM\n";
    expect(() => newAsk(root, { from: "a:b", to: "operator", id: "c4" }, body)).toThrow(/ASK_A=ABCDEFGHIJKLM is not a code/);
  });
  it("a DependsOn naming a code no option has, or a question the ask lacks, is refused", () => {
    const unknownCode = "## ¶ASK_A: Choose one: A?\n- [ ] [YES] y\n- [ ] [NO] n\n\n## ¶ASK_B: Text: Why?\nDependsOn: ASK_A=MAYBE\n";
    expect(() => newAsk(root, { from: "a:b", to: "operator", id: "c5" }, unknownCode)).toThrow(/ASK_A=MAYBE names no option of ASK_A \(it has YES, NO\)/);
    const unknownQ = "## ¶ASK_A: Choose one: A?\n- [ ] [YES] y\n\n## ¶ASK_B: Text: Why?\nDependsOn: ASK_Z=YES\n";
    expect(() => newAsk(root, { from: "a:b", to: "operator", id: "c5b" }, unknownQ)).toThrow(/ASK_Z names no question/);
    const ok = "## ¶ASK_A: Yes or no: A?\n\n## ¶ASK_B: Text: Why?\nDependsOn: ASK_A=NO\n";
    expect(() => newAsk(root, { from: "a:b", to: "operator", id: "c5c" }, ok)).not.toThrow();
  });
  it("`- [X] Xray` keeps code X; `- [X] [A] label` is still a checked box then code A", () => {
    const f = newAsk(root, { from: "a:b", to: "operator", id: "c6" }, "## ¶ASK_Q: Choose one: Q?\n- [X] Xray\n- [Y] Yankee\n- [X] [A] Alpha\n");
    const opts = parseAskFile(fs.readFileSync(f, "utf8")).questions[0].options;
    expect(opts.map((o) => [o.code, o.label])).toEqual([["X", "Xray"], ["Y", "Yankee"], ["A", "Alpha"]]);
  });
  it("HOLDS: a 12-char lean code is recognised on the card", () => {
    const f = newAsk(root, { from: "a:b", to: "operator", id: "c7" }, "## ¶ASK_Q: Choose one: Q?\nLean: ABCDEFGHIJKL — because\n- [ ] [ABCDEFGHIJKL] x\n- [ ] [B] b\n");
    expect(cardFor(parseAskFile(fs.readFileSync(f, "utf8")), 0).lean?.code).toBe("ABCDEFGHIJKL");
  });
});

describe("prose that holds a - [ ] line, or a fence (re-review MAJ-3)", () => {
  it("a checklist line in the reasons is prose, never an answerable option", () => {
    const body = "## ¶ASK_Q: Choose one: Which?\nBefore you pick:\n- [ ] check the logs first\n\n- [ ] [A] Option A\n- [ ] [B] Option B\n";
    const a = parseAskFile(fs.readFileSync(newAsk(root, { from: "a:b", to: "operator", id: "pr1" }, body), "utf8"));
    expect(a.questions[0].options.map((o) => o.label)).toEqual(["Option A", "Option B"]);
    expect(a.questions[0].prose).toBe("Before you pick:\n- [ ] check the logs first");
    expect(() => validateAnswer(a, { Q: ["check the logs first"] })).toThrow("unknown option");
  });
  it("a fenced example under a fork stays in its prose, and the options after it are kept", () => {
    const body = "## ¶ASK_Q: Choose one: Which?\nLike this:\n```\nfoo()\n## not a heading\n- [ ] [Z] not an option\n```\n- [ ] [A] Option A\n- [ ] [B] Option B\n";
    const a = parseAskFile(fs.readFileSync(newAsk(root, { from: "a:b", to: "operator", id: "pr2" }, body), "utf8"));
    expect(a.questions).toHaveLength(1);
    expect(a.questions[0].options.map((o) => o.code)).toEqual(["A", "B"]);
    expect(a.questions[0].prose).toBe("Like this:\n```\nfoo()\n## not a heading\n- [ ] [Z] not an option\n```");
  });
  it("a codeless checklist AFTER coded options (the author guide's, pasted in) never displaces them", () => {
    const a = parseAskFile("---\nid: x\nstatus: open\nrevision: 1\n---\n\n## ¶ASK_Q: Choose one: Q?\n- [ ] [A] a\n- [ ] [B] b\nChecklist:\n- [ ] every fork has a Lean\n- [ ] codes are short\n");
    expect(a.questions[0].options.map((o) => o.code)).toEqual(["A", "B"]);
    expect(a.questions[0].proseAfter).toBe("Checklist:\n- [ ] every fork has a Lean\n- [ ] codes are short");
  });
  it("options separated by blank lines are still one list; codeless v1 options still parse", () => {
    const a = parseAskFile("---\nid: x\nstatus: open\nrevision: 1\n---\n\n## ¶ASK_Q: Choose one: Q?\n- [ ] [A] a\n\n- [ ] [B] b\n\n## ¶ASK_R: Choose: R?\n- [ ] one\n- [ ] two\n");
    expect(a.questions[0].options.map((o) => o.code)).toEqual(["A", "B"]);
    expect(a.questions[1].options.map((o) => o.label)).toEqual(["one", "two"]);
  });
});

describe("pickup sanity after relay", () => {
  it("HOLDS: the asker still picks up an answer a forwarder relayed", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "k1" }, GO);
    await answerAsk(root, "idealic:kernel", "k1", { answers: { GO: ["YES"] }, ...relay("manager:idealic", { note: "n" }) }, { expectedRevision: 1, push: recorder().push });
    const got = await pickupUnread(root, "idealic:kernel", { by: "idealic:kernel" });
    expect(got.map((g) => g.stamped)).toEqual([true]);
    expect((await readAsk(root, "idealic:kernel", "k1", { by: "idealic:kernel" })).stamped).toBe(false);
  });
});

describe("the app tray (re-review: relay drafts)", () => {
  it("lists only drafts the operator authored — a seat's relay draft (answeredBy operator) is not one", async () => {
    const { trayDrafts } = await import("../src/client/App.tsx");
    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "t1" }, GO);
    newAsk(root, { from: "idealic:kernel", to: "operator", id: "t2" }, GO);
    await saveDraft(root, "idealic:kernel", "t1", { answers: { GO: ["YES"] }, ...relay("manager:idealic") }, 1);
    await saveDraft(root, "idealic:kernel", "t2", { answers: { GO: ["NO"] }, answeredBy: "operator" }, 1);
    const asks = ["t1", "t2"].map((id) => ({ ...read("idealic:kernel", id), seat: "idealic:kernel", file: file("idealic:kernel", id), mtimeMs: 0 }));
    expect(trayDrafts(asks).map((a) => a.header.id)).toEqual(["t2"]);
    // The operator cannot SEND it (only its author sends), so it is not in the tray; since round 3
    // (MUST-2) the operator may still discard or replace it from the card.
    expect((await sendBatch(root, ["idealic:kernel/t1"], { by: "operator", push: recorder().push })).refused[0].error).toContain("only its author");
    await discardDraft(root, "idealic:kernel", "t1", "operator");
    expect(read("idealic:kernel", "t1").draft).toBeUndefined();
  });
});
