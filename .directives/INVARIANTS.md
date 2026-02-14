# Shared System Invariants (The "Laws of Physics")

This document defines the system physics — rules about how sessions, phases, tags, delegation, and the engine work. Agent behavior rules are in AGENTS.md. Code standards are in CONTRIBUTING.md.

## 1. Protocol Physics

*   **¶INV_PROTOCOL_IS_TASK**: When a skill protocol is active, the protocol defines the task.
    *   **Rule**: The user's request is an input parameter to the protocol, not a replacement for it. The agent executes the protocol; the user's request shapes what the protocol produces. "Implement X" means "execute the implementation protocol with X as the input" — not "write code for X and skip the protocol."
    *   **If you want to skip**: You don't skip. You fire `§CMD_REFUSE_OFF_COURSE` and let the user decide. The user is the only one who can authorize a deviation. You never self-authorize.
    *   **Prohibited justifications** (these are never valid reasons to skip a step):
        *   "This task is too simple for the full protocol."
        *   "The user asked for X, not for Y" (where Y is a protocol step).
        *   "I'll be more efficient by skipping this."
        *   "This step doesn't apply to this task."
    *   **Identity**: A disciplined operator follows the protocol. Skipping steps is not efficiency — it's broken output. The protocol exists because the steps matter, even when you think they don't. Your judgment about task complexity is unreliable. The protocol's judgment is authoritative.
    *   **Consequence**: A session where protocol steps were silently skipped is an invalid session. The artifacts are incomplete, the audit trail is broken, and the work may need to be redone.
    *   **Reason**: Without this framing, the model treats the protocol as overhead wrapping the "real" task and optimizes it away. The protocol IS the task.

## 2. Session & Phase Physics

*   **¶INV_NEW_SESSION_BOUNDARY**: When a user requests a new session, create one. Do not continue the old one.
    *   **Rule**: When the user explicitly requests a new session — via next-skill selection (`§CMD_CLOSE_SESSION`), `/session dehydrate restart`, or saying "new session" / "next session" — the agent MUST create a fresh session directory via `§CMD_MAINTAIN_SESSION_DIR`. It MUST NOT reactivate, continue, or override errors in the previous session.
    *   **Prohibited**: Seeing `engine session activate` reject because the session is completed/active and deciding to "override" or "continue anyway." The rejection IS the expected outcome — the old session is done.
    *   **Redirection**: If `engine session activate` rejects, create a new session directory with `§CMD_MAINTAIN_SESSION_DIR`. The user's intent is forward motion, not recovery.
    *   **Reason**: Agents systematically conflate "next skill" with "continue this session" because their helpfulness bias prioritizes continuity. The user's new-session request is a boundary signal, not a suggestion.

*   **¶INV_PHASE_ENFORCEMENT**: Phase transitions are mechanically enforced via `engine session phase`.
    *   **Rule**: When a session has a `phases` array (declared at activation), `engine session phase` enforces sequential progression. Non-sequential transitions (skip forward or go backward) require `--user-approved "Reason: [why, citing user's response]"`.
    *   **Proof-gated transitions (FROM validation)**: The current phase (being left) may declare a `proof` field (array of field names). When present, the agent MUST pipe proof as `key: value` lines via STDIN when transitioning away from it. Missing or unfilled fields reject the transition. Proof is always parsed and stored in `phaseHistory` as structured objects when provided, regardless of whether the current phase declares proof fields. Semantically: proof on a phase describes what must be accomplished IN that phase before leaving it.
    *   **Letter suffixes**: Sub-phase labels may include a single uppercase letter suffix (e.g., `"3.1A: Agent Handoff"`). The letter is stripped for enforcement (enforces as `3.1`) but preserved in `phaseHistory` for audit trail. Distinguishes alternative branches.
    *   **Context overflow recovery**: `/session continue` uses `engine session continue` to resume the heartbeat without touching phase state. No phase transition needed — the saved phase in `.state.json` is the source of truth.
    *   **Sub-phases**: Phases with the same major number and a higher minor number (e.g., 4.1 after 4.0) are auto-appended without pre-declaration.
    *   **Sub-phase skippability**: Sub-phases are optional — they represent alternative paths, not mandatory steps. `N.0→(N+1).0` is always allowed even when `N.1` is declared (skip over optional sub-phase). `N.M→(N+1).0` is always allowed (exit sub-phase to next major). Neither requires `--user-approved`.
    *   **Backward compat**: Sessions without a `phases` array have no enforcement — any transition is allowed. Phases without `proof` fields emit a stderr warning if sibling phases declare proof (nudge, not block).
    *   **Reason**: Agents systematically skip phases they judge as "unnecessary." Mechanical enforcement removes this judgment call — the user decides, not the agent.

