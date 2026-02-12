# Pitfalls — Doc Search

Common gotchas when working with doc-search. Shares the sql.js WASM architecture with session-search — many pitfalls are identical.

## Shared Pitfalls (same as session-search)

These apply to both search tools. See `~/.claude/engine/tools/session-search/.directives/PITFALLS.md` for detailed explanations.

1. **Async `initDb()`** — Must `await`. Returns `Promise<Database>`, not `Database`. (§1)
2. **`db.exec()` empty result is `[]`** — Not `[{ values: [] }]`. Guard with optional chaining. (§3)
3. **Float32Array alignment** — Use `bytesToFloat32()` to copy to aligned buffer. (§5)
4. **PRAGMA journal_mode is meaningless** — sql.js runs in WASM memory. (§7)

## Doc-Search-Specific Pitfalls

### 1. Content-Addressed Embeddings

Doc-search uses `content_hash` as the primary key for embeddings (not `chunk_id` like session-search). Two chunks with identical content share one embedding row. This means:

*   **Deleting a doc_chunk doesn't cascade-delete the embedding** — other chunks may still reference it by `content_hash`.
*   **Inserting a duplicate `content_hash`** into `embeddings` will fail with a UNIQUE constraint error. Use `INSERT OR IGNORE` or check existence first.

### 2. `doc_chunks` Table, Not `chunks`

Doc-search uses `doc_chunks` (not `chunks`). The schema includes `project_name` and `branch` fields that session-search doesn't have. Queries must scope by project and branch:

```sql
-- BAD — returns results from all projects/branches
SELECT * FROM doc_chunks WHERE file_path LIKE '%README%';

-- GOOD — scoped to project and branch
SELECT * FROM doc_chunks WHERE project_name = ? AND branch = ? AND file_path LIKE '%README%';
```

### 3. Use `queryAll`/`queryOne`/`execute`, Not Raw `db.exec()`

Doc-search provides typed query helpers that handle statement lifecycle (`prepare` → `bind` → `step` → `free`). Unlike session-search's raw `db.exec()`, these return typed objects:

```typescript
// queryAll<T>() returns T[] (empty array if no rows)
// queryOne<T>() returns T | undefined

// BAD — raw db.exec() loses type safety
const result = db.exec("SELECT * FROM doc_chunks");

// GOOD — typed helper
const chunks = queryAll<DocChunk>(db, "SELECT * FROM doc_chunks WHERE branch = ?", ["main"]);
```

### 4. Schema Version Differs

Doc-search has `SCHEMA_VERSION = 1`, session-search has `SCHEMA_VERSION = 2`. They are independent — don't assume they match. Each tool manages its own database file.
