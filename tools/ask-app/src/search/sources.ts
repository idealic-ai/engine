/**
 * IDE-334 (RAGPROOFS): what the search index reads, as four sources.
 *
 *   asks         every `<root>/<seat>/<id>.md`, all statuses: one section for the card (title, why, context,
 *                lean, note), one per fork (its title, prose, card lines, options, and the answer on it),
 *                one for the answer as a whole (decline reason, note, follow-ups)
 *   broadcasts   every `<BROADCAST_DIR>/<id>.md`: the `## Text`, cut on its headings
 *   proof-bucket every page the local proof store lists (lib/proofs.ts), fetched over its public URL
 *   proof-files  every `<sessions dir>/<session>/builds/*_PROOF.html`, deduped against the bucket by the
 *                hash of the stripped text (the indexer does the dedupe)
 *
 * Listing a source is cheap: a readdir and a stat, or one bucket listing. Each item carries a `stamp` (mtime
 * and size, or the bucket's LastModified and size) that the indexer compares, and reads the item only when
 * the stamp moved. A source whose listing failed says so (`ok: false`), and the indexer then prunes nothing
 * from it: a proof store that is down must not empty the index of proofs.
 */
import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { parseAskFile } from "../lib/format.ts";
import { defaultBroadcastDir, parseBroadcast } from "../lib/broadcasts.ts";
import { listProofs } from "../lib/proofs.ts";
import { askAppBase } from "../lib/url.ts";
import { displayTitle } from "../client/md.ts";
import { answerInWords } from "../client/model.ts";
import { chunkSections, htmlToText, pageTitle, publishedSeat, sectionChunks, type TextChunk } from "./text.ts";

export type Kind = "ask" | "proof" | "broadcast";
export const KINDS: readonly Kind[] = ["ask", "proof", "broadcast"];

export type ItemMeta = { kind: Kind; seat: string; id: string; title: string; status: string; url: string | null; appPath: string | null };
export type ItemBody = ItemMeta & { chunks: TextChunk[]; textHash: string };
export type SourceItem = { key: string; stamp: string; read(): Promise<ItemBody | null> };
export type SourceListing = { ok: boolean; error?: string; items: SourceItem[] };
export type Source = { name: string; kind: Kind; list(): Promise<SourceListing> };

export const sha = (s: string) => createHash("sha256").update(s).digest("hex");

/** The hash an item's text is compared by: every chunk, in order, plus the fields a hit shows. */
export function bodyHash(meta: ItemMeta, chunks: TextChunk[]): string {
  return sha(JSON.stringify([meta.title, meta.status, meta.seat, meta.url, chunks.map((c) => [c.section, c.content])]));
}

/** The text hash a proof is deduped by: the page's stripped text only, so a builds/ copy and its bucket twin agree. */
export function proofTextHash(text: string): string {
  return sha(text);
}

