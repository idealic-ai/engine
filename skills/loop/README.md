# /loop — Hypothesis-Driven Iteration Engine

Iterative improvement of any LLM workload through the scientific method: hypothesize, execute, review, analyze, decide, edit.

## Quick Start

```
/loop                           # Start fresh — guided manifest creation
/loop --manifest path/to/m.json # Use existing manifest
/loop --continue                # Resume from last iteration
/loop --case path/to/case.json  # Focus on a single case
```

## The 6-Step Cycle

```
HYPOTHESIZE → RUN → REVIEW → ANALYZE → DECIDE → EDIT
     ↑                                            │
     └────────────────────────────────────────────┘
```

1. **HYPOTHESIZE** — Form a prediction about what's causing failures and what change will fix them
2. **RUN** — Execute the workload (`runCommand`) on all cases
3. **REVIEW** — Evaluate quality (`evaluateCommand`) and collect critiques
4. **ANALYZE** — Invoke the Composer subagent for deep root cause analysis and 3 strategic options
5. **DECIDE** — User chooses which option to apply (or skips with feedback)
6. **EDIT** — Apply the chosen change to artifact files

## Modes

| Mode | Strategy | When to Use |
|------|----------|-------------|
| **Precision** | Isolate one variable per iteration, minimize blast radius | Surgical fixes, known failure patterns |
| **Exploration** | Bold changes, tolerate regressions, seek breakthroughs | Stuck in local maximum, need paradigm shift |
| **Convergence** | Tighten tolerances, harden edge cases | Close to target, need to close remaining gaps |
| **Custom** | User-defined iteration strategy | Specialized workloads |

## Protocol Phases

| Phase | Name | Purpose |
|-------|------|---------|
| 0 | Setup | Mode selection, manifest check, role assumption |
| 1 | Interrogation | Build workload manifest through guided questioning |
| 2 | Planning | Form hypotheses, design experiments, select cases |
| 3 | Calibration | Single-case pipeline test before full loop |
| 4 | Baseline | Run all cases to establish starting metrics |
| 5 | Iteration Loop | The core 6-step cycle (repeated up to maxIterations) |
| 6 | Synthesis | Debrief, pipeline, close |

## Workload Manifest

The manifest (`loop.manifest.json`) configures the workload. Key fields:

- `workloadId` — Unique identifier
- `artifactPaths` — Files that may be modified (prompts, schemas, configs)
- `casePaths` — Glob patterns for test case inputs
- `runCommand` — Command to execute workload (`{case}` placeholder)
- `outputPath` — Where output is written (`{case}` placeholder)
- `evaluateCommand` — Command to assess quality
- `agents.composer.promptFile` — Composer subagent prompt
- `maxIterations` — Iteration limit (default: 10)

See `assets/MANIFEST_SCHEMA.json` for the full schema.

## The Composer Subagent

The Composer is a Claude subagent (via Task tool) that performs deep analytical reasoning:
- Receives all artifact content, evaluation critiques, and iteration history
- Produces root cause analysis and exactly 3 strategic fix options
- All suggestions must be **structural** prompt engineering techniques (not surface-level)

Prompt template: `assets/COMPOSER_PROMPT.md`

## Key Invariants

- **§INV_HYPOTHESIS_AUDIT_TRAIL** — Every iteration must produce a hypothesis record (prediction + outcome)
- **§INV_REVIEW_BEFORE_COMPOSE** — Composer receives evaluation results, never raw outputs alone
- **§INV_COMPOSER_STRUCTURAL_FIXES** — Suggestions must specify concrete mechanisms
- **§INV_NO_SILENT_REGRESSION** — Regressions are surfaced with options, never silently accepted
- **§INV_VALIDATE_BEFORE_ITERATE** — Single-case calibration before the full loop

## Assets

| File | Purpose |
|------|---------|
| `SKILL.md` | Full protocol definition |
| `assets/MANIFEST_SCHEMA.json` | Workload manifest JSON Schema |
| `assets/COMPOSER_PROMPT.md` | Composer subagent prompt template |
| `assets/TEMPLATE_LOOP_LOG.md` | Log entry schemas |
| `assets/TEMPLATE_LOOP.md` | Debrief template |
| `assets/TEMPLATE_LOOP_PLAN.md` | Experiment plan template |
| `assets/TEMPLATE_LOOP_REQUEST.md` | Delegation request template |
| `assets/TEMPLATE_LOOP_RESPONSE.md` | Delegation response template |
| `modes/precision.md` | Precision mode definition |
| `modes/exploration.md` | Exploration mode definition |
| `modes/convergence.md` | Convergence mode definition |
| `modes/custom.md` | Custom mode definition |

## Tag System

- Tag noun: `loop`
- Lifecycle: `#needs-loop` → `#delegated-loop` → `#claimed-loop` → `#done-loop`
- Immediate path: `#needs-loop` → `#next-loop` → `#claimed-loop` → `#done-loop`
