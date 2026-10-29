# Document Indexing System

Semantic search over project documentation and session history using LOCAL embeddings (Ollama `embeddinggemma`, 768-d, through `tools/embed-local`) + SQLite (sql.js).

## Overview

The engine provides two indexing tools for RAG-style context retrieval:

| Tool | Purpose | Scope | Database |
|------|---------|-------|----------|
| `session-search` | Search session history | `sessions/**/*.md` | `~/.claude/cache/search-db/<namespace>/.session-search.local.db` |
| `doc-search` | Search project documentation | the project's configured roots (see Roots); default `docs/**/*.md`, `{apps,packages}/*/docs/**/*.md` | `~/.claude/cache/search-db/<namespace>/.doc-search.local.db` |

Both DBs live on **local disk**, outside any repo, so no `.gitignore` entry is
needed anywhere. `<namespace>` comes from the sessions path — `yarik/finch/sessions`
on a shared drive, `<project>-<checksum>/sessions` otherwise — so two projects
never share a file. Override the cache root with `ENGINE_SEARCH_DB_DIR`.

A DB left in `sessions/` from before this change is migrated automatically the
next time you run `index`, and the old copy is removed. Migration never happens
on `query`: `sessions/` is frequently a Google Drive mount where a single read
can return nothing for minutes. The wrapper scripts own the path (via
`scripts/search-db-lib.sh`) and pass it to the CLIs as `ENGINE_SEARCH_DB_PATH` —
the TypeScript never re-derives it.

Both tools share the same architecture:
- **Local embeddings** through `tools/embed-local` — Ollama `embeddinggemma`, 768 dimensions, document/query role prefixes, no key and no network, and **no remote fallback**
- **Per-row generation**: every embedding row stores `model` + `dimensions`; a query ranks only rows of its own model and width, and the next `index` re-embeds any other row (so a mixed index cannot build up)
- **SQLite + sqlite-vec** for vector storage and KNN search
- **Content-addressed deduplication** (same content = same embedding)

## doc-search

### Usage

```bash
# Index documentation for current project
~/.claude/tools/doc-search/doc-search.sh index

# One glob under the project root, instead of the configured roots
~/.claude/tools/doc-search/doc-search.sh index --path "packages/*/docs/**/*.md"

# Show which folders index reads, with file counts (no embedding)
~/.claude/tools/doc-search/doc-search.sh roots

# Query for information (filters to current branch by default)
~/.claude/tools/doc-search/doc-search.sh query "how does matching work"

# Search across all branches
~/.claude/tools/doc-search/doc-search.sh query "error handling" --all-branches

# Filter to specific branch
~/.claude/tools/doc-search/doc-search.sh query "schema design" --branch main

# Limit results
~/.claude/tools/doc-search/doc-search.sh query "API endpoints" --limit 5
```

### Roots (which folders are indexed)

A project names its documentation roots in a JSON file. The first one found wins:

1. `$DOC_SEARCH_CONFIG` — **applies to every project** the shell indexes, so set it per command, not in a shell profile
2. `<project>/.doc-search.json` (meant to be committed with the project)
3. `<project>/.claude/doc-search.json` (local; many projects keep `.claude/` out of git)

With none of them, the default is `docs/**/*.md` and `{apps,packages}/*/docs/**/*.md` under the project root, read exactly as before configs existed (including any `node_modules` those globs reach); `index --path GLOB` is read the same way: every path fast-glob returns is stored as it was, a symlinked alias or a symlink loop included. When the project root resolves to the home directory (a worktree without its own `.claude/` walks up to `~/.claude`), the two config files are not looked for, so a `doc-search.json` in `~/.claude/` cannot become every such run's config; an explicit `$DOC_SEARCH_CONFIG` is still honoured there, and one naming a missing file is still an error. The engine names no project's folders itself.

