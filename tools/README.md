# Tools

Standalone tools and services for the workflow engine. Unlike scripts (which are CLI utilities invoked directly), tools are longer-running services or complex subsystems with their own dependencies.

Each tool lives in its own directory with a shell wrapper, TypeScript source, and its own `package.json` (where applicable). Tools are invoked through their wrapper scripts, which resolve symlinks and delegate to `npx tsx`.

## Reference

| Tool | Type | Purpose |
|------|------|---------|
| `statusline.sh` | Shell script | Status line renderer for tmux. Displays session name, skill/phase, and context usage percentage |
| `dispatch-daemon/` | Service (deprecated) | Tag-based work router. Watches `sessions/` for `#delegated-*` tags and spawns Claude agents. Superseded by `run.sh --monitor-tags` |
| `doc-search/` | CLI + SQLite | Semantic search over project documentation. Indexes markdown files, queries via Gemini embeddings |
| `session-search/` | CLI + SQLite | Semantic search over session history. Indexes session artifacts, queries via Gemini embeddings |

## Shared Patterns

### SQLite for Vector Storage

Both `doc-search` and `session-search` use `sql.js` (SQLite compiled to WASM) to store document chunks alongside their embedding vectors. No external database process required — the entire index is a single `.db` file.

### Gemini API for Embeddings

Both search tools call the Gemini embedding API to vectorize text chunks at index time and queries at search time. The API key is loaded from `$GEMINI_API_KEY` or falls back to the project `.env` file.

### TypeScript + Shell Wrapper

Each tool follows the same invocation pattern:

```bash
# Shell wrapper resolves symlinks, sets env, delegates to tsx
exec npx --prefix "$TOOL_DIR" tsx "$TOOL_DIR/src/cli.ts" "$@"
```

Tools manage their own `node_modules` via a local `package.json` — they do not depend on the monorepo's workspace packages.

### Fleet-Optional Design (`¶INV_TMUX_AND_FLEET_OPTIONAL`)

`statusline.sh` is fleet-aware (it renders differently inside fleet panes vs. standalone sessions) but degrades gracefully when tmux or fleet is unavailable. The search tools have no tmux dependency at all.

## How to Add a Tool

1. **Create a directory** under `~/.claude/engine/tools/<tool-name>/`.

2. **Add a shell wrapper** (`<tool-name>.sh`) that resolves symlinks and invokes the TypeScript entry point. Follow the pattern in `doc-search/doc-search.sh`.

3. **Add a `package.json`** with the tool's dependencies. Run `npm install` inside the tool directory. Do not add dependencies to the monorepo root.

4. **Write the TypeScript source** in `src/`. Entry point should be `src/cli.ts`.

5. **Add a `TESTING.md`** documenting how to run tests, what is covered, and any conventions (mock patterns, temp DB isolation, ESM import rules).

6. **Create a symlink** (if needed) from `~/.claude/scripts/` so the tool is accessible via the `engine` CLI alias.

7. **Update this README** — add a row to the reference table above.

## Usage

### doc-search

```bash
# Index project documentation
doc-search.sh index [path]

# Query indexed docs
doc-search.sh query "search terms"
```

### session-search

```bash
# Index session history
session-search.sh index [path]

# Query with filters
session-search.sh query "search terms" [--tags X] [--after YYYY-MM-DD] [--before YYYY-MM-DD] [--file GLOB]
```

### statusline.sh

Called automatically by Claude Code. Receives JSON on stdin with context window data. Not typically invoked manually.

### dispatch-daemon (deprecated)

```bash
# Superseded by: run.sh --monitor-tags '#delegated-implementation,#delegated-chores'
# See ~/.claude/docs/DAEMON.md for the current tag dispatch system
```

## Related Files

| File | Description |
|------|-------------|
| `dispatch-daemon/README.md` | Full dispatch daemon documentation (architecture, tag routing, troubleshooting) |
| `doc-search/TESTING.md` | Doc search test standards (vitest, chunker tests, coverage gaps) |
| `session-search/TESTING.md` | Session search test standards (vitest, DB isolation, embedding mocks) |
| `~/.claude/engine/scripts/README.md` | Scripts directory reference (companion to this file) |
| `~/.claude/docs/DAEMON.md` | Current daemon mode documentation (replaces standalone dispatch daemon) |
