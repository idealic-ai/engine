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
    *   **Proof-gated transitions (FROM validation)**: The current phase (being left) may declare a `proof` field (array of field names). When present, the agent MUST pipe proof as JSON via STDIN when transitioning away from it. Missing or unfilled fields reject the transition. Proof is always parsed and stored in `phaseHistory` as structured objects when provided, regardless of whether the current phase declares proof fields. Semantically: proof on a phase describes what must be accomplished IN that phase before leaving it.
    *   **FROM proof applies even on skip**: When skipping Phase 1→3 with `--user-approved`, FROM validation checks Phase 1's proof (the phase being LEFT). The agent must prove Phase 1's work was done before leaving it. `--user-approved` bypasses sequential enforcement (allows non-sequential jumps) but does NOT bypass proof validation — these are independent checks. If Phase 1 has proof fields but no work was done, the skip fails because proof cannot be provided.
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

*   **¶INV_BACKTICK_INERT_SIGIL**: Backtick-enclosed sigiled references are inert — no scanning, no preloading, no tag actions.
    *   **Rule**: When a sigiled reference (`§CMD_*`, `§FMT_*`, `§INV_*`, `#needs-*`, etc.) is enclosed in backticks, it is a **mention** — documentation, not a dependency or action. All automated systems (tag discovery, reference preloading, dispatch routing) MUST ignore backtick-escaped references.
    *   **Applies to**: Tag lifecycle (`#needs-*` etc. — see `§INV_ESCAPE_BY_DEFAULT`), reference preloading (`§CMD_*`, `§FMT_*`, `§INV_*` — scanner skips backticked refs), code fence blocks (treated as bulk-escaped — all refs inside are inert).
    *   **Mechanism**: Two-pass filtering. First strip backtick spans and code fence blocks, then scan remaining text for bare sigiled references. This pattern is shared by `engine tag find` (tag discovery) and `resolve_refs()` (reference preloading).
    *   **Invoke vs. Mention**: In algorithm/instruction sections (e.g., "Invoke §CMD_DECISION_TREE with..."), use **bare** refs — these are invocations that trigger preloading. In documentation/definition sections (e.g., "Separated from `§CMD_DECISION_TREE` because..."), use **backticked** refs — these are mentions that should not trigger preloading. Code fence blocks are always inert regardless.
    *   **Reason**: Unifies the escaping convention across tags and preloads. Backtick = "I'm mentioning this, not invoking it" — same semantic everywhere.

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
    *   **End-of-session**: `§CMD_MANAGE_DIRECTIVES` handles AGENTS.md updates, invariant capture, and pitfall capture based on session work.
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

*   **¶INV_JSONSCHEMA_COMPLIANCE**: When a JSON Schema is provided in context, agents MUST comply with it fully — not just the property names.
    *   **Rule**: Read the **entire** schema, not just the `properties` block. The `required` array lists fields that MUST be present — omitting a required field causes validation failure. The `type` constraints define what values are acceptable. The `description` fields explain what each property means.
    *   **Rule**: Every field in `"required"` MUST appear in your JSON, even if the value is an empty array `[]` or `null`. Missing required fields are rejected by the engine's JSON Schema validator.
    *   **Redirection**: If you are about to construct a JSON payload that targets a schema, scan the schema's `required` array first. Then check each property's `type` and `description`. Only then construct the JSON.
    *   **Reason**: Agents systematically read `properties` for field names but skip `required`, `type`, and `description`. This invariant was created after an agent missed `directoriesOfInterest` despite having the full schema in context — proving the failure mode is format-blindness, not missing information.

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
    *   **Exception**: Preloaded files require Read before Edit — see `¶INV_PRELOAD_IS_REFERENCE_ONLY`.
    *   **Reason**: Token-expensive re-reads of already-loaded content waste context budget and add latency. Trust the cache.