*   **¶INV_USER_APPROVED_REQUIRES_TOOL**: The `--user-approved` flag on `engine session phase` requires a reason obtained via `AskUserQuestion`.
    *   **Rule**: `AskUserQuestion` is the ONLY valid mechanism to obtain a `--user-approved` reason string. The reason MUST quote the user's answer from the `AskUserQuestion` tool response. Self-authored reasons are invalid regardless of how reasonable they seem.
    *   **Valid example**: `--user-approved "User chose 'Go back to 2: Research Loop' via AskUserQuestion"`
    *   **Valid example**: `--user-approved "User said 'skip calibration, findings are clear' via AskUserQuestion"`
    *   **Invalid example**: `--user-approved "Phase doesn't apply to this task"` (self-authored, no tool call)
    *   **Invalid example**: `--user-approved "Skipping calibration per user request"` (paraphrase, not a quoted tool response)
    *   **Mechanism**: Before using `--user-approved`, the agent MUST have called `AskUserQuestion` in the current conversation turn (or a recent prior turn). The reason string must contain a verbatim quote of the user's selection or text from that tool response.
    *   **Redirection**: Instead of self-authoring a reason, call `AskUserQuestion` with the phase transition as an option. The user's response becomes the valid reason.
    *   **Reason**: Agents systematically invent plausible-sounding justifications for non-sequential phase transitions. Text-based prohibition lists are ineffective because agents rephrase around them. Requiring a tool call creates a mechanical audit trail — no `AskUserQuestion` in the transcript means the `--user-approved` is invalid.

## 3. Tag Physics

*   **¶INV_ESCAPE_BY_DEFAULT**: All lifecycle tags in body text MUST be backtick-escaped unless intentional.
    *   **Rule**: `#needs-*`, `#delegated-*`, `#next-*`, `#claimed-*`, and `#done-*` tags in body text (logs, details, plans, debriefs) must be backtick-escaped (`` `#needs-*` ``) unless they are intentional discoverable tags on the `**Tags**:` line or explicitly promoted/acknowledged inline tags.
    *   **Enforcement**: `engine session check` scans session artifacts for bare inline lifecycle tags during synthesis. Each bare tag must be either PROMOTED (→ request file + escape inline) or ACKNOWLEDGED (→ marked intentional) before synthesis can complete.
    *   **Reason**: Bare inline tags in non-discoverable contexts pollute `engine tag find` results. Escape-by-default ensures every surviving bare tag represents a real, actionable work item.

*   **¶INV_1_TO_1_TAG_SKILL**: Every `#needs-X` tag maps to exactly one skill `/X`. No generic tags.
    *   **Rule**: The tag noun IS the skill name. `#needs-brainstorm` → `/brainstorm`, `#needs-implementation` → `/implement`, `#needs-chores` → `/chores`. No generic `#needs-delegation` or catch-all tags. If a new work type needs a tag, it needs a corresponding skill (or mode within an existing skill).
    *   **Reason**: Generic tags create routing ambiguity. 1:1 mapping makes the system self-documenting — seeing a tag tells you exactly which skill resolves it.

## 4. Multi-Agent Safety

