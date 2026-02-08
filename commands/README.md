# Workflow Engine

A structured command system for Claude Code that turns AI-assisted development into a repeatable, auditable process. Shared across all projects via `~/.claude/commands/`.

## The Happy Path

Most features follow this workflow. Each step is a separate Claude Code session with its own log and debrief — the output of one step feeds directly into the next.

1. **Analyze** (`/analyze`) — Understand the terrain before making plans. Read code, docs, patterns. Produce a research report.
2. **Brainstorm** (`/brainstorm`) — Explore the problem space with the human. Socratic dialogue. Challenge assumptions. Converge on decisions.
3. **Document** (`/document`) — Write the docs BEFORE the code. Update architecture docs, specs, invariants to reflect the decision. Optionally `/dehydrate` to pause here.
4. **Implement** (`/implement`) — Build it. TDD. Strict logging. Plan, red, green, refactor. Every decision recorded.
5. **Test** (`/test`) — Verify it. Go beyond the happy path. Edge cases, regressions, integration. Fill coverage gaps.
6. **Evangelize** (`/evangelize`) — Sell the work. Frame it for stakeholders. What was built, why it matters, how to adopt it.
7. **Review** (`/review`) — End-of-day review. Approve or reject debriefs. Cross-session conflict detection.
8. **Report** (`/summarize-progress`) — Generate a progress summary. What was done, what's pending, what's blocked.

Not every feature needs all 8 steps. Skip `/analyze` if you already know the codebase. Skip `/evangelize` for internal-only changes. The point is that each command slots into a known position — you always know what comes next.

### Docs-First, Not Docs-After

Step 3 is intentionally before Step 4. Updating documentation before writing code forces you to articulate the design in plain language. If the doc update is hard to write, the design probably isn't clear enough yet. The docs become the spec; the code becomes the implementation of the spec.

### Session Handoff

Any step can end with `/dehydrate`, which serializes the session state and copies it to your clipboard. To resume in a new session, just paste it as context into the next command — e.g. `/implement <paste>`. That's all it takes. Works across machines and team members.

## Why This Approach

### Every session produces artifacts

Every command creates a session directory (`sessions/YYYY_MM_DD_TOPIC/`) with a log, a plan (if applicable), and a debrief. Nothing is lost to chat history. Six months from now, you can read exactly why a decision was made, what alternatives were considered, and what was explicitly rejected.

### Commands compose into pipelines

Each command's output is the next command's input. The brainstorm debrief feeds into the implementation plan. The implementation debrief feeds into the test plan. The test results feed into the evangelize narrative. This isn't accidental — the templates are designed to chain.

### Explicit context management

Claude doesn't silently read your whole codebase. Each session starts with a controlled context ingestion phase — you choose exactly what files Claude sees. This prevents "context drift" where the agent gets distracted by unrelated code and keeps sessions focused on the task at hand.

### Cross-validation between sessions

`/review` reads ALL unvalidated session debriefs and checks them against each other. Did two sessions make contradictory decisions? Did an implementation deviate from its brainstorm? The review step catches drift before it compounds.

### Paper trail on Google Drive

Session artifacts are stored on a Google Drive Shared Drive, organized per-person and per-project. Anyone on the team can browse anyone else's session history. When someone asks "why did we build it this way?", the answer is in a dated, tagged markdown file — not buried in a Slack thread.

### Alerts announce work in progress

Alerts are opt-in. When you know upcoming work will temporarily break things — failing tests, changed interfaces, renamed files, shifted expectations — you post an alert (`/alert-raise`) to announce it. New agent sessions scan for active alerts (`#active-alert`) and load them into context, so they don't waste time debugging your intentional breakage. When the work is done, `/alert-resolve` removes it from the active feed. Most sessions don't need an alert. Use them when other agents need to know something is in flight.

### Daily progress reports

`/summarize-progress` scans recent sessions and generates a structured summary. What shipped, what's in progress, what's blocked. No manual standup notes. The session logs ARE the progress data.

## Command Reference

### Core Workflow

