/**
 * ASKTREE TEACH: the examples agents copy from the ask skill and the author guide clear the floor
 * `new` enforces, and the guide teaches the per-option fields the parser reads.
 */
import { describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { floorProblems, forkNameAfterKind, parseAskFile } from "../src/lib/format.ts";

const ASK = path.join(import.meta.dirname, "..", "..", "..", "skills", "ask");
const SKILL = fs.readFileSync(path.join(ASK, "SKILL.md"), "utf8");
const GUIDE = fs.readFileSync(path.join(ASK, "assets", "ASK_AUTHOR_GUIDE.md"), "utf8");
const HEAD = "---\nid: x\nto: operator\nfrom: a:b\nstatus: open\nrevision: 1\n---\n\n";

/** Every fenced block holding a fork heading: a heredoc's body (preamble and all), else from the first `## ` line. */
function askBlocks(md: string): string[] {
  const out: string[] = [];
  for (const m of md.matchAll(/^```[a-z]*\n([\s\S]*?)^```$/gm)) {
    const lines = m[1].split("\n");
    if (!lines.some((l) => /^## /.test(l))) continue;
    const heredoc = lines.findIndex((l) => /<<'EOF'$/.test(l));
    const at = heredoc !== -1 ? heredoc + 1 : lines.findIndex((l) => /^## /.test(l));
    out.push(lines.slice(at).filter((l) => l !== "EOF").join("\n"));
  }
  return out;
}
const problems = (body: string) => [...forkNameAfterKind(parseAskFile(HEAD + body)).map((f) => f.wrote), ...floorProblems(parseAskFile(HEAD + body))];

describe("the examples clear the floor", () => {
  it("every SKILL.md example body files", () => {
    const blocks = askBlocks(SKILL);
    expect(blocks.length).toBeGreaterThanOrEqual(3);
    for (const b of blocks) expect(problems(b)).toEqual([]);
  });

  it("the guide's examples file, except the worked example's labelled Before", () => {
    const blocks = askBlocks(GUIDE);
    const before = blocks.filter((b) => b.startsWith("## Choose one: IDE-264"));
    expect(before).toHaveLength(1);
    expect(problems(before[0]).length).toBeGreaterThan(0);
    const rest = blocks.filter((b) => !before.includes(b));
    expect(rest.length).toBeGreaterThanOrEqual(1);
    for (const b of rest) expect(problems(b)).toEqual([]);
  });

  it("control: the check fires on an example with its context and preamble taken out", () => {
    const b = askBlocks(SKILL).find((x) => x.includes("ASK_LAYOUT"))!.replace(/^[\s\S]*?(?=^## )/m, "");
    expect(problems(b.replace(/^Context: given one file per ask.*\n/m, ""))).toContain('"Which id parts?": a fork needs context: add a Context: line under the heading (or Stake:, Lean:, a line of prose, or a preamble above the first fork) saying what the decider must know');
  });
});

describe("the guide teaches the per-option fields", () => {
  it("names Elegance as a driving factor and teaches Then and per-option Unblocks", () => {
    expect(GUIDE).toMatch(/## Give every answer its own context/);
    expect(GUIDE).toMatch(/`Elegance:` is a driving factor/);
    expect(GUIDE).toMatch(/\*\*`Then:`\*\*/);
    expect(GUIDE).toMatch(/\*\*`Unblocks:`\*\* under an option/);
    expect(GUIDE).not.toMatch(/Coming with ASK v2 H4, not read yet:[^\n]*`Unblocks:`/);
  });

  it("the checklist asks for Cost and Elegance on every option and the name before the kind word", () => {
    const list = GUIDE.slice(GUIDE.indexOf("## Before you run `engine ask new`"));
    expect(list).toMatch(/- \[ \] Every option has a description saying what changes, a `Cost:` and an `Elegance:`/);
    expect(list).toMatch(/the name before the kind word/);
  });
});
