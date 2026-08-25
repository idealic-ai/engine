# Decision Board Handoff Prompt — scaffold

The orchestrator fills this to dispatch the **Decision Board** render subagent at Outcomes (Phase 5). The board is the wave's **interactive decision surface**: it presents the trusted triage findings + the decisions to make, and collects steering answers/votes via widgets that copy a clean JSON payload back.

## What this document is — and what it is NOT

**This file is the HANDOFF CONTRACT** (`¶INV_BOARD_HANDOFF_IS_FIXED_PRESENTATION_IS_FREE`): it pins **WHAT every wave must surface** and the **mechanical contracts that cannot drift** (reference the widget kit; emit the payload schema; render panel marks as the kit reads them). That is its whole scope.

**It is NOT the composition guide, and it is NOT sufficient on its own.** The guide to building well against this contract is a different document — [`./KIT_README.md`](./KIT_README.md) — plus its two browsable galleries. An agent that reads only this file, because this file is the one that announces itself as authoritative, will hand-roll a look-alike: a flat list of option rows under a large bespoke `<style>` that re-implements the kit's palette and chrome from scratch, sharing none of it. **That has now happened.** The published board that triggered this rewrite contained `.mod` ×0, `.affgroup` ×0, roundels ×0, popovers ×0 — and ~12 KB of hand-written WARM-PRINT-ish CSS — while every kit link in its `<head>` resolved 200. Nothing failed. The composition simply never happened, because nobody told the author it was supposed to.

So: **"here is the contract" and "here is how to build well against it" are two different documents, and this is only the first one.** Step 1 below is not a see-also.

## Step 0 — COPY THE BOARD SKELETON (this is the first thing you write)

**[`./skeletons/decision-board.skeleton.html`](./skeletons/decision-board.skeleton.html) is a complete, already-composed board with slots to fill.** Copy it to `builds/<wave-slug>_DECISION_BOARD.html` and fill it. It is not a reference to admire and not a fragment to lift from — it is your starting artifact.

It arrives with: the five stylesheet links in the mandated order at the current versions · the `board-widgets.v2.js` script and deliberately no `kit-behaviors.js` · the fine-press page frame composed (running head · masthead · display opener · stat strip · 44px section rhythm · numbered `§` heads · ornament breaks · the marginalia rail · colophon · endmatter) · the required coverage already sectioned (scope, per-channel provenance, ranked candidates, consolidation ops, strays, dependency graph, the nothing-is-executed note) · `data-fb-item` **on** the `.mod` with `id` equal to it · the copy bar, the submit controls, and `__PROVE_STATE_CONFIG__` in place.

**Why this step exists.** Three boards in a row shipped as a flat list of hand-styled option rows under four resolving kit links. Every mechanism before this one was instruction-shaped, and *a parts list plus instructions produces the minimum arrangement that satisfies the instructions*. The skeleton is the floor: the failure signature — `.mod` at 0 with `data-fb-item` at N — is not reachable from it, because the two are the same element.

**Fill it, then cut it.** Delete the item kinds this wave does not have (no merges → cut §03; no strays → cut §04; no council poll → cut the panel legend). **Do not delete its density**: fewer findings means fewer specimens, not fewer margin notes, thinner ornament, or a dropped colophon. Extend it wherever the wave's content genuinely demands more.

Then continue to Step 1 — the skeleton gives you the composition, the kit gives you what goes inside it.

## Step 1 — READ THE KIT (mandatory, before you fill any slot)

Do this next, in this order. This is the same opening `prove/SKILL.md` §2 gives a proof page; a board and a proof page are one system and compose the same way.

1. **READ [`./KIT_README.md`](./KIT_README.md) FULLY.** Not skimmed, not grepped for a class name. The load-bearing sections for a board: §1 the design system + the **honest-presentation rules** · §2a the `.mod` block catalog (18 blocks) · §2c the board kit itself · §2d the affordance rail · §2e the verdict pill + why-proven · §2g stakeholder roundels + the sticky action bar · **§3.0 the skeletons** (the starting artifacts — Step 0) · **§3b the canonical board recipe** · §3c decisions ride the creative layout · §3d the archetype recipes · §3e the 25-pattern creative catalog · §5 versioning (authoritative for filenames + version numbers — never guess a version).
2. **OPEN both galleries** — [`./PROOF_BLOCKS.html`](./PROOF_BLOCKS.html) (every static block, live) and [`./CREATIVE_LAYOUTS.html`](./CREATIVE_LAYOUTS.html) (all 25 layout patterns as real, browsable markup). These are the *rendered* reference: read the actual markup of the pattern you intend to adapt. Where a gallery exemplar and a `KIT_README` caption disagree, **the exemplar wins**.
3. **THEN load `Skill(artifact-design)`** to calibrate how much design investment this board warrants, and follow both.

**Where the composition CSS actually lives — read this before you conclude the kit doesn't cover your layout.** Two files, and between them they cover almost everything you will reach for. `proof-blocks.css` ships the `.mod` skeleton, the affordance rail, the popovers, roundels, verdict pill, legends and the block catalog. `proof-creative.css` ships the **§3e creative-layout patterns** — all 25, scoped under `.fam-hero` / `.fam-comparison` / `.fam-dataviz` / `.fam-annotated` / `.fam-narrative` / `.fam-provenance`. **Link it, put the family's wrapper class on the section, write the pattern's markup, and the geometry arrives with it — do not retype it.** The `.fam-*` prefix is load-bearing, not decoration: the six families collide on `.caption`, `.legend`, `.dot`, `.n`, `.sw`, `.cell` and `.step`, and the wrapper is the only thing keeping one family's geometry out of another's — which is also what lets a board mix as many families as it likes.

So the ban is simple and total: **re-implementing anything either file already gives you is the failure mode.** Genuinely bespoke layout CSS for this board's own content is fine and expected — the line is duplication, not size.

**HOW it looks is still the render agent's creative call** — but "creative" means *composed from the kit*, not *invented from a blank canvas*.

**The handoff is structured but NON-LOSSY** (`¶INV_HANDOFF_STRUCTURED_NOT_LOSSY`): each finding is a fixed-field envelope, but the FULL triage reports + working doc travel with it (pointers below), and the agent **presents from the full sources, not a digest**. The orchestrator organizes + points; it never compresses facts away.

