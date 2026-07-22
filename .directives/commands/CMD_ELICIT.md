### ¶CMD_ELICIT
**Definition**: The **pure disclosure layer** — the mirror of `§CMD_INTERROGATE`. Where `§CMD_INTERROGATE` pulls information **out of the user** in structured rounds, `§CMD_ELICIT` pulls the **agent's own judgment out** and lays it on the table: for each item (a finding, an idea, an observation, an option-set) it builds a **Decision Card** (`§FMT_DECISION_CARD`), triages it on **severity × complexity** into an **advisory** attention class — `I've-got-this` / `Your-call` / `FYI` — and renders **cards-then-summary**. It then **hands off to the caller's own decision command** — it never collects the final decision and never auto-acts. The goal is to **kill the follow-up interrogation loop**: disclose up front what the user reliably asks for next (the trade-off of a recommendation, the scope, what's at stake, how to verify it cheaply) so the user judges from context instead of extracting it. INTERROGATE ends by collecting the user's input; ELICIT ends by disclosing the agent's — the *choice* that follows is the caller's, in the caller's own vocabulary.
**Trigger**: Called as a sub-step of `§CMD_WALK_THROUGH_RESULTS` (results mode) to disclose findings/results before the caller's triage; OR invoked directly (ad-hoc) whenever an agent is about to hand the user a set of findings, ideas, or decisions and wants to disclose-and-triage rather than dump a flat list. See `¶INV_DISCLOSE_AND_TRIAGE`.

**What ELICIT owns vs. what the caller owns:**
*   **ELICIT owns disclosure**: build the Decision Cards, run the severity×complexity triage, render **cards-then-summary**. The card's options and lean are disclosed *context* — *what you're weighing* — not the choice mechanism.
*   **The caller owns the decision**: after disclosure, the CALLER runs its **own** decision command in its **own** vocabulary — a `#needs-X` tag (`§CMD_TAG_TRIAGE` in the delegation walkthrough), fix/skip/defer (`/scrutinize`), address/ignore (`/pr`). ELICIT never maps its card options onto the `AskUserQuestion` choices and never auto-applies an `I've-got-this`.

**Invocation contexts** (same algorithm both ways — disclose, then hand off):
*   **Walkthrough sub-step**: `§CMD_WALK_THROUGH_RESULTS` (results mode) calls ELICIT to render the Decision Cards + triaged summary in place of the thin `§FMT_CONTEXT_BLOCK`. ELICIT produces the *content* (cards + framed options + triage); it then **falls through** to the walkthrough's own `§CMD_TAG_TRIAGE` loop, which places the tags. The walkthrough stays the orchestrator (granularity, looping, item extraction, tag placement + proof).
*   **Standalone (ad-hoc)**: run Build → Triage → Render directly, then hand the disclosure to whatever decision the agent's own flow makes next. No session, no markers, no tag placement required — the cards + triaged summary are the disclosure deliverable; the decision is made by the caller (or reported, if there's no interactive decision to collect).

---

## Algorithm

### Step 1 — Build a Decision Card per item

For every item (a finding, an idea, an observation, an option-set), assemble a `§FMT_DECISION_CARD`. The fields are **generalized off the fix-shape** so one card fits a proposed fix, a raw idea, or a neutral observation. The user's recurring follow-ups **are the fields** — front-load them so they never have to be asked for:

*   **Options** — 2–4 framed trade-offs: *do A → risk X; do B → risk Y but gain Z*. **Always include an honest "do nothing / defer"** where it is real. Never manufacture a fake option to look balanced. Options come **first** (anti-anchor, Step 4) — your POV lives in the lean, not a separate recommendation-first field.
*   **What's at stake** — the concrete consequence if left unaddressed: who/what it hits, how widely. (For a fix: the failure; for an idea: the missed upside; for an observation: what it implies.)
*   **Trade-off / cost of the recommendation** — what acting on your lean *costs or loses* (always paired with the lean, never omitted).
*   **Complexity / cost to act** — does acting add surface / muddy the design / bloat the build? Orthogonal to correctness (see Step 2).
*   **How to verify / validate** — the low-cost check that would confirm or *size* it (a read-only staging count, a one-line repro, a grep, a quick spike).
*   **Confidence** — your honest confidence in your own read. Load-bearing — it gates the triage (Step 2).
*   **Engagement** — the triage verdict from Step 2 (advisory): `I've-got-this` | `Your-call` | `FYI`.
*   **My lean** — your POV, stated *after* the options (Step 4): *"My lean: B, because… — but the strongest case against it is…"*. A defeasible recommendation, not a neutral dump — but never the anchor.
*   **Why you'd want to understand this** — one line, present on `Your-call` items: what makes it worth the user's attention (a one-way door? a load-bearing assumption? a domain rule?).

