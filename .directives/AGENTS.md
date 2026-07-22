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

*   **¶INV_TERMINAL_FILE_LINKS**: Every file-path reference the user sees MUST be a **labeled clickable link** per `§FMT_FILE_LINK` — never a bare URL, never a dead relative path.
    *   **Rule**: Render file references as `[<label>](<url>)` — labeled markdown links now render clickable in-terminal, so the old bare-URL requirement is retired. Smart-by-type (`§FMT_FILE_LINK`): editable files (code, `.md`, session artifacts, configs) → `cursor://file/<ABS>` (opens the editor); view-only kinds (images, `.pdf`, `.html`) → `file:///<ABS>` (opens the default viewer). Resolve `~`/relative to an absolute path; percent-encode spaces (`%20`). Line number → append `:42` to the path.
    *   **Format**: `[EDIT_SKILL.md](cursor://file/Users/name/proj/sessions/X/EDIT_SKILL.md)` · image: `[overlay-3.png](file:///Users/name/proj/out/overlay-3.png)`. Label = basename or a short description.
    *   **Prohibited**: a bare `cursor://…`/`file://…` blob in prose (wrap it in a label), backtick-wrapped paths, tilde/relative paths, `file://` for an editable file (opens Finder, not the editor), or any non-clickable reference.
    *   **Reason**: a labeled basename beats a 90-char raw URL — it declutters every artifact report — and labeled links now render clickable, which is why the bare-URL mandate (a workaround for the old non-rendering) is gone.

*   **¶INV_SKILL_VIA_TOOL**: Slash commands (skills) MUST be invoked via the Skill tool, NEVER via Bash.
    *   **Rule**: When instructed to run `/session`, `/commit`, `/review`, or any `/skill-name`, you MUST use the Skill tool with `skill: "skill-name"`. Do NOT use Bash to call scripts.
    *   **Prohibited**: `engine session dehydrate`, `bash -c "/session dehydrate"`, or any shell-based skill invocation.
    *   **Correct**: `Skill(skill: "session", args: "dehydrate restart")` or `Skill(skill: "commit")`
    *   **Reason**: Skills are registered in the Claude Code skill system and invoked via the Skill tool. They are NOT bash scripts. The `/` prefix is syntactic sugar for "use the Skill tool".

*   **¶INV_QUESTION_GATE_OVER_TEXT_GATE**: User-facing gates and option menus in ALL agent interactions MUST use `AskUserQuestion` (tool-based blocking), never bare text.
    *   **Rule**: When the agent needs user confirmation before proceeding, it must use `AskUserQuestion` with structured options. Text-based "STOP" instructions are unreliable — they depend on agent compliance. Tool-based gates are mechanically enforced.
    *   **Rule**: When presenting choices, options, or menus to the user, the agent MUST use the `AskUserQuestion` tool. It MUST NOT render the options as a Markdown table, bullet list, or plain text in chat and then wait for the user to type a response. **This applies everywhere** — inside active skill protocols, between sessions, before skill activation, during ad-hoc chat, and after session close. Any time you present 2+ choices to the user, use `AskUserQuestion`.
    *   **Rule**: Every `AskUserQuestion` MUST carry its **complete context inside the question body** (`§CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT`) — what's being decided and why, so the user chooses in place. Do NOT split context into a separate chat block rendered before a terse question (the old duality, retired now that bodies have no length limit). Option labels lead with `§FMT_ANSWER_GRADATION` tags where they differentiate the set. A one-line lead-in sentence is fine; keep ONE trailing blank line before the call so the last line stays visible above the UI overlay.
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

### Building-Block Skills

