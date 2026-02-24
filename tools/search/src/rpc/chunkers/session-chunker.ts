/**
 * Session chunker — splits session markdown files on H2 boundaries.
 *
 * Ported from tools/session-search/src/chunker.ts into the unified search tool.
 * Also handles .state.json files (searchKeywords + sessionDescription).
 */
import crypto from "node:crypto";

export interface SessionChunk {
  sourcePath: string;
  sectionTitle: string;
  chunkText: string;
  contentHash: string;
}

export function computeContentHash(content: string): string {
  return crypto.createHash("sha256").update(content).digest("hex");
}

/**
 * Parse a Markdown file into H2-level chunks.
 *
 * Split on `\n## ` boundaries. Files with no H2 headers produce
 * a single "(full document)" chunk. Empty files produce zero chunks.
 */
export function parseMarkdownChunks(
  markdown: string,
  sourcePath: string
): SessionChunk[] {
  const trimmed = markdown.trim();
  if (trimmed.length === 0) return [];

  const h2Pattern = /(?:^|\n)## /;
  const parts = trimmed.split(h2Pattern);

  if (parts.length <= 1) {
    if (trimmed.startsWith("## ")) {
      const firstNewline = trimmed.indexOf("\n");
      const title =
        firstNewline === -1 ? trimmed.slice(3) : trimmed.slice(3, firstNewline);
      const body = firstNewline === -1 ? "" : trimmed.slice(firstNewline + 1);
      const content = body.trim();
      if (content.length === 0) return [];
      return [
        {
          sourcePath,
          sectionTitle: title.trim(),
          chunkText: content,
          contentHash: computeContentHash(content),
        },
      ];
    }

    return [
      {
        sourcePath,
        sectionTitle: "(full document)",
        chunkText: trimmed,
        contentHash: computeContentHash(trimmed),
      },
    ];
  }

  const chunks: SessionChunk[] = [];
  const titleCounts = new Map<string, number>();

  for (let i = 1; i < parts.length; i++) {
    const part = parts[i];
    const firstNewline = part.indexOf("\n");
    const rawTitle =
      firstNewline === -1 ? part.trim() : part.slice(0, firstNewline).trim();
    const body = firstNewline === -1 ? "" : part.slice(firstNewline + 1).trim();

    if (body.length === 0 && rawTitle.length === 0) continue;

    const count = titleCounts.get(rawTitle) ?? 0;
    titleCounts.set(rawTitle, count + 1);
    const title = count === 0 ? rawTitle : `${rawTitle}##${count}`;
    const content = body.length > 0 ? body : rawTitle;

    chunks.push({
      sourcePath,
      sectionTitle: title,
      chunkText: content,
      contentHash: computeContentHash(content),
    });
  }

  return chunks;
}

/**
 * Parse a .state.json into synthetic searchable chunks.
 * Extracts searchKeywords (one chunk each) and sessionDescription.
 */
export function parseStateJsonChunks(
  jsonContent: string,
  sourcePath: string
): SessionChunk[] {
  let data: Record<string, unknown>;
  try {
    data = JSON.parse(jsonContent) as Record<string, unknown>;
  } catch {
    return [];
  }

  const chunks: SessionChunk[] = [];

  if (Array.isArray(data.searchKeywords)) {
    for (const kw of data.searchKeywords) {
      if (typeof kw === "string" && kw.trim().length > 0) {
        const content = kw.trim();
        chunks.push({
          sourcePath,
          sectionTitle: content,
          chunkText: content,
          contentHash: computeContentHash(content),
        });
      }
    }
  }

  if (
    typeof data.sessionDescription === "string" &&
    data.sessionDescription.trim().length > 0
  ) {
    const content = data.sessionDescription.trim();
    chunks.push({
      sourcePath,
      sectionTitle: "session-description",
      chunkText: content,
      contentHash: computeContentHash(content),
    });
  }

  return chunks;
}
