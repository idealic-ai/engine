# Shared System Invariants (The "Laws of Physics")

This document defines the universal rules that apply across ALL projects using the workflow engine. Project-specific invariants belong in each project's `.claude/directives/INVARIANTS.md`.

## 1. Testing Physics

*   **¶INV_HEADLESS_LOGIC**: Business logic MUST be testable without the framework.
    *   **Rule**: Core domain logic (calculations, state transitions) should be pure functions or classes that don't import framework specifics.
    *   **Reason**: Tests run in milliseconds, not seconds.

*   **¶INV_ISOLATED_STATE**: Tests MUST NOT share mutable state.
    *   **Rule**: Each test case starts with a fresh mock/database transaction/workflow ID.
    *   **Reason**: Flaky tests destroy developer confidence.

## 2. Architecture & Task Decomposition

*   **¶INV_SPEC_FIRST**: Complex logic MUST be specified before implementation.
    *   **Requirement**: Major system components require a written Spec derived from the standard template.
    *   **Rule**: Do not write the code until the Spec (Context, Sequence Diagram, Failure Analysis) is written and reviewed.
    *   **Reason**: It is 10x cheaper to fix a design flaw in Markdown than in code.

*   **¶INV_ATOMIC_TASKS**: Units of work should do ONE thing well.
    *   **Bad**: `processAndEmailAndBill()`
    *   **Good**: `calculateBill()`, `chargeCard()`, `sendReceiptEmail()`
    *   **Reason**: Granular tasks allow for targeted retries and better observability.

## 3. General Code Physics

*   **¶INV_CAMELCASE_EVERYWHERE**: All identifiers use camelCase. No exceptions.
    *   **Rule**: Schema field names, TypeScript properties, variable names, and documentation references to field names MUST use camelCase (`commentPattern`, `isGroupHeader`, `totalSumVerification`).
    *   **Prohibited**: snake_case (`comment_pattern`, `is_group_header`), kebab-case in property names, or any other casing convention for identifiers.
    *   **Reason**: Consistency. One convention across the entire codebase — code, schemas, docs, tests. No mental translation between cases.

*   **¶INV_NO_DEAD_CODE**: Delete it, don't comment it out.
    *   **Rule**: Git is your history. The codebase is the current state.
    *   **Reason**: Commented code rots and confuses readers.

*   **¶INV_NO_LEGACY_CODE**: No Legacy Code.
    *   **Rule**: Migrate immediately, clean up, update tests. Don't leave legacy codepaths.
    *   **Reason**: Legacy code increases technical debt and complexity.

*   **¶INV_TYPESCRIPT_STRICT**: No `any`.
    *   **Rule**: Use `unknown` if you must, then narrow it.
    *   **Reason**: `any` disables the type checker, which is our primary safety net.

*   **¶INV_ENV_CONFIG**: Configuration comes from Environment Variables.
    *   **Rule**: No hardcoded secrets or API keys in code.
    *   **Reason**: Security and portability across environments (Dev/Stage/Prod).

## 4. Communication Physics

*   **¶INV_SKILL_VIA_TOOL**: Slash commands (skills) MUST be invoked via the Skill tool, NEVER via Bash.
    *   **Rule**: When instructed to run `/dehydrate`, `/commit`, `/review`, or any `/skill-name`, you MUST use the Skill tool with `skill: "skill-name"`. Do NOT use Bash to call scripts.
    *   **Prohibited**: `engine session dehydrate`, `bash -c "/dehydrate"`, or any shell-based skill invocation.
    *   **Correct**: `Skill(skill: "dehydrate", args: "restart")` or `Skill(skill: "commit")`
    *   **Reason**: Skills are registered in the Claude Code skill system and invoked via the Skill tool. They are NOT bash scripts. The `/` prefix is syntactic sugar for "use the Skill tool".

