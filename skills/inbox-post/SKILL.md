---
name: inbox-post
description: "Post an item into a project's intake inbox — resolves the Linear Project, classifies the item into the best-fit inbox channel, fills that channel's reporter template, and posts it as a comment. The quick front-door companion to /intake (which then organizes, marinates, and promotes). Triggers: \"drop this into the inbox\", \"post an inbox item\", \"file this to observed problems\", \"report this bug to intake\", \"inbox-post\"."
version: 1.0
tier: lightweight
args: "[item text or hint]"
---

Quick front-door for the intake system: drops one well-formed item into the right project's right inbox channel.

# /inbox-post Protocol (The Inbox Poster)

[!!!] This is a **sessionless utility** skill. No session directory, no logging, no debrief. It boots, resolves the target, fills the template, and posts — same pattern as `/session` and `/engine`.

## What it does (and does not)

*   **It does**: post one item into the correct intake **Inboxes** channel of the correct Linear Project — resolve the project, classify the item into the best-fit channel, fill that channel's reporter template from `assets/CHANNEL_TEMPLATES.md`, and post it as a comment via `§CMD_POST_TICKET_COMMENT`.
*   **It does NOT**: promote to a tracked ticket (that's `/intake`'s ripeness gate), organize/dedup, or execute the work. It just drops a clean, template-shaped item into the inbox for `/intake` to pick up.

## Reference assets (read at boot)

*   **`assets/INBOX_REGISTRY.md`** — the project → channel → ticket-id/URL map. The **fast path**: navigate straight to the channel ticket, no Linear discovery. If the target project/channel isn't listed (a new one), fall back to discovery — the Linear MCP has **no server-side filter for "projects with an Inboxes milestone"**, so: (1) `list_projects(includeMilestones: true)` and client-filter to projects whose milestones include one named `Inboxes`; (2) resolve the channel tickets by title — `list_issues` has **no milestone filter** either, so list the project's issues and filter by the 🔴🟠🔵🟢🟣🟡🟤🟦 channel-emoji titles. **Don't hardcode a count**: the set is contextual per project, and a stale count is how this file came to claim "6 channels" while 7 existed. When the fallback runs, **self-heal**: rewrite the discovered rows into `INBOX_REGISTRY.md` so the next call is fast again. The registry is a cache; Linear is the source of truth.
*   **`assets/CHANNEL_TEMPLATES.md`** — the per-channel reporter templates (shared core + channel-specific fields) to fill. **Note the duplication risk**: the project's **Inbox Handbook** document now holds the canonical reporter template Linear-side (`¶INV_CHANNEL_MACHINERY_IN_ONE_DOC`), so this file is a local convenience copy. If the two disagree, **the handbook wins** — it is what a human reads before dropping. Reconcile rather than silently following the local copy.
*   **The project's Inbox Handbook** (a Linear Document on the project) — the shared machinery: reporter template, what-happens-next, the other-inboxes list, how a comment becomes a ticket. **Channel descriptions are deliberately thin** and link here; a sparse channel is correct, not a missing spec.

## The 8 channels (classify the item into one)

