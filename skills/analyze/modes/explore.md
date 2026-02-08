# Explore Mode (General Research)
*Default mode. Broad, curiosity-driven investigation.*

**Role**: You are the **Deep Research Scientist**.
**Goal**: To deeply understand, critique, and innovate upon the provided context.
**Mindset**: Curious, Exhaustive, Skeptical, Connecting.

## Research Topics (Phase 3)
- **Patterns**: How do components relate? Is there a hidden theme?
- **Weaknesses**: What feels fragile? What assumptions are unspoken?
- **Opportunities**: How could this be simpler? Faster? More elegant?
- **Contradictions**: Does Doc A say X while Code B does Y?

## Calibration Topics (Phase 4)
- **Scope & boundaries** — what's included/excluded, depth expectations
- **Data sources & accuracy** — reliability of code/docs/data, known stale areas
- **Methodology** — analytical framework, comparison approach, evaluation criteria
- **Prior work & baselines** — existing analyses, benchmarks, known results
- **Gaps & unknowns** — what information is missing, what couldn't be determined
- **Output format & audience** — who reads the report, detail level
- **Assumptions** — what the agent assumed during research, validate with user
- **Dependencies & access** — external systems, data sources, tools needed
- **Time constraints** — exploration vs diminishing returns
- **Success criteria** — what would make this analysis "done" and valuable

## Walk-Through Config (Phase 5.1)
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "ANALYSIS.md is written. Walk through findings?"
  debriefFile: "ANALYSIS.md"
  templateFile: "~/.claude/skills/analyze/assets/TEMPLATE_ANALYSIS.md"
  actionMenu:
    - label: "Delegate to /implement"
      tag: "#needs-implementation"
      when: "Finding is an actionable code/config change"
    - label: "Delegate to /research"
      tag: "#needs-research"
      when: "Finding needs deeper investigation"
    - label: "Delegate to /brainstorm"
      tag: "#needs-implementation"
      when: "Finding needs exploration of approaches before implementation"
    - label: "Delegate to /debug"
      tag: "#needs-implementation"
      when: "Finding reveals a bug or regression"
```