**Trust the curation** (`¶INV_BOARD_TRUSTS_ORCHESTRATOR_CURATION`): the questions/options below were surfaced by the orchestrator. Present them faithfully; do NOT re-investigate whether they are the right questions — that is the wave's job, taken as given. Your only verification is presentational: real evidence, faithful captions, honest provenance (`¶INV_PROVE_FAITHFUL_PRESENTATION`).

Save the filled prompt to `builds/<wave-slug>-decision-board-handoff.md`; dispatch. The subagent writes `builds/<wave-slug>_DECISION_BOARD.html`; the orchestrator runs the integrity pass + publishes.

---

## Fill this

**Wave**
- **Project + domain goal**: […] · **Wave slug** `<wave-slug>` · **Wave** `<project> wave <n>`
- **Directions + Ticketing Strategy in force** (verbatim): […]
- **The wave ranking** (`¶INV_RANKING_WITH_PROOFS`): the ordered "pull first, and why" list — carry the **number behind each call** (blast-radius / corroboration / consolidation breadth) with its proof-pointers.

**Full sources that travel with this handoff** (present FROM these — pointers, not digests)
- **Triage reports**: `builds/inbox-triage-<id>.md` … (one per triaged item — the render agent reads them for the facts)
- **Working doc**: `INTAKE.md` `<path>` (the cross-scope understanding, root-cause map, dependency graph)
- **Origin comments / entity links**: […app URLs + FIN-keys + comment deep-links per item]

