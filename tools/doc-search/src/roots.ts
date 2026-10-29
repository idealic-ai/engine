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

/**
 * Never indexed by a CONFIGURED root, whatever its globs say: vendored READMEs
 * are not the project's docs. The no-config default and `--path` do not apply
 * it, so a project without a config indexes exactly what it did before.
 */
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
  /** True for a root read from a config file; only these get ALWAYS_IGNORED. */
  configured?: boolean;
}

/** The pre-config shape: one root at the project root, globs read verbatim. */
export function singleGlobRoot(projectRoot: string, ...globs: string[]): DocRoot {
  return { name: path.basename(projectRoot), path: projectRoot, globs, ignore: [] };
}

function samePath(a: string, b: string): boolean {
  const real = (p: string) => {
    try {
      return fs.realpathSync(p);
    } catch {
      return path.resolve(p);
    }
  };
  return real(a) === real(b);
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
  // An explicit $DOC_SEARCH_CONFIG is set per command on purpose, so it is
  // honoured everywhere — including at ~, where it is the only lever a run has.
  const fromEnv = env[CONFIG_ENV];
  if (fromEnv && fromEnv.length > 0) {
    const resolved = expandPath(fromEnv, projectRoot, home);
    if (!fs.existsSync(resolved)) {
      throw new Error(`[doc-search] ${CONFIG_ENV}=${fromEnv} does not exist`);
    }
    return resolved;
  }
  // A run that resolved its project root to ~ (a worktree with no .claude/ of
  // its own walks up to ~/.claude) has no project config FILE: a
  // doc-search.json in ~/.claude/ would otherwise glob home for every such run.
  // An empty HOME names no directory, so it never matches.
  if (home && samePath(projectRoot, home)) return null;
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
      roots: [singleGlobRoot(projectRoot, ...DEFAULT_DOCS_GLOBS)],
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
      configured: true,
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
  /** Roots marked `tracked` whose `git ls-files` failed (skipped, not fatal), with git's reason. */
  untrackedRoots: UntrackedRoot[];
  /** Names of configured roots whose folder exists but whose globs matched no
   *  file. Their old rows are deleted as orphans by an index run that finds
   *  other files. */
  emptyRoots: string[];
}

export interface UntrackedRoot {
  path: string;
  /** What git said (or why it could not run), not a guess at the cause. */
  reason: string;
}

/**
 * List every markdown file the roots name.
 *
 * Configured roots: a file reached twice — by two overlapping roots, or
 * through a symlinked alias — is read once, under the first root that reached
 * it (compared by real path).
 *
 * The no-config default and `--path` are not de-duplicated by real path: they
 * return every path fast-glob returns, symlinked aliases and loops included,
 * exactly as the tool did before configs existed, so their stored row keys
 * do not change.
 */
export async function collectDocFiles(roots: DocRoot[], projectRoot: string): Promise<CollectedFiles> {
  const files: DocFile[] = [];
  const perRoot: Record<string, number> = {};
  const missingRoots: string[] = [];
  const untrackedRoots: UntrackedRoot[] = [];
  const emptyRoots: string[] = [];
  const seen = new Set<string>();

  for (const root of roots) {
    perRoot[root.name] = 0;
    if (!fs.existsSync(root.path)) {
      missingRoots.push(root.path);
      continue;
    }
    const matches = await fg(root.globs, {
      cwd: root.path,
      ignore: root.configured ? [...ALWAYS_IGNORED, ...root.ignore] : [...root.ignore],
      followSymbolicLinks: true,
      onlyFiles: true,
    });
    let keep: Set<string> | null = null;
    if (root.tracked) {
      const tracked = trackedFiles(root.path);
      if ("reason" in tracked) {
        untrackedRoots.push({ path: root.path, reason: tracked.reason });
        continue;
      }
      keep = tracked.files;
    }
    const kept = keep ? matches.filter((rel) => keep.has(rel)) : matches;
    if (kept.length === 0 && root.configured) emptyRoots.push(root.name);
    for (const rel of kept.sort()) {
      const absPath = path.join(root.path, rel);
      let key = absPath;
      if (root.configured) {
        try {
          key = fs.realpathSync(absPath);
        } catch {
          key = absPath;
        }
      }
      if (seen.has(key)) continue;
      seen.add(key);
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

  return { files, perRoot, missingRoots, untrackedRoots, emptyRoots };
}

/**
 * Paths git tracks under `dir`, relative to it, including the files of any
 * initialised submodule (`--recurse-submodules`), or git's reason when it
 * cannot list them (not a work tree, git missing, output too large). The
 * caller skips such a root rather than indexing every file in it (which would
 * bring back the scratch dirs `tracked` was set to drop) or failing the whole
 * index (which a background session-start run would hide).
 */
function trackedFiles(dir: string): { files: Set<string> } | { reason: string } {
  let out: string;
  try {
    out = execFileSync("git", ["ls-files", "-z", "--recurse-submodules", "--", "."], {
      cwd: dir,
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 256 * 1024 * 1024,
    });
  } catch (err) {
    const e = err as { stderr?: string | Buffer; message?: string };
    const said = e.stderr ? e.stderr.toString().trim() : "";
    return { reason: said || e.message || String(err) };
  }
  return { files: new Set(out.split("\0").filter((p) => p.length > 0)) };
}
