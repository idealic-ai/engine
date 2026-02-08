# Document Update Plan (The Surgical Strategy)
**Tags**: #needs-review

## 1. Executive Summary
*   **The Trigger**: `[What changed in the code?]`
*   **The Goal**: `[What is the target state of the docs?]`
*   **The Constraint**: "Surgical updates only. No creative rewrites."

## Related Sessions
*Prior work that informed this session (from session-search). Omit if none.*

*   `sessions/YYYY_MM_DD_TOPIC/DEBRIEF.md` — [Why it was relevant]

## 2. The Diagnosis (Context)
*   **Old Reality**: "Docs say X."
*   **New Reality**: "Code does Y."
*   **Risk Analysis**:
    *   *Confusion Risk*: [High/Med/Low]
    *   *Breakage Risk*: [High/Med/Low]

## 3. The Surgical Matrix (Scope of Work)
*Define the specific operations.*

### Op 1: [File Path]
*   **Target**: `[Section/Paragraph]`
*   **Operation**: [Rewrite / Append / Prune / Rename]
*   **The Change**:
    *   *From*: `[Summary of old text]`
    *   *To*: `[Summary of new text]`
*   **Reasoning**: "To align with..."

### Op 2: [File Path]
*   **Target**: ...
*   **Operation**: ...
*   **The Change**: ...

## 4. New Artifacts (The Expansion)
*If new features require new files or major sections.*

### New File: [Path]
*   **Purpose**: "To define the new 'Stem Separation' architecture."
*   **Placement**: `docs/architecture/STEMS.md`
*   **Linked From**: `docs/README.md`, `docs/concepts/AUDIO.md`

## 5. Post-Op Verification
*   [ ] **Links**: Check if any internal links were broken.
*   [ ] **Invariants**: Ensure no architectural laws were violated.
*   [ ] **Tone**: Ensure the voice matches the surrounding text.

## 5. Agent's Expert Opinion (Subjective)
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