*   **¶INV_NO_GIT_STATE_COMMANDS**: Agents in multi-agent scenarios MUST NOT run git state-changing commands.
    *   **Rule**: Reserved for future implementation. When multi-agent support is active, agents must coordinate git operations through the engine, not directly.

## 5. Delegation Physics

*   **¶INV_CLAIM_BEFORE_WORK**: An agent MUST swap `#delegated-X` → `#claimed-X` before starting work on a tagged item.
    *   **Rule**: When a daemon-spawned or manually-triggered agent begins work on a tagged request, it must immediately claim the work by swapping the tag via `/delegation-claim`. This prevents double-processing by parallel agents. The swap uses `engine tag swap`, which errors if the old tag is already gone (race condition safety — another worker already claimed it).
    *   **Reason**: Stateless coordination. Tags are the state — `#claimed-X` means "someone is working on this." The `#delegated-X` → `#claimed-X` transition (not `#needs-X` → `#claimed-X`) ensures work was human-approved before any worker touches it.

*   **¶INV_NEEDS_IS_STAGING**: `#needs-X` is a staging tag. Daemons MUST NOT monitor `#needs-X`.
    *   **Rule**: `#needs-X` means "work identified, pending human review." Only `#delegated-X` triggers autonomous daemon dispatch. The transition `#needs-X` → `#delegated-X` requires human approval via `§CMD_DISPATCH_APPROVAL`.
    *   **Rule**: Agents may freely create `#needs-X` tags (via `§CMD_HANDLE_INLINE_TAG`, `§CMD_CAPTURE_SIDE_DISCOVERIES`, REQUEST file creation). These tags are inert until a human explicitly approves dispatch.
    *   **Reason**: Eliminates the race condition where daemons grab work the instant a tag appears, before the user has reviewed or batched related items.

*   **¶INV_NEXT_IS_IMMEDIATE**: `#next-X` is an immediate-execution tag. Daemons MUST NOT monitor `#next-X`.
    *   **Rule**: `#next-X` means "user chose to handle this in the next skill session." It is set during `§CMD_DISPATCH_APPROVAL` via the "Claim for next skill" option. The next skill auto-claims matching `#next-X` items on activation by swapping `#next-X` → `#claimed-X` and writing breadcrumbs normally.
    *   **Rule**: Daemons MUST ignore `#next-X` tags (same policy as `#needs-X`). Only `#delegated-X` triggers daemon dispatch.
    *   **Rule**: If `#next-X` items remain unworked (session died, user forgot), they are detectable as stale. `/delegation-review` surfaces them for re-routing. They do NOT auto-decay — manual handling only.
    *   **Rule**: Multiple `#next-*` items of different tag nouns are allowed simultaneously. The activating skill only auto-claims items matching its own tag noun (e.g., `/implement` claims `#next-implementation` but NOT `#next-brainstorm`). Non-matching `#next-*` items remain and are surfaced as context signal for subsequent skills.
    *   **Reason**: `#next-X` enables a "fast lane" that bypasses the daemon entirely. It must not race with daemon dispatch. The separate state (vs. reusing `#claimed-X`) preserves `#claimed-X`'s breadcrumb-writing semantics from `/delegation-claim` and makes abandoned items detectable.

*   **¶INV_DISPATCH_APPROVAL_REQUIRED**: The `#needs-X` → `#delegated-X` and `#needs-X` → `#next-X` transitions require human approval.
    *   **Rule**: Agents MUST NOT auto-flip `#needs-X` → `#delegated-X` or `#needs-X` → `#next-X` without presenting the dispatch approval walkthrough (`§CMD_DISPATCH_APPROVAL`). The human reviews each tagged item and approves, defers, claims for next skill, or dismisses.
    *   **Reason**: The user is the authority on what gets dispatched. Batch review during synthesis enables informed decision-making about which work items are ready for autonomous processing or immediate execution.