*   **¶INV_PRELOAD_IS_REFERENCE_ONLY**: Preloaded content is already in your context. Do NOT re-read it. Editing requires an explicit Read.
    *   **Rule**: Content injected via hooks (`additionalContext`, `[Preloaded: path]` markers) is delivered to your context window for **reading and reference only**. Claude Code's Edit tool maintains its own registry of "read" files — hook-injected content is NOT registered in that registry.
    *   **Rule**: For **reference purposes**, preloaded content is **complete and sufficient**. Do NOT call Read on a file that was already preloaded — the content is already in your context window. This includes directive files (AGENTS.md, CONTRIBUTING.md, PITFALLS.md, etc.) auto-injected by hooks.
    *   **Rule**: To **edit** a preloaded file, you MUST call the Read tool on it first. The Read call registers the file with the Edit tool. Without it, Edit will block with "you must read the file first."
    *   **Redirection** (`¶INV_REDIRECTION_OVER_PROHIBITION`): When you see `[Preloaded: path]` content, trust it — the file is in your context. Only call Read if you intend to Edit. When you see `[Suggested — read these files for full context]:` with path-only listings, those files are NOT in your context — Read them if needed.
    *   **Two markers**:
        *   `[Preloaded: /path/to/file]` + file content inline → **Already loaded. Do NOT Read.**
        *   `[Suggested — read these files for full context]:` + path list → **Not loaded. Read if relevant.**
    *   **Scope**: Applies to ALL preload sources — SessionStart standards (COMMANDS.md, INVARIANTS.md, SIGILS.md), phase CMD files, skill SKILL.md, templates, directive files, dehydrated context files.
    *   **Not affected**: Files you loaded yourself via the Read tool. Those are already registered.
    *   **Reason**: Hooks deliver content via `additionalContext` injection, which bypasses the Edit tool's read-tracking. The agent sees the content and reasonably assumes it can edit it — but the Edit tool's internal state disagrees. Agents also systematically re-read preloaded directive files, wasting context tokens. This invariant makes both limitations explicit.

## 11. Naming Conventions

*   **¶INV_SIGIL_SEMANTICS**: Sigils encode definition vs reference semantics.
    *   **Rule**: `¶` (pilcrow) marks a **definition** — the place where a command, invariant, feed, or tag section is declared and specified. `§` (section sign) marks a **reference** — a citation of something defined elsewhere.
    *   **Applies to**: All sigiled nouns — `CMD_`, `INV_`, `FEED_`, `TAG_`.
    *   **Definition sites**: COMMANDS.md headings (`¶CMD_X`), CMD_*.md headings (`¶CMD_X`), INVARIANTS.md entries (`¶INV_X`), AGENTS.md entries (`¶INV_X`), CONTRIBUTING.md entries (`¶INV_X`), SIGILS.md section headers (`¶FEED_X`, `¶TAG_X`), any file's inline invariant definitions (`¶INV_X`).
    *   **Reference sites**: SKILL.md steps arrays (`§CMD_X`), body text cross-references (`§CMD_Y`, `§INV_Y`), PROOF FOR headings (`§CMD_X`), docs/ (`§INV_X`, `§CMD_X`).
    *   **Governance**: Any file may define an invariant using `¶INV_X`. Only COMMANDS.md and CMD_*.md may define commands using `¶CMD_X`.
    *   **Redirection**: If you're about to write a sigiled noun, ask: "Am I defining it here, or referring to it?" `¶` = defining, `§` = referring.
    *   **Reason**: Without semantic sigils, readers cannot distinguish "this is defined here" from "this is defined elsewhere." The convention enables grep-based discovery: `grep '¶CMD_'` finds all definition sites; `grep '§CMD_'` finds all usage sites.

*   **¶INV_EPIC_SLUG_SIGIL**: Epic and chapter references use the `@` sigil prefix. Full definition in SIGILS.md § `@` — Epic and Chapter Slugs.

## 12. Formatting

