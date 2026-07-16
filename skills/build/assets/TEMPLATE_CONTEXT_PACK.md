# Context Pack — <CHUNK / TASK>
*The orchestrator (`/build`) fills this, WRITES it to `<trailDir>/<CHUNK>_CONTEXT_PACK.md`, then composes the same content into the builder sub-agent's self-contained prompt. Every field is load-bearing.*
*Engine-optional: under a session, sources are `DIALOGUE.md`, the plan, the log, and `<trailDir> = <sessionDir>/builds/`. In standalone mode (no engine), draw every field from the conversation and `<trailDir>` is the global `/tmp` trail.*

## Goal
<1–3 sentences: what is the ultimate purpose of this build?>

## What was asked (verbatim)
> <the user's exact request(s) from `DIALOGUE.md`. Do NOT paraphrase; exact wording often carries implicit constraints.>

## Plan slice
<this chunk's specific detail from the plan file; include a link to the full plan for reference>

## Session history (do not re-derive / undo)
<a digest of prior chunks from the session log: what's done, what's committed vs. uncommitted, and what invariants/decisions are already locked in>

## The whys / decisions already made
<relevant decisions + rationale from `DIALOGUE.md` / log — why approach A over B, constraints the user set.
*Directive to the agent:* you must honor these decisions; do not attempt to "fix" or override them.>

## Carried-forward lessons
<distilled facts + rulings from `<trailDir>/LESSONS.md` and prior Build Reports' `reusableFacts` that this chunk needs. This is the compounding memory of the system.
*(Illustrative — adapt, don't copy:
- "type is prefix-authoritative"
- "the path engine never lands a table on a subroom path"
- "the FIN-2802 red test is not ours; ignore it")*
Omit only if genuinely none apply.>

## Reference art (prior art / templates)
<name a specific file, function, or PR that serves as a structural template for this work. A "mirror this reference implementation" pointer beats paragraphs of prose.
*(Illustrative — adapt, don't copy: "mirror the error-handling pattern in `src/auth/jwt.ts`.")*
Omit if this is entirely novel work.>

## In scope (only these)
<the authoritative list of files or directories the agent may change>

## Out of scope (do NOT touch)
<explicit boundaries: other chunks, unrelated working-tree changes, specific files/dirs, and explicitly "no commit">

## Likely traps (pre-empt the predictable mistakes)
<the specific wrong turns THIS task invites, stated as "you'll be tempted to X — don't, because Y". Negative guidance beats happy-path prose.
*(Illustrative — adapt, don't copy:
- "you'll want to keep the type-flip as defense-in-depth — don't, type is prefix-authoritative"
- "you'll want to `git add -u` — don't, the tree has parallel-agent work")*>

## Parity oracle (for behavior-preserving work)
<if the goal is behavior-preserving (e.g. refactoring): name the test(s) that ARE the behavior contract.
*(Illustrative — adapt, don't copy: "suite X is the oracle — it must stay green unmodified.")*
If useful, provide a before/after output for one fixture the agent can diff against. Omit for greenfield work.>

## Hard gates (must all pass)
<build/test/lint/type-check commands + machine-checkable pass criteria.
*(Illustrative — adapt, don't copy:
- `tsc --noEmit` (must exit 0)
- `yarn workspace X test` (all green)
- `cast count == N`)*>

## Return contract
Write a Build Report to `<trailDir>/<CHUNK>_BUILD.md` using `TEMPLATE_BUILD_REPORT.md` (fill every field). Return a 4–6 line summary + the report path.
