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
}

/**
 * Reconcile a set of chunks against the database.
 *
 * Algorithm:
 * 1. Build a lookup map of existing chunks keyed by (file_path, section_title)
 * 2. For each incoming chunk:
 *    - If not in DB: INSERT (new)
 *    - If in DB with same hash: SKIP (unchanged)
 *    - If in DB with different hash: UPDATE (changed)
 * 3. Any DB chunks not seen in incoming set: DELETE (orphaned)
 */
export async function reconcileChunks(
  db: Database,
  dbPath: string,
  chunks: Chunk[],
  embedder: EmbeddingClient
): Promise<IndexReport> {
  const report: IndexReport = {
    inserted: 0,
    updated: 0,
    skipped: 0,
    deleted: 0,
  };

  // 1. Load existing chunks from DB
  const existingRows: ExistingChunk[] = [];
  const stmt = db.prepare(
    "SELECT id, file_path, section_title, content_hash FROM chunks"
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
    } else if (existing.content_hash !== chunk.contentHash) {
      toUpdate.push({ chunk, existingId: existing.id });
    } else {
      report.skipped++;
    }
  }

  // 3. Find orphans (in DB but not in incoming set)
  const toDelete: number[] = [];
  for (const [key, row] of existingMap) {
    if (!seenKeys.has(key)) {
      toDelete.push(row.id);
    }
  }

  // 4. Embed new and updated chunks
  const textsToEmbed = [
    ...toInsert.map((c) => c.content),
    ...toUpdate.map((u) => u.chunk.content),
  ];

  let embeddings: Float32Array[] = [];
  if (textsToEmbed.length > 0) {
    embeddings = await embedder.embedTexts(textsToEmbed);
  }

  // 5. Execute DB operations
  let embeddingIndex = 0;

  // Insert new chunks
  for (const chunk of toInsert) {
    db.run(
      `INSERT INTO chunks (session_path, session_date, file_path, section_title, content, content_hash)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [
        chunk.sessionPath,
        chunk.sessionDate,
        chunk.filePath,
        chunk.sectionTitle,
        chunk.content,
        chunk.contentHash,
      ]
    );

    // Get the inserted ID
    const idResult = db.exec("SELECT last_insert_rowid()");
    const chunkId = idResult[0].values[0][0] as number;

    const embedding = embeddings[embeddingIndex++];
    const embeddingBytes = float32ToBytes(embedding);

    db.run(`INSERT INTO embeddings (chunk_id, embedding) VALUES (?, ?)`, [
      chunkId,
      embeddingBytes,
    ]);

    report.inserted++;
  }

  // Update changed chunks
  for (const { chunk, existingId } of toUpdate) {
    db.run(
      `UPDATE chunks
       SET content = ?, content_hash = ?, updated_at = datetime('now')
       WHERE id = ?`,
      [chunk.content, chunk.contentHash, existingId]
    );

    // Delete old embedding and insert new one
    db.run(`DELETE FROM embeddings WHERE chunk_id = ?`, [existingId]);

    const embedding = embeddings[embeddingIndex++];
    const embeddingBytes = float32ToBytes(embedding);

    db.run(`INSERT INTO embeddings (chunk_id, embedding) VALUES (?, ?)`, [
      existingId,
      embeddingBytes,
    ]);

    report.updated++;
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