**Card depth scales with the bucket** (Step 2 governs which) — do the expensive analysis only where it pays off:
*   **`FYI`** → a **one-liner** (what + why-no-action). Cheap.
*   **`I've-got-this`** → a **one-line what + why** (never a bare count — see the guard). Cheap.
*   **`Your-call`** → the **full card**, every field. Few, expensive.

Triage-first ordering (Step 3) concentrates the cost on the handful of `Your-call`s.

### Step 2 — Triage on TWO axes (severity × complexity)

Triage is **severity × cost-to-act/complexity**, NOT severity alone. The catch that de-indiscriminates a flat findings list: **"clear to decide" ≠ "clean to apply."** An item can be *obviously correct* yet *bloat / muddy the implementation* when acted on. The class is **advisory** — it *orders the caller's attention*, it does not decide or authorize any action.

*   **`I've-got-this`** — **advisory "clear-cut"** verdict, all three required: HIGH confidence **AND** low severity **AND** low complexity. This means *the agent judges it clear enough that the caller MAY batch it if its own policy allows* — it is a **recommendation to batch**, never ELICIT auto-applying anything. The caller's decision command still owns the actual disposition.
*   **`Your-call`** — **real severity OR real complexity cost.** A clear-correctness item that carries complexity is a `Your-call` framed as a *worth-it?* judgment (act + carry the complexity, vs. accept the risk + keep it simple). This is precisely what stops "clear" items from silently bloating the build.
*   **`FYI`** — noted, no action recommended (trivia, doc nits, already-cleared).

**Confidence is the backstop.** Agent self-confidence is unreliable (proven: an agent can walk back things it personally endorsed one round earlier). So **low confidence never earns the `I've-got-this` recommendation**, regardless of how low the severity or complexity looks — it goes to `Your-call`. The triple gate on the advisory verdict exists because the only real danger in the two-axis rating is a false-*low* complexity or severity call; the confidence gate catches it.

### Step 3 — Render cards-then-summary (the disclosure)

Never assume the user read the artifact files — **brief them**. Emit in this exact order:

1.  **All Decision Cards, written out and skimmable first** — the pre-decision briefing (a readable written pass beats expand-on-demand). Ordered by engagement then severity so **`Your-call`s lead**, then `I've-got-this`, then `FYI`. Card depth per Step 1 (FYI/handled are one-liners; Your-calls are full).
2.  **A compact triaged summary** — one line: `N Your-calls to weigh · M clear-cut (batch-able) · K FYI`.

That is the whole ELICIT deliverable — cards + summary, in text. ELICIT **does not** render a decision `AskUserQuestion` of its own; the pickable choice belongs to the caller's decision command (Step 5). What ELICIT emits is disclosure the caller then decides *from*.

**No hidden items.** The collapsed `I've-got-this` and `FYI` buckets are **always visible** as titled one-liner lists — never a bare count, never silently hidden. A glance must be able to catch a mislabel *before* the caller acts on the advisory, and a systematic agent bias (e.g. always "simpler, skip it") must be able to surface and be challenged. Escalate-by-exception ≠ hide-by-default.

### Step 4 — Anti-anchor on `Your-call`

Leading with your recommendation invites rubber-stamping — the opposite of wanting the user's judgment where it matters. So on **every `Your-call`**:
1.  **Options first, neutral**, with their real trade-offs (the framed A→risk X; B→risk Y, gain Z; including the honest do-nothing).
2.  **THEN** a labeled, defeasible lean: *"My lean: B, because… — but the strongest case against it is…"*.

You still commit to a POV (a spineless "you decide" is not disclosure) — but the user's independent judgment stays engaged because the options and the counter-case are on the table before your lean is.

### Step 5 — Hand off to the caller's decision command

Disclosure done, **ELICIT hands off — it does not collect the final decision and does not auto-act.** The CALLER now runs its **own** decision command, informed by the cards + triage:

*   **Under `§CMD_WALK_THROUGH_RESULTS` (results mode)**: **fall through** to the walkthrough's `§CMD_TAG_TRIAGE` loop — the `Your-call`s get individual `#needs-X` tag attention; the `I've-got-this`/`FYI` sets can be batched per the walkthrough's Step 4. ELICIT rendered the cards; the walkthrough places the tags + emits tag proof.
*   **Under `/scrutinize`**: the user still decides **fix / skip / defer** per finding (`/scrutinize`'s invariant — *the user, not the model, decides*). The `I've-got-this` verdict is a suggestion the user may honor by fixing, never an auto-fix.
*   **Under `/pr`**: the disclosure feeds the **address / ignore** offer + the downstream `/scrutinize`·`/fix` chains. Read-only — no action taken.
*   **Standalone with no interactive decision**: the cards + summary are the deliverable — report them.