*   **¶INV_LISTS_INSTEAD_OF_TABLES**: Markdown tables are prohibited in all project `.md` files and agent chat output.
    *   **Rule**: Do NOT use markdown tables (`| col | col |`) in any file — directives, SKILL.md files, docs, templates, session artifacts, or chat messages.
    *   **Redirection**: Use `§FMT_LIGHT_LIST`, `§FMT_MEDIUM_LIST`, or `§FMT_HEAVY_LIST` instead. Choose the density level that matches the number of fields per item. See SIGILS.md § Formatting Conventions for definitions and examples.
    *   **Heuristic**: 1-2 fields → `§FMT_LIGHT_LIST`. 3-4 fields → `§FMT_MEDIUM_LIST`. 5+ fields → `§FMT_HEAVY_LIST`.
    *   **Scope**: All `.md` files in the project AND all agent chat output. No exceptions.
    *   **Reason**: Tables break at narrow terminal widths, are hard to edit incrementally, and resist diffing. Lists are readable at any width, trivially editable, and diff cleanly.

*   **¶INV_CAMELCASE_FOR_DATA**: All JSON data the engine reads or writes MUST use camelCase property names.
    *   **Rule**: Property names in JSON schemas, `.state.json` fields, proof schemas, session parameters, dehydration payloads, and hook configs must be camelCase (`sessionDir`, `parametersParsed`, `logEntries`).
    *   **Prohibited**: snake_case (`session_dir`, `parameters_parsed`), kebab-case, or any other casing convention for JSON property names.
    *   **Scope**: All engine JSON — proof schemas in CMD `## PROOF FOR` sections, SKILL.md `proof` arrays, `§CMD_PARSE_PARAMETERS` schema, `§CMD_DEHYDRATE` schema, `.state.json` internal fields.
    *   **Redirection**: When constructing JSON for engine consumption, scan the target schema's `properties` for the canonical camelCase names. Never invent snake_case equivalents.
    *   **Reason**: Session parameters and dehydration data already use camelCase. Proof schemas were added later and used snake_case, creating an inconsistency that causes validation confusion.

## 13. Tmux / Fleet

*   **¶INV_NO_FOCUS_CHANGE_IN_NOTIFY**: Notification commands MUST NOT change the focused pane.
    *   **Rule**: When applying visual state (background color) to a non-focused pane, use the atomic compound command `select-pane -t "$pane" -P "bg=$color" \; select-pane -t "$active"` — this sets style AND restores focus in one tmux server round-trip (no race window). For the focused pane, skip style entirely (avoid flash/distraction).
    *   **Prohibited**: (1) `set-option -p -t style "bg=..."` — INVALID in tmux 3.6a, "style" is not a recognized pane option. (2) `select-pane -t "$pane" -P "bg=$color"` without focus restoration — creates a focus-theft race.
    *   **Reason**: Multiple agents call `fleet.sh notify` concurrently. The atomic compound command eliminates the race window. Skipping focused pane style prevents visual flashing.

*   **¶INV_FLEET_GRACEFUL_OUTSIDE_TMUX**: Fleet commands MUST be no-ops outside tmux.
    *   **Rule**: All tmux calls in fleet.sh and session.sh fleet paths must use `2>/dev/null || true`. Missing `$TMUX` or `$TMUX_PANE` means "not in fleet" — exit silently, don't error.
    *   **Cross-ref**: See also `§INV_TMUX_AND_FLEET_OPTIONAL` in AGENTS.md.

*   **¶INV_SILENT_FAILURE_AUDIT**: Shell commands guarded by `|| true` must be audited for correctness.
    *   **Rule**: When adding `|| true` to a command, verify that the command actually works as expected. Silent failure masking can hide regressions that persist for multiple sessions before being discovered.
    *   **Pattern**: After adding `|| true`, run the command without `|| true` at least once to confirm it succeeds. If it fails, investigate — don't just silence it.
    *   **Reason**: The style regression in fleet.sh was silently broken by `|| true` for an entire session cycle. The command was INVALID in tmux 3.6a but the error was invisible.

*   **¶INV_SUPPRESS_HOOKS_FOR_PROGRAMMATIC_STYLE**: Programmatic style changes via `select-pane -P` MUST suppress the `after-select-pane` hook using `@suppress_focus_hook`.
    *   **Rule**: Any code that calls `select-pane -P` for styling purposes must wrap it in `set -g @suppress_focus_hook 1 \; select-pane -P ... \; set -g @suppress_focus_hook 0`. The hook checks `@suppress_focus_hook` at the top and exits early if set to 1.
    *   **Reason**: Without suppression, `select-pane -P` triggers the focus hook, which calls `select-pane -P` again, creating a rendering cascade that causes visible pane flashing.

