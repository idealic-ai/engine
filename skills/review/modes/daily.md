# Daily Mode (Gemini-First Progress Report)
*Bundles all session artifacts and sends directly to Gemini for report generation. Claude orchestrates discovery and delivery — Gemini does the reading and writing.*

**Role**: You are the **Daily Report Orchestrator**.
**Goal**: To discover session artifacts, bundle them efficiently, and hand off to Gemini for report generation.
**Mindset**: "Find the files, build the bundle, fire Gemini." Minimal Claude-side reading — Gemini has the context window for it.

## Key Principle
Claude does NOT read debriefs or logs into its own context. It discovers file paths, bundles them as `engine gemini` context file arguments, and lets Gemini read everything directly. This saves Claude's context window for orchestration.

## Phase Overrides

### Phase 0: Setup — Discovery Override
*Date-range discovery, model selection, skip tag scanning.*
1. Do NOT search for `#needs-review` / `#needs-rework` tags.
2. Ask the user via `AskUserQuestion` (1 question):
   - "What date range?" — Options: "Today", "Yesterday + Today", "This week", "Custom range"
   - Audience is always "Self" in daily mode (personal progress tracking).
3. Discover session directories by date range:
   - `engine find-sessions today` (or equivalent for the range)
   - For each session directory, check for `.state.json` existence
   - List all `.md` files per session (debriefs, logs, plans, dialogues)
4. Compile a file manifest with line counts. Report: "N sessions, M files, K total lines."
5. Skip context ingestion (`§CMD_INGEST_CONTEXT_BEFORE_WORK`) — not needed.
6. Auto-select Gemini 3 Pro (skip `§CMD_SUGGEST_EXTERNAL_MODEL` question).

#### Proof Override
> **Phase 0 proof:**
> - Mode: `daily`
> - Role: `Daily Report Orchestrator`
> - Date range: `________`
> - Sessions discovered: `________`
> - Files in bundle: `________`

### Phase 1: Discovery — File Collection Only
*Collect file paths. Do NOT read file contents.*
1. For each session directory in the date range:
   - Find debrief files (IMPLEMENTATION.md, ANALYSIS.md, FIX.md, DO.md, etc.)
   - Find log files (*_LOG.md)
   - Find plan files (*_PLAN.md) — include if they exist
   - Find dialogue files (DIALOGUE.md) — include if they exist
   - Record session metadata from `.state.json`: skill, lifecycle, taskSummary
2. Separate into two groups:
   - **Completed sessions**: Have debrief files (lifecycle=idle or completed)
   - **Active sessions**: Have only logs (lifecycle=active)
3. Log a summary to `REVIEW_LOG.md`:
   - Total sessions, completed vs active count
   - Total files and line counts
   - File manifest (paths only, no content)
4. Find the most recent previous REVIEW.md (from yesterday or earlier) as a style reference.
5. Do NOT read any debrief or log content. Do NOT log per-session cards.

#### Proof Override
> **Phase 1 proof:**
> - Sessions collected: `________`
> - Files in manifest: `________`
> - Previous report found: `________`

### Phase 2: Dashboard & Interrogation — Skip Entirely
*No dashboard, no interrogation, no user questions.*
1. Skip the chronological timeline presentation.
2. Skip the Standard Validation Checklist.
3. Skip per-debrief review.
4. Optionally ask ONE framing question:
   - "Anything to highlight or add context?" (with "No, just generate" as the recommended option)
5. If the user provides context, include it in the Gemini prompt as `KEY CONTEXT`.

#### Proof Override
> **Phase 2 proof:**
> - Skipped per daily mode: `true`
> - User context provided: `________`

### Phase 3: Synthesis — Gemini Direct Pipeline
*Bundle files and send to Gemini. Claude writes nothing.*
1. **Construct the `engine gemini` call**:
   - `--model gemini-3-pro-preview`
   - `--system "You are a senior technical reviewer producing a structured progress report. Output ONLY the document content in Markdown. Follow the template structure exactly. Write in flowing prose — no bullet points in the Accomplishments section. Weave specific numbers and technical details into sentences naturally."`
   - **Context files** (positional args): All discovered debrief files, then log files, then the previous report as style reference. Order: debriefs first (most structured), logs second (supporting detail), previous report last (style reference).
   - **Prompt** (stdin): The template + instructions (see below).

2. **Prompt template** (pipe via stdin heredoc):
   ```
   Write a progress report for [DATE] covering all the sessions provided as context files.

   TEMPLATE TO FOLLOW:
   [Paste TEMPLATE_REVIEW_PROGRESS.md content]

   KEY CONTEXT:
   - [N] total sessions. [M] completed with debriefs, [K] active/incomplete.
   - [User-provided context if any]
   - The LAST context file is a previous report — use it as a STYLE REFERENCE.

   IMPORTANT: The report should be 80-120 lines. Be specific and technical.
   Reference actual session findings, code changes, and metrics.
   ```

3. **Execute**: `engine gemini [options] [files...] <<'PROMPT' ... PROMPT`
4. **Capture output** and write to `sessions/[SESSION]/REVIEW.md`.
5. Add `#needs-review` tag to the generated file.
6. Skip finding triage (`§CMD_WALK_THROUGH_RESULTS`) — daily mode doesn't triage.
7. Do NOT perform cross-session conflict analysis.

#### Proof Override
> **Phase 3 proof:**
> - REVIEW.md written: `________` (real file path)
> - Generator: Gemini 3 Pro
> - Context files sent: `________`
> - Sessions covered: `________`

## Mode Template
**template**: `~/.claude/skills/review/assets/TEMPLATE_REVIEW_PROGRESS.md`

## Walk-Through Config
*Not applicable — daily reports skip triage entirely.*
**skip**: true
