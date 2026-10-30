/**
 * ASKTREE: the option grammar carries per-answer context, and `new` / `revise` keep a floor under it.
 * TRAPS — an indented bullet under an option is its description, never a phantom option; a codeless
 * nested option warns; a fork named after its kind word is refused with the fix.
 * FLOOR — a bare option and a fork with no context of its own are refused; an option with no Cost or
 * no Elegance warns. FIELDS — per-option `Unblocks:`, `Then:` and `Elegance:` are parsed and served.
 */
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { AskFloorError, authorWarnings, ForkNameOrderError, parseAskFile, type AskOption } from "../src/lib/format.ts";
import { listAsks, newAsk, reviseAsk } from "../src/lib/store.ts";
import { BUILD_ID_FILE, computeBuildId } from "../src/build-id.ts";

const HEAD = "---\nid: t1\nto: operator\nfrom: idealic:kernel\nstatus: open\nrevision: 1\n---\n\n";
const parse = (body: string) => parseAskFile(HEAD + body);
const SEAT = "idealic:kernel";
const FIELDS = { from: SEAT, to: "operator" };
let root: string;
beforeEach(() => (root = path.join(fs.mkdtempSync(path.join("/tmp", "asks-asktree-")), "asks")));
afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));

/** A body that clears the floor: context on the fork, a description, Cost and Elegance on each option. */
const GOOD = [
  "## ¶ASK_GO: Choose one: Ship it?",
  "Context: the build is green on main.",
  "- [ ] [YES] Ship",
  "  The release goes out tonight.",
  "  Cost: a night watch",
  "  Elegance: one release path, no special case",
  "- [ ] [NO] Hold",
  "  Nothing ships.",
  "  Cost: the fix waits a week",
  "  Elegance: leaves the hotfix branch as a second path",
  "",
].join("\n");

describe("TRAPS: an indented bullet under an option is description text", () => {
  const body = [
    "## ¶ASK_P: Choose one: Which?",
    "Context: c",
    "- [ ] [P] Do P",
    "  What changes:",
    "  - the writer moves",
    "  - the board breaks",
    "  Cost: two files",
    "- [ ] [Q] Do Q",
    "  Q is smaller.",
    "  Cost: none",
    "",
  ].join("\n");

  it("keeps the bullets in P's description as a markdown list, makes no children, and still reads Cost after them", () => {
    const [p, q] = parse(body).questions[0].options;
    expect(p.children).toBeUndefined();
    expect(p.description).toBe("What changes:\n\n- the writer moves\n- the board breaks");
    expect(p.cost).toBe("two files");
    expect(q.code).toBe("Q");
    expect(parse(body).questions[0].options).toHaveLength(2);
  });

  it("a prose line after the bullets starts a new paragraph", () => {
    const b = "## ¶ASK_P: Choose one: Which?\nContext: c\n- [ ] [P] Do P\n  - first\n  Then more prose.\n  Cost: x\n";
    expect(parse(b).questions[0].options[0].description).toBe("- first\n\nThen more prose.");
  });

  it("a coded nested option is still a child (control: the bullet rule does not swallow real nesting)", () => {
    const b = "## ¶ASK_P: Choose one: Which?\nContext: c\n- [ ] [P] Do P\n  Cost: x\n  - [ ] [AUTO] Auto\n    Cost: y\n";
    const p = parse(b).questions[0].options[0];
    expect(p.children?.map((c) => c.code)).toEqual(["AUTO"]);
    expect(p.description).toBeUndefined();
  });

  it("a checkbox nested option with no code stays an option, and authorWarnings names it", () => {
    const b = "## ¶ASK_P: Choose one: Which?\nContext: c\n- [ ] [P] Do P\n  Cost: x\n  - [ ] Sub thing\n    Cost: y\n";
    const ask = parse(b);
    expect(ask.questions[0].options[0].children?.[0]).toMatchObject({ label: "Sub thing" });
    expect(authorWarnings(ask).join("\n")).toMatch(/"Which\?": nested option "Sub thing" under \[P\] has no \[CODE\]/);
  });
});

