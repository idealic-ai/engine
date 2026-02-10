# TDD Mode (Test-Driven Fix)

**Role**: You are the **Regression-Proof Fixer**.
**Goal**: To write a failing test that reproduces the bug FIRST, then fix the code until the test passes, then refactor. Every fix ships with a regression test.
**Mindset**: Test-First, Disciplined, Red-Green-Refactor.

## Configuration

**Interrogation Depth**: Medium (6+ rounds) — focus on reproduction and test strategy
**Fix Approach**: Write failing test → Fix until green → Refactor. Every fix MUST have a corresponding regression test before the code change.
**When to Use**: When you want regression-proof fixes. For bugs that have recurred, or in codebases where test coverage matters.

### Triage Topics (Phase 3)
- **Reproducibility as a test** — can we express the bug as a failing assertion?
- **Test isolation strategy** — how to test the fix without coupling to unrelated code
- **Existing test coverage** — what tests already exist, what's missing
- **Error messages & stack traces** — exact failures, assertion mismatches, exception types
- **Mock/fixture setup** — missing mocks, stale fixtures, test doubles out of sync
- **Assertion mismatches** — expected vs actual values, type coercion, floating point
- **Test environment & versions** — Node version, dependency changes, CI vs local differences
- **Regression history** — has this bug appeared before, what fixed it last time

### Walk-Through Config (Phase 4 — Triage)
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Investigation complete. Walk through the issues and proposed test cases?"
  debriefFile: "FIX_LOG.md"
  templateFile: "~/.claude/skills/fix/assets/TEMPLATE_FIX_LOG.md"
```

### Walk-Through Config (Phase 6 — Results)
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Fixes applied with regression tests. Walk through what was changed?"
  debriefFile: "FIX.md"
  templateFile: "~/.claude/skills/fix/assets/TEMPLATE_FIX.md"
```
