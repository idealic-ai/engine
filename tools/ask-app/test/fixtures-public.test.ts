/**
 * ASKTREEUI S4: the engine's origin is public, so no fixture under test/fixtures may carry the
 * operator's home path or username, the team's tracker URLs, a process id, or the team name. The
 * scan is checked against a planted sample first, so an empty result means clean, not blind.
 */
import { describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";

const ROOT = path.join(import.meta.dirname, "fixtures");
const RULES: [string, RegExp][] = [
  ["home path", /\/Users\//],
  ["username", /invizko/i],
  ["team name", /idealic/i],
  ["tracker URL", /linear\.app\/(?!example\/)/],
  ["process id", /\bpid \d+/],
];
function leaks(text: string): string[] {
  return text.split("\n").flatMap((l, i) => RULES.filter(([, re]) => re.test(l)).map(([n]) => `${i + 1}: ${n}`));
}
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
});