```json
{
  "roots": [
    { "name": "kit", "path": ".", "tracked": true,
      "globs": ["docs/**/*.md", "handbook/**/*.md", "*/docs/**/*.md", "*/*.md", ".directives/**/*.md"],
      "ignore": ["**/CHANGELOG.md"] },
    { "name": "engine", "path": "~/.claude/engine", "globs": ["docs/**/*.md", ".directives/**/*.md"] }
  ]
}
```

- `path` is relative to the project root or starts with `~/`. It never depends on the working directory, so an index started from a subdirectory or a session hook reads the same files.
- `tracked: true` keeps only files git tracks under that root, so build output and scratch folders drop out without an ignore list. A new doc is therefore not indexed until it is `git add`-ed. Files inside an initialised git submodule under the root count as tracked (`git ls-files --recurse-submodules`). A `tracked` root that git cannot list (not in a work tree, or git not runnable) is skipped with a warning carrying git's own message; the other roots still index.
- A configured root never reads `**/node_modules/**`.
- In a config, a file reached twice — by overlapping roots or through a symlinked alias — is indexed once, under the first root that reached it (compared by real path). The no-config default and `--path` do not do this, so their row keys stay as they were.
- A file inside the project is stored by its project-relative path; a file outside it (the engine root above) by its absolute path, so a result can be opened as printed.
- A root whose folder is missing is skipped with a warning, and the rows it had are deleted as orphans on that run. When it returns its rows are inserted again; the embeddings are reused from the content-hash cache, not recomputed. A config with no roots, a root with no globs, or a name used twice is refused.
- A configured root whose folder exists but whose globs match nothing is named in a warning on stderr (`root "<name>" matched no files`) and as `EMPTY` in `doc-search roots`. If any other root still finds files, that root's rows are deleted as orphans on that run, so a glob or path typo in one root of several drops that root's rows (fixing it re-inserts them, reusing the cached embeddings).
- Only when **every** root yields zero files does `index` print "Nothing to index." and return **without reconciling**, leaving the rows already in the index unchanged. Run `doc-search roots` to see the counts before indexing.

### Schema (Content-Addressed)

```sql
-- Global embeddings (shared across all projects/branches)
CREATE TABLE embeddings (
  content_hash TEXT PRIMARY KEY,  -- SHA-256 of chunk content
  embedding BLOB NOT NULL,        -- Float32[3072]
  created_at TEXT NOT NULL
);

-- Location metadata (many-to-one with embeddings)
CREATE TABLE doc_chunks (
  id INTEGER PRIMARY KEY,
  project_name TEXT NOT NULL,     -- Directory name (e.g., 'finch')
  branch TEXT NOT NULL,           -- Git branch
  file_path TEXT NOT NULL,        -- Relative to repo root
  section_title TEXT NOT NULL,    -- H2 section or '(full document)'
  content_hash TEXT NOT NULL,     -- FK to embeddings
  mtime INTEGER NOT NULL,         -- File mtime for change detection
  indexed_at TEXT NOT NULL
);
```

**Key insight**: Same content anywhere shares the same embedding. If `docs/API.md` is identical on `main` and `feature/auth`, only one embedding is stored.

### Change Detection

1. **mtime fast-check**: If file mtime unchanged, skip entirely
2. **Content hash comparison**: If mtime changed but content hash matches, update mtime only
3. **Embed if needed**: Only embed when content changed, or when the stored embedding was written by another model/width

### Concurrency (Multiplayer)

- **Advisory locking** with 5-minute timeout
- Lock file: `tools/doc-search/.doc-search.lock`
- Contains: `{pid, hostname, timestamp}`
- Stale locks (>5 min or dead process) are automatically broken

### Project Identification

- Uses `path.basename(process.cwd())` (directory name)
- Queries are scoped to current project by default
- Branch detection via `git branch --show-current`

## session-search

### Usage

