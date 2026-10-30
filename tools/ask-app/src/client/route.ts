/**
 * The URL is the app's state: a reload, or the same link opened elsewhere, shows the same screen.
 *
 *   /a/<seat>/<id>            an ask            /proofs, /proofs/<key>        the proof list, one proof
 *   /broadcasts, /broadcasts/<id>               ?filter=ruled|settled|all  ?group=seat|topic
 *   ?drafts=1                 the drafts tray shown (an old ?filter=drafts link lands here, on Open)
 *   ?ask=<seat>/<id>          the ask kept open beside the Proofs or Broadcasts list
 *   ?pane=off | ?pane=<url>   the split pane closed, or showing that page (absent: the default)
 *   ?q=<text>                 the sidebar search (IDE-304); typing replaces the entry, never pushes
 *                             (debounced ~300ms). Typing after opening an ask rewrites that ask's
 *                             entry, so Back lands on the entry before it, with its earlier q.
 *   #F2, #Q1                  the fork in view
 *
 * Personal layout (sidebar width, split ratio, theme) stays in localStorage, and unsent picks stay
 * in the saved draft; neither is in the URL.
 */
export type Section = "asks" | "proofs" | "broadcasts";
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
  else path = r.broadcast ? `/broadcasts/${seg(r.broadcast)}` : "/broadcasts";
  const q = new URLSearchParams();
  if (r.section !== "asks" && r.ask) q.set("ask", r.ask);
  if (r.filter !== "open") q.set("filter", r.filter);
  if (r.group !== "none") q.set("group", r.group);
  if (r.pane) q.set("pane", r.pane);
  if (r.drafts) q.set("drafts", "1");
  if (r.q) q.set("q", r.q);
  const qs = q.toString().replace(/%2F/gi, "/").replace(/%3A/gi, ":");
  return `${path}${qs ? `?${qs}` : ""}${r.fork ? `#${seg(r.fork)}` : ""}`;
}

/** Changes the operator expects Back to undo: another section, ask, proof or broadcast. */
export function isNavigation(from: Route, to: Route): boolean {
  return from.section !== to.section || from.ask !== to.ask || from.proof !== to.proof || from.broadcast !== to.broadcast;
}
