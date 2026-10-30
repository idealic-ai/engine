/**
 * Ask v2: question kinds, card fields, tickets, drafts, read/acted stamps and the
 * forward chain — the pure-string half. v1 files must still parse unchanged.
 */
import { describe, expect, it } from "vitest";
import {
  answerLines,
  authorWarnings,
  dependsOnDeclined,
  visibleAsks,
  cardFor,
  forwardChain,
  parseAskFile,
  recipientsOf,
  setHeaderField,
  ticketKeys,
  validateAnswer,
  visibleQuestions,
  writeAnswer,
  writeDraft,
  AskFormatError,
  StaleRevisionError,
} from "../src/lib/format.ts";

const head = (extra = "") => `---\nid: k1\nto: operator\nfrom: idealic:kernel\nstatus: open\nrevision: 1\n${extra}---\n\n`;

const KINDS = head() + `## ¶ASK_ORDER: Rank: Which first?
- [ ] [A] Alpha
- [ ] [B] Beta
- [ ] [C] Gamma

## ¶ASK_NAME: Text: What should we call it?

## ¶ASK_DAYS: Number: How many days?
Range: 1..30
Unit: days

## ¶ASK_WHEN: Date: Ship date?

## ¶ASK_GO: Yes or no: Ship at all?

## ¶ASK_WHY: Text: Why not?
DependsOn: ASK_GO=NO
`;

describe("question kinds (acceptance 3)", () => {
  const ask = parseAskFile(KINDS);
  it("parses every kind from its heading", () => {
    expect(ask.questions.map((q) => q.kind)).toEqual(["rank", "text", "number", "date", "yesno", "text"]);
    expect(ask.questions[2].number).toEqual({ min: 1, max: 30, unit: "days" });
  });
  it("gives a bare yes/no question YES and NO options", () => {
    expect(ask.questions[4].options.map((o) => o.code)).toEqual(["YES", "NO"]);
  });
  it("keeps v1 headings as choose-one / choose", () => {
    const v1 = parseAskFile(head() + "## Choose one: X?\n- [ ] [A] a\n\n## Choose: Y?\n- [ ] [B] b\n");
    expect(v1.questions.map((q) => [q.kind, q.multiSelect])).toEqual([["choose-one", false], ["choose", true]]);
  });
  it("accepts a full ranking, a text, a number in range, a real date and a yes/no", () => {
    expect(() => validateAnswer(ask, { ORDER: ["B", "A", "C"], NAME: "kite", DAYS: 7, WHEN: "2026-11-02", GO: ["YES"] })).not.toThrow();
  });
  it.each([
    [{ ORDER: ["A", "B"] }, "must rank every option"],
    [{ ORDER: ["A", "A", "B"] }, "must rank every option"],
    [{ NAME: "  " }, "non-blank text"],
    [{ DAYS: 31 }, "between 1 and 30"],
    [{ DAYS: "7" }, "must be a number"],
    [{ WHEN: "2026-02-30" }, "real date"],
    [{ WHEN: "next week" }, "real date"],
    [{ GO: ["MAYBE"] }, "unknown option"],
  ])("refuses %j", (answers, msg) => {
    expect(() => validateAnswer(ask, answers)).toThrow(msg);
  });
  it("conditional yes/no: the follow-up shows only under the named code", () => {
    expect(visibleQuestions(ask.questions, { GO: ["YES"] }).map((q) => q.askName)).not.toContain("WHY");
    expect(visibleQuestions(ask.questions, { GO: ["NO"] }).map((q) => q.askName)).toContain("WHY");
  });
  it("deep nesting: a fourth-level option is a valid answer", () => {
    const deep = parseAskFile(head() + "## ¶ASK_D: Choose one: Deep?\n- [ ] [L1] one\n  - [ ] [L2] two\n    - [ ] [L3] three\n      - [ ] [L4] four\n");
    expect(deep.questions[0].options[0].children![0].children![0].children![0].code).toBe("L4");
    expect(() => validateAnswer(deep, { D: ["L1", "L2", "L3", "L4"] })).not.toThrow();
  });
});

