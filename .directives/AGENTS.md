# Workflow Engine

The workflow engine is a structured skill-and-session system layered on top of Claude Code. It provides session lifecycle management, directive-based context injection, tag-driven delegation, and multi-agent coordination.

## Key Subsystems

*   **Sessions**
    *   **Entry Point**: `engine session`
    *   **What It Does**: Activate/deactivate sessions, phase tracking, heartbeat, context overflow recovery

*   **Logging**
    *   **Entry Point**: `engine log`
    *   **What It Does**: Append-only session logs with auto-timestamps

*   **Tags**
    *   **Entry Point**: `engine tag`
    *   **What It Does**: Tag lifecycle management — add, remove, swap, find across session artifacts

*   **Discovery**
    *   **Entry Point**: `engine discover-directives`
    *   **What It Does**: Walk-up search for `.directives/` files from touched directories to project root

*   **Search**
    *   **Entry Point**: `engine session-search`, `engine doc-search`
    *   **What It Does**: Semantic search over past sessions and documentation (RAG)

*   **Hooks**
    *   **Entry Point**: PreToolUse/PostToolUse
    *   **What It Does**: Heartbeat enforcement, directive gate, context overflow protection, details logging

*   **Skills**
    *   **Entry Point**: `~/.claude/skills/*/SKILL.md`
    *   **What It Does**: Structured protocols (implement, analyze, fix, test, brainstorm, etc.)

## The Directive System

Agent-facing context files in `.directives/` subfolders at any level of the project hierarchy. This is the primary mechanism for feeding context to agents.

**8 directive types** (2 tiers):
- **Core** (always discovered): `AGENTS.md`, `INVARIANTS.md`, `ARCHITECTURE.md`
- **Skill-filtered** (loaded when skill declares them): `TESTING.md`, `PITFALLS.md`, `CONTRIBUTING.md`, `TEMPLATE.md`, `CHECKLIST.md`

`CHECKLIST.md` is skill-filtered but has a **hard gate** at deactivation: when discovered, `§CMD_PROCESS_CHECKLISTS` must pass before `engine session idle`/`deactivate` succeeds. Skills that declare it: `/implement`, `/fix`, `/test`.

**Checklist submission format**: `engine session check` expects JSON on stdin: `{"<absolute-path-to-CHECKLIST.md>": "<full original markdown with only [ ] → [x] changes>"}`. Three common mistakes: (1) passing raw markdown instead of JSON, (2) using `~/.claude/` instead of the absolute path, (3) abbreviating/truncating checklist content. The engine compares against the original file — content must be exact.

**Inheritance**: Directives stack cumulatively child-to-root. Package directives extend project directives extend engine directives — never shadow.

**Discovery**: `engine discover-directives` walks up from touched directories. PostToolUse hook tracks touched dirs and warns about pending directives. PreToolUse hook blocks after threshold if unread.

**End-of-session management**: `§CMD_MANAGE_DIRECTIVES` runs 3 passes — AGENTS.md updates (auto-mention new directives), invariant capture, pitfall capture.

**Templates**: Scaffolding for new directive files lives in `~/.claude/engine/.directives/templates/TEMPLATE_*.md` (one per type).

## Do Not Use Claude Code's Built-in Memory Feature

Use `.directives/` files instead of Claude Code's built-in memory feature (`/memory`, `MEMORY.md`). The directive system is structured, discoverable by the engine, and version-controlled. The memory feature stores unstructured notes in `~/.claude/projects/*/memory/MEMORY.md` — this file should remain empty.

## Core Standards (The "Big Three")

Loaded at every session boot — these define the engine's fundamental operations:
- `COMMANDS.md` — All `¶CMD_` command definitions (file ops, process control, workflows)
- `INVARIANTS.md` — Shared `¶INV_` rules (testing, architecture, code, communication, engine physics)
- `SIGILS.md` — Tag lifecycle (`¶FEED_`), escaping, operations, dispatch routing

## Agent Behavior Rules

Rules that govern how agents communicate, interact, and operate. These are behavioral — the agent must follow them but they aren't mechanically enforced.

### Communication

*   See `§INV_SIGIL_SEMANTICS` (shared INVARIANTS.md) — `¶` = definition, `§` = reference. All sigiled nouns (CMD, INV, FEED, TAG) follow this convention.