*   **¶INV_SKILL_PROTOCOL_MANDATORY**: The protocol is the task. Every step executes. No exceptions.
    *   **Rule**: When a skill is invoked, the protocol (`SKILL.md`) defines YOUR TASK. The user's request is the input parameter to that task — it does not replace, shorten, or override the protocol. You execute every phase and every step. If a step produces no useful output, that's fine — you still executed it.
    *   **If you want to skip**: You don't skip. You fire `§CMD_REFUSE_OFF_COURSE` and let the user decide. The user is the only one who can authorize a deviation. You never self-authorize.
    *   **Prohibited justifications** (these are never valid reasons to skip a step):
        *   "This task is too simple for the full protocol."
        *   "The user asked for X, not for Y" (where Y is a protocol step).
        *   "I'll be more efficient by skipping this."
        *   "This step doesn't apply to this task."
    *   **Identity**: A disciplined operator follows the protocol. Skipping steps is not efficiency — it's broken output. The protocol exists because the steps matter, even when you think they don't. Your judgment about task complexity is unreliable. The protocol's judgment is authoritative.
    *   **Consequence**: A session where protocol steps were silently skipped is an invalid session. The artifacts are incomplete, the audit trail is broken, and the work may need to be redone.
    *   **Reason**: LLMs systematically underestimate task complexity and overestimate when steps are "unnecessary." Protocols compensate for this bias. See `¶INV_REDIRECTION_OVER_PROHIBITION`.

*   **¶INV_TERMINAL_FILE_LINKS**: File path references in chat output should use full clickable URLs.
    *   **Rule**: When referencing a file path, output the full URL so it's clickable in the terminal.
    *   **Format**: `cursor://file/ABSOLUTE_PATH` (or `vscode://file/ABSOLUTE_PATH`)
        *   Example: `cursor://file/Users/name/project/src/lib/audio.ts`
        *   With line number: `cursor://file/Users/name/project/src/lib/audio.ts:42`
    *   **URL Encoding**: Spaces and special characters in paths MUST be percent-encoded.
        *   Space → `%20`
        *   Example: `cursor://file/Users/name/Shared%20drives/project/file.ts`
    *   **Protocol Source**: Read from "Terminal link protocol: X" in system prompt. Default: `cursor://file`.
    *   **Note**: OSC 8 escape sequences and markdown link syntax do not render custom display text in Claude Code's terminal — full URLs are the only reliable clickable format.
    *   **Reason**: Clickable links improve navigation. Full URLs are verbose but functional. Unencoded spaces break URL parsing.

*   **¶INV_CONCISE_CHAT**: Chat output is for **User Communication Only**.
    *   **Rule**: Do NOT narrate your internal decision process or micro-steps in the chat.
    *   **Prohibited**: "Wait, I need to check...", "Okay, reading file...", "Executing...", "I will now..." (followed immediately by action).
    *   **Reason**: It consumes tokens, confuses the user, and creates "infinite loop" risks where the agent talks about doing something instead of doing it.
    *   **Mechanism**: If you need to think, write to the `_LOG.md` file. If you need to act, just call the tool.

## 5. Development Philosophy

*   **¶INV_DATA_LAYER_FIRST**: Fix problems at the data layer, not the view.
    *   **Rule**: If a problem can be solved by correcting the schema or upstream data, do that instead of adding view-layer patches or transformer workarounds.
    *   **Rule**: Single source of truth — generate/derive from canonical data, don't duplicate.
    *   **Reason**: View-layer patches accumulate as tech debt and hide the real problem.

*   **¶INV_EXPLICIT_OVER_IMPLICIT**: Prefer explicit configuration over implicit inference.
    *   **Rule**: Caching invalidation, feature flags, and state transitions should use explicit signals (override maps, checksums), not automatic hash-based derivation.
    *   **Rule**: When code and documentation diverge, update documentation to match working code — code is reality.
    *   **Reason**: Implicit behavior is hard to debug and leads to "magic" that breaks unexpectedly.

*   **¶INV_DX_OVER_PERF**: Optimize for developer velocity when performance is acceptable.
    *   **Rule**: If a solution is marginally slower but significantly easier to debug/iterate on, choose it.
    *   **Rule**: Local-first tools (CLI, scripts) over server dependencies where possible.
    *   **Reason**: Developer time is the bottleneck, not CPU time.

*   **¶INV_COMPREHENSIVE_FOUNDATION**: Build foundational systems comprehensively.
    *   **Rule**: For infrastructure/framework code, implement the full feature set rather than a minimal slice.
    *   **Rule**: Test fixtures should cover all patterns — "all of the above" is often correct.
    *   **Reason**: Foundational shortcuts create tech debt that compounds over time.

