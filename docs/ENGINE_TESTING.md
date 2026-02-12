# Engine Testing Methodology

Testing the workflow engine's session infrastructure (session.sh, run.sh, hooks, statusline) using deterministic bash test scripts with a Claude binary stub approach.

## Test Location

All tests live in `~/.claude/engine/scripts/tests/`. This is the canonical location — tests are engine infrastructure, not throwaway scratchpad scripts.

## Test Suites

| File | Target | Assertions | What It Tests |
|------|--------|------------|---------------|
| `test-session-sh.sh` | session.sh (all subcommands) | 34 | init, activate (fresh/re-activation/PID conflicts/completedSkills/migration), update, phase, target, deactivate, restart, find |
| `test-completed-skills.sh` | engine session activate/deactivate | 14 | completedSkills gating, .state.json rename, migration |
| `test-phase-enforcement.sh` | engine session phase | 36 | Phase enforcement, sequential/skip/backward transitions, sub-phases, skill-switch reset |
| `test-log-sh.sh` | log.sh | 13 | Timestamp injection, double-stamp guard, overwrite mode, heading validation |
| `test-run-lifecycle.sh` | run.sh | 22 | Full lifecycle with Claude binary stub — normal exit, restart loop, env vars |
| `test-run-sh.sh` | run.sh (functions) | 8 | find_fleet_session, scoped fleetPaneId, restart sessionId skip, statusline defense, migration |
| `test-threshold.sh` | config.sh, overflow hook, statusline | 17 | Threshold sourcing, allow/deny logic, display normalization, whitelist/bypass |
| `test-tmux.sh` | fleet.sh, session.sh (fleet mode) | 34 | Pane identity, notify states+colors, window aggregation, fleet session discovery, PID conflicts, pane claiming, socket isolation, config paths |
| `test-heartbeat.sh` | pre-tool-use-heartbeat.sh | 23 | Loading mode bypass, tool call counting, log warning thresholds, Edit suppression |
| `test-session-gate.sh` | pre-tool-use-session-gate.sh | 22 | Gate enable/disable, whitelisted tools, session requirement enforcement |
| `test-prompt-gate.sh` | user-prompt-submit-session-gate.sh | 16 | Prompt gate enable/disable, session validation |
| `test-tag-sh.sh` | tag.sh (all subcommands) | 31 | add (create/append/idempotent), remove (Tags-line/inline/error), swap (single/multi/inline/error), find (Tags-line/inline/backtick-filter/dedup/context-mode), edge cases |
| `test-config-sh.sh` | config.sh (all subcommands) | 18 | get (defaults/from-file/create), set (create/overwrite/preserve), list (defaults/config/both/override), error handling |
| `test-user-info-sh.sh` | user-info.sh (all modes) | 16 | Cache mode (all fields + unknown field error), symlink detection (GDrive email parsing), fallback (no symlink/non-GDrive), cache priority |
| `test-glob-sh.sh` | glob.sh (all patterns) | 19 | ** all files, **/*.ext recursive, prefix/**/*.ext, *.ext shallow, dir/*.ext, symlink traversal, path output format, edge cases |
| `test-find-sessions-sh.sh` | find-sessions.sh (all subcommands) | 22 | today/yesterday/recent/date/range/topic/tag/active/all, output modes (dirs/files/debriefs), path override, edge cases |
| `test-lib.sh` | lib.sh (shared utilities) | 20 | timestamp, pid_exists, hook_allow, hook_deny, safe_json_write (validation, atomic write, locking, stale lock cleanup), notify_fleet (TMUX detection, socket parsing, fleet.sh invocation), state_read (field extraction, defaults, missing files) |
| `test-overflow.sh` | pre-tool-use-overflow.sh | 19 | Whitelist bypasses (log.sh, session.sh, Skill dehydrate, lifecycle=dehydrating, killRequested), threshold math (below/above 0.76), sticky overflowed flag, deny for non-whitelisted tools, no-session/missing-state fallback |
| `test-statusline.sh` | statusline.sh | 15 | State updates (contextUsage 4dp, lastHeartbeat ISO, sessionId binding + R1 race protection for kill/overflow/dehydrating), display output (no-session, skill/phase, normalized %, cost, agent name) |
| `test-setup-lib.sh` | setup-lib.sh (pure functions) | 64 | All 11 extracted functions with filesystem isolation, SETUP_* env var overrides |
| `test-setup-integration.sh` | engine.sh (full integration) | 25 | End-to-end setup with filesystem isolation |
| `test-setup-migrations.sh` | setup-migrations.sh (migration runner) | 23 | Each migration (fresh, idempotent, partial), runner sequencing, version tracking |
| `test-discover-instructions.sh` | discover-instructions.sh | 10 | Walk-up logic, boundary detection (PWD), type filtering (soft/hard/all), exclusion rules (node_modules/.git/sessions/tmp/dist/build), deduplication |
| `test-post-tool-use-discovery.sh` | post-tool-use-discovery.sh | 17 | Tool filtering (Read/Edit/Write only), engine path skip, no-session graceful exit, touchedDirs tracking, soft discovery (hookSpecificOutput/dedup), hard discovery (CHECKLIST.md), idempotency |
| `test-session-discovery.sh` | session.sh (discovery integration) | 12 | Activate seeds touchedDirs/discoveredChecklists from directoriesOfInterest, deactivate checklist gate (¶INV_CHECKLIST_BEFORE_CLOSE), idempotent re-activation |
| `test-session-check.sh` | engine session check subcommand | 8 | check validation (empty stdin, missing blocks, empty blocks, happy path, no checklists, paths with spaces), deactivate checklist gate (checkPassed blocking/allowing) |
| `test-session-check-tags.sh` | engine session check (tag scanning) | 20 | `¶INV_ESCAPE_BY_DEFAULT` enforcement, bare tag detection (needs/active/done), Tags-line exclusion, backtick-escape filtering, tagCheckPassed skip, checklist integration, multiple tags per file, empty session, hardening: plan steps, headings, narrative, multi-family, line-start/end, whitespace, mixed escaped+bare |
| `test-tag-find.sh` | tag.sh find (discovery rules) | 17 | Escape-by-default discovery (all .md types), binary DB exclusion, .state.json exclusion, Tags-line Pass 1, inline Pass 2, backtick filtering, dedup, hardening: plan steps, log headings, only-escaped exclusion, TESTING.md debrief, --context flag |

**Total: 28 suites, ~565+ assertions**

### Running Tests

```bash
# Run all suites
bash ~/.claude/engine/scripts/tests/run-all.sh

# Run a single suite
bash ~/.claude/engine/scripts/tests/run-all.sh test-session-sh.sh

# Run a suite directly
bash ~/.claude/engine/scripts/tests/test-session-sh.sh
```

## Architecture

### The "Real" Boundary

Tests use **real** session.sh, real hooks, and real filesystem operations. Only the Claude binary is stubbed. This maximizes integration coverage — the tests exercise actual jq operations on `.state.json`, actual file creation, and actual phase enforcement logic.

### The Claude Binary Stub

`test-run-lifecycle.sh` creates a stub `claude` binary and places it first in PATH. The stub:

1. Logs each invocation to `invocations.log` (for assertion)
2. Reads a script file from `$STUB_SCRIPT_FILE` with commands like:
   - `session:activate DIR SKILL` — calls engine session activate
   - `session:phase DIR PHASE` — calls engine session phase
   - `session:deactivate DIR` — calls engine session deactivate
   - `exit:CODE` — exits with code
3. This enables testing run.sh's restart loop, env var export, and watchdog behavior without a real Claude process

### HOME Override (test-session-sh.sh)

`test-session-sh.sh` uses a `HOME` override strategy for full isolation:

1. Creates `$TEST_DIR/fake-home/.claude/scripts/` with symlinks to real scripts
2. Writes stub `fleet.sh` and search tool scripts into the fake home
3. Controls `CLAUDE_SUPERVISOR_PID` via env var
4. Uses `$$` for alive PIDs, `99999999` for dead PIDs

This enables testing fleet pane detection, search tool invocation, and PID conflict logic without any real tmux or search infrastructure.

### Test Isolation

Each test creates its own temp directory via `mktemp -d`. Fleet/tmux detection is disabled by unsetting `TMUX` and `TMUX_PANE`. `FLEET_SETUP_DONE=1` skips engine.sh. `CLAUDE_SUPERVISOR_PID` is set to `$$` for deterministic PID matching. `DEBUG` must be unset for statusline tests (it triggers a debug output mode that bypasses normal display).

## Writing New Tests

### Pattern: assert helpers

Suites use two styles of helpers (both work):

**Style 1 — assert functions** (test-phase-enforcement.sh, test-threshold.sh):

```bash
assert_ok "description" command args...     # Expect exit 0
assert_fail "description" command args...   # Expect exit non-zero
assert_eq "description" "expected" "$actual" # String equality
assert_json "description" "$file" '.field' "expected"  # jq field check
assert_contains "description" "needle" "$haystack"     # Substring check
assert_gt "description" "$a" "$b"           # Numeric greater-than
```

**Style 2 — pass/fail functions** (test-session-sh.sh, test-run-sh.sh):

```bash
pass "test name"                            # Increment PASS counter
fail "test name" "expected" "got"           # Increment FAIL counter + print diff
skip "test name" "reason"                   # Print skip message
```

### Pattern: reset_state / create_state

Phase enforcement tests use `reset_state` to create a fresh `.state.json` with a known phase and phases array. Session tests use `create_state "$dir" "$json"` to write arbitrary fixtures. Both avoid test coupling.

### Pattern: PASS/FAIL counters

Use `PASS=$((PASS + 1))` instead of `((PASS++))` — the latter returns exit code 1 when the variable is 0 under `set -e`, silently killing the script.

### Adding a Test Case

1. Add the assertion(s) in the appropriate test file
2. Use `reset_state` / `create_state` or `mkdir -p` to set up fresh state
3. Call session.sh with the scenario
4. Assert the outcome with `assert_ok`/`assert_json`/`pass`/`fail`/etc.
5. Run the suite to verify

### Adding a New Suite

1. Create `~/.claude/engine/scripts/tests/test-FEATURE.sh` with `set -uo pipefail` (not `set -e` — counter increment issue)
2. Copy the assert helpers from an existing suite
3. Use `mktemp -d` for isolation
4. Clean up with `rm -rf "$TMP_DIR"` at the end (or trap)
5. Exit 0 on all pass, exit 1 on any failure
6. Update this doc's Test Suites table
