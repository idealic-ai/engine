/**
 * Code fences are syntax-highlighted (IDE-304, operator 15:40): a bundled highlight.js core with a
 * registered set of languages, common aliases, plain text for an unknown or missing tag (no
 * auto-detect), a quiet language label, colours from Slate tokens in both themes, and code that never
 * becomes HTML.
 */
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import { CodeBlock, HL_TOKENS, highlightTree, langLabel, resolveLang } from "../src/client/highlight.tsx";
import { Rich } from "../src/client/rich.tsx";

const dir = path.join(import.meta.dirname, "../src/client");
const theme = fs.readFileSync(path.join(dir, "theme.css"), "utf8");
const styles = fs.readFileSync(path.join(dir, "styles.css"), "utf8");
const R = (text: string) => renderToStaticMarkup(createElement(Rich, { text }));
const C = (code: string, lang?: string) => renderToStaticMarkup(createElement(CodeBlock, { code, lang }));

describe("a known tag gets token spans", () => {
  it("a ts fence: keyword and string spans, labelled ts", () => {
    const html = R("```ts\nconst x: string = \"hi\";\n```");
    expect(html).toContain('<span class="code-lang">ts</span>');
    expect(html).toContain('<code class="hljs language-typescript">');
    expect(html).toContain('<span class="hljs-keyword">const</span>');
    expect(html).toContain('<span class="hljs-string">&quot;hi&quot;</span>');
  });

  it("every language in the registered set highlights something", () => {
    const samples: Record<string, string> = {
      ts: "const a = 1;",
      js: "function f() { return 1; }",
      tsx: "export const A = () => 1;",
      json: '{"a": 1}',
      bash: "echo \"hi\" && exit 1",
      sh: "if true; then echo hi; fi",
      shell: "$ npm test",
      sql: "SELECT id FROM asks WHERE x = 1;",
      yaml: "key: value",
      md: "# Title",
      diff: "-old\n+new",
      python: "def f():\n    return None",
      css: "a { color: red; }",
      html: "<div class=\"x\">hi</div>",
    };
    for (const [tag, code] of Object.entries(samples)) {
      expect(resolveLang(tag), tag).toBeDefined();
      expect(C(code, tag), tag).toMatch(/<span class="hljs-/);
    }
  });
});

describe("aliases resolve", () => {
  it.each([
    ["ts", "typescript"],
    ["typescript", "typescript"],
    ["TS", "typescript"],
    ["tsx", "typescript"],
    ["js", "javascript"],
    ["sh", "bash"],
    ["zsh", "bash"],
    ["console", "shell"],
    ["yml", "yaml"],
    ["md", "markdown"],
    ["py", "python"],
    ["html", "xml"],
  ])("%s -> %s", (tag, lang) => {
    expect(resolveLang(tag)).toBe(lang);
  });

  it("an alias fence highlights and keeps the author's tag as its label", () => {
    const html = R("```zsh\necho hi\n```");
    expect(html).toContain('<span class="code-lang">zsh</span>');
    expect(html).toContain('<code class="hljs language-bash">');
    expect(html).toContain('<span class="hljs-built_in">echo</span>');
  });
});

describe("an unknown or missing tag is plain text", () => {
  it("an unknown tag: no spans, no auto-detect, labelled text", () => {
    expect(resolveLang("brainfuck-ish")).toBeUndefined();
    const html = R("```nosuchlang\nconst x = 1;\n```");
    expect(html).toContain('<span class="code-lang">text</span>');
    expect(html).toContain('<pre class="code"><code>const x = 1;</code></pre>');
    expect(html).not.toContain("hljs");
  });

  it("no tag at all: plain text, labelled text, even when the code looks like a language", () => {
    const html = R("```\nfunction f() { return 1; }\n```");
    expect(langLabel("")).toBe("text");
    expect(html).toContain('<span class="code-lang">text</span>');
    expect(html).toContain('<pre class="code"><code>function f() { return 1; }</code></pre>');
    expect(html).not.toContain("hljs");
  });

  it("a `text` or `plaintext` tag is plain text too", () => {
    expect(C("x = 1", "text")).not.toContain("hljs");
    expect(C("x = 1", "plaintext")).not.toContain("hljs");
  });
});

describe("code never becomes HTML", () => {
  it("<script> in an untagged fence stays text", () => {
    const html = R("```\n<script>alert(1)</script>\n```");
    expect(html).toContain("&lt;script&gt;alert(1)&lt;/script&gt;");
    expect(html).not.toContain("<script");
  });

  it("<script> inside highlighted code stays text: the tree is built from tokens, not set as HTML", () => {
    for (const lang of ["ts", "html", "md", "bash", "json"]) {
      const html = C('const s = "<script>alert(1)</script>"; <img src=x onerror=alert(1)>', lang);
      expect(html, lang).not.toContain("<script");
      expect(html, lang).not.toContain("<img");
      expect(html, lang).toContain("&lt;");
    }
  });

  it("the tree holds only spans with hljs classes and plain strings", () => {
    const tree = highlightTree('<b onclick="x">&amp;</b>', "xml");
    expect(tree).toBeDefined();
    const walk = (n: unknown): void => {
      if (typeof n === "string") return;
      const node = n as { cls: string; kids: unknown[] };
      expect(node.cls).toMatch(/^(hljs-|language-)[\w-]+( [\w-]+)*$/);
      node.kids.forEach(walk);
    };
    tree!.forEach(walk);
    // The text survives exactly, entities decoded once (React escapes it again on render).
    const text = (n: unknown): string => (typeof n === "string" ? n : (n as { kids: unknown[] }).kids.map(text).join(""));
    expect(tree!.map(text).join("")).toBe('<b onclick="x">&amp;</b>');
  });

  it("the renderer never sets inner HTML", () => {
    const src = fs.readFileSync(path.join(dir, "highlight.tsx"), "utf8");
    expect(src).not.toMatch(/dangerouslySetInnerHTML|innerHTML/);
  });
});

describe("theme: Slate tokens in both modes", () => {
  const blocksOf = (css: string) => {
    const light = css.match(/^:root \{([\s\S]*?)^\}/m)?.[1] ?? "";
    const media = css.match(/:root:not\(\[data-theme="light"\]\) \{([\s\S]*?)^ {2}\}/m)?.[1] ?? "";
    const forced = css.match(/^:root\[data-theme="dark"\] \{([\s\S]*?)^\}/m)?.[1] ?? "";
    return { light, media, forced };
  };

  it("every highlight token variable is defined in light, media-dark and forced-dark", () => {
    const { light, media, forced } = blocksOf(theme);
    expect(HL_TOKENS.length).toBeGreaterThanOrEqual(8);
    for (const t of HL_TOKENS) {
      expect(light, `light ${t}`).toMatch(new RegExp(`--${t}:\\s*#[0-9a-f]{6};`));
      expect(media, `media dark ${t}`).toMatch(new RegExp(`--${t}:\\s*#[0-9a-f]{6};`));
      expect(forced, `forced dark ${t}`).toMatch(new RegExp(`--${t}:\\s*#[0-9a-f]{6};`));
    }
  });

  it("the two dark blocks agree", () => {
    const { media, forced } = blocksOf(theme);
    for (const t of HL_TOKENS) {
      const v = (s: string) => s.match(new RegExp(`--${t}:\\s*(#[0-9a-f]{6});`))?.[1];
      expect(v(media), t).toBe(v(forced));
    }
  });

  it("each token reads against the code background at 4.5:1 or better in both modes", () => {
    const { light, forced } = blocksOf(theme);
    const hex = (s: string, name: string) => s.match(new RegExp(`--${name}:\\s*(#[0-9a-f]{6});`))![1];
    const lum = (h: string) => {
      const [r, g, b] = [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255).map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
      return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    };
    const ratio = (a: string, b: string) => {
      const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p);
      return (x + 0.05) / (y + 0.05);
    };
    for (const block of [light, forced]) {
      const bg = hex(block, "code-bg");
      for (const t of HL_TOKENS) expect(ratio(hex(block, t), bg), t).toBeGreaterThanOrEqual(4.5);
    }
  });

  it("styles.css reads the tokens and imports no theme stylesheet", () => {
    for (const t of HL_TOKENS) expect(styles).toContain(`var(--${t})`);
    expect(styles + theme).not.toMatch(/highlight\.js\/styles|@import/);
    const src = fs.readFileSync(path.join(dir, "highlight.tsx"), "utf8");
    expect(src).not.toMatch(/\.css["']/);
    expect(src).toMatch(/from "highlight\.js\/lib\/core"/);
  });

  it("the label is small and quiet", () => {
    const rule = styles.match(/\.code-lang \{([^}]*)\}/)?.[1] ?? "";
    expect(rule).toContain("var(--ink-3)");
    expect(rule).toMatch(/font-size:\s*1[01]px/);
  });
});

describe("where it applies", () => {
  it("a code callout's bare body is plain text, labelled text", () => {
    const html = R("> [!code] run.ts\n> const a = 1;");
    expect(html).toContain('<span class="code-lang">text</span>');
    expect(html).toContain("const a = 1;");
  });

  it("a fence inside a callout, a list item and a quote highlights", () => {
    expect(R("> [!code] x\n> ```ts\n> const a = 1;\n> ```")).toContain('<span class="hljs-keyword">const</span>');
    expect(R("- item\n  ```ts\n  const a = 1;\n  ```")).toContain('<span class="hljs-keyword">const</span>');
    expect(R("> ```ts\n> const a = 1;\n> ```")).toContain('<span class="hljs-keyword">const</span>');
  });

  it("an option body highlights", async () => {
    const { OptionDescription } = await import("../src/client/App.tsx");
    const html = renderToStaticMarkup(createElement(OptionDescription, { text: "Pick it.\n\n```ts\nconst a = 1;\n```" }));
    expect(html).toContain('<span class="hljs-keyword">const</span>');
  });

  it("the recorded answer block renders as highlighted json", async () => {
    const { RecordedAnswer } = await import("../src/client/App.tsx");
    const html = renderToStaticMarkup(createElement(RecordedAnswer, { answer: { picks: { Q1: "a" }, note: "<script>x</script>" } }));
    expect(html).toContain('<span class="code-lang">json</span>');
    expect(html).toContain('<span class="hljs-attr">&quot;picks&quot;</span>');
    expect(html).not.toContain("<script");
  });

  it("a dialogue turn with a fence renders its code block; one without stays inline", async () => {
    const { TurnText } = await import("../src/client/App.tsx");
    const fenced = renderToStaticMarkup(createElement(TurnText, { text: "See:\n```ts\nconst a = 1;\n```" }));
    expect(fenced).toContain('<span class="hljs-keyword">const</span>');
    const plain = renderToStaticMarkup(createElement(TurnText, { text: "just `x` here" }));
    expect(plain).toBe('<span>just </span><code class="ic">x</code><span> here</span>');
  });
});
