import type { Database } from "sql.js";
import type { DocChunk } from "./chunker.js";
import type { EmbeddingClient } from "./embed.js";
import { float32ToBytes, queryAll, queryOne, execute } from "./db.js";

export interface IndexReport {
  inserted: number;
  updated: number;
  skipped: number;
  deleted: number;
  embeddingsReused: number;
  embeddingsCreated: number;
}

interface ExistingChunk {
  id: number;
  file_path: string;
  section_title: string;
  content_hash: string;
  mtime: number;
}

/**
 * Check if the global embeddings table holds this content at the embedder's
 * own model and width. A row from another generation does not count: it is
 * re-embedded and replaced, so a mixed index cannot build up.
 */
function hasCurrentEmbedding(db: Database, contentHash: string, embedder: EmbeddingClient): boolean {
  const row = queryOne<{ found: number }>(
    db,
    "SELECT 1 as found FROM embeddings WHERE content_hash = ? AND model = ? AND dimensions = ?",
    [contentHash, embedder.model, embedder.dimensions]
  );
  return row !== undefined;
}

/**
 * Reconcile a set of chunks against the database for a specific project+branch.
 *
 * Algorithm:
 * 1. Load existing chunks for this project+branch
 * 2. For each incoming chunk:
 *    a. Check mtime — if unchanged, skip (fast path)
 *    b. If mtime changed, check content_hash — if unchanged, update mtime only
 *    c. If content_hash changed:
 *       - Check if embedding exists globally (content-addressed reuse)
 *       - If not, embed and insert into embeddings table
 *       - Upsert doc_chunks with new hash
 * 3. Delete orphaned chunks (in DB but not in incoming set)
 * 4. Any incoming chunk — skipped ones included — whose content has no
 *    embedding at the embedder's model and width gets one (replacing a row
 *    left by another generation).
 */
export async function reconcileChunks(
  db: Database,
  chunks: DocChunk[],
  embedder: EmbeddingClient,
  projectName: string,
  branch: string
): Promise<IndexReport> {
  const report: IndexReport = {
    inserted: 0,
    updated: 0,
    skipped: 0,
    deleted: 0,
    embeddingsReused: 0,
    embeddingsCreated: 0,
  };

  if (chunks.length === 0) {
    // No chunks — delete all existing for this project+branch
    // Count first, then delete
    const countResult = queryOne<{ count: number }>(
      db,
      "SELECT COUNT(*) as count FROM doc_chunks WHERE project_name = ? AND branch = ?",
      [projectName, branch]
    );
    report.deleted = countResult?.count ?? 0;

    execute(
      db,
      "DELETE FROM doc_chunks WHERE project_name = ? AND branch = ?",
      [projectName, branch]
    );
    return report;
  }

  // 1. Load existing chunks for this project+branch
  const existingRows = queryAll<ExistingChunk>(
    db,
    `SELECT id, file_path, section_title, content_hash, mtime
     FROM doc_chunks
     WHERE project_name = ? AND branch = ?`,
    [projectName, branch]
  );

  const existingMap = new Map<string, ExistingChunk>();
  for (const row of existingRows) {
    const key = `${row.file_path}|||${row.section_title}`;
    existingMap.set(key, row);
  }

  // 2. Classify incoming chunks
  const toInsert: DocChunk[] = [];
  const toUpdate: { chunk: DocChunk; existingId: number }[] = [];
  const toUpdateMtimeOnly: { existingId: number; mtime: number }[] = [];
  const seenKeys = new Set<string>();

  for (const chunk of chunks) {
    const key = `${chunk.filePath}|||${chunk.sectionTitle}`;
    seenKeys.add(key);

    const existing = existingMap.get(key);
    if (!existing) {
      // New chunk
      toInsert.push(chunk);
    } else if (existing.mtime === chunk.mtime) {
      // Same mtime — assume unchanged (fast path)
      report.skipped++;
    } else if (existing.content_hash === chunk.contentHash) {
      // mtime changed but content same — just update mtime
      toUpdateMtimeOnly.push({ existingId: existing.id, mtime: chunk.mtime });
      report.skipped++;
    } else {
      // Content changed — need to update
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

  // 4. Collect content hashes that need embeddings at this model/width
  const hashesToEmbed: string[] = [];
  const hashToContent = new Map<string, string>();
  const changed = new Set<DocChunk>([...toInsert, ...toUpdate.map((u) => u.chunk)]);

  for (const chunk of chunks) {
    if (hashToContent.has(chunk.contentHash)) continue;
    if (!hasCurrentEmbedding(db, chunk.contentHash, embedder)) {
      hashesToEmbed.push(chunk.contentHash);
      hashToContent.set(chunk.contentHash, chunk.content);
    } else if (changed.has(chunk)) {
      report.embeddingsReused++;
    }
  }

  // 5. Embed new content
  let embeddings: Float32Array[] = [];
  if (hashesToEmbed.length > 0) {
    const textsToEmbed = hashesToEmbed.map((h) => hashToContent.get(h)!);
    embeddings = await embedder.embedTexts(textsToEmbed);
    report.embeddingsCreated = embeddings.length;
  }

  // 6. Execute DB operations

  // Write embeddings first (since chunks reference them via FK). REPLACE
  // overwrites a row another model/width left under the same content hash.
  for (let i = 0; i < hashesToEmbed.length; i++) {
    execute(
      db,
      "INSERT OR REPLACE INTO embeddings (content_hash, embedding, model, dimensions) VALUES (?, ?, ?, ?)",
      [hashesToEmbed[i], float32ToBytes(embeddings[i]), embedder.model, embedder.dimensions]
    );
  }

  // Insert new chunks
  for (const chunk of toInsert) {
    execute(
      db,
      `INSERT INTO doc_chunks (project_name, branch, file_path, section_title, content_hash, mtime, snippet)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [
        chunk.projectName,
        chunk.branch,
        chunk.filePath,
        chunk.sectionTitle,
        chunk.contentHash,
        chunk.mtime,
        chunk.snippet,
      ]
    );
    report.inserted++;
  }

  // Update changed chunks
  for (const { chunk, existingId } of toUpdate) {
    execute(
      db,
      `UPDATE doc_chunks
       SET content_hash = ?, mtime = ?, snippet = ?, indexed_at = datetime('now')
       WHERE id = ?`,
      [chunk.contentHash, chunk.mtime, chunk.snippet, existingId]
    );
    report.updated++;
  }

  // Update mtime-only changes
  for (const { existingId, mtime } of toUpdateMtimeOnly) {
    execute(
      db,
      `UPDATE doc_chunks
       SET mtime = ?, indexed_at = datetime('now')
       WHERE id = ?`,
      [mtime, existingId]
    );
  }

  // Delete orphaned chunks
  for (const id of toDelete) {
    execute(db, "DELETE FROM doc_chunks WHERE id = ?", [id]);
    report.deleted++;
  }

  return report;
}
