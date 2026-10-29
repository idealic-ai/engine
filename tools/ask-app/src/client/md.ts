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
  | { t: "ticket"; key: string };

export const CALLOUT_KINDS = ["background", "term", "code", "evidence", "more"] as const;
export type CalloutKind = (typeof CALLOUT_KINDS)[number];

export type Block =
  | { t: "p"; text: string }
  | { t: "pre"; lang: string; code: string }
  | { t: "list"; ordered: boolean; items: string[] }
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
  }
  pushText(text.slice(at));
  return out;
}

const FENCE_RE = /^\s*(`{3,}|~{3,})\s*([\w+-]*)\s*$/;
const CALLOUT_RE = new RegExp(`^\\s*>\\s?\\[!(${CALLOUT_KINDS.join("|")})\\]\\s*(.*)$`, "i");
const QUOTE_RE = /^\s*>/;
const LIST_RE = /^\s*(?:([-*])|(\d+)[.)])\s+(.*)$/;

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
    const li = line.match(LIST_RE);
    if (li) {
      flush();
      const ordered = li[2] !== undefined;
      const items: string[] = [];
      while (i < lines.length) {
        const m = lines[i].match(LIST_RE);
        if (m && (m[2] !== undefined) === ordered) items.push(m[3]);
        else if (items.length && lines[i].trim() && /^\s{2,}/.test(lines[i])) items[items.length - 1] += ` ${lines[i].trim()}`;
        else break;
        i++;
      }
      out.push({ t: "list", ordered, items });
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
  return inlineTokens(text).flatMap((t) => (t.t === "link" ? [{ href: t.href, label: t.label }] : []));
}
