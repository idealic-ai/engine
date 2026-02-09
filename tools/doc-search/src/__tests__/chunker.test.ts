import { describe, it, expect } from "vitest";
import { parseChunks, computeContentHash } from "../chunker.js";

const PROJECT = "test-project";
const BRANCH = "main";
const FILE = "docs/TEST.md";
const MTIME = 1234567890;

describe("parseChunks", () => {
  describe("basic hierarchy", () => {
    it("creates chunk for H1 with preamble as (intro)", () => {
      // Preamble is content BEFORE the first header (H1)
      // Preamble content must be > 100 chars to avoid being merged
      const introContent = "This is the introduction content that appears before any headers. It provides context and background information about the document that follows.";
      const h1Content = "Content directly under the H1 header with enough text to be meaningful and avoid tiny chunk merging behavior.";
      const md = `${introContent}

# Main Title

${h1Content}
`;
      const chunks = parseChunks(md, PROJECT, BRANCH, FILE, MTIME);

      // Should have intro chunk and H1 chunk (both > 100 chars)
      expect(chunks.length).toBe(2);

      // First chunk is the preamble (intro) — content before first header
      expect(chunks[0].sectionTitle).toBe("TEST.md > (intro)");
      expect(chunks[0].content).toContain("introduction content");

      // Second chunk is the H1 section
      expect(chunks[1].sectionTitle).toBe("TEST.md > Main Title");
      expect(chunks[1].content).toContain("Content directly under");
    });

    it("creates breadcrumb titles for H1/H2/H3 hierarchy", () => {
      // Each section needs > 100 chars to avoid tiny chunk merging
      const contentA1 = "This is the content for subsection A1 with enough detail to be a meaningful standalone chunk in the search index.";
      const contentA2 = "This is the content for subsection A2 providing different information that warrants its own entry in search results.";
      const contentB = "This is the content for section B which covers a separate topic entirely and should appear as its own search result.";
      const md = `# Document Title

## Section A

### Subsection A1

${contentA1}

### Subsection A2

${contentA2}

## Section B

${contentB}
`;
      const chunks = parseChunks(md, PROJECT, BRANCH, FILE, MTIME);

      const titles = chunks.map(c => c.sectionTitle);

      expect(titles).toContain("TEST.md > Document Title > Section A > Subsection A1");
      expect(titles).toContain("TEST.md > Document Title > Section A > Subsection A2");
      expect(titles).toContain("TEST.md > Document Title > Section B");
    });

    it("ignores H4+ headers (content stays with parent H3)", () => {
      const md = `# Doc

## Section

### Subsection

Main content.

#### Deep Header

Deep content should stay with Subsection.

##### Even Deeper

Still with Subsection.
`;
      const chunks = parseChunks(md, PROJECT, BRANCH, FILE, MTIME);

      // Should only have one chunk for the H3 subsection
      const subsectionChunk = chunks.find(c => c.sectionTitle.includes("Subsection"));
      expect(subsectionChunk).toBeDefined();
      expect(subsectionChunk!.content).toContain("Main content");
      expect(subsectionChunk!.content).toContain("Deep content");
      expect(subsectionChunk!.content).toContain("Still with Subsection");

      // No separate chunks for H4/H5
      const h4Chunk = chunks.find(c => c.sectionTitle.includes("Deep Header"));
      expect(h4Chunk).toBeUndefined();
    });
  });

  describe("edge cases", () => {
    it("handles H1-only document", () => {
      const md = `# Just a Title

Some content under the title with no subsections.
`;
      const chunks = parseChunks(md, PROJECT, BRANCH, FILE, MTIME);

      expect(chunks.length).toBe(1);
      expect(chunks[0].sectionTitle).toBe("TEST.md > Just a Title");
      expect(chunks[0].content).toContain("Some content");
    });

    it("handles document with no headers", () => {
      const md = `Just plain text content.

Multiple paragraphs.

No headers at all.
`;
      const chunks = parseChunks(md, PROJECT, BRANCH, FILE, MTIME);

      expect(chunks.length).toBe(1);
      expect(chunks[0].sectionTitle).toBe("TEST.md > (full document)");
      expect(chunks[0].content).toContain("Just plain text");
    });

    it("handles empty content", () => {
      const chunks = parseChunks("", PROJECT, BRANCH, FILE, MTIME);
      expect(chunks.length).toBe(0);
    });

    it("handles whitespace-only content", () => {
      const chunks = parseChunks("   \n\n  \t  ", PROJECT, BRANCH, FILE, MTIME);
      expect(chunks.length).toBe(0);
    });

    it("deduplicates identical section titles within same file", () => {
      // Each section needs > 100 chars to avoid merging
      const content1 = "This is the first instance of a section with this name, containing substantial content that makes it worthwhile to index.";
      const content2 = "This is the second instance of a section with the same name, but different content that also needs to be searchable.";
      const md = `# Doc

## Section

${content1}

## Section

${content2}
`;
      const chunks = parseChunks(md, PROJECT, BRANCH, FILE, MTIME);

      const titles = chunks.map(c => c.sectionTitle);
      expect(titles).toContain("TEST.md > Doc > Section");
      expect(titles).toContain("TEST.md > Doc > Section##1");
    });
  });

  describe("tiny chunk merging", () => {
    it("merges chunks under 100 chars with next sibling", () => {
      const md = `# Doc

## Tiny

Hi

## Normal

This is a normal section with enough content to be meaningful.
`;
      const chunks = parseChunks(md, PROJECT, BRANCH, FILE, MTIME);

      // Tiny section should be merged with Normal
      const tinyChunk = chunks.find(c => c.sectionTitle.includes("Tiny") && !c.sectionTitle.includes("Normal"));
      expect(tinyChunk).toBeUndefined();

      const normalChunk = chunks.find(c => c.sectionTitle.includes("Normal"));
      expect(normalChunk).toBeDefined();
      expect(normalChunk!.content).toContain("Hi");
      expect(normalChunk!.content).toContain("normal section");
    });

    it("does not merge chunks over 100 chars", () => {
      const md = `# Doc

## Section A

${"x".repeat(150)}

## Section B

Content for B.
`;
      const chunks = parseChunks(md, PROJECT, BRANCH, FILE, MTIME);

      // Both sections should exist separately
      expect(chunks.some(c => c.sectionTitle.includes("Section A"))).toBe(true);
      expect(chunks.some(c => c.sectionTitle.includes("Section B"))).toBe(true);
    });
  });

  describe("snippets", () => {
    it("generates snippet from first 200 chars of content", () => {
      const longContent = "A".repeat(300);
      // Use H2-only structure to avoid H1 merging issues
      const md = `## Section

${longContent}
`;
      const chunks = parseChunks(md, PROJECT, BRANCH, FILE, MTIME);

      const chunk = chunks.find(c => c.sectionTitle.includes("Section"));
      expect(chunk).toBeDefined();
      expect(chunk!.snippet).toBeDefined();
      expect(chunk!.snippet.length).toBeLessThanOrEqual(200);
      // Snippet should be first 200 A's
      expect(chunk!.snippet).toBe("A".repeat(200));
    });

    it("uses full content for snippet if under 200 chars", () => {
      // Use content > 100 chars to avoid merging
      const content = "This is a medium length content section that is long enough to stand on its own but short enough to fit in a snippet.";
      // Use H2-only structure
      const md = `## Section

${content}
`;
      const chunks = parseChunks(md, PROJECT, BRANCH, FILE, MTIME);

      const chunk = chunks.find(c => c.sectionTitle.includes("Section"));
      expect(chunk).toBeDefined();
      expect(chunk!.snippet).toBe(content);
    });
  });

  describe("content hashing", () => {
    it("produces consistent hash for same content", () => {
      const hash1 = computeContentHash("test content");
      const hash2 = computeContentHash("test content");
      expect(hash1).toBe(hash2);
    });

    it("produces different hash for different content", () => {
      const hash1 = computeContentHash("content A");
      const hash2 = computeContentHash("content B");
      expect(hash1).not.toBe(hash2);
    });
  });
});
