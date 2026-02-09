import type { Database } from "sql.js";
import type { EmbeddingClient } from "./embed.js";
import {
  bytesToFloat32,
  cosineSimilarity,
  similarityToDistance,
} from "./db.js";

const SNIPPET_LENGTH = 200;

export interface SearchResult {
  sessionPath: string;
  filePath: string;
  sectionTitle: string;
  distance: number;
  snippet: string;
}

export interface GroupedResult {
  sessionPath: string;
  sessionDate: string;
  matches: SearchResult[];
}

export interface FileResult {
  filePath: string;
  sessionPath: string;
  sessionDate: string;
  matches: SearchResult[];
}

export interface QueryFilters {
  after?: string; // YYYY-MM-DD
  before?: string; // YYYY-MM-DD
  file?: string; // glob pattern for file path
  tags?: string; // tag to search in content
}

interface ChunkWithEmbedding {
  id: number;
  sessionPath: string;
  sessionDate: string;
  filePath: string;
  sectionTitle: string;
  content: string;
  embedding: Float32Array;
}

/**
 * Build SQL WHERE clauses from filter options.
 * Returns clause fragments and parameter values.
 */
export function buildFilterClauses(filters: QueryFilters): {
  whereClauses: string[];
  params: (string | number)[];
} {
  const whereClauses: string[] = [];
  const params: (string | number)[] = [];

  if (filters.after) {
    whereClauses.push("c.session_date >= ?");
    params.push(filters.after);
  }

  if (filters.before) {
    whereClauses.push("c.session_date < ?");
    params.push(filters.before);
  }

  if (filters.file) {
    // Convert simple glob to SQL LIKE pattern
    const likePattern = `%${filters.file}%`;
    whereClauses.push("c.file_path LIKE ?");
    params.push(likePattern);
  }

  if (filters.tags) {
    // Search for tag in content
    whereClauses.push("c.content LIKE ?");
    params.push(`%${filters.tags}%`);
  }

  return { whereClauses, params };
}

/**
 * Extract date from session path.
 * e.g., "sessions/2026_02_04_TEST" -> "2026-02-04"
 */
function extractDateFromSessionPath(sessionPath: string): string {
  const match = sessionPath.match(/(\d{4})_(\d{2})_(\d{2})/);
  if (match) {
    return `${match[1]}-${match[2]}-${match[3]}`;
  }
  return "unknown";
}

/**
 * Group search results by session path, sorted by best match.
 */
export function groupResultsBySession(
  results: SearchResult[]
): GroupedResult[] {
  if (results.length === 0) {
    return [];
  }

  const groups = new Map<string, SearchResult[]>();

  for (const result of results) {
    const existing = groups.get(result.sessionPath);
    if (existing) {
      existing.push(result);
    } else {
      groups.set(result.sessionPath, [result]);
    }
  }

  // Sort matches within each group by distance (ascending)
  for (const matches of groups.values()) {
    matches.sort((a, b) => a.distance - b.distance);
  }

  // Convert to array and sort by best match per session
  const grouped: GroupedResult[] = [];
  for (const [sessionPath, matches] of groups) {
    grouped.push({
      sessionPath,
      sessionDate: extractDateFromSessionPath(sessionPath),
      matches,
    });
  }

  // Sort sessions by their best match distance (ascending)
  grouped.sort((a, b) => a.matches[0].distance - b.matches[0].distance);

  return grouped;
}

/**
 * Group search results by file path, sorted by best match.
 * Session name is preserved as a breadcrumb on each file group.
 */
export function groupResultsByFile(results: SearchResult[]): FileResult[] {
  if (results.length === 0) {
    return [];
  }

  const groups = new Map<string, SearchResult[]>();

  for (const result of results) {
    const existing = groups.get(result.filePath);
    if (existing) {
      existing.push(result);
    } else {
      groups.set(result.filePath, [result]);
    }
  }

  // Sort matches within each file by distance (ascending)
  for (const matches of groups.values()) {
    matches.sort((a, b) => a.distance - b.distance);
  }

  const grouped: FileResult[] = [];
  for (const [filePath, matches] of groups) {
    const sessionPath = matches[0].sessionPath;
    grouped.push({
      filePath,
      sessionPath,
      sessionDate: extractDateFromSessionPath(sessionPath),
      matches,
    });
  }

  // Sort files by their best match distance (ascending = most relevant first)
  grouped.sort((a, b) => a.matches[0].distance - b.matches[0].distance);

  return grouped;
}

/**
 * Load all chunks with embeddings from the database.
 * Applies optional filters.
 */
function loadChunksWithEmbeddings(
  db: Database,
  filters: QueryFilters
): ChunkWithEmbedding[] {
  const { whereClauses, params } = buildFilterClauses(filters);

  let filterClause = "";
  if (whereClauses.length > 0) {
    filterClause = "WHERE " + whereClauses.join(" AND ");
  }

  const sql = `
    SELECT
      c.id,
      c.session_path,
      c.session_date,
      c.file_path,
      c.section_title,
      c.content,
      e.embedding
    FROM chunks c
    INNER JOIN embeddings e ON e.chunk_id = c.id
    ${filterClause}
  `;

  const chunks: ChunkWithEmbedding[] = [];
  const stmt = db.prepare(sql);

  if (params.length > 0) {
    stmt.bind(params);
  }

  while (stmt.step()) {
    const row = stmt.get();
    // row is [id, session_path, session_date, file_path, section_title, content, embedding]
    const embeddingBytes = row[6] as Uint8Array;

    chunks.push({
      id: row[0] as number,
      sessionPath: row[1] as string,
      sessionDate: row[2] as string,
      filePath: row[3] as string,
      sectionTitle: row[4] as string,
      content: row[5] as string,
      embedding: bytesToFloat32(embeddingBytes),
    });
  }
  stmt.free();

  return chunks;
}

/**
 * Perform semantic search over indexed chunks.
 *
 * 1. Embed the query text
 * 2. Load all chunks with embeddings (with optional filters)
 * 3. Compute cosine similarity for each chunk
 * 4. Return top-k results sorted by distance
 */
export async function searchChunks(
  db: Database,
  queryText: string,
  embedder: EmbeddingClient,
  filters: QueryFilters,
  limit: number = 20
): Promise<SearchResult[]> {
  // 1. Embed the query
  const queryEmbedding = await embedder.embedSingle(queryText);

  // 2. Load all chunks with embeddings
  const chunks = loadChunksWithEmbeddings(db, filters);

  if (chunks.length === 0) {
    return [];
  }

  // 3. Compute similarity scores
  const scored = chunks.map((chunk) => ({
    chunk,
    similarity: cosineSimilarity(queryEmbedding, chunk.embedding),
  }));

  // 4. Sort by similarity (descending) and take top-k
  scored.sort((a, b) => b.similarity - a.similarity);
  const topK = scored.slice(0, limit);

  // 5. Convert to SearchResult format
  return topK.map(({ chunk, similarity }) => ({
    sessionPath: chunk.sessionPath,
    filePath: chunk.filePath,
    sectionTitle: chunk.sectionTitle,
    distance: similarityToDistance(similarity),
    snippet: chunk.content.slice(0, SNIPPET_LENGTH),
  }));
}