*   **¶INV_REQUEST_IS_SELF_CONTAINED**: REQUEST files must contain all context needed for execution.
    *   **Rule**: A worker must be able to fulfill a REQUEST without access to the requester's session state. Include relevant file paths, expectations, constraints, and requesting session reference inline.
    *   **Reason**: REQUESTs survive requester session death. The requester may have overflowed, deactivated, or been killed. The REQUEST file is the contract.

*   **¶INV_DELEGATE_IS_NESTABLE**: `/delegation-create` must operate without session activation.
    *   **Rule**: The `/delegation-create` skill reads from and writes to the current session directory. It does not call `engine session activate`. It can be invoked from any phase of any skill without disturbing session state.
    *   **Reason**: Delegation happens mid-skill (during interrogation, walkthrough, or ad-hoc chat). Session activation would conflict with the active skill's session.

*   **¶INV_GRACEFUL_DEGRADATION**: Delegation modes degrade gracefully when infrastructure is unavailable.
    *   **Rule**: Async delegation without fleet degrades to manual pickup (REQUEST file + tag persists). Blocking delegation degrades to async if the session dies (tag persists, worker can still find it). Silent mode requires no infrastructure beyond the Task tool.
    *   **Reason**: Solo developers without fleet/daemon should still benefit from the delegation file format. Nothing is lost — just deferred.

*   **¶INV_DELEGATION_VIA_TEMPLATES**: A skill supports delegation if and only if it has `_REQUEST.md` and `_RESPONSE.md` templates in its `assets/` folder.
    *   **Rule**: Template presence is the opt-in signal. If a skill has no `_REQUEST.md` template, it does not accept delegation requests.
    *   **Rule**: The request template defines what a requester must fill in. The response template defines what a responder must deliver. Both are populated via `§CMD_WRITE_FROM_TEMPLATE`.
    *   **Rule**: REQUEST files are written to the **requesting** session directory. RESPONSE files are written to the **responding** session directory (where the skill executes).
    *   **Rule**: Each RESPONSE template is tailored to its skill's specific outputs (code changes for implement, decisions for brainstorm, docs updated for document, verdict for review, task checklist for chores, research report for research).
    *   **Reference**: See `~/.claude/docs/TAG_LIFECYCLE.md` for the full delegation flow and template inventory.
    *   **Reason**: Delegation was previously a parallel mechanism (3 standalone skills + separate files). This convention makes delegation a capability of each skill rather than a separate system.

*   **¶INV_DYNAMIC_DISCOVERY**: Tag-to-skill mapping must use dynamic template discovery, not static maps.
    *   **Rule**: Daemon dispatch discovers available skills by scanning for `TEMPLATE_*_REQUEST.md` files in each skill's `assets/` directory. No hardcoded tag registries or static configuration maps.
    *   **Rule**: `engine session request-template '#needs-xxx'` resolves the tag noun to a skill, finds the template, and outputs it to stdout. This is the canonical lookup path.
    *   **Reason**: Static maps rot. Dynamic discovery is self-maintaining — adding a REQUEST template to a skill automatically makes it dispatchable. Removing the template removes the capability.

## 6. Directive Physics

