# Testing Standards — Doc Search

Rules for testing the doc-search tool. Tests use vitest and live in `src/__tests__/`.

## 1. Running Tests

```bash
cd ~/.claude/engine/tools/doc-search

# Run all tests
npx vitest run

# Run in watch mode
npx vitest

# Run a specific test file
npx vitest run src/__tests__/chunker.test.ts
```

**Prerequisites**: `npm install` (or the dependencies are already installed).

## 2. Test Files

| File | What It Tests |
|------|---------------|
| `src/__tests__/chunker.test.ts` | Markdown chunking — heading hierarchy, breadcrumb titles, preamble handling, tiny chunk merging |
| `src/__tests__/query.test.ts` | Semantic search queries — ranking, filtering, branch scoping |

## 3. Coverage Gaps

Doc-search shares architecture with session-search (both use sql.js + Gemini embeddings). The following are untested and should follow session-search test patterns:

*   **Database layer** (`db.ts`) — async `initDb()`, schema creation (`doc_chunks` + `embeddings` tables), schema versioning
*   **Indexer** — file discovery, chunking pipeline, deduplication

When adding these tests, follow session-search patterns but note the schema differences below.

## 4. Doc-Search vs Session-Search Differences

Doc-search shares the sql.js WASM architecture but has a different schema and API layer:

| Aspect | session-search | doc-search |
|--------|---------------|------------|
| Metadata table | `chunks` | `doc_chunks` |
| Embeddings key | `chunk_id` (integer FK) | `content_hash` (text PK, content-addressed) |
| Query helpers | Raw `db.exec()` / `db.run()` | `queryAll<T>()`, `queryOne<T>()`, `execute()` helpers |
| Scope | Session paths + dates | Project + branch + file paths |
| Time filtering | `--since` / `--until` with COALESCE | N/A (no time-based filtering) |

**Content-addressed embeddings**: Doc-search deduplicates embeddings by `content_hash`. If two doc chunks have identical content, they share one embedding row. Tests should verify this dedup behavior.

**Query helpers**: Unlike session-search (which uses raw `db.exec()`), doc-search provides typed helpers:

```typescript
// queryAll<T>(db, sql, params) — returns T[]
const chunks = queryAll<DocChunk>(db, "SELECT * FROM doc_chunks WHERE branch = ?", ["main"]);

// queryOne<T>(db, sql, params) — returns T | undefined
const chunk = queryOne<DocChunk>(db, "SELECT * FROM doc_chunks WHERE id = ?", [1]);

// execute(db, sql, params) — void (INSERT/UPDATE/DELETE)
execute(db, "DELETE FROM doc_chunks WHERE project_name = ?", ["old-project"]);
```

## 5. Database Setup (async)

Same async pattern as session-search — `initDb()` returns `Promise<Database>`:

```typescript
async function setupDb(): Promise<{ db: Database; dbPath: string }> {
  const dbPath = path.join(os.tmpdir(), `doc-search-test-${Date.now()}.db`);
  tmpDbs.push(dbPath);
  const db = await initDb(dbPath);
  return { db, dbPath };
}
```

**Rules**:
*   Always `await` the `initDb()` call. See session-search's `.directives/PITFALLS.md` §1 for the failure mode.
*   Clean up temp DBs in `afterEach`.

## 6. Conventions

*   **No `$GEMINI_API_KEY` in tests**: All API calls mocked. Tests must run offline.
*   **Chunk content assertions**: Use `toContain` for content matching — exact string matching is brittle with whitespace normalization.
*   **sql.js WASM**: Vitest handles this natively — no special config needed.
*   **ESM imports**: Use `.js` extensions in imports (`../chunker.js`, not `../chunker`). The project uses `"type": "module"`.
*   **See also**: `.directives/PITFALLS.md` for common gotchas.
