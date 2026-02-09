import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";
import fg from "fast-glob";
import { initDb, saveDb, queryAll, queryOne } from "./db.js";
import { parseChunks, type DocChunk } from "./chunker.js";
import { createEmbeddingClient } from "./embed.js";
import { reconcileChunks, type IndexReport } from "./indexer.js";
import { searchDocs, groupResultsByFile, type QueryFilters } from "./query.js";
import { acquireLock, releaseLock } from "./lock.js";

const TOOL_DIR = path.dirname(fileURLToPath(import.meta.url));

function getDbPath(): string {
  const sessionsDir = path.join(getProjectRoot(), "sessions");
  if (fs.existsSync(sessionsDir)) {
    return path.join(sessionsDir, ".doc-search.db");
  }
  // Fallback to tool dir if sessions/ doesn't exist
  return path.join(TOOL_DIR, "..", ".doc-search.db");
}

const DB_PATH = getDbPath();
const DEFAULT_DOCS_GLOBS = [
  "docs/**/*.md",
  "{apps,packages}/*/docs/**/*.md",
];

/**
 * Find the project root by looking for .claude directory.
 * Falls back to git root, then cwd.
 *
 * Priority:
 * 1. Directory containing .claude/ (Claude Code project marker)
 * 2. Git repository root
 * 3. Current working directory
 */
function getProjectRoot(): string {
  // 1. Walk up looking for .claude directory
  let dir = process.cwd();
  const root = path.parse(dir).root;
  while (dir !== root) {
    if (fs.existsSync(path.join(dir, ".claude"))) {
      return dir;
    }
    dir = path.dirname(dir);
  }

  // 2. Fall back to git root
  try {
    const gitRoot = execSync("git rev-parse --show-toplevel", {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
    if (gitRoot) return gitRoot;
  } catch {
    // Not a git repo
  }

  // 3. Fall back to cwd
  return process.cwd();
}

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

Index options:
  --path GLOB       Custom glob pattern (default: docs/**/*.md + {apps,packages}/*/docs/**/*.md)

Query options:
  --branch NAME     Filter by specific branch (default: current branch)
  --all-branches    Search all branches
  --all-projects    Search all indexed projects (not just current)
  --limit N         Max results (default: 20)

Environment:
  GEMINI_API_KEY    Required for embedding (index and query)

Project identification:
  Finds project root by looking for .claude/ directory (falls back to git root).
  Can be run from any subdirectory within the project.
  Database location: ${DB_PATH}`);
}

async function runIndex(customGlob?: string): Promise<void> {
  const projectRoot = getProjectRoot();
  const projectName = getProjectName();
  const branch = getCurrentBranch();
  const docsGlobs = customGlob ? [customGlob] : DEFAULT_DOCS_GLOBS;

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

  try {
    // Scan for markdown files from project root (not cwd)
    console.log(`Scanning: ${docsGlobs.join(", ")}`);
    const files = await fg(docsGlobs, {
      cwd: projectRoot,
      followSymbolicLinks: true,
      onlyFiles: true,
    });

    console.log(`Found ${files.length} markdown files`);

    if (files.length === 0) {
      console.log("Nothing to index.");
      return;
    }

    // Parse all files into chunks
    const allChunks: DocChunk[] = [];
    for (const relativeFile of files) {
      const absolutePath = path.join(projectRoot, relativeFile);
      const content = fs.readFileSync(absolutePath, "utf-8");
      const mtime = getFileMtime(absolutePath);
      const chunks = parseChunks(
        content,
        projectName,
        branch,
        relativeFile,
        mtime
      );
      allChunks.push(...chunks);
    }

    console.log(`Parsed ${allChunks.length} chunks from ${files.length} files`);

    // Initialize DB and embedder
    const db = await initDb(DB_PATH);
    const embedder = createEmbeddingClient();

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

      const limit =
        typeof flags["limit"] === "string" ? parseInt(flags["limit"], 10) : 20;

      await runQuery(queryText, filters, limit);
      break;
    }

    case "status": {
      await runStatus();
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
