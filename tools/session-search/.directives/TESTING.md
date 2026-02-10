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
| `src/__tests__/db.test.ts` | SQLite database initialization, schema creation, migrations |
| `src/__tests__/indexer.test.ts` | Session indexing — file chunking, embedding storage, deduplication |
| `src/__tests__/query.test.ts` | Semantic search queries — ranking, filtering, result format |
| `src/__tests__/chunker.test.ts` | Markdown chunking — heading hierarchy, breadcrumb titles, section splitting |

## 3. Database Isolation

Tests create temporary SQLite databases in `os.tmpdir()`. Each test gets a fresh DB:

```typescript
function makeTmpDbPath(): string {
  const p = path.join(
    os.tmpdir(),
    `session-search-test-${Date.now()}-${Math.random().toString(36).slice(2)}.db`
  );
  tmpDbs.push(p);
  return p;
}

afterEach(() => {
  for (const p of tmpDbs) {
    try { fs.unlinkSync(p); } catch { /* ignore */ }
  }
  tmpDbs.length = 0;
});
```

**Rule**: Never use a shared or real database path. Always create temp DBs and clean up in `afterEach`.

## 4. Mocking the Embedding API

Tests that exercise the indexer or query path need Gemini embeddings mocked. Do NOT call the real API in tests:

```typescript
vi.mock("../embeddings.js", () => ({
  getEmbedding: vi.fn().mockResolvedValue(new Float32Array(768).fill(0.1)),
}));
```

## 5. Conventions

*   **No `$GEMINI_API_KEY` in tests**: All API calls mocked. Tests must run offline.
*   **sql.js WASM**: The `sql.js` library uses WASM. Vitest handles this natively — no special config needed.
*   **ESM imports**: Use `.js` extensions in imports (`../db.js`, not `../db`). The project uses `"type": "module"`.