```bash
# Index sessions directory
~/.claude/tools/session-search/session-search.sh index

# Query session history
~/.claude/tools/session-search/session-search.sh query "authentication refactor"

# Filter by date
~/.claude/tools/session-search/session-search.sh query "API design" --after 2026-01-01

# Filter by file type
~/.claude/tools/session-search/session-search.sh query "test strategy" --file IMPLEMENTATION
```

### Schema

```sql
CREATE TABLE chunks (
  id INTEGER PRIMARY KEY,
  session_path TEXT NOT NULL,     -- e.g., 'yarik/finch/sessions/2026_02_05_AUTH'
  session_date TEXT NOT NULL,     -- YYYY-MM-DD
  file_path TEXT NOT NULL,
  section_title TEXT NOT NULL,
  content TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

## Integration with Skills

### Context Ingestion (`§CMD_INGEST_CONTEXT_BEFORE_WORK`)

Skills automatically query session-search during setup:

```bash
~/.claude/tools/session-search/session-search.sh query "[taskSummary]" --limit 10
```

Results populate `ragDiscoveredPaths` for user review.

### Post-Synthesis Reindexing (`§CMD_GENERATE_DEBRIEF`)

After completing a skill, the debrief phase triggers reindexing:

```bash
# Reindex sessions (background)
~/.claude/tools/session-search/session-search.sh index &

# Reindex docs if modified (background)
~/.claude/tools/doc-search/doc-search.sh index &
```

## Chunking Strategy

Both tools split markdown by H2 headers (`## `):

- Each H2 section becomes a separate chunk
- Files without H2 headers → single chunk titled `(full document)`
- Duplicate section titles within a file → suffixed with `##1`, `##2`, etc.
- Empty sections are skipped

## Environment

```bash
# Required for both tools: a running Ollama with the model pulled (one-time, ~620 MB)
ollama pull embeddinggemma

# Optional overrides (read by tools/embed-local and its wrapper gate)
export ENGINE_EMBED_ENDPOINT="http://127.0.0.1:11434"
export ENGINE_EMBED_MODEL="embeddinggemma"
export ENGINE_EMBED_DIMENSIONS=768
export ENGINE_EMBED_BATCH=32

# The wrappers refuse to start (exit 1, RUNNER_ABSENT / MODEL_ABSENT) when the
# runner is down or the model is missing. GEMINI_API_KEY is not used by search.
```

## File Locations

```
~/.claude/cache/search-db/<namespace>/
├── .doc-search.local.db        # SQLite database, 768-d local embeddings
├── .session-search.local.db    # SQLite database, 768-d local embeddings
└── .{doc,session}-search.db    # Gemini-era 3072-d databases, no longer read (safe to delete by hand)

~/.claude/tools/
├── doc-search/
│   ├── doc-search.sh           # Wrapper script
│   ├── .doc-search.lock        # Advisory lock file
│   └── src/
│       ├── cli.ts              # CLI interface
│       ├── db.ts               # Schema + init
│       ├── embed.ts            # wraps tools/embed-local
│       ├── chunker.ts          # H2 parsing
│       ├── indexer.ts          # Reconciliation
│       ├── query.ts            # KNN search
│       └── lock.ts             # Advisory locking
│
└── session-search/
    ├── session-search.sh       # Wrapper script
    └── src/
        ├── cli.ts
        ├── db.ts
        ├── embed.ts
        ├── chunker.ts
        ├── indexer.ts
        ├── query.ts
        └── scanner.ts          # Session directory scanning
```

## Invariants

- **`¶INV_EXPLICIT_INDEX`**: Indexing is explicit (via CLI or skill), never automatic on query
- **`¶INV_CONTENT_ADDRESSED_EMBEDDINGS`**: Same content = same embedding (global dedup)
- **`¶INV_PROJECT_SCOPED_QUERIES`**: Queries default to current project
- **`¶INV_LOCK_WITH_TIMEOUT`**: Advisory locks expire after 5 minutes
