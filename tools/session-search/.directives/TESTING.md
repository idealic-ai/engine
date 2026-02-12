# Testing Standards — Session Search

Rules for testing the session-search tool. Tests use vitest and live in `src/__tests__/`.

## 1. Running Tests

```bash
cd ~/.claude/engine/tools/session-search

# Run all tests
npx vitest run

# Run in watch mode
npx vitest

# Run a specific test file
npx vitest run src/__tests__/db.test.ts
```

**Prerequisites**: `npm install` (or the dependencies are already installed).

## 2. Test Files

| File | What It Tests |
|------|---------------|
| `src/__tests__/db.test.ts` | SQLite database initialization, schema creation (chunks + embeddings tables), idempotency, unique index, session_date NOT NULL |
| `src/__tests__/indexer.test.ts` | Session indexing — insert, skip, update, delete, mixed operations, empty chunk list |
| `src/__tests__/query.test.ts` | Filter clause generation (after, before, since, until, file, tags, COALESCE fallback), grouping (by session, by file), vector search integration |
| `src/__tests__/chunker.test.ts` | Markdown chunking — heading hierarchy, breadcrumb titles, section splitting |
| `src/__tests__/scanner.test.ts` | Session directory scanning — file discovery, filtering |

## 3. Database Setup (async)

`initDb()` is **async** (WASM initialization). Tests use a shared `setupDb()` helper:

```typescript
async function setupDb(): Promise<{ db: Database; dbPath: string }> {
  const dbPath = path.join(
    os.tmpdir(),
    `session-search-test-${Date.now()}-${Math.random().toString(36).slice(2)}.db`
  );
  tmpDbs.push(dbPath);
  const db = await initDb(dbPath);
  return { db, dbPath };
}
```

**Rules**:
*   Always `await` the `setupDb()` / `initDb()` call. Forgetting `await` gives you a Promise object instead of a Database — every subsequent call fails silently.
*   `setupDb()` returns `{ db, dbPath }` — both are needed because `reconcileChunks()` requires `dbPath` for `saveDb()` calls.
*   Clean up temp DBs in `afterEach`. Never use a shared or real database path.

## 4. Schema: embeddings Table

The database uses two tables: `chunks` (metadata) and `embeddings` (vectors). Embeddings are stored as raw BLOB (`Float32Array` bytes), not in a sqlite-vec virtual table.

```sql
CREATE TABLE IF NOT EXISTS embeddings (
  chunk_id INTEGER PRIMARY KEY,
  embedding BLOB NOT NULL,
  FOREIGN KEY (chunk_id) REFERENCES chunks(id) ON DELETE CASCADE
);
```

**When testing schema**: Verify tables via `db.exec("SELECT name FROM sqlite_master WHERE type='table'")`. The result is `QueryExecResult[]` — access values via `result[0].values`.

## 5. sql.js Query API

sql.js uses `db.exec(sql)` which returns `QueryExecResult[]`:

```typescript
// db.exec() returns: [{ columns: string[], values: SqlValue[][] }]
const result = db.exec("SELECT count(*) FROM chunks");
const count = result[0]?.values[0]?.[0]; // number

// Empty result set: db.exec() returns [] (empty array)
const empty = db.exec("SELECT * FROM chunks WHERE 1=0");
// empty.length === 0, NOT [{ values: [] }]
```

**Key differences from better-sqlite3**:
*   No `db.prepare().all()` — use `db.exec()` or `db.run()` for mutations.
*   Empty results are `[]`, not `[{ values: [] }]`.
*   Use `db.run(sql, params)` for INSERT/UPDATE/DELETE.

## 6. Mocking the Embedding API

Tests that exercise the indexer or query path need Gemini embeddings mocked. Do NOT call the real API in tests:

```typescript
vi.mock("../embeddings.js", () => ({
  getEmbedding: vi.fn().mockResolvedValue(new Float32Array(768).fill(0.1)),
}));
```

## 7. COALESCE Filtering (--since / --until)

The `--since` and `--until` filters use COALESCE to handle sessions with and without `session_started_at`:

```sql
COALESCE(c.session_started_at, c.session_date || 'T00:00:00.000Z') >= ?
```

**When testing filters**: The `buildFilterClauses()` function is the unit test target. Test both cases: sessions with `session_started_at` populated and sessions without (fallback to `session_date`).

## 8. Conventions

*   **No `$GEMINI_API_KEY` in tests**: All API calls mocked. Tests must run offline.
*   **sql.js WASM**: The `sql.js` library uses WASM. Vitest handles this natively — no special config needed.
*   **ESM imports**: Use `.js` extensions in imports (`../db.js`, not `../db`). The project uses `"type": "module"`.
*   **See also**: `.directives/PITFALLS.md` for common gotchas.
