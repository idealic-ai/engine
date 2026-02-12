# Testing Standards — Skills

Guidelines for verifying skill correctness. Skills are Markdown protocols, not code — testing means structural validation and behavioral verification.

## 1. Structural Validation

*   **Rule**: Every skill MUST pass the following structural checks before shipping.
*   **Checks**:
    - YAML frontmatter has all required fields (`name`, `description`, `version`, `tier`)
    - Boot Sequence block is present and correctly formatted
    - Gate Check block has all three proof blanks (COMMANDS.md, INVARIANTS.md, TAGS.md)
    - Phase array (protocol-tier) matches the actual `## N.` headings in the SKILL.md
    - Every phase has `§CMD_REPORT_INTENT_TO_USER` and `§CMD_VERIFY_PHASE_EXIT` blocks
    - Next Skill Options section defines exactly 4 options

## 2. Template Consistency

*   **Rule**: Templates in `assets/` must be consistent with the skill protocol.
*   **Checks**:
    - Log template schemas cover all log types referenced in the Operation phase
    - Debrief template has `**Tags**: #needs-review` on line 2
    - Plan template (if present) has `**Depends**:` and `**Files**:` fields per operation
    - Section names referenced in walk-through configurations match template headings
    - Request/Response templates exist if and only if the skill is delegation-capable

## 3. Mode File Completeness

*   **Rule**: Every named mode file must be self-contained and have all 4 sections.
*   **Checks**:
    - Each mode file has: Role, Goal, Mindset, Approach
    - No mode file references another mode file (must be self-contained)
    - Custom mode exists and reads all 3 named modes
    - Mode summary table in SKILL.md matches the actual mode files

## 4. Cross-Reference Integrity

*   **Rule**: All `§CMD_*` and `¶INV_*` references in the skill must resolve.
*   **Checks**:
    - Every `§CMD_*` reference exists in `~/.claude/.directives/COMMANDS.md` or `.directives/commands/*.md`
    - Every `¶INV_*` reference exists in `~/.claude/.directives/INVARIANTS.md` or `.claude/.directives/INVARIANTS.md`
    - Every `§FEED_*` reference exists in `~/.claude/.directives/TAGS.md`

## 5. Behavioral Verification (Manual)

Since skills are executed by Claude, not by code, behavioral testing is done by running a session and checking outcomes.

*   **Smoke test**: Run the skill with a minimal input. Verify it produces all expected artifacts (log, plan, debrief).
*   **Phase enforcement**: Verify `session.sh phase` transitions follow the declared array.
*   **Synthesis completeness**: Verify the debrief contains all template sections, the Tags line is set, and `session.sh deactivate` succeeds.
*   **Context overflow**: Verify `/session dehydrate restart` produces a valid `DEHYDRATED_CONTEXT.md` that enables `/session continue` to resume at the correct phase.

## 6. Automated Validation

Run the skill doctor to check all skills at once:

```bash
engine skill-doctor
```

The doctor validates all rule categories (DR-A through DR-I) across every skill in the engine. It is tier-aware: protocol-tier skills get strict checks (modes, phases, Next Skill Options), while utility/lightweight skills get basic structural checks only.

*   **PASS**: Check passed
*   **WARN**: Non-critical issue (e.g., REQUEST template without RESPONSE)
*   **FAIL**: Structural defect that must be fixed
*   **Exit code**: 0 if no FAILs, 1 if any FAIL detected
