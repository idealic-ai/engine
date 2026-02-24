---
name: effort
description: "Manage skill efforts — start new efforts, resume after overflow, or log progress. The PreToolUse hook intercepts this skill and routes to daemon RPC commands automatically."
argument-hint: <start|resume|log> [args...]
disable-model-invocation: false
allowed-tools: Bash(engine-rpc *)
---

# Effort Management

When you invoke this skill, the PreToolUse hook automatically executes the corresponding daemon RPC command and returns the result as additional context. You do not need to run any shell commands — the hook handles execution.

## Subcommands

### start

Activate a new skill effort. Creates project, task, effort, and session. If an active effort already exists for the same task+skill, resumes it instead.

```
/effort start <taskName> <skill> [--mode <mode>]
```

- `taskName`: Task name (e.g. `AUTH_SYSTEM`). Directory `.tasks/auth_system/` is derived automatically.
- `skill`: Skill name (e.g. `implement`, `test`, `fix`, `brainstorm`)
- `--mode`: Optional mode (e.g. `tdd`, `coverage`)

After activation, the hook returns confirmation with the log path, phase info, RAG results, and discovered directives.

### Implicit creation via phase proof

Efforts can also be created implicitly at the phase 0→1 boundary. When `engine session phase` is called with `{taskName, description, keywords}` in the proof JSON and no active effort exists, the PreToolUse hook automatically creates the effort. This enables lazy effort creation — skills run phase 0 without an effort, and the effort is created when the model provides naming proof.

### resume

Resume an effort after context overflow. Creates a new session linked to the previous one.

```
/effort resume [<dirPath>]
```

If `dirPath` is omitted, auto-detects from the active effort.

### log

Append a progress entry to the active effort's log file. Auto-derives filename, injects timestamp, resets heartbeat.

```
/effort log ## My Heading\n*   **Status**: ...\n*   **Next**: ...
```

The content should start with a `## Heading` — the timestamp is injected automatically.

## Response

The hook returns the command result as `additionalContext`. On success you'll see the formatted markdown output. On failure you'll see the error reason.
