# Summary — <chunk "<slug>" | Session: <topic>>

*FRAME OF MIND FOR THE SUBAGENT: You are writing an INWARD review report. You have read and distilled the trail. You TRUST the numbers from the log/git as recorded (you did not re-run them). The orchestrator will render this, run the two-way review (§4 agent-asks-you, §5 inverse-ask), and offer to save it. Be analytical, narrative-driven, and concise.*

> **⚠ CRITICAL INSTRUCTION REGARDING EXAMPLES:**
> The blockquoted `>` examples below are **ILLUSTRATIVE ONLY**. They use a fictional domain (a spaceship hyperdrive) to demonstrate the *shape and depth* of the expected output. **DO NOT copy, paraphrase, or pattern-match these examples.** Replace every section with the REAL details, files, and decisions from THIS specific body of work.

---

## Header
*One line: what this work was.*
> *(Illustrative — adapt, don't copy)*
> **Example:** Chunk 3 — Wire the hyperdrive flux-capacitor to the main nav-relay — ✅ done, green.

## Stat strip
*One glanceable row, computed deterministically (git numstat + git log + log-parsed tests + plan checkboxes). Numbers TRUSTED as recorded; label the source/time.*
> *(Illustrative — adapt, don't copy)*
> **Example:** `4 files · +212/−37 · 3 commits · tests 53→53 ✅ (as recorded 14:33) · 2/2 plan steps ✓ · 0 leftovers`

## Goal vs actual
*What the work was MEANT to do (from plan step / ticket / the original ask) vs what actually happened. Intent alignment in a short paragraph.*
> *(Illustrative — adapt, don't copy)*
> **Example:** **Goal:** Register the auto-coolant hook so the hyperdrive doesn't overheat on jump. **Actual:** Both hooks registered in the committed `engine_settings.json` (root cause of previous failure was an uncommitted edit that got reset); gate verified to deny jump on a synthetic overheated input. Aligned — no drift.

## The 'why' behind the moves
*The 3-4 major architectural/logical shifts and WHY each was necessary. This is intent-driven, NOT a diff-log of files touched. Tell the narrative arc of the chunk.*
> *(Illustrative — adapt, don't copy)*
> **Example:**
> - **Dropped structural type derivation for the nav-mesh.** The legacy code derived `hasCoordinates ? SECTOR : SUBSECTOR`; we dropped it because in the flat model, the prefix is authoritative. Re-deriving it structurally was causing silent routing bugs.
> - **Unified the nanoid in the jump-assembler** (over a data migration). **Why:** Avoids churning persisted jump-IDs in the database, which would have forced a massive, risky backfill across the fleet.

## Unresolved tensions
*Where the work compromised. Did you accept tech debt to move fast? Was an invariant left unasserted? Was a disagreement settled by fiat? What should a future reader know was NOT clean? (Write "None" if genuinely clean).*
> *(Illustrative — adapt, don't copy)*
> **Example:** Converted 2 out-of-declared-scope integration tests rather than escalating. They broke because the rule retargeted from `shield.type` to `hull.type`. Kept the edits surgical, but it crossed the strict file boundary; accepted this debt to keep the chunk moving.

## Leftovers / open
*Unfinished / deferred / open items. This is guidance for the next chunk, not filed tickets or fixes.*
> *(Illustrative — adapt, don't copy)*
> **Example:**
> - `/nav-sync` build still parked (plan written, not built).
> - No `settings.local.json` convention exists yet — hook experiments currently rely on committing shared settings.

## Confidence
*The agent's honest read + why. This is a judgment call, not a mathematical verification.*
> *(Illustrative — adapt, don't copy)*
> **Example:** 90% — Registration and scoped commits are solid and eyeballed. However, the "gate denies on overheated input" check was synthetic, not a live two-agent run.

---

## Agent-asks-you (proposed — orchestrator presents in §4)
*Up to 4 GENUINE uncertainties about whether the work matches intent — each citing a concrete artifact. Real questions, not trivia. Zero is a valid answer.*
> *(Illustrative — adapt, don't copy)*
> **Example:**
> 1. The supersede fix assumes one session = one live watcher. Is a multi-pane/same-session case real for your workflow? (touches `cmd_watch` in `ticket.sh`)
> 2. I left the engine `tools/` files uncommitted as "not mine" — was that the correct call, or did you want them included in this chunk? (`tools/statusline.sh`, `tools/shared/`)

---

## Inverse-ask (proposed — orchestrator presents in §5)
*Two layers. The THEME MAP is a WIDE coverage scaffold (~32 topics, ~8 per lens) — the space of what's askable — and GOVERNS the questions so they cover the real space. From it you SELECT the 16 best WELL-FORMED QUESTIONS the user picks (the 4×4 grid) — a choice from ~32, not a 1:1 lift. EVERY theme and question references a concrete artifact/decision/leftover from THIS work (`¶INV_INVERSE_ASK_IS_SPECIFIC`).*

> **⚠ DO NOT COPY OR PARAPHRASE ANY EXAMPLE.** This section carries **no example themes on purpose** — anything concrete would get pattern-matched instead of generated. Derive all ~32 themes from the ACTUAL trail you read: name this work's real files, functions, decisions, trade-offs, and leftovers. If a theme could apply to a different piece of work, it's too generic — cut it.

### Theme map (wide coverage scaffold — ~32 topics, ~8 per lens, mostly internal)
*Fill each lens with ~8 short topics (2–5 words each), every one naming a concrete artifact / decision / risk / open item from THIS work. This is the space you then SELECT the 16 questions from — generate more than you'll use.*
> - **Correctness:** <~8 topics about whether this work is correct — real functions/tests/edge-cases/races in it>
> - **Decisions:** <~8 topics about the choices made + their alternatives — real trade-offs from the trail>
> - **Risk:** <~8 topics about what could go wrong — real fragilities/assumptions/untested paths>
> - **Scope-&-Next:** <~8 topics about boundaries + what's next — real leftovers/parked items/adjacent work>

### The 16 well-formed questions (user-facing 4×4 — this is what the user picks)
*SELECT the 16 best from the ~32-theme map: 4 lenses × 4 contextual questions. Each must be phrased as a real question the user would ask, derived from a theme + a concrete artifact. Include a short answer sketch for fast answering when picked. Drop weaker/overlapping themes.*

#### Correctness
> - "<question naming a real artifact/behavior from this work>" *(sketch: <1–2 sentence answer from the trail>)*
> - "<…>" *(sketch: …)*
> - "<…>" *(sketch: …)*
> - "<…>" *(sketch: …)*

#### Decisions
> - "<question about a real choice + its alternative>" *(sketch: …)*
> - "<…>" *(sketch: …)*
> - "<…>" *(sketch: …)*
> - "<…>" *(sketch: …)*

#### Risk
> - "<question about a real fragility/assumption>" *(sketch: …)*
> - "<…>" *(sketch: …)*
> - "<…>" *(sketch: …)*
> - "<…>" *(sketch: …)*

#### Scope-&-Next
> - "<question about a real leftover/boundary/next-step>" *(sketch: …)*
> - "<…>" *(sketch: …)*
> - "<…>" *(sketch: …)*
> - "<…>" *(sketch: …)*

---

## Outcome
*(stamped by the orchestrator after §6.)*
- **Rendered:** <yes>
- **Agent-asks-you:** <N answered | none / skipped>
- **Inverse-ask:** <M of 16 questions answered>
- **Saved:** <path (chunk `<slug>_SUMMARY.md` | `SESSION_SUMMARY.md`) | not saved (draft at <reportPath>)>
