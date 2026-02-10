# Writeup: COMMANDS.md — Comparative Analysis Against LLM Behavioral Frameworks

*Created: 2026-02-07*

## Context

This writeup distills the comparative analysis from the `/analyze` session on COMMANDS.md. It positions the standards system against three established approaches to LLM behavioral engineering: Cursor .cursorrules, custom system prompts, and JSON schema-driven approaches.

The analysis was conducted for the system's author, seeking blind spots and external perspective on a system they built incrementally from concrete pain points (agent drift, multi-agent chaos, session management, context overflow).

## Related

- `sessions/2026_02_07_COMMANDS_MD_ANALYSIS/ANALYSIS.md` -- Source research (full analysis with 5 themes)
- `~/.claude/docs/DIRECTIVES_SYSTEM.md` -- Core reference doc for the directives system
- `~/.claude/.directives/COMMANDS.md` -- The subject itself

---

## The Category Gap

COMMANDS.md does not compete with existing approaches. It operates in a category the others do not address.

| Approach | Category | What It Defines |
|----------|----------|-----------------|
| Cursor .cursorrules | Instruction list | Flat rules for immediate behavior |
| Custom system prompts | Instruction list | Flat text, sometimes sectioned |
| JSON schema approaches | Output contract | Structural validation of responses |
| **COMMANDS.md** | **Behavioral operating system** | Lifecycle management, process control, I/O primitives, multi-agent coordination, composable behavioral APIs |

The closest philosophical relative is not any of these tools but Anthropic's own Model Spec -- a layered set of behavioral instructions with named principles, explicit conflict resolution, and compositional structure. The difference: the Model Spec operates at the identity level (who the model is), while COMMANDS.md operates at the operational level (what the agent does during a session). They are complementary layers.

---

## Five-Dimension Comparison

### Dimension 1: Structural Sophistication

| Dimension | Cursor .cursorrules | Custom System Prompts | JSON Schema | COMMANDS.md |
|-----------|--------------------|-----------------------|-------------|-------------|
| **Organization** | Flat file, no sections | Flat text, sometimes sectioned | Structured data, no behavior | 4-layer hierarchy with named commands |
| **Naming** | None (prose rules) | None (prose rules) | Schema field names only | `§CMD_` / `¶INV_` namespaced identifiers |
| **Composability** | None -- each rule independent | None -- rules don't reference each other | Schemas compose (allOf, oneOf) | Commands compose (A calls B calls C) |
| **Scope control** | Global (all files, all time) | Global (all messages) | Per-request (schema per API call) | Phase-specific, with explicit expiration |
| **Size** | Typically 20-100 lines | Typically 50-500 lines | N/A (per-request) | ~700 lines + companion docs |

The `§CMD_` naming system is a significant advancement by itself. It creates addressable, referenceable behavioral units instead of anonymous prose rules. No other approach provides named, composable behavioral specifications.

### Dimension 2: Session and State Management

| Dimension | Cursor .cursorrules | Custom System Prompts | JSON Schema | COMMANDS.md |
|-----------|--------------------|-----------------------|-------------|-------------|
| **Session awareness** | None -- stateless | None -- stateless | None -- stateless | Full lifecycle (birth to restart recovery) |
| **State persistence** | None | None | None | `.state.json`, session directories, log files |
| **Context overflow** | Unhandled (fresh start) | Unhandled | N/A | `§CMD_REANCHOR_AFTER_RESTART` with phase recovery |
| **Multi-session** | N/A | N/A | N/A | Tags for cross-session communication |
| **Post-completion** | N/A | N/A | N/A | `§CMD_CONTINUE_OR_CLOSE_SESSION` with debrief regeneration |

This is the widest gap. None of the three comparands have any concept of session state, lifecycle, or recovery. The context overflow recovery -- dehydration, restart, reanchor with phase skip -- has no parallel in any publicly documented LLM behavioral framework.

### Dimension 3: Compliance Mechanisms

| Dimension | Cursor .cursorrules | Custom System Prompts | JSON Schema | COMMANDS.md |
|-----------|--------------------|-----------------------|-------------|-------------|
| **Enforcement** | Honor system | Honor system | Runtime validation (schema) | Redirect-over-prohibit + protocol-is-task |
| **Deviation handling** | Ignored | Ignored | Error response | `§CMD_REFUSE_OFF_COURSE` (surface and ask) |
| **Compliance rate** | Variable (no data) | Variable (no data) | ~100% (machine-enforced) | ~90% (author-reported) |
| **Failure mode** | Silent drift | Silent drift | Hard error | Logged deviation with user choice |

JSON schema achieves higher enforcement (~100%, machine-enforced) but only for output structure. It cannot enforce behavioral patterns like "reason in the log, not the chat" or "ask the user before skipping a step." COMMANDS.md trades structural enforcement for behavioral breadth. The `§CMD_REFUSE_OFF_COURSE` pattern -- converting the skip impulse into an ask impulse -- has no equivalent in any other framework.