*   **¶INV_CONCISE_CHAT**: Chat output is for **User Communication Only**.
    *   **Rule**: Do NOT narrate your internal decision process or micro-steps in the chat.
    *   **Prohibited**: "Wait, I need to check...", "Okay, reading file...", "Executing...", "I will now..." (followed immediately by action).
    *   **Reason**: It consumes tokens, confuses the user, and creates "infinite loop" risks where the agent talks about doing something instead of doing it.
    *   **Mechanism**: If you need to think, write to the `_LOG.md` file. If you need to act, just call the tool.

*   **¶INV_TERMINAL_FILE_LINKS**: File path references in chat output MUST use full clickable URLs.
    *   **Rule**: When referencing a file path in chat, output the full `protocol://file/ABSOLUTE_PATH` URL. Resolve `~` to the actual home directory. Every file path the user sees MUST be clickable.
    *   **Format**: `cursor://file/ABSOLUTE_PATH` (or `vscode://file/ABSOLUTE_PATH`)
        *   Example: `cursor://file/Users/name/project/src/lib/audio.ts`
        *   With line number: `cursor://file/Users/name/project/src/lib/audio.ts:42`
    *   **URL Encoding**: Spaces and special characters in paths MUST be percent-encoded.
        *   Space → `%20`
        *   Example: `cursor://file/Users/name/Shared%20drives/project/file.ts`
    *   **Protocol Source**: Read from "Terminal link protocol: X" in system prompt. Default: `cursor://file`.
    *   **Prohibited**: Backtick-wrapped paths (`` `~/.claude/file.md` ``), tilde paths (`~/.claude/...`), plain relative paths (`sessions/dir/FILE.md`), or any file reference that is not a clickable URL.
    *   **Bad**: `File: ~/.claude/engine/scripts/lib.sh — 1 change`
    *   **Good**: `File: cursor://file/Users/name/.claude/engine/scripts/lib.sh — 1 change`
    *   **Note**: OSC 8 escape sequences and markdown link syntax do not render custom display text in Claude Code's terminal — full URLs are the only reliable clickable format.
    *   **Reason**: Clickable links improve navigation. Full URLs are verbose but functional. Unencoded spaces break URL parsing.

*   **¶INV_SKILL_VIA_TOOL**: Slash commands (skills) MUST be invoked via the Skill tool, NEVER via Bash.
    *   **Rule**: When instructed to run `/session`, `/commit`, `/review`, or any `/skill-name`, you MUST use the Skill tool with `skill: "skill-name"`. Do NOT use Bash to call scripts.
    *   **Prohibited**: `engine session dehydrate`, `bash -c "/session dehydrate"`, or any shell-based skill invocation.
    *   **Correct**: `Skill(skill: "session", args: "dehydrate restart")` or `Skill(skill: "commit")`
    *   **Reason**: Skills are registered in the Claude Code skill system and invoked via the Skill tool. They are NOT bash scripts. The `/` prefix is syntactic sugar for "use the Skill tool".

