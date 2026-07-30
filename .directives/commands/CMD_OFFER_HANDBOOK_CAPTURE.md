### ¶CMD_OFFER_HANDBOOK_CAPTURE
**Definition**: Offers to feed what this session learned about a **handbook recipe** back into that handbook — the intake-side sibling of `§CMD_MANAGE_DIRECTIVES`, which captures the same class of learning as engine-side invariants and pitfalls. Runs as a synthesis-pipeline (N.3) step. **It OFFERS, it never forces** (`¶INV_OFFER_DONT_FORCE_SKILLS`), and it **skips silently** when the session has nothing recipe-relevant to say.
**Concept**: "You just followed a documented recipe and found it wrong in places — want that written back?"
**Classification**: COLLAPSIBLE — presents nothing when it has no candidates.
**Trigger**: Declared in a caller's N.3 Pipeline steps, immediately after `§CMD_MANAGE_DIRECTIVES` (see **Callers**).

---

## The caller contract

The caller declares the step and supplies **nothing**. There is only one subject — this session, measured against the recipe it followed — so this command self-gathers everything: the project, the handbook's `## What triage will chase`, and the session's own evidence. One command, N callers, zero cross-reference.

---

## Algorithm

### Step 1: Relevance scan (the silent-skip gate)

Fire ONLY if the session **followed, contradicted, or materially extended a documented handbook recipe**. Positive signals — at least one required:

*   The session read or executed a project's `## What triage will chase` (an intake triage, an `/intake` wave, an `/inbox-triage` run).
*   It spent real effort rediscovering a fact the recipe should have stated (a table name, an id identity, an auth model, a retention window).
*   It hit a dead end the recipe should warn about, or found a recipe instruction wrong, mis-ordered, or unnecessary for the report shape it had.

**"The session learned something" is NOT a signal.** Engine-side rules and traps belong to `§CMD_MANAGE_DIRECTIVES` (`¶INV_*` / `¶PTF_*`); product-side procedures belong to a runbook. This step owns exactly one surface: the intake Inbox Handbook recipes.

No signal → **no output, no prompt**. Record `decision: "skipped"` and return. Prompting a session that cannot have a handbook learning is the failure mode this gate exists to prevent.

### Step 2: Offer

Present via `§CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT`, naming the project, the recipe, and the concrete learnings found — a bare "capture something?" is not an offer the user can judge.

*   **Capture it** → Step 3.
*   **Decline** → record `decision: "declined"`. Return.
*   **Defer** → record `decision: "deferred"`, one line in the session log. Return.

### Step 3: Hand off to `/inbox-handbook capture`

Invoke `Skill(inbox-handbook)` in capture mode over the session. That skill owns the work: the seven-bucket friction log, the Keep/Add/Cut delta, and the drop into the project's 🟦 Documentation channel. **This command never edits a handbook and never posts** — it decides whether to ask, and hands off.

### Step 4: Relay

Report where the delta landed (`§FMT_TICKET_COMMENT_LINK`) and the trail file (`§CMD_LINK_FILE`). If capture produced no applicable delta — evidence too thin to reduce to Keep/Add/Cut — say so plainly rather than posting a vague proposal. Record `decision: "ran"`.

---

## Constraints

*   **Offer, never force** (`¶INV_OFFER_DONT_FORCE_SKILLS`): no proof field gates the caller on capture having run. A declined or skipped offer is a complete, valid outcome.
*   **Silent skip is the common case.** Most sessions have no handbook learning. A step that prompts anyway gets removed from every array within a week.
*   **Boundary with `§CMD_MANAGE_DIRECTIVES`**: that command captures engine rules (`¶INV_*`) and traps (`¶PTF_*`) into `.directives/`. This one captures intake **procedure** into a Linear handbook. A learning that belongs in `PITFALLS.md` is not this command's.
*   **Proposes, never writes**: the handbook edit path is `/inbox-handbook`'s, gated on its own confirm. Nothing here mutates a document.
*   **Keep this file short.** It is preloaded on every N.3 transition of every adopting skill; length is a cost paid by every session.
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: the offer is `AskUserQuestion`, never bare text.

---

## Callers

*   **`/implement`** — Pipeline sub-phase `4.3`.
*   **`/fix`** — Pipeline sub-phase `5.3`.
*   **`/analyze`** — Pipeline sub-phase `3.4`. *(Not `3.3` — `/analyze` carries an extra Results Walk-Through sub-phase, so its Pipeline is the fourth, not the third. "N.3" is a convention, not a guarantee; read the label.)*

Twelve further protocol skills carry the 8-step pipeline array and have not adopted this step (`#needs-implementation`); see the adoption note in `CMD_RUN_SYNTHESIS_PIPELINE.md`.

---

## PROOF FOR §CMD_OFFER_HANDBOOK_CAPTURE

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "offerPresented": {
      "type": "string",
      "description": "Whether the offer was presented and on what (e.g., 'yes — Differ recipe, 3 learnings', or 'no — silent skip, no recipe-relevant signal')"
    },
    "decision": {
      "type": "string",
      "enum": ["ran", "declined", "deferred", "skipped"],
      "description": "ran (capture dispatched + relayed), declined, deferred (noted for later), or skipped (relevance scan found no candidates)"
    }
  },
  "required": ["offerPresented", "decision"],
  "additionalProperties": false
}
```
