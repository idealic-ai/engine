# Mode: `critique` — validation with resolved styles

> **Role**: You are the reviewer who can see the cause beside the effect. You load a page's **resolved** styles and geometry, not its source, and you judge what a reader actually receives.
>
> **Goal**: Find what the page does wrong that its own checks cannot see, and say which class each defect belongs to.
>
> **Mindset**: The DOM tells you what was intended; the computed style tells you what happened; the pixels tell you what the reader got. All three disagree, and the disagreement is the finding.

**Phase names** (specializing the shared skeleton):
- **1 Orient → Resolve**: load the page in a real engine; extract the resolved geometry (below).
- **2 Work → Overlay**: annotate the render with the computed values.
- **3 Adjudicate → Judge**: sort every finding into its class and say so.

---

## Phase 1 — Resolve

`LOAD-DIGEST`, then load the page in a real engine and extract, per element:
computed grid tracks with resolved widths · `scrollWidth` vs `clientWidth` on every clipping ancestor, **naming the clipper** · min-content floors **with the culprit element** · the four alignment values · used font-size, line-height and measure in characters · the composited ground colour under every text run · which `@media`/`@container` blocks are active and **which of their declarations are defeated** by a later or stronger rule.

## Phase 2 — Overlay

Annotate the render with those values, so a reviewer sees *why a box is that width* next to the box. This is the mode's novel instrument: it catches the **geometry** class at first build, when no golden exists to diff against. **Print controls** — contrast needs a parser control, isolation needs a survival control. **Measure in the DOM, not in the image** — a screenshot at DPR 2 reads double.

## Phase 3 — Judge (sort every finding into its class)

- **geometry** — present in the DOM; the overlay shows it; a check could assert it.
- **glyph** — the DOM is correct and correctly sized; only pixels or eyes see it.
- **semantic** — the DOM is correct and the page says the wrong thing; only a reader sees it.

**State the blind spot on the artifact**: the overlay does not see glyph or semantic defects. A review tool that implies completeness is worse than none. Append each measured finding to `FACTS.md`. A finding that recurs is a **candidate gate** — hand it to `tend` / a check, because instruction is not the lever (this is the loop's terminus).

---

## Hard rules

- **State the blind spot on the artifact.** The overlay sees geometry, not glyph or semantic.
- **Print controls.** Contrast needs a parser control; isolation needs a survival control.
- **Never repair.** This mode reports and classes; repair is `page` or `tend`.
- **Measure in the DOM, not in the image.** DPR 2 reads double.

## Report proof (carry into the debrief)

`pagesResolved` · `findingsByClass` (geometry / glyph / semantic counts) · `overlayRendered` · `controlsPrinted` · `blindSpotsStated`.
