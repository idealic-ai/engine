# Inbox Registry — intake projects → channels → tickets

Fast-path navigation map for `/inbox-post`. Project → its `Inboxes` channel tickets (FIN-key + URL). A **cache**, not the source of truth — Linear is. When it's stale or missing a target, the skill falls back to live discovery (`list_projects(includeMilestones)` → client-filter `Inboxes`; channel tickets by title) and self-heals this file.

*Channels:* 🔴 Observed problems · 🟠 Identified shortcomings · 🔵 Feature requirements · 🟢 Potential solutions · 🟣 Feedback & Transcripts · 🟤 Priorities & Deadlines · 🟡 Researches & Fixtures · 🟦 Documentation · 🟪 Inquiries · 📣 Announcements · 🟩 Chores & tracker hygiene

Not a fixed set in practice — channel titles vary slightly per project (Claims & Policies uses "Feature **& capability** requirements"). Match by intent, not by exact title. **The discovery fallback filters issue titles by these emojis — extend that list whenever a channel is added, or the new one is invisible to discovery.** It also matches an **`Inbox:` title prefix**, which is a second live convention rather than a legacy one: *Product: Claims Data Consortium* names its channels `Inbox: <what>` with no emoji at all, so an emoji-only filter finds none of them. Squares twin circles by design (🟦 with 🔵, 🟩 with 🟢, 🟪 with 🟣): every color was already taken by a circle, so a twin is the convention rather than a collision. 🟪 twins 🟣 because both are raw human voice arriving unprocessed — 🟣 is what someone **said**, 🟪 is what someone **asked**.

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
| Claims Data Consortium | **none** | — |

The short-lived team-level handbook (`1292d6ee-5819-4354-9892-49f0d3d388a6`, slug `7f5f9c302585`) is **retired** — a team-attached document has no home in the Linear UI, so nothing surfaced it from a project. If you find a channel still linking slug `7f5f9c302585`, repoint it at its own project's handbook above.

**Claims Data Consortium has no handbook.** Its channels link to nothing, so a `/inbox-post` run there has no shared machinery to read and its 🟪 ticket ships without the usual blockquote. That project was scaffolded outside the intake conventions and has drifted from all of them at once — naming, handbook, discoverability. Writing it one is real work, not a patch.

Match a handbook by **slugId**, not by the words in the URL: retitling a Linear document re-slugs the human-readable segment while the 12-hex slugId stays put.

## Slack announce channels

The wave's `§PASS_HEARTBEAT` announce is **per-project** — pass the name below as `engine slack-post --channel '#name'`. Do **not** leave the announce to `$SLACK_INTAKE_CHANNEL`: it is a single global var, so relying on it makes every project post to one channel, and it is only read when **exported** (`--env-file` extracts the token only, and a channel left in the env file resolves to empty).

*   **Claims & Policies** — `#engineering-alerts`
*   **Document Extraction** — `#engineering-alerts`
*   **Email Classification** — `#engineering-alerts`
*   **Differ** — `#engineering-alerts`
*   **Intake System** — `#engineering-alerts`
*   **Preloss B2B** — `#intake-alerts`
*   **Report Design System** — `#intake-alerts`
*   **Ask Finch** — **UNSET**
*   **Session QA** — **UNSET**
*   **Dates & Notifications** — **UNSET**
*   **Mobile** — **UNSET**
*   **Claims Data Consortium** — **UNSET**

The first five were moved from `#intake-alerts` to `#engineering-alerts` on 2026-08-17 (decided: Yarik Fedin) — intake heartbeats belong with the rest of the engineering alerting rather than in a channel of their own. **The rows below it are unresolved because nobody has said where those projects belong** — they are newer than that decision, and a guess here would silently send a project's heartbeat somewhere nobody watches. Preloss B2B and Report Design System still name `#intake-alerts` from their bootstrap; the five marked **UNSET** have never had a destination chosen at all, and a pass on one of them should ask rather than default. Extending the 2026-08-17 `#engineering-alerts` decision to them is a reasonable guess and is still a guess.

This is the **announce** destination only — one per project, where a completed pass posts its heartbeat. It is a different thing from the channels a wave *reads* for ambient context, which are per-project and live in each project's Inbox Handbook under `## Related Slack Channels` (`¶INV_CHANNEL_MACHINERY_IN_ONE_DOC`). A project may read several channels and announces to exactly one.

**Names, never ids.** `slack-post` resolves a name to the id Slack's API requires and keeps the id internal — no channel id belongs in config or in anything a human reads. The tradeoff is that a **rename breaks the row**: resolution fails loudly rather than guessing, so treat renaming an intake channel as a config change and update it here.

Verify a project's Slack setup before its first announce: `engine slack-post --verify --channel '#name'` checks token, scopes, channel and bot membership, and self-joins when `channels:join` is granted.

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

*🔴 Observed problems and 🟡 Researches & Fixtures were deliberately NOT created — the project is in discovery with no product in front of customers, so both would sit empty, and an empty channel makes a dropper hesitate over an irrelevant choice every time. Create them when a design partner is live and there is something to observe. 🟣 Feedback & Transcripts is the primary channel here, not a secondary one: most drops are whole discovery calls.*

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
- Inbox: Observed problems — [FIN-4117](https://linear.app/finchclaims/issue/FIN-4117)
- Inbox: Report and data-cut ideas — [FIN-4116](https://linear.app/finchclaims/issue/FIN-4116)
- Inbox: Legal and counsel questions — [FIN-4115](https://linear.app/finchclaims/issue/FIN-4115)
- Inbox: Partner signal (Brian, Phil, founding firms) — [FIN-4114](https://linear.app/finchclaims/issue/FIN-4114)
- 🟪 Inquiries — [FIN-4187](https://linear.app/finchclaims/issue/FIN-4187)

*The exception on every axis. Its four original channels are named `Inbox: <what>` with **no emoji**, so the emoji-only discovery filter finds none of them — match the `Inbox:` prefix too. It has **no Inbox Handbook**, so its channels link to nothing. Its channel set is hand-designed for a specific effort (a printed report and a founding-member product) rather than scaffolded from the default. 🟪 Inquiries was created here in the **standard** emoji form deliberately, to start pulling the project toward the shared convention; it also has to earn its place against two neighbours that already look like question channels — `Inbox: Legal and counsel questions` (needs a lawyer, carries legal risk) and `Inbox: Partner signal` (what a partner told us, not what we want to ask).*