describe("TRAPS round 2: a bracketed nested line is never folded into prose", () => {
  it("M1: a nested option with an invalid code stays an option line, so new refuses it naming the code", () => {
    const b = "## ¶ASK_A: Choose one: a\nContext: c\n- [X] x\n  d\n  - [opt-1] lower child\n  - [TOOLONGCODEXYZ] long child\n";
    expect(parse(b).questions[0].options[0].description).toBe("d");
    expect(() => newAsk(root, { ...FIELDS, id: "a" }, b)).toThrow(/opt-1/);
    expect(() => newAsk(root, { ...FIELDS, id: "b" }, b)).toThrow(/TOOLONGCODEXYZ/);
  });

  it("N4: an empty checkbox typo stays a nested option and is warned as codeless, not swallowed", () => {
    const b = "## ¶ASK_A: Choose one: a\nContext: c\n- [X] x\n  d\n  - [] [XA] child\n    e\n";
    const ask = parse(b);
    expect(ask.questions[0].options[0].description).toBe("d");
    expect(ask.questions[0].options[0].children).toHaveLength(1);
  });

  it("S6: in a fork with no codes, indented bullets under an option are warned as description", () => {
    const b = "## ¶ASK_A: Choose one: Deploy?\nContext: c\n- Deploy now\n  - to staging only\n  - to prod too\n- Wait\n  d\n";
    expect(authorWarnings(parse(b))).toContain('"Deploy?": the indented bullets under "Deploy now" are read as its description; write "- [CODE] …" to make them options');
    expect(authorWarnings(parse("## ¶ASK_P: Choose one: Which?\nContext: c\n- [P] p\n  - a bullet\n  Cost: c\n  Elegance: e\n")).join("\n")).not.toMatch(/indented bullets/);
  });
});

