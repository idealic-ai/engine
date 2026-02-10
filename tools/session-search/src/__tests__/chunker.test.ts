import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import {
  parseChunks,
  parseStateJsonChunks,
  computeContentHash,
  extractDate,
} from "../chunker.js";

describe("chunker", () => {
  const sessionPath = "sessions/2026_02_04_TEST";
  const filePath = "sessions/2026_02_04_TEST/BRAINSTORM.md";

  describe("parseChunks", () => {
    it("should parse H2 sections from Markdown", () => {
      const markdown = `# Main Title

Some intro text.

## Section One

Content of section one.

## Section Two

Content of section two.
More content here.

## Section Three

Final section content.
`;

      const chunks = parseChunks(markdown, sessionPath, filePath);

      expect(chunks).toHaveLength(3);
      expect(chunks[0].sectionTitle).toBe("Section One");
      expect(chunks[0].content).toContain("Content of section one.");
      expect(chunks[0].sessionPath).toBe(sessionPath);
      expect(chunks[0].filePath).toBe(filePath);

      expect(chunks[1].sectionTitle).toBe("Section Two");
      expect(chunks[1].content).toContain("Content of section two.");
      expect(chunks[1].content).toContain("More content here.");

      expect(chunks[2].sectionTitle).toBe("Section Three");
      expect(chunks[2].content).toContain("Final section content.");
    });

    it("should handle files with no H2 sections", () => {
      const markdown = `# Just a Title

Some content without any H2 headers.
More paragraphs here.
`;

      const chunks = parseChunks(markdown, sessionPath, filePath);

      expect(chunks).toHaveLength(1);
      expect(chunks[0].sectionTitle).toBe("(full document)");
      expect(chunks[0].content).toContain("Some content without any H2 headers.");
    });

    it("should handle empty file", () => {
      const chunks = parseChunks("", sessionPath, filePath);
      expect(chunks).toHaveLength(0);
    });

    it("should handle whitespace-only file", () => {
      const chunks = parseChunks("   \n\n  ", sessionPath, filePath);
      expect(chunks).toHaveLength(0);
    });

    it("should handle H2 with timestamp prefix (log-style)", () => {
      const markdown = `# Implementation Log

## [2026-02-04 12:00:00] Task Start

Started working on feature.

## [2026-02-04 13:00:00] Success

Feature completed.
`;

      const chunks = parseChunks(markdown, sessionPath, filePath);

      expect(chunks).toHaveLength(2);
      expect(chunks[0].sectionTitle).toBe("[2026-02-04 12:00:00] Task Start");
      expect(chunks[1].sectionTitle).toBe("[2026-02-04 13:00:00] Success");
    });

    it("should not split on H3 or other heading levels", () => {
      const markdown = `# Title

## Main Section

Content here.

### Subsection

More content here.

#### Deep section

Even more.
`;

      const chunks = parseChunks(markdown, sessionPath, filePath);

      expect(chunks).toHaveLength(1);
      expect(chunks[0].sectionTitle).toBe("Main Section");
      expect(chunks[0].content).toContain("### Subsection");
      expect(chunks[0].content).toContain("#### Deep section");
    });

    it("should include content before first H2 in the first chunk context", () => {
      const markdown = `# Title
**Tags**: #needs-review

Intro paragraph.

## First Section

Section content.
`;

      const chunks = parseChunks(markdown, sessionPath, filePath);

      // The preamble (before first H2) is included in the first chunk
      expect(chunks).toHaveLength(1);
      expect(chunks[0].sectionTitle).toBe("First Section");
      expect(chunks[0].content).toContain("Section content.");
    });

    it("should populate sessionDate from session path", () => {
      const markdown = `## Section\n\nContent here.`;
      const chunks = parseChunks(markdown, "sessions/2026_02_04_TEST", filePath);

      expect(chunks).toHaveLength(1);
      expect(chunks[0].sessionDate).toBe("2026-02-04");
    });

    it("should deduplicate repeated H2 titles with ##N suffix", () => {
      const markdown = `# Log

## Response

First response content.

## Response

Second response content.

## Response

Third response content.
`;

      const chunks = parseChunks(markdown, sessionPath, filePath);

      expect(chunks).toHaveLength(3);
      expect(chunks[0].sectionTitle).toBe("Response");
      expect(chunks[1].sectionTitle).toBe("Response##1");
      expect(chunks[2].sectionTitle).toBe("Response##2");
    });

    it("should not suffix unique titles", () => {
      const markdown = `# Doc

## Alpha

Content A.

## Beta

Content B.

## Alpha

Content A again.
`;

      const chunks = parseChunks(markdown, sessionPath, filePath);

      expect(chunks).toHaveLength(3);
      expect(chunks[0].sectionTitle).toBe("Alpha");
      expect(chunks[1].sectionTitle).toBe("Beta");
      expect(chunks[2].sectionTitle).toBe("Alpha##1");
    });
  });

  describe("extractDate", () => {
    it("should extract YYYY-MM-DD from session path", () => {
      expect(extractDate("sessions/2026_02_04_TEST")).toBe("2026-02-04");
    });

    it("should handle nested/namespaced paths", () => {
      expect(extractDate("yarik/finch/sessions/2026_01_15_REFACTOR")).toBe("2026-01-15");
    });

    it("should return 'unknown' for paths without date pattern", () => {
      expect(extractDate("sessions/NO_DATE_HERE")).toBe("unknown");
    });

    it("should match first occurrence of date pattern", () => {
      expect(extractDate("archive/2025_12_31_OLD/sub/2026_01_01_NEW")).toBe("2025-12-31");
    });
  });

  describe("computeContentHash", () => {
    it("should compute stable content hashes", () => {
      const hash1 = computeContentHash("Hello World");
      const hash2 = computeContentHash("Hello World");
      expect(hash1).toBe(hash2);
    });

    it("should produce different hashes for different content", () => {
      const hash1 = computeContentHash("Hello World");
      const hash2 = computeContentHash("Goodbye World");
      expect(hash1).not.toBe(hash2);
    });

    it("should return a hex string", () => {
      const hash = computeContentHash("test content");
      expect(hash).toMatch(/^[0-9a-f]{64}$/);
    });
  });
});

