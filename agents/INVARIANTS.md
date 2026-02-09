# Agent Invariants

Agent-specific behavioral rules. For shared engine invariants, see `directives/INVARIANTS.md`.

## 1. Design Invariants

*   **¶INV_AGENT_CONTRACT_DRIVEN**: Every agent must have explicit input/output contracts.
    *   **Rule**: The agent file must define a "Contract" section specifying: (1) what the agent receives as input (plan file, log file, session directory), (2) what the agent produces as output (code changes, log entries, debrief file). Implicit contracts ("the agent figures it out") are prohibited.
    *   **Reason**: Without explicit contracts, agents scope-creep. The contract is the boundary — it defines what the agent does and, by exclusion, what it does not do.

*   **¶INV_AGENT_BOUNDED**: Every agent must have explicit boundaries (what it must NOT do).
    *   **Rule**: The agent file must include a "Boundaries" section listing prohibited actions. Common boundaries: do not re-interrogate the user, do not explore beyond the plan, do not create session directories, do not modify files outside scope.
    *   **Reason**: LLM agents have a helpfulness bias — they want to do more than asked. Explicit boundaries are more effective than hoping the agent stays in lane.

*   **¶INV_AGENT_SPECIALIZED**: Specialized agents outperform general-purpose ones.
    *   **Rule**: Prefer creating a new specialized agent over expanding an existing agent's scope. The `operator` agent is the general-purpose fallback — it should not be the default choice. When a task requires a specific mindset (TDD, adversarial review, visual analysis), use or create the appropriate specialist.
    *   **Reason**: A narrow role produces better output because it constrains the model's attention. A "do everything" agent is worse at everything.

## 2. Execution Invariants

*   **¶INV_AGENT_NO_SELF_AUTHORIZE**: Agents must not self-authorize scope expansion.
    *   **Rule**: If an agent encounters work outside its contract (e.g., a builder finding a bug that needs investigation, a writer discovering stale architecture docs), it must tag the work (`#needs-fix`, `#needs-documentation`) and continue with its original task. It must NOT switch to the new task without explicit user or skill protocol authorization.
    *   **Reason**: Self-authorized scope expansion is the primary failure mode of autonomous agents. The tagging system exists to defer work to the appropriate skill.

*   **¶INV_AGENT_TEMPLATE_FIDELITY**: Agents that produce artifacts must follow their templates strictly.
    *   **Rule**: When an agent produces a debrief, log entry, or plan, it must use the template specified in its handoff parameters. Template sections must not be omitted, reordered, or renamed. Content may be marked "N/A" if a section is irrelevant, but the section header must remain.
    *   **Reason**: Templates ensure consistency across sessions. Downstream consumers (search indexing, review, progress reports) depend on predictable structure.

*   **¶INV_AGENT_MODEL_APPROPRIATE**: Model selection must match the agent's cognitive requirements.
    *   **Rule**: Use `opus` for complex reasoning, multi-step planning, and nuanced judgment. Use `sonnet` for visual/multimodal tasks (image analysis, overlay review). Use `haiku` for fast, straightforward tasks (simple file operations, template filling). When no model is specified in the agent file, it inherits from the parent (typically opus).
    *   **Reason**: Over-provisioning wastes resources and increases latency. Under-provisioning produces poor results. Match the model to the task.
