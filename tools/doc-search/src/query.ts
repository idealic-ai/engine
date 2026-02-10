import type { Database, SqlValue } from "sql.js";
import type { EmbeddingClient } from "./embed.js";
import { bytesToFloat32, cosineSimilarity, similarityToDistance, queryAll } from "./db.js";

export interface SearchResult {
  projectName: string;
  branch: string;
  filePath: string;
  sectionTitle: string;
  distance: number;
  snippet: string;
}

export interface FileResult {
  filePath: string;
  branch: string;
  matches: SearchResult[];
}

export interface QueryFilters {
  branch?: string; // Filter by specific branch
  allBranches?: boolean; // Search all branches (not just current)
  allProjects?: boolean; // Search all projects (not just current)
  since?: number; // Unix ms timestamp — only docs modified on or after
  until?: number; // Unix ms timestamp — only docs modified before
}

/**
 * Group search results by file path, sorted by best match.
 */
export function groupResultsByFile(results: SearchResult[]): FileResult[] {
  if (results.length === 0) {
    return [];
  }

  const groups = new Map<string, SearchResult[]>();

  for (const result of results) {
    // Key by file path + branch to separate same file on different branches
    const key = `${result.branch}|||${result.filePath}`;
    const existing = groups.get(key);
    if (existing) {
      existing.push(result);
    } else {
      groups.set(key, [result]);
    }
  }

  // Sort matches within each file by distance (ascending)
  for (const matches of groups.values()) {
    matches.sort((a, b) => a.distance - b.distance);
  }

  const grouped: FileResult[] = [];
  for (const [, matches] of groups) {
    grouped.push({
      filePath: matches[0].filePath,
      branch: matches[0].branch,
      matches,
    });
  }

  // Sort files by their best match distance (ascending = most relevant first)
  grouped.sort((a, b) => a.matches[0].distance - b.matches[0].distance);

  return grouped;
}

/**
 * Perform semantic search over indexed documentation.
 *
 * 1. Embed the query text
 * 2. Load all embeddings and compute cosine similarity
 * 3. Join with doc_chunks table for metadata
 * 4. Filter by project_name (required) and optionally branch
 * 5. Return results sorted by distance
 */
export async function searchDocs(
  db: Database,
  queryText: string,
  embedder: EmbeddingClient,
  projectName: string,
  filters: QueryFilters = {},
  limit: number = 20
): Promise<SearchResult[]> {
  // 1. Embed the query
  const queryEmbedding = await embedder.embedSingle(queryText);

  // 2. Build filter clauses for doc_chunks
  const whereClauses: string[] = [];
  const params: SqlValue[] = [];

  // Project filter (unless --all-projects)
  if (!filters.allProjects) {
    whereClauses.push("c.project_name = ?");
    params.push(projectName);
  }

  // Branch filter (unless --all-branches)
  if (filters.branch && !filters.allBranches) {
    whereClauses.push("c.branch = ?");
    params.push(filters.branch);
  }

  // Time filters (mtime is Unix ms)
  if (filters.since != null) {
    whereClauses.push("c.mtime >= ?");
    params.push(filters.since);
  }
  if (filters.until != null) {
    whereClauses.push("c.mtime < ?");
    params.push(filters.until);
  }

  const filterClause = whereClauses.length > 0
    ? "WHERE " + whereClauses.join(" AND ")
    : "";

  // 3. Get all matching chunks with their embeddings
  const sql = `
    SELECT
      c.project_name,
      c.branch,
      c.file_path,
      c.section_title,
      c.snippet,
      e.embedding
    FROM doc_chunks c
    INNER JOIN embeddings e ON c.content_hash = e.content_hash
    ${filterClause}
  `;

  const rows = queryAll<{
    project_name: string;
    branch: string;
    file_path: string;
    section_title: string;
    snippet: string | null;
    embedding: Uint8Array;
  }>(db, sql, params);

  // 4. Compute cosine similarity for each row
  const results: SearchResult[] = [];
  for (const row of rows) {
    const embedding = bytesToFloat32(row.embedding);
    const similarity = cosineSimilarity(queryEmbedding, embedding);
    const distance = similarityToDistance(similarity);

    results.push({
      projectName: row.project_name,
      branch: row.branch,
      filePath: row.file_path,
      sectionTitle: row.section_title,
      distance,
      snippet: row.snippet ?? "",
    });
  }

  // 5. Sort by distance (ascending) and limit
  results.sort((a, b) => a.distance - b.distance);
  return results.slice(0, limit);
}
