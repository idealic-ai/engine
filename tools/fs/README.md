# engine-fs

Pure filesystem RPC handlers for the daemon.

## Purpose

Provides filesystem operations as RPC handlers that follow the shared
dispatch pattern. These handlers have zero database dependency -- they
operate on the local filesystem only.

Ports path normalization logic from `lib.sh`'s `normalize_preload_path()`.

## Handlers

### fs.paths.resolve

Path normalization: tilde expansion, symlink resolution, relative-to-absolute
conversion, and existence checking.

**Schema:**

```typescript
{
  paths: string[];     // one or more paths to resolve (min 1)
  cwd?: string;        // working directory for relative paths (default: process.cwd())
}
```

**Response:**

```typescript
{
  resolved: Array<{
    original: string;  // input path as provided
    resolved: string;  // fully resolved absolute path
    exists: boolean;   // whether the resolved path exists on disk
  }>
}
```

**Behavior:**

1. Tilde expansion (`~/foo` -> `/Users/name/foo`)
2. Relative to absolute (using `cwd` or `process.cwd()`)
3. Path normalization (remove `.` and `..`)
4. Symlink resolution via `realpathSync` (handles macOS `/var` -> `/private/var`)
5. Existence check on the resolved path

If the path does not exist, `resolved` contains the normalized path
(without symlink resolution) and `exists` is `false`.

### fs.files.read

File read with encoding support and error taxonomy.

**Schema:**

```typescript
{
  path: string;                          // absolute path to read
  encoding?: "utf-8" | "base64";        // default: "utf-8"
  maxSize?: number;                      // byte limit (default: 10MB)
}
```

**Response (success):**

```typescript
{
  content: string;   // file content in requested encoding
  size: number;      // file size in bytes
  mtime: string;     // last modified time (ISO 8601)
}
```

**Error codes:**

| Error Code | Meaning |
|---|---|
| `FS_NOT_FOUND` | File does not exist (ENOENT) |
| `FS_PERMISSION` | Permission denied (EACCES) |
| `FS_IS_DIRECTORY` | Path is a directory, not a file |
| `FS_TOO_LARGE` | File exceeds `maxSize` limit |

## Files

```
src/
  rpc/
    fs-paths-resolve.ts    -- fs.paths.resolve handler
    fs-files-read.ts        -- fs.files.read handler
  __tests__/
    fs-paths-resolve.test.ts
    fs-files-read.test.ts
```

## Tests

24 tests across 2 test files.