| Command | Description |
|---------|-------------|
| `/analyze` | Deep-dives into a specific topic — reads code, docs, and patterns to produce a structured research report. |
| `/brainstorm` | Explores a problem space through Socratic dialogue — challenges assumptions, maps trade-offs, and converges on decisions. |
| `/implement` | Builds a feature or change using strict TDD — plans first, writes failing tests, implements, logs every decision. |
| `/debug` | Diagnoses a bug using the scientific method — forms hypotheses, runs probes, isolates root cause, and fixes. |
| `/test` | Designs and runs tests — explores edge cases, verifies existing behavior, catches regressions. |

### Documentation

| Command | Description |
|---------|-------------|
| `/document` | Surgically patches documentation after code changes — finds affected docs and makes targeted updates to match reality. |
| `/refine-docs` | Restructures and clarifies existing documentation — consolidates scattered content, improves readability, fixes staleness. |

### Session Management

| Command | Description |
|---------|-------------|
| `/chores` | Works through a queue of small housekeeping tasks in a single session with lightweight logging. |
| `/edit-command` | Creates or edits project-specific commands in `.claude/` — scaffolds boot files, prompts, and templates following engine conventions. |
| `/share-command` | Promotes a project-local command to the shared engine on Google Drive — diffs against existing version, confirms, then copies all associated files. |
| `/dehydrate` | Serializes the current session into a portable snapshot, copies it to clipboard. Paste into the next command to resume. |
| `/details` | Records a structured Q&A exchange — captures user assertions, agent responses, and decisions verbatim. |
| `/summarize-progress` | Generates a progress summary across sessions — what was done, what is pending, and what is blocked. |
| `/find-sessions` | Searches sessions by tags, date, topic, content, and more. Supports shallow metadata search and deep content search. |
| `/review` | Reviews agent work by validating unvalidated session debriefs, detecting cross-session conflicts, and guiding structured approval. |

### Cross-Session Communication

| Command | Description |
|---------|-------------|
| `/alert-raise` | Posts a cross-session alert about in-flight work — creates a tagged alert so other agents know what's intentionally broken or changing. |
| `/alert-resolve` | Resolves an active alert — verifies all work is complete, marks the alert as done, and removes it from the active feed. |
| `/delegate` | Full delegation lifecycle — interrogates, posts a delegation request, hands off to a builder agent via Task tool, and presents the result. |
| `/delegate-request` | Posts a cross-session delegation request — creates a tagged `DELEGATION_REQUEST_[TOPIC].md` in the current session. |
| `/delegate-respond` | Discovers open delegation requests and posts structured responses — finds `#needs-delegation` files, creates `DELEGATION_RESPONSE_[TOPIC].md`, and links them with breadcrumbs. |
| `/decide` | Surfaces deferred decisions (`#needs-decision`) across sessions, presents context, records the user's call in `DECISIONS.md`. |
| `/research` | Full research lifecycle — crafts a research question, calls Gemini Deep Research, and delivers the result. |
| `/research-request` | Posts a research request for Gemini Deep Research to address. |
| `/research-respond` | Discovers open research requests, calls Gemini, and posts the result. |

### Engine Management

| Command | Description |
|---------|-------------|
| `/edit-command` | Creates or edits project-specific commands in `.claude/` — scaffolds boot files, prompts, and templates following engine conventions. |
| `/share-command` | Promotes a project-local command to the shared engine on Google Drive — diffs against existing version, confirms, then copies all associated files. |

### Review & Strategy

| Command | Description |
|---------|-------------|
| `/critique` | Audits code or architecture against project standards and invariants — finds violations, smells, and drift. |
| `/suggest` | Scans code or architecture for improvement opportunities — proposes concrete, actionable changes with trade-off analysis. |
| `/evangelize` | Sells completed work — frames results for stakeholders, explores adoption angles, and generates enthusiasm for what was built. |


## Naming Convention

- **Commands**: verb form, kebab-case (`analyze`, `refine-docs`, `document`, `delegate-request`)
- **Prompts**: verb form, UPPER_SNAKE (`ANALYZE.md`, `REFINE_DOCS.md`, `DOCUMENT.md`, `DELEGATE_REQUEST.md`)
- **Templates**: session-type noun, UPPER_SNAKE (`ANALYSIS.md`, `ANALYSIS_LOG.md`, `ANALYSIS_PLAN.md`)

## Adding Project-Specific Commands

Use `/edit-command <name>` to scaffold a new project-specific command or create a local override of a shared engine command. All output goes to your project's `.claude/` directory (commands, prompts, templates). If a project command has the same name as a shared command, the project version takes priority.
