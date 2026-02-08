# /refine — Iterative Prompt & Schema Refinement

TDD methodology for LLM workloads. Systematically improve extraction accuracy through controlled experiments.

## Quick Start

```bash
# First run — interrogation builds manifest
/refine

# Subsequent runs — use existing manifest
/refine --manifest packages/estimate/refine.manifest.json

# Focus on one problematic case
/refine --manifest path/to/manifest.json --case cases/edge-case-1/input.png

# Fully automated (5 iterations max)
/refine --manifest path/to/manifest.json --auto

# Preview what would happen
/refine --manifest path/to/manifest.json --dry-run
```

## Flags

| Flag | Description |
|------|-------------|
| `--manifest <path>` | Use existing manifest (skips interrogation) |
| `--auto` | Run iterations automatically (default: suggestion mode) |
| `--iterations N` | Max iterations for auto mode (default: 5) |
| `--case <path>` | Focus on single case instead of all cases |
| `--continue` | Resume from last iteration in session |
| `--dry-run` | Show what would happen without executing |

## How It Works

### The Loop

```
1. INTERROGATE → Build manifest (first run only)
2. VALIDATE    → Single-case test to verify manifest works
3. BASELINE    → Run all cases, establish metrics
4. ITERATE     → Analyze → Critique → Hypothesize → Suggest → Apply → Measure
5. SYNTHESIZE  → Generate debrief with iteration history
```

### Analysis Pipeline

Each iteration performs:

1. **JSON Diff** — Compare output to expected (if `expectedPaths` configured)
2. **Visual Critique** — Claude analyzes overlay images for extraction errors
3. **Custom Validators** — Run `validationScripts` for domain-specific checks
4. **Hypothesis Formation** — Synthesize findings into actionable insight
5. **Surgical Edit** — Propose specific prompt/schema changes
6. **Impact Measurement** — Re-run cases, compare metrics

## Manifest Schema

```json
{
  "workloadId": "estimate-extraction",
  "promptPaths": ["packages/estimate/src/schemas/prompts.ts"],
  "schemaPaths": ["packages/estimate/src/schemas/page-data.ts"],
  "casePaths": ["fixtures/*/input.png"],
  "expectedPaths": ["fixtures/*/expected.json"],
  "runCommand": "npx tsx scripts/extract.ts --input {case}",
  "outputPath": "tmp/output/{case}.json",
  "overlayCommand": "npx tsx scripts/overlay.ts --data {output} --image {case}",
  "validationScripts": ["npx tsx scripts/check-no-overlap.ts --input {output}"],
  "critiquePrompt": "Focus on bounding box accuracy...",
  "maxIterations": 5
}
```

### Required Fields

- `workloadId` — Unique identifier
- `promptPaths` — Files that may be edited during refinement
- `casePaths` — Glob patterns for test inputs (images, JSON, whatever)
- `runCommand` — Shell command to run extraction (`{case}` placeholder)
- `outputPath` — Where extraction writes output (`{case}` placeholder)

### Optional Fields

- `schemaPaths` — Schema files that may be edited
- `expectedPaths` — Expected outputs for comparison (visual-only mode if omitted)
- `overlayCommand` — Generate visual overlay (`{output}`, `{case}` placeholders)
- `validationScripts` — Custom invariant checks
- `critiquePrompt` — Override default visual critique prompt
- `critiqueScript` — Use custom script instead of Claude for critique
- `maxIterations` — Limit for `--auto` mode (default: 5)

## Session Artifacts

```
sessions/YYYY_MM_DD_WORKLOAD_REFINE/
├── REFINE_LOG.md      # Experiment journal (append-only)
├── REFINE.md          # Session debrief
├── DETAILS.md         # Interrogation Q&A
└── manifest.json      # Copy of manifest used (if created)
```

## Log Thought Categories

The experiment log uses these categories:

| Emoji | Category | When to Use |
|-------|----------|-------------|
| 🎯 | Iteration Start | Beginning of each iteration with baseline |
| 🧪 | Experiment | Recording a prompt/schema change |
| 🔬 | Hypothesis | Theory about why something fails |
| 👁️ | Critique | Visual analysis findings |
| 📊 | Result | Iteration outcome (pass/fail counts) |
| 📈 | Metrics | Quantitative snapshot with deltas |
| 🔧 | Suggestion | Proposed edit with rationale |
| ✏️ | Edit Applied | Confirmation of change |
| ⚠️ | Regression | Metrics got worse |
| 🛑 | Validation Failure | Manifest config error |
| 🏁 | Iteration Complete | Loop termination reason |
| 💡 | Insight | Generalizable discovery |
| 🅿️ | Parking Lot | Deferred item |