*   **¶INV_DIRECTIVE_STACK**: Agents must load the full stack of directive files (child-to-root ancestor chain) when working in a directory. Enforcement is escalating.
    *   **Rule**: Directive files live in `.directives/` subfolders at each directory level (e.g., `packages/estimate/.directives/INVARIANTS.md`). Discovery walks up from touched directories to the project root, checking `.directives/` at each level. Eight directive types across two tiers:
        *   **Core directives** (always discovered): AGENTS.md, INVARIANTS.md, ARCHITECTURE.md. Surfaced as soft suggestions.
        *   **Skill directives** (filtered by `directives` param): TESTING.md, PITFALLS.md, CONTRIBUTING.md, TEMPLATE.md, CHECKLIST.md. Only suggested when the active skill declares them in the `directives` field of session parameters. CHECKLIST.md has a **hard gate** at deactivation: when discovered, `§CMD_PROCESS_CHECKLISTS` must pass before `engine session deactivate` succeeds. Skills that declare it: `/implement`, `/fix`, `/test`.
    *   **Enforcement**: Escalating two-hook architecture. PostToolUse hook (`post-tool-use-discovery.sh`) discovers directives and adds them to `pendingDirectives` in `.state.json` with a warning. PreToolUse hook (`pre-tool-use-directive-gate.sh`) blocks after a threshold of tool calls if `pendingDirectives` is non-empty. Reading a pending file clears it from the list.
    *   **Discovery**: `engine discover-directives` performs walk-up search (full ancestor chain — all directives from child to root apply cumulatively), checking `.directives/` subfolders first with flat directory root fallback. `engine session activate` discovers files from `directoriesOfInterest`. At runtime, the PostToolUse hook tracks `touchedDirs` in `.state.json` and discovers files for newly-touched directories. Both apply skill-directive filtering.
    *   **End-of-session**: `§CMD_MANAGE_DIRECTIVES` handles AGENTS.md updates, invariant capture, pitfall capture, and contributing-pattern capture based on session work.
    *   **Reason**: Agents systematically ignore directive files placed near their work. Escalating enforcement (warn then block) ensures directives are always loaded.

*   **¶INV_CHECKLIST_BEFORE_CLOSE**: A session cannot be deactivated with unprocessed CHECKLIST.md files.
    *   **Rule**: `engine session deactivate` checks `checkPassed == true` in `.state.json` when `discoveredChecklists[]` is non-empty. If not set, deactivation is blocked.
    *   **Rule**: `§CMD_PROCESS_CHECKLISTS` must run during synthesis. The agent reads each checklist, evaluates items, then quotes results back via `engine session check` (which sets `checkPassed=true`). The deactivate gate is the mechanical safety net.
    *   **Reason**: Checklists contain post-work requirements (testing steps, user questions, cleanup tasks). Allowing session close without processing them defeats their purpose.

*   **¶INV_REQUEST_BEFORE_CLOSE**: A session cannot be deactivated with unfulfilled request files.
    *   **Rule**: `engine session check` Validation 3 reads `requestFiles[]` from `.state.json`. Every request file must (a) exist and (b) have no bare `#needs-*` tags anywhere in the file (backtick-escaped excluded). Formal REQUEST files (filename contains "REQUEST") must additionally have a `## Response` section. If any fail, check exits 1 and deactivation is blocked.
    *   **Rule**: The agent must resolve all bare `#needs-*` tags (swap to `#done-*` or backtick-escape). For formal REQUEST files, also add a `## Response` section.
    *   **Reason**: Request files are contracts between sessions. Closing a session without fulfilling its requests leaves broken promises in the system — future sessions that depend on the work will find unfulfilled tags.

## 7. Engine Physics

*   **¶INV_ENGINE_COMMAND_DISPATCH**: All engine operations MUST go through `engine <command>`.
    *   **Rule**: Use `engine log`, `engine session`, `engine tag`, `engine research`, `engine session-search`, `engine doc-search`, etc. The `engine` command is available as a bare command via PATH — just use `engine`. Never resolve it manually.
    *   **Prohibited**: Any absolute or relative path to engine scripts. Examples: `~/.claude/engine/scripts/engine.sh`, `~/.claude/scripts/session.sh`, `~/.claude/scripts/log.sh`, `~/.claude/tools/session-search/session-search.sh`, `$(which engine)`. Use `engine research`, `engine tag swap`, `engine session-search query` instead.
    *   **Reason**: The heartbeat hook allowlists `engine` commands specifically; full paths are blocked. Resolving the `engine` script path manually (e.g., guessing `~/.claude/engine/scripts/engine.sh`) bypasses PATH and may reference a stale or wrong location.
    *   **Cross-ref**: Originally captured in `~/.claude/docs/.directives/INVARIANTS.md`. Promoted to shared for universal visibility.

## 8. Phase Execution Physics

