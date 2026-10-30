/**
 * IDE-334 (RAGPROOFS): the incremental indexer.
 *
 * For each source, in order: list it; for each item whose stamp moved (or that is new), read it; when its
 * text hash is unchanged, refresh the row and keep its chunks; otherwise re-chunk it and embed only the
 * chunk contents with no embedding at this model and width (content-addressed, so an unchanged section of a
 * changed page costs nothing). Items a successful listing no longer names are deleted with their chunks.
 * Last, embeddings no chunk refers to are deleted: the "stale embeddings never pruned" gap, closed here.
 *
 * Proof dedupe: a proof whose stripped text is the same as another proof's (a builds/ copy of a published
 * page) is kept as a row with `dup_of` set and no chunks, so it costs no embedding and never shows twice.
 * The bucket is listed first, so the published page is the one kept. A copy whose twin goes away, or that
 * gains one, is re-read on the next pass.
 *
 * A failed embedding stops the pass. What was written before it stays, and the items not written keep their
 * old stamp, so the next pass retries exactly them.
 */
import fs from "node:fs";
import type { EmbeddingClient } from "../../../embed-local/src/index.ts";
import { float32ToBytes, getMeta, inTransaction, setMeta, type SearchDb } from "./db.ts";
import { sha, type ItemBody, type Source, type SourceItem } from "./sources.ts";

export type IndexReport = {
  sources: Record<string, { ok: boolean; error?: string; listed: number }>;
  added: number;
  changed: number;
  unchanged: number;
  touched: number;
  deleted: number;
  duplicates: number;
  unreadable: number;
  embeddingsCreated: number;
  embeddingsReused: number;
  embeddingsPruned: number;
  ms: number;
  error?: string;
};

type Row = { key: string; stamp: string; text_hash: string; dup_of: string | null; source: string };
type Pending = { source: string; item: SourceItem; body: ItemBody; isNew: boolean };

const READ_POOL = 8;
const FLUSH_TEXTS = 64;

function emptyReport(): IndexReport {
  return { sources: {}, added: 0, changed: 0, unchanged: 0, touched: 0, deleted: 0, duplicates: 0, unreadable: 0, embeddingsCreated: 0, embeddingsReused: 0, embeddingsPruned: 0, ms: 0 };
}

/** The proof (other than `key`) that already holds this text, preferring a published one. */
function twinOf(db: SearchDb, key: string, textHash: string, pendingTwins: Map<string, string>): string | undefined {
  const row = db
    .prepare("SELECT key FROM items WHERE kind = 'proof' AND text_hash = ? AND key <> ? AND dup_of IS NULL ORDER BY (source = 'proof-bucket') DESC, key LIMIT 1")
    .get(textHash, key) as { key: string } | undefined;
  if (row) return row.key;
  const p = pendingTwins.get(textHash);
  return p && p !== key ? p : undefined;
}

function upsertItem(db: SearchDb, source: string, key: string, stamp: string, b: ItemBody, dupOf: string | null) {
  db.prepare(
    `INSERT INTO items (key, source, kind, seat, id, title, status, url, app_path, stamp, text_hash, dup_of, indexed_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
     ON CONFLICT(key) DO UPDATE SET source = excluded.source, kind = excluded.kind, seat = excluded.seat, id = excluded.id,
       title = excluded.title, status = excluded.status, url = excluded.url, app_path = excluded.app_path, stamp = excluded.stamp,
       text_hash = excluded.text_hash, dup_of = excluded.dup_of, indexed_at = excluded.indexed_at`,
  ).run(key, source, b.kind, b.seat, b.id, b.title, b.status, b.url, b.appPath, stamp, b.textHash, dupOf);
}

function hasEmbedding(db: SearchDb, hash: string, e: EmbeddingClient): boolean {
  return db.prepare("SELECT 1 AS x FROM embeddings WHERE content_hash = ? AND model = ? AND dimensions = ?").get(hash, e.model, e.dimensions) !== undefined;
}

