/**
 * The small slice of markdown an ask's prose uses, as data: inline code, links, bare URLs and ticket
 * keys inside a line; paragraphs, lists, fenced code, quotes and `> [!kind] Title` callouts across
 * lines. Pure functions, no React, so the sidebar and the related pane can read links from the same
 * tokens the card renders.
 */

export type Inline =
  | { t: "text"; v: string }
  | { t: "code"; v: string }
  | { t: "link"; label: string; href: string }
  | { t: "ticket"; key: string }
  | { t: "strong"; v: string }
  | { t: "em"; v: string };

export const CALLOUT_KINDS = ["background", "term", "code", "evidence", "more"] as const;
export type CalloutKind = (typeof CALLOUT_KINDS)[number];

export type Block =
  | { t: "p"; text: string }
  | { t: "pre"; lang: string; code: string }
  | { t: "list"; ordered: boolean; items: string[]; start?: number; nested?: string[] }
  | { t: "hr" }
  | { t: "h"; level: number; text: string }
  | { t: "quote"; text: string }
  | { t: "callout"; kind: CalloutKind; title: string; body: string };

/** The same key shape format.ts's ticketKeys reads, so every key it counts is a key the card links. */
const TICKET_SRC = "[A-Z][A-Z0-9]{1,9}-\\d{1,6}";
const TICKET_ONLY = new RegExp(`^${TICKET_SRC}$`);
const INLINE_RE = new RegExp(
  [
    "`([^`\\n]+)`", // 1 inline code
    "\\[([^\\]\\n]+)\\]\\(([^)\\s]+)\\)", // 2,3 markdown link
    "(https?:\\/\\/[^\\s<>()\\[\\]`\"']+)", // 4 bare URL
    `\\b(${TICKET_SRC})\\b`, // 5 ticket key
    "\\*\\*(?=\\S)([^\\n]+?)\\*\\*", // 6 bold
    "(?<![\\w_])__(?=\\S)([^\\n]+?)__(?![\\w_])", // 7 bold
    "(?<![\\w*])\\*(?=[^\\s*])([^*\\n]+?)\\*(?![\\w*])", // 8 italic
    "(?<![\\w_])_(?=[^\\s_])([^_\\n]+?)_(?![\\w_])", // 9 italic (not inside snake_case)
  ].join("|"),
  "g",
);

/** Split one run of text into plain text, code spans, links and ticket keys. */
export function inlineTokens(text: string): Inline[] {
  const out: Inline[] = [];
  const pushText = (v: string) => {
    if (!v) return;
    const last = out[out.length - 1];
    if (last?.t === "text") last.v += v;
    else out.push({ t: "text", v });
  };
  let at = 0;
  for (const m of text.matchAll(INLINE_RE)) {
    const start = m.index ?? 0;
    pushText(text.slice(at, start));
    at = start + m[0].length;
    if (m[1] !== undefined) out.push({ t: "code", v: m[1] });
    else if (m[2] !== undefined) {
      // A link whose label is just a ticket key is that ticket: it gets the ticket's hover.
      if (TICKET_ONLY.test(m[2].trim())) out.push({ t: "ticket", key: m[2].trim() });
      else out.push({ t: "link", label: m[2], href: m[3] });
    } else if (m[4] !== undefined) {
      // Sentence punctuation after a bare URL is not part of it.
      const url = m[4].replace(/[.,;:!?]+$/, "");
      out.push({ t: "link", label: url, href: url });
      at = start + url.length;
    } else if (m[5] !== undefined) out.push({ t: "ticket", key: m[5] });
    else if (m[6] !== undefined || m[7] !== undefined) out.push({ t: "strong", v: (m[6] ?? m[7])! });
    else out.push({ t: "em", v: (m[8] ?? m[9])! });
  }
  pushText(text.slice(at));
  return out;
}