## Design Principles

### Invariants

- **§INV_MANIFEST_COLOCATED** — Manifests live with workload code, not central registry
- **§INV_SURGICAL_SUGGESTIONS** — LLM sees actual prompt content for precise edits
- **§INV_NO_SILENT_REGRESSION** — Degraded metrics are always flagged
- **§INV_VALIDATE_BEFORE_ITERATE** — Single-case test before committing to loop
- **§INV_VISUAL_ONLY_VALID** — No `expectedPaths` required; visual analysis alone works

### Regression Handling

Regressions are **logged, not reverted**. The experiment log is append-only:

```
Iteration 1: +2 passing (good)
Iteration 2: -1 passing (regression logged)
Iteration 3: Try different hypothesis based on iteration 2 failure
```

This preserves the experimental record. Failed experiments are valuable data.

## Example Workflow

```bash
# 1. Create manifest via interrogation
/refine
# → Answers questions about workload
# → Validates with single case
# → Saves manifest to packages/estimate/refine.manifest.json

# 2. Run baseline
# → 12/15 cases passing (80%)

# 3. Iteration 1
# → Critique identifies bounding box drift on page 2+
# → Hypothesis: coordinate system guidance missing
# → Suggestion: Add "coordinates are page-relative" to prompt
# → Apply edit
# → Re-run: 14/15 passing (+2)

# 4. Iteration 2
# → Remaining failure is OCR quality issue, not prompt
# → Log insight, stop iteration

# 5. Debrief generated with full history
```

## Philosophy

### The Core Insight: Prompts Are Code

Traditional software has tests. You write code, run tests, see red/green. When tests fail, you debug, fix, re-run. The feedback loop is tight and empirical.

**LLM prompts have no equivalent.** You write a prompt, run it against some inputs, eyeball the output, tweak words, hope it gets better. There's no systematic methodology — it's vibes-based engineering.

`/refine` treats prompts like code that deserves TDD:
- **Cases** (not "test data") define what correctness looks like
- **Metrics** (not "gut feel") measure improvement
- **Hypotheses** (not "random tweaks") drive changes
- **Logs** (not "memory") preserve what you tried

### Why "Cases" Not "Fixtures"

"Fixture" is programmer jargon for test scaffolding. But `/refine` is for anyone iterating on LLM behavior — they might be working with images, PDFs, audio transcripts, whatever. "Case" is neutral: it's just an input you want to handle correctly.

### The Append-Only Experiment Log

Science doesn't revert failed experiments — it documents them. If iteration 3 makes things worse, that's *information*:
- What hypothesis led there?
- What cases regressed?
- What does that tell us about the problem space?

Git-style revert destroys this context. The log preserves the full experimental record. Failed experiments are as valuable as successful ones — they constrain the solution space.

### Manifest as Contract

The manifest is a declarative description of "what is this workload." It separates:
- **What** to run (cases, commands, outputs)
- **How** to iterate (the protocol handles this)

This means you can hand a manifest to a colleague (or a future you) and they can immediately run refinement without understanding the codebase deeply. The manifest is the API contract between the workload and the skill.

### Colocated Manifests

The manifest lives *with the code it describes* (e.g., `packages/estimate/refine.manifest.json`), not in a central registry. Why?

1. **Versioning**: When the prompt changes, the manifest can change in the same PR
2. **Discovery**: `ls` the directory, see the manifest
3. **Ownership**: The team that owns the workload owns its refinement config

### Visual Critique as First-Class Citizen

JSON diff tells you *what* is wrong. Visual critique tells you *why*.

A bounding box that's 10px off might diff as "wrong coordinates" — but the visual shows it's consistently drifting right on multi-column layouts. That's actionable. The diff alone isn't.

Claude looking at the overlay is doing what a human would do: pattern-matching on visual artifacts to form hypotheses about root causes.

---

## Reviewer Agent

Visual critique is handled by a specialized sub-agent that runs as part of the iteration loop.

### What It Does

The **reviewer agent** (`~/.claude/agents/reviewer.md`) analyzes overlay images alongside extracted JSON to identify extraction errors. It:

1. Reads overlay PNGs showing bounding boxes drawn over source documents
2. Cross-references with the extraction JSON (what was claimed to be found)
3. Runs 15+ checks from a structured checklist
4. Returns a `CritiqueReport` with issues and actionable recommendations

### When It Runs

During each iteration (Phase 6 Step B), `/refine` spawns the reviewer:

```
Task(subagent_type="reviewer", prompt=`
  Review extraction results for case ${caseId}.

  **Images**: tmp/layout-overlay-page-3.png, tmp/layout-overlay-page-5.png
  **Layout JSON**: tmp/layout.json
  **Pages**: 3, 5

  Return CritiqueReport JSON.
`)
```

### CritiqueReport Schema

```json
{
  "caseId": "case-003",
  "overallScore": 75,
  "summary": "Table bounds mostly correct. 2 scope overlaps on page 5.",
  "pages": [
    {
      "pageNumber": 3,
      "score": 80,
      "issues": [...],
      "observations": ["Scope header correctly detected"]
    }
  ],
  "issues": [
    {
      "type": "TABLE_TOP_EDGE",
      "severity": "error",
      "description": "Table starts at data row, missing column header",
      "pageNumber": 3,
      "location": "middle of page",
      "jsonPath": "scopes[0].tables[0].box_2d"
    }
  ],
  "recommendations": [
    {
      "target": "TABLE_PROMPT",
      "action": "Add: 'Table MUST start at column header row'",
      "rationale": "Page 3 table missed header",
      "priority": "high"
    }
  ]
}
```

### Checklist (§CRITIQUE_CHECKLIST)

**Table Bounds**:
- `TABLE_TOP_EDGE` — Box starts at column header row (DESCRIPTION | QTY | ...)
- `TABLE_BOTTOM_EDGE` — Box ends before scope total
- `TABLE_INCLUDES_GROUP_HEADERS` — Trade names (GUTTERS, CLEANING) inside table
- `TABLE_MISSING_COMMENT` — Comment rows inside table box
- `TABLE_INCLUDES_TOTAL` — Scope total NOT inside table (error if it is)

**Scope Detection**:
- `SCOPE_HEADER_DETECTED` — Every scope has a header box
- `SCOPE_TOTAL_DETECTED` — Every scope has a total box
- `SCOPE_NO_OVERLAP` — Sibling scopes don't overlap
- `SCOPE_TYPE_CORRECT` — ROOM/SUBROOM/GROUP correctly identified

**Structural**:
- `DIAGRAM_DETECTED` — Floor plans have diagram boxes
- `METRICS_DETECTED` — Area/perimeter blocks detected
- `BREADCRUMBS_DETECTED` — Hierarchy path captured

**Consistency**:
- `BOX_MATCHES_CONTENT` — Coordinates match visible content
- `COUNT_MATCHES` — Element counts match visual
- `NO_PHANTOM_ELEMENTS` — No false positive boxes

### Scoring

| Score | Meaning |
|-------|---------|
| 90-100 | Near-perfect extraction |
| 70-89 | Good, some boundary issues |
| 50-69 | Significant issues |
| 0-49 | Major failures |

### Manual Override

If `--manual-critique` is passed and `overallScore < 70`:
- Images are presented to the user for confirmation
- User can add issues the agent missed
- User can reject false positives

### Legacy: Custom Critique

If `critiqueScript` is specified in the manifest, that script runs instead of the reviewer agent. Use this for domain-specific critique logic that can't be expressed in prompts.

### Suggestion Mode vs Auto Mode

Two valid workflows:
1. **Suggestion mode**: You're learning the workload. You want to see each proposed change, understand the reasoning, approve or modify. The skill is a collaborator.
2. **Auto mode**: You trust the methodology. Let it run 5 iterations overnight, review the debrief in the morning. The skill is an agent.

Both are valid. The flag lets you choose based on context.

---

**TL;DR**: `/refine` applies the scientific method to prompt engineering. Measure, hypothesize, experiment, record. Treat prompts with the same rigor you'd treat code.

## Future (v1.1)

- Parallel case execution (`concurrency: N`)
- Parallel experiments (A/B test prompt variants)
- Experiment branching (fork from iteration N)

---

*Created: 2026-02-05 | Session: sessions/2026_02_05_PROMPT_TDD_SKILL*