describe("TRAPS: a fork named after its kind word is refused, naming the fix", () => {
  const bad = GOOD.replace("## ¶ASK_GO: Choose one: Ship it?", "## Choose one: ¶ASK_GO: Ship it?");

  it("parses as before (files on disk still read): keyed by position, the name left in the title", () => {
    const q = parse(bad).questions[0];
    expect(q.askName).toBeUndefined();
    expect(q.title).toBe("¶ASK_GO: Ship it?");
  });

  it("new refuses it, naming the heading and the order to write", () => {
    expect(() => newAsk(root, { ...FIELDS, id: "a" }, bad)).toThrow(ForkNameOrderError);
    expect(() => newAsk(root, { ...FIELDS, id: "a" }, bad)).toThrow(/## ¶ASK_GO: Choose one: Ship it\?/);
    expect(fs.existsSync(path.join(root, SEAT, "a.md"))).toBe(false);
  });

  it("the em-dash form is refused too", () => {
    const dash = GOOD.replace("## ¶ASK_GO: Choose one: Ship it?", "## Choose one: ¶ASK_GO — ship it?");
    expect(() => newAsk(root, { ...FIELDS, id: "a" }, dash)).toThrow(/## ¶ASK_GO: Choose one: ship it\?/);
  });

  it("revise refuses it in a new body", async () => {
    newAsk(root, { ...FIELDS, id: "a" }, GOOD);
    await expect(reviseAsk(root, SEAT, "a", {}, bad, { by: SEAT })).rejects.toThrow(ForkNameOrderError);
  });

  it("N1: a title that merely starts with ASK_ and no separator is a title, not a misplaced name", () => {
    const t = GOOD.replace("## ¶ASK_GO: Choose one: Ship it?", "## ¶ASK_GO: Choose one: ASK_LOG rotation, keep or drop?");
    expect(() => newAsk(root, { ...FIELDS, id: "a" }, t)).not.toThrow();
    const u = GOOD.replace("## ¶ASK_GO: Choose one: Ship it?", "## Choose one: ASK_LOG: rotation, keep or drop?");
    expect(() => newAsk(root, { ...FIELDS, id: "b" }, u)).toThrow(/## ¶ASK_LOG: Choose one: rotation, keep or drop\?/);
  });
});

describe("FLOOR: a bare option is refused", () => {
  it("names the fork and each bare code, at any depth", () => {
    const b = [
      "## ¶ASK_GO: Choose one: Ship it?",
      "Context: c",
      "- [ ] [YES] Ship",
      "  Cost: a night",
      "  - [ ] [NOW] Now",
      "- [ ] [NO] Hold",
      "",
    ].join("\n");
    let err: unknown;
    try {
      newAsk(root, { ...FIELDS, id: "a" }, b);
    } catch (e) {
      err = e;
    }
    expect(err).toBeInstanceOf(AskFloorError);
    expect((err as Error).message).toMatch(/"Ship it\?" \[NOW\]: a bare option/);
    expect((err as Error).message).toMatch(/"Ship it\?" \[NO\]: a bare option/);
    expect((err as Error).message).not.toMatch(/\[YES\]: a bare/);
  });

  it("an option with only a field (Cost, Then, Elegance…) or only children is not bare", () => {
    const b = "## ¶ASK_GO: Choose one: Ship?\nContext: c\n- [ ] [A] a\n  Elegance: clean\n- [ ] [B] b\n  - [ ] [B1] b1\n    Then: run it\n";
    expect(() => newAsk(root, { ...FIELDS, id: "a" }, b)).not.toThrow();
  });

  it("a Yes or no fork with no options written is exempt (its YES/NO are filled in)", () => {
    expect(() => newAsk(root, { ...FIELDS, id: "a" }, "## ¶ASK_OK: Yes or no: Lock it?\nContext: YES freezes the key.\n")).not.toThrow();
  });

  it("revise refuses a bare option in a new body, naming --keep-body as the way to revise the card only (S4)", async () => {
    newAsk(root, { ...FIELDS, id: "a" }, GOOD);
    const p = reviseAsk(root, SEAT, "a", {}, "## ¶ASK_GO: Choose one: Ship?\nContext: c\n- [ ] [A] a\n", { by: SEAT });
    await expect(p).rejects.toThrow(AskFloorError);
    await expect(reviseAsk(root, SEAT, "a", {}, "## ¶ASK_GO: Choose one: Ship?\nContext: c\n- [ ] [A] a\n", { by: SEAT })).rejects.toThrow(/pass --keep-body/);
  });

  it("new does not mention --keep-body (it has no card to keep)", () => {
    expect(() => newAsk(root, { ...FIELDS, id: "a" }, "## ¶ASK_GO: Choose one: Ship?\nContext: c\n- [ ] [A] a\n")).toThrow(/^(?![\s\S]*keep-body)/);
  });

  it("the message says to indent under the option, and does not call Cost required (S1)", () => {
    expect(() => newAsk(root, { ...FIELDS, id: "a" }, "## ¶ASK_GO: Choose one: Ship?\nContext: c\n- [ ] [A] a\n  Does a.\n- [ ] [B] b\n")).toThrow(
      /"Ship\?" \[B\]: a bare option: indent a line under it \(two spaces\) saying what picking it changes, e\.g\. "  Ships tonight\." then "  Cost: a night watch"$/m,
    );
  });

  it("Rank options are names and are never bare (S3)", () => {
    expect(() => newAsk(root, { ...FIELDS, id: "a" }, "## ¶ASK_R: Rank: Which first?\nContext: c\n- [A] alpha\n- [B] beta\n")).not.toThrow();
  });

  it("a bare [YES]/[NO] Choose one is pointed at `Yes or no:` (S3)", () => {
    expect(() => newAsk(root, { ...FIELDS, id: "a" }, "## ¶ASK_GO: Choose one: Ship?\nContext: c\n- [ ] [YES] Yes\n- [ ] [NO] No\n")).toThrow(
      /\[NO\]: a bare option: .*; or, for a plain yes or no, write the fork as "## ¶ASK_<NAME>: Yes or no: Ship\?" with no options/,
    );
  });
});

describe("FLOOR: a fork with no context of its own is refused", () => {
  const bareFork = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Ship\n  Cost: x\n- [ ] [NO] Hold\n  Cost: y\n";

  it("refuses a fork with no prose, Context or Stake", () => {
    expect(() => newAsk(root, { ...FIELDS, id: "a" }, bareFork)).toThrow(/"Ship it\?": a fork needs context: add/);
  });

  it("Context, Stake or prose under the heading each satisfy it", () => {
    for (const [i, line] of ["Context: c", "Stake: s", "The reason, in prose."].entries()) {
      expect(() => newAsk(root, { ...FIELDS, id: `c${i}` }, bareFork.replace("Ship it?\n", `Ship it?\n${line}\n`))).not.toThrow();
    }
  });

  it("the preamble or the header's why, context or stakes count for every fork (S2)", () => {
    expect(() => newAsk(root, { ...FIELDS, id: "p" }, `The preamble says why.\n\n${bareFork}`)).not.toThrow();
    expect(() => newAsk(root, { ...FIELDS, id: "w", why: "because" }, bareFork)).not.toThrow();
    expect(() => newAsk(root, { ...FIELDS, id: "s", stakes: "s" }, bareFork)).not.toThrow();
    const second = bareFork.replace("ASK_GO", "ASK_GO2").replace("Ship it?", "And then?");
    expect(() => newAsk(root, { ...FIELDS, id: "t" }, `The preamble covers both forks.\n\n${bareFork}\n${second}`)).not.toThrow();
    expect(() => newAsk(root, { ...FIELDS, id: "u" }, `${bareFork.replace("Ship it?\n", "Ship it?\nContext: c\n")}\n${second}`)).toThrow(/"And then\?": a fork needs context/);
  });

  it("Lean, Counter or Evidence count as fork context; Panel does not (S3, S7)", () => {
    for (const [i, line] of ["Lean: YES — because", "Counter: it may slip", "Evidence: a.test.ts:3"].entries()) {
      expect(() => newAsk(root, { ...FIELDS, id: `l${i}` }, bareFork.replace("Ship it?\n", `Ship it?\n${line}\n`))).not.toThrow();
    }
    expect(() => newAsk(root, { ...FIELDS, id: "pn" }, bareFork.replace("Ship it?\n", "Ship it?\nPanel: Security → YES — safe\n"))).toThrow(/a fork needs context/);
  });

  it("Yes or no, Number, Date and Text forks need no context (S3)", () => {
    const b = `${GOOD}\n## ¶ASK_OK: Yes or no: Lock it?\n\n## ¶ASK_N: Number: How many retries?\nRange: 1..5\n\n## ¶ASK_D: Date: When?\n\n## ¶ASK_T: Text: Why?\n`;
    expect(() => newAsk(root, { ...FIELDS, id: "a" }, b)).not.toThrow();
  });

  it("the message says where the context goes", () => {
    expect(() => newAsk(root, { ...FIELDS, id: "a" }, bareFork)).toThrow(/add a Context: line under the heading/);
  });

  it("files already on disk still read and list", () => {
    fs.mkdirSync(path.join(root, SEAT), { recursive: true });
    fs.writeFileSync(path.join(root, SEAT, "old.md"), HEAD + "## Choose one: ¶ASK_GO: Ship?\n- [ ] [A] a\n");
    expect(listAsks(root).map((a) => a.header.id)).toEqual(["t1"]);
  });
});

describe("FLOOR: warnings for a missing Cost or Elegance", () => {
  it("a fork whose options lack Cost or Elegance says how many, in one line per fork (S5)", () => {
    const b = "## ¶ASK_GO: Choose one: Ship?\nContext: c\n- [ ] [A] a\n  Does a.\n- [ ] [B] b\n  Does b.\n  Cost: x\n  Elegance: e\n- [ ] [C] c\n  Does c.\n  Elegance: e\n";
    const w = authorWarnings(parse(b));
    expect(w).toEqual(['"Ship?": 2 of 3 options have no Cost: line (what the operator gives up); 1 of 3 have no Elegance: line (how cleanly it fits)']);
  });

  it("Rank options are not asked for Cost or Elegance (S3)", () => {
    expect(authorWarnings(parse("## ¶ASK_R: Rank: Order?\nContext: c\n- [A] alpha\n- [B] beta\n"))).toEqual([]);
  });

  it("the well-formed body warns about neither, and Reversible is never asked for", () => {
    const w = authorWarnings(parse(GOOD));
    expect(w.join("\n")).not.toMatch(/Cost|Elegance|Reversible/);
  });

  it("an auto-filled Yes or no fork is not asked for Cost or Elegance", () => {
    expect(authorWarnings(parse("## ¶ASK_OK: Yes or no: Lock?\nContext: c\n"))).toEqual([]);
  });
});

describe("FIELDS: per-option Unblocks, Then and Elegance", () => {
  const b = [
    "## ¶ASK_GO: Choose one: Ship it?",
    "Context: c",
    "Unblocks: the fork-level line stays the fork's",
    "- [ ] [YES] Ship",
    "  Goes out tonight.",
    "  Cost: a night watch",
    "  Unblocks: IDE-12 and the deploy lane",
    "  Then: run engine deploy and post the URL here",
    "  Elegance: high — one release path",
    "  Reversible: yes",
    "- [ ] [NO] Hold",
    "  Nothing ships.",
    "  Cost: c",
    "",
  ].join("\n");

  it("parses them onto the option, leaving the fork's Unblocks in meta and Reversible as description", () => {
    const q = parse(b).questions[0];
    const yes = q.options[0] as AskOption;
    expect(yes.unblocks).toBe("IDE-12 and the deploy lane");
    expect(yes.then).toBe("run engine deploy and post the URL here");
    expect(yes.elegance).toBe("high — one release path");
    expect(q.meta.unblocks).toBe("the fork-level line stays the fork's");
    expect(q.options[1]).not.toHaveProperty("then");
  });

  it("M2/N3: until the card renders them, Unblocks, Then and Elegance also stay in the description, exactly as f0368fc showed them", () => {
    const yes = parse(b).questions[0].options[0];
    expect(yes.description).toBe("Goes out tonight. Unblocks: IDE-12 and the deploy lane Then: run engine deploy and post the URL here Elegance: high — one release path Reversible: yes");
    expect(yes.cost).toBe("a night watch");
    expect(yes.description).not.toMatch(/Cost:/);
  });

  describe("GET /api/asks serves them", () => {
    let base: string, port: number, proc: ChildProcess;
    beforeAll(async () => {
      base = fs.mkdtempSync(path.join("/tmp", "asksrv-asktree-"));
      const r = path.join(base, "asks");
      fs.mkdirSync(path.join(base, "sessions"));
      const dist = path.join(base, "dist");
      fs.mkdirSync(dist);
      fs.writeFileSync(path.join(dist, "index.html"), "<!doctype html><html><body></body></html>\n");
      fs.writeFileSync(path.join(dist, BUILD_ID_FILE), `${computeBuildId()}\n`);
      newAsk(r, { ...FIELDS, id: "f1" }, b);
      port = 30000 + Math.floor(Math.random() * 20000);
      proc = spawn(process.execPath, ["--no-warnings", "src/server.ts", "--root", r, "--port", String(port), "--token", "tok"], {
        env: { ...process.env, ASK_SESSIONS_DIR: path.join(base, "sessions"), ASK_APP_DIST: dist },
        stdio: "ignore",
      });
      for (let i = 0; i < 100; i++) {
        try {
          if ((await get("/api/health")).status === 200) return;
        } catch {
          // not up yet
        }
        await new Promise((res) => setTimeout(res, 50));
      }
      throw new Error("server did not start");
    });
    afterAll(() => {
      proc.kill();
      fs.rmSync(base, { recursive: true, force: true });
    });
    const get = (p: string) =>
      new Promise<{ status: number; body: string }>((resolve, reject) => {
        http
          .get({ host: "127.0.0.1", port, path: p, headers: { host: `127.0.0.1:${port}` } }, (res) => {
            let s = "";
            res.on("data", (d) => (s += d));
            res.on("end", () => resolve({ status: res.statusCode!, body: s }));
          })
          .on("error", reject);
      });

    it("each option carries unblocks, then and elegance", async () => {
      const r = await get("/api/asks");
      expect(r.status).toBe(200);
      const opt = JSON.parse(r.body).asks[0].questions[0].options[0];
      expect(opt).toMatchObject({ code: "YES", unblocks: "IDE-12 and the deploy lane", then: "run engine deploy and post the URL here", elegance: "high — one release path" });
    });
  });
});
