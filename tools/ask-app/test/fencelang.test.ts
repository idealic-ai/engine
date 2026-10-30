/**
 * FENCELANG: every fenced code block an author writes into an ask carries a language, so the
 * browser can highlight it. `new` and `revise` refuse a fence opened with no info string, naming
 * each opening line of the body; `text` is the tag when nothing fits. The store's own record fences
 * (`json answer`, `json history`) carry a tag already. An ask already on disk is never refused on
 * this: reads, answers and lists parse it as before.
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { listAsks, newAsk, readAsk, reviseAsk } from "../src/lib/store.ts";
import { authorWarnings, parseAskFile, untaggedFenceLines, UntaggedFenceError } from "../src/lib/format.ts";

const GO = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n";
const push = async () => ({ status: "delivered" as const });

let root: string;
beforeEach(() => {
  root = path.join(fs.mkdtempSync(path.join("/tmp", "askfencelang-")), "asks");
});
afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));

const mk = (id: string, body: string) => newAsk(root, { from: "a:b", to: "operator", id }, body);

describe("untaggedFenceLines", () => {
  it("names the 1-based body line of each opener with no info string, never a closer", () => {
    expect(untaggedFenceLines("intro\n\n```\nx\n```\n\n```ts\ny\n```\n~~~\nz\n~~~\n")).toEqual([3, 10]);
  });
  it("a longer fence holds a shorter untagged run as content", () => {
    expect(untaggedFenceLines("````md\n```\ninner\n```\n````\n")).toEqual([]);
  });
  it("a backtick run whose info holds a backtick is inline code, not a fence (CommonMark)", () => {
    // Without the rule, "```a`b" opens a phantom fence and the bare run after it reads as its closer.
    expect(untaggedFenceLines("```a`b\nx\n```")).toEqual([3]);
    // A prose line that starts with inline code must not shift the pairing of the fences after it:
    // read as a phantom fence, it is closed by the inner bare run and the next one reads as an opener.
    const body = "```npm test``` is the command\n\n````md\n```\ninner\n```\n````\n";
    expect(untaggedFenceLines(body)).toEqual([]);
    expect(() => mk("bt1", GO + "\n" + body)).not.toThrow();
    // A tilde fence may hold a backtick in its info; it is a fence, and tagged.
    expect(untaggedFenceLines("~~~a`b\nx\n~~~\n")).toEqual([]);
  });
  it("an indented fence under an option counts", () => {
    expect(untaggedFenceLines("## ¶ASK_Q: Choose one: Q?\n- [ ] [A] a\n  ```\n  code\n  ```\n- [ ] [B] b\n")).toEqual([3]);
  });
});

describe("new refuses an untagged fence", () => {
  it("naming the line, with the text hint, and writes nothing", () => {
    const body = "Context first.\n\n```\nnpm test\n```\n\n" + GO;
    let err: unknown;
    try {
      mk("u1", body);
    } catch (e) {
      err = e;
    }
    expect(err).toBeInstanceOf(UntaggedFenceError);
    expect((err as UntaggedFenceError).lines).toEqual([3]);
    expect((err as Error).message).toBe("line 3: fenced block has no language; write ```text if nothing fits");
    expect(fs.existsSync(path.join(root, "a:b", "u1.md"))).toBe(false);
  });

  it("names every untagged line, one per row", () => {
    const body = GO + "\n```\na\n```\n\n```sh\nb\n```\n\n~~~\nc\n~~~\n";
    expect(() => mk("u2", body)).toThrow(
      "line 5: fenced block has no language; write ```text if nothing fits\nline 13: fenced block has no language; write ```text if nothing fits",
    );
  });

  it("a fence indented under an option counts too", () => {
    const body = "## ¶ASK_Q: Choose one: Which shape?\n- [ ] [A] Tuple\n  The caller destructures it.\n  ```\n  const [ok, err] = run();\n  ```\n- [ ] [B] Throw\n";
    expect(() => mk("u3", body)).toThrow("line 4: fenced block has no language");
  });

  it("a fence left open at the end adds a mispairing hint naming its line", () => {
    // A fork line opened with a backtick in its info is not a fence to the checker, so the bare run
    // meant to close it is named as an untagged opener and is still open at the end of the body.
    const body = "## ¶ASK_Q: Choose one: X?\n- [ ] [A] a\n```a`b\n- [ ] [B] b\n```\n";
    let err: unknown;
    try {
      mk("mp1", body);
    } catch (e) {
      err = e;
    }
    expect(err).toBeInstanceOf(UntaggedFenceError);
    expect((err as UntaggedFenceError).lines).toEqual([5]);
    expect((err as Error).message.split("\n")).toEqual([
      "line 5: fenced block has no language; write ```text if nothing fits",
      "fences may be mispaired: the fence opened on line 5 is never closed; if line 5 is meant to close a block, check the fence that opens before it",
    ]);
  });

  it("an unclosed fence under an option shifts the pairing: the closer named is hinted at", () => {
    // Line 3 never closes, so line 7 reads as its closer and line 9, really a closer, as a bare opener.
    const body = "## ¶ASK_Q: Choose one: Q?\n- [ ] [A] a\n  ```ts\n  oops\n- [ ] [B] b\n\n```\nx\n```\n";
    expect(() => mk("mp2", body)).toThrow(
      "line 9: fenced block has no language; write ```text if nothing fits\nfences may be mispaired: the fence opened on line 9 is never closed",
    );
  });

  it("a well-paired refusal carries no mispairing hint", () => {
    expect(() => mk("mp3", GO + "\n```\na\n```\n")).toThrow(/^line 5: fenced block has no language; write ```text if nothing fits$/);
  });

  it("tagged fences pass, top-level and indented, and `text` is a tag", () => {
    const body = "```text\nplain\n```\n\n## ¶ASK_Q: Choose one: Which?\n- [ ] [A] a\n  ```ts\n  x()\n  ```\n- [ ] [B] b\n  ~~~sh\n  ls\n  ~~~\n";
    expect(() => mk("t1", body)).not.toThrow();
  });

  it("record fences are exempt from this rule (they are refused by M1 as records, not as untagged)", () => {
    const body = GO + "\n```json answer\n{}\n```\n";
    expect(() => mk("r1", body)).toThrow("those are records the store writes");
    expect(() => mk("r1", body)).not.toThrow(UntaggedFenceError);
  });

  it("an unclosed tagged fence is still accepted and still warned, as before", () => {
    const body = "## ¶ASK_Q: Choose one: Q?\nLean: A\n- [ ] [A] a\n  ```ts\n  oops\n- [ ] [B] b\n";
    const file = mk("w1", body);
    expect(authorWarnings(parseAskFile(fs.readFileSync(file, "utf8")))).toContain(
      '"Q?": a code fence is never closed, so everything after it, later forks included, is read as code',
    );
  });
});

describe("revise refuses the same; an ask already on disk is not refused", () => {
  const legacy = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n  ```\n  old untagged\n  ```\n- [ ] [NO] No\n";
  const plantLegacy = (id: string) => {
    // Written as an older engine would have: straight to disk, past the new refusal.
    const file = path.join(root, "a:b", `${id}.md`);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, `---\nid: ${id}\nto: operator\nfrom: a:b\nstatus: open\nrevision: 1\n---\n\n${legacy}`);
    return file;
  };

  it("revise with an untagged body is refused naming the line, and the file is unchanged", async () => {
    const file = mk("v1", GO);
    const before = fs.readFileSync(file, "utf8");
    await expect(reviseAsk(root, "a:b", "v1", {}, "Note:\n```\nx\n```\n" + GO, { by: "a:b", push })).rejects.toThrow(
      "line 2: fenced block has no language; write ```text if nothing fits",
    );
    await expect(reviseAsk(root, "a:b", "v1", {}, "```\nx\n```\n" + GO, { by: "a:b", push })).rejects.toBeInstanceOf(UntaggedFenceError);
    expect(fs.readFileSync(file, "utf8")).toBe(before);
  });

  it("a legacy ask with an untagged fence still lists, reads, and revises its card with the body kept", async () => {
    plantLegacy("old1");
    expect(listAsks(root).map((a) => a.header.id)).toContain("old1");
    expect((await readAsk(root, "a:b", "old1")).ask.questions[0].options.map((o) => o.code)).toEqual(["YES", "NO"]);
    const r = await reviseAsk(root, "a:b", "old1", { stakes: "two lanes" }, undefined, { by: "a:b", push });
    expect(r.changed).toEqual(["stakes"]);
  });
});
