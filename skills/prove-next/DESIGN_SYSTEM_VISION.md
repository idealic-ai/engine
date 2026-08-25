# The iterative design system

**Status**: vision, written from a single day's practice (2026-08-01). Descriptive, not aspirational —
every claim below is something that happened, with the number it produced.

---

## 1. What this is

A **proof page is an argument made of evidence**, and the kit is the vocabulary it argues in. The
design system is not a stylesheet; it is the set of rules that keep a rendered page **honest** —
that stop it asserting more than its data supports, hiding what it cut, or encoding a fact in a
channel a reader cannot perceive.

The system has three layers, and only the middle one is CSS:

- **Contracts** — what a block *requires* before an author may reach for it, what it *unlocks*, what
  it *excludes*, and what it *degrades to*. 45 of them exist.
- **The kit** — tokens, blocks, creative patterns, live components. 343 KB raw / 87 KB gzip.
- **Checks** — the gates that make the contracts real rather than advisory.

The third layer is the young one, and it is the one that decides whether any of this survives.

---

## 2. The founding observation

> **Composers emit what something CONSUMES.**

Measured: the decision board's `data-fb-*` attributes appear **210 times** in output, because a
script reads them. The kit's documented relation attribute appears **0 times**, despite complete
documentation. A composed 814 KB proof page carries **12 `data-*` occurrences in total** — all
decision-layer, **none on any evidence block**.

The corollary governs everything else here: **instruction is not the lever; the slot is.** A rule
that no mechanism consumes is indistinguishable from no rule. This is why the system's centre of
gravity is moving from documentation toward checks.

---

## 3. The honesty rules

These are not style preferences. Each exists because its absence produced a page that lied.

- **Colour encodes a fact or it does not appear** — and every encoding carries a legend. The
  `legend` block is the one block with **no fallback**: if colour encodes a fact and there is no
  key, remove the colour.
- **A non-colour channel is mandatory** wherever colour carries meaning. Shape, fill density,
  texture pitch, areal coverage, position. Hue dies in greyscale and in every form of CVD; the
  others do not.
- **MISSING, not empty.** An absent fact must be visibly distinct from a false one, and from a
  zero. The corpus already contains the counter-example: a machine-readable file stores `{"n": 0}`
  identically for *never measurable* and *measured zero*.
- **Provenance is per-line, not per-entry** — a finding routinely mixes trusted-upstream numbers
  with checked-here ones, and one entry-level label lies about one of them.
- **Depth is a scarce signal, not a default surface.** Measured: four stacked wells = 271 px and 8
  horizontal edges; hairlines plus one accent rule = 197 px for the same four facts.
- **Every removal of a fact must be announced** — and an announcement can only be authored.
  Therefore **a stylesheet may only make cuts that need no announcement.** This restates
  `.cpv{overflow:hidden}` silently destroying 234 px of prose as a *governance violation*, not a bug.

---

## 4. The three parties

A page is produced by three actors with non-overlapping authority:

- **The stylesheet proposes.** It can wrap, hide, scroll or ellipsize. It **cannot shorten text** —
  a short form must be authored.
- **The author authorizes.** Only an author can say what is *said*, and only an author can announce
  a cut.
- **The checker vetoes.** Neither of the other two can *notice* a cut. Without the third,
  **a page can be simultaneously certified and lying.**

That third role is the system's newest and most important addition.

---

## 5. How the work actually goes

An orchestrator holds the design vocabulary and the rulings; specialist agents build pages in
isolation; the human adjudicates by eye. In one day this produced 22 rulings across ~20 agents.

**What the loop is good at**

- **Self-contained pages review instantly.** No server, no build. Eleven pages judged off `file://`
  in a morning is why the design converged as fast as it did.
- **The specimen is the test.** A page that renders the pattern proves the pattern renders, and can
  measure itself — contrast on its own pixels, 100 popover positions on its own DOM.
- **Isolation makes parallelism free.** File-disjoint pages meant seven concurrent agents with zero
  coordination cost.
