/**
 * IDE-337: the links an ask's header names for its reader. `brief:` is one link; `proofs:` and
 * `reading:` are each a `;`-separated list of `[label](url-or-path)`. They are not in format.ts's
 * known fields yet, so they arrive through parseHeader's passthrough of any `key: value` line.
 *
 * An entry is a markdown link or a bare URL. A target that is http(s) is a link. A target that is a
 * path is shown with its path, because the client follows only http(s) links (rich.tsx safeHref)
 * and has no way to open a local file. Anything else, a malformed entry or another scheme, is kept
 * as plain text so the reader still sees what the asker wrote.
 */

export type AskRef =
  | { kind: "url"; label: string; href: string }
  | { kind: "path"; label: string; href: string }
  | { kind: "text"; label: string };

const LINK_RE = /^\[([^\[\]]*)\]\(([^()\s]*(?:\([^()\s]*\)[^()\s]*)*)\)$/;
const URL_RE = /^https?:\/\/\S+$/i;
/** A scheme such as `javascript:` or `data:`; a Windows drive letter is not one we expect here. */
const SCHEME_RE = /^[a-z][a-z0-9+.-]*:/i;

/** One entry, trimmed. Never throws, never returns nothing: an unreadable entry is text. */
export function parseRef(entry: string): AskRef {
  const s = entry.trim();
  const m = s.match(LINK_RE);
  if (m) {
    const label = m[1].trim() || m[2];
    const href = m[2];
    if (URL_RE.test(href)) return { kind: "url", label, href };
    if (href && !SCHEME_RE.test(href)) return { kind: "path", label, href };
    return { kind: "text", label: s };
  }
  if (URL_RE.test(s)) return { kind: "url", label: s, href: s };
  return { kind: "text", label: s };
}

/** A whole `[label](target)` anywhere in a list, so a `;` inside one does not split it. */
const LINK_SPAN_RE = /\[[^\[\]]*\]\([^()\s]*(?:\([^()\s]*\)[^()\s]*)*\)/g;

/**
 * A `;`-separated list. A `;` inside a complete `[label](target)` belongs to the label or the URL,
 * so it does not split. A label may not contain `[`, so an unclosed `[` protects nothing and cannot
 * swallow an entry before or after it. Only `[label](url)` protects a `;`: a bare URL that contains
 * one, such as `https://a.test/x;y=1`, is split there. Empty entries are dropped; every other entry
 * is kept, readable or not.
 */
export function refList(value: string | undefined): AskRef[] {
  if (!value?.trim()) return [];
  const inLink = new Set<number>();
  for (const m of value.matchAll(LINK_SPAN_RE)) {
    for (let i = m.index!; i < m.index! + m[0].length; i++) inLink.add(i);
  }
  const parts: string[] = [];
  let from = 0;
  for (let i = 0; i < value.length; i++) {
    if (value[i] === ";" && !inLink.has(i)) {
      parts.push(value.slice(from, i));
      from = i + 1;
    }
  }
  parts.push(value.slice(from));
  return parts.map((p) => p.trim()).filter(Boolean).map(parseRef);
}

/** The header's brief as one entry, or undefined when the field is absent or empty. */
export function briefRef(header: Record<string, string | undefined>): AskRef | undefined {
  const b = header.brief?.trim();
  return b ? parseRef(b) : undefined;
}
