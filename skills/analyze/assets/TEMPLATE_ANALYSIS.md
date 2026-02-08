# Research Debriefing: [Topic]
**Tags**: #needs-review
**Filename**: `sessions/[YYYY_MM_DD]_[TOPIC]/ANALYSIS.md`

## 1. Executive Summary
*   **The Mission**: [What were we looking for?]
*   **The Bottom Line**: [1-2 sentences summarizing the most critical finding.]
*   **Verdict**: [Proceed / Pivot / Pause / Critical Fix Needed]

## Related Sessions
*Prior work that informed this session (from session-search). Omit if none.*

*   `sessions/YYYY_MM_DD_TOPIC/DEBRIEF.md` — [Why it was relevant]

## 2. The Landscape (Map of the Territory)
*   **Explored Areas**:
    *   `[Module/Concept A]`
    *   `[Module/Concept B]`
*   **The Blind Spots**: "We explicitly did NOT check X, Y, or Z. These remain unknown."

## 3. Key Insights (Synthesis)
*Don't just list log entries. Group them into themes.*

### Theme A: [e.g., The Friction in Onboarding]
*   **Observation**: "We found 3 separate blocks (Log items #2, #5, #8) that delay user gratification."
*   **Impact**: "This creates a cumulative drop-off risk of ~40%."
*   **Root Cause**: "Reliance on legacy 'Account First' architecture."

### Theme B: [e.g., The Viral Opportunity]
*   **Observation**: "The new 'Jam Mode' idea (Log item #12) aligns perfectly with the 'Socket' infrastructure we found in `network.ts`."
*   **Opportunity**: "Low-hanging fruit to double retention."

## 4. The "Iceberg" Risks (Hidden Dangers)
*   **Critical Risk**: "..."
*   **Technical Debt**: "..."

## 5. Strategic Recommendations
1.  **Immediate Win**: [Actionable Step]
2.  **Strategic Shift**: [Long-term Pivot]
3.  **Further Research**: [What question is still unanswered?]

## 6. Agent's Expert Opinion (Subjective)
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