*   **¶INV_BOOT_SECTOR_AT_TOP**: Every protocol-tier SKILL.md starts with `§CMD_EXECUTE_SKILL_PHASES`.
    *   **Rule**: The first instruction in a protocol-tier skill (after frontmatter and title) must invoke `§CMD_EXECUTE_SKILL_PHASES`. This is the boot sector — it tells the LLM "run through all my phases." Phase sections follow below.
    *   **Scope**: Only protocol-tier skills (those with `phases` arrays). Utility-tier skills (sessionless, no phases) do not use the boot sector.
    *   **Reason**: The boot sector ensures the LLM encounters the phase orchestrator before any phase-specific prose, establishing the mechanical execution pattern from the start.

*   **¶INV_STEPS_ARE_COMMANDS**: Phase steps MUST be `§CMD_*` references.
    *   **Rule**: The `steps` array in a phase declaration contains only `§CMD_*` command names. Prose instructions are not steps — they belong in SKILL.md phase sections, executed after `§CMD_EXECUTE_PHASE_STEPS` completes.
    *   **Redirection**: If you want to add a prose instruction as a step, extract it into a `CMD_*.md` file first, then reference it as a step.
    *   **Reason**: Mechanical step execution requires machine-parseable command references. Prose in steps would break hook-driven preloading and proof schema derivation.

