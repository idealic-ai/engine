import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";
import { initDb, saveDb, queryAll, queryOne } from "./db.js";
import { parseChunks, type DocChunk } from "./chunker.js";
import { createEmbeddingClient, INDEXER_EMBED_RETRY } from "./embed.js";
import { reconcileChunks, type IndexReport } from "./indexer.js";
import { searchDocs, groupResultsByFile, countForeignEmbeddings, type QueryFilters } from "./query.js";
import { parseTimeArg, toUnixMs } from "../../shared/parse-time-arg.js";
import { acquireLock, releaseLock, startLockHeartbeat, lockHeartbeatMsFromEnv } from "./lock.js";
import { isSearchDbRefused } from "../../shared/search-db-guard.js";
import { getDbPath, getProjectRoot } from "./db-path.js";
import { loadDocRoots, collectDocFiles, singleGlobRoot, CONFIG_ENV, CONFIG_FILENAMES, type DocRoot } from "./roots.js";

// Resolved in main(), not at import, so a refused path prints its message
// instead of an import-time stack trace.
let DB_PATH = "";


/**
 * Get the project name from the project root.
 * Uses the project root directory name for consistent identification
 * regardless of which subdirectory the command is run from.
 */
function getProjectName(): string {
  return path.basename(getProjectRoot());
}

/**
 * Get the current git branch.
 * Falls back to "detached" if in detached HEAD state.
 */
