# Design System Config — WARM PRINT

The **workload** `/remix` runs its protocol against. The skill is the engine; this
manifest is the specific design system. Selected via `--config warm-print` (the default), or
by absolute path for a config that lives elsewhere. One config = one design system.

Fields the skill reads by name. Keep it a manifest, not prose — every value is something a
mode consumes.

## Identity
- **name**: `warm-print`
- **kit-base-token**: `__FB_KIT_BASE__` — the literal token pages carry unresolved; publish substitutes the real same-origin kit URL.
- **kit-dir**: `~/.claude/engine/skills/intake/assets/` — where the kit CSS/JS + skeletons live (resolve to an absolute path; do not hardcode `~/.claude` in composed pages).
- **kit-readme**: `<kit-dir>/KIT_README.md` — authoritative for block catalog, archetypes, versioning. Read at Setup.

## Corpus & Digest
- **corpus-root**: `<kit-dir>` + the published proof pages — the full body a cold agent would otherwise re-read (~632k tokens, ~71% presentation).
- **digest-dir**: `<kit-dir>/digest/` — the three durable dispatch files:
  - **preamble**: `PREAMBLE.md` — standing brief (invariants + discipline + return contract). Refresh: regenerate-whole.
  - **facts**: `FACTS.md` — append-only ledger, one line `id · claim · number · how measured · by whom`. Refresh: append-only, immutable.
  - **registry**: `REGISTRY.md` — vocabulary, one row `channel · values · meaning · reserved-for`. Refresh: append-only; a collision is a finding.

## Render Matrix
*Consumed by `page` Verify and `critique` Resolve. These numbers are WARM PRINT's; another system sets its own.*
- **themes**: `light`, `dark`
- **viewports**: `1400`, `390`
- **assert**: body-overflow AND per-element-clipping (name the clipper) — both, every render.
- **controls**: print a parser control before any contrast measurement; an isolation control before any layer-survival claim.

## Reserved Channels (REGISTRY seed)
*The vocabulary already settled for this system; new channels register before dispatch.*
- **colour** — values: per-page fact (owner · verdict · delta) — meaning: encodes a REAL fact, always with a legend — reserved-for: the fact the legend names.
- **fill-density / texture-pitch / areal-coverage / shape / position** — the mandatory non-colour channels that must carry any meaning colour carries.

## Thresholds
*The tunable specifics of the universal honesty invariants (which live in SKILL.md).*
- **depth-cap**: 1 depth treatment per composed unit (`¶INV_DS_DEPTH_IS_SCARCE`).
- **contrast-floor**: WCAG AA on the token's REAL composited ground (measured, with the parser control).
- **missing-marker**: an absent fact renders distinct from a false one and from a zero (`¶INV_DS_MISSING_NOT_EMPTY`).

## References
- **pitfalls**: `~/.claude/engine/skills/intake/.directives/PITFALLS.md` — read at Setup; several traps caught agents mid-page in this system.
- **archetypes / block catalog / skeletons**: per `<kit-readme>` (§2a blocks, §3d archetypes, §3.0 skeletons).
- **related tracker work**: `FIN-3566` (extract the /prove visual language into a prescribed theme + block catalog).
