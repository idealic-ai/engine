/**
 * ASKFLOOR: the floor an author's ask must clear. Every decision fork explains itself in a paragraph
 * of its own (for the first fork the ask's opening paragraph counts, because its card shows it).
 * That is refused. Each option saying what picking it changes and what it costs is STAGED: warned
 * in this landing, refused in a later one. `engine ask new` and a body `revise` apply it (the CLI
 * passes floor: "author"); the store's default stays the structural floor its other callers rely on.
 *
 * Controls are real asks, copied body-only into fixtures: domain:Language's COLONBAN ask, which the
 * operator could not answer (positive control: refused), core:kernel's RAISEREND ask and app:deploy's
 * provider-keys ask, a single fork under a long opening paragraph (negative controls: pass).
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { newAsk, reviseAsk } from "../src/lib/store.ts";
import { AskFloorError, authorFloorProblems, authorWarnings, floorProblems, FORK_PARAGRAPH_MIN_WORDS, parseAskFile } from "../src/lib/format.ts";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const CLI = path.resolve(HERE, "..", "src", "cli.ts");
const COLONBAN = fs.readFileSync(path.join(HERE, "fixtures", "askfloor-colonban.body.md"), "utf8");
const RAISEREND = fs.readFileSync(path.join(HERE, "fixtures", "askfloor-raiserend.body.md"), "utf8");
const DEPLOY = fs.readFileSync(path.join(HERE, "fixtures", "askfloor-deploy-keys.body.md"), "utf8");
const SEAT = "domain:language";
const FIELDS = { from: SEAT, to: "operator" };
const AUTHOR = { floor: "author" as const };
const head = "---\nid: a\nto: operator\nfrom: domain:language\nstatus: open\nrevision: 1\ncreated: 2026-10-31T00:00:00.000Z\n---\n\n";
const problems = (body: string) => authorFloorProblems(parseAskFile(head + body));

/** A fork paragraph of exactly n words. */
const words = (n: number) => Array.from({ length: n }, (_, i) => `w${i}`).join(" ") + ".";
const PARA = "We must pick when the release goes out, because the hotfix is waiting on it and support is short this week.";
const GOOD = [
  "## ¶ASK_GO: Choose one: Ship it?",
  PARA,
  "- [ ] [YES] Ship",
  "  The release goes out tonight.",
  "  Cost: a night watch",
  "- [ ] [NO] Hold",
  "  Nothing ships.",
  "  Cost: the fix waits a week",
  "",
].join("\n");

let root: string;
beforeEach(() => (root = path.join(fs.mkdtempSync(path.join("/tmp", "asks-askfloor-")), "asks")));
afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));

