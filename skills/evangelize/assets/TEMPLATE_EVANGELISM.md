# Evangelism Debriefing (Strategic Impact Report)
**Tags**: #needs-review
**Filename**: `sessions/[YYYY_MM_DD]_[TOPIC]/EVANGELISM.md`

## 1. The Paradigm Shift
*What fundamental truth about our system has changed?*

*   **From**: [Old Way, e.g., "Blocking UI for Audio"]
*   **To**: [New Way, e.g., "Asynchronous Parallelism"]
*   **The Win**: "We are no longer bound by the main thread's refresh rate."

## Related Sessions
*Prior work that informed this session (from session-search). Omit if none.*

*   `sessions/YYYY_MM_DD_TOPIC/DEBRIEF.md` — [Why it was relevant]

## 2. The Unlock Map (Strategic Value)
*How does this translate to Product Power?*

### Horizon 1: Immediate User Value
*   **The Win**: "Zero-Latency Seeking."
*   **Why it Matters**: "Users feel 'in control'. It feels native, not web-based."
*   **Metric Impact**: "Likely to reduce 'Frustration Clicks' by 80%."

### Horizon 2: Developer Velocity
*   **The Win**: "Decoupled Renderer."
*   **Why it Matters**: "We can now build new Visualizers without touching the Audio Engine."
*   **Metric Impact**: "New Visualizer Time-to-Market: 2 days -> 4 hours."

### Horizon 3: The Competitive Moat
*   **The Win**: "WASM-based DSP."
*   **Why it Matters**: "Competitors are stuck with Web Audio API limits. We can run VST-grade effects in the browser."
*   **Metric Impact**: "Impossible to clone without deep C++ expertise."

## 3. Angles Discovered
*Distinct framings of why this work matters, surfaced during interrogation.*

### Angle 1: [Name]
*   **Framing**: [How this angle presents the value]
*   **Audience**: [Who cares about this angle — users, devs, business, ops]
*   **Evidence**: [Concrete proof — code, metrics, architecture details]

### Angle 2: [Name]
*   **Framing**: [...]
*   **Audience**: [...]
*   **Evidence**: [...]

### Angle 3: [Name]
*   **Framing**: [...]
*   **Audience**: [...]
*   **Evidence**: [...]

*(Add more angles as discovered)*

## 4. Devil's Advocate Review
*Challenges raised and how they were addressed.*

### Challenge 1: [Objection]
*   **Pushback**: [The skeptical argument]
*   **Response**: [How the user/agent countered it]
*   **Verdict**: [Resolved / Partially Addressed / Open Risk]

### Challenge 2: [Objection]
*   **Pushback**: [...]
*   **Response**: [...]
*   **Verdict**: [...]

*(Add more challenges as raised)*

## 5. The "Story" (Marketing / Internal Comms)
*Drafting the narrative for the team/public.*

> "Today marks the end of [Old Paradigm]. With the new [Topic] architecture, we are effectively [Bold Claim]. We didn't just [Incremental Improvement]; we [Paradigm Shift]."

## 6. The "What If" Scenarios (Future Vision)
*Unlock paths and provocative possibilities generated during the session.*

1.  **"What if... [Scenario]?"**
    *   *Feasibility*: High / Medium / Low
    *   *Value*: [Why this matters]
    *   *Enabled By*: [Specific architectural change that makes this possible]
2.  **"What if... [Scenario]?"**
    *   *Feasibility*: ...
    *   *Value*: ...
    *   *Enabled By*: ...

## 7. Next Steps (Capitalizing on the Win)
*   **Immediate**: "[Ship / Announce / Demo the change]"
*   **Explore**: "[Prototype the most promising unlock path]"
*   **Communicate**: "[Share the strongest angle with stakeholders]"

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
