/**
 * IDE-334 (RAGPROOFS): a query over the search index.
 *
 * The query is embedded in the query role and compared by cosine with every chunk embedded at the same
 * model and width. Hits are grouped by item: an item scores its best chunk, and its excerpt comes from that
 * chunk, so a hit names the fork or section it came from. A small lexical bonus (up to 0.1) lifts a hit
 * whose title or best section holds the query's words literally, so an exact id or ticket key ranks first.
 *
 * Vectors are cached in memory per index generation (the `generation` meta the indexer bumps on every
 * change), so a server answers repeated queries without re-reading the database.
 *
 * Failures are `SearchUnavailable`, with a `reason` a caller can show: the index is missing or empty, or the
 * embedder could not embed the query. A failure is never an empty result.
 */
import { isEmbedLocalError, type EmbeddingClient } from "../../../embed-local/src/index.ts";
import { bytesToFloat32, getMeta, type SearchDb } from "./db.ts";
import { KINDS, type Kind } from "./sources.ts";

export type SearchHit = {
  kind: Kind;
  seat: string;
  id: string;
  title: string;
  status: string;
  score: number;
  excerpt: string;
  url: string | null;
  appPath: string | null;
  section: string;
};

export type UnavailableReason = "index-missing" | "index-empty" | "index-error" | "embedder-unavailable";

export class SearchUnavailable extends Error {
  // Plain fields, not parameter properties: the app runs under node's type stripping, which refuses those.
  readonly reason: UnavailableReason;
  readonly code?: string;
  constructor(reason: UnavailableReason, message: string, code?: string) {
    super(message);
    this.reason = reason;
    if (code !== undefined) this.code = code;
  }
}

/**
 * Every searchable chunk's vector in one contiguous matrix (row i = chunk i), normalised, so ranking is one
 * tight loop of dot products. Measured on this machine's index (25,755 chunks, 768-d): an array of 25k
 * separate Float32Arrays ranked in 300-800 ms per query; the matrix is what keeps a query near the cost
 * of embedding it.
 */
type Matrix = { n: number; d: number; mat: Float32Array; chunkIds: Int32Array; itemKeys: string[]; kinds: Kind[] };
const cache = new WeakMap<SearchDb, { generation: string; model: string; m: Matrix }>();

function vectors(db: SearchDb, e: EmbeddingClient): Matrix {
  const generation = getMeta(db, "generation") ?? "0";
  const model = `${e.model}:${e.dimensions}`;
  const hit = cache.get(db);
  if (hit && hit.generation === generation && hit.model === model) return hit.m;
  const rows = db
    .prepare(
      `SELECT c.id AS id, c.item_key AS item_key, i.kind AS kind, e.embedding AS embedding
       FROM chunks c JOIN items i ON i.key = c.item_key JOIN embeddings e ON e.content_hash = c.content_hash
       WHERE i.dup_of IS NULL AND e.model = ? AND e.dimensions = ?`,
    )
    .all(e.model, e.dimensions) as { id: number; item_key: string; kind: Kind; embedding: Uint8Array }[];
  const d = e.dimensions;
  const m: Matrix = { n: rows.length, d, mat: new Float32Array(rows.length * d), chunkIds: new Int32Array(rows.length), itemKeys: [], kinds: [] };
  rows.forEach((r, i) => {
    m.mat.set(normalise(bytesToFloat32(r.embedding)), i * d);
    m.chunkIds[i] = r.id;
    m.itemKeys.push(r.item_key);
    m.kinds.push(r.kind);
  });
  cache.set(db, { generation, model, m });
  return m;
}

function normalise(v: Float32Array): Float32Array {
  let n = 0;
  for (let i = 0; i < v.length; i++) n += v[i] * v[i];
  n = Math.sqrt(n) || 1;
  for (let i = 0; i < v.length; i++) v[i] /= n;
  return v;
}


export function terms(q: string): string[] {
  return q.toLowerCase().split(/\s+/).map((t) => t.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, "")).filter((t) => t.length > 1);
}

