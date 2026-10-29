import { describe, expect, it } from "vitest";
import {
  parseAskFile,
  writeAnswer,
  visibleQuestions,
  visibleAsks,
  questionKey,
  setHeaderField,
  type AskAnswer,
} from "../src/lib/format.ts";

const SAMPLE = `---
id: 20261028-ask-format
to: manager:director
from: idealic:kernel
why: the store layout blocks two lanes
importance: high
stakes: a wrong layout means migrating every ask file later
context: see builds/ask_BUILD.md
alternatives: one file per seat; one file per ask
lean: one file per ask
falsifier: two asks need to be answered atomically together
status: open
revision: 1
dependsOn:
---

Some free prose the asker wants the answerer to read first.

## ¶ASK_LAYOUT: Choose one: Where do ask files live?
- [ ] [ONE] One file per ask
  Simple to move up the chain.
  - [ ] [FLAT] Flat under the seat
  - [ ] [DATE] Bucketed by date
- [ ] [SEAT] One file per seat

## ¶ASK_NAMING: Choose: Which id parts?
DependsOn: ASK_LAYOUT=ONE
- [ ] [TS] Timestamp
- [ ] [SLG] Slug

## Choose one: Anything else?
- [ ] Nothing
- [ ] Something
`;

describe("parseAskFile", () => {
  it("reads every header field, keeping empty values as empty strings", () => {
    const ask = parseAskFile(SAMPLE);
    expect(ask.header.id).toBe("20261028-ask-format");
    expect(ask.header.to).toBe("manager:director");
    expect(ask.header.from).toBe("idealic:kernel");
    expect(ask.header.importance).toBe("high");
    expect(ask.header.falsifier).toBe("two asks need to be answered atomically together");
    expect(ask.header.status).toBe("open");
    expect(ask.header.revision).toBe("1");
    expect(ask.header.dependsOn).toBe("");
  });

  it("keeps the prose before the first question as the preamble", () => {
    expect(parseAskFile(SAMPLE).preamble.trim()).toBe(
      "Some free prose the asker wants the answerer to read first.",
    );
  });

  it("parses the decision-tree questions with codes, descriptions and nesting", () => {
    const { questions } = parseAskFile(SAMPLE);
    expect(questions).toHaveLength(3);
    const [layout, naming, other] = questions;
    expect(layout.askName).toBe("LAYOUT");
    expect(layout.title).toBe("Where do ask files live?");
    expect(layout.multiSelect).toBe(false);
    expect(layout.options.map((o) => o.code)).toEqual(["ONE", "SEAT"]);
    expect(layout.options[0].description).toBe("Simple to move up the chain.");
    expect(layout.options[0].children?.map((o) => o.code)).toEqual(["FLAT", "DATE"]);
    expect(naming.multiSelect).toBe(true);
    expect(naming.dependsOn).toEqual({ ask: "LAYOUT", code: "ONE" });
    expect(other.askName).toBeUndefined();
    expect(other.options.map((o) => o.label)).toEqual(["Nothing", "Something"]);
  });

  it("has no answer while the file carries no json answer block", () => {
    expect(parseAskFile(SAMPLE).answer).toBeUndefined();
  });

  it("refuses a file with no header block", () => {
    expect(() => parseAskFile("## Choose one: x\n- [ ] a\n")).toThrow(/header/);
  });

  it("does not read a question heading that sits inside a code fence", () => {
    const text = SAMPLE + "\n```md\n## Choose one: fenced\n- [ ] no\n```\n";
    expect(parseAskFile(text).questions).toHaveLength(3);
  });
});

describe("questionKey", () => {
  it("uses the ask name when there is one and the position otherwise", () => {
    const { questions } = parseAskFile(SAMPLE);
    expect(questions.map((q, i) => questionKey(q, i))).toEqual(["LAYOUT", "NAMING", "q2"]);
  });
});

const ANSWER: AskAnswer = {
  answers: { LAYOUT: ["ONE", "FLAT"], NAMING: ["TS"], q2: ["Nothing"] },
  note: "go flat",
  answeredBy: "operator",
  answeredAt: "2026-10-28T22:00:00.000Z",
};

describe("writeAnswer", () => {
  it("embeds the answer as a fenced json answer block and marks the file answered", () => {
    const out = writeAnswer(SAMPLE, ANSWER);
    const ask = parseAskFile(out);
    expect(ask.header.status).toBe("answered");
    expect(ask.answer).toEqual({ ...ANSWER, revision: 2 });
    expect(out).toMatch(/```json answer\n/);
  });

  it("bumps the revision", () => {
    expect(parseAskFile(writeAnswer(SAMPLE, ANSWER)).header.revision).toBe("2");
  });

  it("leaves the questions and the other header fields untouched", () => {
    const before = parseAskFile(SAMPLE);
    const after = parseAskFile(writeAnswer(SAMPLE, ANSWER));
    expect(after.questions).toEqual(before.questions);
    const { status: _s, revision: _r, ...restBefore } = before.header;
    const { status: _s2, revision: _r2, ...restAfter } = after.header;
    expect(restAfter).toEqual(restBefore);
  });

  it("replaces an earlier answer instead of stacking a second block", () => {
    const once = writeAnswer(SAMPLE, ANSWER);
    const twice = writeAnswer(once, { ...ANSWER, note: "changed my mind" });
    expect(twice.match(/```json answer/g)).toHaveLength(1);
    expect(parseAskFile(twice).answer?.note).toBe("changed my mind");
    expect(parseAskFile(twice).header.revision).toBe("3");
  });

  it("refuses to answer a superseded ask", () => {
    const superseded = setHeaderField(SAMPLE, "status", "superseded");
    expect(() => writeAnswer(superseded, ANSWER)).toThrow(/superseded/);
  });
});

