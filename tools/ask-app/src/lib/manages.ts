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
 * - The tree is read: the live edge alone decides. The caller is the tree row whose pane id is
 *   TMUX_PANE (never FLEET_PANE); with no such row, or one naming a different seat from the identity
 *   the command acts as, nothing is granted. The seat's parent must be the caller. A seat absent from
 *   the tree, or named by more than one row, has no live manager. Seats match case-folded (`seatEq`).
 *   A disagreement with FLEET_MANAGES is warned about.
 * - The tree is unreadable (no TMUX_PANE, tmux failed or returned nothing): FLEET_MANAGES decides,
 *   with a warning. An unset or empty FLEET_MANAGES grants nothing, so with neither source it refuses.
 * - The ASK_LIVE_PANES seam is set but unreadable or empty: refused, as hop.sh's live_tree exits 4.
 *   Whenever the seam is used a stderr line says so, so a value leaked from a test shell is visible.
 * - rename-seat after the tmux rename (`renamed`): `old` is gone from a read tree, so its own edge is
 *   unreadable. The caller is accepted only when BOTH hold: `neu`'s live parent is the caller, and the
 *   caller's launch-time FLEET_MANAGES named `old` — the stale list is evidence of the old edge, the
 *   live tree of the new one (meta:engine's ruling, MANAGES fix round).
 */
import fs from "node:fs";
import { execFileSync } from "node:child_process";
import { seatEq } from "./format.ts";

/** The manager check the CLI hands the store; `renamed` answers rename-seat's old→new case. */
export type ManagerCheck = ((seat: string) => boolean) & { renamed?: (old: string, neu: string) => boolean };

/** A seat's standing as a manager: a FLEET_MANAGES-shaped label list, or a check that reads the live tree. */
export type Manages = string[] | ManagerCheck;

/**
 * Round 3 (MUST-1): a FLEET_MANAGES entry names `seat` when it is the seat itself, or the seat's
 * label (the part after its window, `window:label`): `kernel` names `idealic:kernel`.
 */
export function listNames(list: string[], seat: string): boolean {
  return list.some((m) => !!m && (m === seat || seat.endsWith(`:${m}`)));
}

/** One live-tree row: `[seat, pane, parent]`, parent `-` for none. */
export type LiveRow = [seat: string, pane: string, parent: string];

/** The live tree: read, unreadable (the FLEET_MANAGES fallback applies), or refused (nothing is granted). */
export type LiveTree = { state: "read"; rows: LiveRow[] } | { state: "unreadable"; why: string } | { state: "refused"; why: string };

const rowsOf = (text: string): LiveRow[] =>
  text
    .split("\n")
    .map((l) => l.trim().split(/\s+/))
    .filter((r) => !!r[0])
    .map(([s, p, parent]) => [s, p ?? "", parent ?? "-"] as LiveRow);

/**
 * The live tree, read the way hop.sh's live_tree reads it: the ASK_LIVE_PANES seam (a file of
 * `seat pane_id parent` lines), else `tmux list-panes -a` (ASK_TMUX_SOCKET a `-L` socket). Only when
 * this shell is in tmux (TMUX_PANE), as for liveIdentity.
 */
export function readLiveTree(env: NodeJS.ProcessEnv = process.env, note: (m: string) => void = (m) => process.stderr.write(`${m}\n`)): LiveTree {
  if (!env.TMUX_PANE) return { state: "unreadable", why: "this shell is not in tmux (no TMUX_PANE)" };
  if (env.ASK_LIVE_PANES) {
    note(`ask: reading the live tree from ASK_LIVE_PANES=${env.ASK_LIVE_PANES}, not tmux`);
    let text: string;
    try {
      text = fs.readFileSync(env.ASK_LIVE_PANES, "utf8");
    } catch {
      return { state: "refused", why: `ASK_LIVE_PANES=${env.ASK_LIVE_PANES} is not readable` };
    }
    const rows = rowsOf(text);
    return rows.length ? { state: "read", rows } : { state: "refused", why: `ASK_LIVE_PANES=${env.ASK_LIVE_PANES} names no pane` };
  }
  try {
    const text = execFileSync("tmux", [...(env.ASK_TMUX_SOCKET ? ["-L", env.ASK_TMUX_SOCKET] : []), "list-panes", "-a", "-F", "#{window_name}:#{@pane_label} #{pane_id} #{?@pane_parent,#{@pane_parent},-}"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 2000 });
    const rows = rowsOf(text);
    return rows.length ? { state: "read", rows } : { state: "unreadable", why: "tmux returned no panes" };
  } catch {
    return { state: "unreadable", why: "tmux list-panes failed" };
  }
}

/** A seat name a pane can carry: `window:label`, both halves non-empty. */
const isSeatName = (s: string) => /^[^:\s]+:[^:\s]+$/.test(s) && s !== "operator";

/** What the live tree says about one seat. */
export type LiveEdge =
  | { readable: false }
  | { readable: true; present: false }
  | { readable: true; present: "ambiguous"; count: number }
  | { readable: true; present: true; parent: string };

/** The seat's edge, matched case-folded; more than one matching row is ambiguous. */
export function edgeOf(tree: LiveTree | LiveRow[] | undefined, seat: string): LiveEdge {
  const rows = Array.isArray(tree) ? tree : tree?.state === "read" ? tree.rows : undefined;
  if (!rows) return { readable: false };
  const hits = rows.filter(([s]) => seatEq(s, seat));
  if (hits.length === 0) return { readable: true, present: false };
  if (hits.length > 1) return { readable: true, present: "ambiguous", count: hits.length };
  return { readable: true, present: true, parent: hits[0][2] === "-" ? "" : hits[0][2] };
}

/** A seat's live parent ("" when none, absent, ambiguous or unreadable) — the pass-up's read. */
export function parentIn(tree: LiveTree, seat: string): string {
  const e = edgeOf(tree, seat);
  return e.readable && e.present === true ? e.parent : "";
}

/** The seat the pane `tmuxPane` carries in a read tree, or why it vouches for nobody. */
function selfIn(rows: LiveRow[], tmuxPane: string): { seat: string } | { why: string } {
  const mine = rows.filter(([, p]) => !!tmuxPane && p === tmuxPane);
  if (mine.length !== 1) return { why: `this pane (${tmuxPane || "no TMUX_PANE"}) ${mine.length ? "has more than one row" : "is not in the live tree"}` };
  if (!isSeatName(mine[0][0])) return { why: `this pane (${tmuxPane}) carries no seat label` };
  return { seat: mine[0][0] };
}

/**
 * The manager check the CLI hands the store. `tmuxPane` is TMUX_PANE, which picks the caller's row;
 * `actingAs` is the identity the command acts as (liveIdentity's pane, which may be FLEET_PANE when
 * tmux could not be read); `env` its FLEET_MANAGES; `tree` the live tree, or a function that reads
 * it, called at most once and only when a seat is judged. Each seat is judged and warned about once.
 */
export function liveManages(o: { tmuxPane?: string; actingAs?: string; env: string[]; tree: LiveTree | (() => LiveTree); warn?: (m: string) => void }): ManagerCheck {
  const warn = o.warn ?? ((m: string) => process.stderr.write(`${m}\n`));
  const seen = new Map<string, boolean>();
  let cached: LiveTree | undefined;
  const tree = (): LiveTree => (cached ??= typeof o.tree === "function" ? o.tree() : o.tree);
  const warnedOnce = new Set<string>();
  const warn1 = (m: string) => {
    if (warnedOnce.has(m)) return;
    warnedOnce.add(m);
    warn(m);
  };

  /** The caller, vouched by the read tree; undefined (with a warning) when it vouches for nobody. */
  const vouched = (rows: LiveRow[]): string | undefined => {
    const s = selfIn(rows, o.tmuxPane ?? "");
    if ("why" in s) {
      warn1(`ask: ${s.why}, so the live tree vouches for no caller; no manager standing is granted (the operator acts with --by operator from a bare shell)`);
      return undefined;
    }
    if (o.actingAs && !seatEq(o.actingAs, s.seat)) {
      warn1(`ask: this pane is '${s.seat}' in the live tree but the command acts as '${o.actingAs}'; no manager standing is granted`);
      return undefined;
    }
    return s.seat;
  };

  const check = ((seat: string) => {
    if (!seat) return false;
    const hit = seen.get(seat);
    if (hit !== undefined) return hit;
    const listed = listNames(o.env, seat);
    const t = tree();
    let ok = false;
    if (t.state === "refused") {
      warn1(`ask: ${t.why}; no manager standing is granted (hop.sh refuses the same tree, exit 4)`);
    } else if (t.state === "unreadable") {
      ok = listed;
      warn(`ask: the live tree cannot be read (${t.why}); '${seat}' ${ok ? "taken as managed" : "not managed"} on FLEET_MANAGES alone, which is a launch-time cache`);
    } else {
      const self = vouched(t.rows);
      if (self) {
        const edge = edgeOf(t, seat);
        if (edge.readable && edge.present === "ambiguous") {
          warn(`ask: '${seat}' names ${edge.count} panes in the live tree; ambiguous, so it has no manager here`);
        } else {
          const parent = edge.readable && edge.present === true ? edge.parent : "";
          ok = !!parent && seatEq(parent, self);
          if (ok && !listed) {
            warn(`ask: FLEET_MANAGES does not list '${seat}', but its live @pane_parent is '${self}'; using the live edge (FLEET_MANAGES is a launch-time cache)`);
          } else if (!ok && listed) {
            const live = edge.readable && edge.present === true ? `its live @pane_parent is '${parent || "none (operator)"}'` : `'${seat}' is not in the live tree`;
            warn(`ask: FLEET_MANAGES lists '${seat}', but ${live}; not honoured — the live edge decides (FLEET_MANAGES is a launch-time cache)`);
          }
        }
      }
    }
    seen.set(seat, ok);
    return ok;
  }) as ManagerCheck;

  check.renamed = (old: string, neu: string) => {
    const t = tree();
    if (t.state !== "read") return check(old);
    const oldEdge = edgeOf(t, old);
    if (!(oldEdge.readable && oldEdge.present === false)) return check(old);
    const self = vouched(t.rows);
    if (!self) return false;
    const neuEdge = edgeOf(t, neu);
    const neuMine = neuEdge.readable && neuEdge.present === true && !!neuEdge.parent && seatEq(neuEdge.parent, self);
    const oldListed = listNames(o.env, old);
    if (neuMine && oldListed) {
      warn(`ask: '${old}' is gone from the live tree; '${neu}' is under '${self}' live and FLEET_MANAGES (launch-time) named '${old}', so '${self}' renames it`);
      return true;
    }
    const why = !neuMine
      ? `'${neu}' is not under '${self}' in the live tree`
      : `'${self}''s FLEET_MANAGES never named '${old}', so nothing shows '${old}' was its seat`;
    warn(`ask: '${old}' is gone from the live tree and ${why}; the operator can rename it (--by operator from a bare shell)`);
    return false;
  };
  return check;
}
