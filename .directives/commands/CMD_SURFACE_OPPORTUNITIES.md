### ¶CMD_SURFACE_OPPORTUNITIES
**Definition**: At session close, surfaces concrete improvement opportunities the agent observed during the session. Leverages the full loaded context to generate actionable suggestions, each mapped to a specific skill. Display-only with roll-call format.
**Classification**: SYNTHESIS

**Algorithm**:
1.  **Analyze Context**: Review all loaded context — debrief, leftover work, side discoveries, code changes observed, plan deviations, tech debt, and any patterns noticed during the session. Draw from memory of the full session, not just artifacts.
2.  **Generate Opportunities**: Identify 3-5 concrete, actionable improvement opportunities. Each opportunity must be:
    *   **Specific**: Reference actual files, components, or patterns observed — not generic advice.
    *   **Actionable**: Map to a specific skill that could address it (e.g., `/implement`, `/fix`, `/test`, `/document`).
    *   **Novel**: Not duplicating items already captured by `§CMD_REPORT_LEFTOVER_WORK` or tagged by `§CMD_CAPTURE_SIDE_DISCOVERIES`. Focus on things the agent noticed but that fell outside the current session's scope.
3.  **Output**: Print under the header `## Opportunities` using roll-call item IDs:
    ```markdown
    ## Opportunities

    *   **N.4.K/1**: [Concrete observation about what could be improved] — `/skill`
    *   **N.4.K/2**: [Concrete observation about what could be improved] — `/skill`
    *   **N.4.K/3**: [Concrete observation about what could be improved] — `/skill`
    ```
    Where `N.4.K` is this step's position in the Close sub-phase (e.g., `5.4.3` if this is step 3 in Phase 5.4 Close).
4.  **Skip Silently**: If the agent has no meaningful observations beyond what was already captured by leftover work and side discoveries, output a single roll-call line: `N.4.K: §CMD_SURFACE_OPPORTUNITIES — no additional opportunities.`

**Constraints**:
*   **Display-only**: No `AskUserQuestion` — just output. The opportunities inform the user's next-skill choice at `§CMD_PRESENT_NEXT_STEPS`.
*   **Not a scanner**: Unlike `§CMD_REPORT_LEFTOVER_WORK`, this is not mechanical pattern-matching. It is the agent's expert synthesis of what it observed. The agent uses judgment, not regex.
*   **No duplication**: Do NOT repeat items already surfaced by `§CMD_REPORT_LEFTOVER_WORK` (tech debt, blocks, incomplete steps) or tagged by `§CMD_CAPTURE_SIDE_DISCOVERIES`. Focus on fresh observations.
*   **Cap at 5**: Maximum 5 opportunities. Quality over quantity — each must be specific and actionable.
*   **Skill mapping required**: Every opportunity MUST end with ` — /skill-name`. An observation without a skill mapping is not an opportunity.
*   **One line per opportunity**: Each opportunity is a single bullet. No multi-paragraph explanations.
*   **`¶INV_CONCISE_CHAT`**: Chat output is for user communication only — no micro-narration of the analysis process.

---

## PROOF FOR §CMD_SURFACE_OPPORTUNITIES

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "opportunitiesSurfaced": {
      "type": "string",
      "description": "Count and skill categories (e.g., '4 opportunities: 2 /implement, 1 /test, 1 /document')"
    }
  },
  "required": ["executed", "opportunitiesSurfaced"],
  "additionalProperties": false
}
```
