### ¶CMD_READ_PROJECT_HANDBOOK
**Definition**: The ONE canonical READ-ONLY path for reading a Linear Project's **Inbox Handbook** — the per-project document where that project's intake machinery lives once (`¶INV_CHANNEL_MACHINERY_IN_ONE_DOC`). Given a project, or enough context to resolve one, it resolves the handbook **by doc id**, fetches it **fresh**, and returns the sections a caller steers on: `## Ticketing Strategy`, `## Boundaries`, the channel set, and `## What triage will chase`.
**Rule**: Any skill or agent about to **file into, route into, or compose a write against a project whose handbook it is not already holding** routes the read through here — never a hand-rolled document fetch, never a remembered copy from earlier in the session. A seat filing into another project obeys THAT project's lines, not the habits of the project it happens to be working in. **Current callers: `/ticket` (§1, applied at its Subject Gate), `/inbox-post` (routing + its ticket offer) and `/loom` (before any composed tracker write). `/intake`, `/triage` and `/inbox-handbook` still hand-roll their own handbook read and should be converted** — the convergence is started, not finished; do not read this file as evidence that it is done. See `¶INV_TICKETING_STRATEGY_IN_HANDBOOK` and `¶INV_BOUNDARIES_ARE_WRITTEN_DOWN`.
**Constraint**: **READ-ONLY against Linear.** This atom never creates, edits or comments on anything in the tracker. Its one write is **local**: repairing a stale or missing row in the registry cache (step 2), which is a cache repair, not a mutation of the record. Writing the handbook itself belongs to `/intake` (creation) and `/inbox-handbook` (capture).

**Prerequisites**:
*   **Linear MCP present.** Headless / no-MCP → cannot read; report the skipped read in one line and **fall back to the caller's existing behaviour**, never hang and never block the caller's work.
*   **Deferred tools loaded**: `ToolSearch` `select:mcp__linear__list_documents,mcp__linear__get_document,mcp__linear__list_projects` before the first call. *The `mcp__linear__` prefix is the standard server name, not a guarantee — if the available tool list carries a different one, resolve the same tool names from it.* Both halves matter: the selector is what actually loads the schemas (a bare `select:get_document` resolves nothing), and the note is what keeps the atom correct on a machine that mounts the server under another name.
*   **No session required**: a pure read, identical with or without an active engine session.

**Parameters**:
```json
{
  "project": "OPTIONAL — the project NAME or id the handbook belongs to. Omitted → resolved per step 1.",
  "want": "OPTIONAL array of the parts the caller needs — any of 'ticketing-strategy' | 'boundaries' | 'channels' | 'repo-destinations' | 'what-triage-will-chase'. Omitted → all of them.",
  "ask": "OPTIONAL boolean, default false. true lets step 1 prompt the user when the project will not resolve; false degrades silently instead. Pass true only when the project is load-bearing for the caller."
}
```

**Algorithm**:
1.  **Resolve the project**, first match wins: an **explicit `project` argument** → the **active `/intake` session's** project (from its `INTAKE.md`) → the **working context** (the project the target ticket sits on, the caller-pinned placement, the repo's `## Tracker` config). **If none of those resolve, do NOT ask** — go straight to step 5 and degrade, because a caller that could not name a project is a caller that did not need one, and an unconditional prompt at the top of every run is the blocking this atom exists to avoid. **Ask only when the caller passed `ask: true`**, which a caller does when the project is genuinely load-bearing for it. Resolve the project before resolving the document; a handbook matched without a project is a handbook matched by hope.
2.  **Resolve the handbook — one filtered call, verified live.** `list_documents({ projectId, query: "Inbox Handbook", fields: ["id","title","url","updatedAt","project"] })` returns the project's handbook deterministically, because every project's copy carries the identical title and `projectId` scopes the search to the one project. The same response satisfies step 3's freshness and project-identity checks, so **no second call is needed to read `## Ticketing Strategy` metadata** — only the content fetch below.
    *   **Fallback, when that call cannot run or comes back empty**: resolve the doc id from `~/.claude/engine/skills/inbox-post/assets/INBOX_REGISTRY.md` § *The handbook*, **cross-checking the 12-hex `slugId`**. **Never parse the human-readable words of the URL** — retitling a Linear document re-slugs that segment while the slugId stays put. On a registry miss too, widen to `list_projects(includeMilestones: true)` client-filtered to projects carrying an `Inboxes` milestone, then **self-heal the registry row**. The registry is a cache; Linear is the source of truth.
    *   *The filtered call makes the registry/slugId/self-heal apparatus a fallback rather than the path. It is kept deliberately — it still serves the no-MCP and empty-result cases — but a later pass may find it removable.*
3.  **Fetch the content fresh, immediately before use.** `get_document(id)` at the point of need — **never a cached read from earlier in the session**, and never a copy carried forward in a handoff prompt as though it were current. **Check `updatedAt`**: Linear has been observed serving a stale document *with a stale timestamp*, so an earlier read in the same session can silently predate an edit that already landed. **Verify the fetched document's `project.name` matches the project resolved in step 1** and record the result — a stale registry row must never hand back another project's lines.
    *   **The Project-description fallback.** On a project predating the move to the handbook, `## Ticketing Strategy` may still sit on the **Project description** rather than in the document. When the handbook carries no such section, read the Project description before concluding the project published none, and record which surface supplied it. Callers used to carry this fallback individually; it lives here now so one project's lines read the same from every seat.
