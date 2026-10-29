/**
 * One contender in the lock burst test. Waits for the go file so every
 * contender calls acquireLock in the same instant, prints its result, holds the
 * lock briefly, then releases.
 *
 * Usage: tsx lock-contender.ts <lock-module> <dbPath> <goFile>
 */
import fs from "node:fs";
import { pathToFileURL } from "node:url";

const [lockModule, dbPath, goFile] = process.argv.slice(2);
const { acquireLock, releaseLock } = (await import(pathToFileURL(lockModule).href)) as {
  acquireLock(dbPath: string): boolean;
  releaseLock(dbPath: string): void;
};

console.log("ready");
while (!fs.existsSync(goFile)) {
  await new Promise((r) => setTimeout(r, 2));
}
const got = acquireLock(dbPath);
console.log(got ? "won" : "lost");
await new Promise((r) => setTimeout(r, 1500));
if (got) releaseLock(dbPath);
