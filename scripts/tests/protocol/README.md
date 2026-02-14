# Protocol Behavioral Tests

Tests that verify agent behavioral compliance with protocol commands. These invoke real Claude (haiku model, $0.15 budget cap per pass) and are **not** included in `run-all.sh` (which runs unit tests only).

## Why Separate?

Protocol tests are fundamentally different from unit tests:
- **Unit tests** (`tests/test-*.sh`): Test scripts/hooks in isolation. Fast, free, deterministic.
- **Protocol tests** (`tests/protocol/`): Test whether Claude **actually follows** protocol commands. Slow (~30s per pass), costs money, non-deterministic.

The key insight: a unit test can verify that `§CMD_REPORT_INTENT` is defined in COMMANDS.md, but only a behavioral test can verify that Claude actually produces a blockquote when instructed to.

## Tests

| Test | Type | What it verifies |
|------|------|-----------------|
| `test-report-intent-rename.sh` | Static (grep) | Old name absent, new name defined, referenced in 16+ SKILL.md files |
| `test-report-intent-behavioral.sh` | Behavioral (Claude) | Two-pass: (A) real text output has blockquote/phase/steps, (B) diagnostic captures directive discovery + reasoning |

## Running

```bash
# Run all protocol tests
for f in ~/.claude/engine/scripts/tests/protocol/test-*.sh; do bash "$f"; done

# Run individual test
bash ~/.claude/engine/scripts/tests/protocol/test-report-intent-rename.sh
bash ~/.claude/engine/scripts/tests/protocol/test-report-intent-behavioral.sh
```

## Two-Pass Behavioral Test Design

**Problem**: Using `--json-schema` forces Claude to respond with JSON only. Claude self-reports "I produced a blockquote" but never actually produces text output. We verify claims, not behavior.

**Solution**: Two passes per behavioral test:
- **Pass A** (no `--json-schema`): Claude produces natural text output. We grep the `result` field for blockquote markers, phase references, numbered steps. This proves behavior.
- **Pass B** (with `--json-schema`): Claude reports diagnostics — did it find the directive, what does it quote, how did it reason. This explains behavior.

Pass A is the real test. Pass B is the debugger — when Pass A fails, Pass B tells you why.

## Origin

Created during session `2026_02_14_IMPROVE_PROTOCOL_TEST` (skill: improve-protocol, Phase 4: Test Loop).

Prior session `2026_02_13_PROTOCOL_IMPROVEMENT_RUN` applied the rename: `§CMD_REPORT_INTENT_TO_USER` → `§CMD_REPORT_INTENT` across 23 files, 77 occurrences.
