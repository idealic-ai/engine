import type { Database } from "sql.js";
import type { Chunk } from "./chunker.js";
import type { EmbeddingClient } from "./embed.js";
import { float32ToBytes, saveDb } from "./db.js";

export interface IndexReport {
  inserted: number;
  updated: number;
  skipped: number;
  deleted: number;
}

interface ExistingChunk {
  id: number;
  file_path: string;
  section_title: string;
  content_hash: string;
  /** Model/width of the stored embedding; null when the chunk has none. */
  model: string | null;
  dimensions: number | null;
}

export interface ReconcileOptions {
  /**
   * Embed, write and save in slabs of this many chunks, so a long rebuild
   * survives an interrupt: a re-run skips every slab already saved.
   */
  checkpointEvery?: number;
  /** Progress line sink; defaults to stderr. */
  log?: (line: string) => void;
}

const DEFAULT_CHECKPOINT_EVERY = 4096;

/**
 * Reconcile a set of chunks against the database.
 *
 * Algorithm:
 * 1. Build a lookup map of existing chunks keyed by (file_path, section_title)
 * 2. For each incoming chunk:
 *    - If not in DB: INSERT (new)
 *    - If in DB with same hash AND its embedding is the embedder's model and
 *      width: SKIP (unchanged)
 *    - Otherwise: UPDATE (changed, or embedded by another model/width)
 * 3. Any DB chunks not seen in incoming set: DELETE (orphaned)
 *
 * Inserts and updates are embedded and written in slabs, saving after each.
 */
export async function reconcileChunks(
  db: Database,
  dbPath: string,
  chunks: Chunk[],
  embedder: EmbeddingClient,
  options: ReconcileOptions = {}
): Promise<IndexReport> {
  const checkpointEvery = Math.max(1, options.checkpointEvery ?? DEFAULT_CHECKPOINT_EVERY);
  const log = options.log ?? ((line: string) => console.error(line));
  const report: IndexReport = {
    inserted: 0,
    updated: 0,
    skipped: 0,
    deleted: 0,
  };

  // 1. Load existing chunks from DB
  const existingRows: ExistingChunk[] = [];
  const stmt = db.prepare(
    `SELECT c.id, c.file_path, c.section_title, c.content_hash, e.model, e.dimensions
     FROM chunks c LEFT JOIN embeddings e ON e.chunk_id = c.id`
  );
  while (stmt.step()) {
    const row = stmt.getAsObject() as unknown as ExistingChunk;
    existingRows.push(row);
  }
  stmt.free();

  const existingMap = new Map<string, ExistingChunk>();
  for (const row of existingRows) {
    const key = `${row.file_path}|||${row.section_title}`;
    existingMap.set(key, row);
  }

  // 2. Classify incoming chunks
  const toInsert: Chunk[] = [];
  const toUpdate: { chunk: Chunk; existingId: number }[] = [];
  const seenKeys = new Set<string>();

  for (const chunk of chunks) {
    const key = `${chunk.filePath}|||${chunk.sectionTitle}`;
    seenKeys.add(key);

    const existing = existingMap.get(key);
    if (!existing) {
      toInsert.push(chunk);
    } else if (
      existing.content_hash === chunk.contentHash &&
      existing.model === embedder.model &&
      existing.dimensions === embedder.dimensions
    ) {
      report.skipped++;
    } else {
      toUpdate.push({ chunk, existingId: existing.id });
    }
  }

  // 3. Find orphans (in DB but not in incoming set)
  const toDelete: number[] = [];
  for (const [key, row] of existingMap) {
    if (!seenKeys.has(key)) {
      toDelete.push(row.id);
    }
  }

  // 4–5. Embed and write new and updated chunks, one checkpointed slab at a time
  type Work = { chunk: Chunk; existingId: number | null };
  const work: Work[] = [
    ...toInsert.map((chunk) => ({ chunk, existingId: null })),
    ...toUpdate.map(({ chunk, existingId }) => ({ chunk, existingId })),
  ];

  const writeEmbedding = (chunkId: number, embedding: Float32Array): void => {
    db.run(
      `INSERT INTO embeddings (chunk_id, embedding, model, dimensions) VALUES (?, ?, ?, ?)`,
      [chunkId, float32ToBytes(embedding), embedder.model, embedder.dimensions]
    );
  };

  for (let start = 0; start < work.length; start += checkpointEvery) {
    const slab = work.slice(start, start + checkpointEvery);
    const embeddings = await embedder.embedTexts(slab.map((w) => w.chunk.content));

    slab.forEach(({ chunk, existingId }, i) => {
      if (existingId === null) {
        db.run(
          `INSERT INTO chunks (session_path, session_date, file_path, section_title, content, content_hash, session_started_at, session_completed_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            chunk.sessionPath,
            chunk.sessionDate,
            chunk.filePath,
            chunk.sectionTitle,
            chunk.content,
            chunk.contentHash,
            chunk.sessionStartedAt ?? null,
            chunk.sessionCompletedAt ?? null,
          ]
        );
        const idResult = db.exec("SELECT last_insert_rowid()");
        writeEmbedding(idResult[0].values[0][0] as number, embeddings[i]);
        report.inserted++;
      } else {
        db.run(
          `UPDATE chunks
           SET content = ?, content_hash = ?, session_started_at = ?, session_completed_at = ?, updated_at = datetime('now')
           WHERE id = ?`,
          [chunk.content, chunk.contentHash, chunk.sessionStartedAt ?? null, chunk.sessionCompletedAt ?? null, existingId]
        );
        db.run(`DELETE FROM embeddings WHERE chunk_id = ?`, [existingId]);
        writeEmbedding(existingId, embeddings[i]);
        report.updated++;
      }
    });

    const done = Math.min(start + checkpointEvery, work.length);
    if (done < work.length) {
      saveDb(db, dbPath);
      log(`[session-search] embedded ${done}/${work.length} (checkpoint saved)`);
    }
  }

  // Delete orphaned chunks
  for (const id of toDelete) {
    db.run(`DELETE FROM embeddings WHERE chunk_id = ?`, [id]);
    db.run(`DELETE FROM chunks WHERE id = ?`, [id]);
    report.deleted++;
  }

  // Save database to disk
  saveDb(db, dbPath);

  return report;
}
