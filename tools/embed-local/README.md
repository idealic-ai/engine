# embed-local — the engine's one local embedding client

**This is the shared embedding module for the engine.** `tools/session-search`,
`tools/doc-search` and the director's ASKGROOM lane all embed through it. If you need
embeddings anywhere in the engine, import from here. Do not write a second client, and
do not copy the `EmbeddingClient` interface into your own package.

- **Runner**: Ollama `POST /api/embed` on loopback. The same request also works against
  `llama-server --embeddings`.
- **Model**: `embeddinggemma`, 768 dimensions (≈620 MB, `ollama pull embeddinggemma`).
- **Dependencies**: none. It uses plain `fetch` and `node:` built-ins.
- **No remote fallback** (operator ruling, 2026-10-29). When the runner is down or the
  model is missing you get a named error, never vectors of a different width.

Ported from `ideas/ai/embed/` (`local-provider.ts`, `config.ts`, `contract.ts`). Only the
local half was ported.

## Import

```ts
// from tools/<your-tool>/src/*.ts
import {
  createLocalEmbeddingClient,
  type EmbeddingClient,
  EmbedLocalError,
} from "../../embed-local/src/index.js";

const client = createLocalEmbeddingClient();      // config from process.env
const docs = await client.embedTexts(["stored text", "…"]); // DOCUMENT role, batched
const q = await client.embedSingle("what was decided"); // QUERY role
client.model;      // "embeddinggemma": store it beside each vector
client.dimensions; // 768: store it too
```

### Loaders: plain `node`, tsx, vitest or a bundler

The module ships TypeScript source only. It has no `main` or `exports` and no build step.
Its internal imports use `.ts` specifiers (`./config.ts`), so it loads under Node's own type
stripping as well as under `tsx`, vitest or vite: `node --no-warnings` can import
`tools/embed-local/src/index.ts` directly, which is how the ask app (plain Node) uses it. A
TypeScript project that type-checks a file importing it needs `allowImportingTsExtensions`
(session-search, doc-search and ask-app set it). Keep the source inside what type stripping
accepts: no enums, namespaces or constructor parameter properties.

From `tools/<tool>/src/`, import `../../embed-local/src/index.ts` (or `.js`, which tsx and the
bundler resolution map to the same file). From a deeper file, add one `../` per extra directory.

### ASKGROOM (`engine ask`, chunk 3)

The ask index's consumer is `tools/ask-app/src/lib/similar.ts`, so the import is:

```ts
// tools/ask-app/src/lib/similar.ts
import { createLocalEmbeddingClient, type EmbeddingClient } from "../../../embed-local/src/index.ts";
```

ask-app uses `.ts` specifiers (`allowImportingTsExtensions`) and runs as plain Node, which
this module now supports (above). The ask app's search index (`tools/ask-app/src/search/`,
IDE-334) already imports it that way.

The design embeds both sides of an ask-to-ask comparison in the document role, so call
`embed(texts, "document")` or `embedTexts`. Never use `embedSingle` there. For its 2 s
cap, pass `config: { ...resolveEmbedConfig(), timeoutMs: 2000 }`. A miss then arrives as
`RUNNER_TIMEOUT`, which the ask index reports as `timeout`.

`EmbeddingClient` is defined in `src/contract.ts`, and that file is its owner:

| member | meaning |
|---|---|
| `embedTexts(texts)` | Embeds in the **document** role, with the prefix `title: none \| text: `. Sends one request per `batchSize` texts. |
| `embedSingle(text)` | Embeds in the **query** role, with the prefix `task: search result \| query: `. |
| `model`, `dimensions` | The generation that produced the vectors. Callers store both on each row. |

The prefixes are part of embeddinggemma's contract. Leaving them off lowers retrieval
quality without any error. Both prefixes match ideas/ai exactly.

`createLocalEmbeddingClient(options)` also accepts:
- `config`
- `fetchImpl` (inject a fake in tests)
- `isDownloading`
- `onProgress(done, total)`
- `retry`: `{ attempts, baseDelayMs, maxDelayMs }`. It retries one batch that failed as
  `RUNNER_BUSY` or `RUNNER_TIMEOUT`, waiting `baseDelayMs` and then doubling each time.
  It is off by default, so a query on the activate path fails fast. Both indexers pass
  `INDEXER_EMBED_RETRY`, which allows 4 tries with waits of 2 s, 4 s and 8 s.
