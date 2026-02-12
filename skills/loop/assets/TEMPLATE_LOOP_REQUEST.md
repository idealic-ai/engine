# Loop Request: [TOPIC]
**Tags**: #needs-loop
**Filename Convention**: `sessions/[YYYY_MM_DD]_[SESSION_TOPIC]/LOOP_REQUEST_[TOPIC].md`

## 1. Topic
*   **What**: [Concise description of the LLM workload to iterate on]
*   **Why**: [Why iteration is needed — what quality gap exists]

## 2. Workload Context
*   **Manifest**: [Path to existing loop.manifest.json, or "needs creation"]
*   **Artifact Files**: [Paths to prompts/schemas/configs that may be modified]
*   **Case Files**: [Glob patterns for test case inputs]
*   **Current Quality**: [X/Y cases passing, or "unknown — needs baseline"]

## 3. Known Failure Patterns
*   [Pattern 1: e.g., "Multi-line headers are missed on 3 cases"]
*   [Pattern 2: e.g., "Bounding boxes drift right on continuation pages"]
*   [Pattern 3: e.g., "Numeric values truncated to integers"]
*   *(Or "Unknown — needs investigation" if no patterns identified)*

## 4. Iteration Goals
*   **Target Quality**: [e.g., "95% pass rate" or "all focus cases passing"]
*   **Scope**: [e.g., "Prompt changes only" or "Prompt + schema changes allowed"]
*   **Max Iterations**: [e.g., "10" or "until convergence"]
*   **Suggested Mode**: [Precision / Exploration / Convergence / "Agent's choice"]

## 5. Domain Context
*   **Domain Docs**: [Paths to architecture docs, specs, or READMEs the Composer should read]
*   **Constraints**: [Any restrictions — patterns to follow, packages to avoid, etc.]

## 6. Acceptance Criteria
*   [ ] [Criterion 1: e.g., "Pass rate reaches 90%+"]
*   [ ] [Criterion 2: e.g., "Zero regressions from baseline"]
*   [ ] [Criterion 3: e.g., "Insights documented for future sessions"]

## 7. Requesting Session
*   **Session**: `sessions/[YYYY_MM_DD]_[SESSION_TOPIC]/`
*   **Requester**: [Agent name or pane ID]