const CARD = head(
  "rank: 6 of 7\ntopic: who funds a world's seat contracts\nstake: nothing can be the funder yet\nunblocks: E14\nrelated: the re-seed ruling lands first\nevidence: v3 §Contracts line 478 ; v3 open question 6 ; roles.ts:455\ntickets: IDE-234, IDE-182\nlean: B — because a re-seed then never touches contracts\ncounter: B is a root again\nconfidence: med — v3 is silent on B's room\nreversible: no — a one-way door\nreserved-for: operator\n",
) + `A contract's spend grant has to be issued out of a transferable spend grant (see IDE-253).

## ¶ASK_FUND: Choose one: What does a world fund its seat contracts out of?
Verify: grep roles.ts for issueProjectSpend
Panel: Security → B — a separate root keeps the blast small
Panel: Economist → A — one root is simpler to audit
- [ ] [A] Make the world's spend root transferable
  Contracts derive from the world's own root.
  Cost: it changes what a holder can pass on
  Effort: M
  Blast: every world
- [ ] [B] A separate transferable root at the budgets
  Shaped like issueProjectSpend's.
  It is placed at deployment set-up.
  Cost: it is a root again

## ¶ASK_SECOND: Choose one: A second question
Stake: only this card's own stake
- [ ] [X] x
`;

describe("decision-board card fields (acceptance 7, 8)", () => {
  const ask = parseAskFile(CARD);
  it("puts the header's card fields on the first card", () => {
    const c = cardFor(ask, 0);
    expect(c).toMatchObject({ rank: "6 of 7", topic: "who funds a world's seat contracts", stake: "nothing can be the funder yet", unblocks: "E14", related: "the re-seed ruling lands first", counter: "B is a root again", confidence: "med — v3 is silent on B's room", reversible: "no — a one-way door", reservedFor: "operator", verify: "grep roles.ts for issueProjectSpend" });
    expect(c.evidence).toEqual(["v3 §Contracts line 478", "v3 open question 6", "roles.ts:455"]);
    expect(c.lean).toEqual({ code: "B", text: "because a re-seed then never touches contracts" });
  });
  it("does not repeat the header's fields on a later card; a card's own lines win", () => {
    const c = cardFor(ask, 1);
    expect(c.stake).toBe("only this card's own stake");
    expect(c.unblocks).toBeUndefined();
    expect(c.lean).toBeUndefined();
  });
  it("reads per-option cost, effort and blast radius, and a multi-line description (N-2)", () => {
    const [a, b] = ask.questions[0].options;
    expect(a).toMatchObject({ cost: "it changes what a holder can pass on", effort: "M", blastRadius: "every world", description: "Contracts derive from the world's own root." });
    expect(b.description).toBe("Shaped like issueProjectSpend's. It is placed at deployment set-up.");
  });
  it("reads a council panel per option: lens, pick, why", () => {
    expect(ask.questions[0].panel).toEqual([
      { lens: "Security", pick: "B", why: "a separate root keeps the blast small" },
      { lens: "Economist", pick: "A", why: "one root is simpler to audit" },
    ]);
  });
  it("leaves a v1 file's card empty rather than failing", () => {
    const v1 = parseAskFile(head("lean: one file per ask\n") + "## Choose one: X?\n- [ ] [A] a\n");
    expect(cardFor(v1, 0).lean).toEqual({ text: "one file per ask" });
    expect(cardFor(v1, 0).evidence).toEqual([]);
  });
});

describe("linked tickets (acceptance 6)", () => {
  it("finds keys in the tickets header and the body, de-duplicated, header first", () => {
    expect(ticketKeys(parseAskFile(CARD))).toEqual(["IDE-234", "IDE-182", "IDE-253"]);
  });
  it("does not mistake an option code or a date for a key", () => {
    expect(ticketKeys(parseAskFile(head() + "On 2026-10-29.\n## Choose one: X?\n- [ ] [ABC] a\n"))).toEqual([]);
  });
});