*   **¶INV_QUESTION_GATE_OVER_TEXT_GATE**: User-facing gates and option menus in ALL agent interactions MUST use `AskUserQuestion` (tool-based blocking), never bare text.
    *   **Rule**: When the agent needs user confirmation before proceeding, it must use `AskUserQuestion` with structured options. Text-based "STOP" instructions are unreliable — they depend on agent compliance. Tool-based gates are mechanically enforced.
    *   **Rule**: When presenting choices, options, or menus to the user, the agent MUST use the `AskUserQuestion` tool. It MUST NOT render the options as a Markdown table, bullet list, or plain text in chat and then wait for the user to type a response. **This applies everywhere** — inside active skill protocols, between sessions, before skill activation, during ad-hoc chat, and after session close. Any time you present 2+ choices to the user, use `AskUserQuestion`.
    *   **Rule**: Before calling `AskUserQuestion`, the agent MUST output enough context in chat for the user to understand what the options mean and why they are being asked. A bare question with options but no surrounding explanation is a violation — the user cannot make an informed choice without context. The **last line** of chat text before the `AskUserQuestion` call MUST be an empty line (`\n`), because the question UI element overlaps the bottom of the preceding text. Without the trailing blank line, the user cannot read the agent's final sentence.
    *   **Rule**: `AskUserQuestion` option labels and descriptions MUST be descriptive and actionable. Labels explain *what* happens; descriptions explain *why* it matters. When an option triggers tagging, include the `#needs-X` tag in the label. No vague labels — every word must carry information.
        *   **Bad**: label=`"Delegate to /implement"`, description=`"Code change needed"`
        *   **Good**: label=`"#needs-implementation: add auth validation"`, description=`"Prevents unauthenticated access to the payment endpoint"`
    *   **Rule**: When the user responds to `AskUserQuestion` with an empty string or whitespace-only text (via "Other"), treat it as **"Use your best judgement."** The agent MUST:
        1. **Justify**: Output a blockquote in chat explaining which option(s) it is choosing and why (up to 3 lines).
            *   Format: `> Auto-proceeding with "[Option label]" — [reason, up to 3 lines].`
        2. **Choose**: For **single-select**, pick the first option (or the most contextually appropriate if none is marked Recommended). For **multi-select**, pick whichever option(s) the agent deems best given the current context.
        3. **Log**: Execute `§CMD_LOG_INTERACTION` with `**Type**: Auto-Decision` recording the question, the agent's choice, and the justification.
        4. **Proceed**: Continue execution as if the user had selected that option.
        *   **Scope**: Applies to ALL `AskUserQuestion` calls — phase gates, interrogation questions, depth selection, decisions, walk-throughs. No exceptions.
        *   **Constraint**: This rule ONLY triggers on empty/whitespace-only "Other" responses. Any non-empty text from "Other" is treated as user input per normal behavior.
    *   **Rule**: Interaction chains MUST stay structured end-to-end. When an `AskUserQuestion` selection leads to a follow-up question or routing decision, that follow-up MUST also use `AskUserQuestion`. Never degrade from a structured tool-based interaction to bare text mid-chain. If a user's selection requires further input, present the next question via `AskUserQuestion` — do not output "Which X do you want?" as plain text.
        *   **Bad**: `AskUserQuestion` → user picks "Start a new skill" → agent outputs "Which skill?" as plain text
        *   **Good**: `AskUserQuestion` → user picks "Start a new skill" → agent presents skill options via another `AskUserQuestion`
        *   **Redirection** (`¶INV_REDIRECTION_OVER_PROHIBITION`): If you find yourself about to type a question in chat, stop — use `AskUserQuestion` instead.
    *   **Reason**: `AskUserQuestion` provides structured input, mechanical blocking, and clear selection semantics. Text-rendered menus are ambiguous (the user might type something unexpected), non-blocking (the agent might continue without waiting), and invisible to tool-use auditing. Context-free questions and vague option labels are equally harmful — they force the user to guess what the agent is referring to.

*   **¶INV_REDIRECTION_OVER_PROHIBITION**: When preventing an undesired LLM behavior, provide an alternative action rather than just prohibiting the behavior.
    *   **Rule**: Redirections ("do X instead") are more reliable than prohibitions ("don't do Y"). When designing constraints for LLM agents, always pair a prohibition with a concrete alternative action the agent should take instead.
    *   **Reason**: Prohibitions require the model to suppress an impulse, which competes with training signals (helpfulness, efficiency). Redirections channel the impulse into a compliant action, which is fundamentally easier to follow.

*   **¶INV_BATCH_QUESTIONS**: `AskUserQuestion` calls should batch up to 4 questions (the tool maximum).
    *   **Rule**: When asking the user questions via `AskUserQuestion`, group related questions into a single call with up to 4 questions. Do not ask 1-2 questions when you could batch 3-4 related ones together.
    *   **Exempt**: Yes/no confirmations, simple gates, and single-purpose prompts (e.g., phase transition approval) do not need padding.
    *   **Soft suggestion**: When batching, consider adding a probing or devil's-advocate question to deepen the conversation. If you have 2 essential questions, look for a useful "while we're here" question to include.
    *   **Redirection**: When about to call `AskUserQuestion` with 1-2 questions, pause and look for related context questions to include in the same call.
    *   **Reason**: Saves user attention time by batching related questions. Each `AskUserQuestion` call is a round-trip — fewer calls with more questions is more efficient.

