### ¶FMT_CONTEXT_BLOCK

**When to use**: The complete context that goes **inside** an `AskUserQuestion` question body — what the user needs to decide, framed so the body stands alone. Consumed by `§CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT` (every question), `§CMD_INTERROGATE` (each round's body), `§CMD_WALK_THROUGH_RESULTS` (per-item body).

**Rules**: The context lives **in the question body**, NOT in a separate chat block rendered before it — that duality (context up top, terse options below) is exactly what `§CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT` kills. Frame the decision completely: what's being decided, why it matters, whatever's needed to choose in-place. Substantive, not stubs. **No length cap, and there IS a floor** — AskUserQuestion bodies render long content fine; the old "exactly 2 paragraphs" existed only for a removed length limit, and once the limit went it read as a ceiling. The floor is this: **the body carries what the reader would need if they had been handed a couple of pages on the subject** — the draft itself where a draft is being approved, what a referenced item actually is where the decision cites one, and the open questions the drafting agent flagged where it flagged any. The test is not length but that **nothing the reader needs is anywhere except in front of them.** Two well-framed paragraphs is the thin end of acceptable rather than the target; a rich decision uses a full `§FMT_DECISION_CARD` as the body. ⛔ **A body that names the decision without carrying the material to decide it is the failure.** *Measured*: a question reading only "Ticket 1, the Alphabet facility: approve as drafted?" asked for approval of a draft the reader could not see, over premises, three flagged open questions and a related ticket that appeared nowhere.

```markdown
[in the AskUserQuestion `question` field:]
**[Context]**: what the user needs to know — background / recap / scope.
**[The decision]**: the specific choice with concrete details. The user decides from THIS, in place.
```

**Anti-pattern**: a separate context block in chat followed by a terse `AskUserQuestion` — the user then has to map options back to context above. Put the context in the body.