*   **¶INV_EXTEND_EXISTING_PATTERNS**: Extend existing patterns before inventing new ones.
    *   **Rule**: Check if the project already has a similar pattern before inventing a new abstraction.
    *   **Rule**: Extract shared utilities instead of duplicating code across modules.
    *   **Reason**: Consistent patterns reduce cognitive load and maintenance burden.


*   **¶INV_CLAIM_BEFORE_WORK**: An agent MUST swap `#needs-X` → `#active-X` before starting work on a tagged item.
    *   **Rule**: When a daemon-spawned or manually-triggered agent begins work on a tagged request, it must immediately claim the work by swapping the tag. This prevents double-processing by parallel agents.
    *   **Reason**: Stateless coordination. Tags are the state — `#active-X` means "someone is working on this."

*   **¶INV_ESCAPE_BY_DEFAULT**: All lifecycle tags in body text MUST be backtick-escaped unless intentional.
    *   **Rule**: `#needs-*`, `#active-*`, and `#done-*` tags in body text (logs, details, plans, debriefs) must be backtick-escaped (`` `#needs-*` ``) unless they are intentional discoverable tags on the `**Tags**:` line or explicitly promoted/acknowledged inline tags.
    *   **Enforcement**: `session.sh check` scans session artifacts for bare inline lifecycle tags during synthesis. Each bare tag must be either PROMOTED (→ request file + escape inline) or ACKNOWLEDGED (→ marked intentional) before synthesis can complete.
    *   **Reason**: Bare inline tags in non-discoverable contexts pollute `tag.sh find` results. Escape-by-default ensures every surviving bare tag represents a real, actionable work item.

## 6. LLM Output Physics

*   **¶INV_ENUM_OVER_FLOAT**: LLM confidence outputs must use named enum bands, not free-floating numbers.
    *   **Rule**: Define confidence as a discrete enum (e.g., `definitive`, `strong`, `moderate`, `weak`). Code maps bands to deterministic numeric scores via a single utility function.
    *   **Reason**: LLMs self-censor on floating-point outputs and cluster at round numbers. Enums constrain the output space and make routing deterministic.

*   **¶INV_RULE_TRACEABILITY**: Every LLM classification must trace to a named rule via a `ruleApplied` enum.
    *   **Rule**: Free-text rationale is a summary for display, not the audit trail. The enum IS the audit trail — each value maps 1:1 to a classification rule in the prompt.
    *   **Reason**: Debugging misclassifications requires knowing which rule fired, not parsing natural language.

*   **¶INV_ORG_CONTEXT_TWO_TIER**: Org-specific LLM behavior uses two tiers: type-level templates in code (version-controlled) + org-specific config in DB (runtime-tunable).
    *   **Rule**: Type templates are a TypeScript map keyed by `organization.type`. Org-specific overrides live in a JSONB field with structured fields + free-text. Never hardcode customer-specific logic.
    *   **Reason**: Prevents the "one customer trap" where prompt changes optimized for one org break another.


*   **¶INV_REUSE_OVER_REINVENT_MATCHING**: When a matching/scoring engine exists for direction A→B, invert it for B→A rather than building new matching rules.
    *   **Rule**: If you already have a service that does "given X, find matching Y" (with fuzzy matching, scoring, normalization), create an inverse method on that same service rather than writing new brittle SQL or hard-coded rules for "given Y, find matching X."
    *   **Reason**: The forward-direction engine already handles edge cases (normalization, fuzzy matching, multi-source scoring). Re-inventing matching rules from scratch is brittle and duplicates logic. Inversion leverages battle-tested code.


*   **¶INV_INFER_USER_FROM_GDRIVE**: Auto-detect user identity from Google Drive symlink. Do not ask.
    *   **Rule**: When a skill needs user info (name, email), call `engine user-info` instead of prompting.
    *   **Detection**: Reads `~/.claude/scripts` symlink target (via `engine user-info`), extracts `GoogleDrive-email@domain` from the path. No CloudStorage scanning.
    *   **Usage**: `user-info.sh username` → `yarik`, `user-info.sh email` → `yarik@finchclaims.com`, `user-info.sh json` → full object.
    *   **Reason**: No extra state. The symlink already points to the user's Google Drive — derive identity from it.


