# Brainstorm Log Schemas (The Decision Stream)
**Usage**: Choose the best schema to capture the current thought. Combine freely.

## 🏛️ Decision (Draft)
*   **Topic**: `[Concept/Architecture]`
*   **Verdict**: "We will use the Adapter Pattern for the plugin system."
*   **Reasoning**: "It provides the best decoupling between the Core Engine and 3rd party scripts. Inheritance was rejected due to rigidity."
*   **Consensus**: "User agreed that flexibility > performance here."

## 🔄 Alternative (Explored Path)
*   **Option**: "Using a SharedArrayBuffer for state sync."
*   **Status**: [Rejected / Parking Lot]
*   **Why**: "Too complex for the MVP. Requires headers that might block CDN deployment."
*   **Trade-off**: "We lose zero-copy performance but gain deployment simplicity."

## 🛑 Constraint (The Guardrail)
*   **Rule**: "The Audio Graph must remain synchronous on the Worker thread."
*   **Source**: "Web Audio API limitation + Invariant #4."
*   **Impact**: "We cannot use async/await inside the process() loop."

## ⚠️ Risk (The Fear)
*   **Fear**: "What if the user has 1000 tracks?"
*   **Scenario**: "The current O(n) search in `findTrack` will cause frame drops."
*   **Mitigation**: "Need to implement a spatial index or hash map."

## 😟 Concern (Soft Friction)
*   **Topic**: "The new UI layout feels crowded."
*   **Detail**: "User is worried about mobile responsiveness."
*   **Status**: [Noted - Will Prototype]

## ❓ Question (Open Inquiry)
*   **Asking**: "Does the user need offline support?"
*   **Context**: "This changes the storage layer decision fundamentally."
*   **Answer**: [Pending / Answered: Yes]

## 🔀 Divergence (Side Quest)
*   **Trigger**: "User mentioned 'Multi-user editing' while discussing Storage."
*   **Action**: "Spawning a sub-thread to explore CRDTs."
*   **Relevance**: "Low immediate relevance, but high strategic value."

## 🤝 Convergence (Alignment)
*   **Theme**: "Simplicity over Performance."
*   **Signals**: "We rejected 3 complex optimization ideas in a row."
*   **Principle**: "We are optimizing for 'Time to First Hello World'."

## 🅿️ Parking Lot (Deferred/Retracted)
*   **Item**: "Real-time collaboration features."
*   **Disposition**: [Defer to V2 / Retracted / Separate Session]
*   **Reason**: "User said 'Let's leave it for later' - focus is on single-player experience first."
*   **Context**: "Originally brought up during Storage discussion."
