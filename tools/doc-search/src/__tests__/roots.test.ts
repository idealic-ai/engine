/**
 * Which folders `doc-search index` reads. The roots come from a per-project
 * config file, resolved against the project root and the user's home — never
 * against the working directory — so an index started from a subdirectory, a
 * session hook or an unrelated cwd reads the same files.
 */
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import fg from "fast-glob";
import {
  CONFIG_FILENAMES,
  singleGlobRoot,
  loadDocRoots,
  collectDocFiles,
  type DocRoot,
} from "../roots.js";

let tmp: string;
let project: string;
let home: string;

function write(file: string, text = "# T\n\n## S\nBody.\n"): void {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, text);
}

/** A project shaped like kit: top-level packages, a handbook, build output under docs/. */
function makeKitLikeProject(): void {
  write(path.join(project, "docs", "README.md"));
  write(path.join(project, "docs", "guide", "intro.md"));
  write(path.join(project, "docs", "dist", "client", "intro.md")); // build output
  write(path.join(project, "docs", "public", "raw", "en", "intro.md")); // build output
  write(path.join(project, "docs", "node_modules", "d3", "README.md")); // vendored
  write(path.join(project, "handbook", "README.md"));
  write(path.join(project, "handbook", "kernel", "dispatch.md"));
  write(path.join(project, "resource-kernel", "VISION.md"));
  write(path.join(project, "resource-kernel", "README.md"));
  write(path.join(project, "resource-kernel", "CHANGELOG.md"));
  write(path.join(project, "resource-kernel", "docs", "addresses.md"));
  write(path.join(project, "resource-kernel", "src", "notes.md")); // not a doc root
  write(path.join(project, "ui", "ARCHITECTURE.md"));
  write(path.join(project, "node_modules", "left-pad", "README.md"));
  write(path.join(project, ".directives", "PITFALLS.md"));
  fs.mkdirSync(path.join(project, ".claude"), { recursive: true });
  // The engine lives outside the project, under the user's home.
  write(path.join(home, ".claude", "engine", "docs", "DOCUMENT_INDEXING.md"));
  write(path.join(home, ".claude", "engine", ".directives", "commands", "CMD_LOG.md"));
  write(path.join(home, ".claude", "engine", "README.md")); // not named
}

const KIT_LIKE_CONFIG = {
  roots: [
    {
      name: "kit",
      path: ".",
      globs: ["docs/**/*.md", "handbook/**/*.md", "*/docs/**/*.md", "*/*.md", ".directives/**/*.md"],
      ignore: ["docs/dist/**", "docs/public/raw/**", "**/CHANGELOG.md"],
    },
    { name: "engine", path: "~/.claude/engine", globs: ["docs/**/*.md", ".directives/**/*.md"] },
  ],
};

function writeConfig(cfg: unknown, where = path.join(project, ".claude", "doc-search.json")): string {
  write(where, JSON.stringify(cfg, null, 2));
  return where;
}

beforeEach(() => {
  tmp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "doc-search-roots-")));
  project = path.join(tmp, "kit");
  home = path.join(tmp, "home");
  fs.mkdirSync(project, { recursive: true });
  fs.mkdirSync(home, { recursive: true });
});
afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