describe("drafts live in the file (acceptance 1)", () => {
  const ask0 = head() + "## ¶ASK_GO: Choose one: Ship?\n- [ ] [YES] Yes\n- [ ] [NO] No\n";
  it("embeds a draft without settling or bumping the revision", () => {
    const t = writeDraft(ask0, { answers: { GO: ["YES"] }, answeredBy: "operator" }, 1);
    const a = parseAskFile(t);
    expect(a.header.status).toBe("open");
    expect(a.header.revision).toBe("1");
    expect(a.draft).toMatchObject({ answers: { GO: ["YES"] }, basedOn: 1 });
    expect(a.answer).toBeUndefined();
    expect(a.questions).toHaveLength(1);
  });
  it("refuses a draft on a moved ask", () => {
    expect(() => writeDraft(ask0, { answers: { GO: ["YES"] } }, 2)).toThrow(StaleRevisionError);
  });
  it("refuses an invalid draft the way it refuses an answer", () => {
    expect(() => writeDraft(ask0, { answers: {} }, 1)).toThrow("empty answer");
  });
  it("answering removes the draft and clears the read and acted stamps", () => {
    let t = writeDraft(ask0, { answers: { GO: ["YES"] } }, 1);
    t = setHeaderField(t, "readAt", "x");
    t = setHeaderField(t, "acted", "did it");
    const out = parseAskFile(writeAnswer(t, { answers: { GO: ["NO"] } }, 1));
    expect(out.draft).toBeUndefined();
    expect(out.header.readAt).toBeUndefined();
    expect(out.header.acted).toBeUndefined();
    expect(out.answer?.answers).toEqual({ GO: ["NO"] });
  });
});

describe("the batch message is built from the file (acceptance 1)", () => {
  it("lists title → answer · id per question", () => {
    const t = writeAnswer(KINDS, { answers: { ORDER: ["C", "A", "B"], NAME: "kite", DAYS: 7, WHEN: "2026-11-02", GO: ["NO"], WHY: "not ready", "GO.other": "after the freeze" } }, 1);
    const lines = answerLines(parseAskFile(t), "idealic:kernel");
    expect(lines).toEqual([
      "Which first? → Gamma > Alpha > Beta · idealic:kernel/k1#ORDER",
      "What should we call it? → \"kite\" · idealic:kernel/k1#NAME",
      "How many days? → 7 days · idealic:kernel/k1#DAYS",
      "Ship date? → 2026-11-02 · idealic:kernel/k1#WHEN",
      "Ship at all? → No (note: after the freeze) · idealic:kernel/k1#GO",
      "Why not? → \"not ready\" · idealic:kernel/k1#WHY",
    ]);
  });
  it("a decline is one line carrying its reason", () => {
    const t = head().replace("status: open", "status: declined") + "## Choose one: X?\n- [ ] [A] a\n\n```json answer\n{\"declined\":true,\"reason\":\"not mine\",\"revision\":2}\n```\n";
    expect(answerLines(parseAskFile(t), "s")).toEqual(["X? → declined: not mine · s/k1"]);
  });
});

describe("the forward chain (COORDHOP S4)", () => {
  it("parses recorded hops and pushes to the asker and every forwarder", () => {
    const t = head("forwards: manager:idealic→manager:director@2026-10-29T01:00:00Z ; manager:director→operator@2026-10-29T01:10:00Z\n") + "## Choose one: X?\n- [ ] [A] a\n";
    const a = parseAskFile(t);
    expect(forwardChain(a.header).map((h) => [h.from, h.to])).toEqual([["manager:idealic", "manager:director"], ["manager:director", "operator"]]);
    expect(recipientsOf(a, "operator")).toEqual(["idealic:kernel", "manager:idealic", "manager:director"]);
    expect(recipientsOf(a, "manager:director")).toEqual(["idealic:kernel", "manager:idealic"]);
  });
});

it("AskFormatError is still the base class callers catch", () => {
  expect(new StaleRevisionError(1, 2)).toBeInstanceOf(AskFormatError);
});

