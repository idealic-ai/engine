# Inbox Registry — intake projects → channels → tickets

Fast-path navigation map for `/inbox-post`. Project → its `Inboxes` channel tickets (FIN-key + URL). A **cache**, not the source of truth — Linear is. When it's stale or missing a target, the skill falls back to live discovery (`list_projects(includeMilestones)` → client-filter `Inboxes`; channel tickets by title) and self-heals this file.

*Channels:* 🔴 Observed problems · 🟠 Identified shortcomings · 🔵 Feature requirements · 🟢 Potential solutions · 🟣 Feedback & Transcripts · 🟤 Priorities & Deadlines · 🟡 Researches & Fixtures · 🟦 Documentation

Not a fixed set in practice — channel titles vary slightly per project (Claims & Policies uses "Feature **& capability** requirements"). Match by intent, not by exact title.

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

The short-lived team-level handbook (`1292d6ee-5819-4354-9892-49f0d3d388a6`, slug `7f5f9c302585`) is **retired** — a team-attached document has no home in the Linear UI, so nothing surfaced it from a project. If you find a channel still linking slug `7f5f9c302585`, repoint it at its own project's handbook above.

Match a handbook by **slugId**, not by the words in the URL: retitling a Linear document re-slugs the human-readable segment while the 12-hex slugId stays put.

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
