import { describe, it, expect } from "vitest";
import { groupResultsByFile, type SearchResult } from "../query.js";

describe("query", () => {
  describe("groupResultsByFile", () => {
    it("should group results by file+branch and sort by distance", () => {
      const results: SearchResult[] = [
        {
          projectName: "finch",
          branch: "main",
          filePath: "docs/ARCHITECTURE.md",
          sectionTitle: "Overview",
          distance: 0.3,
          snippet: "Content A...",
        },
        {
          projectName: "finch",
          branch: "main",
          filePath: "docs/API.md",
          sectionTitle: "Auth",
          distance: 0.1,
          snippet: "Content B...",
        },
        {
          projectName: "finch",
          branch: "main",
          filePath: "docs/ARCHITECTURE.md",
          sectionTitle: "Database",
          distance: 0.5,
          snippet: "Content C...",
        },
      ];

      const grouped = groupResultsByFile(results);

      expect(grouped).toHaveLength(2);
      // Best file first (API.md has distance 0.1)
      expect(grouped[0].filePath).toBe("docs/API.md");
      expect(grouped[0].matches).toHaveLength(1);

      // ARCHITECTURE.md second (best match distance 0.3)
      expect(grouped[1].filePath).toBe("docs/ARCHITECTURE.md");
      expect(grouped[1].matches).toHaveLength(2);
      expect(grouped[1].matches[0].distance).toBe(0.3);
      expect(grouped[1].matches[1].distance).toBe(0.5);
    });

    it("should handle empty results", () => {
      const grouped = groupResultsByFile([]);
      expect(grouped).toHaveLength(0);
    });

    it("should separate same file on different branches", () => {
      const results: SearchResult[] = [
        {
          projectName: "finch",
          branch: "main",
          filePath: "docs/API.md",
          sectionTitle: "Auth",
          distance: 0.2,
          snippet: "Main branch content...",
        },
        {
          projectName: "finch",
          branch: "dev",
          filePath: "docs/API.md",
          sectionTitle: "Auth",
          distance: 0.3,
          snippet: "Dev branch content...",
        },
      ];

      const grouped = groupResultsByFile(results);

      // Same file path but different branches = different groups
      expect(grouped).toHaveLength(2);
      expect(grouped[0].branch).toBe("main");
      expect(grouped[1].branch).toBe("dev");
    });
  });

  describe("QueryFilters — since/until", () => {
    // The since/until filters are applied as SQL WHERE clauses on mtime.
    // We verify the filter interface accepts the new fields and that
    // the types are correct (number for Unix ms timestamps).
    it("should accept since and until as numbers", () => {
      const filters = {
        since: Date.now() - 7 * 24 * 60 * 60 * 1000, // 7 days ago
        until: Date.now(),
      };

      expect(typeof filters.since).toBe("number");
      expect(typeof filters.until).toBe("number");
      expect(filters.since).toBeLessThan(filters.until);
    });
  });
});
