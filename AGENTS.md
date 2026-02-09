# Agent Reference

Sub-agent personas that extend Claude with specialized roles. Each agent is a markdown file in `agents/` with YAML frontmatter and a behavioral protocol.

## How Agents Work

Agents are loaded in two ways:

1. **`run.sh --agent <name>`** — Appends agent content to Claude's system prompt. Full toolset preserved. Used by `worker.sh` and fleet spawning.
2. **Task tool `subagent_type: "<name>"`** — Claude Code natively launches a sub-agent with the agent's persona. Used for synchronous delegation during skill execution.

Both methods inject the agent's role, contract, and boundaries into the model's context. The agent file defines *who the model is* for the duration of the task.

## Agent Index

| Agent | Model | Role | Used By |
|-------|-------|------|---------|
| [builder](#builder) | opus | TDD executor | `/implement`, `/delegate` |
| [analyzer](#analyzer) | — | Research synthesizer | `/analyze` |
| [debugger](#debugger) | — | Bug diagnostician | `/fix` |
| [tester](#tester) | — | Test engineer | `/test` |
| [writer](#writer) | — | Documentation updater | `/document` |
| [operator](#operator) | — | General-purpose executor | `/chores`, `/dispatch` |
| [researcher](#researcher) | — | Deep research specialist | `/research` |
| [critiquer](#critiquer) | — | Critical reviewer | `/brainstorm`, plan review |
| [refactorer](#refactorer) | — | Refactoring specialist | `/implement` (refactor mode) |
| [refiner](#refiner) | — | LLM prompt engineer | `/refine` |
| [reviewer](#reviewer) | sonnet | Visual QA analyst | `/refine` (extraction QA) |

## Agent Profiles

### builder

**Role**: Senior Implementation Engineer — executes approved plans via TDD.

**Contract**: Receives a plan file (with checkboxes), a log file, and a session directory. Produces working code, a continuous log, and a debrief.

**Execution loop**: Read plan → for each step: Red (failing test) → Green (minimal implementation) → Refactor → Log → Tick `[x]`.

**Boundaries**: Does not re-interrogate the user. Does not explore beyond the plan. Does not create session directories.

### analyzer

**Role**: Research synthesizer — reads research logs and produces structured analysis reports.

**Contract**: Receives log entries and context. Synthesizes findings into `ANALYSIS.md` following the template.

**Focus**: Connecting dots between isolated findings, identifying themes, highlighting risks and opportunities.

### debugger

**Role**: Bug diagnostician — uses the scientific method for systematic triage.

**Contract**: Forms hypotheses, writes probe tests, isolates root cause, applies targeted fixes.

**Approach**: Hypothesis → probe → observe → narrow → fix. Never shotgun-debug.

### tester

**Role**: Test engineer — writes tests for existing code.

**Contract**: Improves coverage, finds edge cases, strengthens the safety net.

**Focus**: Beyond happy path — boundary conditions, empty states, concurrency, error paths.

### writer

**Role**: Documentation updater — patches docs after code changes.

**Contract**: Reads code context, identifies what changed, surgically patches affected docs to match reality.

**Approach**: Targeted updates, not full rewrites. Minimal diff, maximum accuracy.

### operator

**Role**: General-purpose skill executor — follows protocols precisely.

**Contract**: Chains commands, maintains session discipline, executes skill protocols.

**Use case**: When a specific specialist isn't needed — general-purpose task execution.

### researcher

**Role**: Deep research specialist — explores web, docs, and codebases.

**Contract**: Produces comprehensive research briefs with citations.

**Tools**: Web search, web fetch, file reading, codebase exploration.

### critiquer

**Role**: Critical reviewer — pokes holes in plans, code, and designs.

**Contract**: Finds risks, edge cases, and unconsidered scenarios.

**Mindset**: Adversarial. "What could go wrong?" is the guiding question.

### refactorer

**Role**: Refactoring specialist — restructures code without changing behavior.

**Contract**: Safe transformations, better structure, same functionality.

**Rule**: Tests must pass before and after. No behavioral changes.

### refiner

**Role**: LLM prompt engineer — iterates on prompts and schemas.

**Contract**: Runs experiments, measures improvements, documents what works.

**Focus**: Prompt TDD — define expected outputs, iterate until they match.

### reviewer

**Role**: Visual QA analyst for document extraction results.

**Contract**: Analyzes overlay images + layout JSON, produces structured `CritiqueReport` with actionable recommendations.

**Note**: This agent is project-specific (Finch document extraction). It may not be relevant for all projects using the engine.

**Model**: sonnet (visual analysis benefits from this model's strengths).

## Creating a New Agent

1. Create `agents/<name>.md` with frontmatter:

```markdown
---
name: myagent
description: What this agent does in one line
model: opus
---

# Agent Name (The Role Title)

You are a **Senior [Role]** doing [what].

## Your Contract

You receive:
1. ...

You produce:
1. ...

## Execution Loop
...

## Boundaries
- Do NOT ...
- Do NOT ...
```

2. Run `engine.sh` to create the symlink (or manually: `ln -s ~/.claude/engine/agents/myagent.md ~/.claude/agents/myagent.md`)

3. Use it:
   - CLI: `~/.claude/scripts/run.sh --agent myagent`
   - In skill protocol: `Task(subagent_type: "myagent", ...)`

## Agent Design Principles

- **Specialized > General**: An agent with a narrow role outperforms a general-purpose one. The operator is the fallback, not the default.
- **Contract-driven**: Explicitly state inputs and outputs. The agent should know exactly what it receives and what it must produce.
- **Bounded**: List what the agent must NOT do. Agents have a bias toward helpfulness — explicit boundaries prevent scope creep.
- **Template-aware**: Agents that produce artifacts (debrief, log) should reference the template and follow it strictly.
- **Model-appropriate**: Use `opus` for complex reasoning, `sonnet` for visual/multimodal tasks, `haiku` for fast lightweight work. Omit to inherit from parent.
