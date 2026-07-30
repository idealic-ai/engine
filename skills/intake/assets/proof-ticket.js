/* proof-ticket.js — framework-free, CSP-safe ticket-preview kit (inline-embed this whole file).
 *
 * Co-delivery note (READ THIS): this is a SEPARATE file from board-widgets.js on purpose.
 * board-widgets.js is a "cannot-drift" surface whose integrity pass BYTE-COMPARES the embedded
 * copy against source; co-tenanting a tooltip here would churn that checksum on every tweak.
 * The publish step co-inlines BOTH files onto one page (two independent integrity checks).
 * This file is PRESENTATION-ONLY: it emits no payload, never reads/writes data-fb-*, never calls
 * buildPayload(), and lives in a disjoint namespace (<prove-ticket>, <prove-ticket-card>,
 * #prove-tickets, window.ProveTicket).
 *
 * What it does: turns any `FIN-\d+` on the page into a labeled Linear link with
 *   (1) a leading FRESHNESS DOT (activity recency, bucketed <24h / ≤7d / ≤30d / >30d / unknown),
 *   (2) a hover/focus TEASER (title · dated status · last activity), and
 *   (3) a click/Enter/Space-activated, ANCHORED CARD popover — tabbed Overview / Activity / Relations,
 *       positioned against the ref (flip above / clamp into viewport), full dialog a11y.
 * Two entry points:
 *   1. <prove-ticket key="FIN-3519">FIN-3519</prove-ticket>  — explicit custom element.
 *   2. Auto-scanner (default ON): wraps bare FIN-\d+ text, skipping <a>/<code>/<pre>/etc.
 *
 * Metadata source (optional — the publish step BAKES it; superset of iteration-1's {title,status}):
 *   <script id="prove-tickets" type="application/json">
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
 *   <\/script>
 * BAKE CONTRACT (agent-side, publish-time — reuse §CMD_READ_RELATED_TICKET, never a browser fetch):
 *   per distinct FIN key on the page: get_issue + list_comments → normalize to the entry above.
 *   lastActivityAt = max(updatedAt, newest comment ts). activity = LAST 5 events only (comments +
 *   stateHistory transitions), each text TRIMMED — keeps the blob small; do NOT dump full threads.
 * ZERO external requests by design (hard publish gate): with no blob, an unknown key, or an
 * iteration-1 {title,status}-only entry, the element DEGRADES gracefully (link + unknown dot +
 * minimal card) — it NEVER fetches. Every baked string is rendered via textContent (XSS).
 *
 * Per-tracker knob: TRACKER_ISSUE_BASE below is the ONE thing to change for a different tracker.
 */