describe("loadDocRoots", () => {
  it("without a config file keeps the old single-root default", () => {
    const { roots, source } = loadDocRoots(project, { home, env: {} });
    expect(source).toBeNull();
    expect(roots).toHaveLength(1);
    expect(roots[0].path).toBe(project);
    // Spelled out, not the exported constant: a test comparing the constant
    // with itself cannot notice the default changing.
    expect(roots[0].globs).toEqual(["docs/**/*.md", "{apps,packages}/*/docs/**/*.md"]);
  });

  it("reads the config files in a fixed order: env, tracked, then .claude/", () => {
    expect(CONFIG_FILENAMES).toEqual([".doc-search.json", path.join(".claude", "doc-search.json")]);
    writeConfig({ roots: [{ name: "a", path: ".", globs: ["a/**/*.md"] }] }, path.join(project, ".claude", "doc-search.json"));
    expect(loadDocRoots(project, { home, env: {} }).roots[0].name).toBe("a");

    writeConfig({ roots: [{ name: "b", path: ".", globs: ["b/**/*.md"] }] }, path.join(project, ".doc-search.json"));
    expect(loadDocRoots(project, { home, env: {} }).roots[0].name).toBe("b");

    const fromEnv = writeConfig({ roots: [{ name: "c", path: ".", globs: ["c/**/*.md"] }] }, path.join(tmp, "elsewhere.json"));
    const loaded = loadDocRoots(project, { home, env: { DOC_SEARCH_CONFIG: fromEnv } });
    expect(loaded.roots[0].name).toBe("c");
    expect(loaded.source).toBe(fromEnv);
  });

  it("resolves a root against the project and home, never the working directory", () => {
    writeConfig(KIT_LIKE_CONFIG);
    const before = process.cwd();
    try {
      process.chdir(os.tmpdir());
      const { roots } = loadDocRoots(project, { home, env: {} });
      expect(roots.map((r) => [r.name, r.path])).toEqual([
        ["kit", project],
        ["engine", path.join(home, ".claude", "engine")],
      ]);
    } finally {
      process.chdir(before);
    }
  });

  it("does not look for a config when the project root is the home directory", () => {
    // A kit worktree without its own .claude/ resolves to ~; a doc-search.json
    // in ~/.claude/ must not become the config for every such run.
    write(path.join(home, ".claude", "doc-search.json"), JSON.stringify({ roots: [{ name: "home", path: ".", globs: ["**/*.md"] }] }));
    write(path.join(home, ".doc-search.json"), JSON.stringify({ roots: [{ name: "home", path: ".", globs: ["**/*.md"] }] }));
    const loaded = loadDocRoots(home, { home, env: {} });
    expect(loaded.source).toBeNull();
    expect(loaded.roots[0].globs).toEqual(["docs/**/*.md", "{apps,packages}/*/docs/**/*.md"]);
  });

  it("at the home directory still honours an explicit $DOC_SEARCH_CONFIG, and a missing one still throws", () => {
    // Only the config FILES at ~ are skipped; the variable is set per command
    // on purpose and is the one lever a run resolving to ~ has.
    write(path.join(home, ".claude", "doc-search.json"), JSON.stringify({ roots: [{ name: "home", path: ".", globs: ["**/*.md"] }] }));
    const fromEnv = writeConfig({ roots: [{ name: "env", path: ".", globs: ["docs/**/*.md"] }] }, path.join(tmp, "explicit.json"));
    const loaded = loadDocRoots(home, { home, env: { DOC_SEARCH_CONFIG: fromEnv } });
    expect(loaded.source).toBe(fromEnv);
    expect(loaded.roots.map((r) => r.name)).toEqual(["env"]);
    expect(() => loadDocRoots(home, { home, env: { DOC_SEARCH_CONFIG: path.join(tmp, "nonexistent.json") } })).toThrow(/does not exist/);
  });

  it("recognises the home directory through a symlink, not only by its spelling", () => {
    write(path.join(home, ".claude", "doc-search.json"), JSON.stringify({ roots: [{ name: "home", path: ".", globs: ["**/*.md"] }] }));
    const homeLink = path.join(tmp, "home-link");
    fs.symlinkSync(home, homeLink);
    expect(loadDocRoots(home, { home: homeLink, env: {} }).source).toBeNull();
    expect(loadDocRoots(homeLink, { home, env: {} }).source).toBeNull();
  });

  it("an empty HOME does not make the working directory count as home", () => {
    const cfg = writeConfig({ roots: [{ name: "proj", path: ".", globs: ["docs/**/*.md"] }] });
    const before = process.cwd();
    try {
      process.chdir(project);
      expect(loadDocRoots(project, { home: "", env: {} }).source).toBe(cfg);
    } finally {
      process.chdir(before);
    }
  });

  it("refuses a config that names no roots or a root without globs, rather than indexing nothing", () => {
    writeConfig({ roots: [] });
    expect(() => loadDocRoots(project, { home, env: {} })).toThrow(/roots/);
    writeConfig({ roots: [{ name: "x", path: "." }] });
    expect(() => loadDocRoots(project, { home, env: {} })).toThrow(/globs/);
    writeConfig({ roots: [{ name: "x", path: ".", globs: ["a"] }, { name: "x", path: "..", globs: ["b"] }] });
    expect(() => loadDocRoots(project, { home, env: {} })).toThrow(/twice/);
  });
});

