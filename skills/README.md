# Skill Catalog

Feature matrix of all workflow engine skills. Use this as a reference when adding new features (per `¶INV_SKILL_FEATURE_PROPAGATION`).

## Tier Classification

| Tier | Count | Description | Features |
|------|-------|-------------|----------|
| **protocol** | 9 | Full ceremony — interrogation, planning, build loop, synthesis | Phases, Deactivate, Walk-Through, Mode Presets |
| **utility** | 2 | Session-running, lighter protocol — focused execution | Deactivate, some Walk-Through |
| **lightweight** | 9 | No session dir or minimal lifecycle — single-purpose tools | None required |

---

## Protocol Skills (9)

Full-ceremony skills with all engine features.

| Skill | Phases | Deactivate | Walk-Through | Mode Presets |
|-------|--------|------------|--------------|--------------|
| `/analyze` | 5 (Setup → Context → Research → Calibration → Synthesis) | Yes | Results | Explore, Audit, Improve, Custom |
| `/brainstorm` | 4 (Setup → Context → Dialogue → Synthesis) | Yes | Results | Explore, Focused, Adversarial, Custom |
| `/fix` | 7 (Setup → Context → Investigation → Triage Walk-Through → Fix Loop → Results Walk-Through → Debrief) | Yes | Results + Plan | General, TDD, Hotfix, Custom |
| `/document` | 4 (Setup → Diagnosis & Planning → Operation → Synthesis) | Yes | Results + Plan | Surgical, Refine, Audit, Custom |
| `/implement` | 6 (Setup → Context → Interrogation → Planning → Build Loop → Synthesis) | Yes | Results + Plan | TDD, Experimentation, General, Custom |
| `/loop` | 7 (Setup → Interrogation → Planning → Validation → Baseline → Iteration → Synthesis) | Yes | Results | Accuracy, Speed, Robustness |
| `/review` | 4 (Setup → Discovery → Dashboard & Interrogation → Synthesis) | Yes | — | Quality, Velocity, Compliance |
| `/test` | 6 (Setup → Context → Interrogation → Planning → Execution → Synthesis) | Yes | Results | Coverage, Hardening, Integration, Custom |

---

## Utility Skills (5)

Session-running skills with lighter protocols.

| Skill | Deactivate | Walk-Through | Notes |
|-------|------------|--------------|-------|
| `/chores` | Yes | Results | Task queue execution, no formal phases |
| `/refine-docs` | Yes | — | Doc refinement, no formal phases |

---

## Lightweight Skills (13)

Single-purpose tools with no session directory or minimal lifecycle.

| Skill | Purpose |
|-------|---------|
| `/edit-skill` | Create or edit skills in `.claude/` |
| `/session` | Session management — dehydrate, recover, search, status |
| `/research` | Full Gemini Deep Research cycle |
| `/research-request` | Post async research request |
| `/research-respond` | Check/retrieve research results |
| `/summarize-progress` | Generate cross-session progress report |
| `/writeup` | Create situational documents |

---

## Feature Propagation Checklist

When adding a new engine feature, check this list to ensure it's propagated to all applicable skills:

- [ ] **Phases array**: All 9 protocol skills
- [ ] **Deactivate wiring**: All protocol + utility skills (14 total)
- [ ] **Walk-Through configs**: All skills with actionable synthesis outputs
- [ ] **Mode presets**: All protocol skills with variable execution styles
- [ ] **Tier tag**: All skills (in YAML frontmatter)
- [ ] **Phase naming**: Final phase = "Synthesis" for all protocol skills
- [ ] **Log template**: All session-running skills
- [ ] **Debrief template**: All session-running skills

---

## Skill Upgrade Checklist (New Skill)

When creating a new skill, verify it has:

1. **YAML frontmatter** with `name`, `description`, `version`, `tier`
2. **Boot sequence** (standards loading + gate check)
3. **If protocol tier**: Phases array, mode presets, walk-through config, deactivate + Next Skill Options
4. **If utility tier**: Deactivate + Next Skill Options
5. **If session-running**: Log template, debrief template, `§CMD_GENERATE_DEBRIEF`
6. **Post-synthesis**: `§CMD_RESUME_AFTER_CLOSE` handler
