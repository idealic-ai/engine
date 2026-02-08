# Decision Log Schemas (The Deliberation Record)
**Usage**: Capture discovery, context analysis, and decision outcomes. Record what was presented, what the user chose, and why.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `log.sh`.

## ▶️ Discovery Start
*   **Search**: "Searching for `#needs-decision` across sessions/"
*   **Results**: "[N] files found in [M] sessions"
*   **Files**: List of discovered file paths

## 📋 Decision Presented
*   **Item**: "Decision [N]/[Total]: [Topic]"
*   **Source**: `[session_dir]/[file.md]`
*   **Question**: "[The extracted question]"
*   **Options Offered**: "[Option A, Option B, Analyze deeper]"

## 🔍 Deep Analysis
*   **Decision**: "[Topic]"
*   **Files Read**: List of additional session files read for context
*   **New Context**: "[Summary of what was learned]"
*   **Refined Options**: "[Updated options after deeper analysis]"

## ✅ Decision Recorded
*   **Item**: "Decision [N]: [Topic]"
*   **User Choice**: "[Verbatim]"
*   **Reasoning**: "[User's reasoning]"
*   **Tag Swap**: "`#needs-decision` → `#done-decision` in `[file]`"
*   **Breadcrumb**: "Appended decision record to `[file]`"

## ⏭️ Decision Skipped
*   **Item**: "Decision [N]: [Topic]"
*   **Reason**: "[User chose to skip / defer further]"
*   **Action**: "Tag remains `#needs-decision`"
