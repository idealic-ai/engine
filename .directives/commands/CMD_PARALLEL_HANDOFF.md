### §CMD_PARALLEL_HANDOFF
**Definition**: Standardized parallel handoff from a parent command to multiple autonomous agents, each executing an independent chunk of the plan.
**Rule**: Opt-in, user-initiated. The parent analyzes the plan for parallelizable chunks, presents a non-intersection proof, and offers a richer handoff menu. Extends `§CMD_HANDOFF_TO_AGENT` with multi-agent coordination.

**Preconditions**:
*   A plan file exists with steps that declare `**Depends**:` and `**Files**:` fields.
*   The parent has completed all phases up to the handoff point (Planning approved).

---

#### Parameters (inherited from §CMD_HANDOFF_TO_AGENT + extensions)

```json
{
  "agentName": "builder | writer | debugger",
  "sessionDir": "[absolute path to session directory]",
  "planFile": "[path to approved plan file, e.g. IMPLEMENTATION_PLAN.md]",
  "logFile": "[relative path to shared log file, e.g. IMPLEMENTATION_LOG.md]",
  "debriefTemplate": "[path to debrief template]",
  "logTemplate": "[path to log entry template]",
  "contextFiles": ["[files loaded during context ingestion]"],
  "detailsFile": "[path to DETAILS.md]",
  "taskSummary": "[one-line description]"
}
```

---

#### Algorithm

##### Step 1: Parse Plan Dependencies

1.  **Read** the plan file.
2.  **Extract** each step's `**Depends**:` and `**Files**:` fields.
3.  **Build Dependency Graph**: Each step is a node. Edges point from dependency to dependent.
    *   Steps with `**Depends**: None` are root nodes.
    *   Steps with `**Depends**: Step N, Step M` have edges from N and M.

##### Step 2: Derive Parallel Chunks

1.  **Topological Sort**: Process the dependency graph in waves.
    *   **Wave 1**: All root nodes (no incoming edges).
    *   **Wave 2**: Nodes whose dependencies are all in Wave 1.
    *   **Wave N**: Nodes whose dependencies are all in prior waves.
2.  **Group into Chunks**: Within each wave, group steps that share no files into independent chunks.
    *   Two steps can be in the same chunk if they touch the same files (sequential within chunk).
    *   Two steps MUST be in different chunks if they touch different files and have no dependency.
3.  **File Set Aggregation**: Each chunk's file set is the union of all `**Files**:` from its steps.
4.  **Non-Intersection Check**: For chunks within the same wave, verify that file sets are disjoint.
    *   If file sets overlap, merge the conflicting chunks into one.
5.  **Sequential Chunks**: Chunks in later waves depend on earlier waves completing. These run after their dependencies.

##### Step 3: Present Chunk Visualization

**Output this block in chat** (populated with actual data):

```markdown
## Parallel Execution Analysis

**[N] independent chunks detected across [W] waves.**

### Wave 1 (parallel)
| Chunk | Steps | Files | Dependencies |
|-------|-------|-------|-------------|
| A | 1, 3, 5 | `src/parser.ts`, `src/parser.test.ts` | None |
| B | 2, 4, 6 | `src/renderer.ts`, `src/renderer.test.ts` | None |

> **Non-intersection proof (Wave 1):**
> Chunk A files: `{src/parser.ts, src/parser.test.ts}`
> Chunk B files: `{src/renderer.ts, src/renderer.test.ts}`
> Intersection: `∅` (empty set — no file conflicts, safe to parallelize)

### Wave 2 (after Wave 1)
| Chunk | Steps | Files | Dependencies |
|-------|-------|-------|-------------|
| C | 7, 8 | `src/index.ts` | Chunk A, Chunk B |

**Recommended**: [N] parallel agents for Wave 1, then [M] for Wave 2 (or inline).
```

*   If the plan has no `**Depends**:` fields on any step → single chunk → skip visualization, behave like `§CMD_HANDOFF_TO_AGENT` (backward compatible).
*   If all steps are sequential (each depends on prior) → single chunk → skip visualization.

