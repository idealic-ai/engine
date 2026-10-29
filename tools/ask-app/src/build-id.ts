/**
 * The client's build id: a hash of everything the built client is made
 * from — every file under src/client, src/lib/format.ts (the client imports it), and every stylesheet
 * main.tsx imports, wherever it lives. `vite build` writes it into the output as `.build-id`;
 * `engine ask serve` rebuilds only when the built id differs from the sources'; the server refuses
 * to serve a client whose id is missing or not the one its own sources make. Mtimes are never used:
 * a checkout, a merge or a restored copy moves them in either direction.
 *
 * Usage: node src/build-id.ts            prints the id the current sources make
 *        node src/build-id.ts <dist>     prints the id recorded in <dist>/.build-id (or nothing)
 */
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const BUILD_ID_FILE = ".build-id";
export const APP_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function walk(dir: string): string[] {
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .flatMap((d) => (d.isDirectory() ? walk(path.join(dir, d.name)) : [path.join(dir, d.name)]))
    .filter((f) => !path.basename(f).startsWith("."));
}

/** The files the client is built from, sorted: src/client/**, format.ts, and main.tsx's CSS imports. */
export function buildInputs(appDir = APP_DIR): string[] {
  const client = path.join(appDir, "src", "client");
  const main = fs.readFileSync(path.join(client, "main.tsx"), "utf8");
  const sheets = [...main.matchAll(/^import\s+["']([^"']+\.css)["'];?\s*$/gm)].map((m) => path.resolve(client, m[1]));
  return [...new Set([...walk(client), path.join(appDir, "src", "lib", "format.ts"), ...sheets])].sort();
}

/** sha256 over each input's path (relative to the engine root) and bytes; the first 16 hex digits. */
export function computeBuildId(appDir = APP_DIR): string {
  const base = path.resolve(appDir, "..", "..");
  const h = createHash("sha256");
  for (const f of buildInputs(appDir)) {
    h.update(path.relative(base, f));
    h.update("\0");
    h.update(fs.readFileSync(f));
    h.update("\0");
  }
  return h.digest("hex").slice(0, 16);
}

/** The id recorded in a built client, or undefined when it has none (a v1 build, or no build). */
export function recordedBuildId(dist: string): string | undefined {
  try {
    return fs.readFileSync(path.join(dist, BUILD_ID_FILE), "utf8").trim() || undefined;
  } catch {
    return undefined;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const dist = process.argv[2];
  process.stdout.write(`${dist ? (recordedBuildId(dist) ?? "") : computeBuildId()}\n`);
}