*   **¶INV_OFFER_DONT_FORCE_SKILLS**: The sub-agent-driven building-block skills (`/probe`, `/build`, `/experiment`, `/scrutinize`, `/summarize`, `/snapshot`, `/ticket`, `/pr`, and peers) are **optional aids, not gates**. When you are about to do one of these actions **ad-hoc** — answer a question from the code/data/tickets, delegate a scoped build, try something hands-on, adversarially review a body of work, catch up on / review a chunk, checkpoint or commit, file a ticket, open a PR — first `AskUserQuestion` whether to use the dedicated skill or proceed as usual ("wing it"), then honor the choice. Offer the option at the decision point; never force the skill, and if the user says wing it, proceed the usual way. A quick inline commit, a one-off ticket, or a trivial reproduction doesn't need the ceremony — surface the option and let the user decide when the work is substantial enough to warrant it.
    *   **Single source of truth**: each skill's own `SKILL.md` `description` (surfaced in the harness skill list every session) is the catalog — do NOT duplicate per-skill descriptions here; they rot.
    *   **Cross-ref**: `§INV_PREFER_BUILD_SCRUTINIZE` (INVARIANTS.md) is the specific case — when the offered path is an autonomous agent handoff, prefer the `/build` + `/scrutinize` combo if both are available.
    *   **Reason**: these skills package heavy actions with built-in review + safety rails, but forcing them adds friction to trivial work. Offering at the decision point keeps the user in control while surfacing the richer path.

*   **¶INV_OFFER_REPORT_ON_DISORIENTATION**: When the user asks a *general* "where are we?" question — where do things stand, what's the state of this session, what's left, where did we leave off (on STATE) — OFFER `/report` (the read-only orientation skill) rather than improvising a freehand recap. Likewise, when **you** are about to answer a state question you can't actually ground — a cold start or post-overflow resume where you'd be *guessing* at the current state — offer to run `/report` to reground first.
    *   **Offer, don't force, don't auto-run**: surface it as the option (`AskUserQuestion` or a one-line offer) and honor "just answer" — same physics as `§INV_OFFER_DONT_FORCE_SKILLS`. `/report` is never triggered silently.
    *   **Don't over-fire**: for *general* orientation only. A narrow, specific question ("what does this function do?", "did the test pass?", "what's this path?") is answered directly. And the self-trigger is "about to improvise a state answer you can't ground," NOT the bare fact of a cold start / resume — a resume where you already have what you need needs no offer.
    *   **Route vs siblings**: *"where are we / catch me up on STATE"* → `/report` (present orientation). *"catch me up on WHAT WE DID / was it good"* → `/summarize` (retrospective review). Just the mechanical phase/lifecycle, no re-orientation needed → the lean `/session status`, not `/report`.
    *   **Reason**: returning to a session cold is exactly when a freehand recap is least reliable — `/report` grounds the answer in the raw transcript + git + ticket and reconciles it against the agent's live bearings, which is what "back in the flow" actually requires.

*   **¶INV_LOG_SKILL_INVOCATION_BEFORE_DISPATCH**: A sub-agent-dispatching skill MUST record its dispatch to the session log *before* handing control to the subagent — via `§CMD_LOG_SKILL_INVOCATION`, fired as the step immediately before the `Task`/`Agent` call. The entry is agent-authored and curated: WHY the subagent was invoked + a pointer to the context pack + how to re-dispatch — never a raw prompt dump.
    *   **Why before, not after**: the point is crash recovery. A dispatch logged only *after* the subagent returns is worthless if Claude dies mid-run — the reactivated session can't tell what was running or with what inputs. Logging right before the handoff makes every subagentic dispatch re-treadable.
    *   **Curated, not captured** (`§INV_INVOCATION_LOG_IS_CURATED`): the log holds reasoning + a pack pointer; the pack itself lives on disk. Deliberately NOT a hook that auto-dumps the prompt — an agent-authored *why* is higher-signal and doesn't bloat the log.
    *   **Cited, not restated**: skills reference `§CMD_LOG_SKILL_INVOCATION` at their dispatch site; they don't re-explain the format (single source of truth). Applies to the sub-agent dispatchers (`/build`, `/council`, `/probe`, `/scrutinize`, `/experiment`, `/summarize`, `/snapshot`, `/ticket`, `/pr`, `/report`); inline skills don't dispatch, so it doesn't apply.

