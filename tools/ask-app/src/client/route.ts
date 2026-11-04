import type { CommsRow, Tier } from "../lib/comms.ts";

/**
 * The URL is the app's state: a reload, or the same link opened elsewhere, shows the same screen.
 *
 *   /a/<seat>/<id>            an ask            /proofs, /proofs/<key>        the proof list, one proof
 *   /broadcasts, /broadcasts/<id>               ?filter=ruled|settled|all  ?group=seat|topic
 *   ?drafts=1                 the drafts tray shown (an old ?filter=drafts link lands here, on Open)
 *   /comms, /comms/<id>       the Comms feed (COMMSUI), one message picked; ?seat=<seat> and
 *                             ?tier=<t[,t]> and ?kind=<tell|broadcast|ask[,…]> filter it and are kept
 *                             only in the Comms section's URL
 *   ?ask=<seat>/<id>          the ask kept open beside the Proofs, Broadcasts or Comms list
 *   ?pane=off | ?pane=<url>   the split pane closed, or showing that page (absent: the default)
 *   ?q=<text>                 the sidebar search (IDE-304); typing replaces the entry, never pushes
 *                             (debounced ~300ms). Typing after opening an ask rewrites that ask's
 *                             entry, so Back lands on the entry before it, with its earlier q.
 *   #F2, #Q1                  the fork in view
 *
 * Personal layout (sidebar width, split ratio, theme) stays in localStorage, and unsent picks stay
 * in the saved draft; neither is in the URL.
 */
export type Section = "asks" | "proofs" | "broadcasts" | "comms";
/** The tiers a tell rides (src/lib/comms.ts, Tier), in the order the filter offers them. */
export const COMMS_TIERS: Tier[] = ["note", "lazy", "align", "escalate", "wake"];
export type CommsKind = CommsRow["kind"];
/** The kinds of message the feed carries (src/lib/comms.ts, KINDS), in the order the filter offers them. */
export const COMMS_KINDS: CommsKind[] = ["tell", "broadcast", "ask"];
export type Filter = "open" | "ruled" | "settled" | "all";
export type Group = "none" | "seat" | "topic";
export type Route = {
  section: Section;
  /** seat/id of the ask in the main area. */
  ask?: string;
  /** A proof's store key (/proofs/<key>). */
  proof?: string;
  /** A broadcast id (/broadcasts/<id>). */
  broadcast?: string;
  /** A Comms row's id (/comms/<id>); an ask's carries a slash. */
  comm?: string;
  /** The Comms seat filter (?seat=): from, sent by, to or meant for. */
  seat?: string;
  /** The Comms tier filter (?tier=a,b); absent means every tier. */
  tier?: Tier[];
  /** The Comms kind filter (?kind=a,b); absent means every kind. */
  kind?: CommsKind[];
  filter: Filter;
  group: Group;
  /** "off", a page URL, or undefined for the section's default. */
  pane?: string;
  fork?: string;
  /** The drafts tray asked for (it was the Drafts tab before "Ruled below you" took its place). */
  drafts?: true;
  /** The sidebar search text (?q=), kept as typed; absent when empty. */
  q?: string;
};

const FILTERS: Filter[] = ["open", "ruled", "settled", "all"];
const GROUPS: Group[] = ["none", "seat", "topic"];

const dec = (s: string) => {
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
};
/** Encode one path segment, keeping the characters seat names use (`:`) readable. */
const seg = (s: string) => encodeURIComponent(s).replace(/%3A/gi, ":").replace(/%40/g, "@");