const FENCE_RE = /^\s*(`{3,}|~{3,})\s*([\w+-]*)\s*$/;
const CALLOUT_RE = new RegExp(`^\\s*>\\s?\\[!(${CALLOUT_KINDS.join("|")})\\]\\s*(.*)$`, "i");
const QUOTE_RE = /^\s*>/;
const LIST_RE = /^(\s*)(?:([-*+])|(\d+)[.)])\s+(.*)$/;
const HR_RE = /^\s{0,3}([-*_])(?:\s*\1){2,}\s*$/;
const HEAD_RE = /^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$/;
const indentOf = (l: string) => l.length - l.trimStart().length;

/** A heading's display text: an ask fork's `¶ASK_NAME:` anchor is for machines, not for reading. */
export function displayTitle(t: string): string {
  return t.replace(/^\s*(?:#{1,6}\s+)?(?:Q\d+\s+)?¶?ASK_[A-Za-z0-9_-]+\s*:\s*/, "").trim() || t.trim();
}

/** Split prose into blocks. Fenced code keeps its blank lines; a callout runs while lines start with `>`. */
export function blocks(text: string): Block[] {
  const lines = text.replace(/\r\n/g, "\n").split("\n");
  const out: Block[] = [];
  let para: string[] = [];
  const flush = () => {
    if (para.length) out.push({ t: "p", text: para.join(" ") });
    para = [];
  };
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const fence = line.match(FENCE_RE);
    if (fence) {
      flush();
      const close = fence[1];
      const body: string[] = [];
      i++;
      while (i < lines.length && !(lines[i].trim().startsWith(close[0].repeat(3)) && lines[i].trim().replace(/[`~]/g, "") === "")) body.push(lines[i++]);
      i++; // the closing fence (or the end)
      out.push({ t: "pre", lang: fence[2] ?? "", code: dedent(body).join("\n") });
      continue;
    }
    const callout = line.match(CALLOUT_RE);
    if (callout) {
      flush();
      const body: string[] = [];
      i++;
      while (i < lines.length && QUOTE_RE.test(lines[i])) body.push(lines[i++].replace(/^\s*>\s?/, ""));
      out.push({ t: "callout", kind: callout[1].toLowerCase() as CalloutKind, title: callout[2].trim(), body: body.join("\n").trim() });
      continue;
    }
    if (QUOTE_RE.test(line)) {
      flush();
      const body: string[] = [];
      while (i < lines.length && QUOTE_RE.test(lines[i])) body.push(lines[i++].replace(/^\s*>\s?/, ""));
      out.push({ t: "quote", text: body.join("\n").trim() });
      continue;
    }
    if (HR_RE.test(line)) {
      flush();
      out.push({ t: "hr" });
      i++;
      continue;
    }
    const h = line.match(HEAD_RE);
    if (h) {
      flush();
      out.push({ t: "h", level: h[1].length, text: displayTitle(h[2]) });
      i++;
      continue;
    }
    const li = line.match(LIST_RE);
    if (li) {
      flush();
      const base = li[1].length;
      const ordered = li[3] !== undefined;
      const items: string[] = [];
      const nested: string[][] = [];
      while (i < lines.length) {
        const l = lines[i];
        const m = l.match(LIST_RE);
        if (m && m[1].length <= base + 1 && (m[3] !== undefined) === ordered) {
          items.push(m[4]);
          nested.push([]);
        } else if (m && m[1].length <= base + 1) break; // a list of the other kind starts
        else if (!l.trim()) {
          // A blank line ends the list unless the next line is indented under it or is its next item.
          const next = lines.slice(i + 1).find((x) => x.trim());
          const nm = next?.match(LIST_RE);
          if (!next || !(indentOf(next) > base + 1 || (nm && nm[1].length <= base + 1 && (nm[3] !== undefined) === ordered))) break;
          if (nested[nested.length - 1].length) nested[nested.length - 1].push("");
        } else if (indentOf(l) > base + 1 || (!m && !nested[nested.length - 1].length && !HR_RE.test(l) && !QUOTE_RE.test(l) && !FENCE_RE.test(l) && indentOf(l) > base)) {
          // Indented under the item: a nested list or block goes in its body; a plain line continues its text.
          const body = nested[nested.length - 1];
          if (body.length || m || FENCE_RE.test(l) || QUOTE_RE.test(l)) body.push(l);
          else items[items.length - 1] += ` ${l.trim()}`;
        } else break;
        i++;
      }
      const block: Block = { t: "list", ordered, items };
      if (ordered && Number(li[3]) !== 1) block.start = Number(li[3]);
      if (nested.some((n) => n.some((x) => x.trim()))) block.nested = nested.map((n) => dedent(n).join("\n").trim());
      out.push(block);
      continue;
    }
    if (!line.trim()) flush();
    else para.push(line.trim());
    i++;
  }
  flush();
  return out;
}

function dedent(ls: string[]): string[] {
  const pads = ls.filter((l) => l.trim()).map((l) => l.length - l.trimStart().length);
  const n = pads.length ? Math.min(...pads) : 0;
  return ls.map((l) => l.slice(n));
}

/** Every link target in a piece of text, with its label, in order. */
export function linksIn(text: string): { href: string; label: string }[] {
  return inlineTokens(text).flatMap((t) => (t.t === "link" ? [{ href: t.href, label: t.label }] : t.t === "strong" || t.t === "em" ? linksIn(t.v) : []));
}
