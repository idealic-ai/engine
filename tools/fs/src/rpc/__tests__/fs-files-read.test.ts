import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { dispatch } from "engine-shared/dispatch";
import type { RpcContext } from "engine-shared/context";

import "../fs-files-read.js";

describe("fs.files.read", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "fs-read-test-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("reads an existing file as utf-8", async () => {
    const filePath = path.join(tmpDir, "test.txt");
    fs.writeFileSync(filePath, "hello world");
    const result = await dispatch({ cmd: "fs.files.read", args: { path: filePath } }, {} as RpcContext);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.content).toBe("hello world");
    expect(result.data.size).toBe(11);
  });

  it("reads a file as base64", async () => {
    const filePath = path.join(tmpDir, "binary.bin");
    const buf = Buffer.from([0x00, 0x01, 0x02, 0xff]);
    fs.writeFileSync(filePath, buf);
    const result = await dispatch({ cmd: "fs.files.read", args: { path: filePath, encoding: "base64" } }, {} as RpcContext);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.content).toBe(buf.toString("base64"));
  });

  it("returns FS_NOT_FOUND for nonexistent file", async () => {
    const result = await dispatch({ cmd: "fs.files.read", args: { path: "/nonexistent/file.txt" } }, {} as RpcContext);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("FS_NOT_FOUND");
  });

  it("returns FS_IS_DIRECTORY for directories", async () => {
    const result = await dispatch({ cmd: "fs.files.read", args: { path: tmpDir } }, {} as RpcContext);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("FS_IS_DIRECTORY");
  });

  it("returns FS_TOO_LARGE when file exceeds maxSize", async () => {
    const filePath = path.join(tmpDir, "big.txt");
    fs.writeFileSync(filePath, "x".repeat(1000));
    const result = await dispatch({ cmd: "fs.files.read", args: { path: filePath, maxSize: 100 } }, {} as RpcContext);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("FS_TOO_LARGE");
  });

  it("reads empty files without error", async () => {
    const filePath = path.join(tmpDir, "empty.txt");
    fs.writeFileSync(filePath, "");
    const result = await dispatch({ cmd: "fs.files.read", args: { path: filePath } }, {} as RpcContext);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.content).toBe("");
    expect(result.data.size).toBe(0);
  });

  // ── Category C: Error Paths & Boundaries ──────────────────

  it("C/1: returns mtime as ISO string in response", async () => {
    const filePath = path.join(tmpDir, "mtime-check.txt");
    fs.writeFileSync(filePath, "check mtime");
    const result = await dispatch({ cmd: "fs.files.read", args: { path: filePath } }, {} as RpcContext);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    // mtime should be a valid ISO 8601 string
    const mtime = result.data.mtime as string;
    expect(mtime).toBeDefined();
    expect(new Date(mtime).toISOString()).toBe(mtime);
  });

  it("C/2: uses default MAX_FILE_SIZE (10MB) when maxSize not specified", async () => {
    const filePath = path.join(tmpDir, "small.txt");
    fs.writeFileSync(filePath, "small file");
    // Read without maxSize — should use 10MB default and succeed
    const result = await dispatch({ cmd: "fs.files.read", args: { path: filePath } }, {} as RpcContext);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.content).toBe("small file");
  });

  it("C/3: follows symlinks to read target file", async () => {
    const realFile = path.join(tmpDir, "real-target.txt");
    const linkFile = path.join(tmpDir, "symlink.txt");
    fs.writeFileSync(realFile, "symlinked content");
    fs.symlinkSync(realFile, linkFile);

    const result = await dispatch({ cmd: "fs.files.read", args: { path: linkFile } }, {} as RpcContext);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.content).toBe("symlinked content");
  });
});