*   **¶INV_NO_TABLES_IN_CHAT**: Agents MUST NOT use markdown tables in chat output.
    *   **Rule**: When presenting structured data in chat, use `§FMT_LIGHT_LIST`, `§FMT_MEDIUM_LIST`, or `§FMT_HEAVY_LIST` formatting instead of markdown tables.
    *   **Redirection**: If you're about to type `| col |`, stop — use a bullet list with bold keys instead. See `§INV_LISTS_INSTEAD_OF_TABLES` in shared INVARIANTS.md.
    *   **Reason**: Tables in terminal output often render poorly at narrow widths and are harder to scan than structured lists.

### Skill Design

*   **¶INV_MODE_STANDARDIZATION**: All modal skills have exactly **3 named modes + Custom**. Custom is always the last mode.
    *   **Rule**: Skills with multiple modes present them via `AskUserQuestion` in Phase 1 Setup. Mode definitions live in `skills/X/modes/*.md` (per-skill, not shared). SKILL.md contains a summary table of available modes; full definitions are in separate files. Custom mode reads all 3 named mode files to understand the flavor space, then synthesizes a hybrid mode from user input.
    *   **Reason**: Consistent UX across skills. Users learn one pattern. Mode files keep SKILL.md lean and make modes independently versionable. The 3+Custom constraint prevents mode bloat.

*   **¶INV_SKILL_FEATURE_PROPAGATION**: When adding a new feature to a skill, propagate it to ALL applicable skills or tag for follow-up.
    *   **Rule**: When a new engine feature (phase enforcement array, walk-through config, deactivate wiring, mode presets, interrogation depth) is added to one skill, the same feature MUST be added to all other applicable skills in the same session — or each missing skill MUST be explicitly tagged `#needs-implementation` for follow-up.
    *   **Reason**: Feature additions without propagation create structural debt. Each improvement session that touches 1-3 skills leaves the remaining skills further behind, creating an ever-widening gap between "gold standard" and "stale" skills.

*   **¶INV_NO_BUILTIN_COLLISION**: Engine skill names must not collide with Claude Code built-in CLI commands.
    *   **Rule**: Before naming a new skill, check against the known built-in list: `/help`, `/clear`, `/compact`, `/config`, `/debug`, `/init`, `/login`, `/logout`, `/review`, `/status`, `/doctor`, `/hooks`, `/listen`, `/vim`, `/terminal-setup`, `/memory`. Built-in commands intercept at the CLI layer before the LLM sees the input — a colliding skill will be silently shadowed.
    *   **Detection**: Built-in commands produce `<command-name>` tags in the output. If invoking a skill produces a `<command-name>` tag instead of the engine protocol, the name collides.
    *   **Reason**: The `/debug` skill was silently broken for its entire lifetime because Claude Code's built-in `/debug` intercepted it. Renamed to `/fix` to resolve.

### System Awareness

*   **¶INV_GLOB_THROUGH_SYMLINKS**: The Glob tool does not traverse symlinks. Use `engine glob` as a fallback for symlinked directories.
    *   **Rule**: When Glob returns empty for a path that should have files (especially `sessions/` or any symlinked directory), fall back to `engine glob '<pattern>' <path>`. For known symlinked paths (`sessions/`), prefer `engine glob` directly.
    *   **Reason**: `sessions/` is symlinked to Google Drive. The Glob tool's internal engine silently skips symlinks, producing false "no results" responses.

*   **¶INV_TMUX_AND_FLEET_OPTIONAL**: Fleet/tmux is an optional enhancement, not a requirement.
    *   **Rule**: All hooks and scripts that interact with tmux/fleet MUST fail gracefully when running outside tmux. The core workflow engine (sessions, logging, tags, statusline) MUST work identically with or without fleet.
    *   **Pattern**: Guard tmux calls with `[ -n "${TMUX:-}" ]` check, and always use `|| true` when calling `engine fleet` from hooks.
    *   **Reason**: Users may run Claude in a plain terminal, VSCode, or other environments. Fleet is a multi-pane coordination layer — its absence should never break the workflow.

*   **¶INV_DAEMON_STATELESS**: The dispatch daemon MUST NOT maintain state beyond what tags encode.
    *   **Rule**: The daemon reads tags, routes to skills, and spawns agents. It does not track which agents are running, which work is complete, or any other state. Tags ARE the state. `#claimed-X` IS the claim state.
    *   **Reason**: Simplicity and crash recovery. If the daemon restarts, it re-reads tags and resumes correctly. No state file to corrupt, no process table to reconcile.
