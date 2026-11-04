/**
 * "Is this caller a manager of that seat?" — answered from the LIVE tmux edge first.
 *
 * FLEET_MANAGES is exported by run.sh at launch, so it is a cache: a seat renamed since then
 * (core:exchange → core:database) is missing from it, and a seat moved to another manager is still
 * listed in it. The live edge is the asked-about seat's `@pane_parent`, the same read hop.sh's
 * `target --of <seat>` makes (`list-panes -a -F '#{window_name}:#{@pane_label} #{pane_id}
 * #{?@pane_parent,#{@pane_parent},-}'`, or the ASK_LIVE_PANES seam in that shape).
 *
 * The rule:
 * - The caller is a seat and the tree can be read: the live edge alone decides. The seat's parent
 *   must be the caller. A seat absent from a readable tree has no live manager, so a list naming it
 *   grants nothing. A disagreement with FLEET_MANAGES is warned about.
 * - The tree cannot be read (no TMUX_PANE, tmux fails, the seam file is unreadable), or the caller
 *   has no seat identity the tree could vouch for: FLEET_MANAGES decides, with a warning when it
 *   grants. An unset or empty FLEET_MANAGES grants nothing, so with neither source the check refuses.
 */
import fs from "node:fs";
import { execFileSync } from "node:child_process";
import { seatEq } from "./format.ts";

/** A seat's standing as a manager: a FLEET_MANAGES-shaped label list, or a check that reads the live tree. */
export type Manages = string[] | ((seat: string) => boolean);

/**
 * Round 3 (MUST-1): a FLEET_MANAGES entry names `seat` when it is the seat itself, or the seat's
 * label (the part after its window, `window:label`): `kernel` names `idealic:kernel`.
 */
export function listNames(list: string[], seat: string): boolean {
  return list.some((m) => !!m && (m === seat || seat.endsWith(`:${m}`)));
}

/** The live tree as `[seat, pane, parent]` rows, or undefined when it cannot be read. */
export type LiveRow = [seat: string, pane: string, parent: string];

/**
 * The live tree, read the way hop.sh's live_tree reads it: the ASK_LIVE_PANES seam (a file of
 * `seat pane_id parent` lines), else `tmux list-panes -a` (ASK_TMUX_SOCKET a `-L` socket). Only when
 * this shell is in tmux (TMUX_PANE), as for liveIdentity. undefined = unreadable; an empty result
 * from tmux is unreadable too (hop.sh exit 4).
 */
export function readLiveTree(env: NodeJS.ProcessEnv = process.env): LiveRow[] | undefined {
  if (!env.TMUX_PANE) return undefined;
  try {
    const text = env.ASK_LIVE_PANES
      ? fs.readFileSync(env.ASK_LIVE_PANES, "utf8")
      : execFileSync("tmux", [...(env.ASK_TMUX_SOCKET ? ["-L", env.ASK_TMUX_SOCKET] : []), "list-panes", "-a", "-F", "#{window_name}:#{@pane_label} #{pane_id} #{?@pane_parent,#{@pane_parent},-}"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 2000 });
    const rows = text
      .split("\n")
      .map((l) => l.trim().split(/\s+/))
      .filter((r) => !!r[0])
      .map(([s, p, parent]) => [s, p ?? "", parent ?? "-"] as LiveRow);
    return rows.length ? rows : undefined;
  } catch {
    return undefined;
  }
}

/** What the live tree says about one seat: unreadable, absent, or present with its parent ("" = none). */
export type LiveEdge = { readable: false } | { readable: true; present: false } | { readable: true; present: true; parent: string };

export function edgeOf(tree: LiveRow[] | undefined, seat: string): LiveEdge {
  if (!tree) return { readable: false };
  const row = tree.find(([s]) => s === seat);
  if (!row) return { readable: true, present: false };
  return { readable: true, present: true, parent: row[2] === "-" ? "" : row[2] };
}

/**
 * The manager check the CLI hands the store: `self` is the caller's live seat ("" when it is not a
 * seat, e.g. a `--by` from a bare shell), `env` its FLEET_MANAGES, `tree` the live tree (undefined =
 * unreadable), or a function that reads it, called at most once and only when a seat is judged — so a
 * command that decides no standing never runs tmux. Each seat is judged and warned about once.
 */
export function liveManages(o: { self: string; env: string[]; tree: LiveRow[] | undefined | (() => LiveRow[] | undefined); warn?: (m: string) => void }): (seat: string) => boolean {
  const warn = o.warn ?? ((m: string) => process.stderr.write(`${m}\n`));
  const seen = new Map<string, boolean>();
  let read = false;
  let rows: LiveRow[] | undefined;
  const tree = () => {
    if (!read) {
      rows = typeof o.tree === "function" ? o.tree() : o.tree;
      read = true;
    }
    return rows;
  };
  return (seat: string) => {
    if (!seat) return false;
    const hit = seen.get(seat);
    if (hit !== undefined) return hit;
    const listed = listNames(o.env, seat);
    const edge = edgeOf(tree(), seat);
    let ok: boolean;
    if (o.self && edge.readable) {
      const parent = edge.present ? edge.parent : "";
      ok = edge.present && !!parent && seatEq(parent, o.self);
      if (ok && !listed) {
        warn(`ask: FLEET_MANAGES does not list '${seat}', but its live @pane_parent is '${o.self}'; using the live edge (FLEET_MANAGES is a launch-time cache)`);
      } else if (!ok && listed) {
        const live = !edge.present ? `'${seat}' is not in the live tree` : `its live @pane_parent is '${parent || "none (operator)"}'`;
        warn(`ask: FLEET_MANAGES lists '${seat}', but ${live}; not honoured — the live edge decides (FLEET_MANAGES is a launch-time cache)`);
      }
    } else {
      ok = listed;
      if (ok || o.self) {
        const why = o.self ? "the live tree cannot be read" : "this caller is not a seat the live tree can vouch for";
        warn(`ask: ${why}; '${seat}' ${ok ? "taken as managed" : "not managed"} on FLEET_MANAGES alone, which is a launch-time cache`);
      }
    }
    seen.set(seat, ok);
    return ok;
  };
}