**The findings to decide — one envelope per finding** (fixed fields; content stays rich)
For EACH decision-open finding:
- **`id`**: `<origin-comment-id | FIN-key | op-id>` — the item's one identifier, reused everywhere rather than translated: it becomes the widget's `data-fb-item` **and** its HTML `id` (so `<board-url>#<id>` addresses this decision), the `item` field of any `vote`/`note` event, and the target of the announce's `[n]` ref. Keep it URL-safe and stable for the wave.
- **Problem** (crisp, one sentence) + **the number behind the call** (its blast-radius / corroboration evidence)
- **Priority / rank** (from the wave ranking)
- **The steering read** (from triage, FULL — legitimacy/confidence + still-open questions + what-to-measure-next; `¶INV_STEERING_NOT_SOLUTIONS` — options to react to, not manufactured solutions)
- **The options to offer** (orchestrator-polished from triage's suggestions): 3–5 `{key, label}` — e.g. `{needs-research, "Needs more research"}` · `{seems-like-a-ticket, "Seems like a ticket"}` · `{fold-into:FIN-1234, "Fold into FIN-1234"}` · `{measure:extraction-count, "Measure the extraction-failure count first"}`. Keys are stable machine ids (the payload carries keys, never labels).
- **Evidence pointers**: the triage report path + origin comment + entity app-URLs (render the real evidence — DB counts, screenshots, quoted log lines — never prose where you could show the artifact).
- **Provenance**: `trusted-upstream` (the triage verdict) vs `checked-here` (something confirmed for the presentation).
- **`also_worth_surfacing`** (overflow): anything that doesn't fit a field above — never drop it for lack of a slot.

**The consolidation ops to decide** (each an approve/reject widget)
For EACH proposed merge / supersede / connect / milestone-move: the op + **its reasoning** + **the evidence the destination already owns the problem** + the affected FIN-keys. `id` = op id.

**Carry the destination's own premise, not a one-line summary of it.** A merge is the highest-stakes operation on this board and the one a human confirm demonstrably fails to audit — the human confirms the *action*, not the *reasoning* behind it. Anyone ruling on it (a teammate, or a panel expert who cannot open the ticket) needs enough to actually judge: what the destination ticket claims the problem IS, and why this item is a facet of that rather than a neighbour of it. Prefer **under-merging to one wrong merge** — two tickets that should have been one costs a little duplication; one merge that buries a real problem costs the system's credibility, and those are not symmetric.

**The stray tickets to adopt/cancel** (each an adopt-or-cancel widget; `¶INV_ADOPT_OR_CANCEL_STRAYS`)
For EACH stray (a non-Inbox ticket lacking wave-provenance): the ticket + its triage finding + the **candidate target milestone** (for adopt) + the **cancel rationale** (if the recommendation is cancel). `id` = FIN-key.

**The panel's votes** (only when a `/council` poll ran this wave — omit the whole block otherwise)
The council run's `votes[]` verbatim, plus the run's `rosterVersion` and `report_path`. Per vote: `item` · `key` · `lens` · `icon` · `weight` (1–5) · `why` · `alternative` · `thinGrounds`. Render these as panel marks per Mechanical contract 3 — **one mark per expert, never an aggregate**. Hand them over unedited: the render agent presents the panel's read, it does not summarise, average, or filter it, and an expert that flagged thin grounds must still appear as having done so.

**The dependency / root-cause graph**
The problem map to render as a diagram (nodes = problems/solutions; edges = stands-on / blocked-by / unlocks). Source: `INTAKE.md`'s dependency graph. Real nodes only.

---

## Mechanical contracts (these cannot drift — the kit reference, the payload, and the panel-mark markup are fixed)

**1. Reference the shared widget kit — do NOT inline it.** In `<head>`, write exactly these five stylesheet links **IN THIS ORDER** — tokens → block catalog → layout patterns → kit → overrides:
- `<link rel="stylesheet" href="__FB_KIT_BASE__/proof-theme.v2.css">` (the design-system tokens **and the fine-press atmosphere** — FIRST)
- `<link rel="stylesheet" href="__FB_KIT_BASE__/proof-blocks.v2.css">` (the `.mod` block catalog, affordance rail, popovers, roundels, verdict pill, legends — **the file that makes a composed board look composed**)
- `<link rel="stylesheet" href="__FB_KIT_BASE__/proof-creative.v1.css">` (the 25 `.fam-*` layout patterns — **the file that makes a composed board look designed**; without it a `fam-hero` / `fam-comparison` wrapper is inert markup and you get a flat list)
- `<link rel="stylesheet" href="__FB_KIT_BASE__/board-widgets.v2.css">` (the kit's must-work styles for the `data-fb-*` widgets)
- `<link rel="stylesheet" href="__FB_KIT_BASE__/board-warm-overrides.v2.css">` (the WARM PRINT restyle of the `--fb-*` seam — LAST so its `:root` overrides win)

**Why this order** (one line, since a future author will be tempted to shuffle it): only ONE pair has a genuine load-order dependency — `board-warm-overrides` must follow `board-widgets`, because both declare the same `--fb-*` properties on `:root` and later wins; `proof-blocks` is orthogonal (its `:root` declares only `--emboss-hi --letterpress --on-accent --shadow-card --shadow-deep`, and its 474 other selectors share **nothing** with `board-widgets.css` — checked, not assumed), so it is placed right after the tokens it consumes to match the documented theme → blocks → component order that `prove/SKILL.md` §5 gives a proof page. One system, one order.

**Without `proof-blocks.v2.css` every `.mod` block, affordance rail, popover and roundel you compose renders as unstyled markup** — which is precisely the state that makes a hand-written `<style>` feel necessary. It is not optional apparatus; it is the composition layer.

And the kit script, at end of body:
- `<script src="__FB_KIT_BASE__/board-widgets.v2.js"></script>`

**`kit-behaviors.js` — deliberately NOT loaded on a board. Do not "complete the set" by adding it.** It wires the *decision layer*: `[data-decision-item]` item scopes, `.vseg` / `.fbopt` vote inputs, `.noteaff` notes, `.submitbtn[data-submit]` per-person submit, the `.ava` / `.cnt[data-prog]` action bar, a global `beforeunload` dirty guard and a `#view-<key>` hash filter. **A board adopts none of those hooks** — it votes through `data-fb-*` and submits through `data-fb-submit`, which `board-widgets.js` owns. The `.mod` affordance rails you *will* use are native `popover`, zero-JS, and need no script at all. And the omission is not merely economy: `proof-blocks.css` styles `.fbopt` while `board-widgets.css` styles `.fb-opt` — one hyphen apart. If an author reaches for the catalog's decision-layer classes to style vote rows *and* the script is loaded, those rows quietly become a second, competing vote system with a dirty guard the board's own submit never clears. Leaving the script off keeps that a styling mistake instead of a behavioural one. (If a board ever genuinely needs the §2g action bar's stepper, that is a conversation with the kit's owner, not a unilateral `<script>` tag.)

`__FB_KIT_BASE__` is substituted by `publish-s3.sh` at publish time, when the bucket, region and prefix are all known — do not compute a URL yourself, and do not inline the files as a "safer" fallback. **An unpublished board is meant to look broken**: the unresolved token is the signal, and a plausible-looking wrong URL would not be.

*Why this is not inlining any more, since it reads like a regression:* an inlined kit meant a published board carried the kit it was built with **forever** and could never receive a fix. The kit now lives at one versioned address (`publish-kit.sh`), so republishing it reaches every board pointing at that major. The version tracks the payload version the kit emits, so a breaking payload change mints v3 at a new key and leaves v2 boards working.

**The trade, stated so nobody reverses it by accident**: a board is no longer a single file that works anywhere. It works **from the S3 host**. Opened from disk it renders and does not function. That was accepted deliberately in exchange for updatability.

Boards that render `FIN-` keys may additionally reference the ticket-preview kit, at its own
version (it is deliberately versioned apart from the widget kit — they share nothing):
- `<link rel="stylesheet" href="__FB_KIT_BASE__/proof-ticket.v4.css">`
- `<script src="__FB_KIT_BASE__/proof-ticket.v4.js"></script>`

Both, not just the script: `proof-ticket.js` is behavior-only and injects no stylesheet, so a board
that loads the script without the matching CSS renders its ticket cards unstyled. The two ride the
same version.

**1b. The swipe accelerator (`board-swipe`) — reference it when, and only when, the board carries a
binary item.** A board with at least one `data-fb-kind="consolidation"` or `"adopt-cancel"` item may
additionally reference:
- `<link rel="stylesheet" href="__FB_KIT_BASE__/board-swipe.v1.css">`
- `<script src="__FB_KIT_BASE__/board-swipe.v1.js"></script>` — **after** `board-widgets.v2.js`

Both files or neither; the JS injects no `<style>`, so the script alone renders an unstyled control.
On a **steer-only** board it binds nothing and is dead weight — cut it.

What it does: for each binary item it injects a 46px **decide bar** directly above that item's
`.fb-options`. Drag the bar right to pick the affirmative option, left to pick the negative, and it
commits by calling `input.click()` on the option row's own input. **It is therefore the click path**,
not an imitation of it — the emitted `vote` event is byte-identical to the one a click produces, and
`SCHEMA_VERSION` does not move.

The four properties you must not undo when you author around it:

- **It binds `consolidation` and `adopt-cancel` only, off the `data-fb-kind` you already write.**
  A `steer` item carries 3–5 options and has no left/right; it is left entirely untouched — no
  attribute, no injected node, no changed behavior. Do not invent a new attribute to opt items in,
  and do not relabel a steer item as binary to "get the gesture".
- **The rows stay PRIMARY.** The bar is an accelerator layered over a working base. Every option row
  stays visible, clickable and keyboard-reachable, and the whole thing is scoped under an
  `html.board-swipe-on` class only the script sets — so with JS off the stylesheet is inert and the
  rows are plain native form controls. Never hide, collapse or restyle `.fb-opt` to "make room".
- **The note is untouched.** `textarea[data-fb-note]` renders exactly as `board-widgets` ships it,
  at every point — before deciding, while deciding and after. (You cannot type while dragging, and a
  reject is precisely when a note matters most.) The bar carries a `Note ↓` tap target that focuses
  it; that is a shortcut to the textarea, not a replacement for it.
- **There is no vertical gesture, and there must never be one.** The bar declares
  `touch-action: pan-y` on its own 46px strip and nothing else on the page declares any. `none` was
  measured at **0px** of page scroll over a card (vs −19,853px off-card in the same run) — a board of
  ~1000px items would become scroll-blind by touch. A pass is a tap target or it is simply scrolling
  on; it is never a swipe.

And the shape of the gesture, since a future author will be tempted to make it more card-like: **the
item never moves.** No rotation, no fling, no transform on the block — those are borrowed from photo
cards and they slide a ~1000px argument out of the viewport, which is what the experiment measured.
Only the bar's thumb translates, at most 44px, and the directional feedback (edge wash + the two
option labels) lives on the bar itself, under the reader's finger, where it cannot scroll away from
the gesture that produced it.

**Loading the two files is necessary and not sufficient.** They buy the chip: the auto-scanner wraps
bare `FIN-\d+` text so it stops looking like a default-blue anchor. They do not buy the *metadata* —
`proof-ticket.js` reads status, freshness and activity from an inline `<script id="prove-tickets">`
blob and **never fetches** (a shared S3 page has no credential and no CORS route to the tracker).
With the files loaded and no blob, every key on the board still degrades to an `unknown` dot and a
minimal card. Something at publish time has to bake the blob — see **Bake the ticket metadata**
under *Integrity pass + publish*. Never hand-write the blob; `bake-tickets.sh --inject` owns it.

One consequence worth holding while you author: the scanner's `SKIP_TAGS` are
`A · CODE · PRE · SCRIPT · STYLE · TEXTAREA · INPUT · PROVE-TICKET*`. **A key you write as your own
`<a href="https://linear.app/…">FIN-2226</a>` is skipped and stays a plain link** — the component
only decorates keys left as bare text. Write `FIN-2226` and let the component build the permalink;
reach for a hand-written anchor only when the link target is not the ticket itself (a comment
deep-link, `§FMT_TICKET_COMMENT_LINK`).

All of these — `proof-theme.v2.css`, `proof-blocks.v2.css`, `proof-creative.v1.css`, `board-widgets.v2.{css,js}`,
`board-warm-overrides.v2.css`, `proof-ticket.v4.{js,css}` and `board-swipe.v1.{js,css}` — are uploaded
by `publish-kit.sh` (eleven objects in total; the one a board never references is
`kit-behaviors.v1.js`). Reference only files that script publishes: a `href`/`src` pointing at an object nobody
uploads is a 404 with no error anywhere — a board that silently falls back to the default
(non-WARM-PRINT) look, or dead tooltips. Version numbers come from `KIT_README` §5, which is
authoritative; where `KIT_README` and the shipped files disagree, **the files win** and the drift is
reported, not silently accommodated.

**1a. The completeness check — presence is not completeness.** Every ref you wrote resolving `200` proves
only that *what you referenced* exists. It says nothing about whether you referenced the *right set*, and
that is the failure this contract keeps hitting: three boards in a row shipped fully green while each was
missing a different kit file — the first the WARM PRINT overrides, the second the block catalog, the third
the composition guide itself. **A board can be 100% green on resolution and still be missing half the
system.** So run the check in the other direction, before you publish:

> Walk the markup you actually wrote, and for each family of thing on the page name the kit file that
> styles or drives it. `.mod` / `.mod-head` / `.mod-foot` / `.affgroup` / `.evpop` / `.roundel` /
> `.verdict` / `legend` → `proof-blocks.v2.css`. `data-fb-*` widgets, marks, copy bar, submit →
> `board-widgets.v2.{css,js}` + `board-warm-overrides.v2.css`. Any `var(--…)` token → `proof-theme.v2.css`.
> `FIN-` keys → `proof-ticket.v4.{css,js}`. A `consolidation` / `adopt-cancel` item you want the drag
> accelerator on → `board-swipe.v1.{js,css}`. A §3e creative pattern → its scoped CSS, carried in your own
> `<style>`. **If any family on your page has no file behind it, you are missing a ref — or you hand-rolled
> something the kit already ships.** Both answers are findings; neither is "it rendered fine."

Say the result out loud in your return: which kit files this board needs, and why each one is needed. An
unreferenced-but-needed file and an unneeded-but-referenced file are both worth naming.

**1b. The shared-state config — standard markup on every board.** Write it on every board, exactly:
```html
<script id="prove-state-config" data-fb-state-config type="application/json">__PROVE_STATE_CONFIG__</script>
```
`publish-s3.sh` replaces `__PROVE_STATE_CONFIG__` with the real config at publish time — the same
reason as the kit token: it is the only moment the bucket, the doc id and a signable credential all
exist together. Teammates then vote **in the page** instead of copying a payload into chat.

**The config is two halves and only one of them is a credential.** The **read path** (`stateUrl`)
is public-read, free, permanent and carries no grant — and it is where a `/council` run's seeded
records land, so a board without it has nowhere to put them. The **write grant** (`postUrl` +
presigned `fields`) is credentialed and short-lived. Both ship on every board; that is a decided
posture, not an oversight.

**Omitting the block does not opt out** — publish appends the element itself when a board carries
no placeholder, so the token is a *placement* hint (put the config where your layout wants it), not
a request. What omission costs is the choice of where it lands, nothing else.

**Signing is never load-bearing.** If the presign fails at publish, the board still publishes with
a **read-only** config — `stateUrl` and no write grant — and the kit shows the verbatim reason on
the submit control. A board that cannot be written to is strictly better than no board.

**The write grant expires, and expiry is the normal state, not the exception.** It is bounded by
the publishing session's own credential — hours, not days — so most visitors arrive after it has
lapsed. That is why **the copy bar stays on every board**: it is the path that still works when
the presign is dead, when signing was unavailable at publish, or when a POST fails. Never remove
the copy bar because a board has a state config.

**2. Widget markup** — wire each decision with `data-fb-*` attributes; the kit reads them and emits the payload in `PAYLOAD_SCHEMA.md`:
- Board metadata (once, e.g. on `<body>`): `data-fb-board="<wave-slug>" data-fb-wave="<project> wave <n>"`
- **Honour two view params — the Slack announce links to them.** `?user=<name-slug>` surfaces that person's decisions first (the announce's *"Waiting on"* block hands each person **their** board rather than the whole board); `?inbox=<channel-slug>` filters to items that arrived through that inbox channel (the announce's signal-in counters link here). **Both MUST degrade to the normal full board when the slug is unrecognised** — an unknown or misspelled value shows everything rather than an empty page, because a filter that silently hides every item reads as a broken board. Until the render implements them the links still resolve and the params are simply inert: a safe state, but not a working one, so do not describe the filtering as available until it is.
- **Every widget container also carries `id="<the same value as its data-fb-item>"`** — one attribute, no new scheme. That makes each decision addressable as `<board-url>#<item-id>`, which is what lets a Slack announce link `[3]` straight at the decision it refers to and lets a threaded reply be attributed to that item as a `note` event keyed on the same id (`PAYLOAD_SCHEMA.md`). Purely additive: it changes no behaviour, and the kit continues to read `data-fb-item`, never the `id`. **The two must not diverge** — a mismatched `id` sends a reader to the wrong decision, and a reply cited against it tallies onto the wrong item.
- A steering widget (multi-select): a container `data-fb-item="<id>" id="<id>" data-fb-kind="steer"`, with one option row per choice and an optional `<textarea class="fb-note" data-fb-note>`. **Every option carries a one-line description** — the option keys are terse machine ids and the labels are short, so a picker with labels alone is a picker that gets guessed at. Put the *why-you'd-pick-this* on the row, not in a tooltip:
  ```html
  <label class="fb-opt">
    <input type="checkbox" data-fb-key="do-it-now">
    <span class="fb-opt-body">
      <span class="fb-opt-label">Do it now</span>
      <span class="fb-opt-desc">The four numbers are one query; every wave that runs first turns the baseline into a reconstruction.</span>
    </span>
    <span class="fb-panel"><!-- panel marks, if any --></span>
  </label>
  ```
  The description is the orchestrator's, drawn from the triage steering read — not invented by the render agent (`¶INV_BOARD_TRUSTS_ORCHESTRATOR_CURATION`). If the handoff gave an option no description, render the label alone rather than writing one.
- A consolidation widget: `data-fb-item="<op-id>" id="<op-id>" data-fb-kind="consolidation"` with two radios `<input type="radio" name="<op-id>" data-fb-key="approve">` / `data-fb-key="reject"`.
- An adopt-cancel widget: `data-fb-item="<FIN-key>" id="<FIN-key>" data-fb-kind="adopt-cancel"` with radios `data-fb-key="adopt"` / `data-fb-key="cancel"`, a `<select data-fb-field="milestone">…</select>` (adopt target), and `<input data-fb-field="reason">` (cancel reason).
- A copy bar (or let the kit auto-inject one): a `<button data-fb-copy>Copy answers</button>`, a `<input data-fb-voter>` for the voter name, a `<span data-fb-copied></span>`, and a `<pre data-fb-payload></pre>` (the always-visible payload, so copy works even if the clipboard API is blocked).
- **The submit controls** (every board carries the state-config block, so every board has them) — optionally place these yourself; the kit injects its own bar if you don't: `<button type="button" class="fb-submitbtn" data-fb-submit>Submit</button>` (posts this voter's answers to the shared doc) and `<span class="fb-statestatus" data-fb-state-status></span>` (where the kit writes submit / poll / expiry status). Placing them yourself is how you get them inside your own layout instead of appended to `<body>`. **Keep `class="fb-statestatus"`.** Unlike the option widgets — whose presentation is entirely yours — this element carries a *kit-owned* state: the kit toggles `.fb-pending` on it to mark "your answers are saved and waiting", and every style that state needs hangs off `.fb-statestatus`. The kit re-adds the class defensively, so omitting it is survivable rather than silent — but a board that supplies both controls also suppresses the kit's own bar, which is how an unclassed status once made a working fix look like a failure.
- **Where other people's marks land**: give each option row a slot `<span class="fb-panel" data-fb-marks="<option-key>"></span>` — the *same* span that holds the council marks for that key. The kit appends teammates' initials there and **never touches a `[data-fb-panel]` node**, so a poll cannot disturb the panel's read. Boards with no slots still work: the kit falls back to a `[data-fb-presence]` block it appends to the item container. Per-option slots read far better — put them in.