export function parseRoute(pathname: string, search = "", hash = ""): Route {
  const q = new URLSearchParams(search);
  const filter = (FILTERS as string[]).includes(q.get("filter") ?? "") ? (q.get("filter") as Filter) : "open";
  const group = (GROUPS as string[]).includes(q.get("group") ?? "") ? (q.get("group") as Group) : "none";
  const pane = q.get("pane") ?? undefined;
  const query = q.get("q") || undefined;
  // The Drafts tab is gone: its old links open Open with the drafts tray shown.
  const drafts = q.get("filter") === "drafts" || q.get("drafts") === "1";
  const parts = pathname.split("/").filter(Boolean).map(dec);
  const h = dec(hash.replace(/^#/, ""));
  const base: Route = { section: "asks", filter, group, ...(pane ? { pane } : {}), ...(drafts ? { drafts: true as const } : {}), ...(query ? { q: query } : {}) };
  const withFork = (r: Route): Route => (h && !h.includes("/") ? { ...r, fork: h } : r);
  const askParam = q.get("ask") ?? undefined;
  if (parts[0] === "a" && parts.length >= 3) return withFork({ ...base, ask: `${parts[1]}/${parts.slice(2).join("/")}` });
  if (parts[0] === "proofs") return withFork({ ...base, section: "proofs", ...(parts.length > 1 ? { proof: parts.slice(1).join("/") } : {}), ...(askParam ? { ask: askParam } : {}) });
  if (parts[0] === "comms") {
    const seat = q.get("seat") || undefined;
    const tier = (q.get("tier") ?? "").split(",").filter((t): t is Tier => (COMMS_TIERS as string[]).includes(t));
    const kind = (q.get("kind") ?? "").split(",").filter((k): k is CommsKind => (COMMS_KINDS as string[]).includes(k));
    return withFork({ ...base, section: "comms", ...(parts.length > 1 ? { comm: parts.slice(1).join("/") } : {}), ...(seat ? { seat } : {}), ...(tier.length ? { tier } : {}), ...(kind.length ? { kind } : {}), ...(askParam ? { ask: askParam } : {}) });
  }
  if (parts[0] === "broadcasts") return withFork({ ...base, section: "broadcasts", ...(parts[1] ? { broadcast: parts.slice(1).join("/") } : {}), ...(askParam ? { ask: askParam } : {}) });
  // The round-1/2 fragment links (#seat/id and #seat/id/F2) still open their ask.
  if (h.includes("/")) {
    const hp = h.split("/");
    return { ...base, ask: `${hp[0]}/${hp[1]}`, ...(hp[2] ? { fork: hp.slice(2).join("/") } : {}) };
  }
  return withFork(base);
}

export function serializeRoute(r: Route): string {
  let path = "/";
  if (r.section === "asks") path = r.ask ? `/a/${r.ask.split("/").map(seg).join("/")}` : "/";
  else if (r.section === "proofs") path = r.proof ? `/proofs/${r.proof.split("/").map(seg).join("/")}` : "/proofs";
  else if (r.section === "comms") path = r.comm ? `/comms/${r.comm.split("/").map(seg).join("/")}` : "/comms";
  else path = r.broadcast ? `/broadcasts/${seg(r.broadcast)}` : "/broadcasts";
  const q = new URLSearchParams();
  if (r.section !== "asks" && r.ask) q.set("ask", r.ask);
  if (r.filter !== "open") q.set("filter", r.filter);
  if (r.group !== "none") q.set("group", r.group);
  if (r.pane) q.set("pane", r.pane);
  if (r.drafts) q.set("drafts", "1");
  if (r.q) q.set("q", r.q);
  if (r.section === "comms" && r.seat) q.set("seat", r.seat);
  if (r.section === "comms" && r.tier?.length) q.set("tier", r.tier.join(","));
  if (r.section === "comms" && r.kind?.length) q.set("kind", r.kind.join(","));
  const qs = q.toString().replace(/%2F/gi, "/").replace(/%3A/gi, ":").replace(/%2C/gi, ",");
  return `${path}${qs ? `?${qs}` : ""}${r.fork ? `#${seg(r.fork)}` : ""}`;
}

/**
 * COMMSUI S-1: the Comms row and its seat, tier and kind filters belong to the Comms section only. Every
 * route the navigator holds passes through here, so leaving Comms by any path (the tab, "Open the
 * ask", a search result) forgets them in memory as well as in the URL. A Comms route is returned as is.
 */
export function normalizeRoute(r: Route): Route {
  if (r.section === "comms") return r;
  if (!("comm" in r) && !("seat" in r) && !("tier" in r) && !("kind" in r)) return r;
  const { comm: _c, seat: _s, tier: _t, kind: _k, ...rest } = r;
  return rest;
}

/** What a view tab changes: the section, the ask kept beside it, and nothing picked; ?q= stays only on asks. */
export function viewPatch(v: Section, ask?: string): Partial<Route> {
  return { section: v, ask, proof: undefined, broadcast: undefined, comm: undefined, pane: undefined, fork: undefined, ...(v === "asks" ? {} : { q: undefined }) };
}

/** Changes the operator expects Back to undo: another section, ask, proof, broadcast or Comms row. A Comms filter is not one. */
export function isNavigation(from: Route, to: Route): boolean {
  return from.section !== to.section || from.ask !== to.ask || from.proof !== to.proof || from.broadcast !== to.broadcast || from.comm !== to.comm;
}
