# Document Update Log Schemas (The Surgical Record)
**Usage**: Choose the best schema for your action. Capture the reality of the operation.

## ✂️ Incision (Edit Applied)
*   **Target**: `[File Path]`
*   **Scope**: "Section 3: Initialization."
*   **Action**: "Replaced deprecated constructor with new pattern."
*   **Diff**: "Removed 5 lines, Added 12 lines."
*   **Validation**: "Verified syntax and checked surrounding context."

## 🩸 Bleeding (Inconsistency Found)
*   **Wound**: "Updated `AUDIO_GRAPH.md` but `PLUGINS.md` references old structure."
*   **Severity**: [High - Misleading / Low - Trivial]
*   **Root Cause**: "Plugin docs were written before the Graph refactor."
*   **Action**: "Logged to Parking Lot for separate cleanup task."
*   **Risk**: "Users might try to instantiate plugins incorrectly."

## 💀 Necrosis (Dead Content)
*   **Tissue**: `docs/legacy/v1_setup.md`
*   **Diagnosis**: "Refers to pre-React version of the app."
*   **Evidence**: "Mentions `jQuery` and global `window.app`."
*   **Action**: [Deleted / Archived / Marked Deprecated]
*   **Impact**: "Reduces search noise for new developers."

## 🩹 Suture (Link/Ref Fix)
*   **Target**: `README.md`
*   **Fix**: "Updated link to `ARCHITECTURE.md`."
*   **Broken By**: "Renaming of the core architecture file."
*   **Verification**: "Link now resolves correctly."
*   **Note**: "Also fixed a typo in the link text."

## 🌱 Planting (New Content)
*   **File**: `docs/features/STEM_SEPARATION.md`
*   **Trigger**: "Feature 'Stems' was implemented but undocumented."
*   **Placement**: "Created new file, linked from `concepts/AUDIO.md`."
*   **Structure**: "Followed the `FEATURE_TEMPLATE.md` standard."

## 🩺 Observation (Context)
*   **Note**: "The tone here is very casual."
*   **Context**: "Written by early team member, distinct voice."
*   **Decision**: "Matching casual tone to preserve voice."
*   **Constraint**: "Avoid making it sound like corporate jargon."
*   **Example**: "Kept 'Boom!' instead of 'Execution Complete'."

## 🗑️ Parking Lot (Deferred)
*   **Item**: "The `User Guide` needs a full rewrite."
*   **Reason**: "Out of scope for this surgical intervention."
*   **Size**: "Estimated 4 hours of work."
*   **Priority**: [Low]
*   **Owner**: "Unassigned"