describe("collectDocFiles over a kit-shaped project", () => {
  function collect(roots: DocRoot[]) {
    return collectDocFiles(roots, project);
  }

  it("indexes every named root, and each one is visible in the result", async () => {
    makeKitLikeProject();
    writeConfig(KIT_LIKE_CONFIG);
    const { roots } = loadDocRoots(project, { home, env: {} });
    const { files, perRoot } = await collect(roots);
    const stored = files.map((f) => f.storedPath).sort();

    const engine = path.join(home, ".claude", "engine");
    expect(stored).toEqual(
      [
        ".directives/PITFALLS.md",
        "docs/README.md",
        "docs/guide/intro.md",
        "handbook/README.md",
        "handbook/kernel/dispatch.md",
        "resource-kernel/README.md",
        "resource-kernel/VISION.md",
        "resource-kernel/docs/addresses.md",
        "ui/ARCHITECTURE.md",
        path.join(engine, ".directives", "commands", "CMD_LOG.md"),
        path.join(engine, "docs", "DOCUMENT_INDEXING.md"),
      ].sort()
    );
    expect(perRoot).toEqual({ kit: 9, engine: 2 });
  });

  it("names every folder the operator asked for — dropping one fails here", async () => {
    // The roots IDE-333 named: kit docs/, kit handbook/, each package's own
    // docs (its docs/ tree and its root README/VISION), the engine's docs/ and
    // .directives/. Each must contribute at least one file.
    makeKitLikeProject();
    writeConfig(KIT_LIKE_CONFIG);
    const { roots } = loadDocRoots(project, { home, env: {} });
    const { files } = await collect(roots);
    const engine = path.join(home, ".claude", "engine");
    const named: Record<string, (p: string) => boolean> = {
      "kit docs/": (p) => p.startsWith("docs/"),
      "kit handbook/": (p) => p.startsWith("handbook/"),
      "package docs/": (p) => /^[^/]+\/docs\//.test(p) && !p.startsWith("docs/"),
      "package VISION.md": (p) => /^[^/]+\/VISION\.md$/.test(p),
      "package README.md": (p) => /^[^/]+\/README\.md$/.test(p) && !p.startsWith("docs/") && !p.startsWith("handbook/"),
      "engine docs/": (p) => p.startsWith(path.join(engine, "docs") + path.sep),
      "engine .directives/": (p) => p.startsWith(path.join(engine, ".directives") + path.sep),
    };
    const missing = Object.entries(named)
      .filter(([, hit]) => !files.some((f) => hit(f.storedPath)))
      .map(([name]) => name);
    expect(missing).toEqual([]);

    // The control: drop the engine root and the same check must notice.
    const withoutEngine = roots.filter((r) => r.name !== "engine");
    const { files: fewer } = await collect(withoutEngine);
    const missingAfterDrop = Object.entries(named)
      .filter(([, hit]) => !fewer.some((f) => hit(f.storedPath)))
      .map(([name]) => name);
    expect(missingAfterDrop).toEqual(["engine docs/", "engine .directives/"]);
  });

  it("never reads node_modules, even when a glob would reach it", async () => {
    makeKitLikeProject();
    writeConfig({ roots: [{ name: "all", path: ".", globs: ["**/*.md"] }] });
    const { roots } = loadDocRoots(project, { home, env: {} });
    const { files } = await collect(roots);
    expect(files.some((f) => f.storedPath.includes("node_modules"))).toBe(false);
  });

  it("skips a root whose folder is missing and says so, instead of failing the index", async () => {
    makeKitLikeProject();
    writeConfig({
      roots: [
        { name: "kit", path: ".", globs: ["docs/**/*.md"] },
        { name: "gone", path: "~/nowhere", globs: ["**/*.md"] },
      ],
    });
    const { roots } = loadDocRoots(project, { home, env: {} });
    const { perRoot, missingRoots } = await collect(roots);
    expect(perRoot.gone).toBe(0);
    expect(missingRoots).toEqual([path.join(home, "nowhere")]);
  });

  it('with "tracked": true reads only files git tracks, so scratch and build dirs drop out by construction', async () => {
    makeKitLikeProject();
    write(path.join(project, "builds", "scratch.md")); // untracked, matches */*.md
    execFileSync("git", ["init", "-q"], { cwd: project });
    execFileSync("git", ["add", "docs/README.md", "docs/guide/intro.md", "resource-kernel/VISION.md", "handbook/README.md"], { cwd: project });
    writeConfig({ roots: [{ name: "kit", path: ".", globs: ["docs/**/*.md", "handbook/**/*.md", "*/*.md"], tracked: true }] });
    const { roots } = loadDocRoots(project, { home, env: {} });
    expect(roots[0].tracked).toBe(true);
    const { files } = await collect(roots);
    expect(files.map((f) => f.storedPath).sort()).toEqual([
      "docs/README.md",
      "docs/guide/intro.md",
      "handbook/README.md",
      "resource-kernel/VISION.md",
    ]);
  });

  it("with no config, indexes exactly what the old hard-coded globs found — node_modules included", async () => {
    write(path.join(project, "docs", "a.md"));
    write(path.join(project, "docs", "node_modules", "d3", "README.md"));
    write(path.join(project, "packages", "p", "docs", "b.md"));
    write(path.join(project, "handbook", "c.md"));
    // Symlinks the old call followed and spelled out once per alias: a
    // relative alias, a link out of the project, a link to a package's docs
    // and a loop. Every spelling must come back exactly as it did before.
    write(path.join(project, "docs", "real", "r.md"));
    fs.symlinkSync("real", path.join(project, "docs", "alias"));
    write(path.join(tmp, "outside", "o.md"));
    fs.symlinkSync(path.join(tmp, "outside"), path.join(project, "docs", "out"));
    fs.symlinkSync(path.join("..", "packages", "p", "docs"), path.join(project, "docs", "pdocs"));
    fs.mkdirSync(path.join(project, "docs", "loop"), { recursive: true });
    fs.symlinkSync("..", path.join(project, "docs", "loop", "up"));
    // The pre-IDE-333 call, verbatim: cli.ts ran fg(DEFAULT_DOCS_GLOBS, {cwd, followSymbolicLinks, onlyFiles}).
    const old = await fg(["docs/**/*.md", "{apps,packages}/*/docs/**/*.md"], {
      cwd: project,
      followSymbolicLinks: true,
      onlyFiles: true,
    });
    expect(old).toContain("docs/node_modules/d3/README.md");
    expect(old).toContain("docs/real/r.md");
    expect(old).toContain("docs/alias/r.md");
    expect(old).toContain("docs/out/o.md");
    expect(old).toContain("packages/p/docs/b.md");
    expect(old.some((p) => p.startsWith("docs/loop/up/"))).toBe(true);
    const { roots } = loadDocRoots(project, { home, env: {} });
    const { files } = await collect(roots);
    expect(files.map((f) => f.storedPath).sort()).toEqual([...old].sort());
    // --path is the same shape and must agree too.
    const viaPath = await fg(["docs/**/*.md"], { cwd: project, followSymbolicLinks: true, onlyFiles: true });
    const { files: pathFiles } = await collect([singleGlobRoot(project, "docs/**/*.md")]);
    expect(pathFiles.map((f) => f.storedPath).sort()).toEqual([...viaPath].sort());
  });

  it("--path reads its one glob exactly as before, node_modules included", async () => {
    write(path.join(project, "docs", "a.md"));
    write(path.join(project, "docs", "node_modules", "d3", "README.md"));
    const { files } = await collect([singleGlobRoot(project, "docs/**/*.md")]);
    expect(files.map((f) => f.storedPath).sort()).toEqual(["docs/a.md", "docs/node_modules/d3/README.md"]);
  });

  it("a tracked root outside git is skipped with a warning; the other roots still index", async () => {
    makeKitLikeProject(); // not a git repo
    writeConfig({
      roots: [
        { name: "kit", path: ".", globs: ["handbook/**/*.md"], tracked: true },
        { name: "engine", path: "~/.claude/engine", globs: ["docs/**/*.md"] },
      ],
    });
    const { roots } = loadDocRoots(project, { home, env: {} });
    const { files, perRoot, untrackedRoots } = await collect(roots);
    expect(untrackedRoots.map((u) => u.path)).toEqual([project]);
    // git's own words, not a guess at the cause.
    expect(untrackedRoots[0].reason).toMatch(/not a git repository/i);
    expect(perRoot).toEqual({ kit: 0, engine: 1 });
    expect(files.map((f) => f.root)).toEqual(["engine"]);
  });

  it("two roots reaching the same file — overlapping folders or a symlinked alias — read it once", async () => {
    write(path.join(project, "docs", "a.md"));
    write(path.join(project, "docs", "sub", "b.md"));
    fs.symlinkSync(path.join(project, "docs"), path.join(tmp, "docs-alias"));
    writeConfig({
      roots: [
        { name: "kit", path: ".", globs: ["docs/**/*.md"] },
        { name: "sub", path: "docs/sub", globs: ["**/*.md"] },
        { name: "alias", path: path.join(tmp, "docs-alias"), globs: ["**/*.md"] },
      ],
    });
    const { roots } = loadDocRoots(project, { home, env: {} });
    const { files, perRoot } = await collect(roots);
    expect(files.map((f) => f.storedPath).sort()).toEqual(["docs/a.md", "docs/sub/b.md"]);
    expect(perRoot).toEqual({ kit: 2, sub: 0, alias: 0 });
    const { emptyRoots } = await collect(roots);
    expect(emptyRoots).toEqual([]);
  });

  it("names a root whose folder exists but whose globs match nothing", async () => {
    makeKitLikeProject();
    writeConfig({
      roots: [
        { name: "kit", path: ".", globs: ["handbok/**/*.md"] }, // typo
        { name: "engine", path: "~/.claude/engine", globs: ["docs/**/*.md"] },
        { name: "gone", path: "~/nowhere", globs: ["**/*.md"] },
      ],
    });
    const { roots } = loadDocRoots(project, { home, env: {} });
    const { emptyRoots, missingRoots, perRoot } = await collect(roots);
    expect(perRoot).toEqual({ kit: 0, engine: 1, gone: 0 });
    // A missing folder is reported as missing, not also as empty.
    expect(emptyRoots).toEqual(["kit"]);
    expect(missingRoots).toEqual([path.join(home, "nowhere")]);
  });

  it('a "tracked" root reads the files of the submodules it contains', async () => {
    const git = (cwd: string, ...args: string[]) =>
      execFileSync("git", ["-c", "user.email=t@t", "-c", "user.name=t", "-c", "protocol.file.allow=always", ...args], {
        cwd,
        stdio: "ignore",
      });
    const inner = path.join(tmp, "inner");
    write(path.join(inner, "docs", "i.md"));
    git(inner, "init", "-q");
    git(inner, "add", ".");
    git(inner, "commit", "-q", "-m", "inner");
    write(path.join(project, "docs", "o.md"));
    git(project, "init", "-q");
    git(project, "add", "docs/o.md");
    git(project, "submodule", "add", "-q", inner, "vendor/inner");
    writeConfig({ roots: [{ name: "kit", path: ".", globs: ["**/*.md"], tracked: true }] });
    const { roots } = loadDocRoots(project, { home, env: {} });
    const { files } = await collect(roots);
    expect(files.map((f) => f.storedPath).sort()).toEqual(["docs/o.md", "vendor/inner/docs/i.md"]);
  });

  it("the default still reads docs/ and {apps,packages}/*/docs/", async () => {
    write(path.join(project, "docs", "a.md"));
    write(path.join(project, "packages", "p", "docs", "b.md"));
    write(path.join(project, "handbook", "c.md"));
    const { roots } = loadDocRoots(project, { home, env: {} });
    const { files } = await collect(roots);
    expect(files.map((f) => f.storedPath).sort()).toEqual(["docs/a.md", "packages/p/docs/b.md"]);
  });
});
