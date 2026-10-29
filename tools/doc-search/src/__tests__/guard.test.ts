/**
 * doc-search's refusals: the Gemini-era file name (M1), any schema but the
 * current one (S1), decided from the header before the full read (S2).
 */
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { initDb, saveDb, SCHEMA_VERSION } from "../db.js";

let dir: string;
beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), "doc-search-guard-"));
});
afterEach(() => {
  fs.rmSync(dir, { recursive: true, force: true });
});

async function imageAt(version: number): Promise<{ p: string; before: Buffer }> {
  const p = path.join(dir, ".doc-search.local.db");
  const db = await initDb(p);
  db.run(`PRAGMA user_version = ${version};`);
  saveDb(db, p);
  db.close();
  return { p, before: fs.readFileSync(p) };
}

describe("doc-search guard", () => {
  it("refuses user_version 0 and leaves the file byte-identical", async () => {
    const { p, before } = await imageAt(0);
    await expect(initDb(p)).rejects.toThrow(/\[doc-search\] .*unversioned index/);
    expect(fs.readFileSync(p).equals(before)).toBe(true);
  });

  it("refuses a newer schema and leaves the file byte-identical", async () => {
    const { p, before } = await imageAt(SCHEMA_VERSION + 1);
    await expect(initDb(p)).rejects.toThrow(/newer build \(schema 3\)/);
    expect(fs.readFileSync(p).equals(before)).toBe(true);
  });

  it("refuses the Gemini-era name and creates nothing", async () => {
    const p = path.join(dir, ".doc-search.db");
    await expect(initDb(p)).rejects.toThrow(/\.doc-search\.db is a Gemini-era file name/);
    expect(fs.existsSync(p)).toBe(false);
  });

  it("refuses a 3 GiB Gemini-era file from its header, without loading it", async () => {
    const { p } = await imageAt(1);
    fs.truncateSync(p, 3 * 1024 ** 3);
    const t0 = Date.now();
    await expect(initDb(p)).rejects.toThrow(/Gemini-era index \(schema 1\)/);
    expect(Date.now() - t0).toBeLessThan(5000);
  });
});
