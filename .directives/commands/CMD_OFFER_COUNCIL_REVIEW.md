### ¶CMD_OFFER_COUNCIL_REVIEW
**Definition**: Offers a `/council` panel review on the artifact a skill just produced — a plan, a diff, a report, a vision, a brainstorm. The one reusable command any artifact-producing skill declares as a synthesis / next-steps step to compose council into its flow. **It OFFERS, it never forces** — the mechanical embodiment of `¶INV_OFFER_DONT_FORCE_SKILLS`. On accept it dispatches `/council` in the background (report-only), waits within a bounded ceiling, and relays the verdict.
**Concept**: "You just produced X — want a diverse expert panel to look at it before you move on?"
**Trigger**: Declared as a step in a caller's synthesis / plan-approval phase (see **Callers** below). The caller supplies the subject; this command owns the offer, the dispatch, the wait, and the relay.

---

## The caller contract

The caller declares this step and, in the surrounding prose, names the **subject** — the artifact it just produced, in `/council`'s subject vocabulary (`plan <path>`, `diff`, `commit <ref>`, `pr <#>`, `doc <path>`, `build-report <path>`, `session <dir>`, `files <glob>`, `brainstorm <path>`). The subject is the ONLY thing the caller must provide; everything else this command self-gathers from the active session (intent, whys, touched files). One command, N callers, zero cross-reference — the caller never learns council's internals, and council never reads the caller's session (it reads only the Brief this command writes).

---

## Algorithm

### Step 1: Resolve the subject
Take the subject type + pointer from the caller's step context. If the caller produced no reviewable artifact (nothing to point at), record `decision: "skipped"` with reason `no-artifact` and return — do NOT invent a subject or fall back to `diff` (`/council` is targeted, never assumed).

### Step 2: Offer (interactive — a human is at the phase gate)
This command runs in the caller's interactive session, so the offer is a real `AskUserQuestion`. Present it with one-line context naming the subject and what a panel would catch:

> "You just produced `<subject>`. Run a diverse expert-panel review (`/council`) before moving on?"
> - **"Run council"** — dispatch a background panel; I'll relay the verdict when it lands.
> - **"Decline"** — skip the review; continue the caller's flow.
> - **"Defer"** — note it for later; continue now.

- **Decline** → record `decision: "declined"`. Return to the caller.
- **Defer** → record `decision: "deferred"` (leave a one-line note in the session log). Return to the caller.
- **Run council** → proceed to Step 3.

Never force. A declined offer is a complete, valid outcome — the discipline is on the human to accept it on risky work, not on this command to compel it.

