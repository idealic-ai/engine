import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { clearRegistry, dispatch } from "engine-shared/dispatch";
import type { RpcContext } from "engine-shared/context";

// Side-effect registration
import "../fs-paths-resolve.js";

describe("fs.paths.resolve", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "fs-paths-test-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("resolves tilde paths to home directory", async () => {
    const result = await dispatch(
      { cmd: "fs.paths.resolve", args: { paths: ["~/test.txt"] } },
      {} as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const resolved = (result.data.resolved as any[])[0];
    expect(resolved.original).toBe("~/test.txt");
    expect(resolved.resolved).toContain(os.homedir());
  });

  it("resolves relative paths to absolute using cwd", async () => {
    const result = await dispatch(
      { cmd: "fs.paths.resolve", args: { paths: ["foo/bar.ts"], cwd: tmpDir } },
      {} as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const resolved = (result.data.resolved as any[])[0];
    expect(path.isAbsolute(resolved.resolved)).toBe(true);
  });

  it("reports exists=true for existing paths", async () => {
    const testFile = path.join(tmpDir, "exists.txt");
    fs.writeFileSync(testFile, "hello");
    const result = await dispatch(
      { cmd: "fs.paths.resolve", args: { paths: [testFile] } },
      {} as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data.resolved as any[])[0].exists).toBe(true);
  });

  it("reports exists=false for nonexistent paths", async () => {
    const result = await dispatch(
      { cmd: "fs.paths.resolve", args: { paths: ["/nonexistent/path.txt"] } },
      {} as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data.resolved as any[])[0].exists).toBe(false);
  });

  it("resolves symlinks to real paths", async () => {
    const realFile = path.join(tmpDir, "real.txt");
    const linkFile = path.join(tmpDir, "link.txt");
    fs.writeFileSync(realFile, "content");
    fs.symlinkSync(realFile, linkFile);
    const result = await dispatch(
      { cmd: "fs.paths.resolve", args: { paths: [linkFile] } },
      {} as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data.resolved as any[])[0].resolved).toBe(fs.realpathSync(realFile));
  });

  it("resolves multiple paths in a single call", async () => {
    const file1 = path.join(tmpDir, "a.txt");
    fs.writeFileSync(file1, "a");
    const result = await dispatch(
      { cmd: "fs.paths.resolve", args: { paths: [file1, "/nonexistent", "~/test"] } },
      {} as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const resolved = result.data.resolved as any[];
    expect(resolved).toHaveLength(3);
    expect(resolved[0].exists).toBe(true);
    expect(resolved[1].exists).toBe(false);
  });

  it("rejects empty paths array", async () => {
    const result = await dispatch(
      { cmd: "fs.paths.resolve", args: { paths: [] } },
      {} as RpcContext
    );
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("VALIDATION_ERROR");
  });

  // ── Category B: Edge Cases ──────────────────────────────────

  it("B/1: resolves bare tilde '~' to home directory", async () => {
    const result = await dispatch(
      { cmd: "fs.paths.resolve", args: { paths: ["~"] } },
      {} as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const resolved = (result.data.resolved as any[])[0];
    expect(resolved.original).toBe("~");
    // Bare "~" should resolve to homedir (via realpathSync for symlink resolution)
    expect(resolved.resolved).toBe(fs.realpathSync(os.homedir()));
  });

  it("B/2: normalizes paths with .. segments", async () => {
    const result = await dispatch(
      { cmd: "fs.paths.resolve", args: { paths: ["/foo/bar/../baz"] } },
      {} as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const resolved = (result.data.resolved as any[])[0];
    expect(resolved.resolved).toBe("/foo/baz");
  });

  it("B/3: handles paths with spaces and special characters", async () => {
    const spacedDir = path.join(tmpDir, "my dir (copy)");
    fs.mkdirSync(spacedDir);
    const spacedFile = path.join(spacedDir, "file name.txt");
    fs.writeFileSync(spacedFile, "content");

    const result = await dispatch(
      { cmd: "fs.paths.resolve", args: { paths: [spacedFile] } },
      {} as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const resolved = (result.data.resolved as any[])[0];
    expect(resolved.exists).toBe(true);
    expect(resolved.resolved).toContain("my dir (copy)");
    expect(resolved.resolved).toContain("file name.txt");
  });
});
