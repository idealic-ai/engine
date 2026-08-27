# Inbox Registry — intake projects → channels → tickets

Fast-path navigation map for `/inbox-post`. Project → its `Inboxes` channel tickets (FIN-key + URL). A **cache**, not the source of truth — Linear is. When it's stale or missing a target, the skill falls back to live discovery (`list_projects(includeMilestones)` → client-filter `Inboxes`; channel tickets by title) and self-heals this file.

**Issue status:** every ticket under an `Inboxes` milestone — the channels and anything parked there to gather input — sits on the **`Inboxes` issue status**, not `Backlog` (`§INV_INBOX_STATUS_NOT_BACKLOG`). On team Finchclaims that status is `aece8ff9-68f4-4696-8555-8ad5a1e7e7f1`, type `backlog`. Scaffold a new channel straight onto it: `save_issue(state: "Inboxes", …)`. The type is unchanged, so ranking and cycle exclusion behave as before; only the Backlog view stops carrying collectors. To audit, filter on `projectMilestone.name == "Inboxes" AND state.type == "backlog"` — that finds channels this cache has never heard of, which a per-project walk from these rows would miss.

*Channels:* 🔴 Observed problems · 🟠 Identified shortcomings · 🔵 Feature requirements · 🟢 Potential solutions · 🟣 Feedback & Transcripts · 🟤 Priorities & Deadlines · 🟡 Researches & Fixtures · 🟦 Documentation · 🟪 Inquiries · 📣 Announcements · 🟩 Chores & tracker hygiene · ⚖️ Legal and counsel questions · 🤝 Partner signal

Not a fixed set in practice — channel titles vary slightly per project (Claims & Policies uses "Feature **& capability** requirements"). Match by intent, not by exact title. **The discovery fallback filters issue titles by these emojis — extend that list whenever a channel is added, or the new one is invisible to discovery.** **Two of the glyphs are project-specific, not shared**: ⚖️ Legal and counsel questions and 🤝 Partner signal exist only on *Product: Claims Data Consortium*, whose subject makes them real channels rather than a convenience — a question needing a lawyer, and a thing a named partner said, have no honest home in the standard set. Discovery must still know them or that project loses two channels. *(The `Inbox: <what>` naming that project used until 2026-08-26 is **retired** — its four channels were renamed to the emoji convention. If you find a channel still titled `Inbox: …`, it is a project the standardisation missed.)* Squares twin circles by design (🟦 with 🔵, 🟩 with 🟢, 🟪 with 🟣): every color was already taken by a circle, so a twin is the convention rather than a collision. 🟪 twins 🟣 because both are raw human voice arriving unprocessed — 🟣 is what someone **said**, 🟪 is what someone **asked**.

**🟪 Inquiries is universal by nature, and a deliberate exception to how every other channel is chosen.** The others earn their place per project — an empty one is a cost, not a completeness win — so a project's set is decided, never defaulted. Inquiries is different because **any project can be asked a question**, including one with nothing shipped and nothing yet to observe: not knowing is the whole content, so it cannot sit empty for want of subject matter. It was created on **all twelve** intake projects on 2026-08-25 (decided: Yarik Fedin) rather than seeded on one and replicated as it earned its way. A project scaffolding an inbox from here on gets it in the initial set.

**Two of them are not inbound signals**, and a pass should treat them differently:

*   **📣 Announcements** runs **outbound** — news leaving the system, not a signal entering it. It does **not** normally graduate to a ticket. It is triaged for one purpose: **verification** that the announced thing is actually deployed *and wired*. An announcement that shipped and that nothing consumes is a real finding, and routes to whichever channel fits it.
*   **🟩 Chores & tracker hygiene** is about **the record, not the product** — a stale title, an obsolete description, two tickets that are one thing. Its work batches (one stale title isn't worth a pass; twenty are one sweep) and routes to `/chores`. Its load-bearing rule: **chase what a query cannot find** — un-triaged / unassigned / no-priority / stale counts are already measured, so a drop that restates them is waste; a drop about *meaning* is not.

## The handbook

Every channel is **thin**: it says what belongs in it, links **its own project's** handbook, and (where it has one) carries its own `## Directions`. The report template, what-happens-next, and the correction policy live in the handbook — not in the channels.

Each intake project carries its **own complete copy**, attached to the project so it appears in that project's sidebar. All titled `Inbox Handbook — how this project's intake inboxes work`. There is **no inheritance and no parent document**: sections 1–6 and 8 are kept in sync by hand, and `## What triage will chase` is deliberately different in each one (it names that project's actual tools — Temporal for Differ, the staging DB + PostHog for Email Classification, the CDV + source PDF for Document Extraction).

| Project | Handbook | doc id · slugId |
|---|---|---|
| Claims & Policies | [Inbox Handbook](https://linear.app/finchclaims/document/inbox-handbook-how-this-projects-intake-inboxes-work-313413476400) | `b41bd7cf-8ef4-447b-acda-b332c257cb98` · `313413476400` |
| Document Extraction | [Inbox Handbook](https://linear.app/finchclaims/document/inbox-handbook-how-this-projects-intake-inboxes-work-99082b673fbd) | `ae065799-e661-4505-9692-fd1cd7312d30` · `99082b673fbd` |
| Email Classification | [Inbox Handbook](https://linear.app/finchclaims/document/inbox-handbook-how-this-projects-intake-inboxes-work-e92601c17dde) | `9d0018c5-5cae-4ed5-8789-0bd63cdb51b4` · `e92601c17dde` |
| Differ | [Inbox Handbook](https://linear.app/finchclaims/document/inbox-handbook-how-this-projects-intake-inboxes-work-2f42ecf566ae) | `b2b87f75-2d21-4de2-99d6-de2c4c29d931` · `2f42ecf566ae` |
| Intake System | [Inbox Handbook](https://linear.app/finchclaims/document/inbox-handbook-how-this-projects-intake-inboxes-work-28d8ea1b998f) | `6b718963-5fbc-4372-b108-d18407dd6c47` · `28d8ea1b998f` |
| Preloss B2B | [Inbox Handbook](https://linear.app/finchclaims/document/inbox-handbook-how-this-projects-intake-inboxes-work-b22ffd52d65e) | `8a388f09-18f7-44e1-bba0-d7e67f1a1262` · `b22ffd52d65e` |
| Report Design System | [Inbox Handbook](https://linear.app/finchclaims/document/inbox-handbook-how-this-projects-intake-inboxes-work-011d57aa819b) | `57fbc79f-7d40-4573-b793-68657e122795` · `011d57aa819b` |
| Ask Finch | [Inbox Handbook](https://linear.app/finchclaims/document/inbox-handbook-how-this-projects-intake-inboxes-work-b80ae6140797) | `50d63b6f-5ff1-47eb-b2aa-62f7cc1f1152` · `b80ae6140797` |
| Session QA | [Inbox Handbook](https://linear.app/finchclaims/document/inbox-handbook-how-this-projects-intake-inboxes-work-47c325f31985) | `d1661668-d2a5-4487-be5f-fef06eb9d772` · `47c325f31985` |
| Dates & Notifications | [Inbox Handbook](https://linear.app/finchclaims/document/inbox-handbook-how-this-projects-intake-inboxes-work-4abc5a4b5743) | `997c3fcb-a86a-4351-8649-9e6786091d66` · `4abc5a4b5743` |
| Mobile | [Inbox Handbook](https://linear.app/finchclaims/document/inbox-handbook-how-this-projects-intake-inboxes-work-a95a9113c370) | `fc361581-1e2b-4563-b7a8-4e120009d1f0` · `a95a9113c370` |
| Claims Data Consortium | [Inbox Handbook](https://linear.app/finchclaims/document/inbox-handbook-how-this-projects-intake-inboxes-work-41b9992d4887) | `0ea46cbb-9a4b-49d2-9cf8-f240d5e7abac` · `41b9992d4887` |
| API | [Inbox Handbook](https://linear.app/finchclaims/document/inbox-handbook-how-this-projects-intake-inboxes-work-83fea83a335e) | `f7457ce0-416d-444f-9c36-595e395fedde` · `83fea83a335e` |
| Console | [Inbox Handbook](https://linear.app/finchclaims/document/inbox-handbook-how-this-projects-intake-inboxes-work-90d47f725806) | `3f47b2af-762b-435f-bc4d-f24637772323` · `90d47f725806` |
| Design | [Inbox Handbook](https://linear.app/finchclaims/document/inbox-handbook-how-this-projects-intake-inboxes-work-f94156046b9a) | `f91853bb-9793-4372-bec3-7f718ab1c96e` · `f94156046b9a` |

The short-lived team-level handbook (`1292d6ee-5819-4354-9892-49f0d3d388a6`, slug `7f5f9c302585`) is **retired** — a team-attached document has no home in the Linear UI, so nothing surfaced it from a project. If you find a channel still linking slug `7f5f9c302585`, repoint it at its own project's handbook above.

**Every project now has a handbook.** Claims Data Consortium's was written on 2026-08-26, closing the last gap — that project had been scaffolded by hand outside the conventions and had drifted from all of them at once (naming, handbook, discoverability). Its recipe is unlike any other: no claim id, no Temporal, no failing job, because the subject is a data pool, a set of governing documents, a group of partners and a printed report with a hard date.

Match a handbook by **slugId**, not by the words in the URL: retitling a Linear document re-slugs the human-readable segment while the 12-hex slugId stays put.

## Slack announce channels

The wave's `§PASS_HEARTBEAT` announce is **per-project** — pass the name below as `engine slack-post --channel '#name'`. Do **not** leave the announce to `$SLACK_INTAKE_CHANNEL`: it is a single global var, so relying on it makes every project post to one channel, and it is only read when **exported** (`--env-file` extracts the token only, and a channel left in the env file resolves to empty).

*   **Claims & Policies** — `#engineering-alerts`
*   **Document Extraction** — `#engineering-alerts`
*   **Email Classification** — `#engineering-alerts`
*   **Differ** — `#engineering-alerts`
*   **Intake System** — `#engineering-alerts`
*   **Preloss B2B** — `#intake-alerts` *(confirmed 2026-08-26)*
*   **Report Design System** — `#intake-alerts` *(confirmed 2026-08-26)*
*   **Ask Finch** — **UNSET**
*   **Session QA** — **UNSET**
*   **Dates & Notifications** — **UNSET**
*   **Mobile** — **UNSET**
*   **Claims Data Consortium** — `#intake-alerts`
*   **API** — `#intake-alerts` *(chosen at scaffold, 2026-08-26, Yarik Fedin)*
*   **Console** — `#intake-alerts` *(chosen at scaffold, 2026-08-26, Yarik Fedin)*
*   **Design** — `#intake-alerts` *(chosen at scaffold, 2026-08-27, Yarik Fedin)*

The first five were moved from `#intake-alerts` to `#engineering-alerts` on 2026-08-17 (decided: Yarik Fedin) — intake heartbeats belong with the rest of the engineering alerting rather than in a channel of their own. **The rows below it are unresolved because nobody has said where those projects belong** — they are newer than that decision, and a guess here would silently send a project's heartbeat somewhere nobody watches. **Preloss B2B, Report Design System and Claims Data Consortium were decided on 2026-08-26 (Yarik Fedin): each announces to `#intake-alerts`.** Preloss B2B's and Report Design System's rows had been bootstrap leftovers nobody had chosen; both are now recorded choices at the same value, so the value did not move but its standing did — it is answerable now, and re-asking is waste. The rows marked **UNSET** have never had a destination chosen at all — a pass on one of them should ask rather than default. **The 2026-08-26 answer suggests `#intake-alerts` is the intended default for newer projects, but that is an inference and the four UNSET rows are deliberately not filled from it.** Extending the 2026-08-17 `#engineering-alerts` decision to them is a reasonable guess and is still a guess.

This is the **announce** destination only — one per project, where a completed pass posts its heartbeat. It is a different thing from the channels a wave *reads* for ambient context, which are per-project and live in each project's Inbox Handbook under `## Related Slack Channels` (`¶INV_CHANNEL_MACHINERY_IN_ONE_DOC`). A project may read several channels and announces to exactly one.

**Names, never ids.** `slack-post` resolves a name to the id Slack's API requires and keeps the id internal — no channel id belongs in config or in anything a human reads. The tradeoff is that a **rename breaks the row**: resolution fails loudly rather than guessing, so treat renaming an intake channel as a config change and update it here.

Verify a project's Slack setup before its first announce: `engine slack-post --verify --channel '#name'` checks token, scopes, channel and bot membership, and self-joins when `channels:join` is granted.

## Initiatives — the domain a project belongs to

🔴 **NOT YET CREATED, and not yet creatable by any agent.** Initiatives are disabled in the Finchclaims workspace — a probe returns *"Initiative status updates are not enabled for this workspace… enable roadmaps to use initiatives."* Someone has to switch them on (Settings → Initiatives) and create the four **by hand in the UI**, because the MCP has **no `list_initiatives`, no `get_initiative`, no `save_initiative`**. Until that happens, treat every row below as a plan, not a fact.

**What a wave CAN do once they exist**: attach a project — `save_project(addInitiatives: ["Platform"])` — and comment on, document, or post status updates against one. Attach-only: a wave joins an initiative whose name it is given, and can neither enumerate nor create one. **So the attach step fails soft and never blocks a scaffold.**

**Why an initiative rather than a saved view**: a view is a *filter*, and a domain is not filterable — no field on a Linear project says "this is a Platform concern". An initiative is a **curated** set, which is exactly the shape of a judgement call. Views remain the right tool for anything derivable from a property (status, health, lead, name prefix).

The cut below covers the 15 `Product: *` projects; owners were read off existing project leads rather than assigned. Decided 2026-08-26 (Yarik Fedin).

| Initiative | Owner | Projects |
|---|---|---|
| **Platform** | Bruno Gomes | API · Console · Intake System · Report Design System |
| **Claim Data** | Yarik Fedin | Document Extraction · Claims & Policies · Email Classification · Ask Finch |
| **Adjuster Surfaces** | Thomas McLaughlin | Mobile · Dates & Notifications · Session QA · Differ |
| **New Markets** | Thomas McLaughlin | Leads · Preloss B2B · Claims Data Consortium |

*Three judgement calls, recorded so they are not silently re-litigated:* **Ask Finch → Claim Data** (filed by its hard problem, grounding and trust in the data, not by the fact that it is user-facing) · **Session QA → Adjuster Surfaces** (filed by its subject, what a customer hit, not by how it is built, which is internal machinery) · **Differ → Adjuster Surfaces "for now"** (it would otherwise be an initiative of one; expect it to graduate back out when Differ PLG and Standalone Differ GTM come into scope, which is a reversible move).

⚠️ **Name-collision trap**: *Product: Claims Data Consortium* is a **business** — a pooled industry data product — and belongs to **New Markets**, not to Claim Data. The names actively invite the wrong grouping.

⚠️ **Two axes considered and dropped**: **Integrations** would be empty under a `Product: *` scope (Gmail generalization, ClaimWizard migration and Weather Event all live outside it; the MCP surface sits inside Console), and **Differ** as its own initiative held exactly one project. Both become viable if the scope widens past `Product: *` — recorded so the next person does not re-derive them.

---

## Product: Claims & Policies
- **Project id**: `0d1c3330-0cf2-41a6-ab46-733784e580f9` · **Inboxes milestone**: `8ce4f377-f406-4e50-a077-37d7fb5ae5a9`
- 🔴 Observed problems — [FIN-3453](https://linear.app/finchclaims/issue/FIN-3453)
- 🟠 Identified shortcomings — [FIN-3454](https://linear.app/finchclaims/issue/FIN-3454)
- 🔵 Feature & capability requirements — [FIN-3455](https://linear.app/finchclaims/issue/FIN-3455)
- 🟢 Potential solutions — [FIN-3456](https://linear.app/finchclaims/issue/FIN-3456)
- 🟣 Feedback & Transcripts — [FIN-3457](https://linear.app/finchclaims/issue/FIN-3457)
- 🟤 Priorities & Deadlines — [FIN-3458](https://linear.app/finchclaims/issue/FIN-3458)
- 🟡 Researches & Fixtures — [FIN-3459](https://linear.app/finchclaims/issue/FIN-3459)
- 🟦 Documentation — [FIN-3479](https://linear.app/finchclaims/issue/FIN-3479)
- 🟪 Inquiries — [FIN-4176](https://linear.app/finchclaims/issue/FIN-4176)

## Product: Intake System
- **Project id**: `37f469ac-29b4-4d09-8218-57b84bef6a0f` · **Inboxes milestone**: `309c89cf-e8c3-4a63-b9f2-93f2756c28cc`
- 🔴 Observed problems — [FIN-3445](https://linear.app/finchclaims/issue/FIN-3445)
- 🟠 Identified shortcomings — [FIN-3446](https://linear.app/finchclaims/issue/FIN-3446)
- 🔵 Feature requirements — [FIN-3447](https://linear.app/finchclaims/issue/FIN-3447)
- 🟢 Potential solutions — [FIN-3448](https://linear.app/finchclaims/issue/FIN-3448)
- 🟣 Feedback & Transcripts — [FIN-3449](https://linear.app/finchclaims/issue/FIN-3449)
- 🟤 Priorities & Deadlines — [FIN-3451](https://linear.app/finchclaims/issue/FIN-3451)
- 🟡 Researches & Fixtures — [FIN-3450](https://linear.app/finchclaims/issue/FIN-3450)
- 🟦 Documentation — [FIN-3476](https://linear.app/finchclaims/issue/FIN-3476)
- 🟪 Inquiries — [FIN-4177](https://linear.app/finchclaims/issue/FIN-4177)
- 📣 Announcements — [FIN-3590](https://linear.app/finchclaims/issue/FIN-3590)
- 🟩 Chores & tracker hygiene — [FIN-3591](https://linear.app/finchclaims/issue/FIN-3591)

*Intake System is the only project carrying 📣 and 🟩 today — they were created here first, deliberately. Replicate them elsewhere only if they earn it there; the channel set is contextual per project (`¶INV_INBOX_IS_TICKETS`), and an empty channel is a cost, not a completeness win.*

## Product: Email Classification
- **Project id**: `fe33cb95-67b0-4355-b096-a3ecde805757` · **Inboxes milestone**: `aeab32a5-d202-4f92-97e2-774241a7a026`
- 🔴 Observed problems — [FIN-3356](https://linear.app/finchclaims/issue/FIN-3356)
- 🟠 Identified shortcomings — [FIN-3358](https://linear.app/finchclaims/issue/FIN-3358)
- 🔵 Feature requirements — [FIN-3360](https://linear.app/finchclaims/issue/FIN-3360)
- 🟢 Potential solutions — [FIN-3359](https://linear.app/finchclaims/issue/FIN-3359)
- 🟣 Feedback & Transcripts — [FIN-3367](https://linear.app/finchclaims/issue/FIN-3367)
- 🟤 Priorities & Deadlines — [FIN-3442](https://linear.app/finchclaims/issue/FIN-3442)
- 🟡 Researches & Fixtures — [FIN-3377](https://linear.app/finchclaims/issue/FIN-3377)
- 🟦 Documentation — [FIN-3481](https://linear.app/finchclaims/issue/FIN-3481)
- 🟪 Inquiries — [FIN-4178](https://linear.app/finchclaims/issue/FIN-4178)

## Product: Differ
- **Project id**: `cae6ffa0-50df-49ab-aed3-d69a5d8169d9` · **Inboxes milestone**: `e60da303-e43d-46e4-a368-0b9276cecda4`
- 🔴 Observed problems — [FIN-3362](https://linear.app/finchclaims/issue/FIN-3362)
- 🟠 Identified shortcomings — [FIN-3363](https://linear.app/finchclaims/issue/FIN-3363)
- 🔵 Feature requirements — [FIN-3364](https://linear.app/finchclaims/issue/FIN-3364)
- 🟢 Potential solutions — [FIN-3365](https://linear.app/finchclaims/issue/FIN-3365)
- 🟣 Feedback & Transcripts — [FIN-3368](https://linear.app/finchclaims/issue/FIN-3368)
- 🟤 Priorities & Deadlines — [FIN-3443](https://linear.app/finchclaims/issue/FIN-3443)
- 🟡 Researches & Fixtures — [FIN-3378](https://linear.app/finchclaims/issue/FIN-3378)
- 🟦 Documentation — [FIN-3482](https://linear.app/finchclaims/issue/FIN-3482)
- 🟪 Inquiries — [FIN-4179](https://linear.app/finchclaims/issue/FIN-4179)

## Product: Document Extraction
- **Project id**: `9da56ed5-7293-45cb-b8f4-38bfa2a4203e` · **Inboxes milestone**: `4690caff-1ad3-4154-8c9a-ad70fdd394f9`
- 🔴 Observed problems — [FIN-3369](https://linear.app/finchclaims/issue/FIN-3369)
- 🟠 Identified shortcomings — [FIN-3370](https://linear.app/finchclaims/issue/FIN-3370)
- 🔵 Feature requirements — [FIN-3371](https://linear.app/finchclaims/issue/FIN-3371)
- 🟢 Potential solutions — [FIN-3372](https://linear.app/finchclaims/issue/FIN-3372)
- 🟣 Feedback & Transcripts — [FIN-3373](https://linear.app/finchclaims/issue/FIN-3373)
- 🟤 Priorities & Deadlines — [FIN-3444](https://linear.app/finchclaims/issue/FIN-3444)
- 🟡 Researches & Fixtures — [FIN-3376](https://linear.app/finchclaims/issue/FIN-3376)
- 🟦 Documentation — [FIN-3480](https://linear.app/finchclaims/issue/FIN-3480)
- 🟪 Inquiries — [FIN-4180](https://linear.app/finchclaims/issue/FIN-4180)

## Product: Preloss B2B
- **Project id**: `054224f1-4782-43f7-998d-7f31d1c12b9c` · **Inboxes milestone**: `f1ec64c8-6c28-4191-bbda-66b1f7a0c763`
- 🟣 Feedback & Transcripts — [FIN-3663](https://linear.app/finchclaims/issue/FIN-3663)
- 🟠 Identified shortcomings — [FIN-3664](https://linear.app/finchclaims/issue/FIN-3664)
- 🔵 Feature requirements — [FIN-3665](https://linear.app/finchclaims/issue/FIN-3665)
- 🟢 Potential solutions — [FIN-3666](https://linear.app/finchclaims/issue/FIN-3666)
- 🟤 Priorities & Deadlines — [FIN-3667](https://linear.app/finchclaims/issue/FIN-3667)
- 🟦 Documentation — [FIN-3668](https://linear.app/finchclaims/issue/FIN-3668)
- 🟪 Inquiries — [FIN-4181](https://linear.app/finchclaims/issue/FIN-4181)
- 🔴 Observed problems — [FIN-4188](https://linear.app/finchclaims/issue/FIN-4188)
- 🟡 Researches & Fixtures — [FIN-4189](https://linear.app/finchclaims/issue/FIN-4189)

*🔴 Observed problems and 🟡 Researches & Fixtures were deliberately withheld at bootstrap — the project was in discovery with no product in front of customers, so both would have sat empty, and an empty channel makes a dropper hesitate over an irrelevant choice every time. **The stated trigger — "when a design partner is live and there is something to observe" — fired, and both were created on 2026-08-26 (decided: Yarik Fedin).** 🟡 is scoped to this project's actual subject: a **market fact we got wrong** (a mis-sized segment, a mis-read buyer type, a competitor claim that does not hold), rather than corrected AI output, because there is no AI workload here to correct. 🟣 Feedback & Transcripts remains the primary channel, not a secondary one: most drops are whole discovery calls.*

*Worth keeping as a pattern: the withholding decision was recorded **with the condition that would end it**, and that is the only reason anyone could tell the condition had been met. A deliberate omission with no stated trigger is indistinguishable from an oversight a month later.*

## Product: Report Design System
- **Project id**: `6cd804e9-02a3-4a52-bb59-937a03d3a374` · **Inboxes milestone**: `b2c91cc5-cc27-4233-a5e2-abd292281532`
- 🔴 Observed problems — [FIN-3920](https://linear.app/finchclaims/issue/FIN-3920)
- 🟠 Identified shortcomings — [FIN-3921](https://linear.app/finchclaims/issue/FIN-3921)
- 🔵 Feature requirements — [FIN-3922](https://linear.app/finchclaims/issue/FIN-3922)
- 🟢 Potential solutions — [FIN-3923](https://linear.app/finchclaims/issue/FIN-3923)
- 🟣 Feedback & Transcripts — [FIN-3924](https://linear.app/finchclaims/issue/FIN-3924)
- 🟡 Researches & Fixtures — [FIN-3925](https://linear.app/finchclaims/issue/FIN-3925)
- 🟤 Priorities & Deadlines — [FIN-3926](https://linear.app/finchclaims/issue/FIN-3926)
- 🟦 Documentation — [FIN-3927](https://linear.app/finchclaims/issue/FIN-3927)
- 🟪 Inquiries — [FIN-4182](https://linear.app/finchclaims/issue/FIN-4182)

*The design kit and the skills that compose from it (`/design`, `/design-request`, `/design-server`, `/prove`, `/remix`). Bootstrapped 2026-08-14. Routing test against its nearest neighbour, Intake System: **if the fix is in how a page is made or what it can express, it is Report Design System; if the fix is a step in a grooming protocol, it is Intake System.** A Decision or Outcomes Board that looks wrong is usually a kit defect wearing a costume; one that asks the wrong question is intake's. 🟢 Potential solutions doubles as the home for visual references — no separate reference channel, deliberately: it has the same consumer.*

## Product: Ask Finch
- **Project id**: `35a5f2ab-0fcb-4fd9-98a5-74ace0514fa6` · **Inboxes milestone**: `ff570e58-b967-4683-915d-34279e811231`
- 🔴 Observed problems — [FIN-3683](https://linear.app/finchclaims/issue/FIN-3683)
- 🟠 Identified shortcomings — [FIN-3684](https://linear.app/finchclaims/issue/FIN-3684)
- 🔵 Feature requirements — [FIN-3685](https://linear.app/finchclaims/issue/FIN-3685)
- 🟢 Potential solutions — [FIN-3686](https://linear.app/finchclaims/issue/FIN-3686)
- 🟣 Feedback & Transcripts — [FIN-3687](https://linear.app/finchclaims/issue/FIN-3687)
- 🟡 Researches & Fixtures — [FIN-3688](https://linear.app/finchclaims/issue/FIN-3688)
- 🟤 Priorities & Deadlines — [FIN-3689](https://linear.app/finchclaims/issue/FIN-3689)
- 🟦 Documentation — [FIN-3690](https://linear.app/finchclaims/issue/FIN-3690)
- 🟪 Inquiries — [FIN-4183](https://linear.app/finchclaims/issue/FIN-4183)

## Product: Session QA
- **Project id**: `88923778-470d-4c98-8bf8-77bc8e9370e9` · **Inboxes milestone**: `1e3e9e05-b3f7-4f79-8a2d-90f401f9a5d1`
- 🔴 Observed problems — [FIN-3961](https://linear.app/finchclaims/issue/FIN-3961)
- 🟠 Identified shortcomings — [FIN-3962](https://linear.app/finchclaims/issue/FIN-3962)
- 🔵 Feature requirements — [FIN-3963](https://linear.app/finchclaims/issue/FIN-3963)
- 🟢 Potential solutions — [FIN-3964](https://linear.app/finchclaims/issue/FIN-3964)
- 🟣 Feedback & Transcripts — [FIN-3965](https://linear.app/finchclaims/issue/FIN-3965)
- 🟡 Researches & Fixtures — [FIN-3966](https://linear.app/finchclaims/issue/FIN-3966)
- 🟤 Priorities & Deadlines — [FIN-3967](https://linear.app/finchclaims/issue/FIN-3967)
- 🟦 Documentation — [FIN-3968](https://linear.app/finchclaims/issue/FIN-3968)
- 🟪 Inquiries — [FIN-4184](https://linear.app/finchclaims/issue/FIN-4184)

*The `Inboxes` milestone here also holds **working** tickets that are not channels — `replay-watcher: run state (do not close)` ([FIN-3937](https://linear.app/finchclaims/issue/FIN-3937)) and the monthly digest ([FIN-3939](https://linear.app/finchclaims/issue/FIN-3939)). **Milestone membership alone does not identify a channel**; match the title too, or a pass will try to drain a run-state ticket.*

## Product: Dates & Notifications
- **Project id**: `dc2836c9-d7f4-4bae-b100-9d4a19680387` · **Inboxes milestone**: `d8dd3b8f-a83e-4a57-ba97-22b29325f21e`
- 🔴 Observed problems — [FIN-3758](https://linear.app/finchclaims/issue/FIN-3758)
- 🟠 Identified shortcomings — [FIN-3759](https://linear.app/finchclaims/issue/FIN-3759)
- 🔵 Feature requirements — [FIN-3760](https://linear.app/finchclaims/issue/FIN-3760)
- 🟢 Potential solutions — [FIN-3761](https://linear.app/finchclaims/issue/FIN-3761)
- 🟣 Feedback & Transcripts — [FIN-3762](https://linear.app/finchclaims/issue/FIN-3762)
- 🟡 Researches & Fixtures — [FIN-3763](https://linear.app/finchclaims/issue/FIN-3763)
- 🟤 Priorities & **Urgency** — [FIN-3764](https://linear.app/finchclaims/issue/FIN-3764)
- 🟦 Documentation — [FIN-3765](https://linear.app/finchclaims/issue/FIN-3765)
- 🟪 Inquiries — [FIN-4185](https://linear.app/finchclaims/issue/FIN-4185)

*Its 🟤 channel is titled **Priorities & Urgency**, not *Priorities & Deadlines* — the one live counter-example to assuming the default titles, and why the rule is match-by-intent.*

## Product: Mobile
- **Project id**: `88cc737d-1d55-4828-b57d-ee2a6325922f` · **Inboxes milestone**: `13b46022-fe8f-4d2d-8d65-eff05fc986f7`
- 🔴 Observed problems — [FIN-4047](https://linear.app/finchclaims/issue/FIN-4047)
- 🟠 Identified shortcomings — [FIN-4048](https://linear.app/finchclaims/issue/FIN-4048)
- 🔵 Feature requirements — [FIN-4049](https://linear.app/finchclaims/issue/FIN-4049)
- 🟢 Potential solutions — [FIN-4050](https://linear.app/finchclaims/issue/FIN-4050)
- 🟣 Feedback & Transcripts — [FIN-4051](https://linear.app/finchclaims/issue/FIN-4051)
- 🟡 Researches & Fixtures — [FIN-4052](https://linear.app/finchclaims/issue/FIN-4052)
- 🟤 Priorities & Deadlines — [FIN-4053](https://linear.app/finchclaims/issue/FIN-4053)
- 🟦 Documentation — [FIN-4054](https://linear.app/finchclaims/issue/FIN-4054)
- 🟪 Inquiries — [FIN-4186](https://linear.app/finchclaims/issue/FIN-4186)

## Product: Claims Data Consortium
- **Project id**: `466aecae-8b2c-4ee6-ab2e-594b08d7f83b` · **Inboxes milestone**: `f92a6c89-97f4-4b87-be4f-2ef63f84f8ce`
- 🔴 Observed problems — [FIN-4117](https://linear.app/finchclaims/issue/FIN-4117)
- 🟠 Identified shortcomings — [FIN-4190](https://linear.app/finchclaims/issue/FIN-4190)
- 🟢 Report and data-cut ideas — [FIN-4116](https://linear.app/finchclaims/issue/FIN-4116)
- ⚖️ Legal and counsel questions — [FIN-4115](https://linear.app/finchclaims/issue/FIN-4115)
- 🤝 Partner signal — [FIN-4114](https://linear.app/finchclaims/issue/FIN-4114)
- 🟣 Feedback & Transcripts — [FIN-4191](https://linear.app/finchclaims/issue/FIN-4191)
- 🟤 Priorities & Deadlines — [FIN-4192](https://linear.app/finchclaims/issue/FIN-4192)
- 🟦 Documentation — [FIN-4193](https://linear.app/finchclaims/issue/FIN-4193)
- 🟪 Inquiries — [FIN-4187](https://linear.app/finchclaims/issue/FIN-4187)

*Standardised 2026-08-26. It **keeps two channels of its own** — ⚖️ Legal and counsel questions and 🤝 Partner signal — because its subject genuinely produces those kinds and the standard set has no honest home for either; forcing the default eight would have deleted real design. The four original `Inbox: <what>` titles were renamed to the emoji convention, so the project is discoverable for the first time. Two collisions the bespoke pair creates are resolved in the channel descriptions and the handbook: 🟠 vs ⚖️ is **can you assert the gap, or are you asking whether it is allowed**; 🟣 vs 🤝 is **the whole artifact vs one attributed thing a partner said** — a 40-minute call goes to 🟣, the objection inside it to 🤝.*

---

## Product: API
- **Project id**: `d515309d-e846-47f9-b20c-e5672f856a07` · **Inboxes milestone**: `63526ea7-d318-4a2d-97e3-6c893d999919`
- 🔴 Observed problems — [FIN-4196](https://linear.app/finchclaims/issue/FIN-4196)
- 🟠 Identified shortcomings — [FIN-4197](https://linear.app/finchclaims/issue/FIN-4197)
- 🔵 Feature requirements — [FIN-4198](https://linear.app/finchclaims/issue/FIN-4198)
- 🟢 Potential solutions — [FIN-4199](https://linear.app/finchclaims/issue/FIN-4199)
- 🟣 Feedback & Transcripts — [FIN-4200](https://linear.app/finchclaims/issue/FIN-4200)
- 🟤 Priorities & Deadlines — [FIN-4201](https://linear.app/finchclaims/issue/FIN-4201)
- 🟦 Documentation — [FIN-4202](https://linear.app/finchclaims/issue/FIN-4202)
- 🟪 Inquiries — [FIN-4203](https://linear.app/finchclaims/issue/FIN-4203)

*Scaffolded 2026-08-26. **Platform scope only** (ruled by Yarik Fedin): identity and tenancy, request safety, queues, events, data and migrations, contracts, observability, deploy. **Not the product logic** — `apps/api` implements every product capability, so without that boundary the project would be unroutable. The test a drop is sorted by: **is the fix about how the system serves a request, or about what the answer should have been?** The second belongs to Claims & Policies, Document Extraction, Email Classification, Differ or Ask Finch. 🟡 Researches & Fixtures is deliberately absent — human-ratified AI oracles belong to the product projects.*

## Product: Console
- **Project id**: `1f8da919-6e79-4013-8c0f-a70623715ad9` · **Inboxes milestone**: `0492234f-1294-4f6c-89e6-4f71d981c594`
- 🔴 Observed problems — [FIN-4204](https://linear.app/finchclaims/issue/FIN-4204)
- 🟠 Identified shortcomings — [FIN-4205](https://linear.app/finchclaims/issue/FIN-4205)
- 🔵 Feature requirements — [FIN-4206](https://linear.app/finchclaims/issue/FIN-4206)
- 🟢 Potential solutions — [FIN-4207](https://linear.app/finchclaims/issue/FIN-4207)
- 🟣 Feedback & Transcripts — [FIN-4208](https://linear.app/finchclaims/issue/FIN-4208)
- 🟤 Priorities & Deadlines — [FIN-4209](https://linear.app/finchclaims/issue/FIN-4209)
- 🟦 Documentation — [FIN-4210](https://linear.app/finchclaims/issue/FIN-4210)
- 🟪 Inquiries — [FIN-4211](https://linear.app/finchclaims/issue/FIN-4211)

*Scaffolded 2026-08-26. **Back-office ops including the MCP surface** (ruled by Yarik Fedin): onboarding, per-org views, claims and document health, the data funnel, integrations, members, the staff access model, and the agent-facing MCP/OAuth flow that lives in the same app. The app is `apps/console` on `origin/dev` and **may not exist on a given branch** — read it with `git show origin/dev:`. The discriminator that decides most drops: **open the network call behind the page — if the wrong value is already in the API response, it is not a Console item.** Beware the funnel trap: that surface exists to reveal OTHER projects' losses, so a funnel finding is usually a high-quality report for someone else. 🟡 Researches & Fixtures deliberately absent, same reasoning as API.*

## Product: Design
- **Project id**: `a5d54950-c27d-4fce-9bf4-6317add325b0` · **Inboxes milestone**: `58ae0200-113f-488e-b5af-3df4ba0b9ec1`
- 🔴 Observed problems — [FIN-4238](https://linear.app/finchclaims/issue/FIN-4238)
- 🟠 Identified shortcomings — [FIN-4239](https://linear.app/finchclaims/issue/FIN-4239)
- 🔵 Feature requirements — [FIN-4240](https://linear.app/finchclaims/issue/FIN-4240)
- 🟢 Potential solutions — [FIN-4241](https://linear.app/finchclaims/issue/FIN-4241)
- 🟣 Feedback & Transcripts — [FIN-4242](https://linear.app/finchclaims/issue/FIN-4242)
- 🟤 Priorities & Deadlines — [FIN-4243](https://linear.app/finchclaims/issue/FIN-4243)
- 🟡 Researches & Fixtures — [FIN-4244](https://linear.app/finchclaims/issue/FIN-4244)
- 🟦 Documentation — [FIN-4245](https://linear.app/finchclaims/issue/FIN-4245)
- 🟪 Inquiries — [FIN-4246](https://linear.app/finchclaims/issue/FIN-4246)

*Scaffolded 2026-08-27. Operator **Rob Coyle** (`rob@finchclaims.com`), who authored both principles documents. **The product's design principles, vocabulary and target state** — the upstream context all design work draws on. Scope ruled by Yarik Fedin: the context layer plus typically-evergreen product design work, **mostly target state, not today's patches.** Two tests decide a drop, and both are in the handbook's `## Boundaries`: against Report Design System, **is a person using the product, or reading something an agent produced?**; against every product project, **is the screen wrong today, or is this where it should be going?** The name collides with its nearest neighbour, so expect misroutes in both directions until the tests are known. 🔴 and 🟡 were created on request but are the two the scoping argues against — a target-state project has no natural home for "this screen is wrong right now" and no fixtures to ratify; 🟡 carries its own provisionality in its Directions. Retire either if it sits empty across several passes.*
