### §CMD_PARSE_PARAMETERS
**Definition**: Parse and validate the session parameters before execution.
**Rule**: Execute this immediately after `§CMD_MAINTAIN_SESSION_DIR` (or as part of setup). This command outputs the "Flight Plan" for the session.

**Schema**:
```json
{
  "type": "object",
  "title": "Session Parameters",
  "required": ["sessionDir", "taskType", "taskSummary", "scope", "directoriesOfInterest", "contextPaths", "planTemplate", "logTemplate", "debriefTemplate", "requestTemplate", "responseTemplate", "requestFiles", "nextSkills", "extraInfo", "phases"],
  "properties": {
    "sessionDir": {
      "type": "string",
      "title": "Session Directory",
      "description": "Absolute or relative path to the active session folder.",

      "setByScript": true
    },
    "taskType": {
      "type": "string",
      "title": "Task Type",
      "description": "The active mode of operation. Skills define their own task types."
    },
    "taskSummary": {
      "type": "string",
      "title": "Task Summary",
      "description": "Concise summary of the user's prompt/goal.",
    },
    "scope": {
      "type": "string",
      "title": "Scope of Work",
      "description": "Operational boundaries and sanity check (e.g., 'Discussion Only', 'Code Changes Allowed'). Prevents phase leakage.",
    },
    "directoriesOfInterest": {
      "type": "array",
      "title": "Working Directories / Directories of interest",
      "description": "Explicit directories targeted for this task (source code, docs, etc.).",
      "items": { "type": "string" },
    },
    "contextPaths": {
      "type": "array",
      "title": "Project Context Paths",
      "description": "User-specified files/directories to load in Phase 2.",
      "items": { "type": "string" },
    },
    "ragDiscoveredPaths": {
      "type": "array",
      "title": "RAG-Discovered Paths",
      "description": "Paths discovered via RAG search during setup. These are suggested by semantic search over session logs, docs, and codebase — not explicitly requested by the user. Merged with contextPaths during ingestion, but displayed separately so the user can review/prune.",
      "items": {
        "type": "object",
        "properties": {
          "path": { "type": "string", "description": "File or directory path" },
          "reason": { "type": "string", "description": "Why RAG suggested this (e.g., 'similar past session', 'mentions same component')" },
          "confidence": { "type": "string", "enum": ["high", "medium", "low"], "description": "RAG confidence level" }
        },
        "required": ["path", "reason"]
      },
    },
    "directives": {
      "type": "array",
      "items": { "type": "string" },
      "title": "Skill Directives",
      "description": "Directive file types this skill cares about beyond the core set (README.md, INVARIANTS.md, CHECKLIST.md are always discovered). Derived from the skill's Required Context section: if SKILL.md loads `.claude/.directives/X.md`, include `X.md` here. Convention: editing skills (implement, fix, test, refine, document) load PITFALLS.md and CONTRIBUTING.md; testing skills (implement, fix, test) load TESTING.md. See ¶INV_DIRECTIVE_STACK.",
    },
    "planTemplate": {
      "type": "string",
      "title": "Plan Template Path",
      "description": "Path to the plan template (if applicable).",
    },
    "logTemplate": {
      "type": "string",
      "title": "Log Template Path",
      "description": "Path to the log template (if applicable).",
    },
    "debriefTemplate": {
      "type": "string",
      "title": "Debrief Template Path",
      "description": "Path to the debrief template.",
    },
    "requestTemplate": {
      "type": "string",
      "title": "Request Template Path",
      "description": "Path to the REQUEST template (if this skill supports delegation).",
    },
    "responseTemplate": {
      "type": "string",
      "title": "Response Template Path",
      "description": "Path to the RESPONSE template (if this skill supports delegation).",
    },
    "requestFiles": {
      "type": "array",
      "items": { "type": "string" },
      "title": "Request Files",
      "description": "Request files this session is fulfilling. Supports two types: formal REQUEST files (filename contains 'REQUEST') and inline-tag source files (any other file with #needs-* tags). Validated by `engine session check` Validation 3 (¶INV_REQUEST_BEFORE_CLOSE).",
    },
    "nextSkills": {
      "type": "array",
      "items": { "type": "string" },
      "title": "Next Skill Options",
      "description": "Skills to suggest after session completion. Used by §CMD_CLOSE_SESSION for the post-session menu. Each skill declares its own nextSkills in SKILL.md. Required field.",
    },
    "extraInfo": {
      "type": "string",
      "title": "Extra Info",
      "description": "Any additional context or constraints.",
    },
    "phases": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["major", "minor", "name"],
        "properties": {
          "major": {
            "type": "integer",
            "description": "Major phase number (1, 2, 3, ...). Main phases from the skill protocol."
          },
          "minor": {
            "type": "integer",
            "description": "Minor phase number (0 for main phases, 1+ for sub-phases). E.g., major=4 minor=0 is '4: Planning', major=4 minor=1 is '4.1: Agent Handoff'."
          },
          "name": {
            "type": "string",
            "description": "Short phase name (e.g., 'Setup', 'Context Ingestion'). Label is derived: minor=0 → 'N: Name', minor>0 → 'N.M: Name'."
          }
        }
      },
      "title": "Session Phases",
      "description": "Ordered list of phases for this skill session. These MUST correspond to the phases defined in the skill's SKILL.md protocol. Phase enforcement ensures sequential progression — non-sequential transitions (skip forward or go backward) require explicit user approval via --user-approved flag on `engine session phase`. Sub-phases (minor > 0) can be auto-appended during the session without pre-declaration. Labels are derived from major/minor/name — not stored."
    }
  }
}
```

**Algorithm**:
1.  **Analyze**: Review the user's prompt and current context to extract the parameters.
2.  **Construct**: Create the JSON object matching the schema.
3.  **Activate Session**: Pipe the JSON to `engine session activate` via heredoc (see `§CMD_SESSION_CLI` for exact syntax). The JSON is stored in `.state.json` (merged with runtime fields) and activate returns context (alerts, delegations, RAG suggestions). Do NOT output the JSON to chat — it is stored by activate.
    *   The agent reads activate's stdout for context sections (## §CMD_SURFACE_ACTIVE_ALERTS, ## §CMD_RECALL_PRIOR_SESSIONS, ## §CMD_RECALL_RELEVANT_DOCS, ## §CMD_DISCOVER_DELEGATION_TARGETS).
    *   activate uses `taskSummary` from the JSON to run thematic searches via session-search and doc-search automatically.
    *   **No-JSON calls** (e.g., re-activation without new params): use `< /dev/null` to avoid stdin hang.
4.  **Process Context Output**: Parse activate's Markdown output to identify the context categories (Alerts, RAG:Sessions, RAG:Docs). These are consumed by `§CMD_INGEST_CONTEXT_BEFORE_WORK`, which curates the best results and builds the multichoice menu in Phase 1.
