/* proof-ticket.js — framework-free, CSP-safe REFERENCE kit (inline-embed this whole file).
 *
 * Co-delivery note (READ THIS): this is a SEPARATE file from board-widgets.js on purpose.
 * board-widgets.js is a "cannot-drift" surface whose integrity pass BYTE-COMPARES the embedded
 * copy against source; co-tenanting a tooltip here would churn that checksum on every tweak.
 * The publish step co-inlines BOTH files onto one page (two independent integrity checks).
 * This file is PRESENTATION-ONLY: it emits no payload, never reads/writes data-fb-*, never calls
 * buildPayload(), and lives in a disjoint namespace (<prove-ticket>, <prove-ref>,
 * <prove-ticket-card>, #prove-tickets, window.ProveTicket). It READS data-fb-item to resolve
 * in-page references, which is a read of the board's public addressing, not of its payload.
 *
 * LIGHT-DOM by design (no Shadow DOM): the /prove page is single-author + CSP-locked, so there is
 * no foreign CSS to defend against — light DOM is what lets these components SHARE the page's WARM
 * PRINT design tokens (proof-theme.css custom properties) and classes. This file is BEHAVIOR-ONLY:
 * it ships NO CSS and injects NO <style>. All component styling lives in proof-ticket.css — a real
 * linkable asset the page must provide (the /prove compose step links or inlines it into the page
 * <head>; the standalone auto-scanner case likewise requires proof-ticket.css to be linked). Every
 * color there is `var(--…)` resolved from the page's proof-theme.css tokens — no hardcoded palette.
 *
 * TWO REFERENCE KINDS, ONE MACHINE. A proof page carries two kinds of reference and this file
 * resolves both through one TreeWalker pass, one affordance vocabulary and one anchored popover:
 *
 *   1. TICKET refs — `FIN-\d+`. Resolved against EXTERNAL metadata (title/status/activity) that a
 *      static page cannot look up itself, so it is baked at publish time. See "Metadata source".
 *   2. INTERNAL ITEM refs — `[3]`, `[f34c8270]`. Resolved against THE PAGE ITSELF: board items set
 *      `id` = `data-fb-item` (so `<board-url>#<id>` addresses a decision) and carry a visible
 *      ordinal. Nothing is fetched, nothing is baked — the answer is already in the DOM.
 *
 * What a resolved reference gets:
 *   TICKET: a leading FRESHNESS DOT (activity recency, bucketed <24h / ≤7d / ≤30d / >30d /
 *       unknown) carrying a NON-COLOR fill-fraction channel (full / ¾ / ½ / ¼ / ring) so greyscale
 *       and colorblind readers can still read it; a hover/focus TEASER (title · dated status · last
 *       activity); and a click/Enter/Space-activated ANCHORED CARD — tabbed Overview / Activity /
 *       Relations, positioned against the ref (flip above / clamp into viewport), full dialog a11y.
 *   INTERNAL: a leading § MARK BUTTON that opens the SAME anchored card in item mode (title, state,
 *       channel, "Go to decision ↓"), a hover/focus teaser, and a link whose click/Enter jumps to
 *       the item via scrollIntoView + focus + a flash attribute. An UNRESOLVED token is left as
 *       plain text — `[0-9]` in prose is a regex, not a decision.
 * Entry points:
 *   1. <prove-ticket key="FIN-3519">FIN-3519</prove-ticket>  — explicit ticket element.
 *   2. <prove-ref item="f34c8270">[3]</prove-ref>            — explicit internal-item element.
 *   3. Auto-scanner (default ON): wraps bare FIN-\d+ and resolvable [token]s, skipping <a>/<code>/
 *      <pre>/etc.
 *
 * SVG / mermaid support: the scanner also reaches bare keys inside inline SVG <text> (e.g. mermaid
 * node labels rendered with htmlLabels:false). Those branch BY NAMESPACE to an SVG-native affordance
 * — an SVG <a>+<tspan> link (createElementNS) plus a sibling <circle> freshness dot — wired to open
 * the SAME shared <prove-ticket-card> (the card anchors to any element with getBoundingClientRect,
 * SVG included). Only the inline affordance is namespace-specific; card / metadata / freshness /
 * placement are reused verbatim. (A plain HTML <prove-ticket> replaceChild'd into SVG <text> renders
 * NOTHING — silently eating the key; branching here closes that latent bug.) Scope: single-line SVG
 * <text> (mermaid's common case) is fully supported; multi-line / <tspan>-split / transform'd SVG
 * text gets best-effort dot placement only (no per-line correction). mermaid foreignObject / HTML
 * labels live in the HTML namespace and already work through the HTML path unchanged.
 *
 * ── TICKET METADATA SOURCE (v4: FETCHED sibling JSON, with the inline blob as fallback) ──────────
 * Resolution order, first hit wins:
 *   A. INLINE  <script id="prove-tickets" type="application/json"> … <\/script>
 *      Used verbatim, synchronously, with NO network call. This is the offline-honest path: a page
 *      saved to disk, mailed as an attachment, or opened over file:// still shows real statuses.
 *   B. FETCHED sibling JSON, same shape, at a URL resolved from (in order)
 *         <link rel="prove-tickets" href="https://…/<page-stem>.tickets.json">
 *         <meta name="prove-tickets" content="…">
 *         convention: the page's own http(s) URL with .html → .tickets.json
 *      Same bucket as the page ⇒ SAME-ORIGIN for the canonical copy: no credential, no preflight.
 *      A copy attached elsewhere (e.g. to a tracker issue) is served from a FOREIGN host, which
 *      makes this fetch CROSS-ORIGIN — it needs a CORS policy on the bucket (see KIT_README /
 *      the publish runbook). Which is exactly why failure here is LOUD, not silent (below).
 *   C. Neither ⇒ every reference degrades to a working link with an `unknown` dot.
 * The fetch is only ever attempted when the page actually holds ticket references, is `credentials:
 * "omit"` (so the bucket may answer `Access-Control-Allow-Origin: *`), and NEVER blocks first paint:
 * the scanner renders the degraded affordance immediately and re-paints when data lands.
 *
 *   { "bakedAt": "2026-07-31T12:00:00Z",
 *     "tickets": {
 *       "FIN-3519": {
 *         "title": "…", "status": "In Progress", "statusType": "started",
 *         "priority": "Medium", "assignee": "…", "project": "…",
 *         "url": "https://linear.app/finchclaims/issue/FIN-3519",
 *         "updatedAt": "2026-07-30T18:24:00Z",
 *         "lastActivityAt": "2026-07-30T18:24:00Z",   // drives freshness; falls back to updatedAt
 *         "description": "…trimmed snippet…",
 *         "relations": [ { "key": "FIN-3518", "type": "related", "title": "…" } ],
 *         "activity": [ { "author": "…", "ts": "2026-07-30T18:24:00Z", "kind": "comment"|"state", "text": "…" } ]
 *       } } }
 * BAKE CONTRACT (agent-side, publish-time — reuse §CMD_READ_RELATED_TICKET, never a browser call to
 * the tracker): per distinct FIN key on the page: get_issue + list_comments → normalize to the entry
 * above. lastActivityAt = max(updatedAt, newest comment ts). activity = LAST 5 events only (comments
 * + stateHistory transitions), each text TRIMMED. Every baked string is rendered via textContent.
 *
 * DATED FACTS STAY DATED. `bakedAt` is the freshness of the DATA, not of the page, and a shared JSON
 * can be re-baked after the page ships. So the timestamp shown always comes from the RESOLVED source
 * — the fetched JSON's own bakedAt when fetched, the inline blob's when inline — and it is labelled
 * "ticket data as of …", never "as of …". The page's own publish date is a different fact.
 *
 * FAILURE IS LOUD, NEVER SILENT. A 404, a CORS block, or unparseable JSON must not look like
 * "these tickets simply have no data". On failure the component:
 *   · stamps `data-prove-tickets="error"` on <html> (CSS can react page-wide),
 *   · marks every ref `data-pt-source="unavailable"` and labels its dot "ticket data unavailable —
 *     link only" instead of the innocuous "activity date unknown",
 *   · fills every `[data-prove-tickets-status]` host on the page with a plain-English sentence
 *     naming the URL and the reason — this is how the PAGE gets to say why,
 *   · renders that same sentence as a banner inside every card, with a Retry control.
 * `window.ProveTicket.dataState()` exposes the whole thing for a page that wants its own treatment.
 *
 * STATIC FALLBACK DOT CONTRACT (zero-JS reader path, hand-authored in the block catalog): a static
 * freshness dot rendered WITHOUT this component MUST carry the same non-color channel to stay legible
 * in greyscale — a `data-fill` of full/three-quarter/half/quarter/ring mapped fresh→stale (or the
 * equivalent shape), PLUS `role="img"` and a bucket-word `aria-label` (e.g. "active in the last 7
 * days"). Reuse the `.pt-dot` class + proof-ticket.css so the static and JS dots render identically.
 *
 * Per-tracker knob: TRACKER_ISSUE_BASE below is the ONE thing to change for a different tracker.
 */
