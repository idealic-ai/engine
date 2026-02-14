# Protocol Improvement Log Schemas (The Protocol Doctor's Notebook)
**Usage**: Capture protocol issues, improvement proposals, and change decisions.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `engine log`.

## 🔍 Finding (Protocol Issue)
*   **File**: `[~/.claude/engine/.directives/commands/CMD_*.md]`
*   **Section**: `[Step N / Algorithm / Constraints]`
*   **Category**: [Violation / Clarity / Structural / Consistency]
*   **Description**: "The wording of Step 3 says 'should' when the invariant says 'MUST'."
*   **Evidence**: "Line 42: 'Agents should provide proof' vs `¶INV_PROOF_IS_DERIVED`: 'MUST pipe proof'"
*   **Granularity**: [Surgical / Directional]
*   **Proposed Fix**: "[Old text] -> [New text]" OR "[Description of structural change needed]"

## 💡 Suggestion (Improvement Idea)
*   **File**: `[target file]`
*   **Idea**: "Add an example block showing correct vs incorrect usage."
*   **Rationale**: "Agents consistently misinterpret this command because there's no concrete example."
*   **Priority**: [High / Medium / Low]

## ⚠️ Violation (Session Behavioral Issue)
*   **Session**: `[sessions/YYYY_MM_DD_TOPIC]`
*   **Phase**: `[Phase N: Name]`
*   **Violation**: "Agent skipped between-rounds context in Round 3 of interrogation."
*   **Root Cause**: "`§CMD_INTERROGATE` Step 2 says 'MANDATORY' but doesn't mechanically enforce it."
*   **Protocol Fix**: "Add a proof field for between_rounds_context_provided."

## 🔗 Connection (Cross-File Pattern)
*   **Files**: `[CMD_A.md, CMD_B.md, INVARIANTS.md]`
*   **Pattern**: "All three use different terminology for the same concept."
*   **Impact**: "Agents interpret them inconsistently."
*   **Unification**: "Standardize on '[term]' across all three files."

## ✅ Applied (Change Committed)
*   **File**: `[file path]`
*   **Change**: "[summary of edit]"
*   **Type**: [Surgical / Directional]
*   **Verification**: "[how we confirmed the change is correct]"

## ⏭️ Skipped (Change Deferred)
*   **File**: `[file path]`
*   **Finding**: "[summary]"
*   **Reason**: "[why skipped -- user decided, too risky, needs more investigation]"