const seg = (s: string) => encodeURIComponent(s).replace(/%3A/gi, ":").replace(/%40/g, "@");
const plain = (s: string) => s.replace(/[*_`#>]+/g, "").replace(/\[([^\]]*)\]\([^)]*\)/g, "$1").replace(/\s+/g, " ").trim();

// ── asks ──────────────────────────────────────────────────────────────

/** One ask file as an item body, or null when it does not parse. */
export function askBody(root: string, seat: string, file: string, text: string): ItemBody | null {
  let a;
  try {
    a = parseAskFile(text);
  } catch {
    return null;
  }
  const id = a.header.id || path.basename(file, ".md");
  const title = plain(displayTitle(a.questions[0]?.title ?? id)) || id;
  const status = a.header.status || "open";
  const h = a.header;
  const card = [
    title,
    h.why && `Why: ${h.why}`,
    h.context && `Context: ${h.context}`,
    h.stakes && `Stakes: ${h.stakes}`,
    h.alternatives && `Alternatives: ${h.alternatives}`,
    h.lean && `Lean: ${h.lean}`,
    h.falsifier && `Falsifier: ${h.falsifier}`,
    h.note && `Note: ${h.note}`,
    `From ${h.from ?? seat} to ${h.to ?? "?"}, ${status}`,
    a.preamble,
  ].filter(Boolean).join("\n");
  const chunks: TextChunk[] = [...sectionChunks(title, card)];
  const words = answerInWords(a, a.answer);
  a.questions.forEach((q, i) => {
    const opts: string[] = [];
    const walk = (os: typeof q.options, depth: number) => {
      for (const o of os) {
        opts.push(`${"  ".repeat(depth)}- ${o.code ? `[${o.code}] ` : ""}${o.label}${o.description ? `: ${o.description}` : ""}`);
        walk(o.children ?? [], depth + 1);
      }
    };
    walk(q.options, 0);
    const w = words[i];
    const fork = plain(displayTitle(q.title));
    const body = [
      fork,
      q.prose,
      ...Object.entries(q.meta).map(([k, v]) => `${k}: ${v}`),
      ...q.evidence.map((e) => `Evidence: ${e}`),
      opts.join("\n"),
      q.proseAfter,
      w && w.picks.length ? `Answer: ${w.picks.join(", ")}` : "",
      w?.note ? `Answer note: ${w.note}` : "",
    ].filter(Boolean).join("\n");
    chunks.push(...sectionChunks(`${title} > ${fork}`, body));
  });
  const ans = a.answer;
  const answerText = [
    ans?.declined ? `Declined: ${ans.reason ?? ""}` : "",
    ans?.note ? `Note: ${ans.note}` : "",
    ans?.answeredBy ? `Answered by ${ans.answeredBy}${ans.answeredAt ? ` at ${ans.answeredAt}` : ""}` : "",
    ...a.followups.map((f) => `Follow-up (${f.kind}): ${f.text}`),
    h.withdrawnReason ? `Withdrawn: ${h.withdrawnReason}` : "",
  ].filter(Boolean).join("\n");
  chunks.push(...sectionChunks(`${title} > Answer`, answerText));
  // Section titles are unique per item (a fork title can repeat across forks).
  const seen = new Map<string, number>();
  for (const c of chunks) {
    const n = (seen.get(c.section) ?? 0) + 1;
    seen.set(c.section, n);
    if (n > 1) c.section = `${c.section} (${n})`;
  }
  const meta: ItemMeta = { kind: "ask", seat, id, title, status, url: `${askAppBase(root)}/a/${seg(seat)}/${seg(id)}`, appPath: `/a/${seg(seat)}/${seg(id)}` };
  return { ...meta, chunks, textHash: bodyHash(meta, chunks) };
}

export function askSource(root: string): Source {
  return {
    name: "asks",
    kind: "ask",
    async list() {
      let seats: string[];
      try {
        seats = fs.readdirSync(root, { withFileTypes: true }).filter((d) => d.isDirectory() && !d.name.startsWith(".")).map((d) => d.name);
      } catch (e) {
        // A root that does not exist yet has no asks; any other failure is a failed listing.
        if ((e as NodeJS.ErrnoException).code === "ENOENT") return { ok: true, items: [] };
        return { ok: false, error: `asks root not readable (${(e as NodeJS.ErrnoException).code ?? "error"})`, items: [] };
      }
      const items: SourceItem[] = [];
      for (const seat of seats) {
        for (const f of fs.readdirSync(path.join(root, seat))) {
          if (!f.endsWith(".md") || f.startsWith(".")) continue;
          const file = path.join(root, seat, f);
          let st: fs.Stats;
          try {
            st = fs.statSync(file);
          } catch {
            continue;
          }
          items.push({
            key: `ask:${seat}/${f.slice(0, -3)}`,
            stamp: `${st.mtimeMs}:${st.size}`,
            read: async () => {
              try {
                return askBody(root, seat, file, fs.readFileSync(file, "utf8"));
              } catch {
                return null;
              }
            },
          });
        }
      }
      return { ok: true, items };
    },
  };
}

// ── broadcasts ────────────────────────────────────────────────────────

export function broadcastSource(root: string, dir = defaultBroadcastDir()): Source {
  return {
    name: "broadcasts",
    kind: "broadcast",
    async list() {
      let names: string[];
      try {
        names = fs.readdirSync(dir);
      } catch (e) {
        if ((e as NodeJS.ErrnoException).code === "ENOENT") return { ok: true, items: [] };
        return { ok: false, error: "broadcast dir not readable", items: [] };
      }
      const items: SourceItem[] = [];
      const now = Date.now();
      for (const n of names) {
        if (!n.endsWith(".md")) continue;
        const file = path.join(dir, n);
        let text: string;
        let st: fs.Stats;
        try {
          st = fs.statSync(file);
          text = fs.readFileSync(file, "utf8");
        } catch {
          continue;
        }
        const b = parseBroadcast(n.slice(0, -3), text, [], now);
        const status = b.inForce ? "in-force" : "expired";
        items.push({
          key: `broadcast:${n.slice(0, -3)}`,
          // In force is a function of the clock too, so it is part of the stamp.
          stamp: `${st.mtimeMs}:${st.size}:${status}`,
          read: async () => {
            const firstLine = plain(b.text.split("\n").find((l) => l.trim()) ?? "") || b.id;
            const title = firstLine.length > 120 ? `${firstLine.slice(0, 119)}…` : firstLine;
            const chunks = chunkSections(b.text, title);
            const meta: ItemMeta = { kind: "broadcast", seat: b.from, id: b.id, title, status, url: `${askAppBase(root)}/broadcasts/${seg(b.id)}`, appPath: `/broadcasts/${seg(b.id)}` };
            return { ...meta, chunks, textHash: bodyHash(meta, chunks) };
          },
        });
      }
      return { ok: true, items };
    },
  };
}

// ── proofs ────────────────────────────────────────────────────────────

/** A proof page as an item body. `textHash` is the stripped text's hash, which the dedupe compares. */
export function proofBody(html: string, m: { id: string; fallbackTitle: string; seat: string; status: string; url: string | null; appPath: string | null }): ItemBody {
  const text = htmlToText(html);
  const title = pageTitle(html) || m.fallbackTitle;
  const seat = publishedSeat(html) || m.seat;
  const meta: ItemMeta = { kind: "proof", seat, id: m.id, title, status: m.status, url: m.url, appPath: m.appPath };
  return { ...meta, chunks: chunkSections(text, title), textHash: proofTextHash(text) };
}

export function proofBucketSource(fetchImpl: typeof fetch = fetch): Source {
  return {
    name: "proof-bucket",
    kind: "proof",
    async list() {
      const l = await listProofs(true);
      if (!l.ok) return { ok: false, error: l.error ?? "proof store not reachable", items: [] };
      return {
        ok: true,
        items: l.proofs.map((p) => ({
          key: `proof:${p.key}`,
          stamp: `${p.modified}:${p.size}`,
          read: async () => {
            try {
              const r = await fetchImpl(p.url, { signal: AbortSignal.timeout(15_000) });
              if (!r.ok) return null;
              return proofBody(await r.text(), { id: p.key, fallbackTitle: p.title, seat: p.owner, status: "published", url: p.url, appPath: `/proofs/${p.key.split("/").map(seg).join("/")}` });
            } catch {
              return null;
            }
          },
        })),
      };
    },
  };
}

/** ASK_SEARCH_PROOF_DIRS (colon-separated sessions dirs), else every ~/.claude/data/<x>/sessions and ~/Projects/<x>/sessions. */
export function defaultProofDirs(): string[] {
  const env = process.env.ASK_SEARCH_PROOF_DIRS;
  if (env !== undefined) return env.split(":").filter(Boolean);
  const out: string[] = [];
  for (const parent of [path.join(os.homedir(), ".claude", "data"), path.join(os.homedir(), "Projects")]) {
    try {
      for (const d of fs.readdirSync(parent)) out.push(path.join(parent, d, "sessions"));
    } catch {
      /* no such parent */
    }
  }
  return out;
}

export function proofFileSource(dirs = defaultProofDirs()): Source {
  return {
    name: "proof-files",
    kind: "proof",
    async list() {
      const files = new Set<string>();
      for (const d of dirs) {
        let real: string;
        try {
          real = fs.realpathSync(d);
        } catch {
          continue; // a configured dir that does not exist holds no proofs
        }
        let sessions: string[] = [];
        try {
          sessions = fs.readdirSync(real);
        } catch {
          continue;
        }
        for (const s of sessions) {
          const builds = path.join(real, s, "builds");
          let names: string[];
          try {
            names = fs.readdirSync(builds);
          } catch {
            continue;
          }
          for (const n of names) if (n.endsWith("_PROOF.html")) files.add(path.join(builds, n));
        }
      }
      const items: SourceItem[] = [];
      for (const file of [...files].sort()) {
        let st: fs.Stats;
        try {
          st = fs.statSync(file);
        } catch {
          continue;
        }
        const session = path.basename(path.dirname(path.dirname(file)));
        const id = `${session}/${path.basename(file)}`;
        items.push({
          key: `proof-file:${file}`,
          stamp: `${st.mtimeMs}:${st.size}`,
          read: async () => {
            try {
              return proofBody(fs.readFileSync(file, "utf8"), { id, fallbackTitle: path.basename(file, "_PROOF.html"), seat: "", status: "local", url: null, appPath: null });
            } catch {
              return null;
            }
          },
        });
      }
      return { ok: true, items };
    },
  };
}

/** The sources the server and the CLI index, in the order the dedupe needs (the bucket before the files). */
export function defaultSources(root: string): Source[] {
  const off = new Set((process.env.ASK_SEARCH_SOURCES_OFF ?? "").split(",").filter(Boolean));
  return [askSource(root), broadcastSource(root), proofBucketSource(), proofFileSource()].filter((s) => !off.has(s.name));
}