*   **¶INV_TMUX_AND_FLEET_OPTIONAL**: Fleet/tmux is an optional enhancement, not a requirement.
    *   **Rule**: All hooks and scripts that interact with tmux/fleet MUST fail gracefully when running outside tmux. The core workflow engine (sessions, logging, tags, statusline) MUST work identically with or without fleet.
    *   **Pattern**: Guard tmux calls with `[ -n "${TMUX:-}" ]` check, and always use `|| true` when calling fleet.sh from hooks.
    *   **Reason**: Users may run Claude in a plain terminal, VSCode, or other environments. Fleet is a multi-pane coordination layer — its absence should never break the workflow.


*   **¶INV_REDIRECTION_OVER_PROHIBITION**: When preventing an undesired LLM behavior, provide an alternative action rather than just prohibiting the behavior.
    *   **Rule**: Redirections ("do X instead") are more reliable than prohibitions ("don't do Y"). When designing constraints for LLM agents, always pair a prohibition with a concrete alternative action the agent should take instead.
    *   **Reason**: Prohibitions require the model to suppress an impulse, which competes with training signals (helpfulness, efficiency). Redirections channel the impulse into a compliant action, which is fundamentally easier to follow.


*   **¶INV_PROTOCOL_IS_TASK**: When a skill protocol is active, the protocol defines the task.
    *   **Rule**: The user's request is an input parameter to the protocol, not a replacement for it. The agent executes the protocol; the user's request shapes what the protocol produces. "Implement X" means "execute the implementation protocol with X as the input" — not "write code for X and skip the protocol."
    *   **Reason**: Without this framing, the model treats the protocol as overhead wrapping the "real" task and optimizes it away. The protocol IS the task.

*   **¶INV_NEW_SESSION_BOUNDARY**: When a user requests a new session, create one. Do not continue the old one.
    *   **Rule**: When the user explicitly requests a new session — via next-skill selection (`§CMD_DEACTIVATE_AND_PROMPT_NEXT_SKILL`), `/dehydrate restart`, or saying "new session" / "next session" — the agent MUST create a fresh session directory via `§CMD_MAINTAIN_SESSION_DIR`. It MUST NOT reactivate, continue, or override errors in the previous session.
    *   **Prohibited**: Seeing `session.sh activate` reject because the session is completed/active and deciding to "override" or "continue anyway." The rejection IS the expected outcome — the old session is done.
    *   **Redirection**: If `session.sh activate` rejects, create a new session directory with `§CMD_MAINTAIN_SESSION_DIR`. The user's intent is forward motion, not recovery.
    *   **Reason**: Agents systematically conflate "next skill" with "continue this session" because their helpfulness bias prioritizes continuity. The user's new-session request is a boundary signal, not a suggestion.

*   **¶INV_PHASE_ENFORCEMENT**: Phase transitions are mechanically enforced via `session.sh phase`.
    *   **Rule**: When a session has a `phases` array (declared at activation), `session.sh phase` enforces sequential progression. Non-sequential transitions (skip forward or go backward) require `--user-approved "Reason: [why, citing user's response]"`.
    *   **Sub-phases**: Phases with the same major number and a higher minor number (e.g., 4.1 after 4.0) are auto-appended without pre-declaration.
    *   **Sub-phase skippability**: Sub-phases are optional — they represent alternative paths, not mandatory steps. `N.0→(N+1).0` is always allowed even when `N.1` is declared (skip over optional sub-phase). `N.M→(N+1).0` is always allowed (exit sub-phase to next major). Neither requires `--user-approved`.
    *   **Backward compat**: Sessions without a `phases` array have no enforcement — any transition is allowed.
    *   **Reason**: Agents systematically skip phases they judge as "unnecessary." Mechanical enforcement removes this judgment call — the user decides, not the agent.

*   **¶INV_SKILL_FEATURE_PROPAGATION**: When adding a new feature to a skill, propagate it to ALL applicable skills or tag for follow-up.
    *   **Rule**: When a new engine feature (phase enforcement array, walk-through config, deactivate wiring, mode presets, interrogation depth) is added to one skill, the same feature MUST be added to all other applicable skills in the same session — or each missing skill MUST be explicitly tagged `#needs-implementation` for follow-up.
    *   **Reason**: Feature additions without propagation create structural debt. Each improvement session that touches 1-3 skills leaves the remaining skills further behind, creating an ever-widening gap between "gold standard" and "stale" skills.

