/**
 * Doc chunker — splits doc markdown files on H1/H2/H3 boundaries with breadcrumb titles.
 *
 * Ported from tools/doc-search/src/chunker.ts into the unified search tool.
 * Merges tiny chunks (< 100 chars) with next sibling.
 */
import crypto from "node:crypto";
import path from "node:path";

const MIN_CHUNK_SIZE = 100;

export interface DocChunk {
  sourcePath: string;
  sectionTitle: string;
  chunkText: string;
  contentHash: string;
}

export function computeContentHash(content: string): string {
  return crypto.createHash("sha256").update(content).digest("hex");
}

interface RawChunk {
  level: 0 | 1 | 2 | 3;
  title: string;
  content: string;
  h1Title: string;
  h2Title: string;
  h3Title: string;
}

/**
 * Parse a Markdown file into H1/H2/H3-level chunks with breadcrumb titles.
 *
 * Strategy:
 * 1. Split on H1/H2/H3 headers (H4+ stay with parent)
 * 2. Build breadcrumb titles: "filename.md > H1 > H2 > H3"
 * 3. Merge tiny chunks (< 100 chars) with next sibling
 */
export function parseChunks(
  markdown: string,
  filePath: string
): DocChunk[] {
  const trimmed = markdown.trim();
  if (trimmed.length === 0) return [];

  const fileName = path.basename(filePath);
  const lines = trimmed.split("\n");

  let currentH1 = "";
  let currentH2 = "";
  let currentH3 = "";
  const rawChunks: RawChunk[] = [];
  let currentContent: string[] = [];
  let currentLevel: 0 | 1 | 2 | 3 = 0;
  let currentTitle = "";

  const headerRegex = /^(#{1,3})\s+(.+)$/;

  function flushChunk(): void {
    const content = currentContent.join("\n").trim();
    if (content.length > 0 || currentTitle.length > 0) {
      rawChunks.push({
        level: currentLevel,
        title: currentTitle,
        content: content.length > 0 ? content : currentTitle,
        h1Title: currentH1,
        h2Title: currentH2,
        h3Title: currentH3,
      });
    }
    currentContent = [];
  }

  for (const line of lines) {
    const match = line.match(headerRegex);
    if (match) {
      const level = match[1].length as 1 | 2 | 3;
      const title = match[2].trim();
      flushChunk();
      if (level === 1) { currentH1 = title; currentH2 = ""; currentH3 = ""; }
      else if (level === 2) { currentH2 = title; currentH3 = ""; }
      else { currentH3 = title; }
      currentLevel = level;
      currentTitle = title;
    } else {
      currentContent.push(line);
    }
  }
  flushChunk();

  if (rawChunks.length === 0 || !rawChunks.some((c) => c.level > 0)) {
    const content = rawChunks.length > 0
      ? rawChunks.map((c) => c.content).join("\n").trim()
      : trimmed;
    return [
      {
        sourcePath: filePath,
        sectionTitle: `${fileName} > (full document)`,
        chunkText: content,
        contentHash: computeContentHash(content),
      },
    ];
  }

  // Build breadcrumb titles
  const processedChunks: DocChunk[] = [];
  const titleCounts = new Map<string, number>();

  for (const raw of rawChunks) {
    let breadcrumb: string;
    if (raw.level === 0) {
      breadcrumb = `${fileName} > (intro)`;
    } else if (raw.level === 1) {
      breadcrumb = `${fileName} > ${raw.h1Title}`;
    } else if (raw.level === 2) {
      breadcrumb = raw.h1Title
        ? `${fileName} > ${raw.h1Title} > ${raw.h2Title}`
        : `${fileName} > ${raw.h2Title}`;
    } else {
      const parts = [fileName];
      if (raw.h1Title) parts.push(raw.h1Title);
      if (raw.h2Title) parts.push(raw.h2Title);
      parts.push(raw.h3Title);
      breadcrumb = parts.join(" > ");
    }

    const count = titleCounts.get(breadcrumb) ?? 0;
    titleCounts.set(breadcrumb, count + 1);
    const sectionTitle = count === 0 ? breadcrumb : `${breadcrumb}##${count}`;

    processedChunks.push({
      sourcePath: filePath,
      sectionTitle,
      chunkText: raw.content,
      contentHash: computeContentHash(raw.content),
    });
  }

  // Merge tiny chunks with next sibling
  const merged: DocChunk[] = [];
  for (let i = 0; i < processedChunks.length; i++) {
    const chunk = processedChunks[i];
    if (chunk.chunkText.length < MIN_CHUNK_SIZE && i + 1 < processedChunks.length) {
      const next = processedChunks[i + 1];
      const mergedContent = `${chunk.chunkText}\n\n${next.chunkText}`.trim();
      processedChunks[i + 1] = {
        ...next,
        chunkText: mergedContent,
        contentHash: computeContentHash(mergedContent),
      };
    } else {
      merged.push(chunk);
    }
  }

  return merged;
}