/** About `width` characters of `body` around the first query word found in it, else its start. */
export function excerptOf(body: string, words: string[], width = 240): string {
  const flat = body.replace(/\s+/g, " ").trim();
  const low = flat.toLowerCase();
  const at = Math.min(...words.map((w) => low.indexOf(w)).filter((i) => i >= 0));
  const start = Number.isFinite(at) ? Math.max(0, at - Math.floor(width / 3)) : 0;
  const end = Math.min(flat.length, start + width);
  return `${start > 0 ? "…" : ""}${flat.slice(start, end).trim()}${end < flat.length ? "…" : ""}`;
}

export type SearchOptions = { q: string; limit?: number; kinds?: Kind[] };

export async function search(db: SearchDb, embedder: EmbeddingClient, opts: SearchOptions): Promise<SearchHit[]> {
  const limit = Math.max(1, Math.min(100, opts.limit ?? 20));
  const kinds = new Set(opts.kinds?.length ? opts.kinds : KINDS);
  let items: number;
  try {
    items = (db.prepare("SELECT count(*) AS n FROM items WHERE dup_of IS NULL").get() as { n: number }).n;
  } catch (e) {
    throw new SearchUnavailable("index-error", `the search index could not be read: ${(e as Error).message}`);
  }
  if (items === 0) throw new SearchUnavailable("index-empty", "the search index is empty: it has not finished its first pass");
  let qv: Float32Array;
  try {
    qv = normalise(await embedder.embedSingle(opts.q));
  } catch (e) {
    if (isEmbedLocalError(e)) throw new SearchUnavailable("embedder-unavailable", `the query could not be embedded: ${e.code}`, e.code);
    throw new SearchUnavailable("embedder-unavailable", `the query could not be embedded: ${(e as Error).message}`);
  }
  const best = new Map<string, { score: number; chunkId: number }>();
  const m = vectors(db, embedder);
  for (let i = 0; i < m.n; i++) {
    if (!kinds.has(m.kinds[i])) continue;
    let s = 0;
    const off = i * m.d;
    for (let j = 0; j < m.d; j++) s += qv[j] * m.mat[off + j];
    const b = best.get(m.itemKeys[i]);
    if (!b || s > b.score) best.set(m.itemKeys[i], { score: s, chunkId: m.chunkIds[i] });
  }
  const words = terms(opts.q);
  const itemQ = db.prepare("SELECT kind, seat, id, title, status, url, app_path FROM items WHERE key = ?");
  const chunkQ = db.prepare("SELECT section, body FROM chunks WHERE id = ?");
  // Score every candidate's lexical bonus only for the top of the cosine ranking: cheap and enough.
  const pool = [...best.entries()].sort((a, b) => b[1].score - a[1].score).slice(0, Math.max(limit * 5, 50));
  const hits: SearchHit[] = pool.map(([key, b]) => {
    const it = itemQ.get(key) as { kind: Kind; seat: string; id: string; title: string; status: string; url: string | null; app_path: string | null };
    const ch = chunkQ.get(b.chunkId) as { section: string; body: string };
    const hay = `${it.title} ${it.id} ${ch.section} ${ch.body}`.toLowerCase();
    const found = words.length ? words.filter((w) => hay.includes(w)).length / words.length : 0;
    return {
      kind: it.kind,
      seat: it.seat,
      id: it.id,
      title: it.title,
      status: it.status,
      score: Math.round((b.score + 0.1 * found) * 10000) / 10000,
      excerpt: excerptOf(ch.body, words),
      url: it.url,
      appPath: it.app_path,
      section: ch.section,
    };
  });
  return hits.sort((a, b) => b.score - a.score).slice(0, limit);
}

/** When the last completed pass ran (ISO), and how many items are searchable. */
export function indexState(db: SearchDb): { indexedAt: string | null; items: number; chunks: number; lastReport: unknown } {
  const items = (db.prepare("SELECT count(*) AS n FROM items WHERE dup_of IS NULL").get() as { n: number }).n;
  const chunks = (db.prepare("SELECT count(*) AS n FROM chunks").get() as { n: number }).n;
  const r = getMeta(db, "last_report");
  return { indexedAt: getMeta(db, "last_index_at") ?? null, items, chunks, lastReport: r ? JSON.parse(r) : null };
}
