import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { scanStateFiles } from "../scanner.js";

describe("scanStateFiles", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "test-scan-state-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("S1: should find .state.json in session subdirectories", () => {
    // One session dir has .state.json, the other does not
    fs.mkdirSync(path.join(tmpDir, "2026_02_10_HAS_STATE"));
    fs.writeFileSync(
      path.join(tmpDir, "2026_02_10_HAS_STATE", ".state.json"),
      JSON.stringify({ pid: 123 })
    );

    fs.mkdirSync(path.join(tmpDir, "2026_02_10_NO_STATE"));
    fs.writeFileSync(
      path.join(tmpDir, "2026_02_10_NO_STATE", "BRAINSTORM.md"),
      "# Hello"
    );

    const results = scanStateFiles(tmpDir);

    expect(results).toHaveLength(1);
    expect(results[0]).toContain("2026_02_10_HAS_STATE");
    expect(results[0]).toContain(".state.json");
  });

  it("S2: should find multiple .state.json files across sessions", () => {
    const sessions = [
      "2026_01_01_ALPHA",
      "2026_02_02_BETA",
      "2026_03_03_GAMMA",
    ];

    for (const name of sessions) {
      fs.mkdirSync(path.join(tmpDir, name));
      fs.writeFileSync(
        path.join(tmpDir, name, ".state.json"),
        JSON.stringify({ pid: 1 })
      );
    }

    const results = scanStateFiles(tmpDir);

    expect(results).toHaveLength(3);
    // Results should be sorted
    expect(results[0]).toContain("2026_01_01_ALPHA");
    expect(results[1]).toContain("2026_02_02_BETA");
    expect(results[2]).toContain("2026_03_03_GAMMA");
  });

  it("S3: should return paths relative to relativeTo parameter", () => {
    // Create a parent dir and a sessions subdir inside it
    const parentDir = path.join(tmpDir, "parent");
    const sessionsDir = path.join(parentDir, "sessions");
    fs.mkdirSync(sessionsDir, { recursive: true });

    const sessionName = "2026_02_10_TEST";
    fs.mkdirSync(path.join(sessionsDir, sessionName));
    fs.writeFileSync(
      path.join(sessionsDir, sessionName, ".state.json"),
      JSON.stringify({ pid: 1 })
    );

    // Scan sessionsDir but relativeTo parentDir
    const results = scanStateFiles(sessionsDir, parentDir);

    expect(results).toHaveLength(1);
    // Path should be relative to parentDir, so it includes "sessions/"
    expect(results[0]).toBe(
      path.join("sessions", sessionName, ".state.json")
    );
  });

  it("S4: should return empty array for empty directory", () => {
    const results = scanStateFiles(tmpDir);
    expect(results).toEqual([]);
  });

  it("S5: should return empty array for nonexistent directory", () => {
    const nonexistent = path.join(tmpDir, "does-not-exist");
    const results = scanStateFiles(nonexistent);
    expect(results).toEqual([]);
  });

  it("S6: should skip files at top level (only scan directories)", () => {
    // Place a file at top level
    fs.writeFileSync(path.join(tmpDir, "README.md"), "# Top level file");

    // Place a real session directory with .state.json
    const sessionName = "2026_02_10_SESSION";
    fs.mkdirSync(path.join(tmpDir, sessionName));
    fs.writeFileSync(
      path.join(tmpDir, sessionName, ".state.json"),
      JSON.stringify({ pid: 1 })
    );

    const results = scanStateFiles(tmpDir);

    // Should only find the session's .state.json, not the top-level README
    expect(results).toHaveLength(1);
    expect(results[0]).toContain(sessionName);
  });

  it("S7: should NOT recurse into nested subdirectories", () => {
    // Create a nested structure: session/sub/sub2/.state.json
    const nested = path.join(tmpDir, "session", "sub", "sub2");
    fs.mkdirSync(nested, { recursive: true });
    fs.writeFileSync(
      path.join(nested, ".state.json"),
      JSON.stringify({ pid: 999 })
    );

    // Also no .state.json directly under tmpDir/session/
    const results = scanStateFiles(tmpDir);

    // Should NOT find the deeply nested .state.json since it only checks
    // immediate children (tmpDir/session/.state.json which does not exist)
    expect(results).toEqual([]);
  });
});