## 7. Filesystem Physics

*   **¶INV_GLOB_THROUGH_SYMLINKS**: The Glob tool does not traverse symlinks. Use `glob.sh` as a fallback for symlinked directories.
    *   **Rule**: When Glob returns empty for a path that should have files (especially `sessions/` or any symlinked directory), fall back to `engine glob '<pattern>' <path>`. For known symlinked paths (`sessions/`), prefer `glob.sh` directly.
    *   **Reason**: `sessions/` is symlinked to Google Drive. The Glob tool's internal engine silently skips symlinks, producing false "no results" responses.


*   **¶INV_NO_GIT_ON_CLOUD_SYNC**: Git repositories (`.git/`) must never be stored on cloud sync services (GDrive, Dropbox, OneDrive).
    *   **Rule**: Cloud sync services sync files individually and asynchronously. Git requires atomic multi-file writes to `.git/objects/`. This mismatch causes repository corruption. Use a proper Git remote (GitHub, GitLab, bare repo on a server) and deploy clean files (without `.git/`) to cloud sync if needed.
    *   **Reason**: This is a known, unfixable corruption pattern. No workaround (locking, single-writer discipline) reliably prevents it.


*   **¶INV_QUESTION_GATE_OVER_TEXT_GATE**: User-facing gates and option menus in skill protocols MUST use `AskUserQuestion` (tool-based blocking), never bare text.
    *   **Rule**: When a skill protocol needs user confirmation before proceeding, it must use `AskUserQuestion` with structured options. Text-based "STOP" instructions are unreliable — they depend on agent compliance. Tool-based gates are mechanically enforced.
    *   **Rule**: When a skill protocol specifies presenting choices, options, or menus to the user, the agent MUST use the `AskUserQuestion` tool. It MUST NOT render the options as a Markdown table, bullet list, or plain text in chat and then wait for the user to type a response.
    *   **Rule**: Before calling `AskUserQuestion`, the agent MUST output enough context in chat for the user to understand what the options mean and why they are being asked. A bare question with options but no surrounding explanation is a violation — the user cannot make an informed choice without context.
    *   **Rule**: `AskUserQuestion` option labels and descriptions MUST be descriptive and actionable. Labels explain *what* happens; descriptions explain *why* it matters. When an option triggers tagging, include the `#needs-X` tag in the label. No vague labels — every word must carry information.
        *   **Bad**: label=`"Delegate to /implement"`, description=`"Code change needed"`
        *   **Good**: label=`"#needs-implementation: add auth validation"`, description=`"Prevents unauthenticated access to the payment endpoint"`
    *   **Rule**: When the user responds to `AskUserQuestion` with an empty string or whitespace-only text (via "Other"), treat it as **"Use your best judgement."** The agent MUST:
        1. **Justify**: Output a blockquote in chat explaining which option(s) it is choosing and why (up to 3 lines).
            *   Format: `> Auto-proceeding with "[Option label]" — [reason, up to 3 lines].`
        2. **Choose**: For **single-select**, pick the first option (or the most contextually appropriate if none is marked Recommended). For **multi-select**, pick whichever option(s) the agent deems best given the current context.
        3. **Log**: Execute `§CMD_LOG_TO_DETAILS` with `**Type**: Auto-Decision` recording the question, the agent's choice, and the justification.
        4. **Proceed**: Continue execution as if the user had selected that option.
        *   **Scope**: Applies to ALL `AskUserQuestion` calls — phase gates, interrogation questions, depth selection, decisions, walk-throughs. No exceptions.
        *   **Constraint**: This rule ONLY triggers on empty/whitespace-only "Other" responses. Any non-empty text from "Other" is treated as user input per normal behavior.
    *   **Reason**: `AskUserQuestion` provides structured input, mechanical blocking, and clear selection semantics. Text-rendered menus are ambiguous (the user might type something unexpected), non-blocking (the agent might continue without waiting), and invisible to tool-use auditing. Context-free questions and vague option labels are equally harmful — they force the user to guess what the agent is referring to.

