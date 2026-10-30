/**
 * ASKLINK: every ask is reachable by a clickable app URL, `http://127.0.0.1:<port>/a/<seat>/<id>`.
 * The port is the one `engine ask serve` uses (the `<root>/.ask-app.pid` record, else 4977), and
 * the path is the one the client's router opens.
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { askAppBase, askUrl } from "../src/lib/url.ts";
import { parseRoute } from "../src/client/route.ts";

const CLI = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "src", "cli.ts");
const BODY = "## Choose one: Ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n";

let root: string;
beforeEach(() => {
  root = fs.mkdtempSync(path.join(os.tmpdir(), "asklink-"));
});
afterEach(() => fs.rmSync(root, { recursive: true, force: true }));

const cli = (args: string[], input?: string) =>
  spawnSync(process.execPath, ["--no-warnings", CLI, ...args, "--root", root], {
    encoding: "utf8",
    input,
    env: { ...process.env, FLEET_PANE: "domain:stats", FLEET_PARENT: "", TMUX_PANE: "", ASK_ROOT: root },
  });

describe("askUrl", () => {
  it("with no server record, uses ask serve's default port", () => {
    expect(askAppBase(root)).toBe("http://127.0.0.1:4977");
    expect(askUrl(root, "domain:stats", "20261030-130014-where-the-fit-check-sits")).toBe(
      "http://127.0.0.1:4977/a/domain:stats/20261030-130014-where-the-fit-check-sits",
    );
  });

  it("takes the port ask serve recorded in <root>/.ask-app.pid", () => {
    fs.writeFileSync(path.join(root, ".ask-app.pid"), "12345 5123\n");
    expect(askUrl(root, "idealic:ui", "a1")).toBe("http://127.0.0.1:5123/a/idealic:ui/a1");
  });

  it("ignores a malformed pid record", () => {
    fs.writeFileSync(path.join(root, ".ask-app.pid"), "garbage\n");
    expect(askAppBase(root)).toBe("http://127.0.0.1:4977");
  });

  it("keeps ':' and '@' readable and the router opens exactly that seat and full id", () => {
    for (const [seat, id] of [
      ["domain:stats", "20261030-130014-where-the-fit-check-sits"],
      ["manager:domain", "opforks-1029"],
      ["app:writer@2", "v1.2_x"],
    ]) {
      const u = new URL(askUrl(root, seat, id));
      expect(u.pathname).toBe(`/a/${seat}/${id}`);
      expect(parseRoute(u.pathname, u.search, u.hash).ask).toBe(`${seat}/${id}`);
    }
  });
});

describe("cli", () => {
  it("new prints the path, then the app URL on its own line", () => {
    const r = cli(["new", "--id", "n1"], BODY);
    expect(r.status).toBe(0);
    const lines = r.stdout.trim().split("\n");
    expect(lines[0]).toBe(path.join(root, "domain:stats", "n1.md"));
    expect(lines[1]).toBe("http://127.0.0.1:4977/a/domain:stats/n1");
  });

  it("url <seat>/<id> prints the URL of an existing ask, and refuses an unknown one", () => {
    cli(["new", "--id", "u1"], BODY);
    fs.writeFileSync(path.join(root, ".ask-app.pid"), "1 4988\n");
    const r = cli(["url", "domain:stats/u1"]);
    expect(r.status).toBe(0);
    expect(r.stdout.trim()).toBe("http://127.0.0.1:4988/a/domain:stats/u1");
    const miss = cli(["url", "domain:stats/nope"]);
    expect(miss.status).toBe(1);
    expect(miss.stderr).toMatch(/no ask domain:stats\/nope/);
  });

  it("list --url adds the URL as the last column", () => {
    cli(["new", "--id", "l1"], BODY);
    const plain = cli(["list"]).stdout.trim();
    expect(plain).not.toContain("http://");
    const withUrl = cli(["list", "--url"]).stdout.trim();
    expect(withUrl.split("\t").at(-1)).toBe("http://127.0.0.1:4977/a/domain:stats/l1");
    const json = JSON.parse(cli(["list", "--json"]).stdout);
    expect(json[0].url).toBe("http://127.0.0.1:4977/a/domain:stats/l1");
  });
});