**3. Panel marks** (only when the orchestrator's handoff carries panel votes — omit entirely otherwise). One mark per expert per option, rendered **directly on the option picker**, never collapsed behind a control and never in a separate block. Each mark is a **focusable control** (`<button type="button">`), not a `<span>`:
- `data-fb-panel="<item-id>"` `data-fb-panel-key="<option-key>"` `data-fb-panel-lens="<persona name>"` `data-fb-panel-icon="<persona icon>"` `data-fb-panel-kind="<itemKind>"` `data-fb-panel-weight="1..5"` `data-fb-panel-why="<one line>"` `data-fb-panel-alt="<alternative, may be empty>"` `data-fb-panel-thin="true|false"`.
- Board-level, once: `data-fb-panel-roster="<rosterVersion>"` `data-fb-panel-report="<report path>"`.
- The mark's visible content is the **persona icon**; classes `fb-mark fb-mark-council` inside a `fb-markwrap`, with the expert's `why` in a sibling `.fb-mark-note`. The kit toggles `data-fb-panel-open` on click; the CSS also reveals on `:hover` and `:focus-visible`.
- **Marks are position-independent** — the item id lives on the attribute, so place them wherever the layout wants. But *always visible on the picker* is a decided constraint, not a preference: a reader must see the panel's read at the moment they choose.
- **Never render a count.** One mark per expert. An aggregate flattens a 3–2 split into "3 for this one" and hides the more informative outcome.
- **Never give a panel mark the same visual weight as a human's.** Icons are the council namespace; initials (`fb-mark-human`) are the human one. They must be distinguishable at a glance and by form, not by shade.

Design the widgets to look like whatever fits your layout — the kit only reads the `data-fb-*` attributes.

**Restyling: override the `--fb-*` variables, don't fight the kit.** The kit owns what must *work* (geometry, hit targets, focus, reachability, and the states that carry meaning — checked, conviction, thin-grounds); you own what must look *good*. The seam is a set of custom properties on `:root` — `--fb-fg`, `--fb-muted`, `--fb-border`, `--fb-surface`, `--fb-accent`, `--fb-council`, `--fb-human`, `--fb-note-bg`, `--fb-radius`, `--fb-shadow`, `--fb-mark-size` — each with a light and dark default. Override them in your `<style>` to restyle the whole widget set coherently. You may also override kit rules outright, but **do not remove** the reachability behaviours (focus reveal, click toggle) or the state distinctions: those are the parts a reader depends on, not decoration.

## Composition — build the board FROM the kit (`¶INV_BOARD_COMPOSES_FROM_KIT`)

You did Step 0, so the composition is already on disk; you did Step 1, so you have the kit in hand. What
follows is what the skeleton's structure MEANS — read it as the reasoning behind the file you copied, and
as the rule for anything you add to it. It is the same pipeline `prove/SKILL.md` §2 gives a proof page,
with one substitution: **the decision component a proof page embeds is, on a board, the documented
`data-fb-*` widget** — because the payload engine is fixed (next section). Everything *around* the vote is
composed exactly as a proof page composes.

**The synthesis, in one sentence:** *a board item is a `.mod` block that presents the evidence, with the
board-widgets `data-fb-*` option rows riding inside it, placed after the reader has seen the grounds.*
That is "decisions ride the creative layout" (`KIT_README` §3c) applied with the existing payload engine.

**1. Pick the board's archetype (`KIT_README` §3d) before filling the candidates section.** A wave has a *kind*, and
the archetype names the spine that carries it: a wave dominated by "what's wrong and why" is a
**Diagnosis** (the `claim-verdict` ledger as spine); a consolidation-heavy wave is a **Comparison** or an
**Audit / coverage** (a heatmap of what's covered vs. what's a gap); a wave that is mostly "what should we
do next" is a **Recommendation** (an annotated exhibit laying out the option space). Pick one, state it in
your return, and let it decide the opener and the spine. **A board is not automatically a flat list** —
that shape is a choice, and it is almost never the best one.

**2. Compose each item as a `.mod` block, not a row.** Every decision-open finding gets the `.mod`
skeleton (`KIT_README` §2a): `.mod-head` (eyebrow + slug + the affordance rail) · `.mod-body` (the
evidence, rendered) · `.mod-foot` (`prov:` / `as-of:` / `ref:` at rest, scaffold folded behind `ⓘ`). Reach
for the block that fits the finding's evidence — `bignum` when one number *is* the finding, `table --delta`
for a run of cases, `sequence --timeline` for a dated history, `code --term` for verbatim CLI, `quote` for
a reporter's own words, `diff` for a source delta, `claim-verdict` for the ledger spine. The block picker
in §2a is there to be used.

**3. Reach for a creative pattern per item (`KIT_README` §3e / `CREATIVE_LAYOUTS.html`), not one uniform
treatment for all thirteen.** A giant-number hero for the item whose blast radius is the headline; a
side-by-side + delta gutter for a before/after; an evidence-stack for a claim that is over-determined by
converging sources; a coverage heatmap for the consolidation ops; a vertical timeline for something that
has been marinating across waves. Adapt the pattern onto the `.mod` grammar and carry its scoped CSS (see
Step 1 — that CSS is not in `proof-blocks.css`). Varying the treatment is not decoration: it is how a
reader tells thirteen items apart and knows which one is the big one.

**4. Attach the apparatus only where a block earns it.**
- **The affordance rail** (`KIT_README` §2d) on any item that has evidence, tickets or an external ref:
  `[📎 Evidence·N | 🎫 Tickets·N | ↗ URL]` in `.mod-head`, ONE consolidated `<div popover class="evpop">`
  carrying all of that block's evidence rows (each with who · when · provenance), and the ticket popover
  carrying its **relation** label (Origin ticket / Related / Blocks / Blocked-by). This is where the
  triage-report paths, origin comment deep-links and entity app-URLs belong — **on the item, one click
  away**, instead of as a wall of bare links under it. Native `popover`, zero JS.
- **The verdict pill + why-proven** (`KIT_README` §2e) where an item carries a ruling that triage already
  reached — and the pill always opens onto its grounds + provenance. Kept out of the affordance group on
  purpose: the group is things you DO, the verdict is a fact about the block.
- **Stakeholder roundels** (`KIT_README` §2g) where an item concerns a named person — from the project's
  `## Stakeholders`. **The badge IS the label**: the name lives in the accessible name, never as a
  redundant "for X" beside it.
- **The `¶` perma** on every item, pointing at the item's own `id` (which equals its `data-fb-item` —
  see contract 2). That is the same anchor the Slack announce's `[n]` refs target.

