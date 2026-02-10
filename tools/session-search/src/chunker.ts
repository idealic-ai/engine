import crypto from "node:crypto";
import fs from "node:fs";

export interface Chunk {
  sessionPath: string;
  sessionDate: string;
  filePath: string;
  sectionTitle: string;
  content: string;
  contentHash: string;
  sessionStartedAt?: string;
  sessionCompletedAt?: string;
}

/**
 * Extract YYYY-MM-DD date from a session path.
 * Matches the YYYY_MM_DD pattern anywhere in the path.
 */
export function extractDate(sessionPath: string): string {
  const match = sessionPath.match(/(\d{4})_(\d{2})_(\d{2})/);
  return match ? `${match[1]}-${match[2]}-${match[3]}` : "unknown";
}

/**
 * Compute SHA-256 hex digest of content.
 */
export function computeContentHash(content: string): string {
  return crypto.createHash("sha256").update(content).digest("hex");
}

/**
 * Parse a Markdown file into H2-level chunks.
 *
 * Split strategy: split on `\n## ` (newline followed by H2 header).
 * Each chunk gets the section title (text after `## `) and the full
 * section body. Files with no H2 headers produce a single chunk with
 * title "(full document)".
 *
 * Empty/whitespace-only files produce zero chunks.
 */
export function parseChunks(
  markdown: string,
  sessionPath: string,
  filePath: string
): Chunk[] {
  const trimmed = markdown.trim();
  if (trimmed.length === 0) {
    return [];
  }

  const sessionDate = extractDate(sessionPath);

  // Split on H2 boundaries. The delimiter is "\n## " at start of line.
  // We also handle the case where the file starts with "## " (no leading newline).
  const h2Pattern = /(?:^|\n)## /;
  const parts = trimmed.split(h2Pattern);

  // If there are no H2 headers, the split produces a single element
  if (parts.length <= 1) {
    // Check if the content starts with "## " (single H2 section at the top)
    if (trimmed.startsWith("## ")) {
      const firstNewline = trimmed.indexOf("\n");
      const title =
        firstNewline === -1 ? trimmed.slice(3) : trimmed.slice(3, firstNewline);
      const body = firstNewline === -1 ? "" : trimmed.slice(firstNewline + 1);
      const content = body.trim();
      if (content.length === 0) {
        return [];
      }
      return [
        {
          sessionPath,
          sessionDate,
          filePath,
          sectionTitle: title.trim(),
          content,
          contentHash: computeContentHash(content),
        },
      ];
    }

    // No H2 headers at all — return full document as one chunk
    return [
      {
        sessionPath,
        sessionDate,
        filePath,
        sectionTitle: "(full document)",
        content: trimmed,
        contentHash: computeContentHash(trimmed),
      },
    ];
  }

  const chunks: Chunk[] = [];
  const titleCounts = new Map<string, number>();

  // parts[0] is the preamble (content before first ## )
  // parts[1..n] each start with the H2 title line
  for (let i = 1; i < parts.length; i++) {
    const part = parts[i];
    const firstNewline = part.indexOf("\n");
    const rawTitle =
      firstNewline === -1 ? part.trim() : part.slice(0, firstNewline).trim();
    const body = firstNewline === -1 ? "" : part.slice(firstNewline + 1).trim();

    // Use body as the chunk content; skip empty sections
    if (body.length === 0 && rawTitle.length === 0) {
      continue;
    }

    // Deduplicate section titles within the same file by appending ##N
    const count = titleCounts.get(rawTitle) ?? 0;
    titleCounts.set(rawTitle, count + 1);
    const title = count === 0 ? rawTitle : `${rawTitle}##${count}`;

    const content = body.length > 0 ? body : rawTitle;

    chunks.push({
      sessionPath,
      sessionDate,
      filePath,
      sectionTitle: title,
      content,
      contentHash: computeContentHash(content),
    });
  }

  return chunks;
}

/**
 * Parse a .state.json file into synthetic searchable chunks.
 *
 * Extracts:
 *   - `searchKeywords` (string[]) → one Chunk per keyword
 *   - `sessionDescription` (string) → one Chunk
 *
 * Skips gracefully if the file is unreadable, unparseable, or missing
 * the relevant fields.
 */
export function parseStateJsonChunks(
  absolutePath: string,
  sessionPath: string,
  filePath: string
): Chunk[] {
  let raw: string;
  try {
    raw = fs.readFileSync(absolutePath, "utf-8");
  } catch {
    return [];
  }

  let data: Record<string, unknown>;
  try {
    data = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return [];
  }

  const sessionDate = extractDate(sessionPath);
  const chunks: Chunk[] = [];

  // Extract timestamps for all chunks from this session
  const sessionStartedAt = typeof data.startedAt === "string" ? data.startedAt : undefined;
  // completedAt may be stored at top level or in lifecycle
  const sessionCompletedAt =
    typeof data.completedAt === "string" ? data.completedAt :
    (typeof (data as Record<string, unknown>).deactivatedAt === "string"
      ? (data as Record<string, unknown>).deactivatedAt as string
      : undefined);

  // Extract searchKeywords — one chunk per keyword
  if (Array.isArray(data.searchKeywords)) {
    for (const kw of data.searchKeywords) {
      if (typeof kw === "string" && kw.trim().length > 0) {
        const content = kw.trim();
        chunks.push({
          sessionPath,
          sessionDate,
          filePath,
          sectionTitle: content,
          content,
          contentHash: computeContentHash(content),
          sessionStartedAt,
          sessionCompletedAt,
        });
      }
    }
  }

  // Extract sessionDescription — one chunk
  if (
    typeof data.sessionDescription === "string" &&
    data.sessionDescription.trim().length > 0
  ) {
    const content = data.sessionDescription.trim();
    chunks.push({
      sessionPath,
      sessionDate,
      filePath,
      sectionTitle: "session-description",
      content,
      contentHash: computeContentHash(content),
      sessionStartedAt,
      sessionCompletedAt,
    });
  }

  return chunks;
}