- `sleep` (inject a fake in tests)

The `LocalEmbeddingClient` it returns adds `embed(texts, role)` and `health()`.

## Configuration

| env | default |
|---|---|
| `ENGINE_EMBED_ENDPOINT` | `http://127.0.0.1:11434` |
| `ENGINE_EMBED_MODEL` | `embeddinggemma` |
| `ENGINE_EMBED_DIMENSIONS` | `768` |
| `ENGINE_EMBED_BATCH` | `32` |
| `ENGINE_EMBED_TIMEOUT_MS` | `120000` (per request, body included) |

A value that is not a positive whole number throws `CONFIG_INVALID`.

If you change the model or the width, you start a new index generation. The search tools
rank only rows whose stored model and width match the client's, and they re-embed every
other row on the next `index`.

## Named failures (`EmbedLocalError.code`)

| code | when it happens | what to do |
|---|---|---|
| `RUNNER_ABSENT` | Nothing is listening at the endpoint. | Start Ollama, or set `ENGINE_EMBED_ENDPOINT`. |
| `MODEL_ABSENT` | The runner returned 404 and no download is in flight. | `ollama pull embeddinggemma` |
| `MODEL_LOADING` | The runner returned 404 while a pull is in progress. | Wait for the pull to finish. |
| `RUNNER_LACKS_EMBEDDINGS` | The runner returned 501. | Start llama.cpp with `--embeddings`. |
| `RUNNER_BUSY` | The runner returned 503. | Retry, or lower `ENGINE_EMBED_BATCH`. The indexers retry it themselves. |
| `RUNNER_TIMEOUT` | The runner accepted the request and did not finish within `timeoutMs`. | Retry, lower `ENGINE_EMBED_BATCH`, or raise `ENGINE_EMBED_TIMEOUT_MS`. The indexers retry it themselves. |
| `DIMENSION_UNEXPECTED` | A returned vector is not `dimensions` wide. | Fix the config, then rebuild the index. |
| `PROVIDER_ERROR` | Any other non-2xx response, a body that is not JSON, or a vector count that does not match. | Read the message. |
| `EMPTY_TEXTS` | `embed([], …)` was called. (`embedTexts([])` returns `[]` instead.) | |
| `CONFIG_INVALID` | An env override is not a positive whole number. | Unset it or fix it. |

## Shell gate

`embed-local-gate.sh` defines `embed_local_gate`. All four search wrappers source it:
`scripts/{session,doc}-search.sh` and `tools/{session-search,doc-search}/*.sh`.

It exits 1 with `[embed-local] RUNNER_ABSENT: …` or `MODEL_ABSENT: …` on stderr. It reads
`ENGINE_EMBED_ENDPOINT` and `ENGINE_EMBED_MODEL`. It replaced the old `GEMINI_API_KEY` gate.

## Rollback hazard: roll the shell lib and the tools back together

The file names live in `scripts/search-db-lib.sh`. The schema check lives in the
TypeScript. If those two come from different versions of the engine, things go wrong:

- **Old tools with new scripts can wipe a `.local.db`.** This happens after a rollback of
  `tools/` while some `ENGINE_SCRIPTS` still points at a checkout from 4f4206b or later.
  The new lib exports `.session-search.local.db` or `.doc-search.local.db`, and the
  Gemini-era tools open it. Their only schema rule is "drop on mismatch", so they drop
  the local tables and refill them with Gemini vectors. Nothing written today can stop
  that, because the old code is already written.
- Afterwards the new tools refuse that same file: its schema is now Gemini-era.
- **New tools with an old lib** is the other direction. It is safe: the tools refuse the
  old file names (`.session-search.db`, `.doc-search.db`) and any schema other than their
  own, and they leave the file byte-identical.

To roll back, move `scripts/` and `tools/` to the same commit, then run `engine reindex`.
It deletes only the `.local.db` files, so a mixed window cannot leave a wrong-generation
index behind.

## Tests

```bash
cd tools/embed-local && npm test
```

This runs vitest with globals, borrowing session-search's binary, so this module installs
nothing. It then runs `test/gate.test.sh`, which serves a fake `/api/tags` through
python3's http.server. Nothing in the tests touches a real runner.
