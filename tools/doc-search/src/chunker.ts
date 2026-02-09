import crypto from "node:crypto";
import path from "node:path";

const MIN_CHUNK_SIZE = 100;
const SNIPPET_LENGTH = 200;

export interface DocChunk {
  projectName: string;
  branch: string;
  filePath: string;
  sectionTitle: string;
  content: string;
  contentHash: string;
  mtime: number;
  snippet: string;
}

/**
 * Compute SHA-256 hex digest of content.
 */
export function computeContentHash(content: string): string {
  return crypto.createHash("sha256").update(content).digest("hex");
}

/**
 * Generate a snippet from content (first N chars).
 */
function generateSnippet(content: string, maxLength: number = SNIPPET_LENGTH): string {
  const trimmed = content.trim();
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return trimmed.slice(0, maxLength);
}

interface RawChunk {
  level: 1 | 2 | 3 | 0; // 0 = preamble/no-header
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
 * 1. Split on H1/H2/H3 headers (H4+ are ignored — content stays with parent)
 * 2. Build breadcrumb titles: "filename.md > H1 > H2 > H3"
 * 3. Merge tiny chunks (< 100 chars) with next sibling
 * 4. Generate snippets (first 200 chars)
 *
 * Empty/whitespace-only files produce zero chunks.
 */
export function parseChunks(
  markdown: string,
  projectName: string,
  branch: string,
  filePath: string,
  mtime: number
): DocChunk[] {
  const trimmed = markdown.trim();
  if (trimmed.length === 0) {
    return [];
  }

  const fileName = path.basename(filePath);
  const lines = trimmed.split("\n");

  // State machine to track current headers
  let currentH1 = "";
  let currentH2 = "";
  let currentH3 = "";

  const rawChunks: RawChunk[] = [];
  let currentContent: string[] = [];
  let currentLevel: 0 | 1 | 2 | 3 = 0;
  let currentTitle = "";

  // Regex to match H1, H2, H3 (not H4+)
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
      const hashes = match[1];
      const title = match[2].trim();
      const level = hashes.length as 1 | 2 | 3;

      // Flush previous chunk before starting new one
      flushChunk();

      // Update header state based on level
      if (level === 1) {
        currentH1 = title;
        currentH2 = "";
        currentH3 = "";
      } else if (level === 2) {
        currentH2 = title;
        currentH3 = "";
      } else if (level === 3) {
        currentH3 = title;
      }

      currentLevel = level;
      currentTitle = title;
    } else {
      // Regular line (including H4+ headers) — add to current content
      currentContent.push(line);
    }
  }

  // Flush final chunk
  flushChunk();

  // If no chunks (no headers found), return full document as one chunk
  if (rawChunks.length === 0) {
    const content = trimmed;
    return [
      {
        projectName,
        branch,
        filePath,
        sectionTitle: `${fileName} > (full document)`,
        content,
        contentHash: computeContentHash(content),
        mtime,
        snippet: generateSnippet(content),
      },
    ];
  }

  // Special case: only preamble content (content before first header, but file has headers)
  // If we have exactly one chunk and it's level 0, it means there was only preamble
  // But actually, rawChunks.length === 0 only when no headers AND no content before headers
  // Let's check if all chunks are level 0 (no actual headers, just preamble-like content)
  const hasRealHeaders = rawChunks.some(c => c.level > 0);
  if (!hasRealHeaders) {
    // No H1/H2/H3 headers found — treat as full document
    const content = rawChunks.map(c => c.content).join("\n").trim();
    return [
      {
        projectName,
        branch,
        filePath,
        sectionTitle: `${fileName} > (full document)`,
        content,
        contentHash: computeContentHash(content),
        mtime,
        snippet: generateSnippet(content),
      },
    ];
  }

  // Build breadcrumb titles and convert to DocChunks
  const processedChunks: DocChunk[] = [];
  const titleCounts = new Map<string, number>();

  for (const raw of rawChunks) {
    // Build breadcrumb based on level
    let breadcrumb: string;

    if (raw.level === 0) {
      // Preamble (content before first header)
      breadcrumb = `${fileName} > (intro)`;
    } else if (raw.level === 1) {
      // H1 section (no parent headers)
      breadcrumb = `${fileName} > ${raw.h1Title}`;
    } else if (raw.level === 2) {
      // H2 section
      if (raw.h1Title) {
        breadcrumb = `${fileName} > ${raw.h1Title} > ${raw.h2Title}`;
      } else {
        breadcrumb = `${fileName} > ${raw.h2Title}`;
      }
    } else {
      // H3 section
      if (raw.h1Title && raw.h2Title) {
        breadcrumb = `${fileName} > ${raw.h1Title} > ${raw.h2Title} > ${raw.h3Title}`;
      } else if (raw.h1Title) {
        breadcrumb = `${fileName} > ${raw.h1Title} > ${raw.h3Title}`;
      } else if (raw.h2Title) {
        breadcrumb = `${fileName} > ${raw.h2Title} > ${raw.h3Title}`;
      } else {
        breadcrumb = `${fileName} > ${raw.h3Title}`;
      }
    }

    // Deduplicate titles
    const count = titleCounts.get(breadcrumb) ?? 0;
    titleCounts.set(breadcrumb, count + 1);
    const sectionTitle = count === 0 ? breadcrumb : `${breadcrumb}##${count}`;

    processedChunks.push({
      projectName,
      branch,
      filePath,
      sectionTitle,
      content: raw.content,
      contentHash: computeContentHash(raw.content),
      mtime,
      snippet: generateSnippet(raw.content),
    });
  }

  // Merge tiny chunks with next sibling
  const mergedChunks: DocChunk[] = [];

  for (let i = 0; i < processedChunks.length; i++) {
    const chunk = processedChunks[i];

    if (chunk.content.length < MIN_CHUNK_SIZE && i + 1 < processedChunks.length) {
      // Merge with next chunk
      const nextChunk = processedChunks[i + 1];
      const mergedContent = `${chunk.content}\n\n${nextChunk.content}`.trim();

      // Update next chunk with merged content
      processedChunks[i + 1] = {
        ...nextChunk,
        content: mergedContent,
        contentHash: computeContentHash(mergedContent),
        snippet: generateSnippet(mergedContent),
      };
      // Skip this chunk (it's merged into next)
    } else {
      mergedChunks.push(chunk);
    }
  }

  return mergedChunks;
}