describe("parseStateJsonChunks", () => {
  let tmpDir: string;
  const sessionPath = "sessions/2026_02_10_TEST";
  const filePath = "sessions/2026_02_10_TEST/.state.json";

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "test-state-chunks-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  /** Helper to write a .state.json and return its absolute path */
  function writeState(data: unknown): string {
    const stateFile = path.join(tmpDir, ".state.json");
    fs.writeFileSync(stateFile, JSON.stringify(data));
    return stateFile;
  }

  // --- Keywords ---

  it("C1: should produce one chunk per keyword", () => {
    const file = writeState({ searchKeywords: ["auth", "middleware"] });

    const chunks = parseStateJsonChunks(file, sessionPath, filePath);

    expect(chunks).toHaveLength(2);
    expect(chunks[0].content).toBe("auth");
    expect(chunks[0].sectionTitle).toBe("auth");
    expect(chunks[1].content).toBe("middleware");
    expect(chunks[1].sectionTitle).toBe("middleware");
  });

  it("C2: should skip empty and whitespace-only keywords", () => {
    const file = writeState({
      searchKeywords: ["auth", "", "  ", "middleware"],
    });

    const chunks = parseStateJsonChunks(file, sessionPath, filePath);

    expect(chunks).toHaveLength(2);
    expect(chunks[0].content).toBe("auth");
    expect(chunks[1].content).toBe("middleware");
  });

  it("C3: should trim keyword whitespace", () => {
    const file = writeState({
      searchKeywords: ["  auth  ", " middleware"],
    });

    const chunks = parseStateJsonChunks(file, sessionPath, filePath);

    expect(chunks).toHaveLength(2);
    expect(chunks[0].content).toBe("auth");
    expect(chunks[0].sectionTitle).toBe("auth");
    expect(chunks[1].content).toBe("middleware");
    expect(chunks[1].sectionTitle).toBe("middleware");
  });

  // --- Description ---

  it("C4: should produce one chunk for sessionDescription", () => {
    const file = writeState({
      sessionDescription: "Fixed auth flow including token refresh",
    });

    const chunks = parseStateJsonChunks(file, sessionPath, filePath);

    expect(chunks).toHaveLength(1);
    expect(chunks[0].content).toBe("Fixed auth flow including token refresh");
    expect(chunks[0].sectionTitle).toBe("session-description");
  });

  it("C5: should trim description whitespace", () => {
    const file = writeState({
      sessionDescription: "  Fixed auth flow  ",
    });

    const chunks = parseStateJsonChunks(file, sessionPath, filePath);

    expect(chunks).toHaveLength(1);
    expect(chunks[0].content).toBe("Fixed auth flow");
  });

  // --- Combined ---

  it("C6: should handle both keywords AND description", () => {
    const file = writeState({
      searchKeywords: ["fleet", "tmux", "colors"],
      sessionDescription: "Changed fleet tmux notification colors",
    });

    const chunks = parseStateJsonChunks(
      file,
      "sessions/2026_02_08_COLORS",
      "sessions/2026_02_08_COLORS/.state.json"
    );

    expect(chunks).toHaveLength(4); // 3 keywords + 1 description
    expect(chunks[0].content).toBe("fleet");
    expect(chunks[1].content).toBe("tmux");
    expect(chunks[2].content).toBe("colors");
    expect(chunks[3].sectionTitle).toBe("session-description");
    expect(chunks[3].content).toBe("Changed fleet tmux notification colors");
  });

  // --- Graceful Skip ---

  it("C7: should return empty for missing metadata fields", () => {
    const file = writeState({ pid: 12345 });

    const chunks = parseStateJsonChunks(file, sessionPath, filePath);

    expect(chunks).toEqual([]);
  });

  it("C8: should return empty for nonexistent file", () => {
    const chunks = parseStateJsonChunks(
      "/tmp/nonexistent-file-xyz-999.json",
      sessionPath,
      filePath
    );

    expect(chunks).toEqual([]);
  });

  it("C9: should return empty for invalid JSON", () => {
    const stateFile = path.join(tmpDir, ".state.json");
    fs.writeFileSync(stateFile, "not valid json {{{");

    const chunks = parseStateJsonChunks(stateFile, sessionPath, filePath);

    expect(chunks).toEqual([]);
  });

  // --- Type Safety ---

  it("C10: should skip non-string values in searchKeywords array", () => {
    const file = writeState({
      searchKeywords: ["auth", 42, null, { key: "val" }, "middleware"],
    });

    const chunks = parseStateJsonChunks(file, sessionPath, filePath);

    expect(chunks).toHaveLength(2);
    expect(chunks[0].content).toBe("auth");
    expect(chunks[1].content).toBe("middleware");
  });

  it("C11: should skip non-string sessionDescription", () => {
    const file = writeState({ sessionDescription: 12345 });

    const chunks = parseStateJsonChunks(file, sessionPath, filePath);

    expect(chunks).toEqual([]);
  });

  // --- Metadata Accuracy ---

  it("C12: should extract correct sessionDate from session path", () => {
    const file = writeState({
      searchKeywords: ["test"],
      sessionDescription: "A description",
    });

    const chunks = parseStateJsonChunks(
      file,
      "sessions/2026_02_08_COLORS",
      "sessions/2026_02_08_COLORS/.state.json"
    );

    // Every chunk should have the correct sessionDate
    for (const chunk of chunks) {
      expect(chunk.sessionDate).toBe("2026-02-08");
    }
  });

  it("C13: should compute unique content hashes per chunk", () => {
    const file = writeState({
      searchKeywords: ["auth", "middleware", "redis"],
    });

    const chunks = parseStateJsonChunks(file, sessionPath, filePath);

    expect(chunks).toHaveLength(3);

    const hashes = chunks.map((c) => c.contentHash);
    const uniqueHashes = new Set(hashes);
    expect(uniqueHashes.size).toBe(3);

    // Each hash should be a valid SHA-256 hex string
    for (const hash of hashes) {
      expect(hash).toMatch(/^[0-9a-f]{64}$/);
    }
  });
});
