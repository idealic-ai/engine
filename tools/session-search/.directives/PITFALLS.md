# Pitfalls — Session Search

Common gotchas when working with session-search. Discovered during the sql.js WASM migration.

## 1. Async `initDb()` — Must Await

`initDb()` returns `Promise<Database>`, not `Database`. Forgetting `await` gives you a Promise object — every subsequent `db.exec()` / `db.run()` call fails with a cryptic error (calling methods on a Promise, not a Database).

```typescript
// BAD — db is a Promise, not a Database
const db = initDb(dbPath);
db.exec("SELECT 1"); // TypeError: db.exec is not a function

// GOOD
const db = await initDb(dbPath);
db.exec("SELECT 1"); // works
```

**Why it's async**: sql.js loads a WASM binary on first use. The `getSqlJs()` call caches the module after initialization.

## 2. `reconcileChunks()` Requires `dbPath`

The function signature is `reconcileChunks(db, dbPath, chunks, embedder)`. The `dbPath` is needed for `saveDb()` calls after mutations. If you omit `dbPath`, the `chunks` argument gets treated as `dbPath` (a string), and `embedder` becomes `chunks` — causing silent type confusion at runtime.

```typescript
// BAD — missing dbPath, silent misalignment
await reconcileChunks(db, chunks, embedder);

// GOOD
await reconcileChunks(db, dbPath, chunks, embedder);
```

## 3. `db.exec()` Empty Result Is `[]`

sql.js `db.exec()` returns `QueryExecResult[]`. For queries with no matching rows, it returns an **empty array** `[]`, not `[{ columns: [...], values: [] }]`.

```typescript
const result = db.exec("SELECT * FROM chunks WHERE 1=0");
// result === [] (length 0)
// NOT [{ columns: [...], values: [] }]

// Guard pattern:
const count = result[0]?.values[0]?.[0] ?? 0;
```

## 4. Schema: `embeddings` Table, Not `vec_chunks`

The old sqlite-vec virtual table (`vec_chunks`) was replaced with a plain `embeddings` table storing BLOB data. References to `vec_chunks` or `vec_version()` are stale.

| Old (sqlite-vec) | New (sql.js) |
|---|---|
| `vec_chunks` virtual table | `embeddings` plain table |
| `vec_version()` function | Does not exist |
| sqlite-vec distance function | JS `cosineSimilarity()` |

## 5. Float32Array Alignment

When converting `Uint8Array` (from BLOB) back to `Float32Array`, the byte array may not be aligned to a 4-byte boundary. Always copy to a fresh `ArrayBuffer`:

```typescript
// BAD — may throw on misaligned buffer
const floats = new Float32Array(bytes.buffer);

// GOOD — bytesToFloat32() copies to aligned buffer
const floats = bytesToFloat32(bytes);
```

## 6. COALESCE for Time Filtering

`--since` / `--until` filters use COALESCE because older sessions lack `session_started_at`:

```sql
COALESCE(c.session_started_at, c.session_date || 'T00:00:00.000Z') >= ?
```

When testing, ensure test data covers both cases: sessions with and without `session_started_at`.

## 7. PRAGMA journal_mode Is Meaningless

sql.js runs in-memory (WASM). PRAGMA journal_mode returns `"memory"` regardless of settings. Don't write tests for it — it provides no useful signal.
