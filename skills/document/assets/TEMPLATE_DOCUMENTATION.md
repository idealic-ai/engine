# Documentation Debriefing (The Post-Op Report)
**Tags**: #needs-review
**Filename Convention**: `sessions/[YYYY_MM_DD]_[TOPIC]/DOCUMENTATION.md`.

## 1. Executive Summary
*Status: [Complete / Partial / Audit Only]*

*   **Trigger**: `[What changed in the code/system?]`
*   **Operations Performed**: [N] edits across [M] files
*   **New Artifacts**: [List any new documentation files created]
*   **Key Artifacts**:
    *   `docs/path/to/updated_doc.md` (Updated/Created)

## Related Sessions
*Prior work that informed this session (from session-search). Omit if none.*

*   `sessions/YYYY_MM_DD_TOPIC/DEBRIEF.md` — [Why it was relevant]

## 2. The Campaign (Narrative)
*Describe the documentation session. What was the state before? What drift was found? What was the hardest part?*
"We found that the API docs were 3 months stale after the auth refactor. The biggest challenge was tracing which endpoints had changed signatures. We updated 5 files and created 1 new concept page."

<!-- WALKTHROUGH RESULTS -->
## 3. Operations Log (The Surgical Record)
*Summary of edits performed. Link to specific log entries if possible.*

### ✂️ Edit 1: [File Path]
*   **Section**: `[Section/Heading]`
*   **Operation**: [Rewrite / Append / Prune / Rename]
*   **Summary**: "Replaced deprecated API endpoint docs with current v2 signatures."
*   **Validation**: [Verified against code / Cross-referenced / Spot-checked]

### ✂️ Edit 2: [File Path]
*   **Section**: ...
*   **Operation**: ...
*   **Summary**: ...

<!-- WALKTHROUGH RESULTS -->
## 4. New Artifacts (The Expansion)
*New documentation files created during this session.*

### New File: [Path]
*   **Purpose**: "Documents the new discovery hook system."
*   **Placement**: `docs/architecture/DISCOVERY.md`
*   **Linked From**: `docs/README.md`, `docs/TOC.md`

<!-- WALKTHROUGH RESULTS -->
## 5. Documentation Health (The Prognosis)

*   **Coverage**: "The core API is now fully documented. Edge cases in auth flow are still sparse."
*   **Freshness**: "All updated docs now match the current codebase as of this session."
*   **Consistency**: "Tone and structure are aligned across the updated files."
*   **Remaining Drift**: "The deployment guide still references the old CI pipeline."

## 6. The "Parking Lot" (Deferred)
*Documentation work identified but not performed in this session.*

*   **Deferred Edit**: "[File] needs a full rewrite — out of scope for this session."
*   **New Doc Needed**: "[Topic] should have its own concept page."

<!-- WALKTHROUGH RESULTS -->
## 7. Agent's Expert Opinion (Subjective)

### 1. The Quality Audit (Honest)
*   **Confidence**: "I'm 90% confident the updated docs are accurate."
*   **Completeness**: "We covered the primary changes but missed the edge cases."

### 2. The Advice
*   **Next Steps**: "The deployment guide needs a follow-up session."
*   **Warning**: "Don't merge the auth changes without updating the security docs first."