- **A page can carry its own correction history.** One records `line → cut → bars → measured`, with
  the wrong published claim left standing beside the correction. A commit message cannot do that.

**What it costs**

- **Inlining tokens freezes the page.** Pages that inline `:root` become dated specimens the moment
  a token changes — and then quietly disagree with the kit.
- **Integration is the unpriced half.** Experimenting is cheap; folding the result back is not, and
  the bill arrives later.
- **A self-contained page cannot tell you whether its finding is about the kit or about itself.**
  Two agents reported kit defects that turned out to be local to their own page.
- **Isolation is also how vocabularies diverge.** Seven agents asked to converge produced four
  channel vocabularies that partly agree.

**The discipline that resolves it**: a page must declare whether it **inlines** the kit (a dated
specimen, frozen by design) or **links** it (a live demo that breaks loudly when the kit changes).
Today everything inlines, so nothing breaks loudly and nothing tracks.

---

## 6. Why looking is not optional

**33 distinct defects in one day — 27 found by looking, 6 by a check that refused.** The looser
claim this campaign repeated to itself ("twenty defects invisible to every check") does **not**
survive its own arithmetic: the reconciliation is short by 15, because the headline silently counted
only strands that reported a total and quietly excluded defects a check *did* catch. That failure is
itself the lesson — **a headline number survived a whole campaign and failed the first time anyone
added it up.** What follows is the defensible version.

The defects that automated checks could not see were not edge cases — a value label rendering `168` as `16`, a table hyphenating `article.mo|d`, nine
distinct shapes collapsing to identical marks, a grid pairing every label with the *previous* row's
number. Structural assertions passed on all of them.

The lesson two agents reached independently, hours apart and in almost the same words:

> **Assert the thing the reader loses, not a condition that usually accompanies it.**

One asserted an outline *existed* and passed a red ring on a red ground. One read
`scrollWidth > clientWidth` as *"an ellipsis was drawn."* And the canonical case: body-level
overflow measured **0 at every width** on two pages that were simultaneously destroying **234 px and
283 px** of prose — because ancestors clip. **The metric certified the pages it existed to catch.**

Defects sort into three classes, and they need different instruments:

| class | example | caught by |
|---|---|---|
| **geometry** | starved track, ragged heights, min-content floor | DOM assertions — *if* you assert the right property |
| **glyph** | ink-on-ink label, split token, clipped chip | pixels, or eyes |
| **semantic** | correct DOM saying the wrong thing | eyes only |

---

## 7. Where it is going

- **The producer.** The kit can now render intervals, matrices, rankings, receipts. Nothing produces
  the payloads. Layout choice is downstream of data shape, and the data is flattened to prose
  upstream — so this is the half that matters next.
- **The affordance check.** Compute what each entry's data *afforded* against what was *rendered*,
  and report the gap. It converts "the layouts go unused" from a taste complaint into a measurable
  defect. Report, never block — a checker that fights good judgment gets disabled.
- **The contract digest.** The full corpus costs an agent ~632 k tokens, of which **71 % is
  presentation**. Extracted, the contracts are ~10 k. The galleries stay human artifacts; the digest
  is what a composing agent reads.
- **Resolved-style review.** An overlay annotating a render with the computed values that produced
  it — the geometry class made visible at first build, when no golden exists to diff against.

---

## 8. What we know and have not fixed

Recorded because an unstated known defect is worse than an unknown one.

- One CSS subsystem is **24.9 % of the corpus and 86.4 % unreferenced** — built, guarded by tests,
  and not yet reachable from any page.
- The creative patterns are **entirely family-scoped**, and **no rule styles the wrapper itself** —
  so lifting a documented snippet yields *completely unstyled* markup, exactly as the galleries
  instruct authors to do.
- The theme defines 51 tokens, **all colour/material/type and zero spacing** — 263 `padding`
  declarations resolve to 170 distinct values.
- **6 of 25 patterns are unreachable** for want of any image in the corpus. That production point is
  upstream of every schema.