*   **¶INV_VISUALIZE_STRUCTURE_WITH_GRAPH**: When a body of work has non-trivial structure — a branching algorithm, a dependency graph, a state/lifecycle, a decision tree, a multi-path flow — reach for `/graph` to render it as an ASCII flowgraph. Offer it, contextually, not as a mandate. A plan's step dependencies, an analyzed control flow, a design's decision tree, a chapter graph, a bug's failure-paths all read far faster as a diagram than as prose, and seeing the structure surfaces missing branches, cycles, and dead ends that prose hides.
    *   **Context-gate it**: only when the flow actually branches / loops / depends. A linear `1 → 2 → 3` sequence is clearer as a numbered list — a flowgraph of it is noise (`/graph`'s own "when NOT to use"). Assess first; stay silent when there's nothing to draw.
    *   **Wired vs ad-hoc**: skills that produce such artifacts declare `§CMD_OFFER_GRAPH_VIZ` at their plan-review / synthesis phase; ad-hoc, just offer `/graph` when you notice structure worth drawing. Never force it.
    *   **One canonical notation — never freehand**: the `§CMD_FLOWGRAPH` glyph vocabulary (defined in `/graph`) is the **single** ASCII-diagram language in the engine — covering both control-flow (decisions, branches, loops) and trajectory/timeline graphs. Whenever you actually draw an ASCII chart/diagram/flow, render it in that vocabulary — the closed **status set** for trajectory graphs (`✓` done · `○` upcoming · `✗` dropped · `⚠` stale · `◄ HERE` · `▣ <sha>` checkpoint) plus the flow/decision/branch glyphs (`◆ ├► ╰► ⟨…⟩`) — and do NOT freehand ad-hoc marks that duplicate them (`●`, `♦`, `★`, `←—`, `〈〉`, `[ ]` checkboxes, hand-drawn boxes). Invoke `/graph` for anything non-trivial; for a quick inline diagram, still use its glyphs. Enforced by *this one rule*, **cited** (not re-explained) at each diagram site — a skill writes `(§INV_VISUALIZE_STRUCTURE_WITH_GRAPH)`, it never restates the glyph list. Single source of truth; no per-skill pollution (the `§INV_OFFER_DONT_FORCE_SKILLS` "do NOT duplicate" pattern).
    *   **Reason**: structure is easier to verify and critique when you can SEE it — but a diagram of a flat list wastes attention, and every agent hand-rolling its own glyphs makes diagrams unreadable and unparseable. Gate on real structure; when you do draw, draw in the one notation.

*   **¶INV_DISCLOSE_AND_TRIAGE**: When you hand the user a set of findings / ideas / options / decisions, don't dump a flat list where every item reads as equally deserving scrutiny and each omits what the user then has to ask for. **Have a POV** (a defeasible lean, not neutral findings); **front-load** what they reliably ask next — what's at stake / severity, the trade-off of acting, the complexity it adds, how to verify it cheaply; **triage attention on severity × complexity** ("clear to decide" ≠ "clean to apply") into an advisory `I've-got-this` (clear-cut) / `Your-call` (worth your attention) / `FYI` (noted); **escalate by exception** — brief with skimmable Decision Cards, then let the decision command decide. **Disclosure is not decision**: classify attention, then hand off to the caller's own decision (tag / fix-skip-defer / address-ignore) — never auto-act on an `I've-got-this`. The wired path is `§CMD_ELICIT` (the disclosure layer, mirror of `§CMD_INTERROGATE`) via `§CMD_WALK_THROUGH_RESULTS` results mode; **ad-hoc (outside a walkthrough), still disclose this way**.
    *   **Anti-anchor**: on a genuine judgment call, options-first-neutral, THEN a defeasible "my lean … — but the strongest case against is …" — so the user's judgment stays engaged rather than rubber-stamping your recommendation.
    *   **No hidden decisions**: the handled/FYI buckets stay visible as one-line what+why lists (never bare counts), and self-confidence is unreliable — low confidence never earns the advisory clear-cut verdict. See `§CMD_ELICIT` for the triple gate and the guards.
    *   **Reason**: two real transcripts showed the identical loop — the agent's answers were excellent *when asked*, so the follow-up interrogation was a disclosure + triage gap, not a capability gap. Disclose and triage up front and the loop disappears.

*   **¶INV_KEEP_PLAN_LIVE**: When build/fix work **deviates from the plan mid-execution** — a new discovery, a scope shift, re-cut chunks, a superseded step — **proactively** (don't wait to be asked) do two things. **(1) Reconcile the plan**: append a dated `## 🔄 STATUS RECONCILIATION (YYYY-MM-DD)` section that supersedes the now-stale checkboxes while **preserving the original plan as history** — surgical `[x]`/`[ ]` edits only for the few most-wrong boxes; never silently rewrite the plan body. **(2) Offer to log the course change to the ticket** via `/snapshot`, which can **skip the commit** for a pure course-change log (a ticket-description touch + a comment through `§CMD_POST_TICKET_COMMENT`, no commit) — its "skip the commit (post update only)" choice is exactly this case.
    *   **Event-triggered, not a phase step**: this fires on *deviation*, not on a schedule. A plan that's tracking reality needs no reconciliation section — only append one when the checkboxes have actually gone stale.
    *   **Reason**: plans go stale across long multi-pivot arcs; a stale plan misleads the next session and loses the decision trail. A dated reconciliation section keeps the original intent visible *and* records where reality diverged.

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

### Ticket Subscriptions

The `engine ticket` subsystem is a cross-session update tracker for Linear tickets. It is a dirty-flag + watermark tracker only — comment content always lives in Linear; agents fetch it via MCP.

*   **Subscribe when you work a ticket**: If your work is tied to a Linear ticket, subscribe the session — `engine ticket subscribe FIN-1234` (or pass `"tickets": ["FIN-1234"]` in the session-activation params, which auto-subscribes on startup). Subscribing is what lets other sessions' updates reach you.
*   **Notify when you post a ticket comment**: Immediately after posting a comment to a ticket (e.g. via the `/snapshot` skill or Linear MCP), run `engine ticket notify FIN-1234 "<decision-grade note>"`. This flags every *other* session subscribed to `FIN-1234` (never yourself). **Write the note decision-grade** — on wake a reader drains only this note, NOT the Linear body (the body can't be carried locally — `notify` can't call MCP, and keeping it local would go stale vs Linear). So write it so they can answer *"do I need to act?"* without a Linear fetch: include the **commit SHA** if one landed, the **one-phrase what-changed**, and an **affects-you verdict** (`no action` / `rebase onto <sha>` / `your files untouched` / `needs your reply`). One line, terse. The Linear comment remains the source of truth for anyone who wants full detail — a good note just means they rarely need it. E.g. `engine ticket notify FIN-2833 "2db0ecea6: entities/ scaffold committed byte-equal; scope.ts aliases left for FIN-2737 — no action for you"`.
*   **¶INV_TICKET_COMMENT_VIA_CMD**: Never post a raw ticket comment. Route every ticket-comment post through `§CMD_POST_TICKET_COMMENT` (the canonical subscribe-check → `save_comment` → `engine ticket notify` atom) so the subscribe-check + sibling-notify always fire together. **Reason**: a bare `save_comment` silently drops the notify, leaving sibling agents unaware a comment landed and the poster unsubscribed from replies — bundling them in one atom makes the miss impossible.
*   **Drain updates when your status line shows 🎟**: A `🎟 FIN-1234` segment on the status line means that ticket has pending updates. Run `engine ticket read` to drain them — **plain `read` already pretty-prints** each ticket, its `since` datetime, and every note (`🎟 <key> since=… (N updates)` + bulleted notes), so you don't need to reformat it. Only add `--json` when you're machine-parsing (then pipe to `jq`, not a hand-rolled python formatter). `read` advances the watermark; use that `since` to fetch the new comments from Linear via MCP (`list_comments`, filtered to `>= since`). Use `engine ticket list` to peek without draining.

*   **Watch your tickets in the background**: `engine ticket watch` blocks until any subscribed ticket gets an update, then exits — run it via the Bash tool's **`run_in_background: true`** parameter (NOT a shell `&`) so the harness re-invokes you when it fires (you keep working meanwhile). A shell `&` detaches the watcher from the harness's task tracker, so it may fire and exit but **never wake you** — always use `run_in_background: true`. **Unbounded by default — no `--timeout`, so it blocks until a *real* update and never fake-wakes you** (a deadline exit would re-invoke you for nothing and burn context; a non-matching fs event just re-checks silently without exiting). On exit **0** a watched ticket changed (stdout is the key(s)) → **`engine ticket read` FIRST to drain the queue (advances the watermark), THEN fetch via MCP, THEN re-arm** — if you re-arm the watch *without* draining, it re-fires exit-0 instantly on the same undrained entry and you spin (that fast exit-0 is "an update is waiting," NOT "the watcher is broken"). Exit **2** = fswatch not installed, **1** = nothing subscribed to watch. Only if you pass `--timeout N` can it exit **124** (bounded deadline; re-arm or stop). `engine ticket watch FIN-1234` narrows to one ticket; no arg watches all your subscriptions. It only detects a *local* agent's `notify` — a human typing directly on Linear is not seen.
    *   **Name the watcher as a wake-instruction, not a label.** The harness wakes you with `Background command "<description>" completed (exit code N)` — that line IS the signal, so set the Bash tool's `description` to an imperative like **`Ticket watcher fired — drain with 'engine ticket read', then fetch new comments via Linear MCP`**. A bare "Re-arm ticket watcher" leaves you staring at an opaque `exit code 0`; a self-instructing description carries the next step in the wake message itself.

*   **Arming is enforced — a hard gate**: whenever your session's `tickets[]` is non-empty, a PreToolUse gate requires a *live* background watcher. `cmd_watch` self-registers `.state.json:watchTaskId = {pid, startedAt, keys}` on start and clears it on graceful exit; liveness is authoritative via `kill -0 <pid>` (a hard-killed watcher leaves a stale field the gate clears on sight). Until you arm one, the gate allows a short grace window, then **blocks ordinary tools** with the exact spawn command. Always allowed so you can never deadlock: the arming call (`engine ticket watch`), `AskUserQuestion`, `Skill`, and engine bookkeeping (`engine ticket`/`session`/`log`). A PostToolUse nudge fires right after `engine session activate`/`phase` reminding you to arm — so spawning the watcher is your natural first move.

### Discussing in a Ticket (multi-agent)

A ticket's Linear comment thread doubles as a shared discussion channel between agents. The loop:

1.  **Ask**: post your question as a Linear comment (MCP) on `FIN-1234`, then `engine ticket subscribe FIN-1234` (if not already), `engine ticket notify FIN-1234 "asked X"`, and spawn `engine ticket watch FIN-1234` in the background.
2.  **Hand-off**: a human tells another agent "check `FIN-1234`'s comment." That agent subscribes, reads the thread via Linear MCP, posts its reply (MCP), and runs `engine ticket notify FIN-1234 "replied"`.
3.  **Wake**: the notify flags your session; your background watcher exits 0 and you're re-invoked. `read` → fetch the new comment via MCP → reply → `notify` → `watch` again.
4.  Both agents subscribed + watching makes it self-sustaining — a back-and-forth in the ticket, each turn: read → reply(MCP) → notify → re-watch. Agents may `subscribe` to more tickets any time to widen what they watch.

The **`/communicate`** skill packages one full turn of this loop (subscribe → post via Linear MCP → `notify` siblings → arm/keep `engine ticket watch`; on wake → `read` → `list_comments` since the watermark → reply → re-arm). Reach for it instead of hand-driving the verbs. **Known gap (local-signal only)**: the wake fires only on another *local* agent's `notify`; a human commenting directly in Linear does not `notify`, so a local watcher won't wake for it — you'd catch it on your next manual `list_comments`. A future Linear-poll (Option B) would close this; it is intentionally not built.
