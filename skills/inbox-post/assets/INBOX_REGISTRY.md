# Inbox Registry — intake projects → channels → tickets

Fast-path navigation map for `/inbox-post`. Project → its `Inboxes` channel tickets (ENG-key + URL). A **cache**, not the source of truth — Linear is. When it's stale or missing a target, the skill falls back to live discovery (`list_projects(includeMilestones)` → client-filter `Inboxes`; channel tickets by title) and self-heals this file.

**Issue status:** every ticket under an `Inboxes` milestone — the channels and anything parked there to gather input — sits on the **`Inboxes` issue status**, not `Backlog` (`§INV_INBOX_STATUS_NOT_BACKLOG`). Record the status id for your team here once it exists; its type is `backlog`. Scaffold a new channel straight onto it: `save_issue(state: "Inboxes", …)`. The type is unchanged, so ranking and cycle exclusion behave as before; only the Backlog view stops carrying collectors. To audit, filter on `projectMilestone.name == "Inboxes" AND state.type == "backlog"` — that finds channels this cache has never heard of, which a per-project walk from these rows would miss.

*Channels:* 🔴 Observed problems · 🟠 Identified shortcomings · 🔵 Feature requirements · 🟢 Potential solutions · 🟣 Feedback & Transcripts · 🟤 Priorities & Deadlines · 🟡 Researches & Fixtures · 🟦 Documentation · 🟪 Inquiries · 📣 Announcements · 🟩 Chores & tracker hygiene · 🛠️ Tooling & Gates · ⚖️ Legal and counsel questions · 🤝 Partner signal

Not a fixed set in practice — channel titles vary slightly per project (Claims & Policies uses "Feature **& capability** requirements"). Match by intent, not by exact title. **The discovery fallback filters issue titles by these emojis — extend that list whenever a channel is added, or the new one is invisible to discovery.** **Two of the glyphs are project-specific, not shared**: ⚖️ Legal and counsel questions and 🤝 Partner signal exist only on *Product: Claims Data Consortium*, whose subject makes them real channels rather than a convenience — a question needing a lawyer, and a thing a named partner said, have no honest home in the standard set. Discovery must still know them or that project loses two channels. *(The `Inbox: <what>` naming that project used until 2026-08-26 is **retired** — its four channels were renamed to the emoji convention. If you find a channel still titled `Inbox: …`, it is a project the standardisation missed.)* Squares twin circles by design (🟦 with 🔵, 🟩 with 🟢, 🟪 with 🟣): every color was already taken by a circle, so a twin is the convention rather than a collision. 🟪 twins 🟣 because both are raw human voice arriving unprocessed — 🟣 is what someone **said**, 🟪 is what someone **asked**.

**🟪 Inquiries is universal by nature, and a deliberate exception to how every other channel is chosen.** The others earn their place per project — an empty one is a cost, not a completeness win — so a project's set is decided, never defaulted. Inquiries is different because **any project can be asked a question**, including one with nothing shipped and nothing yet to observe: not knowing is the whole content, so it cannot sit empty for want of subject matter. It was created on **all twelve** intake projects on 2026-08-25 (decided: Yarik Fedin) rather than seeded on one and replicated as it earned its way. A project scaffolding an inbox from here on gets it in the initial set.