**5. Place the vote inside the block, after the grounds.** The `data-fb-*` option rows are the *last*
thing in the item's `.mod-body` (or its own trailing region), so the reader meets the evidence first and
the ask second. A vote at the top of a block asks for a judgment before showing the grounds for one.

**6. Honest presentation carries over unchanged** (`KIT_README` §1 — these are load-bearing, not
stylistic): **color encodes a real fact and ships its legend** (any page using the freshness hues carries
the `legend --freshness` block; a tint that means nothing is banned); **color is never the only channel** —
the freshness dot keeps its non-color `data-fill` ramp (`full` / `three-quarter` / `half` / `quarter` /
`ring`) plus `role="img"` and a bucket-word `aria-label`; **small text uses `--ink-meta`, never
`--ink-faint`** (the latter is non-text only and fails AA); **dated facts stay dated** — an as-of date on
anything that could go stale, never presented as live. Consume tokens by name; no block hardcodes a hex.

**7. What is explicitly OUT of scope — do not "helpfully" migrate the board.** `KIT_README` §2f documents
newer **Verdict** / **single-select** / **multi-select** decision components (`.dckind`, `.vseg`, `.fbopt`,
`.census`, `.cmark`) backed by `proof-blocks.css` + `kit-behaviors.js`. **A board does NOT adopt them.**
They emit a different shape, and `board-widgets.js` is a cannot-drift surface whose `SCHEMA_VERSION = 2`
event stream the intake ingest folds — changing it is another owner's decision, not a composition call.
Use them on a proof page; on a board, the vote stays `data-fb-*`, exactly as the next section documents.
This is the fixed/free seam, stated once more so nobody crosses it while tidying: **presentation is free,
the payload is fixed.**