4.  **Return the parts the caller needs**, derived from the document's own headings rather than a remembered section list (the set drifts — do not hardcode a count):
    *   **`## Ticketing Strategy`** — the three independently-dialable bullets (**Volume** how many tickets the project wants at all · **Size** how big one should be · **Substance** what makes one worth existing), plus whatever that project adds (an out-of-scope line, a "ripe here" bar). One per project: **no channel override and no precedence chain**, because how many tickets a project wants is a property of the project, not of the firehose an item arrived through. Return it **verbatim** — a caller's sub-agent cannot read Linear and gets only what this atom hands it.
    *   **`## Boundaries`** — one entry per neighbouring project, each with the split **and the one-line test** that decides a borderline item. The test is the load-bearing half; the prose list does not enumerate the cases that actually arrive.
    *   **The channel set** — the project's actual inbox channels, resolved from the registry row or discovery. Never assume a channel exists because the standard set lists it, and never assume one is absent because the standard set omits it. **Report the presence or absence of a 🛠️ Tooling & Gates channel explicitly**, since a caller redirecting a refused subject needs to know whether the destination is real before it names it.
    *   **The repo destinations** — where a tooling or gate item's RESOLUTION lands in this project's repository. These are **per-project and live in the project's own surfaces** — the 🛠️ channel ticket's `## Directions`, else the handbook — never in a skill, because a path that exists in one repository does not exist in the next one a global skill runs in. Return them as the project wrote them; a caller names what this returns and invents nothing when it returns nothing.
    *   **`## What triage will chase`** — this project's own recipe, naming this project's actual tools. **Never reuse another project's**; that section is the entire reason the handbook is per-project.
5.  **Degrade gracefully, in one line.** No handbook, no `## Ticketing Strategy`, or no MCP → say which is missing — *"no Ticketing Strategy published for `<project>`; falling back to `<the caller's own default>`"* — and hand control back. **Never block a filing, a routing decision or a write on a missing handbook.** Absence is a normal state and must be **visible**, never silent: a defaulted caller says it defaulted.

**Constraints**:
*   **The caller keeps its own floor.** This atom returns a project's lines; it does not replace the caller's own rules. A caller with a subject gate, an allowlist or a confirm still runs it — the handbook is *additional* to that floor, and a project that publishes nothing leaves the floor standing alone.
*   **Never editorialize in the return.** Hand back the sections as written. The caller owns the verdict — whether to file, where to route, whether to fold — exactly as `§CMD_READ_RELATED_TICKET` hands back facts and lets the caller classify.
*   **Fresh at the point of need, not once at boot.** A caller that holds the handbook across a long session re-reads before it acts on it. `/intake` is the one caller that deliberately loads once per wave and holds it (one fetch replaces N copies within a wave); every other caller fetches at the step that uses it.
*   **Single source of the resolution shape, and it is not yet single.** `/ticket`, `/inbox-post` and `/loom` cite this atom; `/intake`, `/triage` and `/inbox-handbook` still hand-roll the same resolution and are the remaining conversion work. A caller must not hand-roll its own subset, or the resolution drifts and a renamed handbook goes missing on one site while working on the others.
*   **Never copy the registry into a caller's own assets.** A second cache of the same project identity is the duplication problem one level down. *Noted inversion: the registry this atom reads currently lives in `/inbox-post`'s asset directory, so an engine-level directive depends on one skill's private assets. If the registry stays canonical it should move up to the engine; the filtered-call path in step 2 may instead make it unnecessary.*
*   **Destinations are the project's, never the skill's.** Where a tooling item's resolution lands is a fact about one repository. This atom returns what the project published and a caller names that; **no skill hardcodes a repository path**, because a global skill runs in repositories that have never heard of it.

---

## PROOF FOR §CMD_READ_PROJECT_HANDBOOK

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "project": {
      "type": "string",
      "description": "The project the handbook was resolved for, and how it was resolved (e.g. 'Product: Idea — from the caller-pinned placement')"
    },
    "handbookRead": {
      "type": "string",
      "description": "The doc id + slugId fetched with its updatedAt (e.g. '0a1b… · 3f9c2d4e61b0 · updated 2026-10-18'), or 'skipped — <reason>' (no handbook published / no Linear MCP / registry miss and discovery found none)"
    },
    "resolution": {
      "type": "string",
      "enum": ["filtered-call", "registry-hit", "discovery-fallback", "discovery-fallback-self-heal-failed", "not-found", "not-attempted"],
      "description": "Which path resolved the doc id. 'not-attempted' is the no-MCP / no-project case where nothing was looked up — distinct from 'not-found', which claims we looked. 'discovery-fallback' implies the registry row was rewritten; the -self-heal-failed variant means the doc was found but the cache write did not land"
    },
    "projectVerified": {
      "type": "boolean",
      "description": "Whether the fetched document's project.name was confirmed to match the project resolved in step 1 — the one safety check standing between a stale registry row and another project's lines. False on any path that could not run it"
    },
    "strategySource": {
      "type": "string",
      "enum": ["handbook", "project-description", "none"],
      "description": "Which surface supplied the Ticketing Strategy; 'project-description' records the pre-move fallback having fired"
    },
    "sectionsReturned": {
      "type": "array",
      "items": {
        "type": "string",
        "enum": ["ticketing-strategy", "boundaries", "channels", "repo-destinations", "what-triage-will-chase"]
      },
      "description": "The parts actually found and handed back — one the handbook does not carry is absent here, never fabricated. The enum closes the same set `want` does; a heading outside it is read but not reported through this field"
    },
    "toolingChannel": {
      "type": "string",
      "description": "The 🛠️ Tooling & Gates channel's key if the project has one, or 'absent' — a caller redirecting a refused subject reads this before naming the destination"
    },
    "fallbackApplied": {
      "type": "string",
      "description": "The one-line degradation notice given to the caller, or 'none — handbook read in full'"
    }
  },
  "required": ["project", "handbookRead", "resolution", "projectVerified", "strategySource", "sectionsReturned", "toolingChannel", "fallbackApplied"],
  "additionalProperties": false
}
```
