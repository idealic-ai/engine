/**
 * OPTFENCE: a fenced code block indented under an option belongs to that option. The option stays
 * answerable and its description keeps the fence as raw markdown, newlines intact, dedented to the
 * fence's own indent, so the client's markdown renderer shows it as code. A fence at the fork's top
 * level stays the fork's prose, and no fence ever ends or splits the options group.
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { newAsk } from "../src/lib/store.ts";
import { parseAskFile, validateAnswer } from "../src/lib/format.ts";

const head = "---\nid: f1\nto: operator\nfrom: meta:engine\nstatus: open\nrevision: 1\n---\n\n";
const parse = (body: string) => parseAskFile(head + body);

let root: string;
beforeEach(() => {
  root = path.join(fs.mkdtempSync(path.join("/tmp", "askoptfence-")), "asks");
});
afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));

describe("a fence indented under an option", () => {
  it("keeps the option an option, with the fence verbatim in its description", () => {
    const a = parse(
      "## ¶ASK_Q: Choose one: Which shape?\n" +
        "- [ ] [A] Return a tuple\n" +
        "  The caller destructures it.\n" +
        "  ```ts\n" +
        "  const [ok, err] = run();\n" +
        "  if (err) {\n" +
        "    throw err;\n" +
        "  }\n" +
        "  ```\n" +
        "- [ ] [B] Throw\n" +
        "  Plain.\n",
    );
    const q = a.questions[0];
    expect(q.options.map((o) => o.code)).toEqual(["A", "B"]);
    expect(q.options[0].description).toBe(
      "The caller destructures it.\n\n```ts\nconst [ok, err] = run();\nif (err) {\n  throw err;\n}\n```",
    );
    expect(q.options[1].description).toBe("Plain.");
    expect(q.prose).toBeUndefined();
    expect(() => validateAnswer(a, { Q: ["A"] })).not.toThrow();
  });

  it("keeps blank lines inside the fence, and prose after the fence follows it as its own paragraph", () => {
    const a = parse(
      "## ¶ASK_Q: Choose one: Q?\n" +
        "- [ ] [A] a\n" +
        "  Before.\n" +
        "\n" +
        "  ```\n" +
        "  one\n" +
        "\n" +
        "  two\n" +
        "  ```\n" +
        "\n" +
        "  After.\n" +
        "- [ ] [B] b\n",
    );
    expect(a.questions[0].options.map((o) => o.code)).toEqual(["A", "B"]);
    expect(a.questions[0].options[0].description).toBe("Before.\n\n```\none\n\ntwo\n```\n\nAfter.");
  });

  it("parses every option of a fork with fences in its prose AND in two options", () => {
    const a = parse(
      "## ¶ASK_Q: Choose one: Which call?\n" +
        "Today the code reads:\n" +
        "```ts\n" +
        "load(id);\n" +
        "- [ ] [Z] not an option\n" +
        "```\n" +
        "- [ ] [A] Await it\n" +
        "  ```ts\n" +
        "  await load(id);\n" +
        "  ```\n" +
        "- [ ] [B] Cache it\n" +
        "  ```ts\n" +
        "  cache.get(id) ?? load(id);\n" +
        "  ```\n" +
        "- [ ] [C] Leave it\n",
    );
    const q = a.questions[0];
    expect(q.options.map((o) => o.code)).toEqual(["A", "B", "C"]);
    expect(q.options[0].description).toBe("```ts\nawait load(id);\n```");
    expect(q.options[1].description).toBe("```ts\ncache.get(id) ?? load(id);\n```");
    expect(q.prose).toBe("Today the code reads:\n```ts\nload(id);\n- [ ] [Z] not an option\n```");
    expect(() => validateAnswer(a, { Q: ["B"] })).not.toThrow();
  });

  it("a ``` line inside the fence content that is not the closing fence does not close it", () => {
    const a = parse(
      "## ¶ASK_Q: Choose one: Q?\n" +
        "- [ ] [A] a\n" +
        "  ```md\n" +
        "  ```ts example\n" +
        "  - [ ] [Z] still code\n" +
        "  ```\n" +
        "- [ ] [B] b\n",
    );
    const q = a.questions[0];
    // ```ts example has an info string, so it cannot close; the bare ``` that follows does.
    expect(q.options.map((o) => o.code)).toEqual(["A", "B"]);
    expect(q.options[0].description).toBe("```md\n```ts example\n- [ ] [Z] still code\n```");
  });

  it("a 4-backtick fence holds a whole 3-backtick fence", () => {
    const a = parse(
      "## ¶ASK_Q: Choose one: Q?\n" +
        "- [ ] [A] a\n" +
        "  ````md\n" +
        "  ```\n" +
        "  - [ ] [Z] inner\n" +
        "  ```\n" +
        "  ````\n" +
        "- [ ] [B] b\n",
    );
    const q = a.questions[0];
    expect(q.options.map((o) => o.code)).toEqual(["A", "B"]);
    expect(q.options[0].description).toBe("````md\n```\n- [ ] [Z] inner\n```\n````");
  });

  it("a fence under a nested option belongs to that child", () => {
    const a = parse(
      "## ¶ASK_Q: Choose one: Q?\n" +
        "- [ ] [A] a\n" +
        "  - [ ] [AA] child\n" +
        "    ```\n" +
        "    x\n" +
        "    ```\n" +
        "- [ ] [B] b\n",
    );
    const q = a.questions[0];
    expect(q.options.map((o) => o.code)).toEqual(["A", "B"]);
    expect(q.options[0].description).toBeUndefined();
    expect(q.options[0].children?.[0].description).toBe("```\nx\n```");
  });

  it("an indented fence in the reasons, with no option above it, stays prose, shown as written", () => {
    const a = parse("## ¶ASK_Q: Choose one: Q?\nLike:\n  ```\n  x\n  ```\n- [ ] [A] a\n- [ ] [B] b\n");
    expect(a.questions[0].options.map((o) => o.code)).toEqual(["A", "B"]);
    expect(a.questions[0].prose).toBe("Like:\n  ```\n  x\n  ```");
  });

  it("an unindented fence after the options is after-prose and does not swallow them", () => {
    const a = parse("## ¶ASK_Q: Choose one: Q?\n- [ ] [A] a\n- [ ] [B] b\n```\nnote\n```\n");
    expect(a.questions[0].options.map((o) => o.code)).toEqual(["A", "B"]);
    expect(a.questions[0].proseAfter).toBe("```\nnote\n```");
  });

  it("an ask filed through `new` keeps the fenced options answerable", () => {
    const body = "## ¶ASK_Q: Choose one: Which?\n- [ ] [A] a\n  ```ts\n  x();\n  ```\n- [ ] [B] b\n  ```ts\n  y();\n  ```\n";
    const a = parseAskFile(fs.readFileSync(newAsk(root, { from: "meta:engine", to: "operator", id: "of1" }, body), "utf8"));
    expect(a.questions[0].options.map((o) => o.code)).toEqual(["A", "B"]);
    expect(a.questions[0].options[1].description).toBe("```ts\ny();\n```");
  });
});