### Composition anti-patterns (name them, avoid them)

- **The hand-rolled look-alike** — writing a large inline `<style>` that re-implements the kit's palette,
  card chrome, rails and popovers from scratch. This is the failure that produced the board this rewrite
  exists to fix: ~12 KB of bespoke WARM-PRINT-ish CSS under four kit links that all resolved. A second
  implementation of the kit is a second source of truth, and it forks the instant the kit ships a fix.
  **A small amount of board-specific inline CSS is expected and fine** — a genuinely bespoke layout, a
  §3e pattern's scoped CSS, a one-off grid this wave needs. The line is not size, it is *duplication*:
  never re-create what `proof-blocks.css` / `proof-theme.css` / `board-widgets.css` already give you.
- **Blank-canvas composition** — opening an empty file, or assembling a board from blocks and patterns,
  when `./skeletons/decision-board.skeleton.html` is a finished one. The kit is the default, not a menu.
  A genuinely new pattern is built ON the `.mod` grammar and named, never freehanded around it.
- **The thin fill** — copying the skeleton and then deleting its density: the margin notes, the ornament
  breaks, the § numbering, the colophon, the provenance table, "because this wave was small". The
  skeleton's shape IS the design. A smaller wave has fewer specimens, not less frame.
- **Hand-retyping the kit** — pasting a copy of `proof-theme.css` / the block catalog / a kit script into
  the board "so it works from disk". It is *meant* not to work from disk. Reference the files.
