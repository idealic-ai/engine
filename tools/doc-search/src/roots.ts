/**
 * Which folders `doc-search index` reads.
 *
 * A project names its documentation roots in a config file. Without one, the
 * tool keeps its old behaviour: `docs/` and `{apps,packages}/*\/docs/` under the
 * project root. The engine itself names no project's folders.
 *
 * Every path is resolved against the project root (relative paths) or the
 * user's home (`~/...`), never against the working directory, so an index run
 * from a subdirectory, a session hook or another cwd reads the same files.
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import fg from "fast-glob";

/** The roots a project gets when it has no config file. */
export const DEFAULT_DOCS_GLOBS = ["docs/**/*.md", "{apps,packages}/*/docs/**/*.md"];

/** Never indexed, whatever a glob says: vendored READMEs are not the project's docs. */
export const ALWAYS_IGNORED = ["**/node_modules/**"];

/**
 * Where a project's config is looked for, relative to the project root, after
 * `$DOC_SEARCH_CONFIG`. The first is meant to be committed with the project;
 * the second sits in `.claude/`, which a project may keep out of git.
 */
export const CONFIG_FILENAMES = [".doc-search.json", path.join(".claude", "doc-search.json")];

export const CONFIG_ENV = "DOC_SEARCH_CONFIG";

export interface DocRoot {
  /** Short label, shown in index output. Unique within a config. */
  name: string;
  /** Absolute folder the globs are matched in. */
  path: string;
  globs: string[];
  ignore: string[];
  /** Keep only files git tracks under this root: build output, scratch dirs and
   *  other untracked or gitignored folders drop out without an ignore list. */
  tracked?: boolean;
}

export interface LoadedRoots {
  roots: DocRoot[];
  /** The config file the roots came from; null when the default was used. */
  source: string | null;
}

export interface LoadOptions {
  home?: string;
  env?: NodeJS.ProcessEnv;
}

function expandPath(p: string, base: string, home: string): string {
  if (p === "~") return home;
  if (p.startsWith("~/")) return path.join(home, p.slice(2));
  return path.resolve(base, p);
}

function findConfig(projectRoot: string, env: NodeJS.ProcessEnv, home: string): string | null {
  const fromEnv = env[CONFIG_ENV];
  if (fromEnv && fromEnv.length > 0) {
    const resolved = expandPath(fromEnv, projectRoot, home);
    if (!fs.existsSync(resolved)) {
      throw new Error(`[doc-search] ${CONFIG_ENV}=${fromEnv} does not exist`);
    }
    return resolved;
  }
  for (const name of CONFIG_FILENAMES) {
    const candidate = path.join(projectRoot, name);
    if (fs.existsSync(candidate)) return candidate;
  }
  return null;
}

function stringList(value: unknown, what: string, source: string): string[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.some((v) => typeof v !== "string" || v.length === 0)) {
    throw new Error(`[doc-search] ${source}: ${what} must be a list of non-empty strings`);
  }
  return value as string[];
}

/** Read the project's roots, or the default single root when it has no config. */
export function loadDocRoots(projectRoot: string, opts: LoadOptions = {}): LoadedRoots {
  const home = opts.home ?? os.homedir();
  const env = opts.env ?? process.env;
  const source = findConfig(projectRoot, env, home);

  if (!source) {
    return {
      roots: [{ name: path.basename(projectRoot), path: projectRoot, globs: [...DEFAULT_DOCS_GLOBS], ignore: [] }],
      source: null,
    };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(fs.readFileSync(source, "utf-8"));
  } catch (err) {
    throw new Error(`[doc-search] ${source}: not valid JSON (${(err as Error).message})`);
  }
  const rawRoots = (parsed as { roots?: unknown })?.roots;
  if (!Array.isArray(rawRoots) || rawRoots.length === 0) {
    throw new Error(`[doc-search] ${source}: "roots" must be a non-empty list`);
  }

  const seen = new Set<string>();
  const roots = rawRoots.map((raw, i): DocRoot => {
    const r = raw as Record<string, unknown>;
    const name = typeof r.name === "string" && r.name.length > 0 ? r.name : `root${i}`;
    if (seen.has(name)) throw new Error(`[doc-search] ${source}: root "${name}" is named twice`);
    seen.add(name);
    if (typeof r.path !== "string" || r.path.length === 0) {
      throw new Error(`[doc-search] ${source}: root "${name}" needs a "path"`);
    }
    const globs = stringList(r.globs, `root "${name}" globs`, source);
    if (globs.length === 0) throw new Error(`[doc-search] ${source}: root "${name}" needs at least one of "globs"`);
    return {
      name,
      // Relative to the project root — not to the config file, and never to cwd.
      path: expandPath(r.path, projectRoot, home),
      globs,
      ignore: stringList(r.ignore, `root "${name}" ignore`, source),
      tracked: r.tracked === true,
    };
  });

  return { roots, source };
}

export interface DocFile {
  /** Where to read it. */
  absPath: string;
  /** What the index stores as file_path: relative to the project root when the
   *  file is inside it (so existing rows keep their keys), absolute otherwise. */
  storedPath: string;
  root: string;
}

export interface CollectedFiles {
  files: DocFile[];
  /** Files per root name, after de-duplication across roots. */
  perRoot: Record<string, number>;
  /** Root folders that do not exist on this machine (skipped, not fatal). */
  missingRoots: string[];
}

/** List every markdown file the roots name. A file named by two roots is read once. */
export async function collectDocFiles(roots: DocRoot[], projectRoot: string): Promise<CollectedFiles> {
  const files: DocFile[] = [];
  const perRoot: Record<string, number> = {};
  const missingRoots: string[] = [];
  const seen = new Set<string>();

  for (const root of roots) {
    perRoot[root.name] = 0;
    if (!fs.existsSync(root.path)) {
      missingRoots.push(root.path);
      continue;
    }
    const matches = await fg(root.globs, {
      cwd: root.path,
      ignore: [...ALWAYS_IGNORED, ...root.ignore],
      followSymbolicLinks: true,
      onlyFiles: true,
    });
    const keep = root.tracked ? trackedFiles(root.path) : null;
    for (const rel of matches.sort()) {
      if (keep && !keep.has(rel)) continue;
      const absPath = path.join(root.path, rel);
      if (seen.has(absPath)) continue;
      seen.add(absPath);
      const fromProject = path.relative(projectRoot, absPath);
      const inside = fromProject !== "" && !fromProject.startsWith("..") && !path.isAbsolute(fromProject);
      files.push({
        absPath,
        storedPath: inside ? fromProject.split(path.sep).join("/") : absPath,
        root: root.name,
      });
      perRoot[root.name]++;
    }
  }

  return { files, perRoot, missingRoots };
}

/**
 * Paths git tracks under `dir`, relative to it. A root asked to be `tracked`
 * that is not inside a git work tree is an error: silently indexing every
 * untracked file instead would bring back the scratch dirs it was set to drop.
 */
function trackedFiles(dir: string): Set<string> {
  let out: string;
  try {
    out = execFileSync("git", ["ls-files", "-z", "--", "."], {
      cwd: dir,
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 256 * 1024 * 1024,
    });
  } catch (err) {
    throw new Error(`[doc-search] root ${dir} is marked "tracked" but git ls-files failed there: ${(err as Error).message}`);
  }
  return new Set(out.split("\0").filter((p) => p.length > 0));
}