##### Step 4: Present Handoff Menu

Execute `AskUserQuestion` (multiSelect: false):

> "Phase [N]: Plan ready. [chunk_count] parallel chunks detected. How to proceed?"
> - **"Continue inline"** — Execute all steps sequentially in this conversation
> - **"1 agent"** — Hand off entire plan to a single agent (sequential execution)
> - **"[N] agents (recommended)"** — Launch [N] parallel agents, one per independent chunk
> - **"Custom agent count"** — Specify how many agents (1-5)
> - **"Revise the plan"** — Go back and edit the plan before proceeding

*   The recommended option shows the actual chunk count (capped at 5).
*   If chunk count is 1, omit the "[N] agents" option (only show inline / 1 agent / revise).

##### Step 5: Execute Based on User Choice

**"Continue inline"**: Return control to the parent command's build loop. Done.

**"1 agent"**: Execute `§CMD_HANDOFF_TO_AGENT` with the full plan (single agent, all steps sequential). Done.

**"Revise the plan"**: Return to the planning phase for revision. Done.

**"[N] agents" or "Custom agent count"**:

1.  **Determine Agent Count**: Use the recommended count or user's custom count (max 5). If custom count < chunk count, merge smallest chunks.
2.  **Construct Per-Chunk Task Prompts**: For each chunk, build a task prompt:

    ```
    You are executing a chunk of an approved plan as an autonomous agent.

    ## 1. Standards (Read These First)
    Read these files before doing anything:
    - ~/.claude/.directives/INVARIANTS.md
    - .claude/.directives/INVARIANTS.md (if exists)

    ## 2. Your Assignment
    Session directory: [sessionDir]
    Log file: [sessionDir]/[logFile]
    Log entry template: [logTemplate]

    You are executing **Chunk [X]** of the implementation plan.

    ### Your Steps
    [paste the specific plan steps for this chunk, with full detail]

    ### Your File Set
    [list of files this chunk touches]

    ### Rules
    - Log every action to the log file via: engine log [sessionDir]/[logFile]
    - Prefix EVERY log entry header with `[Chunk X]` for traceability
    - Follow the TDD cycle: write test (red), implement (green), refactor
    - Do NOT touch files outside your file set
    - Do NOT write a debrief — the parent will synthesize one
    - If you hit a blocker, log it as a 🚧 Block and continue with other steps if possible
    - If a step depends on another chunk's output, log it as a 😨 Stuck and stop that step

    ### Context Files (read these for understanding)
    [list contextFiles]

    ### Task Summary
    [taskSummary] — Chunk [X]: [chunk description]
    ```

3.  **Launch Agents**: For each chunk in the current wave, call the `Task` tool with:
    *   `subagent_type`: `[agentName]` (e.g., `"builder"`)
    *   `run_in_background`: `true`
    *   `prompt`: The per-chunk task prompt constructed above
    *   `description`: `"Chunk [X]: [brief]"`

    Launch ALL agents in the same wave simultaneously (parallel tool calls in a single message).

4.  **Poll Status**: After launching, periodically check agent status:
    *   Use `TaskOutput` with `block: false` to check each agent's progress.
    *   Report progress to user: "Chunk A: in progress, Chunk B: complete"
    *   Wait for all agents in the current wave to complete before launching the next wave.

5.  **Wave Sequencing**: If there are multiple waves:
    *   Launch Wave 1 agents in parallel.
    *   Wait for all Wave 1 agents to complete.
    *   Launch Wave 2 agents (which depend on Wave 1 outputs).
    *   Repeat until all waves complete.

6.  **Handle Failures**: If an agent fails:
    *   Log the failure: "Chunk [X] failed: [error summary]"
    *   Other agents continue unaffected.
    *   After all agents complete, report: "Chunks A, B completed. Chunk C failed — [reason]."
    *   Offer: "Retry failed chunk inline / Launch new agent / Skip and continue"

##### Step 6: Post-Agent Synthesis

After all agents complete (or fail):