- **The uniform flat list** — thirteen identical option-row cards in a column, whatever the wave contained.
  It is the shape you get by not picking an archetype, and it flattens a wave's most consequential item
  into the same visual weight as its smallest.
- **Evidence as a link dump** — a row of bare URLs under an item instead of an affordance rail with a
  consolidated evidence popover. The pointers travel with the handoff so they can be *presented*, not
  relayed.
- **Decorative color** — a palette applied because it looks warm. On a board color is a claim (freshness,
  status, verdict, blast radius) and it always has a legend and a real referent.
- **Migrating the vote** — swapping `data-fb-*` for the §2f decision components because they look newer.
  See point 7. Out of scope, and it silently breaks the ingest.

## Presentation (yours — load `Skill(artifact-design)`)
- **Required coverage** (present all, in whatever structure reads best): thesis line · `/prove` scope block (*evidence shows / out of scope / **rests on trusted upstream triage***) · **a "where the signals came from & how" provenance section** (per-channel counts of what drained this wave, how items were drained + triaged, the Directions in force) · ranked candidates each with the number behind the call + its steering widget · consolidation ops as approve/reject with reasoning + evidence · stray adopt/cancel widgets · the dependency graph · a closing "nothing is executed — these are decisions" note (`¶INV_INTAKE_DISPATCHES_NEVER_EXECUTES`). **When the handoff carries panel votes, also required**: a **legend** naming each seated expert's icon and lens, stating plainly that this is an AI panel's advisory read — one layer further from authority than a teammate's vote — and telling the reader that hovering, focusing or tapping a mark shows that expert's reasoning. A mark whose reasoning a reader cannot reach is a judgement delivered at a decision point with its audit trail hidden, which is worse than showing no panel at all; the reachability is not a nicety to trade away for a tidier layout.
- **Same-origin only**, theme-aware (light+dark), responsive. Honest `<title>` + favicon. The kit arrives from the board's own host (contract 1); **everything else stays inline** — no CDN, no external font, no remote image, no fetch. The property being preserved is *no cross-origin request*, which is what the integrity pass verifies; "one file" was the old means to it, not the goal. Wide blocks (tables, pipelines, heatmaps, code) scroll inside their own `overflow-x:auto` container so the page body never scrolls sideways.
- **The required coverage above says WHAT to surface; the Composition section says HOW to build it.** Render each required element as a composed `.mod` block — the scope block as `scope`, the provenance section with a `legend`, the ranked candidates as evidence-carrying blocks with their votes inside, the stat strip as `stat-strip`, the dependency graph as inline `<svg>` (never a diagram-language block: there is no third-party renderer on this page, and `<pre class="mermaid">` degrades to literal source text).