describe("controls: two real asks", () => {
  it("COLONBAN (positive control) is refused: forks 2 and 3 have no paragraph of their own; fork 1 is covered by the opening paragraph its card shows", () => {
    let err: unknown;
    try {
      newAsk(root, { ...FIELDS, id: "c" }, COLONBAN, AUTHOR);
    } catch (e) {
      err = e;
    }
    expect(err).toBeInstanceOf(AskFloorError);
    const p = (err as AskFloorError).problems;
    for (const t of ["does an earlier entry's value run to the next `, word:`?", "titles that only repeat the name"]) {
      expect(p.some((x) => x.includes(`${t}": this fork has no paragraph of its own`))).toBe(true);
    }
    expect(p.some((x) => x.includes(`where does a title end?": this fork has no paragraph`))).toBe(false);
    expect(fs.existsSync(path.join(root, SEAT, "c.md"))).toBe(false);
  });

  it("COLONBAN's missing Cost: lines are warned, not refused, in this landing (staged)", () => {
    const p = authorFloorProblems(parseAskFile(head + COLONBAN));
    expect(p.some((x) => /Cost/.test(x))).toBe(false);
    const w = authorWarnings(parseAskFile(head + COLONBAN));
    expect(w.filter((x) => x.includes("options have no Cost: line"))).toHaveLength(3);
  });

  it("COLONBAN passed the old structural floor, which is the finding: the preamble and a Lean: line counted as each fork's context", () => {
    expect(floorProblems(parseAskFile(head + COLONBAN))).toEqual([]);
  });

  it("its headings put the fork name after the kind word too; the author floor reports that beside the rest, in one refusal", () => {
    let err: unknown;
    try {
      newAsk(root, { ...FIELDS, id: "c" }, COLONBAN, AUTHOR);
    } catch (e) {
      err = e;
    }
    expect((err as AskFloorError).problems[0]).toMatch(/^"## Choose one: ¶ASK_COLONBANEND — where does a title end\?": the fork's name comes after the kind word, so nothing can depend on it: write "## ¶ASK_COLONBANEND: Choose one: where does a title end\?"/);
  });

  it("app:deploy's provider-keys ask (negative control: one fork under a long opening paragraph) passes", () => {
    expect(problems(DEPLOY)).toEqual([]);
    expect(() => newAsk(root, { ...FIELDS, id: "d" }, DEPLOY, AUTHOR)).not.toThrow();
  });

  it("the shape most live asks take, one fork with a long opening and a Lean:, passes; the same fork with no opening is refused", () => {
    const fork = GOOD.replace(PARA + "\n", "Lean: YES\n");
    expect(problems(`${PARA} ${PARA}\n\n${fork}`)).toEqual([]);
    expect(problems(fork)[0]).toMatch(/"Ship it\?": this fork has no paragraph of its own \(it has 0 words/);
  });

  it("RAISEREND (negative control) passes the author floor", () => {
    expect(problems(RAISEREND)).toEqual([]);
    expect(() => newAsk(root, { ...FIELDS, id: "r" }, RAISEREND, AUTHOR)).not.toThrow();
  });
});

describe("each fork carries a paragraph of its own", () => {
  it("a good fork passes", () => {
    expect(problems(GOOD)).toEqual([]);
  });

  it("a Lean: line alone is not the paragraph", () => {
    const b = GOOD.replace(PARA, "Lean: YES");
    expect(problems(b)).toEqual([expect.stringContaining('"Ship it?": this fork has no paragraph of its own (it has 0 words')]);
  });

  it("the ask's opening paragraph counts for the first fork, whose card shows it, and for no later fork", () => {
    const bare = GOOD.replace(PARA + "\n", "");
    const second = bare.replace("ASK_GO", "ASK_GO2").replace("Ship it?", "Ship it later?");
    const p = problems(`**Context.** ${PARA} ${PARA}\n\n${bare}\n${second}`);
    expect(p).toEqual([expect.stringMatching(/^"Ship it later\?": this fork has no paragraph of its own.*shows the ask's opening paragraph only collapsed/)]);
  });

  it("the header's why counts for the first fork too", () => {
    const b = GOOD.replace(PARA + "\n", "");
    expect(authorFloorProblems(parseAskFile(head.replace("status: open\n", `status: open\nwhy: ${words(12)}\n`) + b))).toEqual([]);
  });

  it("code blocks and paths are not words; Counter: and Evidence: lines are", () => {
    const fence = "```text\n" + words(20) + "\n```";
    expect(problems(GOOD.replace(PARA, fence))[0]).toMatch(/it has 0 words/);
    expect(problems(GOOD.replace(PARA, "Context: ~/project/sessions/2026_10_29/builds/a_b/COLONBAN_PLAN.md and https://example.com/a/b/c/d")).length).toBe(1);
    expect(problems(GOOD.replace(PARA, `Counter: ${words(6)}\nEvidence: ${words(6)}`))).toEqual([]);
  });

  it(`counts the prose before the options with Context: and Stake: lines; ${FORK_PARAGRAPH_MIN_WORDS} words pass and one fewer is refused`, () => {
    expect(FORK_PARAGRAPH_MIN_WORDS).toBe(12);
    expect(problems(GOOD.replace(PARA, words(12)))).toEqual([]);
    expect(problems(GOOD.replace(PARA, words(11)))[0]).toMatch(/it has 11 words; it needs at least 12/);
    expect(problems(GOOD.replace(PARA, `Context: ${words(6)}\nStake: ${words(6)}`))).toEqual([]);
  });

  it("prose written after the options does not count, and the message says to move it above them", () => {
    const b = GOOD.replace(PARA + "\n", "") + `\n${PARA}\n`;
    expect(problems(b)[0]).toMatch(/before the options/);
  });

  it("the message says what to write, in plain words", () => {
    const [m] = problems(GOOD.replace(PARA, "Lean: YES"));
    expect(m).toMatch(/write two or three sentences: what is being decided, and why it matters/);
    expect(m).toMatch(/The opening paragraph above the first fork counts for it\./);
  });

  it("Yes or no and Rank forks need it too; Text, Number and Date forks only warn", () => {
    expect(problems("## ¶ASK_OK: Yes or no: Lock it?\nLean: YES\n")[0]).toMatch(/"Lock it\?": this fork has no paragraph/);
    expect(problems("## ¶ASK_R: Rank: Order these\n- [ ] [A] a\n- [ ] [B] b\n")[0]).toMatch(/"Order these": this fork has no paragraph/);
    expect(problems(`${GOOD}\n## ¶ASK_WHY: Text: Anything else?\n`)).toEqual([]);
    const w = authorWarnings(parseAskFile(head + `${GOOD}\n## ¶ASK_WHY: Text: Anything else?\n`));
    expect(w).toContainEqual(expect.stringContaining('"Anything else?": no paragraph of its own'));
  });
});

describe("each option says what picking it changes and what it costs (staged: warned now, refused later)", () => {
  const warns = (body: string) => authorWarnings(parseAskFile(head + body));
  it("an option with no Cost: line files, and the warning counts it", () => {
    const b = GOOD.replace("  Cost: the fix waits a week\n", "");
    expect(problems(b)).toEqual([]);
    expect(warns(b)).toContainEqual(expect.stringContaining('"Ship it?": 1 of 2 options have no Cost: line'));
  });

  it("a Cost: line that says what happens counts as the change line (S1)", () => {
    const b = GOOD.replace("  Nothing ships.\n", "");
    expect(problems(b)).toEqual([]);
    expect(warns(b).filter((x) => x.includes("nothing says what picking it changes"))).toEqual([]);
  });

  it("an Elegance: or Unblocks: line alone is not a change line, and is warned; a Then: line is one", () => {
    const only = (lines: string) => GOOD.replace("  Nothing ships.\n  Cost: the fix waits a week\n", lines);
    for (const l of ["  Elegance: low — two paths\n", "  Unblocks: IDE-1\n"]) {
      expect(problems(only(l))).toEqual([]);
      expect(warns(only(l))).toContainEqual(expect.stringMatching(/\[NO\]: nothing says what picking it changes.*refused in a later landing/));
    }
    expect(warns(only("  Then: queue it behind IDE-1\n")).filter((x) => x.includes("nothing says what"))).toEqual([]);
  });

  it("a bare option is still refused, with a placeholder rather than an example to copy", () => {
    const p = problems(GOOD.replace("  Nothing ships.\n  Cost: the fix waits a week\n", ""));
    expect(p).toHaveLength(1);
    expect(p[0]).toMatch(/\[NO\]: a bare option: .*"  <what changes if this is picked>" then "  Cost: <what the person answering gives up>"/);
  });

  it("Rank options are names to order and owe neither", () => {
    expect(problems(`## ¶ASK_R: Rank: Order these\n${PARA}\n- [ ] [A] a\n- [ ] [B] b\n`)).toEqual([]);
  });
});

describe("a concrete example is a warning, not a refusal", () => {
  it("warns when a choice fork shows nothing in backticks or a fence, and says when an example helps", () => {
    const w = authorWarnings(parseAskFile(head + GOOD));
    expect(w).toContainEqual(expect.stringMatching(/"Ship it\?": no concrete example\. If this fork is about syntax, a file, a command or a value/));
  });

  it("says nothing when the fork's paragraph or an option shows one", () => {
    const inline = GOOD.replace(PARA, `${PARA} Today it reads \`ship --now\`.`);
    expect(authorWarnings(parseAskFile(head + inline)).filter((x) => x.includes("no concrete example"))).toEqual([]);
    const opt = GOOD.replace("  The release goes out tonight.", "  Runs `ship --now` tonight.");
    expect(authorWarnings(parseAskFile(head + opt)).filter((x) => x.includes("no concrete example"))).toEqual([]);
  });
});

describe("where it applies", () => {
  it("revise with a new body is refused under the author floor and keeps the file as it was", async () => {
    const file = newAsk(root, { ...FIELDS, id: "a" }, GOOD, AUTHOR);
    const before = fs.readFileSync(file, "utf8");
    await expect(reviseAsk(root, SEAT, "a", {}, COLONBAN, { by: SEAT, ...AUTHOR })).rejects.toThrow(AskFloorError);
    expect(fs.readFileSync(file, "utf8")).toBe(before);
  });

  it("the refusal's first line states the floor", () => {
    expect(() => newAsk(root, { ...FIELDS, id: "c" }, COLONBAN, AUTHOR)).toThrow(/^under the ask floor \(each fork says in a paragraph of its own what is being decided and why it matters\)/);
  });

  it("`engine ask new` (the CLI) applies it: COLONBAN exits 1 with the messages, RAISEREND files", () => {
    const run = (id: string, body: string) => spawnSync(process.execPath, ["--no-warnings", CLI, "new", "--from", SEAT, "--to", "operator", "--id", id, "--root", root], {
      input: body, encoding: "utf8", env: { ...process.env, FLEET_PANE: SEAT, FLEET_PARENT: "", TMUX_PANE: "", ASK_ROOT: root },
    });
    const bad = run("c", COLONBAN);
    expect(bad.status).toBe(1);
    expect(bad.stderr).toMatch(/does an earlier entry's value run to the next `, word:`\?": this fork has no paragraph of its own/);
    expect(bad.stderr).toMatch(/titles that only repeat the name": this fork has no paragraph of its own/);
    const good = run("r", RAISEREND);
    expect(good.stderr).toBe("");
    expect(good.status).toBe(0);
  });
});

describe("`engine ask revise` (the CLI) applies it too (S4)", () => {
  it("a body revise to COLONBAN is refused with the --keep-body hint and leaves the file as it was; a --keep-body revise then goes through", () => {
    const env = { ...process.env, FLEET_PANE: SEAT, FLEET_PARENT: "", TMUX_PANE: "", ASK_ROOT: root };
    const cli = (args: string[], input = "") => spawnSync(process.execPath, ["--no-warnings", CLI, ...args, "--root", root], { input, encoding: "utf8", env });
    expect(cli(["new", "--to", "operator", "--id", "rv"], GOOD).status).toBe(0);
    const file = path.join(root, SEAT, "rv.md");
    const before = fs.readFileSync(file, "utf8");
    const bad = cli(["revise", `${SEAT}/rv`], COLONBAN);
    expect(bad.status).toBe(1);
    expect(bad.stderr).toMatch(/titles that only repeat the name": this fork has no paragraph of its own/);
    expect(bad.stderr).toMatch(/pass --keep-body/);
    expect(fs.readFileSync(file, "utf8")).toBe(before);
    const card = cli(["revise", `${SEAT}/rv`, "--keep-body", "--stake", "card only"]);
    expect(card.status).toBe(0);
    expect(fs.readFileSync(file, "utf8")).toMatch(/stake: card only/);
  });
});

describe("the app: the ask's opening context is reachable from every fork card", () => {
  const stored = (text: string) => ({ ...parseAskFile(text), seat: SEAT, file: "/x.md", mtimeMs: 0 });

  it("fork 1 shows it inline; forks 2 and 3 carry a collapsed 'What this ask is about' with the same text", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const a = stored(head + COLONBAN);
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    const cards = html.split('<article class="fork"').slice(1);
    expect(cards).toHaveLength(3);
    expect(cards[0]).toContain('class="rich preamble"');
    expect(cards[0]).not.toContain("What this ask is about");
    for (const c of cards.slice(1)) {
      expect(c).toMatch(/<details class="evidence ask-about"><summary>What this ask is about<\/summary>/);
      expect(c).toContain("67 tracked lines");
    }
  });

  it("an ask with no opening paragraph adds nothing to its cards", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const a = stored(head + GOOD + "\n" + GOOD.replace("ASK_GO", "ASK_GO2"));
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    expect(html).not.toContain("What this ask is about");
  });
});

describe("the docs' own examples are fileable", () => {
  const SKILL_DIR = path.resolve(HERE, "..", "..", "..", "skills", "ask");
  const docs = [path.join(SKILL_DIR, "SKILL.md"), path.join(SKILL_DIR, "assets", "ASK_AUTHOR_GUIDE.md")];
  /** Every example body: a heredoc fed to `engine ask new`, or a fenced block holding a fork heading. */
  function examples(file: string): { at: string; body: string }[] {
    const text = fs.readFileSync(file, "utf8");
    const out: { at: string; body: string }[] = [];
    for (const m of text.matchAll(/engine ask new[^\n]*(?:\n[^\n]*)*?<<'EOF'\n([\s\S]*?)\nEOF\n/g)) out.push({ at: `${path.basename(file)} heredoc @${m.index}`, body: m[1] });
    for (const m of text.matchAll(/^(`{3,4})(?:md|markdown)?\n([\s\S]*?)^\1$/gm)) {
      if (/^## (?:¶ASK_\w+: )?(?:Choose one|Choose|Rank|Yes or no):/m.test(m[2])) out.push({ at: `${path.basename(file)} block @${m.index}`, body: m[2].replace(/^---\n[\s\S]*?\n---\n/, "") });
    }
    return out;
  }
  /** The two "before" blocks the docs show on purpose, to be refused. */
  const isBefore = (b: string) => b.includes("¶ASK_COLONBANEND") || b.includes("## Choose one: IDE-264 (D8 row-id refusal)");

  it("finds the examples it means to check (control: the count is not zero)", () => {
    const all = docs.flatMap(examples);
    expect(all.filter((e) => isBefore(e.body))).toHaveLength(2);
    expect(all.filter((e) => !isBefore(e.body)).length).toBeGreaterThanOrEqual(4);
  });

  it("every example the docs recommend clears the author floor, and each 'before' is refused", () => {
    for (const e of docs.flatMap(examples)) {
      const p = problems(e.body);
      if (isBefore(e.body)) expect(p.length, e.at).toBeGreaterThan(0);
      else expect(p, e.at).toEqual([]);
    }
  });
});

describe("the header's context and stakes count for the first fork, whose card shows them", () => {
  const bare = GOOD.replace(PARA + "\n", "");
  const withHeader = (extra: string, body: string) => authorFloorProblems(parseAskFile(head.replace("status: open\n", `status: open\n${extra}`) + body));
  it("a first fork with only header context and stakes passes", () => {
    expect(withHeader(`context: ${words(6)}\nstakes: ${words(6)}\n`, bare)).toEqual([]);
  });
  it("a second fork does not borrow them", () => {
    const p = withHeader(`context: ${words(6)}\nstakes: ${words(6)}\n`, `${bare}\n${bare.replace("ASK_GO", "ASK_GO2").replace("Ship it?", "Ship it later?")}`);
    expect(p).toEqual([expect.stringMatching(/^"Ship it later\?": this fork has no paragraph of its own/)]);
  });
});