*   **¶INV_SKIP_REDUNDANT_STYLE_APPLY**: Visual style updates MUST be skipped when the target state hasn't changed.
    *   **Rule**: Before calling `select-pane -P`, read the current `@pane_notify` value. If it matches the requested state, skip the visual update. Data layer (`@pane_notify` set-option) still updates every time — only the visual `select-pane -P` is skipped.
    *   **Reason**: Redundant `select-pane -P` calls cause unnecessary tmux redraws and visible flashing.

*   **¶INV_HOOKS_NOOP_WHEN_IDLE**: Hooks MUST be no-ops when there is nothing to do.
    *   **Rule**: If a hook has no work to perform (e.g., no session active, no fleet pane, no applicable condition), it must exit 0 immediately. No logging, no side effects, no errors.
    *   **Reason**: Hooks fire on every tool call. Unnecessary work or errors in idle hooks degrade the entire agent experience.

## 14. Synthesis Pipeline Physics

*   **¶INV_SKIP_ON_EMPTY**: Pipeline steps that find nothing MUST skip silently — no halt, no user prompt.
    *   **Rule**: When a synthesis pipeline step (e.g., `§CMD_CAPTURE_SIDE_DISCOVERIES`, `§CMD_DISPATCH_APPROVAL`, `§CMD_RESOLVE_CROSS_SESSION_TAGS`) scans and finds zero items, it MUST NOT halt execution or prompt the user. Skip and return control to the orchestrator.
    *   **Redirection**: Instead of prompting "No items found — proceed?", just echo the scan scope (per `¶INV_ECHO_ON_SKIP`) and continue.
    *   **Reason**: Empty scans are the common case. Halting on every empty scan creates unnecessary round-trips in a pipeline that may have 8+ steps.

*   **¶INV_ECHO_ON_SKIP**: Every synthesis pipeline step MUST echo its scan scope to chat, even when nothing is found.
    *   **Rule**: When a pipeline step runs and finds zero results, it MUST still output a one-line summary of what it scanned and that nothing was found. Example: "Side discoveries: scanned IMPLEMENTATION_LOG.md — none found."
    *   **Reason**: Silent skips make the pipeline opaque. The user cannot tell if a step ran and found nothing vs. was accidentally skipped. Echo-on-skip provides an audit trail in the chat.

*   **¶INV_IDEMPOTENT_STEPS**: Pipeline steps MUST be safe to re-run without side effects.
    *   **Rule**: Every synthesis pipeline step must check existing state before acting. If a debrief already exists, don't create a duplicate. If tags are already swapped, don't swap again. If backlinks are already written, don't double-write.
    *   **Reason**: Context overflow can interrupt synthesis mid-pipeline. The rehydrated agent resumes at the saved sub-phase and re-runs steps. Non-idempotent steps would corrupt artifacts on re-run.

*   **¶INV_BATCH_SIZE_4**: `AskUserQuestion` batches are fixed at 4 items per call.
    *   **Rule**: When presenting multiple items for user decision (dispatch approval, tag triage, walkthrough items), batch them in groups of 4. The last batch gets the remainder (1-3 items). This matches `AskUserQuestion`'s maximum of 4 questions per call.
    *   **Reason**: Consistent batch sizing across all pipeline steps. The tool's 4-question limit is the natural batch boundary.

*   **¶INV_FOLLOWUP_ON_DEMAND**: Follow-up questions only when the user's selection requires additional input.
    *   **Rule**: After an `AskUserQuestion` response, only ask a follow-up if the selected option requires additional information to execute (e.g., "Claim for next skill" needs state passing, "Split item" needs sub-item definitions). Do not ask confirmations, summaries, or "anything else?" after each batch.
    *   **Reason**: Minimizes round-trips. The user chose an option — execute it. Only re-engage when genuinely blocked on missing input.