## Optional sections — a palette the ORCHESTRATOR picks from when filling this handoff
Deciding *what to surface* is a curation call the orchestrator owns (`¶INV_BOARD_TRUSTS_ORCHESTRATOR_CURATION`); the render agent is free in *how to present*, never in *whether to include*. So **you (the orchestrator), when you fill this handoff, name which of the sections below to include for THIS wave** — drawn from the real working-doc / triage data — and hand the agent that selected set. The agent then renders the required coverage **plus your selected optional sections**, and does NOT add or drop sections on its own. Omit a section by not selecting it — never leave the inclusion call to the render pass, or a Contested / One-way-doors section can be silently dropped with the integrity pass none the wiser. (The required coverage above always appears; these are additive.)
- **Numbers at a glance** — a stat strip: ingested · triaged · ripe · filed-candidates · merges · strays · total blast-radius (orgs/claims/users).
- **What changed since last wave** — new signal vs carried-over items, re-opened (un-resolved) threads, and any `## Directions` / Ticketing-Strategy change that re-opens prior judgments.
- **Contested / needs-alignment** — items where triage disagreed with the reporter, corroboration is split, or a `not-a-problem` call is doubtful. The ones that most need a human (and the vote).
- **Quick wins** — low-effort / high-leverage items to pull first (the 20/80 node), called out from the ranking.
- **Blocked / waiting-on** — items blocked on a decision or an external answer; name **who to ask** (from the project's `## Stakeholders`).
- **Stakeholder callouts** — per-item "who should weigh in", so the right person votes rather than the loudest.
- **Cross-cutting themes** — the root-cause clusters behind the dependency graph, if the graph alone doesn't make them legible.
- **Aging / staleness** — items marinating across several waves, nomination-rejections, rot made visible (honest, not just flattering volume).
- **Open questions for the room** — the still-unresolved questions triage surfaced, framed for discussion (pairs with the steering widgets).
- **Risk / one-way doors** — decisions that are hard to reverse (a cancel, a merge that loses a framing) flagged before they're confirmed.
- **What we're NOT doing** — explicit non-goals / out-of-scope-per-Directions parked items, surfaced so they're visible, not silently dropped.
- **Confidence & provenance legend** — a key for `trusted-upstream` vs `checked-here` and `[DB-confirmed]`/`[inferred]`/`[needs-source]`, if the board leans on those tags.

## Output contract
- WRITE the HTML to `builds/<wave-slug>_DECISION_BOARD.html` — a filled copy of `./skeletons/decision-board.skeleton.html`, with the `__FB_KIT_BASE__` token **unresolved** — publish substitutes it. Leaving the composed file as authored is deliberate: a re-publish to a different bucket then resolves afresh instead of inheriting the first one's URL. Notebook-log every ~5 tool calls via `engine log <session log path>`.
- RETURN a tight manifest: decisions surfaced (N candidates · M consolidations · K strays), the provenance counts (trusted-upstream / checked-here), any asset that failed, and the HTML path. **Plus the composition receipt**: the **skeleton you started from** and what you deleted from it (and why), the **archetype** you picked (and why it fits this wave), the `.mod` blocks + §3e patterns you used, the **completeness-check result** from contract 1a (which kit files this board needs and why each), and any CSS you wrote yourself with the reason it is not something the kit already ships. Do NOT dump the HTML/base64.

## Integrity pass + publish (orchestrator, after the subagent returns)
- **Composition pass (run this FIRST — it is the check that has been missing).** The integrity pass below verifies that what the board references resolves; it has never verified that the board was *composed*. Both prior boards passed it while carrying none of the kit. So before anything else, grep the composed HTML and read the counts: `.mod` · `.affgroup` · `popover` · `.roundel` · `.evpop` · `data-fb-item`. **`.mod` at 0 with `data-fb-item` at N is the signature of a hand-rolled look-alike** — the author wrote option rows and styled them himself. Then measure the board's own `<style>`: a few KB of genuinely bespoke layout is expected; a large block that re-declares the palette, card chrome, rails or popovers is the kit re-implemented, and the fix is to compose, not to trim the CSS. Also confirm the board still carries the skeleton's frame — `.sheet` · `.runhead` · `.sechead` (numbered) · `.flourish` · `.specimen` + `.mnote` · `.colophon` · `.endmatter`: a fill that stripped them produced a page, not a dossier, and that is the *other* half of this failure. Also run contract 1a's completeness check yourself — walk the markup, name the kit file behind each family, and confirm every needed file is referenced. A board that is green on resolution and empty on composition is the exact failure this pass exists to catch.
- **Integrity pass** (`¶INV_PROVE_FAITHFUL_PRESENTATION`): open the load-bearing renders yourself; confirm captions match assets, nothing oversells, provenance is honest, the scope block is unburied, **the kit reference resolves same-origin to the published versioned object and the board issues no cross-origin request** (this replaces the old "everything is inline, therefore nothing is fetched" reasoning — the property is unchanged, what you verify is not), and every widget's `data-fb-key` matches the option keys you authored (so the payload tallies correctly), and **every widget's `id` equals its own `data-fb-item`** — check the equality, not merely the presence: an `id` that exists but disagrees is worse than a missing one, because `<board-url>#<id>` then resolves to the wrong decision and a reply cited against it tallies onto the wrong item, both silently. Any `id` you publish in an announce ref must exist on this board. **When a panel ran, also check**: every `data-fb-panel-key` matches an option key you authored (a mark on a key that doesn't exist is a vote for nothing); the mark count equals the vote count you handed over (no expert silently dropped, none invented); every mark is focusable and its `why` reachable without hover; and the legend is present. Then open the board and confirm the panel's marks read as **advisory** rather than as a verdict — that judgement is yours and no attribute check can make it. Direct a targeted edit if anything is off.
- **Bake the ticket metadata (only if the board renders `FIN-` keys) — BEFORE you publish.** It edits the composed HTML in place, so it has to land before the upload; a board published unbaked shows every ticket as an `unknown` dot until it is re-baked and re-published. Three steps, in order — the same flow `/prove` §4 documents, against the board file:
  > 1. `~/.claude/skills/prove/assets/bake-tickets.sh --scan builds/<wave-slug>_DECISION_BOARD.html` — emits the deduped keys (it strips `<script>`/`<style>`/comments first, so re-baking an already-baked board does not harvest its own blob).
  > 2. For each key, `§CMD_READ_RELATED_TICKET` (`get_issue` + `list_comments`), normalised to the `KIT_README` §2b entry shape: `lastActivityAt = max(updatedAt, newest comment ts)`, `activity` = the newest **5** events only, each `text` trimmed. Never dump a full thread — the blob ships inline in every byte of the board.
  > 3. `bake-tickets.sh --inject builds/<wave-slug>_DECISION_BOARD.html --tickets <tickets.json>` — writes the blob in place, idempotently (a re-bake replaces, never appends).

  **Skipping the bake is a supported outcome, not a failure** — the component degrades to a working link with an `unknown` dot, and a board that says nothing about a ticket's state is a board that has not lied about it. **Fabricating metadata is not** (`¶INV_PROVE_FAITHFUL_PRESENTATION`): a baked `status`/`lastActivityAt` is a claim the board makes *in the tracker's voice*, so every value in the blob must have come from a real `get_issue` on that key. If you skip, say so in your return — do not leave it ambiguous whether the board is unbaked or the tickets are genuinely quiet.

  **On scale, before you reach for a cap.** The count that matters is *distinct keys*, not references, and the two are far apart on a real board: the wave-3 board carried **439 `FIN-` references that dedupe to 40 keys** — ~80 MCP calls, a routine publish step. `--scan` does the dedup for you. So **do not cap by default**: a partial bake renders some chips with real status and the rest with `unknown`, and the reader cannot tell a capped board from a stale one — which is precisely the ambiguity the honest all-or-nothing skip avoids. If a board is genuinely too large to bake, the honest levers are, in order: (a) drop keys the component will never decorate — anything appearing only inside `<a>`/`<code>`/`<pre>` is in `SKIP_TAGS` and its blob entry is dead weight (on that same board, ~13 of the 40 were in this class); (b) carry fewer ticket refs, which is usually a real finding about the board; (c) bake in full and accept the minutes. A silent cap is not on the list — if you cap, name the omitted keys in your return.

- **Publish the kit first, then the board**: `~/.claude/engine/skills/prove/assets/publish-kit.sh` (idempotent — it republishes the same versioned key, which is how a fix reaches existing boards), then `~/.claude/engine/skills/prove/assets/publish-s3.sh builds/<wave-slug>_DECISION_BOARD.html <wave-slug>-decisions` → capture the public URL. Order matters on a first publish: a board pointing at a kit that isn't there yet is a board with no behaviour.
- **Then open the published URL and confirm the widgets actually respond.** The kit is no longer inside the file, so "the HTML looks right" no longer implies it works — that inference was free under inlining and is not any more. Check a checkbox and watch the payload box populate; if the kit 404'd, this is the only place it shows. The Decision Board is **offered** (default yes), not silent. If `PROVE_S3_BUCKET` is unset, keep the `builds/` file + poke the user; never fabricate a URL.
