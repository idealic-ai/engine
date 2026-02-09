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

## 3. Coverage Gaps

Doc-search shares architecture with session-search (both use sql.js + Gemini embeddings). The following are untested and should follow session-search patterns:

*   **Database layer** (`db.ts`) — initialization, schema, migrations
*   **Indexer** (`indexer.ts`) — file discovery, chunking pipeline, deduplication
*   **Query** (`query.ts`) — semantic search, ranking, result formatting

When adding these tests, follow the session-search test patterns (temp DB isolation, embedding mocks, ESM imports with `.js` extensions).

## 4. Conventions

*   **No `$GEMINI_API_KEY` in tests**: All API calls mocked. Tests must run offline.
*   **Chunk content assertions**: Use `toContain` for content matching — exact string matching is brittle with whitespace normalization.
*   **sql.js WASM**: Vitest handles this natively — no special config needed.
*   **ESM imports**: Use `.js` extensions in imports (`../chunker.js`, not `../chunker`). The project uses `"type": "module"`.
