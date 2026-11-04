/**
 * ASKTREEUI S4: the engine's origin is public, so no fixture under test/fixtures may carry the
 * operator's home path or username, the team's tracker URLs, a process id, or the team name. The
 * scan is checked against a planted sample first, so an empty result means clean, not blind.
 *
 * ASKLISTUI: the username and the home path are also looked for in every file under test/, not only
 * the fixtures, since a test's own inline fixture is just as public. This file is left out of that
 * scan: it holds the patterns and the planted sample.
 */
import { describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";

const TEST = import.meta.dirname;
const ROOT = path.join(TEST, "fixtures");
const SELF = path.join(TEST, "fixtures-public.test.ts");
const RULES: [string, RegExp][] = [
  ["home path", /\/Users\//],
  ["username", /invizko/i],
  ["team name", /idealic/i],
  ["tracker URL", /linear\.app\/(?!example\/)/],
  ["process id", /\bpid \d+/],
];
/** What every file under test/ is held to: the operator's username and home path. */
const WIDE = RULES.filter(([n]) => n === "username" || n === "home path");
function leaks(text: string, rules = RULES): string[] {
  return text.split("\n").flatMap((l, i) => rules.filter(([, re]) => re.test(l)).map(([n]) => `${i + 1}: ${n}`));
}
const everyFile = (d: string): string[] => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? everyFile(path.join(d, e.name)) : [path.join(d, e.name)]));
const files = (d: string): string[] => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? files(path.join(d, e.name)) : e.name.endsWith(".md") ? [path.join(d, e.name)] : []));

describe("S4: fixtures carry nothing private", () => {
  it("control: the scan flags each kind it looks for", () => {
    const planted = ["see /Users/someone/x", "by Invizko", "Idealic's board", "https://linear.app/acme/issue/A-1", "skipped (pid 2101)", "https://linear.app/example/issue/EX-1"].join("\n");
    expect(leaks(planted)).toEqual(["1: home path", "2: username", "3: team name", "4: tracker URL", "5: process id"]);
  });

  it("every fixture is clean", () => {
    const all = files(ROOT);
    expect(all.length).toBeGreaterThanOrEqual(10);
    const found = all.flatMap((f) => leaks(fs.readFileSync(f, "utf8")).map((l) => `${path.relative(ROOT, f)}:${l}`));
    expect(found).toEqual([]);
  });

  it("control: the wide scan flags the username and the home path, and only those", () => {
    expect(WIDE.map(([n]) => n)).toEqual(["home path", "username"]);
    const planted = ["see /Users/someone/x", "by Invizko", "Idealic's board"].join("\n");
    expect(leaks(planted, WIDE)).toEqual(["1: home path", "2: username"]);
  });

  it("every file under test/ carries neither the username nor the home path", () => {
    const all = everyFile(TEST).filter((f) => f !== SELF);
    expect(all.length).toBeGreaterThanOrEqual(60);
    expect(all).not.toContain(SELF);
    const found = all.flatMap((f) => leaks(fs.readFileSync(f, "utf8"), WIDE).map((l) => `${path.relative(TEST, f)}:${l}`));
    expect(found).toEqual([]);
  });
});
