# Search Tool API Reference

Vector similarity search over SQLite, powered by sqlite-vec. All commands use the RPC dispatch pattern with Zod validation.

## Overview

**Namespace**: `search.*`
**Source**: `search/src/rpc/`
**DB**: sql.js WASM SQLite with sqlite-vec extension (cosine distance)

### Database Schema

*   **`chunks`** — Stores text fragments with metadata
    *   `id` INTEGER PRIMARY KEY
    *   `source_type` TEXT — "session" or "doc"
    *   `source_path` TEXT — file origin path
    *   `section_title` TEXT — heading or breadcrumb label
    *   `chunk_text` TEXT — the searchable content
    *   `content_hash` TEXT — SHA-256 of chunk_text (FK to embeddings)
    *   `updated_at` TEXT — ISO datetime
    *   UNIQUE(`source_path`, `section_title`)

*   **`embeddings`** — Stores vector embeddings (content-addressed)
    *   `content_hash` TEXT PRIMARY KEY — SHA-256 linking to chunks
    *   `embedding` BLOB — Float32Array buffer (3072 dims, Gemini)
    *   `updated_at` TEXT — ISO datetime

**Content-hash dedup**: Multiple chunks with identical text share one embedding row. Orphan cleanup runs after deletes.

---

## Commands

### `search.query`

Vector similarity search over stored chunks.

**Input**:
*   `embedding` (number[], required) — Query vector (Float32Array-compatible)
*   `sourceTypes` (string[], optional) — Filter by source_type. Empty/omitted = no filter.
*   `limit` (number, optional) — Max results. Default: 10.

**Output**:
*   `results` — Array of matches sorted by cosine distance ASC (0 = identical):
    *   `sourceType` — "session" or "doc"
    *   `sourcePath` — Origin file path
    *   `sectionTitle` — Heading label
    *   `chunkText` — Full chunk content
    *   `distance` — Cosine distance (0-1)

**Notes**: Uses `vec_distance_cosine()` from sqlite-vec. Two SQL paths: with sourceTypes filter (IN clause) and without (full scan). The embedding is converted to a Float32Array BLOB before passing to SQL.

---

### `search.upsert`

Insert or update a chunk and its embedding.

**Input**:
*   `sourceType` (string, required) — "session" or "doc"
*   `sourcePath` (string, required) — File origin path
*   `sectionTitle` (string, required) — Heading or breadcrumb label
*   `chunkText` (string, required) — Searchable content
*   `contentHash` (string, required) — SHA-256 of chunkText
*   `embedding` (number[], required) — Vector embedding

**Output**:
*   `chunkId` (number) — Row ID of the chunk
*   `contentHash` (string) — Stored content hash
*   `created` (boolean) — true if new, false if updated

**Notes**: Runs in a manual BEGIN/COMMIT/ROLLBACK transaction. Upserts embedding first (keyed by content_hash), then upserts chunk (keyed by source_path + section_title). Idempotent — re-upserting same content is safe. Content-hash dedup means multiple chunks can share one embedding.

---

### `search.delete`

Delete chunks by path and/or type, with orphan embedding cleanup.

**Input** (at least one required):
*   `sourcePath` (string, optional) — Delete chunks matching this path
*   `sourceType` (string, optional) — Delete chunks matching this type

**Output**:
*   `chunksDeleted` (number) — Chunks removed
*   `embeddingsDeleted` (number) — Orphaned embeddings cleaned up

**Notes**: Uses Zod `.refine()` to enforce at least one filter. After deleting chunks, runs `DELETE FROM embeddings WHERE content_hash NOT IN (SELECT DISTINCT content_hash FROM chunks)` to clean orphans. Transaction-wrapped.

---

### `search.status`

Aggregate statistics over the search index.

**Input**: None (empty object).

**Output**:
*   `totalChunks` (number) — Total chunks in DB
*   `totalEmbeddings` (number) — Total embeddings in DB
*   `bySourceType` (Record<string, number>) — Chunk count per source_type
*   `uniquePaths` (number) — Count of distinct source_path values

