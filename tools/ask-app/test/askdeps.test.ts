/**
 * ASKDEPS: two parser changes reported by meta:utils.
 * 1. A `DependsOn:` that names its own fork, or a ring of forks that wait on each other, makes forks
 *    that never show. invalidDependsOn refuses both, naming the forks, so `new` and `revise` refuse
 *    the body before anyone has to answer it.
 * 2. `Reversible:` indented under an option is that option's field (`option.reversible`), so the
 *    card can show a one-way badge per option. The fork-level `Reversible:` is unchanged.
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { newAsk, reviseAsk } from "../src/lib/store.ts";
import { duplicateForkNames, invalidDependsOn, parseAskFile } from "../src/lib/format.ts";

const head = `---\nid: d1\nto: operator\nfrom: meta:engine\nstatus: open\nrevision: 1\ncreated: 2026-10-31T10:00:00.000Z\n---\n\n`;
const fork = (name: string, title: string, dep?: string) =>
  `## ¶ASK_${name}: Choose one: ${title}\nContext: c\n${dep ? `DependsOn: ${dep}\n` : ""}- [ ] [YES] y\n  Picks YES.\n- [ ] [NO] n\n  Picks NO.\n`;
const deps = (...forks: string[]) => invalidDependsOn(parseAskFile(head + forks.join("\n")));

describe("ASKDEPS 1: DependsOn refuses a fork that waits on itself", () => {
  it("refuses DependsOn: ASK_A written under ¶ASK_A, naming the fork", () => {
    const out = deps(fork("A", "First?", "ASK_A"));
    expect(out).toHaveLength(1);
    expect(out[0]).toContain('"First?"');
    expect(out[0]).toContain("ASK_A");
    expect(out[0]).toMatch(/its own fork/);
  });
  it("refuses the self-reference with a code too (ASK_A=YES under ¶ASK_A)", () => {
    const out = deps(fork("A", "First?", "ASK_A=YES"));
    expect(out).toHaveLength(1);
    expect(out[0]).toMatch(/its own fork/);
  });
  it("nearest neighbour: a fork depending on a SIBLING fork still passes", () => {
    expect(deps(fork("A", "First?"), fork("B", "Second?", "ASK_A=YES"))).toEqual([]);
    expect(deps(fork("A", "First?"), fork("B", "Second?", "ASK_A"))).toEqual([]);
  });
});

describe("ASKDEPS 1: DependsOn refuses a cycle", () => {
  it("refuses A → B → A once, naming both forks", () => {
    const out = deps(fork("A", "First?", "ASK_B=YES"), fork("B", "Second?", "ASK_A=YES"));
    expect(out).toHaveLength(1);
    expect(out[0]).toMatch(/loop/);
    expect(out[0]).toContain('ASK_A ("First?")');
    expect(out[0]).toContain('ASK_B ("Second?")');
  });
  it("refuses a 3-cycle A → B → C → A once, naming all three in order", () => {
    const out = deps(fork("A", "A?", "ASK_B"), fork("B", "B?", "ASK_C"), fork("C", "C?", "ASK_A"));
    expect(out).toHaveLength(1);
    expect(out[0]).toContain('ASK_A ("A?") waits on ASK_B ("B?"), which waits on ASK_C ("C?"), which waits on ASK_A');
  });
  it("a legal chain A → B → C passes (C waits on B, B waits on A)", () => {
    expect(deps(fork("A", "A?"), fork("B", "B?", "ASK_A=YES"), fork("C", "C?", "ASK_B=NO"))).toEqual([]);
  });
  it("a fork hanging off a loop is not itself reported; the loop is", () => {
    const out = deps(fork("A", "A?", "ASK_B"), fork("B", "B?", "ASK_A"), fork("C", "C?", "ASK_A"));
    expect(out).toHaveLength(1);
    expect(out[0]).not.toContain("ASK_C");
  });
  it("the existing refusals still fire beside the new ones", () => {
    const out = deps(fork("A", "A?", "ASK_Z"));
    expect(out).toEqual(['"A?": DependsOn ASK_Z names no question in this ask']);
  });
});

describe("ASKDEPS 1: `engine ask new` refuses the body", () => {
  let root: string;
  beforeEach(() => {
    root = path.join(fs.mkdtempSync(path.join("/tmp", "askdeps-")), "asks");
  });
  afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));
  it("refuses a self-reference and a cycle at filing, and files the sibling case", () => {
    expect(() => newAsk(root, { from: "a:b", to: "operator", id: "s1" }, fork("A", "First?", "ASK_A"))).toThrow(/DependsOn refused: .*its own fork/);
    expect(() => newAsk(root, { from: "a:b", to: "operator", id: "s2" }, fork("A", "First?", "ASK_B") + "\n" + fork("B", "Second?", "ASK_A"))).toThrow(/DependsOn refused: .*loop/);
    expect(() => newAsk(root, { from: "a:b", to: "operator", id: "s3" }, fork("A", "First?") + "\n" + fork("B", "Second?", "ASK_A=YES"))).not.toThrow();
  });
  it("NIT-5: `revise` refuses a body that introduces a loop, and leaves the filed ask as it was", async () => {
    const f = newAsk(root, { from: "a:b", to: "operator", id: "r1" }, fork("A", "First?") + "\n" + fork("B", "Second?", "ASK_A"));
    const before = fs.readFileSync(f, "utf8");
    const push = async () => ({ status: "delivered" as const });
    await expect(reviseAsk(root, "a:b", "r1", {}, fork("A", "First?", "ASK_B") + "\n" + fork("B", "Second?", "ASK_A"), { by: "a:b", push })).rejects.toThrow(/DependsOn refused: .*loop/);
    expect(fs.readFileSync(f, "utf8")).toBe(before);
  });
  it("SHOULD-2 case A: a repeated fork name is refused as a duplicate, not as an invented loop", () => {
    const body = fork("A", "A1?") + "\n" + fork("A", "A2?", "ASK_B") + "\n" + fork("B", "B?", "ASK_A");
    expect(() => newAsk(root, { from: "a:b", to: "operator", id: "u1" }, body)).toThrow(/¶ASK_A names 2 forks \("A1\?", "A2\?"\)/);
    expect(() => newAsk(root, { from: "a:b", to: "operator", id: "u1" }, body)).not.toThrow(/loop/);
  });
  it("SHOULD-2 case B: a repeated name that DependsOn names is a duplicate, not a self-reference", () => {
    const body = fork("A", "A1?") + "\n" + fork("A", "A2?", "ASK_A");
    expect(() => newAsk(root, { from: "a:b", to: "operator", id: "u2" }, body)).toThrow(/¶ASK_A names 2 forks/);
    expect(() => newAsk(root, { from: "a:b", to: "operator", id: "u2" }, body)).not.toThrow(/its own fork/);
  });
});

describe("ASKDEPS SHOULD-2: duplicateForkNames", () => {
  it("names each repeated name once, with every fork that carries it", () => {
    const ask = parseAskFile(head + [fork("A", "A1?"), fork("B", "B?"), fork("A", "A2?"), fork("A", "A3?")].join("\n"));
    expect(duplicateForkNames(ask)).toEqual(['¶ASK_A names 3 forks ("A1?", "A2?", "A3?"), and a name has to pick out one fork, because answers and DependsOn find a fork by its name']);
  });
  it("control: distinct names and unnamed forks pass", () => {
    const unnamed = "## Choose one: Loose?\nContext: c\n- [ ] [YES] y\n  Picks YES.\n";
    expect(duplicateForkNames(parseAskFile(head + [fork("A", "A?"), fork("B", "B?"), unnamed, unnamed].join("\n")))).toEqual([]);
  });
});

describe("ASKDEPS 2: a per-option Reversible: line", () => {
  const ask = parseAskFile(
    head +
      "## ¶ASK_M: Choose one: Migrate?\nReversible: no — the fork as a whole\nContext: c\n" +
      "- [ ] [DROP] Drop the column\n  Removes it for good.\n  Reversible: no — the data is gone\n  Cost: an hour\n" +
      "- [ ] [KEEP] Keep it\n  Leaves it alone.\n",
  );
  const [drop, keep] = ask.questions[0].options;
  it("is parsed onto the option, and leaves the description now the card draws the field", () => {
    expect(drop.reversible).toBe("no — the data is gone");
    expect(drop.description).toBe("Removes it for good."); // WAKEUI: the card draws option.reversible, so it is no longer echoed
    expect(drop.cost).toBe("an hour");
  });
  it("an option without the line has no reversible", () => {
    expect(keep.reversible).toBeUndefined();
  });
  it("the fork-level Reversible: is unchanged", () => {
    expect(ask.questions[0].meta.reversible).toBe("no — the fork as a whole");
  });
});