/** Embed what the pending items need, then write them, each item's row and chunks together. */
async function flush(db: SearchDb, pending: Pending[], embedder: EmbeddingClient, report: IndexReport) {
  if (pending.length === 0) return;
  const need = new Map<string, string>();
  for (const p of pending) {
    for (const c of p.body.chunks) {
      const h = sha(c.content);
      if (need.has(h)) continue;
      if (hasEmbedding(db, h, embedder)) report.embeddingsReused++;
      else need.set(h, c.content);
    }
  }
  const hashes = [...need.keys()];
  const vectors = hashes.length ? await embedder.embedTexts(hashes.map((h) => need.get(h)!)) : [];
  inTransaction(db, () => {
    const ins = db.prepare("INSERT OR REPLACE INTO embeddings (content_hash, embedding, model, dimensions) VALUES (?, ?, ?, ?)");
    hashes.forEach((h, i) => ins.run(h, float32ToBytes(vectors[i]), embedder.model, embedder.dimensions));
    const chunk = db.prepare("INSERT INTO chunks (item_key, section, content_hash, body) VALUES (?, ?, ?, ?)");
    for (const p of pending) {
      upsertItem(db, p.source, p.item.key, p.item.stamp, p.body, null);
      db.prepare("DELETE FROM chunks WHERE item_key = ?").run(p.item.key);
      for (const c of p.body.chunks) {
        const nl = c.content.indexOf("\n");
        chunk.run(p.item.key, c.section, sha(c.content), nl >= 0 ? c.content.slice(nl + 1) : c.content);
      }
      if (p.isNew) report.added++;
      else report.changed++;
    }
  });
  report.embeddingsCreated += hashes.length;
  pending.length = 0;
}

export type IndexOptions = {
  /** Called once per source with how many items it listed (the CLI prints progress from it). */
  onSource?: (name: string, listed: number) => void;
  /** Re-read every item, ignoring stamps (a model change does this on its own). */
  full?: boolean;
  /**
   * The meta key that records when this pass completed: `last_index_at` (the default) for a pass over every
   * source, which is what freshness is judged by; a pass over the asks alone records `last_asks_index_at`.
   */
  stampKey?: string;
};