**🛠️ Tooling & Gates is opt-in per project, and its absence is a ruling rather than a gap.** It exists on *Product: Idea* ([IDE-126](https://linear.app/idealic/issue/IDE-126/tooling-and-gates)); Overseer has ruled **against** creating it on *Market & Jobs* and *Worlds & Branches*. So **a project without one is the normal case** — `/inbox-post` has a missing-channel branch for exactly that, and a tooling item must not be bent into a defect channel instead. It is also the one channel that **never graduates to a ticket**: it reports, and the repository resolves, at destinations the channel's own `## Directions` name per project (they are repository-specific, so no skill hardcodes them).

**Two of them are not inbound signals**, and a pass should treat them differently:

*   **📣 Announcements** runs **outbound** — news leaving the system, not a signal entering it. It does **not** normally graduate to a ticket. It is triaged for one purpose: **verification** that the announced thing is actually deployed *and wired*. An announcement that shipped and that nothing consumes is a real finding, and routes to whichever channel fits it.
*   **🟩 Chores & tracker hygiene** is about **the record, not the product** — a stale title, an obsolete description, two tickets that are one thing. Its work batches (one stale title isn't worth a pass; twenty are one sweep) and routes to `/chores`. Its load-bearing rule: **chase what a query cannot find** — un-triaged / unassigned / no-priority / stale counts are already measured, so a drop that restates them is waste; a drop about *meaning* is not.

## The handbook

Every channel is **thin**: it says what belongs in it, links **its own project's** handbook, and (where it has one) carries its own `## Directions`. The report template, what-happens-next, and the correction policy live in the handbook — not in the channels.

Each intake project carries its **own complete copy**, attached to the project so it appears in that project's sidebar. All titled `Inbox Handbook — how this project's intake inboxes work`. There is **no inheritance and no parent document**: the shared sections are kept in sync by hand, and `## What triage will chase` is deliberately different in each one (it names that project's actual tools — its database, its analytics, its source documents).

| Project | Handbook | doc id · slugId |
|---|---|---|
| Example | [Inbox Handbook](https://linear.app/acme/document/inbox-handbook-how-this-projects-intake-inboxes-work-000000000000) | `00000000-0000-4000-8000-000000000000` · `000000000000` |
| Product: Idea | [Inbox Handbook](https://linear.app/idealic/document/inbox-handbook-how-this-projects-intake-inboxes-work-d0af553e772b) | `cd6df668-3156-4293-98c9-adf09f82a587` · `d0af553e772b` |
| Product: Handbook | [Inbox Handbook](https://linear.app/idealic/document/inbox-handbook-how-this-projects-intake-inboxes-work-1cef23ee882a) | `941dc575-d981-4c65-963d-087fdabddf99` · `1cef23ee882a` |
| Product: Stats | [Inbox Handbook](https://linear.app/idealic/document/inbox-handbook-how-this-projects-intake-inboxes-work-0d867505073a) | `a4ad13b9-a462-49bf-8d22-36ddb7eee108` · `0d867505073a` |

**A filtered call resolves a handbook without this table.** `list_documents({ projectId, query: "Inbox Handbook", fields: ["id","title","url","updatedAt","project"] })` returns the one document deterministically — verified live — because every project's copy carries the identical title and `projectId` scopes the search. `§CMD_READ_PROJECT_HANDBOOK` tries that first and falls back to these rows, so the table is a cache for the no-MCP and empty-result cases rather than the path.

Match a handbook by **slugId**, not by the words in the URL: retitling a Linear document re-slugs the human-readable segment while the 12-hex slugId stays put.

## Slack announce channels

The wave's `§PASS_HEARTBEAT` announce is **per-project** — pass the name below as `engine slack-post --channel '#name'`. Do **not** leave the announce to `$SLACK_INTAKE_CHANNEL`: it is a single global var, so relying on it makes every project post to the same place.

*   **Example** — **UNSET**
*   **Product: Stats** — **UNSET** (no bot token configured at scaffold time either — `engine env doctor --domain intake` failed on `SLACK_INTAKE_TOKEN`, so the transport is deaf rather than merely unrouted)

A project whose row is **UNSET** has no announce destination yet; ask rather than guess, because a guess silently sends a heartbeat somewhere nobody watches.

**Names, never ids.** `slack-post` resolves a name to the id Slack's API requires and keeps the id internal — no channel id belongs in config or in anything a human reads. The tradeoff is that a **rename breaks the row**: resolution fails loudly rather than posting somewhere stale.

Verify a project's Slack setup before its first announce: `engine slack-post --verify --channel '#name'` checks token, scopes, channel and bot membership, and self-joins when `channels:join` is granted.

## Initiatives — the domain a project belongs to

A wave can attach a project to an initiative it is given by name — `save_project(addInitiatives: ["Platform"])` — and comment on, document, or post status updates against one. Membership is read live — `list_initiatives`, then `get_initiative(includeProjects: true)` — so it is never kept here. What a wave cannot do is decide the cut, so record the decision and its owner here once someone makes it:

| Initiative | Owner | Decision |
|---|---|---|
| _none yet, for Product: Stats_ | manager:director | One initiative per manager is the intended cut (operator, 2026-10-28), not yet created. **A wave never creates one because the authority grant reserves it to the operator** — the grant's classes went up for their tick on [IDE-238](https://linear.app/idealic/issue/IDE-238). ⚠️ **Corrected 2026-10-29**: this row previously said the MCP was attach-only with no `save_initiative`. That was false and was relayed from `intake/SKILL.md` rather than measured — `list_initiatives`, `get_initiative` and `save_initiative` all load, and `save_initiative` creates. The policy is unchanged; only its reason was wrong, and a capability claim owed evidence it did not have. `Product: Stats` stays unattached until the cut is settled, which is a normal state. |

**Why an initiative rather than a saved view**: a view is a *filter*, and a domain is not filterable — no field on a Linear project says "this is a Platform concern". An initiative is a **curated** set, which is exactly the shape of a judgement call.

## Product: Stats
- **Project id**: `2676866f-52f0-48a2-9aa7-8696f8a51fd7` (`P-IDE-13`) · **Inboxes milestone**: `154fb314-b34b-47ee-9564-db48a21feba8`
- 📊 Measure requests — [IDE-248](https://linear.app/idealic/issue/IDE-248/measure-requests)
- 🔴 Observed problems — [IDE-249](https://linear.app/idealic/issue/IDE-249/observed-problems)
- 🛠️ Tooling & Gates — [IDE-250](https://linear.app/idealic/issue/IDE-250/tooling-and-gates)
- 🟦 Documentation — [IDE-251](https://linear.app/idealic/issue/IDE-251/documentation)

*Four channels rather than the default set: this project's own 📊 Measure requests is the one it has and others do not, and the four were the operator's choice at scaffold time. **All four sit on `Backlog`, not on an `Inboxes` status** — team Idealic has no such status and it cannot be created through the API; the sibling channel IDE-126 in Product: Idea has the same gap, so the repair is one workflow state added in team settings, then the channels moved.*

## Product: Example
- **Project id**: `00000000-0000-4000-8000-000000000001` · **Inboxes milestone**: `00000000-0000-4000-8000-000000000002`
- 🔴 Observed problems — [ENG-1001](https://linear.app/acme/issue/ENG-1001)
- 🟠 Identified shortcomings — [ENG-1002](https://linear.app/acme/issue/ENG-1002)
- 🔵 Feature requirements — [ENG-1003](https://linear.app/acme/issue/ENG-1003)
- 🟢 Potential solutions — [ENG-1004](https://linear.app/acme/issue/ENG-1004)
- 🟣 Feedback & Transcripts — [ENG-1005](https://linear.app/acme/issue/ENG-1005)
- 🟪 Inquiries — [ENG-1006](https://linear.app/acme/issue/ENG-1006)

*A placeholder showing the row shape. Replace it with your intake projects as `/intake` scaffolds them; until then `/inbox-post` falls back to live discovery.*