describe("setHeaderField", () => {
  it("rewrites an existing field and appends a missing one inside the header", () => {
    const moved = setHeaderField(SAMPLE, "to", "operator");
    expect(parseAskFile(moved).header.to).toBe("operator");
    const marked = setHeaderField(SAMPLE, "delivery", "undelivered");
    const ask = parseAskFile(marked);
    expect(ask.header.delivery).toBe("undelivered");
    expect(ask.questions).toHaveLength(3);
  });
});

describe("visibleQuestions", () => {
  it("hides a question until the one it depends on is answered with the named code", () => {
    const { questions } = parseAskFile(SAMPLE);
    expect(visibleQuestions(questions, {}).map((q) => q.title)).toEqual([
      "Where do ask files live?",
      "Anything else?",
    ]);
    expect(visibleQuestions(questions, { LAYOUT: ["SEAT"] })).toHaveLength(2);
    expect(visibleQuestions(questions, { LAYOUT: ["ONE"] })).toHaveLength(3);
  });

  it("shows a question with a bare dependency once the other has any answer", () => {
    const text = SAMPLE.replace("DependsOn: ASK_LAYOUT=ONE", "DependsOn: ASK_LAYOUT");
    const { questions } = parseAskFile(text);
    expect(visibleQuestions(questions, {})).toHaveLength(2);
    expect(visibleQuestions(questions, { LAYOUT: ["SEAT"] })).toHaveLength(3);
  });
});

describe("visibleAsks", () => {
  const mk = (id: string, status: string, dependsOn = "") =>
    parseAskFile(
      SAMPLE.replace("id: 20261028-ask-format", `id: ${id}`)
        .replace("status: open", `status: ${status}`)
        .replace("dependsOn:", `dependsOn: ${dependsOn}`),
    );

  it("hides an ask until the ask it depends on is answered", () => {
    const first = mk("a1", "open");
    const second = mk("a2", "open", "a1");
    expect(visibleAsks([first, second]).map((a) => a.header.id)).toEqual(["a1"]);
    const answered = mk("a1", "answered");
    expect(visibleAsks([answered, second]).map((a) => a.header.id)).toEqual(["a1", "a2"]);
  });

  it("shows an ask whose dependency is not in the set, rather than hiding it forever", () => {
    expect(visibleAsks([mk("a2", "open", "gone")]).map((a) => a.header.id)).toEqual(["a2"]);
  });
});

import { validateAnswer, writeDecline, StaleRevisionError } from "../src/lib/format.ts";

describe("validateAnswer (INV_REFUSAL_IS_NOT_EMPTY)", () => {
  const ask = parseAskFile(SAMPLE);
  it("accepts known keys with known codes, labels, and a .other free-text string", () => {
    expect(() => validateAnswer(ask, { LAYOUT: ["ONE", "FLAT"], q2: ["Nothing"], "LAYOUT.other": "flat please" })).not.toThrow();
  });
  it.each([
    ["null", null],
    ["an array", []],
    ["an empty object", {}],
    ["an unknown key", { NOPE: ["ONE"] }],
    ["an unknown code", { LAYOUT: ["ZZZ"] }],
    ["an empty selection", { LAYOUT: [] }],
    ["a blank free text", { "LAYOUT.other": "  " }],
  ])("refuses %s", (_n, answers) => {
    expect(() => validateAnswer(ask, answers as never)).toThrow();
  });
});

describe("writeDecline", () => {
  it("records a declined status with its reason in the json answer block", () => {
    const out = writeDecline(SAMPLE, { reason: "beyond my grant; take it to the operator", answeredBy: "manager:idealic" });
    const ask = parseAskFile(out);
    expect(ask.header.status).toBe("declined");
    expect(ask.answer?.declined).toBe(true);
    expect(ask.answer?.reason).toMatch(/beyond my grant/);
  });
  it("refuses a decline without a reason", () => {
    expect(() => writeDecline(SAMPLE, { reason: "  " })).toThrow(/reason/);
  });
});

describe("compare-and-swap on revision (INV_ONE_CHOSEN_DESTINATION)", () => {
  it("refuses an answer whose expected revision is stale", () => {
    const once = writeAnswer(SAMPLE, ANSWER, 1);
    expect(() => writeAnswer(once, ANSWER, 1)).toThrow(StaleRevisionError);
    expect(() => writeAnswer(once, ANSWER, 2)).not.toThrow();
  });
});

describe("answer block in an open ask", () => {
  it("is ignored unless the status says answered or declined", () => {
    const planted = SAMPLE + '\n```json answer\n{"answers":{"LAYOUT":["ONE"]}}\n```\n';
    expect(parseAskFile(planted).answer).toBeUndefined();
  });
});