**Notes**: Runs 4 queries in parallel via `Promise.all`. No arguments needed.

---

### `search.sessions.reindex`

Scan session files, chunk, embed, and reconcile with the search index.

**Input**:
*   `sessionPaths` (string[], required, min 1) — Session directory paths to scan
*   `fileContents` (Record<string, string>, optional) — Pre-loaded file contents keyed by path. Avoids filesystem access (used in tests).

**Output** (ReindexReport):
*   `inserted` (number) — New chunks added
*   `updated` (number) — Changed chunks re-embedded
*   `skipped` (number) — Unchanged chunks (same content_hash)
*   `deleted` (number) — Orphaned chunks removed
*   `totalChunks` (number) — Total chunks processed from source

**Reconciliation**:
1. Scan all `.md` files → H2-level chunks via session-chunker
2. Scan `.state.json` files → searchKeywords + sessionDescription chunks
3. Compare incoming chunks against DB by `sourcePath::sectionTitle` key
4. Classify: new (insert + embed), changed hash (update + re-embed), same hash (skip)
5. Delete orphans (in DB but not in incoming set)
6. Clean orphaned embeddings

**Notes**: Uses `dispatch()` to call `search.upsert` and `ai.embed` internally. Source type is always "session".

---

### `search.docs.reindex`

Scan doc files, chunk with breadcrumb titles, embed, and reconcile.

**Input**:
*   `fileContents` (Record<string, string>, required) — File contents keyed by path. No filesystem access — caller provides all content.

**Output** (ReindexReport): Same structure as `search.sessions.reindex`.

**Reconciliation**: Same 5-step algorithm as sessions.reindex. Source type is always "doc". Uses doc-chunker (H1/H2/H3 breadcrumbs, tiny-merge) instead of session-chunker.

---

### `search.reindex` (stub)

Placeholder for a unified reindex entry point.

**Input**:
*   `sourceTypes` (string[], optional)

**Output**:
*   `status`: "not_implemented"
*   `message`: "Requires fs.* and ai.* RPCs"

**Notes**: Returns immediately. Use `search.sessions.reindex` or `search.docs.reindex` directly.

---

## Chunker Modules

### Session Chunker (`chunkers/session-chunker.ts`)

Splits session markdown files on H2 boundaries.

**Exports**:
*   `parseMarkdownChunks(markdown, sourcePath)` → `SessionChunk[]`
    *   Splits on `\n## ` boundaries
    *   Files with no H2 → single "(full document)" chunk
    *   Empty files → zero chunks
    *   Duplicate H2 titles get `##N` suffix (e.g., `"Title##1"`)
*   `parseStateJsonChunks(jsonContent, sourcePath)` → `SessionChunk[]`
    *   Extracts `searchKeywords` array → one chunk per keyword
    *   Extracts `sessionDescription` → one "session-description" chunk
    *   Invalid JSON → zero chunks
*   `computeContentHash(content)` → string (SHA-256 hex)

**SessionChunk interface**: `{ sourcePath, sectionTitle, chunkText, contentHash }`

---

### Doc Chunker (`chunkers/doc-chunker.ts`)

Splits doc files on H1/H2/H3 headers with breadcrumb titles.

**Exports**:
*   `parseChunks(markdown, filePath)` → `DocChunk[]`
    *   Splits on H1/H2/H3 headers (H4+ stay with parent)
    *   Breadcrumb titles: `"filename.md > H1 > H2 > H3"`
    *   No headers → single `"filename.md > (full document)"` chunk
    *   Content before first header → `"filename.md > (intro)"` chunk
    *   Tiny chunks (< 100 chars) merge with next sibling
    *   Duplicate breadcrumbs get `##N` suffix
*   `computeContentHash(content)` → string (SHA-256 hex)

**DocChunk interface**: `{ sourcePath, sectionTitle, chunkText, contentHash }`

**MIN_CHUNK_SIZE**: 100 characters. Chunks below this threshold are merged with the next sibling to avoid noise in search results.