*   **¶INV_PROOF_IS_DERIVED**: Phase proof is the concatenation of its steps' proof schemas.
    *   **Rule**: Skills declare `steps` and `commands` per phase. The `proof` array contains data fields that the step commands produce (as defined in each CMD file's `## PROOF FOR §CMD_X` section). Phase proof is the union of all step proof schemas plus any phase-level data fields.
    *   **Enforcement**: `engine session phase` extracts standard JSON Schemas from each step's CMD file, merges them into a combined schema, and validates the proof JSON against it (exit 1 on failure). The validation tool is `tools/json-schema-validate/`.
    *   **Reason**: Co-located proof schemas (in CMD files) are the source of truth. Declaring proof separately from steps creates drift — the proof list diverges from what the commands actually produce.

*   **¶INV_PROOF_COLOCATED**: Each `CMD_*.md` file has a `## PROOF FOR §CMD_X` section.
    *   **Rule**: Every extracted command file in `~/.claude/engine/.directives/commands/` must include a proof schema section at the bottom. The schema uses standard JSON Schema format (`$schema`, `type: object`, `properties`, `required`, `additionalProperties`).
    *   **Rule**: Commands that orchestrate other commands (like `§CMD_RUN_SYNTHESIS_PIPELINE` or `§CMD_EXECUTE_PHASE_STEPS`) note that proof comes from the commands they invoke, not from themselves.
    *   **Reason**: Co-location keeps command files self-contained (definition + proof contract). The hook preloads CMD files into context — the LLM sees the proof schema alongside the command definition.

## 9. Hook Physics

*   **¶INV_PREFER_AC_OVER_STDOUT**: Hooks SHOULD use JSON `additionalContext` over plain stdout.
    *   **Rule**: When delivering content to the LLM from hooks, use `hookSpecificOutput.additionalContext` (with `hookEventName`) rather than plain stdout. Both mechanisms work for SessionStart and UserPromptSubmit, but `additionalContext` is the documented, structured delivery path.
    *   **Reason**: `additionalContext` is the official mechanism per Claude Code docs. Plain stdout works but is the legacy/simple path. Consistent use of `additionalContext` makes hook output parseable and debuggable.

## 10. Token Economy

*   **¶INV_TRUST_CACHED_CONTEXT**: Do not burn tokens on redundant operations.
    *   **Rule**: If you have loaded `DEHYDRATED_CONTEXT.md` or `DEHYDRATED_DOCS.md` during session rehydration, you MUST NOT read the individual files contained within them (e.g., `_LOG.md`, specs) unless you have a specific reason to believe they have changed externally.
    *   **Rule**: Rely on your context window. Do not `read_file` something just to check a detail if you recently read it in a dehydrated block. Memory over IO.
    *   **Rule**: Prefer single, larger tool calls over many small ones. Batch operations.
    *   **Rule**: When you know a file exists and you have its content in a summary/dehydrated file, trust it. Blind trust.
    *   **Reason**: Token-expensive re-reads of already-loaded content waste context budget and add latency. Trust the cache.

## 11. Naming Conventions

*   **¶INV_SIGIL_SEMANTICS**: Sigils encode definition vs reference semantics.
    *   **Rule**: `¶` (pilcrow) marks a **definition** — the place where a command, invariant, feed, or tag section is declared and specified. `§` (section sign) marks a **reference** — a citation of something defined elsewhere.
    *   **Applies to**: All sigiled nouns — `CMD_`, `INV_`, `FEED_`, `TAG_`.
    *   **Definition sites**: COMMANDS.md headings (`¶CMD_X`), CMD_*.md headings (`¶CMD_X`), INVARIANTS.md entries (`¶INV_X`), AGENTS.md entries (`¶INV_X`), CONTRIBUTING.md entries (`¶INV_X`), TAGS.md section headers (`¶FEED_X`, `¶TAG_X`), any file's inline invariant definitions (`¶INV_X`).
    *   **Reference sites**: SKILL.md steps arrays (`§CMD_X`), body text cross-references (`§CMD_Y`, `§INV_Y`), PROOF FOR headings (`§CMD_X`), docs/ (`§INV_X`, `§CMD_X`).
    *   **Governance**: Any file may define an invariant using `¶INV_X`. Only COMMANDS.md and CMD_*.md may define commands using `¶CMD_X`.
    *   **Redirection**: If you're about to write a sigiled noun, ask: "Am I defining it here, or referring to it?" `¶` = defining, `§` = referring.
    *   **Reason**: Without semantic sigils, readers cannot distinguish "this is defined here" from "this is defined elsewhere." The convention enables grep-based discovery: `grep '¶CMD_'` finds all definition sites; `grep '§CMD_'` finds all usage sites.

*   **¶INV_EPIC_SLUG_SIGIL**: Epic and chapter references use the `@` sigil prefix.
    *   **Rule**: When referencing epics or chapters by their semantic slug, prefix with `@`: `@scope/slug` (e.g., `@app/auth-system`, `@packages/sdk/types`). This is the canonical format in vision documents, dependency graphs, plans, logs, and inline references.
    *   **Sigil inventory**: `#` = tags, `§` = commands, `¶` = invariants, `@` = epic/chapter slugs. Each sigil is distinct and greppable.
    *   **Slug format**: Path-based semantic slug mirroring project structure (e.g., `app/auth-system`, `packages/estimate/layout-extraction`). Slugs are stable identifiers — renaming a slug of a completed chapter triggers re-execution.
    *   **Workspace alignment**: Epic slugs double as workspace directory paths. `@apps/estimate-viewer/extraction` is both an epic reference and a valid `WORKSPACE` value. Sessions created with `WORKSPACE=apps/estimate-viewer/extraction` live at `apps/estimate-viewer/extraction/sessions/`. Epic directories coexist alongside source code directories (e.g., `src/`) within package folders.
    *   **Usage examples**:
        *   Chapter headings: `### @app/auth-system: Auth System Refactor`
        *   Dependencies: `**Depends on**: @app/auth-system`
        *   Dependency graphs: `@app/auth-system ──► @app/rate-limiting`
        *   Inline references: "See `@app/auth-system` for the token service work"
        *   Workspace: `engine run --workspace apps/estimate-viewer/extraction`
    *   **Discovery**: `grep '@app/' docs/` finds all epics in the `app` scope.
    *   **Reason**: Epics/chapters are first-class addressable entities in the orchestration system. A dedicated sigil prevents collision with tags (`#`), commands (`§`), and invariants (`¶`), and enables mechanical discovery.