*   **¶INV_REQUEST_IS_SELF_CONTAINED**: REQUEST files must contain all context needed for execution.
    *   **Rule**: A worker must be able to fulfill a REQUEST without access to the requester's session state. Include relevant file paths, expectations, constraints, and requesting session reference inline.
    *   **Reason**: REQUESTs survive requester session death. The requester may have overflowed, deactivated, or been killed. The REQUEST file is the contract.

*   **¶INV_DELEGATE_IS_NESTABLE**: `/delegate` must operate without session activation.
    *   **Rule**: The `/delegate` skill reads from and writes to the current session directory. It does not call `session.sh activate`. It can be invoked from any phase of any skill without disturbing session state.
    *   **Reason**: Delegation happens mid-skill (during interrogation, walkthrough, or ad-hoc chat). Session activation would conflict with the active skill's session.

*   **¶INV_GRACEFUL_DEGRADATION**: Delegation modes degrade gracefully when infrastructure is unavailable.
    *   **Rule**: Async delegation without fleet degrades to manual pickup (REQUEST file + tag persists). Blocking delegation degrades to async if the session dies (tag persists, worker can still find it). Silent mode requires no infrastructure beyond the Task tool.
    *   **Reason**: Solo developers without fleet/daemon should still benefit from the delegation file format. Nothing is lost — just deferred.

*   **¶INV_DELEGATION_VIA_TEMPLATES**: A skill supports delegation if and only if it has `_REQUEST.md` and `_RESPONSE.md` templates in its `assets/` folder.
    *   **Rule**: Template presence is the opt-in signal. If a skill has no `_REQUEST.md` template, it does not accept delegation requests.
    *   **Rule**: The request template defines what a requester must fill in. The response template defines what a responder must deliver. Both are populated via `§CMD_POPULATE_LOADED_TEMPLATE`.
    *   **Rule**: REQUEST files are written to the **requesting** session directory. RESPONSE files are written to the **responding** session directory (where the skill executes).
    *   **Rule**: Each RESPONSE template is tailored to its skill's specific outputs (code changes for implement, decisions for brainstorm, docs updated for document, verdict for review, task checklist for chores, research report for research).
    *   **Reference**: See `~/.claude/docs/TAG_LIFECYCLE.md` for the full delegation flow and template inventory.
    *   **Reason**: Delegation was previously a parallel mechanism (3 standalone skills + separate files). This convention makes delegation a capability of each skill rather than a separate system.

*   **¶INV_DYNAMIC_DISCOVERY**: Tag-to-skill mapping must use dynamic template discovery, not static maps.
    *   **Rule**: Daemon dispatch discovers available skills by scanning for `TEMPLATE_*_REQUEST.md` files in each skill's `assets/` directory. No hardcoded tag registries or static configuration maps.
    *   **Rule**: `session.sh request-template '#needs-xxx'` resolves the tag noun to a skill, finds the template, and outputs it to stdout. This is the canonical lookup path.
    *   **Reason**: Static maps rot. Dynamic discovery is self-maintaining — adding a REQUEST template to a skill automatically makes it dispatchable. Removing the template removes the capability.

*   **¶INV_DIRECTORY_AWARENESS**: Agents must be aware of directive markdown files in directories they touch.
    *   **Rule**: Directive files are discovered via walk-up from touched directories to the project root. Two tiers:
        *   **Core directives** (always discovered): README.md, INVARIANTS.md, CHECKLIST.md. Surfaced as soft suggestions (CHECKLIST.md is also enforced as a hard gate at session deactivation).
        *   **Skill directives** (filtered by `directives` param): TESTING.md, PITFALLS.md. Only suggested when the active skill declares them in the `directives` field of session parameters.
    *   **Discovery**: `discover-directives.sh` performs walk-up search. `session.sh activate` discovers files from `directoriesOfInterest`. At runtime, a PostToolUse hook tracks `touchedDirs` in `.state.json` and suggests newly-discovered files. Both apply skill-directive filtering.
    *   **End-of-session**: `§CMD_MANAGE_DIRECTIVES` handles README updates, invariant capture, and pitfall capture based on session work.
    *   **Reason**: Agents systematically ignore directive files placed near their work. Infrastructure-level discovery guarantees delivery.

