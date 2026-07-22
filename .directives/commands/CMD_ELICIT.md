### ¶CMD_ELICIT
**Definition**: The **pure disclosure layer** — the mirror of `§CMD_INTERROGATE`. Where `§CMD_INTERROGATE` pulls information **out of the user** in structured rounds, `§CMD_ELICIT` pulls the **agent's own judgment out** and lays it on the table: for each item (a finding, an idea, an observation, an option-set) it builds a **Decision Card** (`§FMT_DECISION_CARD`), triages it on **severity × complexity** into an **advisory** attention class — `I've-got-this` / `Your-call` / `FYI` — and renders each card **as its item's `AskUserQuestion` question body** (`§CMD_PRESENT_CARD_WITH_COMPLETE_CONTEXT`), with the caller's dispositions as that question's options (each leading with `§FMT_ANSWER_GRADATION`). It **still collects no final decision and never auto-acts** — the caller's own decision command owns what the pick *means*. The goal is to **kill the follow-up interrogation loop**: disclose up front what the user reliably asks for next (the trade-off of a recommendation, the scope, what's at stake, how to verify it cheaply) so the user judges from context instead of extracting it. INTERROGATE ends by collecting the user's input; ELICIT ends by disclosing the agent's — the *choice* that follows is the caller's, in the caller's own vocabulary.
**Trigger**: Called as a sub-step of `§CMD_WALK_THROUGH_RESULTS` (results mode) to disclose findings/results before the caller's triage; OR invoked directly (ad-hoc) whenever an agent is about to hand the user a set of findings, ideas, or decisions and wants to disclose-and-triage rather than dump a flat list. See `¶INV_DISCLOSE_AND_TRIAGE`.

**What ELICIT owns vs. what the caller owns:**
*   **ELICIT owns disclosure**: build the Decision Cards, run the severity×complexity triage, render each card **as its item's `AskUserQuestion` question body** (`§CMD_PRESENT_CARD_WITH_COMPLETE_CONTEXT`), and frame that question's answer options — the caller's dispositions — with `§FMT_ANSWER_GRADATION` (`★` carrying **My lean**, `○◑●` the card's **Confidence**). The card body and the gradation-tagged framing are disclosed *context* — *what you're weighing* and *how the agent reads it* — not the choice's meaning.
*   **The caller owns the decision**: the answer options are the CALLER's **own** vocabulary — a `#needs-X` tag (`§CMD_TAG_TRIAGE` in the delegation walkthrough), fix/skip/defer (`/scrutinize`), address/ignore (`/pr`). ELICIT frames those options inside its card body; the caller's command **interprets what the pick means** (places the tag, runs the fix, records the address). ELICIT never auto-applies an `I've-got-this`.

**Invocation contexts** (same algorithm both ways — disclose, then hand off):
*   **Walkthrough sub-step**: `§CMD_WALK_THROUGH_RESULTS` (results mode) calls ELICIT to render each Decision Card **as its item's `AskUserQuestion` question body** (`§CMD_PRESENT_CARD_WITH_COMPLETE_CONTEXT`) in place of the thin `§FMT_CONTEXT_BLOCK` — the walkthrough's `§CMD_TAG_TRIAGE` tags become that same question's answer options. ELICIT produces the *content* (card body + gradation-tagged option framing + triage); the walkthrough still **owns the tag placement + proof**. The walkthrough stays the orchestrator (granularity, looping, item extraction, tag placement + proof).
*   **Standalone (ad-hoc)**: run Build → Triage → Render directly — cards render as the question bodies — then let whatever decision the agent's own flow makes next interpret the picks. No session, no markers, no tag placement required — the cards (as question bodies) + the triaged summary lead-in are the disclosure deliverable; the decision's meaning is the caller's (or, if there's no interactive decision to collect, just report the cards).

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

### Step 3 — Render each card as its question body (the disclosure)

Never assume the user read the artifact files — **brief them**. The card no longer lands as chat text before a terse popup; it lands **inside** the question via `§CMD_PRESENT_CARD_WITH_COMPLETE_CONTEXT`:

1.  **A compact triaged summary lead-in** — one line before the call: `N Your-calls to weigh · M clear-cut (batch-able) · K FYI`, then the visible one-liner lists for the `I've-got-this` and `FYI` buckets (see *No hidden items*).
2.  **Each `Your-call` card AS an `AskUserQuestion` question body** (`§CMD_PRESENT_CARD_WITH_COMPLETE_CONTEXT`) — one item = one question, batched up to 4 per call, `Your-call`s leading. The body carries the full card (stakes, options, how-to-verify, lean); the answer options are the caller's dispositions, each leading with `§FMT_ANSWER_GRADATION` (Step 4). Card depth per Step 1 (FYI/handled stay one-liners; `Your-call`s are full).