(function () {
  "use strict";

  // The one per-tracker constant — mirrors the project `## Tracker` Issue-URL convention.
  var TRACKER_ISSUE_BASE = "https://linear.app/finchclaims/issue/";

  var KEY_RE = /^FIN-\d+$/;          // exact key validation
  var SCAN_TEST_RE = /\bFIN-\d+\b/;  // non-global: cheap "does this text hold a key?" probe
  // Text nodes under any of these ancestors are left alone (real code/logs, already-linked keys,
  // editable fields, and our own elements to keep the scan idempotent).
  var SKIP_TAGS = {
    A: 1, CODE: 1, PRE: 1, SCRIPT: 1, STYLE: 1, TEXTAREA: 1, INPUT: 1,
    "PROVE-TICKET": 1, "PROVE-TICKET-CARD": 1
  };
  var OPT_OUT_ATTR = "data-no-prove-ticketify";
  var TIP_ID = "pt-tip";
  var CARD_TAG = "prove-ticket-card";
  var ACTIVITY_CAP = 5; // render at most the last-5 events (bake caps it too; belt + suspenders)

  // Freshness thresholds (activity recency, ref = bakedAt). Buckets: fresh <24h · recent ≤7d ·
  // moderate ≤30d · stale >30d · unknown (no date). Color is never the only channel: each carries
  // a title/aria-label and the card renders a one-line legend.
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

  var _meta = null; // parsed { bakedAt, tickets } | { absent: true }; parsed once, cached.
  var _card = null; // the single shared <prove-ticket-card> instance, created lazily.

  function readMeta() {
    if (_meta) return _meta;
    var el = document.getElementById("prove-tickets");
    if (!el) { _meta = { absent: true }; return _meta; }
    try {
      var raw = JSON.parse(el.textContent || "{}");
      _meta = {
        bakedAt: typeof raw.bakedAt === "string" ? raw.bakedAt : "",
        tickets: raw.tickets && typeof raw.tickets === "object" ? raw.tickets : {}
      };
    } catch (e) {
      _meta = { absent: true };
    }
    return _meta;
  }

  function metaFor(key) {
    var m = readMeta();
    if (m.absent || !m.tickets) return null;
    var t = m.tickets[key];
    return t && typeof t === "object" ? t : null;
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
  function refMs(bakedAt) {
    var r = bakedAt ? Date.parse(bakedAt) : NaN;
    return isNaN(r) ? NaN : r;
  }
  // Bucket the gap between the baked reference time and the ticket's last activity. No date → unknown
  // (never claims a freshness it can't back). Activity "after" bake (clock skew) clamps to freshest.
  function freshnessOf(entry, bakedAt) {
    var last = lastActivityMs(entry);
    if (isNaN(last)) return "unknown";
    var ref = refMs(bakedAt);
    if (isNaN(ref)) return "unknown";
    var diff = ref - last;
    if (diff < 0) diff = 0;
    if (diff < FRESH_24H) return "fresh";
    if (diff <= FRESH_7D) return "recent";
    if (diff <= FRESH_30D) return "moderate";
    return "stale";
  }
  // Human "3h ago" for the teaser/header (never a hard claim — pairs with the dated "as of").
  function ageString(entry, bakedAt) {
    var last = lastActivityMs(entry);
    if (isNaN(last)) return "";
    var ref = refMs(bakedAt);
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
  function freshTitle(entry, bakedAt) {
    var b = freshnessOf(entry, bakedAt);
    var age = ageString(entry, bakedAt);
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

  // ── inline element styles ─────────────────────────────────────────────────────
  var SHADOW_STYLE =
    ":host{display:inline;color-scheme:light dark}" +
    "a{color:currentColor;text-decoration:underline;text-underline-offset:2px;cursor:pointer}" +
    ".dot{display:inline-block;width:.55em;height:.55em;border-radius:50%;margin-right:.3em;" +
    "vertical-align:baseline;border:1px solid transparent;box-sizing:border-box}" +
    ".dot-fresh{background:#16a34a}" +
    ".dot-recent{background:#65a30d}" +
    ".dot-moderate{background:#d97706}" +
    ".dot-stale{background:#9ca3af}" +
    ".dot-unknown{background:transparent;border-color:currentColor;opacity:.55}" +
    ".tip{position:absolute;left:0;top:1.4em;z-index:2147483646;max-width:22rem;" +
    "padding:.4rem .55rem;border:1px solid;border-radius:.35rem;" +
    "background:Canvas;color:CanvasText;font:400 .8rem/1.35 system-ui,sans-serif;" +
    "white-space:normal;box-shadow:0 2px 8px rgba(0,0,0,.25)}" +
    ".tip[hidden]{display:none}" +
    ".wrap{position:relative;display:inline-block}" +
    ".t{font-weight:600;display:block}" +
    ".s{opacity:.8;display:block;margin-top:.15rem}" +
    ".la{opacity:.7;display:block;margin-top:.1rem;font-size:.92em}";

  var ProveTicket = class extends HTMLElement {
    connectedCallback() {
    if (this._rendered) return;
    this._rendered = true;
    var key = keyOf(this);
    var root = this.attachShadow ? this.attachShadow({ mode: "open" }) : null;
    if (!root) return;

    // Static skeleton only — NO baked/user strings via innerHTML (XSS). Dynamic text set below.
    var style = document.createElement("style");
    style.textContent = SHADOW_STYLE;
    root.appendChild(style);

    if (!key) {
      // Not a valid key: render the original text inertly, no link.
      root.appendChild(document.createTextNode(this.textContent || ""));
      return;
    }
    this._key = key;

    var wrap = document.createElement("span");
    wrap.className = "wrap";

    var meta = metaFor(key);
    var bakedAt = readMeta().bakedAt || "";
    var bucket = freshnessOf(meta, bakedAt);

    // Freshness dot (leading). Color is never alone: role=img + title/aria-label carry the fact.
    var dot = document.createElement("span");
    dot.className = "dot dot-" + bucket;
    dot.setAttribute("part", "dot");
    dot.setAttribute("role", "img");
    var dotLabel = freshTitle(meta, bakedAt);
    dot.setAttribute("title", dotLabel);
    dot.setAttribute("aria-label", dotLabel);

    var a = document.createElement("a");
    a.setAttribute("part", "link");
    a.setAttribute("href", TRACKER_ISSUE_BASE + key);
    a.setAttribute("target", "_blank");
    a.setAttribute("rel", "noopener noreferrer");
    a.setAttribute("aria-describedby", TIP_ID);
    a.setAttribute("aria-haspopup", "dialog");
    a.setAttribute("aria-expanded", "false");
    a.textContent = key; // textContent — never innerHTML
    this._anchor = a;

    var tip = document.createElement("span");
    tip.className = "tip";
    tip.id = TIP_ID;
    tip.setAttribute("role", "tooltip");
    tip.hidden = true;

    var line1 = document.createElement("span");
    line1.className = "t";
    var line2 = document.createElement("span");
    line2.className = "s";

    if (meta && typeof meta.title === "string" && meta.title.trim()) {
      line1.textContent = meta.title;                 // baked title — textContent-safe
      var status = typeof meta.status === "string" ? meta.status : "";
      // Status is a DATED fact, never presented as if live.
      var stamp = "status as of " + (bakedAt || "publish");
      line2.textContent = status ? stamp + ": " + status : stamp;
      tip.appendChild(line1);
      tip.appendChild(line2);
      var age = ageString(meta, bakedAt);
      if (age) {
        var line3 = document.createElement("span");
        line3.className = "la";
        line3.textContent = "last activity " + age;
        tip.appendChild(line3);
      }
    } else {
      // Link-only degradation: no metadata for this key (or blob absent).
      line1.textContent = "Open " + key + " in Linear";
      tip.appendChild(line1);
    }

    wrap.appendChild(dot);
    wrap.appendChild(a);
    wrap.appendChild(tip);
    root.appendChild(wrap);

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
    var self = this;
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

  // ── the shared anchored card ──────────────────────────────────────────────────
  var STATUS_HUE = {
    started: "#2563eb", completed: "#16a34a", canceled: "#6b7280",
    backlog: "#9ca3af", unstarted: "#8b5cf6", triage: "#d97706"
  };

  var CARD_STYLE =
    ":host{position:fixed;z-index:2147483647;color-scheme:light dark}" +
    ":host([hidden]){display:none}" +
    ".card{width:min(24rem,92vw);max-height:80vh;overflow:auto;box-sizing:border-box;" +
    "border:1px solid rgba(128,128,128,.4);border-radius:.6rem;background:Canvas;color:CanvasText;" +
    "font:400 .82rem/1.4 system-ui,sans-serif;box-shadow:0 8px 30px rgba(0,0,0,.35)}" +
    ".hd{padding:.6rem .7rem;border-bottom:1px solid rgba(128,128,128,.25)}" +
    ".hd-top{display:flex;align-items:center;gap:.4rem;flex-wrap:wrap}" +
    ".keylink{font-weight:700;color:currentColor;text-decoration:none}" +
    ".keylink:hover{text-decoration:underline}" +
    ".pill{font-size:.7rem;font-weight:700;color:#fff;padding:.05rem .4rem;border-radius:1rem;white-space:nowrap}" +
    ".title{font-weight:600;margin:.35rem 0 .25rem;display:block}" +
    ".metarow{display:flex;gap:.5rem;flex-wrap:wrap;opacity:.85;font-size:.74rem}" +
    ".fresh{display:inline-flex;align-items:center;gap:.3rem;font-size:.72rem;opacity:.9;margin-top:.3rem}" +
    ".fdot{width:.55em;height:.55em;border-radius:50%;border:1px solid transparent;box-sizing:border-box}" +
    ".fdot-fresh{background:#16a34a}.fdot-recent{background:#65a30d}.fdot-moderate{background:#d97706}" +
    ".fdot-stale{background:#9ca3af}.fdot-unknown{background:transparent;border-color:currentColor;opacity:.55}" +
    ".close{position:absolute;top:.4rem;right:.5rem;border:0;background:transparent;color:currentColor;" +
    "font-size:1.1rem;line-height:1;cursor:pointer;padding:.1rem .3rem;border-radius:.3rem}" +
    ".close:hover{background:rgba(128,128,128,.2)}" +
    "[role=tablist]{display:flex;gap:.2rem;padding:.35rem .5rem 0}" +
    "[role=tab]{border:0;background:transparent;color:currentColor;cursor:pointer;font:inherit;" +
    "padding:.3rem .55rem;border-radius:.35rem .35rem 0 0;opacity:.6}" +
    "[role=tab][aria-selected=true]{opacity:1;font-weight:700;box-shadow:inset 0 -2px 0 currentColor}" +
    "[role=tabpanel]{padding:.6rem .7rem}" +
    "[role=tabpanel][hidden]{display:none}" +
    ".desc{white-space:pre-wrap;opacity:.9}" +
    ".grid{display:grid;grid-template-columns:auto 1fr;gap:.15rem .6rem;margin-top:.5rem;font-size:.76rem}" +
    ".grid b{opacity:.6;font-weight:600}" +
    ".evts{list-style:none;margin:0;padding:0;max-height:14rem;overflow:auto}" +
    ".pt-evt{padding:.35rem 0;border-bottom:1px solid rgba(128,128,128,.18)}" +
    ".pt-evt-hd{display:flex;gap:.4rem;align-items:baseline;font-size:.72rem;opacity:.75}" +
    ".pt-evt-kind{font-weight:700;text-transform:uppercase;font-size:.62rem;letter-spacing:.03em;" +
    "padding:.02rem .3rem;border-radius:.25rem;border:1px solid currentColor}" +
    ".pt-evt--state .pt-evt-kind{opacity:.8}" +
    ".pt-evt--comment .pt-evt-kind{opacity:.6}" +
    ".pt-evt-text{margin-top:.15rem;white-space:pre-wrap}" +
    ".rels{display:flex;flex-wrap:wrap;gap:.35rem}" +
    ".pt-rel{border:1px solid rgba(128,128,128,.5);background:transparent;color:currentColor;" +
    "cursor:pointer;font:inherit;font-size:.74rem;padding:.2rem .5rem;border-radius:1rem}" +
    ".pt-rel:hover{background:rgba(128,128,128,.15)}" +
    ".empty{opacity:.6;font-style:italic}" +
    ".legend{padding:.4rem .7rem;border-top:1px solid rgba(128,128,128,.25);font-size:.66rem;opacity:.7;" +
    "display:flex;flex-wrap:wrap;gap:.5rem}" +
    ".legend span{display:inline-flex;align-items:center;gap:.25rem}" +
    ".legend i{width:.5em;height:.5em;border-radius:50%;display:inline-block;border:1px solid transparent}";

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
      var root = this.attachShadow ? this.attachShadow({ mode: "open" }) : null;
      if (!root) return;
      this._root = root;
      var style = document.createElement("style");
      style.textContent = CARD_STYLE;
      root.appendChild(style);
      this._activeTab = "overview";
      this._docHandlers = null;
    }

    // Open the card for `key`, anchored to `anchorEl`; remember it as the focus-return target.
    openFor(key, anchorEl) {
      this._opener = anchorEl || this._opener || null;
      this._activeTab = "overview";
      this.render(key);
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

    render(key) {
      this._key = key;
      var root = this._root;
      // Drop the previous content node (all its listeners go with it) — rebuild fresh. Keep <style>.
      if (this._content && this._content.parentNode) root.removeChild(this._content);
      var meta = metaFor(key);
      var bakedAt = readMeta().bakedAt || "";
      var card = el("div", "card");
      card.setAttribute("role", "dialog");
      card.setAttribute("aria-modal", "false");
      var titleId = "pt-card-title";
      card.setAttribute("aria-labelledby", titleId);

      // Close button
      var close = el("button", "close", "×");
      close.setAttribute("type", "button");
      close.setAttribute("aria-label", "Close");
      var self = this;
      close.addEventListener("click", function () { self.close(); });
      card.appendChild(close);

      card.appendChild(this.buildHeader(key, meta, bakedAt, titleId));
      card.appendChild(this.buildTablist());
      this._panels = {};
      card.appendChild(this.buildOverview(key, meta));
      card.appendChild(this.buildActivity(meta, bakedAt));
      card.appendChild(this.buildRelations(meta));
      card.appendChild(this.buildLegend());

      this.selectTab(this._activeTab, false);
      this._content = card;
      root.appendChild(card);
    }

    buildHeader(key, meta, bakedAt, titleId) {
      var hd = el("div", "hd");
      var top = el("div", "hd-top");
      var link = el("a", "keylink", key + " ↗");
      link.setAttribute("href", safeHref(meta && meta.url, key));
      link.setAttribute("target", "_blank");
      link.setAttribute("rel", "noopener noreferrer");
      top.appendChild(link);
      var status = meta && typeof meta.status === "string" ? meta.status : "";
      if (status) {
        var pill = el("span", "pill", status);
        var hue = STATUS_HUE[meta && meta.statusType] || "#6b7280";
        pill.style.background = hue;
        top.appendChild(pill);
      }
      hd.appendChild(top);

      var title = el("span", "title", (meta && typeof meta.title === "string" && meta.title) ? meta.title : ("Open " + key + " in Linear"));
      title.id = titleId;
      hd.appendChild(title);

      var metarow = el("div", "metarow");
      if (meta && meta.priority) metarow.appendChild(el("span", null, "Priority: " + meta.priority));
      if (meta && meta.assignee) metarow.appendChild(el("span", null, "Assignee: " + meta.assignee));
      if (meta && meta.project) metarow.appendChild(el("span", null, meta.project));
      if (metarow.childNodes.length) hd.appendChild(metarow);

      var bucket = freshnessOf(meta, bakedAt);
      var fresh = el("div", "fresh");
      var fdot = el("span", "fdot fdot-" + bucket);
      fresh.appendChild(fdot);
      var age = ageString(meta, bakedAt);
      var stamp = bakedAt ? " · as of " + bakedAt : "";
      fresh.appendChild(el("span", null, (age ? "last activity " + age : FRESHNESS_LABEL[bucket]) + stamp));
      hd.appendChild(fresh);
      return hd;
    }

    buildTablist() {
      var list = el("div");
      list.setAttribute("role", "tablist");
      list.setAttribute("aria-label", "Ticket detail sections");
      var self = this;
      this._tabs = {};
      TABS.forEach(function (t) {
        var b = el("button", null, t.label);
        b.setAttribute("type", "button");
        b.setAttribute("role", "tab");
        b.id = "pt-tab-" + t.id;
        b.setAttribute("aria-controls", "pt-panel-" + t.id);
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
      var p = el("section");
      p.setAttribute("role", "tabpanel");
      p.id = "pt-panel-" + id;
      p.setAttribute("aria-labelledby", "pt-tab-" + id);
      p.hidden = true;
      this._panels[id] = p;
      return p;
    }

    buildOverview(key, meta) {
      var p = this.makePanel("overview");
      var desc = (meta && typeof meta.description === "string" && meta.description.trim())
        ? meta.description.trim() : "";
      if (desc) p.appendChild(el("div", "desc", desc));
      else p.appendChild(el("div", "empty", "No description baked for " + key + "."));
      var grid = el("div", "grid");
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

    buildActivity(meta, bakedAt) {
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
        p.appendChild(el("div", "empty", "No recent activity baked."));
        return p;
      }
      var ul = el("ul", "evts");
      acts.forEach(function (ev) {
        var isState = ev && ev.kind === "state";
        var li = el("li", "pt-evt " + (isState ? "pt-evt--state" : "pt-evt--comment"));
        var head = el("div", "pt-evt-hd");
        head.appendChild(el("span", "pt-evt-kind", isState ? "State" : "Comment"));
        if (ev && ev.author) head.appendChild(el("span", null, ev.author));
        var one = { lastActivityAt: ev && ev.ts };
        var age = ageString(one, bakedAt);
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
        p.appendChild(el("div", "empty", "No related tickets baked."));
        return p;
      }
      var box = el("div", "rels");
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
      if (!box.childNodes.length) p.appendChild(el("div", "empty", "No related tickets baked."));
      else p.appendChild(box);
      return p;
    }

    buildLegend() {
      var lg = el("div", "legend");
      lg.setAttribute("aria-hidden", "true");
      [["fresh", "<24h"], ["recent", "≤7d"], ["moderate", "≤30d"], ["stale", ">30d"], ["unknown", "unknown"]]
        .forEach(function (pair) {
          var s = el("span");
          var i = el("i", "fdot-" + pair[0]);
          i.style.borderColor = "currentColor";
          s.appendChild(i);
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
      var root = this._root;
      var active = root && root.activeElement;
      var first = f[0], last = f[f.length - 1];
      if (e.shiftKey && active === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && active === last) { e.preventDefault(); first.focus(); }
    }
  };

  function defineElement() {
    if (typeof customElements === "undefined") return;
    if (!customElements.get("prove-ticket")) customElements.define("prove-ticket", ProveTicket);
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
    if (!node.nodeValue || node.nodeValue.indexOf("FIN-") === -1) return true;
    if (!SCAN_TEST_RE.test(node.nodeValue)) return true;
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

  function wrapTextNode(node) {
    var text = node.nodeValue;
    var re = /FIN-\d+/g;
    var frag = document.createDocumentFragment();
    var last = 0, m, matched = false;
    while ((m = re.exec(text))) {
      // Reject when a word char OR a hyphen sits directly against the key — `\b` alone admits a
      // leading/trailing hyphen (e.g. "report-FIN-5-draft" would wrap "FIN-5"). Rejected keys stay
      // as plain text: `last` is not advanced, so they fall into the next surrounding slice.
      var end = m.index + m[0].length;
      var before = m.index > 0 ? text.charAt(m.index - 1) : "";
      var after = end < text.length ? text.charAt(end) : "";
      if (/[\w-]/.test(before) || /[\w-]/.test(after)) continue;
      matched = true;
      if (m.index > last) frag.appendChild(document.createTextNode(text.slice(last, m.index)));
      var el = document.createElement("prove-ticket");
      el.setAttribute("key", m[0]);
      el.textContent = m[0];
      frag.appendChild(el);
      last = end;
    }
    if (!matched) return;
    if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
    if (node.parentNode) node.parentNode.replaceChild(frag, node);
  }

  // Auto-scanner (default ON). Idempotent: wrapped keys live inside <prove-ticket>, which is a
  // SKIP_TAG, so a second pass is a no-op. Collect first, mutate after (never edit mid-walk).
  function scan(root) {
    root = root || document.body;
    if (!root || typeof document.createTreeWalker !== "function") return;
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) { return skipTextNode(n) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT; }
    });
    var targets = [], n;
    while ((n = walker.nextNode())) targets.push(n);
    for (var i = 0; i < targets.length; i++) wrapTextNode(targets[i]);
  }

  function init() {
    defineElement();
    scan(document.body);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();

  window.ProveTicket = {
    scan: scan, define: defineElement, keyOf: keyOf, getCard: getCard,
    freshnessOf: freshnessOf, ageString: ageString, choosePlacement: choosePlacement,
    TRACKER_ISSUE_BASE: TRACKER_ISSUE_BASE
  };
})();