*   **¶INV_CHECKLIST_BEFORE_CLOSE**: A session cannot be deactivated with unprocessed CHECKLIST.md files.
    *   **Rule**: `session.sh deactivate` checks `checkPassed == true` in `.state.json` when `discoveredChecklists[]` is non-empty. If not set, deactivation is blocked.
    *   **Rule**: `§CMD_PROCESS_CHECKLISTS` must run during synthesis. The agent reads each checklist, evaluates items, then quotes results back via `session.sh check` (which sets `checkPassed=true`). The deactivate gate is the mechanical safety net.
    *   **Reason**: Checklists contain post-work requirements (testing steps, user questions, cleanup tasks). Allowing session close without processing them defeats their purpose.

*   **¶INV_REQUEST_BEFORE_CLOSE**: A session cannot be deactivated with unfulfilled request files.
    *   **Rule**: `session.sh check` Validation 3 reads `requestFiles[]` from `.state.json`. Every request file must (a) exist and (b) have no bare `#needs-*` tags anywhere in the file (backtick-escaped excluded). Formal REQUEST files (filename contains "REQUEST") must additionally have a `## Response` section. If any fail, check exits 1 and deactivation is blocked.
    *   **Rule**: The agent must resolve all bare `#needs-*` tags (swap to `#done-*` or backtick-escape). For formal REQUEST files, also add a `## Response` section.
    *   **Reason**: Request files are contracts between sessions. Closing a session without fulfilling its requests leaves broken promises in the system — future sessions that depend on the work will find unfulfilled tags.

*   **¶INV_WALKTHROUGH_TAGS_ARE_PASSIVE**: Tags placed during `§CMD_WALK_THROUGH_RESULTS` do NOT trigger delegation offers.
    *   **Rule**: Tags applied during walkthrough triage are protocol-placed (expected output of the walkthrough step). They are recorded but do not invoke `/delegate`. Tags in all other contexts (interrogation, QnA, ad-hoc chat, side discovery) are reactive — they trigger a `/delegate` offer.
    *   **Reason**: Walkthrough triage already handles tag placement as part of its protocol. Offering delegation on top of that would double-prompt the user for every triage decision.

*   **¶INV_1_TO_1_TAG_SKILL**: Every `#needs-X` tag maps to exactly one skill `/X`. No generic tags.
    *   **Rule**: The tag noun IS the skill name. `#needs-brainstorm` → `/brainstorm`, `#needs-implementation` → `/implement`, `#needs-chores` → `/chores`. No generic `#needs-delegation` or catch-all tags. If a new work type needs a tag, it needs a corresponding skill (or mode within an existing skill).
    *   **Reason**: Generic tags create routing ambiguity. 1:1 mapping makes the system self-documenting — seeing a tag tells you exactly which skill resolves it.

*   **¶INV_MODE_STANDARDIZATION**: All modal skills have exactly **3 named modes + Custom**. Custom is always the last mode.
    *   **Rule**: Skills with multiple modes present them via `AskUserQuestion` in Phase 1 Setup. Mode definitions live in `skills/X/modes/*.md` (per-skill, not shared). SKILL.md contains a summary table of available modes; full definitions are in separate files. Custom mode reads all 3 named mode files to understand the flavor space, then synthesizes a hybrid mode from user input.
    *   **Reason**: Consistent UX across skills. Users learn one pattern. Mode files keep SKILL.md lean and make modes independently versionable. The 3+Custom constraint prevents mode bloat.

*   **¶INV_NO_BUILTIN_COLLISION**: Engine skill names must not collide with Claude Code built-in CLI commands.
    *   **Rule**: Before naming a new skill, check against the known built-in list: `/help`, `/clear`, `/compact`, `/config`, `/debug`, `/init`, `/login`, `/logout`, `/review`, `/status`, `/doctor`, `/hooks`, `/listen`, `/vim`, `/terminal-setup`, `/memory`. Built-in commands intercept at the CLI layer before the LLM sees the input — a colliding skill will be silently shadowed.
    *   **Detection**: Built-in commands produce `<command-name>` tags in the output. If invoking a skill produces a `<command-name>` tag instead of the engine protocol, the name collides.
    *   **Reason**: The `/debug` skill was silently broken for its entire lifetime because Claude Code's built-in `/debug` intercepted it. Renamed to `/fix` to resolve.
