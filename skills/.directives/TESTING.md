# Testing Standards — Skills

Guidelines for verifying skill correctness. Skills are Markdown protocols, not code — testing means structural validation and behavioral verification.

## 1. Structural Validation

*   **Rule**: Every skill MUST pass the following structural checks before shipping.
*   **Checks**:
    - YAML frontmatter has all required fields (`name`, `description`, `version`, `tier`)
    - Boot sector (`§CMD_EXECUTE_SKILL_PHASES`) present at top of protocol-tier skills
    - JSON manifest block is valid JSON and passes schema validation (`skill-manifest.json`)
    - Phase labels in JSON manifest match actual `## N.` section headers in SKILL.md
    - All `§CMD_*` step references resolve to CMD files or COMMANDS.md definitions
    - `nextSkills` array references valid skill directories

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
*   **Phase enforcement**: Verify `engine session phase` transitions follow the declared array.
*   **Synthesis completeness**: Verify the debrief contains all template sections, the Tags line is set, and `engine session deactivate` succeeds.
*   **Context overflow**: Verify `§CMD_DEHYDRATE` produces valid JSON that enables `/session continue` to resume at the correct phase.

## 6. Protocol Completeness (protocol-tier only)

*   **Rule**: Protocol-tier skills must follow universal structural patterns.
*   **Checks**:
    - `§CMD_REPORT_INTENT` present in each major phase section
    - `§CMD_EXECUTE_PHASE_STEPS` present in each major phase section
    - Synthesis phases include `§CMD_RUN_SYNTHESIS_PIPELINE` and `§CMD_CLOSE_SESSION`
    - Debrief phase includes `§CMD_GENERATE_DEBRIEF`

## 7. Automated Validation

Run `engine skill-doctor` before shipping. See `CONTRIBUTING.md` for the check category reference and workflow.

## 8. E2E Behavioral Tests

Protocol behavioral tests verify that Claude **actually follows** protocol commands — not just that the commands are defined. They live in `tests/protocol/` and are **not** included in `run-all.sh` (they invoke real Claude and cost money).

### Where to Put Tests

```
scripts/tests/              # Unit tests (fast, free, deterministic) — run-all.sh globs here
scripts/tests/protocol/     # Behavioral tests (slow, paid, non-deterministic) — manual run only
```

`run-all.sh` globs `test-*.sh` in the flat `tests/` directory only — subdirectories are intentionally excluded.

### Two Test Types

| Type | Cost | What it proves | Example |
|------|------|---------------|---------|
| **Static (grep)** | Free | Cross-cutting changes are complete (renames, format conversions) | Old command name absent from all engine files |
| **Behavioral (Claude)** | ~$0.30/run | Claude actually produces the expected output given a protocol context | Intent report has blockquote format with phase reference |

### Two-Pass Behavioral Design

Single-pass `--json-schema` tests are insufficient — Claude self-reports compliance without ever producing real output. Two passes solve this:

*   **Pass A** (no `--json-schema`): Claude produces natural text. Grep the `result` field for behavioral markers (blockquotes, phase references, numbered steps). This **proves** behavior.
*   **Pass B** (with `--json-schema`): Claude reports diagnostics — did it find the directive, what does it quote, how did it reason. This **explains** behavior.

Pass A is the real test. Pass B is the debugger — when Pass A fails, Pass B tells you why.

### Sandbox Setup

Behavioral tests use `setup_claude_e2e_env` (sourced from `test-helpers.sh`) to create an isolated sandbox:

1.  Creates a temp directory with `FAKE_HOME` and `PROJECT_DIR`
2.  Symlinks real engine components (hooks, directives, scripts) into the sandbox
3.  Writes a minimal `settings.json` with `Bash(engine *)` permissions
4.  Creates a `.state.json` with the desired skill/phase context
5.  Mocks fleet and search tools to prevent side effects

### Invoking Claude

Use the `invoke_claude` helper:

```bash
# Pass A — real text output
RESULT=$(invoke_claude "$PROMPT" "" "none" "2" "--disable-slash-commands")
RESULT_TEXT=$(echo "$RESULT" | jq -r '.result // ""')

# Pass B — diagnostic with JSON schema
RESULT=$(invoke_claude "$PROMPT" "$SCHEMA_JSON" "none" "2" "--disable-slash-commands")
PARSED=$(extract_result "$RESULT")
```

Key flags: `--model haiku` (cheapest), `--max-budget-usd 0.15` (cap per pass), `--tools ""` for `none` (no tool use), `--dangerously-skip-permissions`, `--no-session-persistence`.

### Running

```bash
# All protocol tests
for f in ~/.claude/engine/scripts/tests/protocol/test-*.sh; do bash "$f"; done

# Individual test
bash ~/.claude/engine/scripts/tests/protocol/test-report-intent-behavioral.sh
```

### Multi-Scenario Testing

Behavioral tests should include multiple scenarios to verify context adaptation. For example, testing `§CMD_REPORT_INTENT` with Phase 3/Planning AND Phase 1/Analysis verifies the agent adapts to context rather than hardcoding a single response.

### Origin

Pattern established in session `2026_02_14_IMPROVE_PROTOCOL_TEST` (skill: improve-protocol, Phase 4: Test Loop).
