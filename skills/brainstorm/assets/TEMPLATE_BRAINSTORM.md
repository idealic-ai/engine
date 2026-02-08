# Brainstorm Debriefing Template
**Tags**: #needs-review
**Filename Convention**: `sessions/[YYYY_MM_DD]_[TOPIC]/BRAINSTORM.md`.

## 1. Executive Summary
*A high-level narrative explaining the "What" and "Why" of the pivot or decision.*

*   **The Context**: Briefly describe the problem or the architectural gap that triggered the session.
*   **The Pivot**: Describe the core decision (e.g., "Moving from Class-Based to Configuration-Driven").
*   **The Benefit**: Why is this better? (e.g., "Decouples DSP from Topology").

## Related Sessions
*Prior work that informed this session (from session-search). Omit if none.*

*   `sessions/YYYY_MM_DD_TOPIC/DEBRIEF.md` — [Why it was relevant]

## 2. Key Insights & Decisions (The Q&A Synthesis)
*Summarize the critical questions asked during the session and the answers that shaped the new architecture.*

### Insight 1: [Topic/Question Title]
*   **Question**: What was the specific uncertainty?
*   **Answer**: The specific decision made.
*   **Reasoning**: Why is this the right path?
*   **Implications**: What are the side effects?

## 3. The Pre-Mortem (Risk Analysis)
*Assume this decision failed 6 months from now. Why did it fail?*

*   **Risk 1**: (e.g., "The serialization format became too heavy for LocalStorage.")
    *   *Mitigation*: (e.g., "Implement compression or move to IndexedDB.")

## 4. The "One-Way Door" Test (Reversibility)
*Is this decision easily reversible? (Jeff Bezos Principle)*

*   **Reversibility**: [Easy / Hard / Impossible]
*   **The Exit Strategy**: (e.g., "If we hate this config schema, we can write a migration script.")

## 5. Invariants & Rules
*Define the new "Laws of Physics" that emerge from this decision.*

*   **§INV_NAME**: Definition.

## 6. Documentation Updates
*A checklist of existing documentation that must be updated.*

*   [ ] **`docs/architecture/OLD_DOC.md`**:
    *   *Change*: Remove section X.

## 7. Conclusion
*   **Status**: [Consensus Achieved / More Research Needed / Pivot Required]
*   **Next Step**: (e.g., "Move to Planning Phase" or "Prototype X")

## 8. Agent's Expert Opinion (Subjective)
*Your unfiltered thoughts on the session.*

### 1. The Task Review (Subjective)
*   **Value**: "This felt critical. The system was rotting without it."
*   **Clarity**: "The goal was vague at first, but we clarified it."
*   **Engagement**: "Honestly, this was boring/exciting work."

### 2. The Result Audit (Honest)
*   **Quality**: "I'm 90% happy, but that one hack bothers me."
*   **Robustness**: "It will hold up under load, but edge cases might break it."
*   **Completeness**: "We missed the 'Offline' aspect completely."

### 3. Personal Commentary (Unfiltered)
*   **The Worry**: "I'm scared that the 'User' object is becoming a God Object."
*   **The Surprise**: "I didn't expect the Worker latency to be that low."
*   **The Advice**: "Please, for the love of code, refactor `utils.ts` next."