### Dimension 4: Multi-Agent Coordination

| Dimension | Cursor .cursorrules | Custom System Prompts | JSON Schema | COMMANDS.md |
|-----------|--------------------|-----------------------|-------------|-------------|
| **Agent awareness** | None | None | None | PID tracking, `.state.json`, `¶INV_NO_GIT_STATE_COMMANDS` |
| **Coordination** | N/A | N/A | N/A | Tags (`#needs-X` / `#claimed-X`), `¶INV_CLAIM_BEFORE_WORK` |
| **Conflict prevention** | N/A | N/A | N/A | Session activation rejects if different PID is active |
| **Work routing** | N/A | N/A | N/A | `§TAG_DISPATCH` with priority ordering |

Another gap with no parallel. The tag-based coordination system (`#needs-X` to `#claimed-X` to `#done-X`) is a work queue implementation built on filesystem tags. The `§TAG_DISPATCH` table maps tags to resolving skills with priority ordering -- decisions first (they unblock), research second (async, queue early), implementation third, documentation fourth, review last.

### Dimension 5: Token Economy

| Dimension | Cursor .cursorrules | Custom System Prompts | JSON Schema | COMMANDS.md |
|-----------|--------------------|-----------------------|-------------|-------------|
| **Context cost** | Low (small file) | Medium (system prompt) | Low (per-request) | High (~700 lines upfront) |
| **Runtime cost** | No optimization | No optimization | N/A | Blind writes, dehydration, "memory over IO" |
| **Cost trajectory** | Flat | Flat | Flat | Amortized (upfront cost, runtime savings) |

This is COMMANDS.md's most honest weakness. The ~700 lines of behavioral specification consume significant context window real estate on every session. The system compensates with runtime optimizations (blind writes saving thousands of tokens per session, dehydration/reanchor for infinite sessions, `§CMD_AVOID_WASTING_TOKENS` reducing redundant reads). Cursor .cursorrules at 20-100 lines are 7-35x cheaper in context tokens. The question is whether the behavioral improvements justify the cost -- and at 90%+ compliance with materially better agent behavior, the empirical answer is yes.

---

## The Compiler IR Hypothesis

An analytical framing positions COMMANDS.md as an Intermediate Representation (IR) in a compilation stack:

```
Skill Protocols (SKILL.md)     <-- Source code
        |
        v
COMMANDS.md (§CMD_*)           <-- IR / Instruction Set Architecture
        |
        v
LLM Runtime (Claude, etc.)    <-- Processor
```

If COMMANDS.md is truly an ISA (instruction set architecture), it should be relatively model-agnostic. The same commands should work on different LLM "processors" with predictable behavior differences -- like running the same code on Intel vs AMD.

**Prediction**: Layer 1 (file operations) and Layer 3 (interaction) would likely port cleanly to other models. Layer 2 (process control, especially `§CMD_REFUSE_OFF_COURSE`) would show the most model-dependent behavior, because impulse redirection depends on the model's internal compliance architecture.

**Current status**: Untested. The system is Claude-only. The hypothesis is analytical, not empirical. A cross-model portability test (running COMMANDS.md on GPT-4 or Gemini 2.5 Pro and measuring compliance per layer) would validate or refute this framing.

---

## What COMMANDS.md Uniquely Provides

Capabilities that exist in COMMANDS.md but in none of the comparands:

1. **Named, composable behavioral specifications** -- The `§CMD_` system creates a DSL for LLM programming. No other approach has addressable behavioral units.

2. **Session lifecycle with overflow recovery** -- Birth, activation, execution, debrief, continuation, and restart after context exhaustion. No other approach manages session state at all.

3. **Redirect-over-prohibit compliance** -- Converting the skip impulse into an ask impulse. Other approaches either prohibit (and fail silently) or ignore deviations entirely.

4. **Multi-agent coordination via tags** -- A work queue and IPC system built on filesystem tags. Other approaches assume a single agent.

5. **Blind-write token economy** -- Append-only logging that never re-reads accumulated output. Other approaches have no token management strategy.

6. **An emergent type system** -- JSON parameter schemas (input types), template fidelity (output types), and tag lifecycles (state types) converge into behavioral type safety. No other approach constrains agent behavior across input, output, and state simultaneously.

---

## Growth Risks

Three medium-term risks identified in the analysis:

1. **Context window pressure** -- At 32+ commands and ~700 lines, COMMANDS.md is approaching a practical ceiling. Each new command adds marginal context cost. Options: selective loading by layer, command discovery mechanism, or conscious feature freeze.

2. **Implicit command call graph** -- Commands compose, but the composition graph is in prose. There is no dependency diagram or formal composition rules. A command manifest (table listing each command's callers and callees) would make the graph explicit.

3. **Single-model coupling** -- The system assumes Claude's tool-calling interface, context window management, and compliance architecture. Portability to other LLMs is unverified.
