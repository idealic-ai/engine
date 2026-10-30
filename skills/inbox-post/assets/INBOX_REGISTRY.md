# Inbox Registry — intake projects → channels → tickets

Fast-path navigation map for `/inbox-post`. Project → its `Inboxes` channel tickets (ENG-key + URL). A **cache**, not the source of truth — Linear is. When it's stale or missing a target, the skill falls back to live discovery (`list_projects(includeMilestones)` → client-filter `Inboxes`; channel tickets by title) and self-heals this file.

**Issue status:** every ticket under an `Inboxes` milestone — the channels and anything parked there to gather input — sits on the **`Inboxes` issue status**, not `Backlog` (`§INV_INBOX_STATUS_NOT_BACKLOG`). Record the status id for your team here once it exists; its type is `backlog`. Team Idealic: `52f37197-541b-4053-ad65-fa14356cdb2f`. Scaffold a new channel straight onto it: `save_issue(state: "Inboxes", …)`. The type is unchanged, so ranking and cycle exclusion behave as before; only the Backlog view stops carrying collectors. To audit, filter on `projectMilestone.name == "Inboxes" AND state.type == "backlog"` — that finds channels this cache has never heard of, which a per-project walk from these rows would miss.

*Channels:* 🔴 Observed problems · 🟠 Identified shortcomings · 🔵 Feature requirements · 🟢 Potential solutions · 🟣 Feedback & Transcripts · 🟤 Priorities & Deadlines · 🟡 Researches & Fixtures · 🟦 Documentation · 🟪 Inquiries · 📣 Announcements · 🟩 Chores & tracker hygiene · 🛠️ Tooling & Gates · ⚖️ Legal and counsel questions · 🤝 Partner signal · 📊 Measure requests (Product: Stats only)

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
| Product: Deploy | [Inbox Handbook](https://linear.app/idealic/document/inbox-handbook-how-this-projects-intake-inboxes-work-c498df89472d) | `a6f5098f-4827-4053-b1a4-9e000a9154ce` · `c498df89472d` |
| Product: Writer | [Inbox Handbook](https://linear.app/idealic/document/inbox-handbook-how-this-projects-intake-inboxes-work-68121d233e0e) | `7715150a-7ed8-4458-9e85-e2b18cf5467a` · `68121d233e0e` |
| Product: Playground | [Inbox Handbook](https://linear.app/idealic/document/inbox-handbook-how-this-projects-intake-inboxes-work-4ce0c5ff2dfc) | `91ac23b5-a42e-4a41-890f-3fa8ccbaac3c` · `4ce0c5ff2dfc` |
| Product: Ideas site | [Inbox Handbook](https://linear.app/idealic/document/inbox-handbook-how-this-projects-intake-inboxes-work-77c40cb0e4fb) | `04a1a8e3-1b89-412f-aa3a-12523a32cdda` · `77c40cb0e4fb` |
| Product: Orchestration | [Inbox Handbook](https://linear.app/idealic/document/inbox-handbook-how-orchestration-intake-inboxes-work-1ff5597c997b) | `83a9a7d7-fecf-4135-b47b-75514e9f3b6e` · `1ff5597c997b` |
| Product: Market & Jobs | [Inbox Handbook](https://linear.app/idealic/document/inbox-handbook-how-market-and-jobs-intake-inboxes-work-4b8c10a1ebe7) | `163b1b3d-74e0-4f14-a169-ad448c295c60` · `4b8c10a1ebe7` |

**A row's project id alone resolves the project.** A caller that needs only the project (`/snapshot --yes` filing un-ticketed work, for one) takes the **Project id** from the project's section below and needs nothing else here. A project with no handbook document — Product: Realm's case, or any section reading *No inbox handbook yet* — still resolves; the missing handbook only means no handbook rules apply.

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
| Idealic kernel & runtime (I-2) · Apps (I-3) · Domain platform (I-4) · Docs & handbook (I-5) | manager:director | One initiative per manager (manager:idealic, manager:app, manager:domain, manager:docs), the operator's cut of 2026-10-28. All four exist in Linear, created 2026-10-28 16:20–16:21 UTC. Which project goes under which is the operator's to rule (ask `manager:director/initproj-map`), so no project is attached to any of them yet, `Product: Stats` included; that is a normal state. **A wave never creates or re-cuts an initiative, because the authority grant reserves that to the operator** — the grant's classes went up for their tick on [IDE-238](https://linear.app/idealic/issue/IDE-238). The reason is the grant and not a missing tool: `list_initiatives`, `get_initiative` and `save_initiative` all load, and `save_initiative` creates. |

**Why an initiative rather than a saved view**: a view is a *filter*, and a domain is not filterable — no field on a Linear project says "this is a Platform concern". An initiative is a **curated** set, which is exactly the shape of a judgement call.

## Product: Stats
- **Project id**: `2676866f-52f0-48a2-9aa7-8696f8a51fd7` (`P-IDE-13`) · **Inboxes milestone**: `154fb314-b34b-47ee-9564-db48a21feba8`
- 📊 Measure requests — [IDE-248](https://linear.app/idealic/issue/IDE-248/measure-requests)
- 🔴 Observed problems — [IDE-249](https://linear.app/idealic/issue/IDE-249/observed-problems)
- 🛠️ Tooling & Gates — [IDE-250](https://linear.app/idealic/issue/IDE-250/tooling-and-gates)
- 🟦 Documentation — [IDE-251](https://linear.app/idealic/issue/IDE-251/documentation)

*Four channels rather than the default set: this project's own 📊 Measure requests is the one it has and others do not, and the four were the operator's choice at scaffold time.*

## Product: Playground
- **Project id**: `d11c75f2-a259-4618-ade1-bcad99128572` (`P-IDE-15`) · **Inboxes milestone**: `f1fa9f18-c545-4a5c-8dd1-9416b5e81043`
- 🟪 Inquiries — [IDE-342](https://linear.app/idealic/issue/IDE-342/inquiries)
- 🔴 Observed problems — [IDE-343](https://linear.app/idealic/issue/IDE-343/observed-problems)
- 🔵 Feature requirements — [IDE-344](https://linear.app/idealic/issue/IDE-344/feature-requirements)
- 🟦 Documentation — [IDE-345](https://linear.app/idealic/issue/IDE-345/documentation)

*Four channels rather than the default set, approved by manager:app as a small scaffold. Seat: app:playground.*

## Product: Deploy
- **Project id**: `cdc5753a-3e3d-4385-8b44-c92d2e463359` (`P-IDE-14`) · **Inboxes milestone**: none yet
- No channels yet. Its seat is app:deploy, and the handbook says to raise signals with that seat directly until channels exist.

*Created 2026-10-30 on the operator's per-area project ruling. Channels and an Inboxes milestone are not scaffolded; add them here when they exist rather than inventing ids.*

## Product: Writer
- **Project id**: `3614e4b5-d4b1-44a6-a35c-2e06c5f3c91a` (`P-IDE-17`) · **Inboxes milestone**: none yet
- No channels yet. Its seat is app:writer, and the handbook says to drop writer and editor findings in Product: Editor's channels until this project's exist.

*Created 2026-10-30 on the operator's per-area project ruling. Channels and an Inboxes milestone are not scaffolded; add them here when they exist rather than inventing ids.*

## Product: Idea
- **Project id**: `1116afcd-4829-4bda-872d-df146b9d5450` · **Inboxes milestone**: `d22ec35a-8b99-44f0-886c-50496a39db08`
- 🔴 Observed problems — [IDE-34](https://linear.app/idealic/issue/IDE-34)
- 🟠 Identified shortcomings — [IDE-35](https://linear.app/idealic/issue/IDE-35)
- 🔵 Feature requirements — [IDE-37](https://linear.app/idealic/issue/IDE-37)
- 🟢 Potential solutions — [IDE-38](https://linear.app/idealic/issue/IDE-38)
- 🟡 Researches & Fixtures — [IDE-39](https://linear.app/idealic/issue/IDE-39)
- 🟣 Feedback & Transcripts — [IDE-40](https://linear.app/idealic/issue/IDE-40)
- 🟪 Inquiries — [IDE-41](https://linear.app/idealic/issue/IDE-41)
- 🛠️ Tooling & Gates — [IDE-126](https://linear.app/idealic/issue/IDE-126)
- 🟦 Documentation — [IDE-287](https://linear.app/idealic/issue/IDE-287)

## Product: Market & Jobs
- **Project id**: `3c4310e5-d8c4-4fe2-a328-0e979c8a80fb` · **Inboxes milestone**: `731e8cd9-c9d4-4673-9cd5-b069a41cfa2e`
- 🔴 Observed problems — [IDE-42](https://linear.app/idealic/issue/IDE-42)
- 🟠 Identified shortcomings — [IDE-84](https://linear.app/idealic/issue/IDE-84)
- 🔵 Feature requirements — [IDE-85](https://linear.app/idealic/issue/IDE-85)
- 🟢 Potential solutions — [IDE-43](https://linear.app/idealic/issue/IDE-43)
- 🟡 Researches & Fixtures — [IDE-86](https://linear.app/idealic/issue/IDE-86)
- 🟣 Feedback & Transcripts — [IDE-87](https://linear.app/idealic/issue/IDE-87)
- 🟪 Inquiries — [IDE-44](https://linear.app/idealic/issue/IDE-44)
- 🟦 Documentation — [IDE-288](https://linear.app/idealic/issue/IDE-288)

## Product: Worlds & Branches
- **Project id**: `aa02b1cc-f1c7-46e9-985a-073e9f0d3294` · **Inboxes milestone**: `b8690911-225f-4005-9db8-156f1e4ae92a`
- 🔴 Observed problems — [IDE-45](https://linear.app/idealic/issue/IDE-45)
- 🟠 Identified shortcomings — [IDE-88](https://linear.app/idealic/issue/IDE-88)
- 🔵 Feature requirements — [IDE-89](https://linear.app/idealic/issue/IDE-89)
- 🟢 Potential solutions — [IDE-46](https://linear.app/idealic/issue/IDE-46)
- 🟡 Researches & Fixtures — [IDE-90](https://linear.app/idealic/issue/IDE-90)
- 🟣 Feedback & Transcripts — [IDE-91](https://linear.app/idealic/issue/IDE-91)
- 🟪 Inquiries — [IDE-47](https://linear.app/idealic/issue/IDE-47)
- 🟦 Documentation — [IDE-289](https://linear.app/idealic/issue/IDE-289)

## Product: Handbook
- **Project id**: `1aeb0e20-d6b9-410f-9e9b-605c0394f170` · **Inboxes milestone**: `cf4cbd86-d6ba-4c3d-9537-54594f1b9ec4`
- 🔴 Observed problems — [IDE-51](https://linear.app/idealic/issue/IDE-51)
- 🟠 Identified shortcomings — [IDE-61](https://linear.app/idealic/issue/IDE-61)
- 🔵 Feature requirements — [IDE-62](https://linear.app/idealic/issue/IDE-62)
- 🟢 Potential solutions — [IDE-52](https://linear.app/idealic/issue/IDE-52)
- 🟡 Researches & Fixtures — [IDE-63](https://linear.app/idealic/issue/IDE-63)
- 🟣 Feedback & Transcripts — [IDE-64](https://linear.app/idealic/issue/IDE-64)
- 🟪 Inquiries — [IDE-53](https://linear.app/idealic/issue/IDE-53)
- 🟦 Documentation — [IDE-290](https://linear.app/idealic/issue/IDE-290)

*No 🛠️ channel of its own: its handbook routes tooling to Product: Idea's IDE-126.*

## Product: CI & Gates
- **Project id**: `fa0ddd40-cd7c-4c91-aec3-0f6594a1109e` · **Inboxes milestone**: `873d11af-bfe3-41b0-92c2-e809ae34df3f`
- 🔴 Observed problems — [IDE-48](https://linear.app/idealic/issue/IDE-48)
- 🟠 Identified shortcomings — [IDE-57](https://linear.app/idealic/issue/IDE-57)
- 🔵 Feature requirements — [IDE-58](https://linear.app/idealic/issue/IDE-58)
- 🟢 Potential solutions — [IDE-49](https://linear.app/idealic/issue/IDE-49)
- 🟡 Researches & Fixtures — [IDE-59](https://linear.app/idealic/issue/IDE-59)
- 🟣 Feedback & Transcripts — [IDE-60](https://linear.app/idealic/issue/IDE-60)
- 🟪 Inquiries — [IDE-50](https://linear.app/idealic/issue/IDE-50)
- 🟦 Documentation — [IDE-291](https://linear.app/idealic/issue/IDE-291)

*No inbox handbook yet.*

## Product: Editor
- **Project id**: `97398436-12f5-4726-b052-3a60aece50a3` · **Inboxes milestone**: `1673b2e3-9a6c-4cfc-b38b-c78bd99ccdbf`
- 🔴 Observed problems — [IDE-54](https://linear.app/idealic/issue/IDE-54)
- 🟠 Identified shortcomings — [IDE-65](https://linear.app/idealic/issue/IDE-65)
- 🔵 Feature requirements — [IDE-66](https://linear.app/idealic/issue/IDE-66)
- 🟢 Potential solutions — [IDE-55](https://linear.app/idealic/issue/IDE-55)
- 🟡 Researches & Fixtures — [IDE-67](https://linear.app/idealic/issue/IDE-67)
- 🟣 Feedback & Transcripts — [IDE-68](https://linear.app/idealic/issue/IDE-68)
- 🟪 Inquiries — [IDE-56](https://linear.app/idealic/issue/IDE-56)
- 🟦 Documentation — [IDE-292](https://linear.app/idealic/issue/IDE-292)

*No inbox handbook yet.*

## Product: Demos & Explainers
- **Project id**: `b81d0528-299f-4728-9e9d-c96283153578` · **Inboxes milestone**: `3d9695f5-470d-4d89-9903-16680d6cdaca`
- 🔴 Observed problems — [IDE-70](https://linear.app/idealic/issue/IDE-70)
- 🟠 Identified shortcomings — [IDE-72](https://linear.app/idealic/issue/IDE-72)
- 🔵 Feature requirements — [IDE-76](https://linear.app/idealic/issue/IDE-76)
- 🟢 Potential solutions — [IDE-80](https://linear.app/idealic/issue/IDE-80)
- 🟡 Researches & Fixtures — [IDE-81](https://linear.app/idealic/issue/IDE-81)
- 🟣 Feedback & Transcripts — [IDE-82](https://linear.app/idealic/issue/IDE-82)
- 🟪 Inquiries — [IDE-83](https://linear.app/idealic/issue/IDE-83)
- 🟦 Documentation — [IDE-293](https://linear.app/idealic/issue/IDE-293)

*No inbox handbook yet.*

## Product: Realm
- **Project id**: `1dbba1ef-e245-45e5-987e-7f29bfc474a0` · **Inboxes milestone**: `9afd387b-895f-4489-b842-aaa800fd3009`
- 🔴 Observed problems — [IDE-71](https://linear.app/idealic/issue/IDE-71)
- 🟠 Identified shortcomings — [IDE-73](https://linear.app/idealic/issue/IDE-73)
- 🔵 Feature requirements — [IDE-74](https://linear.app/idealic/issue/IDE-74)
- 🟢 Potential solutions — [IDE-75](https://linear.app/idealic/issue/IDE-75)
- 🟡 Researches & Fixtures — [IDE-77](https://linear.app/idealic/issue/IDE-77)
- 🟣 Feedback & Transcripts — [IDE-78](https://linear.app/idealic/issue/IDE-78)
- 🟪 Inquiries — [IDE-79](https://linear.app/idealic/issue/IDE-79)
- 🟦 Documentation — [IDE-294](https://linear.app/idealic/issue/IDE-294)

*No inbox handbook yet.*

## Product: Orchestration
- **Project id**: `8716ada7-01c9-49b7-a882-51e7c2352960` (`P-IDE-10`, team Idealic) · **Inboxes milestone**: none yet
- No channels yet. Its handbook says so in its own opening, and rules a 🛠️ Tooling & Gates channel out: here, engine coordination work is ticket material (the carve-out in `/ticket`'s Subject Gate), not a residue.

*Added 2026-10-30 from [IDE-128](https://linear.app/idealic/issue/IDE-128), which recorded the handbook's publication. Add channels here when they exist rather than inventing ids.*

## Product: Ideas site
- **Project id**: `d7147709-bbf3-43ea-8cb0-d402ab4c102d` (`P-IDE-16`) · **Inboxes milestone**: none yet
- No channels yet. Its seat is app:ideas. The handbook says to file a chunk of work as a ticket here, send a question or finding to app:ideas, and drop tooling in Product: Idea's 🛠️ [IDE-126](https://linear.app/idealic/issue/IDE-126) until this project's channels exist.

*Created 2026-10-30 on the operator's per-area project ruling. Channels and an Inboxes milestone are not scaffolded; add them here when they exist rather than inventing ids.*

## Product: Resources & Platform
- **Project id**: `d0d527e1-51d9-4121-85c1-e265ac7b4fae` (`P-IDE-11`) · **Inboxes milestone**: none yet
- No channels and no inbox handbook yet, so no handbook rules apply. Its project description says it covers `resource-kernel`, `resource-database`, `resource-edge`, `resource-mount`, `afford`, `ideas-grants`, `ideas-storage`, `ideas-secrets`, `ideas-identity`, `ideas-scope`, `ideas-process`, `ideas-stats` and `app/`.

*Created 2026-10-28 on the operator's ruling, under the Domain platform initiative; added here 2026-10-30 from Linear's get_project. Channels and an Inboxes milestone are not scaffolded; add them here when they exist rather than inventing ids.*

## Product: Example
- **Project id**: `00000000-0000-4000-8000-000000000001` · **Inboxes milestone**: `00000000-0000-4000-8000-000000000002`
- 🔴 Observed problems — [ENG-1001](https://linear.app/acme/issue/ENG-1001)
- 🟠 Identified shortcomings — [ENG-1002](https://linear.app/acme/issue/ENG-1002)
- 🔵 Feature requirements — [ENG-1003](https://linear.app/acme/issue/ENG-1003)
- 🟢 Potential solutions — [ENG-1004](https://linear.app/acme/issue/ENG-1004)
- 🟣 Feedback & Transcripts — [ENG-1005](https://linear.app/acme/issue/ENG-1005)
- 🟪 Inquiries — [ENG-1006](https://linear.app/acme/issue/ENG-1006)

*A placeholder showing the row shape. Replace it with your intake projects as `/intake` scaffolds them; until then `/inbox-post` falls back to live discovery.*
