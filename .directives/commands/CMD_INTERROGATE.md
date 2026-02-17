### ¶CMD_INTERROGATE
**Definition**: Structured interrogation with depth selection, topic-driven rounds, between-rounds context, and exit gating. The skill provides a **standard topics list** (under `### Interrogation Topics` in its SKILL.md); the command owns all mechanics.
**Trigger**: Called by skill protocols during their interrogation/pre-flight phase.

**Step 0 — Prior Context Scan** (skill switches only):
If the session has artifacts from a prior skill (check `## SRC_SESSION_ARTIFACTS` and `## SRC_PRIOR_SKILL_CONTEXT` from activate output), read the prior skill's log and DIALOGUE.md BEFORE starting interrogation. Extract topics already covered — these should be skipped or condensed in interrogation rounds. Do NOT re-ask questions whose answers are already established in prior logs.

**Step 1 — Depth Selection**: Invoke §CMD_DECISION_TREE with `§ASK_INTERROGATION_DEPTH`.

Record the user's choice. This sets the **minimum** — the agent can always ask more, and the user can always say "proceed" after the minimum is met.

**Step 2 — Round Loop**:

[!!!] CRITICAL: You MUST complete at least the minimum rounds for the chosen depth.

**Round counter**: Output on every round: "**Round N / {depth_minimum}+**"

**Item IDs**: Questions use hierarchical IDs per the Item IDs convention (SIGILS.md § Item IDs). Format: `{phase}.{round}/{question}`. Example: Phase 2, Round 3, Question 2 = `2.3/2`. Use the item ID as the `header` field in `AskUserQuestion`. IDs are assigned at creation and persisted in both chat headers and DIALOGUE.md.

**Topic selection**: Pick from the skill's standard topics or the universal repeatable topics below. Do NOT follow a fixed sequence — choose the most relevant uncovered topic based on what you've learned so far.

**Universal repeatable topics** (available to all skills, can be selected any number of times):
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions and decisions made so far
- **What-if scenarios** — Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** — Drill into a specific topic from a previous round in much more detail

**Each round**:
1.  **Between-rounds context** (`§FMT_CONTEXT_BLOCK` — MANDATORY, skip for Round 1): Context label = "Round N-1 recap" (what was learned). Content label = "Round N — [Topic]" (what's next and why).
2.  **Ask**: Execute `§CMD_ASK_ROUND` via `AskUserQuestion` (up to 4 targeted questions on the chosen topic — the tool maximum).
3.  **Handle response**:
    *   **User provided answers**: Auto-logged to DIALOGUE.md by `post-tool-use-details-log.sh` hook. Continue to next round.
    *   **User asked a counter-question**: PAUSE. Answer in chat. Ask "Does this clarify? Ready to resume?" Once confirmed, resume.

**Step 3 — Exit Gate**: After reaching minimum rounds, invoke §CMD_DECISION_TREE with `§ASK_INTERROGATION_EXIT`.

**Execution order** (when multiple selected): Standard rounds first → Devil's advocate → What-ifs → re-present exit gate.

**On "Proceed to next phase"**: Execute the phase transition directly -- the exit gate IS the phase gate for interrogation (replacing the automatic gate in `§CMD_EXECUTE_PHASE_STEPS`). Walkthrough and Go Back are available via smart extras (A/B) on the exit gate preamble, eliminating the double-click problem.

**Smart extras for exit gate preamble** (agent-generated, shown before AskUserQuestion):
> **Also:** A: Walk through what was established before proceeding | B: Go back to re-do the last round | C: Skip to synthesis

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining questions. Output: "Round N complete. I still have questions about [X]. Continuing..."

**Constraints**:
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in this command MUST use `AskUserQuestion`. Never drop to bare text for questions or routing decisions.
*   Minimum rounds are mandatory. No self-authorized skips — fire `§CMD_REFUSE_OFF_COURSE` if tempted.
*   Between-rounds context is mandatory after Round 1. No bare question dumps.
*   Every round logged to DIALOGUE.md. No unlogged rounds.
*   Counter-questions don't count as rounds.
*   **`¶INV_CONCISE_CHAT`**: Chat output is for user communication only — no micro-narration between rounds.

---

### ¶ASK_INTERROGATION_DEPTH
Trigger: when starting any skill's interrogation phase (except: when depth was already set by dehydrated context from a previous overflow)
Extras: A: Show example questions before choosing | B: Start with 1 warm-up round first | C: Use depth from previous session

## Decision: Interrogation Depth
- [LITE] Short (4+ rounds)
  Findings are clear, just confirm direction
- [MEDM] Medium (8+ rounds)
  Moderate complexity, some findings need input
- [FULL] Long (12+ rounds)
  Complex analysis, many open questions
- Absolute (until resolved)
  Zero ambiguity tolerance — no minimum, no exit gate until all questions resolved
- Custom depth
  Specify a custom minimum round count

### ¶ASK_INTERROGATION_EXIT
Trigger: after minimum interrogation rounds are met (except: when exit gate was merged with phase gate per interrogation double-tap fix)
Extras: A: Walk through findings so far | B: Go back to a previous topic | C: Skip to planning

## Decision: Interrogation Exit
- [NEXT] [ ] Next phase
  Done interrogating — move on
- [MORE] [ ] More interrogation (4 more rounds)
  Standard topic rounds, then re-present this gate
- [DEEP] [ ] Deep dive round
  1 round drilling into a specific prior topic in detail
- [ ] Devil's advocate round
  1 round challenging assumptions and decisions made so far
- [ ] What-if scenarios round
  1 round exploring hypotheticals and edge cases
- [ ] Gaps round
  1 round identifying what hasn't been asked yet — unknown unknowns

---

## PROOF FOR §CMD_INTERROGATE

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "depthChosen": {
      "type": "string",
      "description": "The interrogation depth selected by the user"
    },
    "roundsCompleted": {
      "type": "string",
      "description": "Count and topics covered (e.g., '6 rounds: scope, deps, testing, arch, UX, edge cases')"
    }
  },
  "required": ["depthChosen", "roundsCompleted"],
  "additionalProperties": false
}
```