function getCurrentBranch(): string {
  try {
    const branch = execSync("git branch --show-current", {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
    return branch || "detached";
  } catch {
    return "unknown";
  }
}

/**
 * Get file modification time (mtime) as Unix timestamp.
 */
function getFileMtime(filePath: string): number {
  const stats = fs.statSync(filePath);
  return Math.floor(stats.mtimeMs);
}

function usage(): void {
  console.log(`doc-search — semantic search over project documentation

Usage:
  doc-search index [options]                       Index docs for current project
  doc-search query "text" [options]                Semantic search
  doc-search status                                Show index statistics
  doc-search roots                                 Show which folders index reads, with file counts

Index options:
  --path GLOB       One glob under the project root, instead of the configured roots

Roots (which folders are indexed):
  Read from the first of: $${CONFIG_ENV}, ${CONFIG_FILENAMES.map((f) => "<project>/" + f).join(", ")}.
  Shape: {"roots": [{"name": "kit", "path": ".", "globs": ["docs/**/*.md"], "ignore": ["docs/dist/**"]},
                    {"name": "engine", "path": "~/.claude/engine", "globs": ["docs/**/*.md"]}]}
  "path" is relative to the project root or starts with ~/; it never depends on the working directory.
  "tracked": true keeps only files git tracks under that root (drops build output and scratch dirs).
  With no config file: docs/**/*.md + {apps,packages}/*/docs/**/*.md, read exactly as before.
  Configured roots never read node_modules. A config is not looked for when the project root is ~.

Query options:
  --branch NAME     Filter by specific branch (default: current branch)
  --all-branches    Search all branches
  --all-projects    Search all indexed projects (not just current)
  --since TIME      Only docs modified on or after TIME
  --until TIME      Only docs modified before TIME
  --limit N         Max results (default: 20)

TIME formats:
  16h, 7d, 2w, 1m, 1y   Relative (hours, days, weeks, months, years ago)
  2026-02-01             Absolute date (midnight UTC)
  2026-02-01T14:30:00Z   ISO datetime

Embedding (local, no key, no network; tools/embed-local):
  A running Ollama with the model pulled is required for index and query:
    ollama pull embeddinggemma
  ENGINE_EMBED_ENDPOINT    Runner URL (default: http://127.0.0.1:11434)
  ENGINE_EMBED_MODEL       Model tag (default: embeddinggemma)
  ENGINE_EMBED_DIMENSIONS  Vector width the model returns (default: 768)
  ENGINE_EMBED_BATCH       Texts per embed request (default: 32)
  ENGINE_EMBED_TIMEOUT_MS  Per-request timeout in ms (default: 120000)

Project identification:
  Finds project root by looking for .claude/ directory (falls back to git root).
  Can be run from any subdirectory within the project.
  Database location: ${describeDbPath()}`);
}

/** The DB path for the help text; a refused path is shown as its refusal. */
function describeDbPath(): string {
  try {
    return getDbPath();
  } catch (err: unknown) {
    return isSearchDbRefused(err) ? `(refused) ${err.message}` : String(err);
  }
}

/** The roots this run reads: the configured ones, or one glob under the project root. */
function resolveRoots(projectRoot: string, customGlob?: string): { roots: DocRoot[]; source: string } {
  if (customGlob) {
    return { roots: [singleGlobRoot(projectRoot, customGlob)], source: "--path" };
  }
  const loaded = loadDocRoots(projectRoot);
  return { roots: loaded.roots, source: loaded.source ?? "(default, no config file)" };
}

function printRoots(roots: DocRoot[], source: string, perRoot?: Record<string, number>): void {
  console.log(`Roots from: ${source}`);
  for (const r of roots) {
    const count = perRoot ? `  ${perRoot[r.name] ?? 0} files` : "";
    console.log(`  [${r.name}] ${r.path}${count}`);
    console.log(`      globs:  ${r.globs.join(", ")}`);
    if (r.ignore.length > 0) console.log(`      ignore: ${r.ignore.join(", ")}`);
  }
}

async function runRoots(): Promise<void> {
  const projectRoot = getProjectRoot();
  const { roots, source } = resolveRoots(projectRoot);
  const { files, perRoot, missingRoots, untrackedRoots } = await collectDocFiles(roots, projectRoot);
  console.log(`Project root: ${projectRoot}`);
  printRoots(roots, source, perRoot);
  for (const m of missingRoots) console.log(`  MISSING: ${m} (skipped)`);
  for (const u of untrackedRoots) console.log(`  NOT IN GIT: ${u} is marked "tracked" but is not a git work tree (skipped)`);
  console.log(`Total: ${files.length} markdown files`);
}

async function runIndex(customGlob?: string): Promise<void> {
  const projectRoot = getProjectRoot();
  const projectName = getProjectName();
  const branch = getCurrentBranch();
  const { roots, source } = resolveRoots(projectRoot, customGlob);

  console.log(`Project: ${projectName}`);
  console.log(`Project root: ${projectRoot}`);
  console.log(`Branch: ${branch}`);
  console.log(`Database: ${DB_PATH}`);

  // Acquire lock
  console.log("Acquiring lock...");
  if (!acquireLock(DB_PATH)) {
    console.error(
      "Error: Could not acquire lock. Another process may be indexing."
    );
    process.exit(1);
  }

  // A long rebuild refreshes its lock, so it is never judged stale mid-run.
  const stopHeartbeat = startLockHeartbeat(DB_PATH, lockHeartbeatMsFromEnv());
  try {
    // Roots resolve against the project root and ~, never cwd.
    const { files, perRoot, missingRoots, untrackedRoots } = await collectDocFiles(roots, projectRoot);
    printRoots(roots, source, perRoot);
    for (const m of missingRoots) {
      console.error(`[doc-search] root folder ${m} does not exist; skipped`);
    }
    for (const u of untrackedRoots) {
      console.error(`[doc-search] root ${u} is marked "tracked" but is not a git work tree; skipped`);
    }

    console.log(`Found ${files.length} markdown files`);

    if (files.length === 0) {
      console.log("Nothing to index.");
      return;
    }

    // Parse all files into chunks
    const allChunks: DocChunk[] = [];
    for (const file of files) {
      const content = fs.readFileSync(file.absPath, "utf-8");
      const mtime = getFileMtime(file.absPath);
      const chunks = parseChunks(
        content,
        projectName,
        branch,
        file.storedPath,
        mtime
      );
      allChunks.push(...chunks);
    }

    console.log(`Parsed ${allChunks.length} chunks from ${files.length} files`);

    // Initialize DB and embedder
    const db = await initDb(DB_PATH);
    // Indexing retries a busy or timed-out batch with backoff; a query does not.
    const embedder = createEmbeddingClient({ retry: INDEXER_EMBED_RETRY });
    console.log(`Embedding with ${embedder.model} (${embedder.dimensions}-d, local)`);

    // Reconcile
    console.log("Reconciling with database...");
    const report = await reconcileChunks(
      db,
      allChunks,
      embedder,
      projectName,
      branch
    );

    // Save database to disk
    saveDb(db, DB_PATH);

    printReport(report);
    db.close();
  } finally {
    // Always release lock
    stopHeartbeat();
    releaseLock(DB_PATH);
    console.log("Lock released.");
  }
}

function printReport(report: IndexReport): void {
  console.log("\nIndex report:");
  console.log(`  Inserted:          ${report.inserted}`);
  console.log(`  Updated:           ${report.updated}`);
  console.log(`  Skipped:           ${report.skipped}`);
  console.log(`  Deleted:           ${report.deleted}`);
  console.log(`  Embeddings reused: ${report.embeddingsReused}`);
  console.log(`  Embeddings created: ${report.embeddingsCreated}`);
  console.log(
    `  Total chunks:      ${report.inserted + report.updated + report.skipped}`
  );
}

async function runStatus(): Promise<void> {
  if (!fs.existsSync(DB_PATH)) {
    console.log("No index found. Run 'doc-search index' first.");
    return;
  }

  const db = await initDb(DB_PATH);

  // Get total counts
  const totalChunks = queryOne<{ count: number }>(db, "SELECT COUNT(*) as count FROM doc_chunks")?.count ?? 0;
  const totalEmbeddings = queryOne<{ count: number }>(db, "SELECT COUNT(*) as count FROM embeddings")?.count ?? 0;
  const generations = queryAll<{ model: string; dimensions: number; count: number }>(db, `
    SELECT model, dimensions, COUNT(*) as count FROM embeddings GROUP BY model, dimensions ORDER BY count DESC
  `);

  // Get projects
  const projects = queryAll<{ project_name: string; chunk_count: number }>(db, `
    SELECT project_name, COUNT(*) as chunk_count
    FROM doc_chunks
    GROUP BY project_name
    ORDER BY chunk_count DESC
  `);

  // Get branches per project
  const branches = queryAll<{ project_name: string; branch: string; chunk_count: number }>(db, `
    SELECT project_name, branch, COUNT(*) as chunk_count
    FROM doc_chunks
    GROUP BY project_name, branch
    ORDER BY project_name, chunk_count DESC
  `);

  // Get files count
  const filesCount = queryOne<{ count: number }>(db, `
    SELECT COUNT(DISTINCT file_path) as count FROM doc_chunks
  `)?.count ?? 0;

  console.log("doc-search Index Status");
  console.log("=======================");
  console.log(`Database: ${DB_PATH}`);
  console.log();
  console.log("Global Statistics:");
  console.log(`  Total chunks:     ${totalChunks}`);
  console.log(`  Total embeddings: ${totalEmbeddings}`);
  for (const g of generations) {
    console.log(`    - ${g.model} (${g.dimensions}-d): ${g.count}`);
  }
  console.log(`  Unique files:     ${filesCount}`);
  console.log(`  Projects:         ${projects.length}`);
  console.log();

  if (projects.length > 0) {
    console.log("Projects:");
    for (const project of projects) {
      console.log(`  ${project.project_name}: ${project.chunk_count} chunks`);

      // Show branches for this project
      const projectBranches = branches.filter(b => b.project_name === project.project_name);
      for (const branch of projectBranches) {
        console.log(`    - ${branch.branch}: ${branch.chunk_count} chunks`);
      }
    }
  }

  db.close();
}

async function runQuery(
  queryText: string,
  filters: QueryFilters,
  limit: number
): Promise<void> {
  const projectName = getProjectName();
  const currentBranch = getCurrentBranch();

  if (!fs.existsSync(DB_PATH)) {
    console.error("Error: No index found. Run 'doc-search index' first.");
    process.exit(1);
  }

  const db = await initDb(DB_PATH);
  const embedder = createEmbeddingClient();

  const foreign = countForeignEmbeddings(db, embedder);
  if (foreign > 0) {
    console.error(
      `[doc-search] ${foreign} embeddings were written by another model or width and are not ranked. ` +
        `Run 'doc-search index' to re-embed them with ${embedder.model} (${embedder.dimensions}-d).`
    );
  }

  // Default to current branch unless --all-branches specified
  const effectiveFilters: QueryFilters = {
    ...filters,
    branch: filters.allBranches ? undefined : filters.branch ?? currentBranch,
  };

  if (filters.allProjects) {
    console.log("Project: all indexed projects");
  } else {
    console.log(`Project: ${projectName}`);
  }
  console.log(`Searching for: "${queryText}"`);
  if (effectiveFilters.branch) {
    console.log(`Branch filter: ${effectiveFilters.branch}`);
  } else {
    console.log("Branch filter: all branches");
  }

  const results = await searchDocs(
    db,
    queryText,
    embedder,
    projectName,
    effectiveFilters,
    limit
  );

  if (results.length === 0) {
    console.log("\nNo results found.");
    db.close();
    return;
  }

  const grouped = groupResultsByFile(results);

  console.log(
    `\nFound ${results.length} matches across ${grouped.length} files:\n`
  );

  for (const group of grouped) {
    // Show project name if searching all projects
    const projectPrefix = filters.allProjects ? `[${group.matches[0].projectName}] ` : "";
    console.log(`  ${projectPrefix}${group.filePath}  [${group.branch}]`);

    for (const match of group.matches) {
      const distStr = match.distance.toFixed(4);
      console.log(`    [${distStr}] ${match.sectionTitle}`);
      if (match.snippet) {
        // Truncate long snippets and show on new line with indent
        const snippetPreview = match.snippet.length > 100
          ? match.snippet.slice(0, 100) + "..."
          : match.snippet;
        console.log(`             ${snippetPreview.replace(/\n/g, " ")}`);
      }
    }
    console.log();
  }

  db.close();
}

function parseArgs(argv: string[]): {
  command: string;
  positional: string[];
  flags: Record<string, string | boolean>;
} {
  const command = argv[0] ?? "";
  const positional: string[] = [];
  const flags: Record<string, string | boolean> = {};

  let i = 1;
  while (i < argv.length) {
    const arg = argv[i];
    if (arg === "--all-branches") {
      flags["all-branches"] = true;
      i++;
    } else if (arg === "--all-projects") {
      flags["all-projects"] = true;
      i++;
    } else if (arg.startsWith("--")) {
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
  DB_PATH = getDbPath();

  switch (command) {
    case "index": {
      const customGlob =
        typeof flags["path"] === "string" ? flags["path"] : undefined;
      await runIndex(customGlob);
      break;
    }

    case "query": {
      const queryText = positional[0];
      if (!queryText) {
        console.error(
          'Error: Query text is required. Usage: doc-search query "your search text"'
        );
        process.exit(1);
      }

      const filters: QueryFilters = {};
      if (flags["branch"] && typeof flags["branch"] === "string") {
        filters.branch = flags["branch"];
      }
      if (flags["all-branches"]) {
        filters.allBranches = true;
      }
      if (flags["all-projects"]) {
        filters.allProjects = true;
      }
      if (flags["since"] && typeof flags["since"] === "string") {
        try {
          filters.since = toUnixMs(parseTimeArg(flags["since"]));
        } catch (e: unknown) {
          console.error(`Error: Invalid --since value: ${(e as Error).message}`);
          process.exit(1);
        }
      }
      if (flags["until"] && typeof flags["until"] === "string") {
        try {
          filters.until = toUnixMs(parseTimeArg(flags["until"]));
        } catch (e: unknown) {
          console.error(`Error: Invalid --until value: ${(e as Error).message}`);
          process.exit(1);
        }
      }

      const limit =
        typeof flags["limit"] === "string" ? parseInt(flags["limit"], 10) : 20;

      await runQuery(queryText, filters, limit);
      break;
    }

    case "status": {
      await runStatus();
      break;
    }

    case "roots": {
      await runRoots();
      break;
    }

    default:
      console.error(`Unknown command: ${command}`);
      usage();
      process.exit(1);
  }
}

main().catch((err: unknown) => {
  // A refused DB path or schema is an answer, not a crash: print it as written.
  if (isSearchDbRefused(err)) {
    console.error(err.message);
    process.exit(1);
  }
  console.error("Fatal error:", err);
  process.exit(1);
});
