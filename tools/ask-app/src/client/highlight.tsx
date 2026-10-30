/**
 * Fenced code, highlighted (IDE-304). highlight.js core is bundled with a fixed set of languages; a
 * tag outside the set, or no tag, renders as plain text (never auto-detected). The colours are the
 * `--hl-*` tokens in theme.css, read by the `.hljs-*` rules in styles.css; no theme stylesheet.
 *
 * Code never becomes HTML: highlight.js returns escaped HTML whose only markup is
 * `<span class="…">` and `</span>`. That output is parsed back into a tree of class names and plain
 * strings, and React renders the tree (escaping the text again). Anything else in the output, which
 * highlight.js does not produce, drops the block to plain text instead of being trusted.
 */
import type { ReactNode } from "react";
import hljs from "highlight.js/lib/core";
import bash from "highlight.js/lib/languages/bash";
import css from "highlight.js/lib/languages/css";
import diff from "highlight.js/lib/languages/diff";
import javascript from "highlight.js/lib/languages/javascript";
import json from "highlight.js/lib/languages/json";
import markdown from "highlight.js/lib/languages/markdown";
import python from "highlight.js/lib/languages/python";
import shell from "highlight.js/lib/languages/shell";
import sql from "highlight.js/lib/languages/sql";
import typescript from "highlight.js/lib/languages/typescript";
import xml from "highlight.js/lib/languages/xml";
import yaml from "highlight.js/lib/languages/yaml";

const LANGS = { bash, css, diff, javascript, json, markdown, python, shell, sql, typescript, xml, yaml };
for (const [name, def] of Object.entries(LANGS)) hljs.registerLanguage(name, def);

/** A fence tag, lowercased, to the registered language it means. A tag not here is plain text. */
const ALIASES: Record<string, keyof typeof LANGS> = {
  ts: "typescript", typescript: "typescript", tsx: "typescript", mts: "typescript", cts: "typescript",
  js: "javascript", javascript: "javascript", jsx: "javascript", mjs: "javascript", cjs: "javascript",
  json: "json", jsonc: "json",
  bash: "bash", sh: "bash", zsh: "bash",
  shell: "shell", console: "shell", shellsession: "shell",
  sql: "sql",
  yaml: "yaml", yml: "yaml",
  md: "markdown", markdown: "markdown",
  diff: "diff", patch: "diff",
  python: "python", py: "python",
  css: "css",
  html: "xml", xml: "xml", svg: "xml", xhtml: "xml",
};

/** The colour tokens the highlighter reads; theme.css defines each in light and both dark blocks. */
export const HL_TOKENS = [
  "hl-keyword", "hl-string", "hl-number", "hl-comment", "hl-title", "hl-type",
  "hl-attr", "hl-meta", "hl-variable", "hl-addition", "hl-deletion",
] as const;

export function resolveLang(tag: string | undefined): keyof typeof LANGS | undefined {
  const k = (tag ?? "").trim().toLowerCase();
  return Object.hasOwn(ALIASES, k) ? ALIASES[k] : undefined;
}

/** The block's label: the author's own tag when it is one we highlight, else "text". */
export function langLabel(tag: string | undefined): string {
  return resolveLang(tag) ? tag!.trim().toLowerCase() : "text";
}

export type HlNode = string | { cls: string; kids: HlNode[] };

const ENTITIES: Record<string, string> = { "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#x27;": "'", "&#39;": "'" };
const PIECE = /<span class="([\w -]+)">|<\/span>|([^<]+)/gy;

/** Highlighted code as a tree, or undefined when the tag is not highlighted or the output is not the expected shape. */
export function highlightTree(code: string, tag: string | undefined): HlNode[] | undefined {
  const language = resolveLang(tag);
  if (!language) return undefined;
  let html: string;
  try {
    html = hljs.highlight(code, { language, ignoreIllegals: true }).value;
  } catch {
    return undefined;
  }
  const root: HlNode[] = [];
  const stack: HlNode[][] = [root];
  PIECE.lastIndex = 0;
  let at = 0;
  for (let m = PIECE.exec(html); m; m = PIECE.exec(html)) {
    at = PIECE.lastIndex;
    const top = stack[stack.length - 1];
    if (m[1] !== undefined) {
      if (!/^(hljs-|language-)/.test(m[1])) return undefined;
      const node = { cls: m[1], kids: [] as HlNode[] };
      top.push(node);
      stack.push(node.kids);
    } else if (m[2] !== undefined) {
      const text = m[2].replace(/&(?:amp|lt|gt|quot|#x27|#39);/g, (e) => ENTITIES[e]);
      if (/&/.test(m[2].replace(/&(?:amp|lt|gt|quot|#x27|#39);/g, ""))) return undefined;
      top.push(text);
    } else {
      if (stack.length === 1) return undefined;
      stack.pop();
    }
  }
  return at === html.length && stack.length === 1 ? root : undefined;
}

function render(nodes: HlNode[]): ReactNode[] {
  return nodes.map((n, i) => (typeof n === "string" ? n : <span key={i} className={n.cls}>{render(n.kids)}</span>));
}

/** A fenced block: a quiet language label, then the code, highlighted when its tag is one we know. */
export function CodeBlock({ code, lang }: { code: string; lang?: string }) {
  const tree = highlightTree(code, lang);
  const language = resolveLang(lang);
  return (
    <div className="codeblock">
      <span className="code-lang">{langLabel(lang)}</span>
      <pre className="code">{tree && language ? <code className={`hljs language-${language}`}>{render(tree)}</code> : <code>{code}</code>}</pre>
    </div>
  );
}