(function () {
  "use strict";

  // v4: ticket metadata moved from an inline-only blob to a FETCHED sibling tickets.json (inline
  // kept as the offline fallback), and a second reference kind — internal item refs — joined the
  // same scanner. publish-kit.sh greps this to name the published key (proof-ticket.v<N>.js).
  var PROOF_TICKET_VERSION = 4;

  // The one per-tracker constant — mirrors the project `## Tracker` Issue-URL convention.
  var TRACKER_ISSUE_BASE = "https://linear.app/finchclaims/issue/";

  var KEY_RE = /^FIN-\d+$/;          // exact key validation
  var SCAN_TEST_RE = /\bFIN-\d+\b/;  // non-global: cheap "does this text hold a key?" probe
  // Internal item reference: a bracketed token. Deliberately permissive on shape and STRICT on
  // resolution — an unresolvable token is left as plain text, so `[0-9]` in prose stays a regex.
  var ITEM_TOKEN_RE = /\[([A-Za-z0-9][A-Za-z0-9_.\-]{0,39})\]/;
  var ITEM_SCAN_TEST_RE = new RegExp(ITEM_TOKEN_RE.source);
  // Text nodes under any of these ancestors are left alone (real code/logs, already-linked keys,
  // editable fields, and our own elements to keep the scan idempotent).
  var SKIP_TAGS = {
    A: 1, CODE: 1, PRE: 1, SCRIPT: 1, STYLE: 1, TEXTAREA: 1, INPUT: 1,
    "PROVE-TICKET": 1, "PROVE-REF": 1, "PROVE-TICKET-CARD": 1
  };
  var OPT_OUT_ATTR = "data-no-prove-ticketify";
  var CARD_TAG = "prove-ticket-card";
  // Selectors that make an element an addressable in-page ITEM. data-fb-item is the board's own
  // addressing (id === data-fb-item, so <url>#<id> works); the others let a non-board proof page
  // opt in without pretending to be a board.
  var ITEM_SEL = "[data-fb-item],[data-decision-item],[data-prove-item]";
  // Where an item's own DOM states its title / state / ordinal. First hit wins; a page can always
  // be explicit with data-ref-title / data-ref-state / data-ordinal.
  var ITEM_TITLE_SEL = ["[data-ref-title]", ".dectitle", ".mod-title", ".item-title", "h2", "h3", "h4"];
  var ITEM_STATE_SEL = ["[data-ref-state]", ".statechip", ".mod-state", ".item-state"];
  var ITEM_ORDINAL_SEL = ["[data-ordinal]", ".decno", ".itemno"];
  var ITEM_TEXT_CAP = 220;
  // The Linear status-type vocabulary the pill has a token for. An unknown/absent type falls back to
  // the base .pt-pill (var(--ink-soft)) — we never emit a meaningless pt-pill-<x> class.
  var STATUS_TYPES = {
    started: 1, completed: 1, canceled: 1, backlog: 1, unstarted: 1, triage: 1
  };
  var ACTIVITY_CAP = 5; // render at most the last-5 events (bake caps it too; belt + suspenders)

  // Sibling-JSON conventions. The suffix is what publish-s3.sh uploads beside the page.
  var TICKETS_SUFFIX = ".tickets.json";
  var TICKETS_LINK_REL = "prove-tickets";
  var STATE_ATTR = "data-prove-tickets";
  var STATE_BAKED_ATTR = "data-prove-tickets-baked-at";
  var STATUS_HOST_SEL = "[data-prove-tickets-status]";

  // In light DOM, element ids become GLOBAL (a shadow root's scope is gone). A monotonic per-instance
  // uid keeps every tip / card title / tab / panel id unique so N refs on one page never collide.
  var _uid = 0;

  // Freshness thresholds (activity recency, ref = bakedAt). Buckets: fresh <24h · recent ≤7d ·
  // moderate ≤30d · stale >30d · unknown (no date). Color is never the only channel: each carries
  // a title/aria-label, a data-fill fill-fraction (non-color), and the card renders a one-line legend.
  var FRESH_24H = 24 * 60 * 60 * 1000;
  var FRESH_7D = 7 * 24 * 60 * 60 * 1000;
  var FRESH_30D = 30 * 24 * 60 * 60 * 1000;
  var FRESHNESS_LABEL = {
    fresh: "active in the last 24h",
    recent: "active in the last 7 days",
    moderate: "no activity for over a week",
    stale: "no activity for over a month",
    unknown: "activity date unknown"
  };
  // The NON-COLOR channel: a fill-fraction ramp fresh→stale that survives greyscale/colorblindness.
  // Rendered as a conic pie (HTML .pt-dot) and a size ramp (SVG <circle>); unknown = ring outline.
  var FILL_WORD = {
    fresh: "full", recent: "three-quarter", moderate: "half", stale: "quarter", unknown: "ring"
  };
  var SVG_DOT_R = { full: 5, "three-quarter": 4.3, half: 3.6, quarter: 2.8, ring: 5 };

  var _card = null; // the single shared <prove-ticket-card> instance, created lazily.

  // ── ticket-metadata state machine ────────────────────────────────────────────
  // One of: absent (nothing to load / nothing declared) · inline (blob on the page) ·
  // pending (fetch in flight) · fetched (loaded) · error (LOUD — attempted and failed).
  var _meta = null;          // { bakedAt, tickets } once resolved
  var _state = "absent";
  var _detail = "";          // human sentence fragment explaining a non-happy state
  var _sourceUrl = "";       // the URL we did/would fetch
  var _loadStarted = false;
  var _refreshers = [];      // painters to re-run when the data lands or fails
  var _ticketRefCount = 0;   // how many ticket refs the scan found — gates the fetch entirely

  function readInlineMeta() {
    var el = document.getElementById("prove-tickets");
    if (!el) return null;
    var raw;
    try {
      raw = JSON.parse(el.textContent || "{}");
    } catch (e) {
      // A blob that does not parse is a BAKE DEFECT, not an absence. Say so.
      _detail = "the inline #prove-tickets blob did not parse as JSON";
      return "broken";
    }
    if (!raw || typeof raw !== "object") {
      _detail = "the inline #prove-tickets blob is not an object";
      return "broken";
    }
    return {
      bakedAt: typeof raw.bakedAt === "string" ? raw.bakedAt : "",
      tickets: raw.tickets && typeof raw.tickets === "object" ? raw.tickets : {}
    };
  }

  function readMeta() {
    if (_meta) return _meta;
    return { absent: true, bakedAt: "", tickets: null };
  }

  function metaFor(key) {
    var m = readMeta();
    if (m.absent || !m.tickets) return null;
    var t = m.tickets[key];
    return t && typeof t === "object" ? t : null;
  }

  function bakedAt() {
    var m = readMeta();
    return (m && m.bakedAt) || "";
  }

  // Per-ref provenance, so a reader (and a test) can tell "no data for this key" apart from
  // "the data file never loaded" — the distinction the whole loud-failure design exists to make.
  function sourceForKey(key) {
    if (_state === "error") return "unavailable";
    if (_state === "pending") return "loading";
    if (_state === "absent") return "none";
    return metaFor(key) ? _state : "missing";
  }

  // The dot's accessible label. On a load failure it must NOT read "activity date unknown" — that
  // is the label for a ticket whose data we HAVE and which carries no date.
  function dotLabelFor(key, entry) {
    if (_state === "error") return "ticket data unavailable — link only";
    if (_state === "pending") return "loading ticket data…";
    return freshTitle(entry, bakedAt());
  }

  // Where the sibling JSON lives. Explicit declaration first (publish-s3.sh writes an ABSOLUTE URL,
  // which is what keeps an attached/rehosted copy pointing back at the bucket instead of at its new
  // host); then the same-directory convention. Convention is restricted to http(s): a file:// or
  // about:blank page has no meaningful sibling, and guessing one there buys a guaranteed failure.
  function resolveTicketsUrl() {
    var link = document.querySelector('link[rel~="' + TICKETS_LINK_REL + '"][href]');
    if (link) return link.href || link.getAttribute("href") || "";
    var meta = document.querySelector('meta[name="' + TICKETS_LINK_REL + '"][content]');
    if (meta) return meta.getAttribute("content") || "";
    var href = (typeof location !== "undefined" && location && location.href) ? location.href : "";
    if (!/^https?:/i.test(href)) return "";
    var base = href.split("#")[0].split("?")[0];
    if (/\.html?$/i.test(base)) return base.replace(/\.html?$/i, "") + TICKETS_SUFFIX;
    if (/\/$/.test(base)) return base + "tickets.json";
    return base + TICKETS_SUFFIX;
  }

  // credentials:"omit" is load-bearing, not hygiene: a cross-origin read of a public object must not
  // carry cookies, and a request that carries none lets the bucket answer with a wildcard
  // Access-Control-Allow-Origin (a credentialed request forbids `*` and would fail every attached
  // copy). Transport is feature-detected so a browser without fetch still resolves rather than
  // silently doing nothing.
  function fetchTickets(url, done) {
    var settled = false;
    var finish = function (text, err) { if (!settled) { settled = true; done(text, err); } };
    if (typeof fetch === "function") {
      try {
        fetch(url, { credentials: "omit", cache: "no-cache" }).then(function (res) {
          if (!res || !res.ok) { finish(null, "the server answered HTTP " + (res ? res.status : "?")); return null; }
          return res.text().then(function (t) { finish(t, ""); });
        })["catch"](function (e) {
          // A cross-origin block and a dead host are indistinguishable to script by design; name both.
          finish(null, "the request was blocked or the host is unreachable — most often a missing CORS policy on the bucket (" + ((e && e.message) || "network error") + ")");
        });
        return;
      } catch (e) { /* fall through to XHR */ }
    }
    if (typeof XMLHttpRequest === "function") {
      try {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        xhr.withCredentials = false;
        xhr.onload = function () {
          if (xhr.status >= 200 && xhr.status < 300) finish(xhr.responseText, "");
          else finish(null, "the server answered HTTP " + xhr.status);
        };
        xhr.onerror = function () {
          finish(null, "the request was blocked or the host is unreachable — most often a missing CORS policy on the bucket");
        };
        xhr.send();
        return;
      } catch (e2) { /* fall through */ }
    }
    finish(null, "this browser exposes no way to load it (no fetch, no XMLHttpRequest)");
  }

  function setState(state, detail, meta) {
    _state = state;
    _detail = detail || "";
    if (meta) _meta = meta;
    applyState();
    repaintAll();
  }

  // The plain-English sentence the page (and every card) shows. It names WHAT is dated and, on
  // failure, names the URL and the reason — the difference between "no data" and "data missing".
  function statusSentence() {
    var b = bakedAt();
    if (_state === "error") {
      // Short on purpose: a failure notice that takes six lines and the lowest-contrast ink on the
      // page inverts its own point. The URL and the reason stay — they are the actionable half.
      return "⚠ Ticket data unavailable — " + (_detail || "it could not be loaded") +
        ". Links still work; status and detail are MISSING, not empty.";
    }
    if (_state === "pending") return "Loading ticket data" + (_sourceUrl ? " from " + _sourceUrl : "") + "…";
    if (_state === "absent") return "No ticket data is attached to this page — ticket references are plain links.";
    if (_state === "inline") return "Ticket data is baked into this page" + (b ? " · as of " + b : "") + ".";
    return "Ticket data loaded" + (_sourceUrl ? " from " + _sourceUrl : "") + (b ? " · as of " + b : "") + ".";
  }

  function applyState() {
    var root = document.documentElement;
    if (root && root.setAttribute) {
      root.setAttribute(STATE_ATTR, _state);
      var b = bakedAt();
      if (b) root.setAttribute(STATE_BAKED_ATTR, b);
      else if (root.removeAttribute) root.removeAttribute(STATE_BAKED_ATTR);
    }
    var hosts = document.querySelectorAll(STATUS_HOST_SEL);
    for (var i = 0; i < hosts.length; i++) {
      hosts[i].textContent = statusSentence();     // textContent — the URL is inert text
      hosts[i].setAttribute("data-state", _state);
    }
  }

  function repaintAll() {
    for (var i = 0; i < _refreshers.length; i++) {
      try { _refreshers[i](); } catch (e) { /* one bad ref must not strand the rest */ }
    }
    if (_card && _card._built && !_card.hidden && _card._key) _card.render(_card._key);
  }

  function startMetaLoad() {
    if (_loadStarted) return;
    _loadStarted = true;
    var inline = readInlineMeta();
    if (inline === "broken") { setState("error", _detail, { bakedAt: "", tickets: {} }); return; }
    if (inline) { setState("inline", "", inline); return; }
    if (!_ticketRefCount) { setState("absent", "the page holds no ticket references", null); return; }
    var url = resolveTicketsUrl();
    if (!url) {
      setState("absent", "no ticket-data URL is declared and none can be derived from this page's address", null);
      return;
    }
    _sourceUrl = url;
    setState("pending", "", null);
    fetchTickets(url, function (text, err) {
      if (err) { setState("error", "could not load " + url + " — " + err, { bakedAt: "", tickets: {} }); return; }
      var doc;
      try { doc = JSON.parse(text); } catch (e) {
        setState("error", url + " did not parse as JSON", { bakedAt: "", tickets: {} }); return;
      }
      if (!doc || typeof doc !== "object" || Array.isArray(doc)) {
        setState("error", url + " is not a ticket-data object", { bakedAt: "", tickets: {} }); return;
      }
      var tickets = (doc.tickets && typeof doc.tickets === "object") ? doc.tickets : null;
      if (!tickets) { setState("error", url + " carries no `tickets` map", { bakedAt: "", tickets: {} }); return; }
      setState("fetched", "", {
        bakedAt: typeof doc.bakedAt === "string" ? doc.bakedAt : "",
        tickets: tickets
      });
    });
  }

  // Re-arm the load after a failure. Exposed on the card's banner so a reader who fixed their VPN /
  // the operator who just applied the CORS policy does not have to reload the page.
  function retryMetaLoad() {
    if (_state !== "error") return;
    _loadStarted = false;
    _meta = null;
    startMetaLoad();
  }

  function keyOf(host) {
    var k = host.getAttribute("key");
    if (k == null || k === "") k = (host.textContent || "").trim();
    else k = k.trim();
    return KEY_RE.test(k) ? k : null;
  }

  // A baked string in a link context needs scheme allow-listing, not just HTML-escaping. Accept only
  // the tracker permalink prefix or an http(s) URL; anything else (javascript:, data:, …) falls back
  // to the constructed, KEY_RE-validated permalink so a compromised bake can't emit a live script sink.
  function safeHref(url, key) {
    var fallback = TRACKER_ISSUE_BASE + key;
    if (typeof url !== "string" || !url) return fallback;
    if (url.indexOf(TRACKER_ISSUE_BASE) === 0) return url;
    return /^https?:\/\//i.test(url) ? url : fallback;
  }

  // ── freshness (pure) ─────────────────────────────────────────────────────────
  function lastActivityMs(entry) {
    if (!entry) return NaN;
    var d = entry.lastActivityAt || entry.updatedAt;
    if (typeof d !== "string" || !d) return NaN;
    var t = Date.parse(d);
    return isNaN(t) ? NaN : t;
  }
  // Missing/unparseable bakedAt → NaN, NOT Date.now(): freshness must degrade to "unknown" rather
  // than silently measure against the viewer's wall-clock (a confident-but-wrong bucket).
  function refMs(at) {
    var r = at ? Date.parse(at) : NaN;
    return isNaN(r) ? NaN : r;
  }
  // Bucket the gap between the baked reference time and the ticket's last activity. No date → unknown
  // (never claims a freshness it can't back). Activity "after" bake (clock skew) clamps to freshest.
  function freshnessOf(entry, at) {
    var last = lastActivityMs(entry);
    if (isNaN(last)) return "unknown";
    var ref = refMs(at);
    if (isNaN(ref)) return "unknown";
    var diff = ref - last;
    if (diff < 0) diff = 0;
    if (diff < FRESH_24H) return "fresh";
    if (diff <= FRESH_7D) return "recent";
    if (diff <= FRESH_30D) return "moderate";
    return "stale";
  }
  // Human "3h ago" for the teaser/header (never a hard claim — pairs with the dated "as of").
  function ageString(entry, at) {
    var last = lastActivityMs(entry);
    if (isNaN(last)) return "";
    var ref = refMs(at);
    if (isNaN(ref)) return "";
    var diff = ref - last;
    if (diff < 0) diff = 0;
    var mins = Math.round(diff / 60000);
    if (mins < 60) return mins <= 1 ? "just now" : mins + "m ago";
    var hrs = Math.round(mins / 60);
    if (hrs < 24) return hrs + "h ago";
    var days = Math.round(hrs / 24);
    if (days < 30) return days + "d ago";
    return Math.round(days / 30) + "mo ago";
  }
  function freshTitle(entry, at) {
    var b = freshnessOf(entry, at);
    var age = ageString(entry, at);
    return age ? "last activity " + age + " · " + FRESHNESS_LABEL[b] : FRESHNESS_LABEL[b];
  }

  // ── positioning (pure) ───────────────────────────────────────────────────────
  // Decide where the card sits relative to the ref, given the ref's rect, the viewport, and the
  // card's measured size. Default below; flip above when it would overflow the bottom AND there's
  // room above; clamp both axes into the viewport. Pure so it's unit-testable — jsdom never lays
  // out, so we prove placement here rather than against rendered coordinates.
  function choosePlacement(anchorRect, viewport, cardSize) {
    var margin = 8, gap = 6;
    var cw = (cardSize && cardSize.width) || 320;
    var ch = (cardSize && cardSize.height) || 240;
    var placement = "below";
    var top = anchorRect.bottom + gap;
    var overflowsBottom = top + ch > viewport.height - margin;
    var roomAbove = anchorRect.top - gap - ch >= margin;
    if (overflowsBottom && roomAbove) {
      placement = "above";
      top = anchorRect.top - gap - ch;
    }
    if (top + ch > viewport.height - margin) top = viewport.height - margin - ch;
    if (top < margin) top = margin;
    var left = anchorRect.left;
    if (left + cw > viewport.width - margin) left = viewport.width - margin - cw;
    if (left < margin) left = margin;
    return { top: top, left: left, placement: placement };
  }

  // Build an HTML freshness dot span carrying BOTH channels: color (via data-fill token rule) and the
  // non-color fill-fraction (data-fill word). `label` sets role=img + title/aria-label; a decorative
  // dot (adjacent text already states the fact) is aria-hidden instead.
  function makeDot(bucket, label, decorative) {
    var d = document.createElement("span");
    d.className = "pt-dot pt-dot-" + bucket;
    d.setAttribute("data-fill", FILL_WORD[bucket] || "ring");
    if (decorative) {
      d.setAttribute("aria-hidden", "true");
    } else {
      d.setAttribute("role", "img");
      if (label != null) { d.setAttribute("title", label); d.setAttribute("aria-label", label); }
    }
    return d;
  }

  // ── in-page item resolution (NO fetch — the answer is already in the DOM) ─────
  function isItem(n) {
    return !!(n && n.nodeType === 1 && n.matches && n.matches(ITEM_SEL));
  }
  // Memoized for the duration of one scan pass: resolving N bracket tokens would otherwise re-query
  // and re-read every item's ordinal N times, which on a 400-ref board is the difference between a
  // scan and a stall. Invalidated at each scan() so a page that adds items later still resolves.
  var _items = null;
  function itemList() {
    if (!_items) _items = Array.prototype.slice.call(document.querySelectorAll(ITEM_SEL));
    return _items;
  }
  function forgetItems() { _items = null; _ordinals = null; }
  function closestItem(n) {
    var p = n;
    while (p && p.nodeType === 1) { if (isItem(p)) return p; p = p.parentNode; }
    return null;
  }
  function trimText(s) {
    if (typeof s !== "string") return "";
    s = s.replace(/\s+/g, " ").trim();
    return s.length > ITEM_TEXT_CAP ? s.slice(0, ITEM_TEXT_CAP - 1) + "…" : s;
  }
  // Read a field off the item's OWN DOM, never a nested item's — a board section can contain
  // another addressable block, and inheriting its title would attribute the wrong decision.
  function fieldOf(item, selectors) {
    for (var i = 0; i < selectors.length; i++) {
      var found = item.querySelectorAll(selectors[i]);
      for (var j = 0; j < found.length; j++) {
        if (closestItem(found[j]) !== item) continue;
        var attr = found[j].getAttribute && found[j].getAttribute("data-ordinal");
        var t = trimText(attr != null && attr !== "" ? attr : found[j].textContent);
        if (t) return t;
      }
    }
    return "";
  }
  var _ordinals = null;
  function ordinalOf(item) {
    if (!_ordinals) _ordinals = (typeof Map === "function") ? new Map() : null;
    if (_ordinals && _ordinals.has(item)) return _ordinals.get(item);
    var v = fieldOf(item, ITEM_ORDINAL_SEL);
    if (_ordinals) _ordinals.set(item, v);
    return v;
  }

  function itemMeta(item) {
    return {
      id: (item.getAttribute("data-fb-item") || item.id || ""),
      ordinal: ordinalOf(item),
      title: fieldOf(item, ITEM_TITLE_SEL),
      state: fieldOf(item, ITEM_STATE_SEL),
      kind: trimText(item.getAttribute("data-fb-kind") || ""),
      channel: trimText(item.getAttribute("data-fb-channel") || "")
    };
  }

  // Resolve `[token]` against the page. Ordinal-first when the page shows ordinals at all, because
  // that is what prose means by "decision [5]"; id second. Falls back to document position ONLY on
  // a page that exposes no ordinals anywhere — otherwise a page with ordinals 1,2,4 would answer
  // "[3]" with its third section, confidently and wrongly.
  function resolveItem(token) {
    if (!token) return null;
    var items = itemList();
    if (!items.length) return null;
    var i;
    if (/^\d{1,3}$/.test(token)) {
      var anyOrdinal = false;
      for (i = 0; i < items.length; i++) {
        var o = ordinalOf(items[i]);
        if (o) anyOrdinal = true;
        if (o && o.replace(/^0+(?=\d)/, "") === token.replace(/^0+(?=\d)/, "")) return items[i];
      }
      if (!anyOrdinal) {
        var idx = parseInt(token, 10) - 1;
        if (idx >= 0 && idx < items.length) return items[idx];
      }
    }
    for (i = 0; i < items.length; i++) {
      if ((items[i].getAttribute("data-fb-item") || "") === token || items[i].id === token) return items[i];
    }
    return null;
  }

  function itemHref(item) {
    var id = item.getAttribute("data-fb-item") || item.id || "";
    return id ? "#" + id : "";
  }

  // Jump to the item. scrollIntoView is guarded (jsdom has none) and focus is moved so a keyboard
  // reader actually lands there rather than merely watching the page move. The flash attribute is
  // the CSS hook; it self-clears so a re-jump re-triggers the animation.
  function gotoItem(item) {
    if (!item) return;
    if (typeof item.scrollIntoView === "function") {
      try { item.scrollIntoView({ behavior: "smooth", block: "start" }); }
      catch (e) { try { item.scrollIntoView(); } catch (e2) { /* no layout */ } }
    }
    if (!item.hasAttribute("tabindex")) item.setAttribute("tabindex", "-1");
    if (typeof item.focus === "function") { try { item.focus({ preventScroll: true }); } catch (e3) { item.focus(); } }
    item.setAttribute("data-pt-flash", "1");
    var clear = function () { item.removeAttribute("data-pt-flash"); };
    if (typeof setTimeout === "function") setTimeout(clear, 1400);
  }

  // ── the ticket reference element ─────────────────────────────────────────────
  var ProveTicket = class extends HTMLElement {
    connectedCallback() {
      if (this._rendered) return;
      this._rendered = true;
      var key = keyOf(this);
      // Not a valid key: leave the original text content in place, inertly, no link.
      if (!key) return;
      this._uid = ++_uid;
      this._key = key;
      var self = this;
      this.paint();
      _refreshers.push(function () { self.paint(); });
    }

    // Idempotent full repaint — called once at connect and again whenever the ticket data resolves
    // (or fails). Rebuilding is cheaper to reason about than patching, and dropping the old wrapper
    // takes its listeners with it, so repeated data arrivals cannot leak handlers.
    paint() {
      var key = this._key;
      if (!key) return;
      this.textContent = ""; // clear the raw key text — we re-render it as a link below

      var tipId = "pt-tip-" + this._uid;

      var wrap = document.createElement("span");
      wrap.className = "pt-wrap";

      var meta = metaFor(key);
      var at = bakedAt();
      var bucket = freshnessOf(meta, at);
      this.setAttribute("data-pt-source", sourceForKey(key));

      // Freshness dot (leading). Color is never alone: role=img + title/aria-label + non-color fill.
      var dot = makeDot(bucket, dotLabelFor(key, meta), false);

      var a = document.createElement("a");
      a.className = "pt-link";
      a.setAttribute("href", TRACKER_ISSUE_BASE + key);
      a.setAttribute("target", "_blank");
      a.setAttribute("rel", "noopener noreferrer");
      a.setAttribute("aria-describedby", tipId);
      a.setAttribute("aria-haspopup", "dialog");
      a.setAttribute("aria-expanded", "false");
      a.textContent = key; // textContent — never innerHTML
      this._anchor = a;

      var tip = document.createElement("span");
      tip.className = "pt-tip";
      tip.id = tipId;
      tip.setAttribute("role", "tooltip");
      tip.hidden = true;

      var line1 = document.createElement("span");
      line1.className = "pt-tip-title";
      var line2 = document.createElement("span");
      line2.className = "pt-tip-status";

      if (meta && typeof meta.title === "string" && meta.title.trim()) {
        line1.textContent = meta.title;                 // baked title — textContent-safe
        var status = typeof meta.status === "string" ? meta.status : "";
        // Status is a DATED fact, never presented as if live — and what is dated is the DATA,
        // which is why the stamp names it.
        var stamp = "status as of " + (at || "publish");
        line2.textContent = status ? stamp + ": " + status : stamp;
        tip.appendChild(line1);
        tip.appendChild(line2);
        var age = ageString(meta, at);
        if (age) {
          var line3 = document.createElement("span");
          line3.className = "pt-tip-age";
          line3.textContent = "last activity " + age;
          tip.appendChild(line3);
        }
      } else {
        // Link-only degradation. When the data FAILED to load, say that instead of implying the
        // ticket simply has nothing to show.
        line1.textContent = "Open " + key + " in Linear";
        tip.appendChild(line1);
        if (_state === "error") {
          var warn = document.createElement("span");
          warn.className = "pt-tip-warn";
          warn.textContent = "ticket data unavailable — link only";
          tip.appendChild(warn);
        }
      }

      wrap.appendChild(dot);
      wrap.appendChild(a);
      wrap.appendChild(tip);
      this.appendChild(wrap);

      var show = function () { tip.hidden = false; };
      var hide = function () { tip.hidden = true; };
      a.addEventListener("mouseenter", show);
      a.addEventListener("mouseleave", hide);
      a.addEventListener("focus", show);
      a.addEventListener("blur", hide);
      a.addEventListener("keydown", function (e) { if (e.key === "Escape") hide(); });
      wrap.addEventListener("mouseleave", hide);

      // Click / Enter / Space open the anchored CARD (not navigate). "Open in Linear ↗" lives in the
      // card header for the actual navigation.
      var open = function (e) {
        if (e) e.preventDefault();
        hide();
        getCard().openFor(key, a);
      };
      a.addEventListener("click", open);
      a.addEventListener("keydown", function (e) {
        if (e.key === "Enter" || e.key === " " || e.key === "Spacebar") open(e);
      });
    }
  };

  // ── the internal item reference element ──────────────────────────────────────
  // Same affordance vocabulary as a ticket ref (leading mark, .pt-link, .pt-tip teaser, the shared
  // anchored card) with the two behaviours the reference kind actually wants: the LINK jumps
  // (it is a real in-page anchor, so middle-click and copy-link work untouched) and the MARK opens
  // the card. No fetch, no freshness — an in-page reference has no external truth to age against.
  var ProveRef = class extends HTMLElement {
    connectedCallback() {
      if (this._rendered) return;
      this._rendered = true;
      var token = (this.getAttribute("item") || "").trim();
      var label = (this.getAttribute("label") || "").trim() || (this.textContent || "").trim() || ("[" + token + "]");
      var item = resolveItem(token);
      // Unresolvable: leave the text exactly as authored. A page must never gain an affordance that
      // points nowhere — `[0-9]` in prose is a regex, not a decision.
      if (!item) { this.textContent = label; return; }
      this._uid = ++_uid;
      this._token = token;
      this._item = item;
      this.textContent = "";
      this.setAttribute("data-pt-item", item.getAttribute("data-fb-item") || item.id || token);

      var info = itemMeta(item);
      var tipId = "pt-reftip-" + this._uid;
      var wrap = document.createElement("span");
      wrap.className = "pt-wrap pt-wrap-ref";

      var mark = document.createElement("button");
      mark.className = "pt-mark";
      mark.setAttribute("type", "button");
      mark.setAttribute("aria-haspopup", "dialog");
      mark.setAttribute("aria-expanded", "false");
      mark.setAttribute("aria-label", "Details for " + (info.title ? info.title : "this item"));
      mark.setAttribute("title", "Details");

      var a = document.createElement("a");
      a.className = "pt-link pt-ref";
      a.setAttribute("href", itemHref(item) || "#");
      a.setAttribute("aria-describedby", tipId);
      a.textContent = label;

      var tip = document.createElement("span");
      tip.className = "pt-tip";
      tip.id = tipId;
      tip.setAttribute("role", "tooltip");
      tip.hidden = true;
      var t1 = document.createElement("span");
      t1.className = "pt-tip-title";
      t1.textContent = info.title || ("Item " + (info.ordinal || info.id || token));
      tip.appendChild(t1);
      if (info.state) {
        var t2 = document.createElement("span");
        t2.className = "pt-tip-status";
        t2.textContent = info.state;
        tip.appendChild(t2);
      }
      var t3 = document.createElement("span");
      t3.className = "pt-tip-age";
      t3.textContent = "on this page — press to jump";
      tip.appendChild(t3);

      wrap.appendChild(mark);
      wrap.appendChild(a);
      wrap.appendChild(tip);
      this.appendChild(wrap);

      var show = function () {
        tip.hidden = false;
        // Reuse the shared flip/clamp geometry for the teaser too, so a ref near the bottom edge
        // does not open a popover off-screen.
        placeTip(a, tip);
      };
      var hide = function () { tip.hidden = true; };
      a.addEventListener("mouseenter", show);
      a.addEventListener("mouseleave", hide);
      a.addEventListener("focus", show);
      a.addEventListener("blur", hide);
      mark.addEventListener("mouseenter", show);
      mark.addEventListener("mouseleave", hide);
      wrap.addEventListener("mouseleave", hide);

      // The link jumps. Enter/Space on an <a> already fires click, so this covers keyboard too.
      a.addEventListener("click", function (e) {
        if (e && (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey)) return; // let the browser do its thing
        if (e) e.preventDefault();
        hide();
        gotoItem(item);
      });
      // The mark opens the shared card in item mode.
      var self = this;
      mark.addEventListener("click", function (e) {
        if (e) e.preventDefault();
        hide();
        getCard().openForItem(self._item, mark);
      });
    }
  };

  // ── the shared anchored card ──────────────────────────────────────────────────
  var TABS = [
    { id: "overview", label: "Overview" },
    { id: "activity", label: "Activity" },
    { id: "relations", label: "Relations" }
  ];

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text; // textContent — every baked string is inert
    return n;
  }

  // Position a plain teaser with the same pure geometry the card uses. No-ops without layout.
  function placeTip(anchor, tip) {
    if (!anchor || !tip || typeof anchor.getBoundingClientRect !== "function") return;
    if (typeof window === "undefined") return;
    var rect = anchor.getBoundingClientRect();
    if (!rect || (!rect.width && !rect.height)) return;
    var size = { width: 300, height: 96 };
    if (tip.getBoundingClientRect) {
      var r = tip.getBoundingClientRect();
      if (r.width) size.width = r.width;
      if (r.height) size.height = r.height;
    }
    var pos = choosePlacement(
      { top: rect.top, bottom: rect.bottom, left: rect.left, right: rect.right },
      { width: window.innerWidth || 1024, height: window.innerHeight || 768 }, size
    );
    tip.style.position = "fixed";
    tip.style.top = pos.top + "px";
    tip.style.left = pos.left + "px";
    tip.setAttribute("data-placement", pos.placement);
  }

  // Real focusability needs ancestor visibility, not just the element's own `hidden`. A tab-panel
  // widget hides inactive panels on the ancestor [role=tabpanel][hidden] (→ display:none), so a
  // control inside a hidden panel is unreachable even though its own `hidden` is false.
  function inHiddenPanel(n) {
    var p = n;
    while (p && p.nodeType === 1) {
      if (p.getAttribute && p.getAttribute("role") === "tabpanel" && p.hidden) return true;
      p = p.parentNode;
    }
    return false;
  }

  var ProveTicketCard = class extends HTMLElement {
    connectedCallback() {
      if (this._built) return;
      this._built = true;
      this.hidden = true;
      this.setAttribute("aria-hidden", "true");
      this._uid = ++_uid; // uniquifies this card's global ids (title/tab/panel) in light DOM
      this._activeTab = "overview";
      this._docHandlers = null;
    }

    // Open the card for `key`, anchored to `anchorEl`; remember it as the focus-return target.
    openFor(key, anchorEl) {
      this._opener = anchorEl || this._opener || null;
      this._activeTab = "overview";
      this._item = null;
      this.render(key);
      this.reveal();
    }

    // Same machinery, item mode: no tabs, no freshness, and a primary "Go to decision" action.
    openForItem(item, anchorEl) {
      this._opener = anchorEl || this._opener || null;
      this._key = null;
      this._item = item;
      this.renderItem(item);
      this.reveal();
    }

    reveal() {
      this.hidden = false;
      this.setAttribute("aria-hidden", "false");
      if (this._opener && this._opener.setAttribute) this._opener.setAttribute("aria-expanded", "true");
      this.position();
      this.bindDocHandlers();
      this.focusFirst();
    }

    // Swap content to a related key WITHOUT re-opening (card stays visible, doc-handlers untouched →
    // no listener leak) and WITHOUT losing the original focus-return target.
    navigateTo(key) {
      this._activeTab = "overview";
      this._item = null;
      this.render(key);
      this.position();
      this.focusFirst();
    }

    close() {
      if (this.hidden) return;
      this.hidden = true;
      this.setAttribute("aria-hidden", "true");
      this.unbindDocHandlers();
      var opener = this._opener;
      if (opener && opener.setAttribute) opener.setAttribute("aria-expanded", "false");
      if (opener && typeof opener.focus === "function") opener.focus();
    }

    shell(titleId) {
      if (this._content && this._content.parentNode) this.removeChild(this._content);
      var card = el("div", "pt-card");
      card.setAttribute("role", "dialog");
      card.setAttribute("aria-modal", "false");
      card.setAttribute("aria-labelledby", titleId);
      var close = el("button", "pt-close", "×");
      close.setAttribute("type", "button");
      close.setAttribute("aria-label", "Close");
      var self = this;
      close.addEventListener("click", function () { self.close(); });
      card.appendChild(close);
      return card;
    }

    render(key) {
      this._key = key;
      var uid = this._uid;
      var titleId = "pt-card-title-" + uid;
      var card = this.shell(titleId);
      var meta = metaFor(key);
      var at = bakedAt();

      // The banner is the card's half of the loud-failure contract: a reader who opens a card and
      // finds it empty must be told WHY it is empty, in the same place they looked.
      var banner = this.buildAlert();
      if (banner) card.appendChild(banner);

      card.appendChild(this.buildHeader(key, meta, at, titleId));
      card.appendChild(this.buildTablist());
      this._panels = {};
      card.appendChild(this.buildOverview(key, meta));
      card.appendChild(this.buildActivity(meta, at));
      card.appendChild(this.buildRelations(meta));
      card.appendChild(this.buildLegend());

      this.selectTab(this._activeTab, false);
      this._content = card;
      this.appendChild(card);
    }

    renderItem(item) {
      var uid = this._uid;
      var titleId = "pt-card-title-" + uid;
      var card = this.shell(titleId);
      var info = itemMeta(item);
      this._tabs = null;
      this._panels = {};

      var hd = el("div", "pt-hd");
      var top = el("div", "pt-hd-top");
      var href = itemHref(item);
      var perma = el("a", "pt-keylink", (info.ordinal ? "[" + info.ordinal + "]" : (info.id || "item")) + " ↓");
      perma.setAttribute("href", href || "#");
      top.appendChild(perma);
      if (info.state) top.appendChild(el("span", "pt-pill", info.state));
      hd.appendChild(top);
      var title = el("span", "pt-title", info.title || ("Item " + (info.id || info.ordinal || "")));
      title.id = titleId;
      hd.appendChild(title);
      var metarow = el("div", "pt-metarow");
      if (info.channel) metarow.appendChild(el("span", null, info.channel));
      if (info.kind) metarow.appendChild(el("span", null, info.kind));
      if (info.id) metarow.appendChild(el("span", null, "#" + info.id));
      if (metarow.childNodes.length) hd.appendChild(metarow);
      hd.appendChild(el("div", "pt-fresh", "on this page — no external data, nothing dated"));
      card.appendChild(hd);

      var actions = el("div", "pt-actions");
      var go = el("button", "pt-go", "Go to decision ↓");
      go.setAttribute("type", "button");
      var self = this;
      go.addEventListener("click", function () { self.close(); gotoItem(item); });
      actions.appendChild(go);
      card.appendChild(actions);
      this._primary = go;

      this._content = card;
      this.appendChild(card);
    }

    // Null when the data resolved cleanly — the happy path shows no chrome about loading at all.
    buildAlert() {
      if (_state !== "error" && _state !== "pending") return null;
      var box = el("div", "pt-alert");
      box.setAttribute("role", _state === "error" ? "alert" : "status");
      box.setAttribute("data-state", _state);
      box.appendChild(el("span", "pt-alert-text", statusSentence()));
      if (_state === "error") {
        var retry = el("button", "pt-retry", "Retry");
        retry.setAttribute("type", "button");
        retry.addEventListener("click", function () { retryMetaLoad(); });
        box.appendChild(retry);
      }
      return box;
    }

    buildHeader(key, meta, at, titleId) {
      var hd = el("div", "pt-hd");
      var top = el("div", "pt-hd-top");
      var link = el("a", "pt-keylink", key + " ↗");
      link.setAttribute("href", safeHref(meta && meta.url, key));
      link.setAttribute("target", "_blank");
      link.setAttribute("rel", "noopener noreferrer");
      top.appendChild(link);
      var status = meta && typeof meta.status === "string" ? meta.status : "";
      if (status) {
        // Status color is a token applied through a per-type class — never an inline hex on .style.
        var stype = meta && typeof meta.statusType === "string" ? meta.statusType : "";
        var pill = el("span", (stype && STATUS_TYPES[stype]) ? "pt-pill pt-pill-" + stype : "pt-pill", status);
        top.appendChild(pill);
      }
      hd.appendChild(top);

      var title = el("span", "pt-title", (meta && typeof meta.title === "string" && meta.title) ? meta.title : ("Open " + key + " in Linear"));
      title.id = titleId;
      hd.appendChild(title);

      var metarow = el("div", "pt-metarow");
      if (meta && meta.priority) metarow.appendChild(el("span", null, "Priority: " + meta.priority));
      if (meta && meta.assignee) metarow.appendChild(el("span", null, "Assignee: " + meta.assignee));
      if (meta && meta.project) metarow.appendChild(el("span", null, meta.project));
      if (metarow.childNodes.length) hd.appendChild(metarow);

      var bucket = freshnessOf(meta, at);
      var fresh = el("div", "pt-fresh");
      fresh.appendChild(makeDot(bucket, null, true)); // decorative — the adjacent text states the fact
      var age = ageString(meta, at);
      // "TICKET DATA as of" — the timestamp belongs to the data, which can be re-baked after this
      // page shipped. Saying only "as of" would let a reader read it as the page's own date.
      var stamp = at ? " · ticket data as of " + at : "";
      fresh.appendChild(el("span", null, (age ? "last activity " + age : FRESHNESS_LABEL[bucket]) + stamp));
      hd.appendChild(fresh);
      return hd;
    }

    buildTablist() {
      var list = el("div");
      list.setAttribute("role", "tablist");
      list.setAttribute("aria-label", "Ticket detail sections");
      var self = this;
      var uid = this._uid;
      this._tabs = {};
      TABS.forEach(function (t) {
        var b = el("button", null, t.label);
        b.setAttribute("type", "button");
        b.setAttribute("role", "tab");
        b.setAttribute("data-tab", t.id);
        b.id = "pt-tab-" + t.id + "-" + uid;
        b.setAttribute("aria-controls", "pt-panel-" + t.id + "-" + uid);
        b.setAttribute("aria-selected", "false");
        b.setAttribute("tabindex", "-1");
        b.addEventListener("click", function () { self.selectTab(t.id, true); });
        b.addEventListener("keydown", function (e) { self.onTabKey(e, t.id); });
        self._tabs[t.id] = b;
        list.appendChild(b);
      });
      return list;
    }

    onTabKey(e, id) {
      var order = TABS.map(function (t) { return t.id; });
      var i = order.indexOf(id);
      var next = null;
      if (e.key === "ArrowRight" || e.key === "ArrowDown") next = order[(i + 1) % order.length];
      else if (e.key === "ArrowLeft" || e.key === "ArrowUp") next = order[(i - 1 + order.length) % order.length];
      else if (e.key === "Home") next = order[0];
      else if (e.key === "End") next = order[order.length - 1];
      if (next) { e.preventDefault(); this.selectTab(next, true); }
    }

    selectTab(id, focus) {
      this._activeTab = id;
      var self = this;
      TABS.forEach(function (t) {
        var b = self._tabs && self._tabs[t.id];
        var p = self._panels && self._panels[t.id];
        var on = t.id === id;
        if (b) {
          b.setAttribute("aria-selected", on ? "true" : "false");
          b.setAttribute("tabindex", on ? "0" : "-1");
          if (on && focus) b.focus();
        }
        if (p) p.hidden = !on;
      });
    }

    makePanel(id) {
      var uid = this._uid;
      var p = el("section");
      p.setAttribute("role", "tabpanel");
      p.setAttribute("data-panel", id);
      p.id = "pt-panel-" + id + "-" + uid;
      p.setAttribute("aria-labelledby", "pt-tab-" + id + "-" + uid);
      p.hidden = true;
      this._panels[id] = p;
      return p;
    }

    // The empty-state wording carries the same distinction the banner does: "not baked" (we have the
    // data and it holds nothing) is a different sentence from "could not load" (we have nothing).
    emptyLine(what, key) {
      if (_state === "error") return "No " + what + " — the ticket data could not be loaded.";
      if (_state === "pending") return "Loading " + what + "…";
      return key ? "No " + what + " baked for " + key + "." : "No " + what + " baked.";
    }

    buildOverview(key, meta) {
      var p = this.makePanel("overview");
      var desc = (meta && typeof meta.description === "string" && meta.description.trim())
        ? meta.description.trim() : "";
      if (desc) p.appendChild(el("div", "pt-desc", desc));
      else p.appendChild(el("div", "pt-empty", this.emptyLine("description", key)));
      var grid = el("div", "pt-grid");
      var add = function (label, val) {
        if (val == null || val === "") return;
        grid.appendChild(el("b", null, label));
        grid.appendChild(el("span", null, String(val)));
      };
      add("Status", meta && meta.status);
      add("Priority", meta && meta.priority);
      add("Assignee", meta && meta.assignee);
      add("Project", meta && meta.project);
      add("Updated", meta && meta.updatedAt);
      if (grid.childNodes.length) p.appendChild(grid);
      return p;
    }

    buildActivity(meta, at) {
      var p = this.makePanel("activity");
      // Sort newest-first by ts before capping, so the last-5 are the NEWEST 5 regardless of bake
      // order. Stable: equal/missing ts keep their relative order (missing sorts oldest).
      var acts = meta && Array.isArray(meta.activity)
        ? meta.activity.slice().sort(function (a, b) {
            var ta = a && a.ts ? Date.parse(a.ts) : NaN;
            var tb = b && b.ts ? Date.parse(b.ts) : NaN;
            return (isNaN(tb) ? -Infinity : tb) - (isNaN(ta) ? -Infinity : ta);
          }).slice(0, ACTIVITY_CAP)
        : [];
      if (!acts.length) {
        p.appendChild(el("div", "pt-empty", this.emptyLine("recent activity")));
        return p;
      }
      var ul = el("ul", "pt-evts");
      acts.forEach(function (ev) {
        var isState = ev && ev.kind === "state";
        var li = el("li", "pt-evt " + (isState ? "pt-evt--state" : "pt-evt--comment"));
        var head = el("div", "pt-evt-hd");
        head.appendChild(el("span", "pt-evt-kind", isState ? "State" : "Comment"));
        if (ev && ev.author) head.appendChild(el("span", null, ev.author));
        var one = { lastActivityAt: ev && ev.ts };
        var age = ageString(one, at);
        if (age) head.appendChild(el("span", null, age));
        li.appendChild(head);
        var text = ev && typeof ev.text === "string" ? ev.text : "";
        if (text) li.appendChild(el("div", "pt-evt-text", text));
        ul.appendChild(li);
      });
      p.appendChild(ul);
      return p;
    }

    buildRelations(meta) {
      var p = this.makePanel("relations");
      var rels = meta && Array.isArray(meta.relations) ? meta.relations : [];
      if (!rels.length) {
        p.appendChild(el("div", "pt-empty", this.emptyLine("related tickets")));
        return p;
      }
      var box = el("div", "pt-rels");
      var self = this;
      rels.forEach(function (r) {
        if (!r || !KEY_RE.test(String(r.key || ""))) return;
        var label = r.key + (r.type ? " · " + r.type : "");
        var chip = el("button", "pt-rel", r.title ? label + " — " + r.title : label);
        chip.setAttribute("type", "button");
        chip.setAttribute("data-key", r.key);
        chip.addEventListener("click", function () { self.navigateTo(r.key); });
        box.appendChild(chip);
      });
      if (!box.childNodes.length) p.appendChild(el("div", "pt-empty", this.emptyLine("related tickets")));
      else p.appendChild(box);
      return p;
    }

    buildLegend() {
      var lg = el("div", "pt-legend");
      lg.setAttribute("aria-hidden", "true");
      [["fresh", "<24h"], ["recent", "≤7d"], ["moderate", "≤30d"], ["stale", ">30d"], ["unknown", "unknown"]]
        .forEach(function (pair) {
          var s = el("span");
          s.appendChild(makeDot(pair[0], null, true));
          s.appendChild(el("span", null, pair[1]));
          lg.appendChild(s);
        });
      return lg;
    }

    focusables() {
      if (!this._content) return [];
      return Array.prototype.slice.call(
        this._content.querySelectorAll('a[href],button,[role=tab][tabindex="0"],[tabindex]:not([tabindex="-1"])')
      ).filter(function (n) {
        if (inHiddenPanel(n)) return false;
        return (!n.hidden && n.getAttribute("tabindex") !== "-1") || (n.getAttribute("role") === "tab" && n.getAttribute("tabindex") === "0");
      });
    }

    focusFirst() {
      // Item mode has no tablist; its primary action is the thing a reader came for.
      if (this._primary && this._item && typeof this._primary.focus === "function") { this._primary.focus(); return; }
      var sel = this._tabs && this._tabs[this._activeTab];
      if (sel && typeof sel.focus === "function") { sel.focus(); return; }
      var f = this.focusables();
      if (f.length && typeof f[0].focus === "function") f[0].focus();
    }

    position() {
      if (!this._opener || typeof this._opener.getBoundingClientRect !== "function") return;
      var rect = this._opener.getBoundingClientRect();
      var vw = (typeof window !== "undefined" && window.innerWidth) || 1024;
      var vh = (typeof window !== "undefined" && window.innerHeight) || 768;
      var size = { width: 384, height: 240 };
      if (this._content && this._content.getBoundingClientRect) {
        var r = this._content.getBoundingClientRect();
        if (r.width) size.width = r.width;
        if (r.height) size.height = r.height;
      }
      var pos = choosePlacement(
        { top: rect.top, bottom: rect.bottom, left: rect.left, right: rect.right },
        { width: vw, height: vh }, size
      );
      this.style.top = pos.top + "px";
      this.style.left = pos.left + "px";
      this.setAttribute("data-placement", pos.placement);
    }

    bindDocHandlers() {
      if (this._docHandlers) return;
      var self = this;
      var onKey = function (e) {
        if (e.key === "Escape") { e.preventDefault(); self.close(); return; }
        if (e.key === "Tab") self.trapTab(e);
      };
      var onDown = function (e) {
        // Outside-click: the event's composedPath (or target) never includes this host → close.
        var path = typeof e.composedPath === "function" ? e.composedPath() : [e.target];
        if (path.indexOf(self) === -1 && (!self._opener || path.indexOf(self._opener) === -1)) self.close();
      };
      var onReflow = function () { self.position(); };
      document.addEventListener("keydown", onKey, true);
      document.addEventListener("mousedown", onDown, true);
      window.addEventListener("resize", onReflow);
      window.addEventListener("scroll", onReflow, true);
      this._docHandlers = { onKey: onKey, onDown: onDown, onReflow: onReflow };
    }

    unbindDocHandlers() {
      var h = this._docHandlers;
      if (!h) return;
      document.removeEventListener("keydown", h.onKey, true);
      document.removeEventListener("mousedown", h.onDown, true);
      window.removeEventListener("resize", h.onReflow);
      window.removeEventListener("scroll", h.onReflow, true);
      this._docHandlers = null;
    }

    trapTab(e) {
      var f = Array.prototype.slice.call(
        this._content ? this._content.querySelectorAll('a[href],button,[role=tab],[tabindex]') : []
      ).filter(function (n) {
        if (n.hidden) return false;
        if (inHiddenPanel(n)) return false;
        if (n.getAttribute("tabindex") === "-1" && n.getAttribute("role") !== "tab") return false;
        if (n.getAttribute("role") === "tab" && n.getAttribute("aria-selected") !== "true") return false;
        return true;
      });
      if (!f.length) return;
      // Light DOM: the active element lives on the document, not a shadow root.
      var active = document.activeElement;
      var first = f[0], last = f[f.length - 1];
      if (e.shiftKey && active === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && active === last) { e.preventDefault(); first.focus(); }
    }
  };

  function defineElement() {
    if (typeof customElements === "undefined") return;
    if (!customElements.get("prove-ticket")) customElements.define("prove-ticket", ProveTicket);
    if (!customElements.get("prove-ref")) customElements.define("prove-ref", ProveRef);
    if (!customElements.get(CARD_TAG)) customElements.define(CARD_TAG, ProveTicketCard);
  }

  function getCard() {
    if (_card && _card.isConnected !== false) return _card;
    defineElement();
    _card = document.createElement(CARD_TAG);
    document.body.appendChild(_card);
    return _card;
  }

  function skipTextNode(node) {
    var v = node.nodeValue;
    if (!v) return true;
    var hasKey = v.indexOf("FIN-") !== -1 && SCAN_TEST_RE.test(v);
    var hasRef = v.indexOf("[") !== -1 && ITEM_SCAN_TEST_RE.test(v);
    if (!hasKey && !hasRef) return true;
    var p = node.parentNode;
    while (p && p.nodeType === 1) {
      // tagName is lowercase for SVG/foreign-namespace elements (e.g. an SVG <a>), uppercase for
      // HTML — normalize so a foreign <a> is still skipped and never gets a link nested inside it.
      if (p.tagName && SKIP_TAGS[p.tagName.toUpperCase()]) return true;
      if (p.hasAttribute) {
        if (p.hasAttribute(OPT_OUT_ATTR)) return true;
        var ce = p.getAttribute && p.getAttribute("contenteditable");
        if (ce != null && ce !== "false") return true;
      }
      p = p.parentNode;
    }
    return false;
  }

  // A FIN-\d+ sitting inside a plain-text URL ("…/issue/FIN-3519") must NOT be wrapped — the "/"
  // after it clears the [\w-] neighbor guard, so it would linkify a fragment of a real link. Reject
  // when the contiguous run of non-whitespace chars immediately preceding the match contains "://".
  // Precise: "(FIN-3519)" (preceding run "(") and "issue FIN-3519" (preceding run empty) still wrap.
  function precededByScheme(text, index) {
    var start = index;
    while (start > 0 && !/\s/.test(text.charAt(start - 1))) start--;
    return text.slice(start, index).indexOf("://") !== -1;
  }

  // ── the single tokenizer both reference kinds go through ─────────────────────
  // Returns non-overlapping matches in document order: { kind:"ticket"|"ref", start, end, text,
  // token }. Ticket matches win a tie, and an unresolvable [token] is simply not returned — which
  // is what leaves `[0-9]` in prose alone.
  function collectRefs(text) {
    var out = [];
    var re = /FIN-\d+/g, m;
    while ((m = re.exec(text))) {
      var end = m.index + m[0].length;
      var before = m.index > 0 ? text.charAt(m.index - 1) : "";
      var after = end < text.length ? text.charAt(end) : "";
      // Reject when a word char OR a hyphen sits directly against the key — `\b` alone admits a
      // leading/trailing hyphen (e.g. "report-FIN-5-draft" would wrap "FIN-5").
      if (/[\w-]/.test(before) || /[\w-]/.test(after)) continue;
      if (precededByScheme(text, m.index)) continue; // don't wrap a FIN inside a plain-text URL
      out.push({ kind: "ticket", start: m.index, end: end, text: m[0], token: m[0] });
    }
    var rre = new RegExp(ITEM_TOKEN_RE.source, "g"), r;
    while ((r = rre.exec(text))) {
      var rEnd = r.index + r[0].length;
      var clash = false;
      for (var i = 0; i < out.length; i++) {
        if (r.index < out[i].end && rEnd > out[i].start) { clash = true; break; }
      }
      if (clash) continue;
      if (!resolveItem(r[1])) continue;   // unresolvable → not a reference, leave the prose alone
      out.push({ kind: "ref", start: r.index, end: rEnd, text: r[0], token: r[1] });
    }
    out.sort(function (a, b) { return a.start - b.start; });
    return out;
  }

  // ── SVG / mermaid inline affordance ──────────────────────────────────────────
  // Only the INLINE affordance is namespace-specific. The shared <prove-ticket-card>, readMeta/
  // metaFor, freshnessOf, choosePlacement/position() are reused verbatim — the card anchors to ANY
  // element exposing getBoundingClientRect(), SVG included.
  var SVGNS = "http://www.w3.org/2000/svg";
  var XLINKNS = "http://www.w3.org/1999/xlink";

  function nearestSvg(node) {
    var p = node;
    while (p && p.nodeType === 1) {
      if (p.namespaceURI === SVGNS && p.tagName && p.tagName.toLowerCase() === "svg") return p;
      p = p.parentNode;
    }
    return null;
  }

  // Build the freshness <circle> synchronously so its structure + bucket class are observable WITHOUT
  // layout (jsdom has none). Color comes from a CSS `fill` on the .pt-dot-<bucket> class (a token — a
  // <circle fill> presentation attr can't read var(), and CSS fill wins over it anyway). The
  // non-color channel is the `r` size ramp; unknown = ring (fill:none stroke via CSS). Positioning is
  // deferred to placeSvgDot.
  function makeSvgDot(bucket) {
    var fill = FILL_WORD[bucket] || "ring";
    var c = document.createElementNS(SVGNS, "circle");
    c.setAttribute("r", String(SVG_DOT_R[fill] || 5));
    c.setAttribute("data-pt-dot", "1");
    c.setAttribute("data-pt-bucket", bucket);
    c.setAttribute("data-fill", fill);
    c.setAttribute("class", "pt-svg-dot pt-dot-" + bucket);
    return c;
  }

  // Deferred: once the anchor is laid out, read its user-space bbox and drop the dot just left of the
  // key in the same SVG user coordinate system. jsdom has NO SVG layout (getBBox missing/zero), so
  // this guards a missing method AND zero/NaN geometry and simply no-ops there — never throws.
  function placeSvgDot(anchor, circle) {
    if (!anchor || !circle || typeof anchor.getBBox !== "function") return;
    var bb;
    try { bb = anchor.getBBox(); } catch (e) { return; }
    if (!bb || (!bb.width && !bb.height)) return;
    var cx = bb.x - 8, cy = bb.y + bb.height / 2;
    if (isNaN(cx) || isNaN(cy)) return;
    circle.setAttribute("cx", String(cx));
    circle.setAttribute("cy", String(cy));
  }

  // Re-point an already-rendered SVG affordance at freshly-arrived data. The SVG path cannot simply
  // repaint like the HTML element does (its nodes are spliced into someone else's <text>), so it
  // updates the three things the data actually governs: href, accessible label, and the dot.
  function refreshSvgRef(rec) {
    var meta = metaFor(rec.key);
    var at = bakedAt();
    var bucket = freshnessOf(meta, at);
    rec.a.setAttribute("href", safeHref(meta && meta.url, rec.key));
    rec.a.setAttributeNS(XLINKNS, "xlink:href", safeHref(meta && meta.url, rec.key));
    rec.a.setAttribute("aria-label", rec.key + " · " + dotLabelFor(rec.key, meta));
    rec.a.setAttribute("data-pt-source", sourceForKey(rec.key));
    if (rec.circle) {
      var fill = FILL_WORD[bucket] || "ring";
      rec.circle.setAttribute("r", String(SVG_DOT_R[fill] || 5));
      rec.circle.setAttribute("data-pt-bucket", bucket);
      rec.circle.setAttribute("data-fill", fill);
      rec.circle.setAttribute("class", "pt-svg-dot pt-dot-" + bucket);
    }
  }

  function wrapTextNodeSvg(node) {
    var text = node.nodeValue;
    var svg = nearestSvg(node.parentNode);
    var at = bakedAt();
    var refs = collectRefs(text);
    if (!refs.length) return;
    var frag = document.createDocumentFragment();
    var pending = []; // {anchor, circle} — dots positioned after the frag is live (needs layout)
    var last = 0;
    for (var i = 0; i < refs.length; i++) {
      var r = refs[i];
      if (r.start > last) frag.appendChild(document.createTextNode(text.slice(last, r.start)));
      last = r.end;
      if (r.kind !== "ticket") {
        // Internal refs get no SVG-native affordance (a mermaid label is not an addressing surface);
        // keeping the literal text is honest and loses nothing.
        frag.appendChild(document.createTextNode(r.text));
        continue;
      }
      var key = r.token;
      _ticketRefCount++;
      var meta = metaFor(key);
      var bucket = freshnessOf(meta, at);

      // Inline affordance in the SVG namespace: <a role=link><tspan>KEY</tspan></a>. Leading spaces
      // in the tspan reserve room for the <circle> dot placed to its left post-layout.
      var a = document.createElementNS(SVGNS, "a");
      var href = safeHref(meta && meta.url, key);
      a.setAttribute("href", href);
      a.setAttributeNS(XLINKNS, "xlink:href", href); // legacy renderers still key off xlink:href
      a.setAttribute("target", "_blank");
      a.setAttribute("rel", "noopener noreferrer");
      a.setAttribute("role", "link");
      a.setAttribute("aria-label", key + " · " + dotLabelFor(key, meta));
      a.setAttribute("aria-haspopup", "dialog");
      a.setAttribute("data-pt-key", key);
      a.setAttribute("data-pt-source", sourceForKey(key));
      a.style.cursor = "pointer";
      var tspan = document.createElementNS(SVGNS, "tspan");
      tspan.setAttribute("text-decoration", "underline");
      tspan.setAttribute("fill", "currentColor");
      tspan.textContent = "  " + key; // textContent — never innerHTML
      a.appendChild(tspan);
      // Click opens the SAME shared card, anchored to this SVG <a> via getBoundingClientRect().
      (function (k) {
        a.addEventListener("click", function (e) {
          if (e) e.preventDefault();
          getCard().openFor(k, this);
        });
      })(key);
      frag.appendChild(a);
      var circle = null;
      if (svg) {
        circle = makeSvgDot(bucket);
        svg.appendChild(circle);
        pending.push({ anchor: a, circle: circle });
      }
      (function (rec) { _refreshers.push(function () { refreshSvgRef(rec); }); })({ key: key, a: a, circle: circle });
    }
    if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
    if (node.parentNode) node.parentNode.replaceChild(frag, node);
    // Anchors are live now — position the dots on the next frame (needs real layout; guarded no-op
    // under jsdom). rAF falls back to a macrotask where unavailable.
    if (pending.length) {
      var raf = (typeof requestAnimationFrame === "function") ? requestAnimationFrame : function (f) { setTimeout(f, 0); };
      raf(function () { for (var i2 = 0; i2 < pending.length; i2++) placeSvgDot(pending[i2].anchor, pending[i2].circle); });
    }
  }

  function wrapTextNode(node) {
    // Namespace split: an SVG-namespace text node gets the SVG affordance (an HTML <prove-ticket>
    // replaceChild'd into SVG <text> renders nothing — the latent bug this closes). HTML path below.
    if (node.parentNode && node.parentNode.namespaceURI === SVGNS) return wrapTextNodeSvg(node);
    var text = node.nodeValue;
    var refs = collectRefs(text);
    if (!refs.length) return;
    var frag = document.createDocumentFragment();
    var last = 0;
    for (var i = 0; i < refs.length; i++) {
      var r = refs[i];
      if (r.start > last) frag.appendChild(document.createTextNode(text.slice(last, r.start)));
      last = r.end;
      var e;
      if (r.kind === "ticket") {
        _ticketRefCount++;
        e = document.createElement("prove-ticket");
        e.setAttribute("key", r.token);
      } else {
        e = document.createElement("prove-ref");
        e.setAttribute("item", r.token);
      }
      e.textContent = r.text;
      frag.appendChild(e);
    }
    if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
    if (node.parentNode) node.parentNode.replaceChild(frag, node);
  }

  // Auto-scanner (default ON). Idempotent: wrapped refs live inside <prove-ticket>/<prove-ref>,
  // both SKIP_TAGS, so a second pass is a no-op. Collect first, mutate after (never edit mid-walk).
  function scan(root) {
    root = root || document.body;
    if (!root || typeof document.createTreeWalker !== "function") return;
    forgetItems();
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) { return skipTextNode(n) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT; }
    });
    var targets = [], n;
    while ((n = walker.nextNode())) targets.push(n);
    for (var i = 0; i < targets.length; i++) wrapTextNode(targets[i]);
  }

  function init() {
    defineElement();
    // Scan FIRST, load SECOND. The degraded affordance is therefore the INITIAL state and every
    // later outcome is an upgrade — which is what makes a 404 visually indistinguishable from
    // "not yet arrived" instead of a half-built page, and why nothing here blocks first paint.
    scan(document.body);
    // Explicit <prove-ticket> elements the author wrote by hand count toward the fetch gate too.
    if (!_ticketRefCount) {
      var explicit = document.querySelectorAll("prove-ticket");
      _ticketRefCount = explicit ? explicit.length : 0;
    }
    startMetaLoad();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();

  window.ProveTicket = {
    scan: scan, define: defineElement, keyOf: keyOf, getCard: getCard,
    freshnessOf: freshnessOf, ageString: ageString, choosePlacement: choosePlacement,
    resolveItem: resolveItem, itemMeta: itemMeta, gotoItem: gotoItem,
    ticketsUrl: resolveTicketsUrl, retry: retryMetaLoad,
    dataState: function () {
      return { state: _state, detail: _detail, url: _sourceUrl, bakedAt: bakedAt(), message: statusSentence() };
    },
    TICKETS_SUFFIX: TICKETS_SUFFIX,
    TRACKER_ISSUE_BASE: TRACKER_ISSUE_BASE, PROOF_TICKET_VERSION: PROOF_TICKET_VERSION
  };
})();