### Step 3: Write the Council Brief
Fill `~/.claude/engine/skills/council/assets/TEMPLATE_COUNCIL_BRIEF.md` to `<trailDir>/<slug>_council_brief.md` (Engine Mode `<trailDir> = <sessionDir>/builds/`):
- **`brief_version`**: `1`.
- **`subject`**: the resolved subject from Step 1.
- **`mode`**: **`report-only`** — the dispatched council runs unattended (background), so it must ask nothing and hand back a structured verdict.
- **`report_path`**: mint a path **unique to THIS dispatch** — `<trailDir>/<slug>_COUNCIL_<run-id>.md` (run-id = a short unique token). Pass it in the Brief. The absence-check in Step 5 targets this exact path, so a prior run's reused-slug report can never read as this run's clean verdict.
- **`panel.size`**: default 3; a whole-PR or cross-cutting plan may warrant 5.
- **Intent / whys / dialogue digest / touched files**: self-gather from the active session — the ticket intent, the deliberate decisions (so the panel doesn't flag them), the plan/design digest, the file list. This is the field set most worth filling; a thin Brief yields a generic panel.

### Step 4: Dispatch council in the background (report-only)
Launch `/council` as a **background task** over the Brief — `run_in_background: true`, a prompt that runs the council protocol (`~/.claude/engine/skills/council/SKILL.md`) with `--brief <brief path>` in `report-only` mode. The parent (this command) does NOT block the caller's whole flow — it continues to the bounded wait.

*Council fans out its own expert sub-agents (§4). If the harness no-ops that nested dispatch, council's own zero-experts hard-error fires and it writes NO report — which the Step-5 absence-check catches as a blind spot. This command need not special-case it; council's contract already makes a dead panel unfalsifiable.*

### Step 5: Bounded wait → absence-check → relay
Council does real multi-agent work (minutes, not seconds). Wait within a generous two-stage ceiling, with the **human as the early-out** (proceed anytime they're impatient):
- **~10 min → soft nudge**: signal council to wrap up. Council reconciles the **partial panel** (unfinished lenses become Panel Blind Spots — already supported).
- **15 min → hard cap**: force-stop. If ≥1 expert returned, council writes a partial report; if zero, it hard-errors with no report.
- The ceiling is only the backstop for a walked-away human; the completion notification normally returns control sooner.

When council settles (notification or ceiling), **absence-check the `report_path`**:
- **Report present** (with the §5.D verdict block) → **relay answer-first**: the overall `verdict` (`solid` / `sound_with_fixes` / `needs_work` / `not_ready`), the `counts` (N MUST FIX, M SHOULD FIX, K CONSIDER), and the top surviving MUST FIX titles. Link the report (`§CMD_LINK_FILE`). Surface any `blind_spots` — a non-empty list is never a silent clean.
- **Report absent** (council died / nested-dispatch no-op / truncated) → do NOT treat as clean. Record it as a **blind spot** ("council review dispatched but produced no report — panel did not run"), state it plainly, and proceed. Record `decision: "ran"` with the blind-spot noted.

### Step 6: Offer the next-step chains (never auto-run)
`/council` is read-only — it reports, it does not fix. After relaying, offer (via `AskUserQuestion`) the chains, and let the user pick:
- **`/scrutinize`** a specific finding — verify it against intent and FIX it.
- **`/fix`** a confirmed defect directly.
- **Loopback** — when the subject was a *plan* (the `/implement` plan-approval caller), hand the findings back for the plan-revision loop.
- **Proceed** — continue the caller's flow (defer any open MUST FIX with a noted deferral).

Record `decision: "ran"`. Return to the caller.

---

## Constraints

- **Offer, never force** (`¶INV_OFFER_DONT_FORCE_SKILLS`): this command's whole purpose is to make council *available* at the decision point, not mandatory. There is no proof field that gates the caller on council having run — `reviewOffered` records that the offer was made (always true when this step runs) and `decision` records the human's choice. A caller can never be blocked because the user declined.
- **The subject is the caller's; everything else self-gathers**: the caller names the artifact; this command builds the Brief. Council reads the Brief, never the session.
- **Dispatched council is always `report-only`**: it runs unattended in the background, so it must ask nothing and return a structured verdict. The *offer* is interactive (a human is present); the *review* is not.
- **Per-run `report_path`**: mint a dispatch-unique path so the absence-check can distinguish "this run wrote it" from "a prior run left one."
- **A dead panel is a blind spot, not a pass**: an absent report is surfaced, never silently treated as clean.
- **Read-only downstream**: this command offers `/scrutinize` / `/fix` / loopback; it never auto-runs them. The human keeps the gate.
- **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: the offer and the next-step chains are `AskUserQuestion`, never bare text.

---

## Callers

Declared as a synthesis / plan-approval step in these skills (the subject each supplies):
- **`/implement`** — TWICE: at plan-approval (Phase 2, `subject: plan <path>` — catch a bad plan before code exists) and at synthesis (`subject: session <dir>` — review what was actually built).
- **`/fix`** — at synthesis (`subject: diff`/`session` — the fix).
- **`/brainstorm`** — at synthesis (`subject: brainstorm <path>` — the resulting artifact).
- **`/direct`** — at synthesis (`subject: plan <path>`/`doc` — the vision).
- **`/analyze`** — at synthesis (`subject: doc <path>` — the report).
- **`/pr`** — at PR creation (`subject: pr <#>`/`diff` — the diff).

---

## PROOF FOR §CMD_OFFER_COUNCIL_REVIEW

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "reviewOffered": {
      "type": "string",
      "description": "Whether the council offer was presented and the subject offered (e.g., 'yes — offered on plan <path>', or 'skipped — no-artifact')"
    },
    "decision": {
      "type": "string",
      "enum": ["ran", "declined", "deferred", "skipped"],
      "description": "The user's choice: ran (council dispatched + relayed), declined, deferred (noted for later), or skipped (no reviewable artifact)"
    }
  },
  "required": ["reviewOffered", "decision"],
  "additionalProperties": false
}
```