Emit the `## PROOF FOR` fields either way (they describe the *disclosure*, not a decision ELICIT made).

---

## Constraints

*   **Disclosure, not decision.** ELICIT discloses cards + triaged summary and classifies attention (advisory). It never collects the final decision and never auto-acts — the caller's own decision command does that (Step 5). When that caller collects the pickable decision it hands off to, that decision block MUST use `AskUserQuestion` per `¶INV_QUESTION_GATE_OVER_TEXT_GATE` — but the block is the caller's, in the caller's vocabulary, not ELICIT's.
*   **`¶INV_DISCLOSE_AND_TRIAGE`** (AGENTS.md): ELICIT is the wired expression of the disclosure philosophy — have a POV, front-load what's-at-stake / trade-off / complexity / how-to-verify, triage by severity×complexity, escalate by exception, brief with cards before the caller decides.
*   **Have a POV.** Every card carries a defeasible `my lean` (stated after the options). Neutral-findings dumps are the failure mode this command exists to kill — but the lean is disclosed *context*, never the choice mechanism.
*   **Never omit the paired trade-off.** A lean without its "what acting costs" is an under-brief — the user will just ask for it.
*   **Never manufacture a fake option** to look balanced. Real trade-offs only; the honest do-nothing when it's real.
*   **The `I've-got-this` verdict is advisory.** It requires HIGH confidence AND low severity AND low complexity — and even then it only *recommends* the caller may batch it. Low confidence never earns it. ELICIT never auto-applies it.
*   **Buckets always visible.** One-line what+why per `I've-got-this` / `FYI` item — never a bare count, never hidden.
*   **Anti-anchor on `Your-call`.** Options-first-neutral, then the defeasible lean + strongest counter. No lean-first framing on judgment calls.
*   **Card depth scales with bucket.** Don't spend a full card on an FYI; don't shortchange a `Your-call`.
*   **`¶INV_LISTS_INSTEAD_OF_TABLES`**: Cards and summaries render as named lists, never markdown tables.
*   **`¶INV_ESCAPE_BY_DEFAULT`**: Backtick-escape sigil/tag references in chat output.
*   **Hands off, doesn't own the choice.** ELICIT produces content (cards + framed options + triage); the caller's `§CMD_TAG_TRIAGE` / fix-skip-defer / address-ignore command is the choice-collection mechanic it hands off to — ELICIT does not drive or replace it.

---

## Hand-off — ELICIT owns no decision ask

ELICIT deliberately has **no** `AskUserQuestion` tree of its own. After the cards-then-summary (Step 3), the caller runs its own decision command (Step 5): `§CMD_TAG_TRIAGE` in the delegation walkthrough, fix/skip/defer in `/scrutinize`, address/ignore in `/pr`. The caller's block presents *its* vocabulary as the choices — ELICIT's card options are disclosed context that *inform* those choices, never the choices themselves. Natural-language shortcuts ("skip the FYIs", "hold the whole set") are honored by the caller's command, not here.

---

## PROOF FOR §CMD_ELICIT

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "itemsDisclosed": {
      "type": "string",
      "description": "Count of items disclosed as Decision Cards, and the field-completeness (all Your-calls carry every card field)"
    },
    "yourCalls": {
      "type": "string",
      "description": "The Your-call items surfaced for the caller's attention — count + one-line each, with the anti-anchor lean noted"
    },
    "handled": {
      "type": "string",
      "description": "The I've-got-this (advisory clear-cut) set — count + the one-line what+why per item (never a bare count); confirms the triple gate held on the advisory verdict"
    },
    "fyi": {
      "type": "string",
      "description": "The FYI items — count + one-line each (visible, not hidden)"
    },
    "handoff": {
      "type": "string",
      "description": "Which decision command the caller runs next informed by this disclosure (§CMD_TAG_TRIAGE / fix-skip-defer / address-ignore) — ELICIT collects no decision itself"
    }
  },
  "required": ["itemsDisclosed", "yourCalls", "handled", "fyi", "handoff"],
  "additionalProperties": false
}

*A caller MAY surface ELICIT's proof (`yourCalls` / `handled` / `fyi`) into its own synthesis proof — the disclosure is reusable evidence, not throwaway.*
```
