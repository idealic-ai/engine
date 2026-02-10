import { describe, it, expect } from "vitest";
import { parseTimeArg, toDateString, toISOString, toUnixMs } from "../parse-time-arg.js";

// Fixed reference time for deterministic tests: 2026-02-10T12:00:00Z
const NOW = new Date("2026-02-10T12:00:00Z");

describe("parseTimeArg", () => {
  describe("relative time — hours", () => {
    it("should subtract hours from now", () => {
      const result = parseTimeArg("16h", NOW);
      // 2026-02-10T12:00:00Z - 16h = 2026-02-09T20:00:00Z
      expect(result.toISOString()).toBe("2026-02-09T20:00:00.000Z");
    });

    it("should handle single hour", () => {
      const result = parseTimeArg("1h", NOW);
      expect(result.toISOString()).toBe("2026-02-10T11:00:00.000Z");
    });

    it("should handle 0 hours (returns now)", () => {
      const result = parseTimeArg("0h", NOW);
      expect(result.toISOString()).toBe("2026-02-10T12:00:00.000Z");
    });
  });

  describe("relative time — days", () => {
    it("should subtract days from now", () => {
      const result = parseTimeArg("7d", NOW);
      // 2026-02-10 - 7d = 2026-02-03
      expect(result.toISOString()).toBe("2026-02-03T12:00:00.000Z");
    });

    it("should handle 30 days crossing month boundary", () => {
      const result = parseTimeArg("30d", NOW);
      // 2026-02-10 - 30d = 2026-01-11
      expect(result.toISOString()).toBe("2026-01-11T12:00:00.000Z");
    });
  });

  describe("relative time — weeks", () => {
    it("should subtract weeks from now", () => {
      const result = parseTimeArg("2w", NOW);
      // 2026-02-10 - 14d = 2026-01-27
      expect(result.toISOString()).toBe("2026-01-27T12:00:00.000Z");
    });
  });

  describe("relative time — months", () => {
    it("should subtract months from now", () => {
      const result = parseTimeArg("1m", NOW);
      // 2026-02-10 - 1m = 2026-01-10
      expect(result.toISOString()).toBe("2026-01-10T12:00:00.000Z");
    });

    it("should handle month subtraction across year boundary", () => {
      const result = parseTimeArg("3m", NOW);
      // 2026-02-10 - 3m = 2025-11-10
      expect(result.toISOString()).toBe("2025-11-10T12:00:00.000Z");
    });
  });

  describe("relative time — years", () => {
    it("should subtract years from now", () => {
      const result = parseTimeArg("1y", NOW);
      expect(result.toISOString()).toBe("2025-02-10T12:00:00.000Z");
    });
  });

  describe("absolute date — YYYY-MM-DD", () => {
    it("should parse as midnight UTC", () => {
      const result = parseTimeArg("2026-02-01");
      expect(result.toISOString()).toBe("2026-02-01T00:00:00.000Z");
    });

    it("should parse different dates", () => {
      const result = parseTimeArg("2025-12-25");
      expect(result.toISOString()).toBe("2025-12-25T00:00:00.000Z");
    });
  });

  describe("ISO datetime", () => {
    it("should parse ISO datetime with Z suffix", () => {
      const result = parseTimeArg("2026-02-01T14:30:00Z");
      expect(result.toISOString()).toBe("2026-02-01T14:30:00.000Z");
    });

    it("should parse ISO datetime without Z suffix", () => {
      const result = parseTimeArg("2026-02-01T14:30:00");
      // Without Z, interpreted as local time — just check it parses
      expect(result.getTime()).not.toBeNaN();
    });

    it("should parse ISO datetime with milliseconds", () => {
      const result = parseTimeArg("2026-02-01T14:30:00.500Z");
      expect(result.toISOString()).toBe("2026-02-01T14:30:00.500Z");
    });
  });

  describe("invalid inputs", () => {
    it("should throw on empty string", () => {
      expect(() => parseTimeArg("")).toThrow("empty string");
    });

    it("should throw on whitespace-only string", () => {
      expect(() => parseTimeArg("   ")).toThrow("empty string");
    });

    it("should throw on unknown format", () => {
      expect(() => parseTimeArg("abc")).toThrow('Invalid time argument: "abc"');
    });

    it("should throw on unknown unit suffix", () => {
      expect(() => parseTimeArg("16x")).toThrow('Invalid time argument: "16x"');
    });

    it("should throw on malformed date", () => {
      expect(() => parseTimeArg("2026-13-45")).toThrow("invalid date");
    });

    it("should throw on partial date", () => {
      expect(() => parseTimeArg("2026-02")).toThrow("Invalid time argument");
    });

    it("should throw on invalid ISO datetime", () => {
      expect(() => parseTimeArg("2026-02-01Tnotadate")).toThrow("invalid ISO datetime");
    });
  });

  describe("whitespace handling", () => {
    it("should trim leading/trailing whitespace", () => {
      const result = parseTimeArg("  7d  ", NOW);
      expect(result.toISOString()).toBe("2026-02-03T12:00:00.000Z");
    });
  });

  describe("case insensitivity", () => {
    it("should accept uppercase unit", () => {
      const result = parseTimeArg("7D", NOW);
      expect(result.toISOString()).toBe("2026-02-03T12:00:00.000Z");
    });

    it("should accept uppercase H", () => {
      const result = parseTimeArg("16H", NOW);
      expect(result.toISOString()).toBe("2026-02-09T20:00:00.000Z");
    });
  });
});

describe("conversion utilities", () => {
  const date = new Date("2026-02-10T14:30:00.000Z");

  describe("toDateString", () => {
    it("should return YYYY-MM-DD format", () => {
      expect(toDateString(date)).toBe("2026-02-10");
    });
  });

  describe("toISOString", () => {
    it("should return full ISO string", () => {
      expect(toISOString(date)).toBe("2026-02-10T14:30:00.000Z");
    });
  });

  describe("toUnixMs", () => {
    it("should return Unix timestamp in milliseconds", () => {
      expect(toUnixMs(date)).toBe(date.getTime());
      expect(typeof toUnixMs(date)).toBe("number");
    });
  });
});