/** One incremental pass over `sources`. Never throws for a source or an embedding failure: the report says. */
export async function indexSources(db: SearchDb, sources: Source[], embedder: EmbeddingClient, opts: IndexOptions = {}): Promise<IndexReport> {
  const t0 = Date.now();
  const report = emptyReport();
  const generation = `${embedder.model}:${embedder.dimensions}`;
  const full = opts.full || getMeta(db, "embedder") !== generation;
  const pendingTwins = new Map<string, string>();
  let changedAny = false;
  try {
    for (const src of sources) {
      const listing = await src.list();
      report.sources[src.name] = { ok: listing.ok, ...(listing.error ? { error: listing.error } : {}), listed: listing.items.length };
      opts.onSource?.(src.name, listing.items.length);
      if (!listing.ok) continue;
      const pending: Pending[] = [];
      const pendingTexts = () => pending.reduce((n, p) => n + p.body.chunks.length, 0);
      const seen = new Set<string>();
      const get = db.prepare("SELECT key, stamp, text_hash, dup_of, source FROM items WHERE key = ?");

      for (let i = 0; i < listing.items.length; i += READ_POOL) {
        const batch = listing.items.slice(i, i + READ_POOL);
        const rows = batch.map((it) => get.get(it.key) as Row | undefined);
        const toRead = batch.map((it, j) => {
          seen.add(it.key);
          const row = rows[j];
          if (full || !row || row.stamp !== it.stamp) return true;
          if (src.kind !== "proof") return false;
          // An unchanged proof is re-read when its dedupe no longer holds: a twin gone, or a twin gained.
          if (row.dup_of) {
            const t = db.prepare("SELECT 1 AS x FROM items WHERE key = ? AND text_hash = ? AND dup_of IS NULL").get(row.dup_of, row.text_hash);
            return t === undefined;
          }
          return twinOf(db, it.key, row.text_hash, pendingTwins) !== undefined && src.name !== "proof-bucket";
        });
        const bodies = await Promise.all(batch.map((it, j) => (toRead[j] ? it.read() : Promise.resolve(undefined))));
        for (let j = 0; j < batch.length; j++) {
          const it = batch[j];
          const row = rows[j];
          if (!toRead[j]) {
            report.unchanged++;
            if (src.kind === "proof" && row && !row.dup_of) pendingTwins.set(row.text_hash, it.key);
            continue;
          }
          const body = bodies[j];
          if (!body) {
            // Unreadable now: keep whatever the index has, so a blip does not drop a page.
            report.unreadable++;
            continue;
          }
          if (src.kind === "proof" && src.name !== "proof-bucket") {
            const twin = twinOf(db, it.key, body.textHash, pendingTwins);
            if (twin) {
              inTransaction(db, () => {
                upsertItem(db, src.name, it.key, it.stamp, body, twin);
                db.prepare("DELETE FROM chunks WHERE item_key = ?").run(it.key);
              });
              report.duplicates++;
              changedAny = true;
              continue;
            }
          }
          if (src.kind === "proof") pendingTwins.set(body.textHash, it.key);
          if (!full && row && !row.dup_of && row.text_hash === body.textHash) {
            // Same text: the stamp moved (a touch, a re-save); the row is refreshed and the chunks kept.
            upsertItem(db, src.name, it.key, it.stamp, body, null);
            report.touched++;
            continue;
          }
          pending.push({ source: src.name, item: it, body, isNew: !row });
          changedAny = true;
          if (pendingTexts() >= FLUSH_TEXTS) await flush(db, pending, embedder, report);
        }
      }
      await flush(db, pending, embedder, report);

      // Prune: rows this source wrote that its listing no longer names.
      const gone = (db.prepare("SELECT key FROM items WHERE source = ?").all(src.name) as { key: string }[]).filter((r) => !seen.has(r.key));
      if (gone.length) {
        inTransaction(db, () => {
          const del = db.prepare("DELETE FROM items WHERE key = ?");
          for (const g of gone) del.run(g.key);
        });
        report.deleted += gone.length;
        changedAny = true;
      }
    }
    setMeta(db, "embedder", generation);
  } catch (e) {
    report.error = (e as Error).message;
  }
  const pruned = db.prepare("DELETE FROM embeddings WHERE content_hash NOT IN (SELECT content_hash FROM chunks)").run();
  report.embeddingsPruned = Number(pruned.changes);
  if (changedAny || report.embeddingsPruned) setMeta(db, "generation", String(Number(getMeta(db, "generation") ?? "0") + 1));
  report.ms = Date.now() - t0;
  if (!report.error) setMeta(db, opts.stampKey ?? "last_index_at", new Date().toISOString());
  setMeta(db, "last_report", JSON.stringify(report));
  return report;
}

/**
 * One indexer at a time per database, across processes: `<db>.lock` holds the holder's pid. A lock whose
 * pid is gone is taken over. Returns a release function, or null when a live process holds it.
 */
export function tryIndexLock(dbFile: string): (() => void) | null {
  const lock = `${dbFile}.lock`;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      fs.writeFileSync(lock, String(process.pid), { flag: "wx" });
      return () => {
        try {
          if (fs.readFileSync(lock, "utf8").trim() === String(process.pid)) fs.unlinkSync(lock);
        } catch {
          /* already gone */
        }
      };
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code !== "EEXIST") throw e;
      const pid = Number(fs.readFileSync(lock, "utf8").trim());
      let alive = false;
      try {
        process.kill(pid, 0);
        alive = pid > 0;
      } catch (k) {
        alive = (k as NodeJS.ErrnoException).code === "EPERM";
      }
      if (alive) return null;
      try {
        fs.unlinkSync(lock);
      } catch {
        /* someone else took it over first */
      }
    }
  }
  return null;
}
