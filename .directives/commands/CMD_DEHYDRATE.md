### §CMD_DEHYDRATE
**Definition**: Captures current session context and triggers a context overflow restart. Produces a JSON payload piped to `engine session dehydrate`, which stores it in `.state.json` and restarts Claude.

**Trigger**: Injected by the overflow hook as `§CMD_DEHYDRATE NOW` when context usage exceeds the threshold.

**Preloaded**: Always — this file is injected by SessionStart hook so it's available before overflow.

[!!!] CRITICAL: Context is likely near overflow. DO NOT read extra files. Use ONLY what's already in your context window.

---

## Algorithm

### Step 1: Set Lifecycle
```bash
engine session phase sessions/[CURRENT_SESSION] "[CURRENT_PHASE]"
```
This saves the current phase so the rehydrated agent knows where to resume.

### Step 2: Gather Context (From Memory Only)

[!!!] DO NOT call Read tool to load files. Use what's already loaded.

**Minimal I/O Allowed**:
1. `ls -F sessions/[CURRENT_SESSION]/` — see what artifacts exist
2. Review chat history for `§CMD_PARSE_PARAMETERS` output to recall `contextPaths`

**Collect**:
- **Summary**: Ultimate goal, strategy, completion status (e.g., "60% — core logic done, integration pending")
- **Last Action**: What you were doing when overflow hit. Outcome (succeed/fail/in-progress).
- **Next Steps**: Ordered list of immediate tasks. For proof-gated phases, include the proof fields needed.
- **Handover Instructions**: Anything the next agent must know that isn't in the artifacts.
- **User History**: Sentiment, key directives, recent feedback quotes.
- **Required Files**: All files the next agent needs. Cap at 8. Prioritize:
  1. Session artifacts: `_LOG.md`, `_PLAN.md`, `DETAILS.md`
  2. Source code being modified
  3. Skill protocol (e.g., `~/.claude/skills/implement/SKILL.md`)

**Path Conventions**:
| Prefix | Resolves To | Contains |
|--------|-------------|----------|
| `~/.claude/` | User home `~/.claude/` | Shared engine (skills, standards, scripts) |
| `.claude/` | Project root `.claude/` | Project-local config |
| `sessions/` | Project root `sessions/` | Session directories |
| `packages/`, `apps/`, `src/` | Project root | Source code |

### Step 3: Produce JSON and Dehydrate+Restart

Pipe the JSON to `engine session dehydrate`. This stores the content AND triggers restart.

```bash
engine session dehydrate sessions/[CURRENT_SESSION] <<'EOF'
{
  "summary": "[Big picture — goal, strategy, status percentage]",
  "lastAction": "[What you were doing, outcome, code state]",
  "nextSteps": [
    "[Step 1 — most urgent]",
    "[Step 2]",
    "[Step 3]"
  ],
  "handoverInstructions": "[Specific guidance for next agent]",
  "userHistory": "[Sentiment, key directives, recent feedback]",
  "requiredFiles": [
    "sessions/[SESSION]/IMPLEMENTATION_LOG.md",
    "sessions/[SESSION]/IMPLEMENTATION_PLAN.md",
    "sessions/[SESSION]/DETAILS.md",
    "~/.claude/skills/[SKILL]/SKILL.md"
  ]
}
EOF
```

[!!!] WARNING: This command will kill the current Claude process. It is the LAST command you execute.

### Step 4: Display Summary (Before Restart)

Before the `engine session dehydrate` call, briefly announce in chat:
> Dehydrating session. Restart imminent.
> - **Session**: `[SESSION_DIR]`
> - **Phase**: `[CURRENT_PHASE]`
> - **Files preserved**: [N] required files

---

## JSON Schema

```json
{
  "summary": {
    "type": "string",
    "required": true,
    "description": "Big picture — ultimate goal, strategy, completion status"
  },
  "lastAction": {
    "type": "string",
    "required": true,
    "description": "What agent was doing when overflow hit, outcome, code state"
  },
  "nextSteps": {
    "type": "array",
    "items": "string",
    "required": true,
    "description": "Ordered list of immediate tasks for the next agent"
  },
  "handoverInstructions": {
    "type": "string",
    "required": false,
    "description": "Specific guidance for the next agent"
  },
  "userHistory": {
    "type": "string",
    "required": false,
    "description": "User sentiment, key directives, recent feedback"
  },
  "requiredFiles": {
    "type": "array",
    "items": "string",
    "required": true,
    "maxItems": 8,
    "description": "File paths to auto-preload on restart. Capped at 8."
  }
}
```

---

## Constraints

- **No file reads**: Context is near overflow. Trust your memory.
- **Cap at 8 files**: `requiredFiles` max 8 entries. Prioritize session artifacts > source code > templates.
- **Combined command**: `engine session dehydrate` both stores AND restarts. Do not call `engine session restart` separately.
- **JSON only**: Content must be valid JSON. The engine validates before storing.
- **Auto-injected files**: COMMANDS.md, INVARIANTS.md, TAGS.md, CMD_DEHYDRATE.md, CMD_RESUME_SESSION.md are auto-injected by SessionStart. Do NOT list them in requiredFiles.

---

## PROOF FOR §CMD_DEHYDRATE

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "dehydrated": {
      "type": "boolean",
      "description": "Whether dehydration JSON was piped to engine session dehydrate"
    },
    "files_listed": {
      "type": "number",
      "description": "Number of required files in the JSON payload"
    }
  },
  "required": ["dehydrated", "files_listed"],
  "additionalProperties": false
}
```