ELICIT now **does** render the card AS the `AskUserQuestion` body — but the answer options are the caller's decision vocabulary (Step 5), and the caller's command still owns what a pick *means*. What ELICIT emits is disclosure the caller then decides *from*, now fused into one prompt instead of cards-in-chat then a separate terse popup.

**No hidden items.** The `I've-got-this` and `FYI` buckets are **always visible** as titled one-liner lists in the lead-in — never a bare count, never silently hidden. A glance must be able to catch a mislabel *before* the caller acts on the advisory, and a systematic agent bias (e.g. always "simpler, skip it") must be able to surface and be challenged. Escalate-by-exception ≠ hide-by-default.

### Step 4 — Anti-anchor on `Your-call`

Leading with your recommendation invites rubber-stamping — the opposite of wanting the user's judgment where it matters. So on **every `Your-call`**:
1.  **Options first, neutral**, with their real trade-offs (the framed A→risk X; B→risk Y, gain Z; including the honest do-nothing).
2.  **THEN** a labeled, defeasible lean: *"My lean: B, because… — but the strongest case against it is…"*.

You still commit to a POV (a spineless "you decide" is not disclosure) — but the user's independent judgment stays engaged because the options and the counter-case are on the table before your lean is.

In the rendered question, the lean surfaces as the single **`★`** on the recommended answer option (`§FMT_ANSWER_GRADATION`), and the card's **Confidence** surfaces as `○◑●` — the anti-anchor holds because the option order is neutral and the body's counter-case is read before the `★` is acted on.

### Step 5 — Hand off to the caller's decision command

**ELICIT hands off the choice's *meaning* — it does not collect the final decision and does not auto-act.** The card is the question body and the caller's dispositions are that same question's answer options (no separate popup follows); the CALLER's **own** decision command still interprets the pick, informed by the cards + triage:

*   **Under `§CMD_WALK_THROUGH_RESULTS` (results mode)**: the `§CMD_TAG_TRIAGE` `#needs-X` tags ARE the answer options on ELICIT's card-body questions — the `Your-call`s get individual tag attention; the `I've-got-this`/`FYI` sets can be batched per the walkthrough's Step 4. ELICIT rendered the cards + framed the options; the walkthrough places the tags + emits tag proof.
*   **Under `/scrutinize`**: the user still decides **fix / skip / defer** per finding (`/scrutinize`'s invariant — *the user, not the model, decides*). The `I've-got-this` verdict is a suggestion the user may honor by fixing, never an auto-fix.
*   **Under `/pr`**: the disclosure feeds the **address / ignore** offer + the downstream `/scrutinize`·`/fix` chains. Read-only — no action taken.
*   **Standalone with no interactive decision**: the cards + summary are the deliverable — report them.

Emit the `## PROOF FOR` fields either way (they describe the *disclosure*, not a decision ELICIT made).

---

## Constraints

*   **Disclosure, not decision.** ELICIT discloses cards (as `AskUserQuestion` question bodies per `§CMD_PRESENT_CARD_WITH_COMPLETE_CONTEXT`) + a triaged summary lead-in and classifies attention (advisory). It never collects the final decision's *meaning* and never auto-acts — the caller's own decision command does that (Step 5). The question satisfies `¶INV_QUESTION_GATE_OVER_TEXT_GATE`, but its answer options are the caller's vocabulary (tag / fix-skip-defer / address-ignore), framed by ELICIT and interpreted by the caller — not ELICIT's own choice.
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
*   **Hands off, doesn't own the choice.** ELICIT produces content (card-as-question-body + gradation-tagged option framing + triage); the caller's `§CMD_TAG_TRIAGE` / fix-skip-defer / address-ignore command supplies the answer vocabulary and interprets what the pick *means* — ELICIT frames the options but does not own or apply the decision.

---

## Hand-off — ELICIT renders the ask, the caller owns its meaning

ELICIT renders the `AskUserQuestion` — the card IS the question body (`§CMD_PRESENT_CARD_WITH_COMPLETE_CONTEXT`) — but it owns **no decision meaning**. The answer options are the caller's vocabulary (Step 5): `§CMD_TAG_TRIAGE` in the delegation walkthrough, fix/skip/defer in `/scrutinize`, address/ignore in `/pr`. ELICIT frames those options (`§FMT_ANSWER_GRADATION`, `★`=lean) inside the card body; the caller's command interprets the pick — places the tag, runs the fix, records the address. There is no longer a cards-in-chat pass followed by a separate terse popup: disclosure and choice are one prompt. Natural-language shortcuts ("skip the FYIs", "hold the whole set") are honored by the caller's command, not here.

---

## PROOF FOR §CMD_ELICIT

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "itemsDisclosed": {
      "type": "string",
      "description": "Count of items disclosed as Decision Cards rendered as AskUserQuestion question bodies, and the field-completeness (all Your-calls carry every card field)"
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
```

*A caller MAY surface ELICIT's proof (`yourCalls` / `handled` / `fyi`) into its own synthesis proof — the disclosure is reusable evidence, not throwaway.*
