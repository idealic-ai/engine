### §CMD_INTERROGATE
**Definition**: Structured interrogation with depth selection, topic-driven rounds, between-rounds context, and exit gating. The skill provides a **standard topics list** (under `### Interrogation Topics` in its SKILL.md); the command owns all mechanics.
**Trigger**: Called by skill protocols during their interrogation/pre-flight phase.

**Step 1 — Depth Selection**: Present via `AskUserQuestion` (multiSelect: false):
> "How deep should interrogation go?"

| Depth | Minimum Rounds | When to Use |
|-------|---------------|-------------|
| **Short** | 3+ | Task is well-understood, small scope, clear requirements |
| **Medium** | 6+ | Moderate complexity, some unknowns, multi-file changes |
| **Long** | 9+ | Complex system changes, many unknowns, architectural impact |
| **Absolute** | Until ALL questions resolved | Novel domain, high risk, critical system, zero ambiguity tolerance |

Record the user's choice. This sets the **minimum** — the agent can always ask more, and the user can always say "proceed" after the minimum is met.

**Step 2 — Round Loop**:

[!!!] CRITICAL: You MUST complete at least the minimum rounds for the chosen depth.

**Round counter**: Output on every round: "**Round N / {depth_minimum}+**"

**Topic selection**: Pick from the skill's standard topics or the universal repeatable topics below. Do NOT follow a fixed sequence — choose the most relevant uncovered topic based on what you've learned so far.

**Universal repeatable topics** (available to all skills, can be selected any number of times):
- **Followup** — Clarify or revisit answers from previous rounds
- **Devil's advocate** — Challenge assumptions and decisions made so far
- **What-if scenarios** — Explore hypotheticals, edge cases, and alternative futures
- **Deep dive** — Drill into a specific topic from a previous round in much more detail

**Each round**:
1.  **Between-rounds context (2 paragraphs — MANDATORY, skip for Round 1)**:
    > **Round N-1 recap**: [1 paragraph — Summarize what was learned: key answers, decisions made, constraints established, assumptions confirmed or invalidated.]
    >
    > **Round N — [Topic]**: [1 paragraph — Explain what topic is next, why it's relevant given what was just learned, and what the questions aim to uncover.]

    **Anti-pattern**: Do NOT jump straight into questions without context. The user should always know what was just established and why they're being asked the next set.
2.  **Ask**: Execute `§CMD_ASK_ROUND` via `AskUserQuestion` (3-5 targeted questions on the chosen topic).
3.  **Handle response**:
    *   **User provided answers**: Auto-logged to DETAILS.md by `post-tool-use-details-log.sh` hook. Continue to next round.
    *   **User asked a counter-question**: PAUSE. Answer in chat. Ask "Does this clarify? Ready to resume?" Once confirmed, resume.

**Step 3 — Exit Gate**: After reaching minimum rounds, present via `AskUserQuestion` (multiSelect: true):
> "Round N complete (minimum met). What next?"
> - **"Proceed to next phase"** — *(terminal: if selected, skip all others and move on)*
> - **"More interrogation (3 more rounds)"** — Standard topic rounds, then this gate re-appears
> - **"Devil's advocate round"** — 1 round challenging assumptions, then this gate re-appears
> - **"What-if scenarios round"** — 1 round exploring hypotheticals, then this gate re-appears

**Execution order** (when multiple selected): Standard rounds first → Devil's advocate → What-ifs → re-present exit gate.

**On "Proceed to next phase"**: After the exit gate resolves, fire `§CMD_GATE_PHASE`. This gives the user the walkthrough option (review what was established during interrogation) before committing to the next phase. Current/next/previous phases are derived from the `phases` array in `.state.json`.

**For `Absolute` depth**: Do NOT offer the exit gate until you have zero remaining questions. Output: "Round N complete. I still have questions about [X]. Continuing..."

**Constraints**:
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in this command MUST use `AskUserQuestion`. Never drop to bare text for questions or routing decisions.
*   Minimum rounds are mandatory. No self-authorized skips — fire `§CMD_REFUSE_OFF_COURSE` if tempted.
*   Between-rounds context is mandatory after Round 1. No bare question dumps.
*   Every round logged to DETAILS.md. No unlogged rounds.
*   Counter-questions don't count as rounds.

---

## PROOF FOR §CMD_INTERROGATE

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "depth_chosen": {
      "type": "string",
      "description": "The interrogation depth selected by the user"
    },
    "rounds_completed": {
      "type": "number",
      "description": "Total number of interrogation rounds completed"
    }
  },
  "required": ["depth_chosen", "rounds_completed"],
  "additionalProperties": false
}
```