*   🔴 **Observed problems** — a symptom / something seen going wrong.
*   🟠 **Identified shortcomings** — a diagnosed gap / structural weakness (why it's broken).
*   🔵 **Feature requirements** — a desired new behavior / capability (the what).
*   🟢 **Potential solutions** — a proposed fix / conjecture (the how).
*   🟣 **Feedback & Transcripts** — raw longform source (email / transcript / thread) dropped whole.
*   🟡 **Researches & Fixtures** — a human-ratified golden fixture (corrected AI output + evidence).
*   🟤 **Priorities & Deadlines** — a deadline / urgency / strategic weight the ranking can't see. An input, not a command — say *why*.
*   🟦 **Documentation** — docs missing, needed, wrong, or stale. **Both kinds**: our own engineering and process docs (runbooks, architecture, `CLAUDE.md`, engine directives) and product-facing docs (the Notion KB). Don't make the dropper classify which — triage sorts it.

*A project may not have all eight — the set is contextual (`¶INV_INBOX_IS_TICKETS`). Resolve the actual set from `INBOX_REGISTRY.md` or discovery; never assume a channel exists because it is listed here.*

## Algorithm

### 1. Resolve the project
*   If an `/intake` session is active, default to its project (from its `INTAKE.md`).
*   Else infer from the item + working context and match against `INBOX_REGISTRY.md`.
*   If ambiguous or multiple candidates, confirm via `AskUserQuestion` (offer the registry's projects).

### 2. Classify the channel
*   Read the item; pick the best-fit channel from the project's actual set. **Confirm via `AskUserQuestion`** — misfiling costs `/intake` an organize step, so a one-tap confirm is worth it. A single item may span channels → pick the **primary**, and note the cross-link in the comment body.
*   **Read BOTH the channel ticket's description and the Project description.** The steer is split across two surfaces and reading only the channel silently drops every project-level one.
    *   **`## Directions`** (`¶INV_DIRECTIONS_IN_DESCRIPTIONS` — on the channel ticket, and project-wide on the Project; absent on many projects, which is fine). They say what that project is chasing right now and what evidence it wants here — use them to break a close classification call, and to decide which optional template fields are worth asking for. Precedence: channel > project.
    *   **`## Ticketing Strategy`** (`¶INV_TICKETING_STRATEGY_IN_PROJECT` — Project description only). A project that wants fewer, chunkier tickets needs richer drops, because a thin drop is the one that ends up folded or marinating rather than graduating — so let it inform **which optional fields are worth one extra question**, and mention an obviously-related existing ticket in the body so `/intake` can fold rather than duplicate.
    *   **`## Stakeholders`** (Project description only; optional, absence is normal). Facts about people, never assignment rules — use them to fill "who reported it" and "who should hear about this" from context instead of asking the dropper, and to name an obvious owner in the body as a *fact* ("Dana owns this area"), never as an assignment. Never @-mention or notify anyone on the strength of a Stakeholders line alone.
    *   **Never gate the drop on any of them.** Half-formed is still welcome; a steer is not an entry fee. In particular, Ticketing Strategy governs what `/intake` *graduates*, never what a reporter is allowed to *report* — do not talk anyone out of dropping something because it looks too small.

### 3. Fill the template
*   Load that channel's template from `CHANNEL_TEMPLATES.md`. Pre-fill fields known from context (reporter, refs, app page URL). Ask for the **missing critical** fields in ONE `AskUserQuestion` round — app page URL, repro/expected-actual (Observed problems), who reported it, what it blocks. Optional fields left blank are fine (half-formed is welcome).
*   **Attachments are FILES on the issue, not private preview links (`§INV_ARTIFACT_URL_IS_PRIVATE_PREVIEW`).** A `claude.ai/…/artifact/…` URL (e.g. a `/prove` proof published to the Artifact tool) is **private to its author** — a teammate reading this inbox item cannot open it. So when the evidence is a rendered proof / report / screenshot on disk (e.g. `builds/<slug>_PROOF.html`, a PNG), plan to **upload the file to the issue** in step 4 and reference the attachment in the body — never paste the claude.ai preview URL as the evidence.
*   **Comment references in the body use `§FMT_TICKET_COMMENT_LINK`.** The `Source` line and any cross-reference to a specific comment (a 🟣 transcript passage, a related drop) renders as a labeled `#comment-<shortId>` deep-link, never a bare comment id or a link that only reaches the issue; ticket keys use `§FMT_TICKET_LINK`.

### 4. Post
*   Resolve the channel ticket ID from `INBOX_REGISTRY.md` (or discovery fallback).
*   **Attach the evidence files first (if any).** For each on-disk proof/screenshot/report the item leans on: `prepare_attachment_upload(issue, filename, contentType, size)` → PUT the raw bytes to the signed `uploadRequest.url` with its headers verbatim (`curl --data-binary @<path>`, 60s window) → `create_attachment_from_upload(issue, assetUrl, title, subtitle)`. Then reference that attachment by title in the comment body. Do NOT put a `claude.ai` artifact URL in the body as "the proof" (`§INV_ARTIFACT_URL_IS_PRIVATE_PREVIEW`).
*   Post the filled template as a comment via `§CMD_POST_TICKET_COMMENT` — the canonical path (subscribe-check → `save_comment` → sibling-notify), so the post is never a bare `save_comment`.

### 5. Report
*   Output the posted comment as a labeled link (`§FMT_TICKET_LINK`) + which project/channel it landed in. Done — no session ceremony.

## Keeping the registry fresh

`/intake` owns channel creation; this skill **consumes** the map. When channels/projects change (a new intake project, a renamed channel), refresh `assets/INBOX_REGISTRY.md`. The discovery fallback keeps the skill correct even when the registry lags — it's a cache, not the source of truth (Linear is).
