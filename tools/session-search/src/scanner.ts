import fs from "node:fs";
import path from "node:path";

/**
 * Recursively scan a directory for .md files.
 * Returns file paths relative to the base directory.
 */
export function scanMarkdownFiles(
  baseDir: string,
  relativeTo?: string
): string[] {
  const root = relativeTo ?? baseDir;
  const results: string[] = [];

  function walk(dir: string): void {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      // Skip unreadable directories
      return;
    }

    for (const entry of entries) {
      // Skip hidden files/directories (except the base dir itself)
      if (entry.name.startsWith(".")) {
        continue;
      }

      const fullPath = path.join(dir, entry.name);

      if (entry.isDirectory()) {
        walk(fullPath);
      } else if (entry.isFile() && entry.name.endsWith(".md")) {
        results.push(path.relative(root, fullPath));
      }
    }
  }

  walk(baseDir);
  return results.sort();
}

/**
 * Extract the session directory path from a file path.
 * e.g., "sessions/2026_02_04_TEST/BRAINSTORM.md" -> "sessions/2026_02_04_TEST"
 */
export function extractSessionPath(filePath: string): string {
  const parts = filePath.split(path.sep);
  // Session paths are always sessions/<session_name>/...
  if (parts.length >= 2 && parts[0] === "sessions") {
    return parts.slice(0, 2).join(path.sep);
  }
  // Fallback: use the directory containing the file
  return path.dirname(filePath);
}
