/**
 * IDE-334 (RAGPROOFS): text for the search index.
 *
 * `htmlToText` turns a proof page into plain text, keeping h1-h3 as markdown headings so the page can be
 * cut where its author cut it. `chunkSections` cuts text the way doc-search does (tools/doc-search/src/
 * chunker.ts): on H1-H3, each section titled by its breadcrumb ("page > H1 > H2 > H3"), a section whose
 * body is under 100 characters merged into the next one. It adds one thing doc-search lacks: a cap.
 *
 * The cap is measured, not guessed. embeddinggemma's context is 2,048 tokens and Ollama cuts longer input
 * silently (2026-10-30: two 71,640-character texts that differ only after the cut embedded to cosine 1.0;
 * with truncate:false Ollama answers 400). So a section longer than MAX_CHUNK_CHARS is split on paragraph
 * boundaries, then lines, then hard, into "(part n)" sections; 4,000 characters is about 1,000-1,400
 * tokens of prose, well under the context.
 */

export const MAX_CHUNK_CHARS = 4000;
const MIN_CHUNK_CHARS = 100;

export type TextChunk = { section: string; content: string };

const NAMED: Record<string, string> = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", mdash: "—", ndash: "–", hellip: "…",
  middot: "·", rarr: "→", larr: "←", harr: "↔", times: "×", rsquo: "’", lsquo: "‘", rdquo: "”", ldquo: "“",
  bull: "•", copy: "©", check: "✓", ge: "≥", le: "≤", ne: "≠", minus: "−", deg: "°", para: "¶", sect: "§",
};

export function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e: string) => {
    if (e[0] === "#") {
      const n = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      try {
        return Number.isFinite(n) ? String.fromCodePoint(n) : m;
      } catch {
        return m;
      }
    }
    return NAMED[e.toLowerCase()] ?? m;
  });
}

const stripTags = (s: string) => s.replace(/<[^>]*>/g, "");

/** The page's `<title>`, decoded; empty when it has none. */
export function pageTitle(html: string): string {
  const m = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  return m ? decodeEntities(stripTags(m[1])).replace(/\s+/g, " ").trim() : "";
}

/** The seat a published page names in its seat strip (`data-seat`), or "" when it carries none. */
export function publishedSeat(html: string): string {
  const m = html.match(/<!--prove-seat-strip:begin-->[\s\S]*?data-seat="([^"]*)"/);
  return m ? decodeEntities(m[1]).trim() : "";
}

/** A proof page as plain text: no head, scripts, styles, svg or comments; h1-h3 become `#` headings. */
export function htmlToText(html: string): string {
  let s = html
    // The publisher's seat strip (publish-s3.sh) is not the page's text, and without it a builds/ copy
    // and its published twin strip to the same text, which is how the two are deduped.
    .replace(/<!--prove-seat-strip:begin-->[\s\S]*?<!--prove-seat-strip:end-->/g, " ")
    .replace(/<!--[\s\S]*?-->/g, " ")
    .replace(/<head[\s>][\s\S]*?<\/head>/gi, " ")
    .replace(/<(script|style|noscript|svg|template|iframe|canvas)[\s>][\s\S]*?<\/\1>/gi, " ");
  s = s.replace(/<h([1-3])[^>]*>([\s\S]*?)<\/h\1>/gi, (_m, n: string, inner: string) => {
    const t = decodeEntities(stripTags(inner)).replace(/\s+/g, " ").trim();
    return t ? `\n\n${"#".repeat(Number(n))} ${t}\n\n` : "\n\n";
  });
  s = s
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/?(p|div|li|ul|ol|tr|table|thead|tbody|section|article|header|footer|main|nav|aside|pre|blockquote|details|summary|figure|figcaption|h[4-6]|dt|dd|dl|hr)\b[^>]*>/gi, "\n")
    .replace(/<\/(td|th)>/gi, " \t ");
  s = decodeEntities(stripTags(s));
  return s
    .split("\n")
    .map((l) => l.replace(/[ \t ]+/g, " ").trim())
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/** Split `body` into pieces no longer than `max`: on blank lines, then lines, then hard. */
function capPieces(body: string, max = MAX_CHUNK_CHARS): string[] {
  if (body.length <= max) return [body];
  const out: string[] = [];
  let cur = "";
  const push = () => {
    if (cur.trim()) out.push(cur.trim());
    cur = "";
  };
  const units = body.split(/\n\n+/).flatMap((p) => (p.length <= max ? [p] : p.split("\n")));
  for (const u of units) {
    if (u.length > max) {
      push();
      for (let i = 0; i < u.length; i += max) out.push(u.slice(i, i + max));
      continue;
    }
    if (cur && cur.length + 2 + u.length > max) push();
    cur = cur ? `${cur}\n\n${u}` : u;
  }
  push();
  return out;
}

/**
 * Text cut into sections. `docTitle` heads every breadcrumb, and names the text before the first heading.
 * Each chunk's `content` starts with its breadcrumb, so the heading path is part of what is embedded.
 */
export function chunkSections(text: string, docTitle: string): TextChunk[] {
  type Raw = { section: string; body: string };
  const raws: Raw[] = [];
  const trail: string[] = [];
  let cur: Raw = { section: docTitle, body: "" };
  for (const line of text.split("\n")) {
    const h = line.match(/^(#{1,3})\s+(.+?)\s*#*\s*$/);
    if (h) {
      raws.push(cur);
      const level = h[1].length;
      trail.length = level - 1;
      trail[level - 1] = h[2];
      cur = { section: [docTitle, ...trail.filter(Boolean)].join(" > "), body: "" };
    } else {
      cur.body += `${line}\n`;
    }
  }
  raws.push(cur);

  // Merge a short body forward (into the next section), as doc-search does; a short last one merges back.
  const merged: Raw[] = [];
  let carry = "";
  for (let i = 0; i < raws.length; i++) {
    const r = raws[i];
    const own = r.body.trim();
    const body = [carry, own].filter(Boolean).join("\n\n");
    if (own.length < MIN_CHUNK_CHARS && i < raws.length - 1) {
      // Carried forward with its own heading, so the merged text still says what it was.
      const heading = r.section === docTitle ? "" : r.section.split(" > ").pop()!;
      carry = [carry, own ? [heading, own].filter(Boolean).join("\n") : ""].filter(Boolean).join("\n\n");
      continue;
    }
    carry = "";
    if (!body) continue;
    merged.push({ section: r.section, body });
  }
  if (carry.trim()) {
    if (merged.length) merged[merged.length - 1].body += `\n\n${carry.trim()}`;
    else merged.push({ section: docTitle, body: carry.trim() });
  }

  const seen = new Map<string, number>();
  const out: TextChunk[] = [];
  for (const m of merged) {
    const n = (seen.get(m.section) ?? 0) + 1;
    seen.set(m.section, n);
    const base = n > 1 ? `${m.section} (${n})` : m.section;
    capPieces(m.body).forEach((piece, i) => {
      const section = i === 0 ? base : `${base} (part ${i + 1})`;
      out.push({ section, content: `${section}\n${piece}` });
    });
  }
  return out;
}

/** One named section as chunks: the whole body when it fits, else "(part n)" pieces under the cap. */
export function sectionChunks(section: string, body: string): TextChunk[] {
  const b = body.trim();
  if (!b) return [];
  return capPieces(b).map((piece, i) => {
    const s = i === 0 ? section : `${section} (part ${i + 1})`;
    return { section: s, content: `${s}\n${piece}` };
  });
}