1.  **Read Log File**: Read the full shared log file to understand what all agents did.
2.  **Check Plan**: Read the plan file for any unchecked `[ ]` steps. Flag incomplete work.
3.  **Synthesize Debrief**: The parent writes the unified debrief using `§CMD_GENERATE_DEBRIEF`. This covers ALL chunks, not just individual agent work.
4.  **Report**: Execute `§CMD_REPORT_ARTIFACTS` and `§CMD_REPORT_SUMMARY`.

---

#### Constraints

*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: All user-facing interactions in this command MUST use `AskUserQuestion`. Never drop to bare text for questions or routing decisions.
*   **Max 5 Agents**: Hard cap. If chunk count > 5, merge smallest chunks until count <= 5.
*   **Disjoint File Sets**: Chunks within the same wave MUST touch different files. The non-intersection proof is mandatory — if it fails, merge chunks.
*   **Shared Log**: All agents append to the SAME log file via `engine log`. Each entry prefixed with `[Chunk X]`.
*   **No Agent-to-Agent Communication**: Agents are isolated. They cannot read each other's output. Only the parent orchestrates.
*   **No Agent Debriefs**: Agents do NOT write debriefs. The parent synthesizes one unified debrief from all agent logs.
*   **Backward Compatible**: Plans without `**Depends**:` fields → single chunk → single-agent menu (identical to `§CMD_HANDOFF_TO_AGENT`).
*   **Opt-In Only**: Never launch parallel agents without user approval.
*   **Agents Receive INVARIANTS**: Each agent gets shared + project INVARIANTS. They do NOT receive the full skill protocol.

---

#### Examples

**Example 1 — 2 independent chunks**:
```
## Parallel Execution Analysis

**2 independent chunks detected across 1 wave.**

### Wave 1 (parallel)
| Chunk | Steps | Files | Dependencies |
|-------|-------|-------|-------------|
| A | 1, 2, 3 | `src/auth/login.ts`, `src/auth/login.test.ts` | None |
| B | 4, 5 | `src/auth/register.ts`, `src/auth/register.test.ts` | None |

> **Non-intersection proof (Wave 1):**
> Chunk A files: `{src/auth/login.ts, src/auth/login.test.ts}`
> Chunk B files: `{src/auth/register.ts, src/auth/register.test.ts}`
> Intersection: `∅` (empty set — safe to parallelize)

**Recommended**: 2 parallel agents for Wave 1.
```

> "Phase 4: Plan ready. 2 parallel chunks detected. How to proceed?"
> - "Continue inline"
> - "1 agent"
> - "2 agents (recommended)"
> - "Custom agent count"
> - "Revise the plan"

**Example 2 — No dependencies (backward compatible)**:
Plan steps have no `**Depends**:` fields → treated as single sequential chunk → menu shows:

> "Phase 4: Plan ready. How to proceed?"
> - "Launch builder agent" — Hand off to autonomous agent
> - "Continue inline" — Execute step by step
> - "Revise the plan"

(Identical to `§CMD_HANDOFF_TO_AGENT` behavior.)

**Example 3 — Multi-wave with sequential tail**:
```
## Parallel Execution Analysis

**3 chunks detected across 2 waves.**

### Wave 1 (parallel)
| Chunk | Steps | Files | Dependencies |
|-------|-------|-------|-------------|
| A | 1, 3 | `src/parser.ts` | None |
| B | 2, 4 | `src/renderer.ts` | None |

> **Non-intersection proof (Wave 1):**
> Chunk A ∩ Chunk B = ∅ — safe to parallelize

### Wave 2 (after Wave 1)
| Chunk | Steps | Files | Dependencies |
|-------|-------|-------|-------------|
| C | 5, 6, 7 | `src/index.ts`, `src/parser.ts`, `src/renderer.ts` | Chunk A, Chunk B |

**Recommended**: 2 agents for Wave 1, then Chunk C inline (touches files from both A and B).
```

---

## PROOF FOR §CMD_PARALLEL_HANDOFF

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "agents_launched": {
      "type": "string",
      "description": "Number and type of agents launched with chunk assignments"
    }
  },
  "required": ["agents_launched"],
  "additionalProperties": false
}
```
