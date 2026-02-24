import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { dispatch } from "engine-shared/dispatch";
import type { RpcContext } from "engine-shared/context";
import "../fs-files-append.js";

let tmpDir: string;

beforeEach(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "fs-append-"));
});

afterEach(() => {
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

describe("fs.files.append", () => {
  it("should create file and write content", async () => {
    const filePath = path.join(tmpDir, "new.md");

    const result = await dispatch(
      { cmd: "fs.files.append", args: { path: filePath, content: "## Hello\nWorld" } },
      {} as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.path).toBe(filePath);

    const content = fs.readFileSync(filePath, "utf-8");
    expect(content).toBe("## Hello\nWorld\n");
  });

  it("should append to existing file with newline separator", async () => {
    const filePath = path.join(tmpDir, "existing.md");
    fs.writeFileSync(filePath, "First line\n");

    const result = await dispatch(
      { cmd: "fs.files.append", args: { path: filePath, content: "Second line" } },
      {} as RpcContext
    );

    expect(result.ok).toBe(true);
    const content = fs.readFileSync(filePath, "utf-8");
    expect(content).toBe("First line\n\nSecond line\n");
  });

  it("should create parent directories automatically", async () => {
    const filePath = path.join(tmpDir, "deep", "nested", "dir", "file.md");

    const result = await dispatch(
      { cmd: "fs.files.append", args: { path: filePath, content: "Deep content" } },
      {} as RpcContext
    );

    expect(result.ok).toBe(true);
    expect(fs.existsSync(filePath)).toBe(true);
    expect(fs.readFileSync(filePath, "utf-8")).toBe("Deep content\n");
  });

  it("should use custom separator", async () => {
    const filePath = path.join(tmpDir, "custom-sep.md");
    fs.writeFileSync(filePath, "AAA");

    const result = await dispatch(
      { cmd: "fs.files.append", args: { path: filePath, content: "BBB", separator: "---" } },
      {} as RpcContext
    );

    expect(result.ok).toBe(true);
    const content = fs.readFileSync(filePath, "utf-8");
    expect(content).toBe("AAA---BBB\n");
  });

  it("should reject when path is a directory", async () => {
    const dirPath = path.join(tmpDir, "adir");
    fs.mkdirSync(dirPath);

    const result = await dispatch(
      { cmd: "fs.files.append", args: { path: dirPath, content: "test" } },
      {} as RpcContext
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("FS_IS_DIRECTORY");
  });

  it("should handle empty content", async () => {
    const filePath = path.join(tmpDir, "empty.md");

    const result = await dispatch(
      { cmd: "fs.files.append", args: { path: filePath, content: "" } },
      {} as RpcContext
    );

    expect(result.ok).toBe(true);
    const content = fs.readFileSync(filePath, "utf-8");
    expect(content).toBe("\n");
  });
});