describe("fix round 1 (pure)", () => {
  const mk = (id: string, status: string, dep = "") => parseAskFile(`---\nid: ${id}\nstatus: ${status}\nrevision: 2\ndependsOn: ${dep}\n---\n\n## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n`);

  it("P5/S6: an ask that depends on a DECLINED ask is shown, and marked as such", () => {
    const all = [mk("a", "declined"), mk("b", "open", "a"), mk("c", "open", "z")];
    expect(visibleAsks(all).map((x) => x.header.id)).toEqual(["a", "b", "c"]);
    expect(all.map((x) => dependsOnDeclined(x, all))).toEqual([false, true, false]);
    expect(visibleAsks([mk("a", "open"), mk("b", "open", "a")]).map((x) => x.header.id)).toEqual(["a"]);
  });

  it("N5: a hop between seats whose names hold @ splits at the timestamp's @", () => {
    const h = forwardChain({ forwards: "team@x→boss@y@2026-10-29T01:00:00Z ; boss@y→operator@2026-10-29T02:00:00Z" });
    expect(h).toEqual([{ from: "team@x", to: "boss@y", at: "2026-10-29T01:00:00Z" }, { from: "boss@y", to: "operator", at: "2026-10-29T02:00:00Z" }]);
  });

  it("M1: writeDraft's own draft is honoured; the same block copied into the body is not", () => {
    const base = head() + "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n";
    const drafted = writeDraft(base, { answers: { GO: ["YES"] }, answeredBy: "operator", savedAt: "2026-10-29T00:00:00Z" }, 1);
    expect(parseAskFile(drafted).draft?.answers).toEqual({ GO: ["YES"] });
    const fence = drafted.slice(drafted.indexOf("```json draft"));
    const moved = drafted.replace(fence, "").replace("## ¶ASK_GO", fence + "\n## ¶ASK_GO");
    expect(parseAskFile(moved).draft).toBeUndefined();
    const reheaded = drafted.replace("draft: 2026-10-29T00:00:00Z", "draft: 2026-10-29T09:09:09Z");
    expect(parseAskFile(reheaded).draft).toBeUndefined();
    expect(parseAskFile(moved).questions.map((q) => q.title)).toEqual(["Ship it?"]);
  });
});

describe("the card shows a relay", () => {
  it("AnsweredBy names the relayer in plain words; a browser answer shows no relay", async () => {
    const { renderToStaticMarkup } = await import("react-dom/server");
    const { createElement } = await import("react");
    const { AnsweredBy } = await import("../src/client/App.tsx");
    const relayed = renderToStaticMarkup(createElement(AnsweredBy, { answer: { answeredBy: "operator", answeredVia: "relay:manager:docs", note: "chat 02:20" } }));
    expect(relayed).toContain("relayed by manager:docs");
    const direct = renderToStaticMarkup(createElement(AnsweredBy, { answer: { answeredBy: "operator", answeredVia: "browser" } }));
    expect(direct).not.toContain("relayed by");
    expect(direct).toContain("via browser");
  });
});

