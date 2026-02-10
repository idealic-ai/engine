# Contributing to Agents

Guide for creating, modifying, and testing workflow engine agents.

## Agent File Structure

Each agent is a markdown file with YAML frontmatter:

```yaml
---
name: myagent
description: What this agent does in one line
model: opus          # Optional: opus (default), sonnet, haiku
---
```

The body is a behavioral protocol written in second person ("You are a..."):

```markdown
# Agent Name (The Role Title)

You are a **Senior [Role]** specializing in [domain].

## Your Contract

You receive:
1. A plan file at `[sessionDir]/[PLAN].md`
2. A log file at `[sessionDir]/[LOG].md`
3. A session directory at `[sessionDir]`

You produce:
1. Working code changes (committed or staged)
2. Continuous log entries in `[LOG].md`
3. A debrief at `[sessionDir]/[DEBRIEF].md`

## Execution Loop

[Step-by-step protocol the agent follows]

## Boundaries

- Do NOT re-interrogate the user
- Do NOT explore beyond the plan
- Do NOT create session directories
- Do NOT modify files outside the plan scope
```

## Step-by-Step: Creating a New Agent

1. **Identify the need**: Is there an existing agent that covers this role? Check the Agent Index in `README.md`. Prefer extending an existing agent over creating a new one for similar roles.

2. **Choose the model tier**:
   - `opus` — Complex reasoning, multi-step planning, nuanced judgment
   - `sonnet` — Visual/multimodal tasks (image analysis, overlay review)
   - `haiku` — Fast, straightforward tasks (template filling, simple operations)
   - Omit to inherit from parent (default: opus)

3. **Write the agent file**: Create `agents/<name>.md` using the template above. Key sections:
   - **Role**: One-line persona with seniority level
   - **Contract**: Explicit inputs and outputs
   - **Execution Loop**: Step-by-step protocol
   - **Boundaries**: Explicit list of prohibited actions

4. **Create the symlink**: Run `engine.sh` to set up symlinks automatically (it calls `setup-lib.sh` which creates per-file symlinks from `engine/agents/*.md` to `~/.claude/agents/*.md`). Or manually:
   ```bash
   ln -s ~/.claude/engine/agents/myagent.md ~/.claude/agents/myagent.md
   ```

5. **Use the agent**: Agents are available immediately after symlinking:
   - CLI: `~/.claude/scripts/run.sh --agent myagent`
   - In skill protocol: `Task(subagent_type: "myagent", ...)`

6. **Update the README**: Add the agent to the Agent Index table in `agents/README.md`.

## Testing Agents

Agents don't have unit tests in the traditional sense. Instead:

1. **Dry run**: Invoke the agent via `Task(subagent_type: "myagent", prompt: "...")` with a test scenario
2. **Check contract compliance**: Verify the agent produced all specified outputs
3. **Check boundary compliance**: Verify the agent did NOT do anything in its Boundaries list
4. **Review quality**: Check that outputs follow templates and match expected quality

## Modifying Existing Agents

1. **Read `.directives/INVARIANTS.md`** — behavioral rules that apply to all agents
2. **Preserve the contract**: Don't change inputs/outputs without updating all callers
3. **Preserve boundaries**: Don't remove boundaries without understanding why they were added
4. **Test with the calling skill**: Each agent is invoked by specific skills (see the "Used By" column in README.md). Test within that skill's protocol.

## Common Patterns

### The Builder Pattern
Agents that produce code follow a strict loop: read plan -> for each step: test -> implement -> refactor -> log -> tick checkbox. The `builder` agent is the canonical example.

### The Analyzer Pattern
Agents that produce reports follow: read inputs -> synthesize findings -> write structured output. The `analyzer` and `critiquer` agents use this pattern.

### The Operator Pattern
General-purpose agents that execute protocols: read protocol -> follow steps -> log progress. The `operator` agent is intentionally generic as a fallback.

## Related Files

- `README.md` — Agent catalog and design principles
- `.directives/INVARIANTS.md` — Behavioral rules for agents
