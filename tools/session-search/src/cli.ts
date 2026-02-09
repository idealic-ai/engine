import fs from "node:fs";
import path from "node:path";
import { initDb, saveDb } from "./db.js";
import { parseChunks } from "./chunker.js";
import { scanMarkdownFiles, extractSessionPath } from "./scanner.js";
import { createEmbeddingClient } from "./embed.js";
import { reconcileChunks, type IndexReport } from "./indexer.js";
import {
  searchChunks,
  groupResultsByFile,
  type QueryFilters,
} from "./query.js";

const SESSIONS_DIR = "sessions";
const DB_FILENAME = ".session-search.db";

/**
 * Extract the user namespace from a resolved Google Drive sessions path.
 * e.g., ".../Shared drives/finch-os/yarik/finch/sessions" -> "yarik/finch/sessions"
 * Falls back to "sessions" if the path isn't on Google Drive.
 */
function extractNamespace(resolvedPath: string): string {
  const marker = "finch-os/";
  const idx = resolvedPath.indexOf(marker);
  if (idx !== -1) {
    return resolvedPath.slice(idx + marker.length);
  }
  return "sessions";
}

function usage(): void {
  console.log(`session-search — semantic search over session history

Usage:
  session-search index [path]                           Index sessions (default: ./sessions/)
  session-search query "text" [options]                 Semantic search

Query options:
  --after  YYYY-MM-DD    Only sessions on or after date
  --before YYYY-MM-DD    Only sessions before date
  --file   PATTERN       Filter by filename pattern (e.g., BRAINSTORM)
  --tags   TAG           Filter by tag in content
  --limit  N             Max results (default: 20)

Environment:
  GEMINI_API_KEY         Required for embedding (index and query)`);
}

function resolveSessionsDir(customPath?: string): string {
  const sessionsPath = customPath ?? path.join(process.cwd(), SESSIONS_DIR);

  // Resolve symlinks to find the real path
  let resolved: string;
  try {
    resolved = fs.realpathSync(sessionsPath);
  } catch {
    console.error(`Error: Sessions directory not found: ${sessionsPath}`);
    process.exit(1);
  }

  if (!fs.statSync(resolved).isDirectory()) {
    console.error(`Error: Not a directory: ${sessionsPath}`);
    process.exit(1);
  }

  return resolved;
}

function resolveDbPath(sessionsDir: string): string {
  return path.join(sessionsDir, DB_FILENAME);
}

async function runIndex(targetPath?: string): Promise<void> {
  const sessionsDir = resolveSessionsDir(targetPath);
  const dbPath = resolveDbPath(sessionsDir);

  console.log(`Scanning: ${sessionsDir}`);
  console.log(`Database: ${dbPath}`);

  // 1. Scan for markdown files
  const files = scanMarkdownFiles(sessionsDir);
  console.log(`Found ${files.length} markdown files`);

  if (files.length === 0) {
    console.log("Nothing to index.");
    return;
  }

  // 2. Parse all files into chunks, with namespace prefix for multi-user support
  const namespace = extractNamespace(sessionsDir);
  const allChunks = [];
  for (const relativeFile of files) {
    const absolutePath = path.join(sessionsDir, relativeFile);
    const content = fs.readFileSync(absolutePath, "utf-8");
    const rawSessionPath = extractSessionPath(relativeFile);
    const sessionPath = `${namespace}/${rawSessionPath}`;
    const filePath = `${namespace}/${relativeFile}`;
    const chunks = parseChunks(content, sessionPath, filePath);
    allChunks.push(...chunks);
  }

  console.log(`Parsed ${allChunks.length} chunks from ${files.length} files`);

  // 3. Initialize DB and embedder
  const db = await initDb(dbPath);
  const embedder = createEmbeddingClient();

  // 4. Reconcile (this also saves the DB)
  console.log("Reconciling with database...");
  const report = await reconcileChunks(db, dbPath, allChunks, embedder);

  printReport(report);
}

function printReport(report: IndexReport): void {
  console.log("\nIndex report:");
  console.log(`  Inserted: ${report.inserted}`);
  console.log(`  Updated:  ${report.updated}`);
  console.log(`  Skipped:  ${report.skipped}`);
  console.log(`  Deleted:  ${report.deleted}`);
  console.log(
    `  Total:    ${report.inserted + report.updated + report.skipped}`
  );
}

async function runQuery(
  queryText: string,
  filters: QueryFilters,
  limit: number
): Promise<void> {
  const sessionsDir = resolveSessionsDir();
  const dbPath = resolveDbPath(sessionsDir);

  if (!fs.existsSync(dbPath)) {
    console.error(
      "Error: No index found. Run 'session-search index' first."
    );
    process.exit(1);
  }

  const db = await initDb(dbPath);
  const embedder = createEmbeddingClient();

  console.log(`Searching for: "${queryText}"`);
  if (Object.keys(filters).length > 0) {
    console.log(`Filters: ${JSON.stringify(filters)}`);
  }

  const results = await searchChunks(db, queryText, embedder, filters, limit);

  if (results.length === 0) {
    console.log("\nNo results found.");
    return;
  }

  const grouped = groupResultsByFile(results);

  console.log(`\nFound ${results.length} matches across ${grouped.length} files:\n`);

  for (const group of grouped) {
    // Strip namespace prefix, show from sessions/ onward for clickable paths
    const displayPath = group.filePath.replace(/^.*?(sessions\/)/, "$1");

    console.log(`  ${displayPath}  (${group.sessionDate})`);

    for (const match of group.matches) {
      const distStr = match.distance.toFixed(4);
      // Show snippet (first line, trimmed)
      const snippetLine = match.snippet.split("\n")[0].trim();
      const truncated =
        snippetLine.length > 100
          ? snippetLine.slice(0, 100) + "..."
          : snippetLine;
      console.log(`    [${distStr}] ${match.sectionTitle}`);
      if (truncated.length > 0) {
        console.log(`             ${truncated}`);
      }
    }
    console.log();
  }
}

function parseArgs(argv: string[]): {
  command: string;
  positional: string[];
  flags: Record<string, string>;
} {
  const command = argv[0] ?? "";
  const positional: string[] = [];
  const flags: Record<string, string> = {};

  let i = 1;
  while (i < argv.length) {
    const arg = argv[i];
    if (arg.startsWith("--")) {
      const key = arg.slice(2);
      const value = argv[i + 1] ?? "";
      flags[key] = value;
      i += 2;
    } else {
      positional.push(arg);
      i++;
    }
  }

  return { command, positional, flags };
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);

  if (args.length === 0 || args[0] === "--help" || args[0] === "-h") {
    usage();
    process.exit(0);
  }

  const { command, positional, flags } = parseArgs(args);

  switch (command) {
    case "index": {
      const targetPath = positional[0];
      await runIndex(targetPath);
      break;
    }

    case "query": {
      const queryText = positional[0];
      if (!queryText) {
        console.error('Error: Query text is required. Usage: session-search query "your search text"');
        process.exit(1);
      }

      const filters: QueryFilters = {};
      if (flags.after) filters.after = flags.after;
      if (flags.before) filters.before = flags.before;
      if (flags.file) filters.file = flags.file;
      if (flags.tags) filters.tags = flags.tags;

      const limit = flags.limit ? parseInt(flags.limit, 10) : 20;

      await runQuery(queryText, filters, limit);
      break;
    }

    default:
      console.error(`Unknown command: ${command}`);
      usage();
      process.exit(1);
  }
}

main().catch((err: unknown) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