describe("parser: fork prose and long codes (ASKDESIGN)", () => {
  const ASK = head() + `## ¶ASK_F5: Choose one: Correct the F5 ruling?
The earlier ruling read the cache as cold. It was warm: IDE-264's numbers came from a replay.

So the fork is whether to rescope.
Stake: two lanes stall
- [ ] [RESCOPE] Rescope it
  Cost: a day
- [ ] [KEEPBROAD] Keep it broad
Unindented note after the options.

## ¶ASK_NEXT: Choose one: Then?
- [ ] [MARINATE] Marinate
`;

  it("keeps the prose under a heading as the fork's context, and the card lines and options still parse", () => {
    const a = parseAskFile(ASK);
    expect(a.questions[0].prose).toBe("The earlier ruling read the cache as cold. It was warm: IDE-264's numbers came from a replay.\n\nSo the fork is whether to rescope.");
    expect(a.questions[0].proseAfter).toBe("Unindented note after the options.");
    expect(a.questions[0].meta.stake).toBe("two lanes stall");
    expect(a.questions[0].options.map((o) => o.code)).toEqual(["RESCOPE", "KEEPBROAD"]);
    expect(a.questions[0].options[0].cost).toBe("a day");
    expect(a.questions[1].prose).toBeUndefined();
    expect(ticketKeys(a)).toContain("IDE-264");
  });

  it("the card renders that prose", async () => {
    const { renderToStaticMarkup } = await import("react-dom/server");
    const { createElement } = await import("react");
    const { ForkProse } = await import("../src/client/App.tsx");
    const html = renderToStaticMarkup(createElement(ForkProse, { text: parseAskFile(ASK).questions[0].prose }));
    expect(html).toContain("It was warm");
    expect(html).toContain("So the fork is whether to rescope.");
  });

  it("codes up to 12 characters are codes, never label text; 13 is not read as a code", () => {
    const a = parseAskFile(head() + "## ¶ASK_X: Choose one: X?\n- [ ] [KEEPBROAD] Keep\n- [ ] [ABCDEFGHIJKL] Twelve\n- [ ] [ABCDEFGHIJKLM] Thirteen\n");
    expect(a.questions[0].options.map((o) => o.code ?? null)).toEqual(["KEEPBROAD", "ABCDEFGHIJKL", null]);
    expect(validateAnswer.bind(null, a, { X: ["KEEPBROAD"] })).not.toThrow();
  });
});

describe("authoring warnings", () => {
  it("warn on a header lean over many forks, a fork with no Lean:, and codeless options; a well-formed ask warns nothing", () => {
    const bad = parseAskFile(head("lean: F1 ALL; F2 DEGR\n") + "## ¶ASK_A: Choose one: A?\n- [ ] [X] x\n- [ ] y\n\n## ¶ASK_B: Choose one: B?\n- [ ] [P] p\n");
    expect(authorWarnings(bad)).toEqual([
      "the header lean fills the first fork's card only; write a Lean: line under every fork",
      '"A?": 1 option(s) have no [CODE]; the answer will store the whole label',
      '"A?": 2 of 2 options have no Cost: line (what the operator gives up); 2 of 2 have no Elegance: line (how cleanly it fits)',
      '"B?": no Lean: line',
      '"B?": 1 of 1 options have no Cost: line (what the operator gives up); 1 of 1 have no Elegance: line (how cleanly it fits)',
    ]);
    const good = parseAskFile(head() + "## ¶ASK_A: Choose one: A?\nLean: X — because\n- [ ] [X] x\n  Cost: c\n  Elegance: e\n\n## ¶ASK_B: Text: Name?\n");
    expect(authorWarnings(good)).toEqual([]);
  });
});

describe("the app renders fork prose between the cards (operator's screenshot)", () => {
  it("prose before the options is inside its card, prose after them sits between that card and the next", async () => {
    const { renderToStaticMarkup } = await import("react-dom/server");
    const { createElement } = await import("react");
    const { AskDetail } = await import("../src/client/App.tsx");
    const text = head() + "## ¶ASK_A: Choose one: First?\nWhy first matters.\n- [ ] [X] x\n- [ ] [Y] y\nBETWEEN-THE-FORKS note.\n\n## ¶ASK_B: Choose one: Second?\nWhy second.\n- [ ] [P] p\n";
    const ask = { ...parseAskFile(text), seat: "idealic:kernel", file: "/x.md", mtimeMs: 0 };
    const html = renderToStaticMarkup(createElement(AskDetail, { ask, all: [ask], onChanged: () => {} }));
    const iFirst = html.indexOf("First?"), iBetween = html.indexOf("BETWEEN-THE-FORKS"), iSecond = html.indexOf("Second?");
    expect(html).toContain("Why first matters.");
    expect(html).toContain("Why second.");
    expect(iFirst).toBeGreaterThan(-1);
    expect(iBetween).toBeGreaterThan(iFirst);
    expect(iSecond).toBeGreaterThan(iBetween);
    expect(html).toContain('class="fork-prose between-forks"');
  });
});
