# Coordination Request: [TOPIC]
**Tags**: #needs-coordination
**Filename Convention**: `sessions/[YYYY_MM_DD]_[SESSION_TOPIC]/COORDINATE_REQUEST_[TOPIC].md`

## 1. Topic
*   **What**: [Concise description of what needs multi-agent coordination]
*   **Why**: [Why coordination is needed — what sequential work can't achieve]

## 2. Fleet Configuration
*   **Target Panes**: [List of pane names/IDs to coordinate, or "all active"]
*   **Decision Principles**: [Key principles for autonomous decision-making]
*   **Escalation Rules**: [What should always/never be escalated to the user]

## 3. Work Distribution
*   [Agent 1 / Pane 1: task description]
*   [Agent 2 / Pane 2: task description]
*   [Agent 3 / Pane 3: task description (if applicable)]

## 4. Coordination Requirements
*   **Dependencies**: [Which tasks depend on others completing first]
*   **Shared Resources**: [Files or state that multiple agents will touch]
*   **Conflict Resolution**: [How to handle conflicting changes — e.g., "coordinator decides", "escalate to user"]

## 5. Acceptance Criteria
*   [ ] [Criterion 1: e.g., "All agents complete their assigned tasks"]
*   [ ] [Criterion 2: e.g., "No merge conflicts in shared files"]
*   [ ] [Criterion 3: e.g., "Integration test passes after coordination"]

## 6. Requesting Session
*   **Session**: `sessions/[YYYY_MM_DD]_[SESSION_TOPIC]/`
*   **Requester**: [Agent name or pane ID]
