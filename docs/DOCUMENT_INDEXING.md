# Document Indexing System

Semantic search over project documentation and session history using Gemini embeddings + SQLite + sqlite-vec.

## Overview

The engine provides two indexing tools for RAG-style context retrieval:

| Tool | Purpose | Scope | Database |
|------|---------|-------|----------|
| `session-search` | Search session history | `sessions/**/*.md` | `sessions/.session-search.db` |
| `doc-search` | Search project documentation | `docs/**/*.md`, `{apps,packages}/*/docs/**/*.md` | `tools/doc-search/.doc-search.db` |

Both tools share the same architecture:
- **Gemini embeddings** (`gemini-embedding-001`, 3072 dimensions)
- **SQLite + sqlite-vec** for vector storage and KNN search
- **Content-addressed deduplication** (same content = same embedding)
- **Google Drive sync** for multiplayer access

## doc-search

### Usage

```bash
# Index documentation for current project
~/.claude/tools/doc-search/doc-search.sh index

# Index with custom glob pattern
~/.claude/tools/doc-search/doc-search.sh index --path "packages/*/docs/**/*.md"

# Query for information (filters to current branch by default)
~/.claude/tools/doc-search/doc-search.sh query "how does matching work"

# Search across all branches
~/.claude/tools/doc-search/doc-search.sh query "error handling" --all-branches

# Filter to specific branch
~/.claude/tools/doc-search/doc-search.sh query "schema design" --branch main

# Limit results
~/.claude/tools/doc-search/doc-search.sh query "API endpoints" --limit 5
```

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
3. **Embed if needed**: Only call Gemini API when content actually changed

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
# Required for both tools
export GEMINI_API_KEY="..."

# Default key is hardcoded in wrapper scripts (for convenience)
# Override with your own key if needed
```

## File Locations

```
~/.claude/tools/
├── doc-search/
│   ├── doc-search.sh           # Wrapper script
│   ├── .doc-search.db          # SQLite database
│   ├── .doc-search.lock        # Advisory lock file
│   └── src/
│       ├── cli.ts              # CLI interface
│       ├── db.ts               # Schema + init
│       ├── embed.ts            # Gemini client
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

- **§INV_EXPLICIT_INDEX**: Indexing is explicit (via CLI or skill), never automatic on query
- **§INV_CONTENT_ADDRESSED_EMBEDDINGS**: Same content = same embedding (global dedup)
- **§INV_PROJECT_SCOPED_QUERIES**: Queries default to current project
- **§INV_LOCK_WITH_TIMEOUT**: Advisory locks expire after 5 minutes
