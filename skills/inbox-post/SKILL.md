---
name: inbox-post
description: "Post an item into a project's intake inbox — resolves the Linear Project, classifies the item into the best-fit inbox channel, fills that channel's reporter template, and posts it as a comment — then triangulates what it posted and replies to the drop with the finding, so an item arrives with an answer under it instead of waiting for the next wave. The front-door companion to /intake (which then organizes, marinates, and promotes). Triggers: \"drop this into the inbox\", \"post an inbox item\", \"file this to observed problems\", \"report this bug to intake\", \"inbox-post\"."
version: 1.0
tier: lightweight
args: "[item text or hint]"
---

Quick front-door for the intake system: drops one well-formed item into the right project's right inbox channel.

# /inbox-post Protocol (The Inbox Poster)

[!!!] This is a **sessionless utility** skill. No session directory, no logging, no debrief. It boots, resolves the target, fills the template, and posts — same pattern as `/session` and `/engine`.

## What it does (and does not)

*   **It does**: post one item into the correct intake **Inboxes** channel of the correct Linear Project — resolve the project, classify the item into the best-fit channel, fill that channel's reporter template from `assets/CHANNEL_TEMPLATES.md`, and post it as a comment via `§CMD_POST_TICKET_COMMENT`.
*   **It also**: triangulates what it just posted, by default, and replies to the drop with the finding (step 5). The drop lands first and is never blocked on the investigation.
*   **It does NOT**: promote to a tracked ticket (that's `/intake`'s ripeness gate), organize/dedup, or execute the work. It drops a clean, template-shaped item into the inbox for `/intake` to pick up — now with an answer already under it.

## Reference assets (read at boot)

*   **`assets/INBOX_REGISTRY.md`** — the project → channel → ticket-id/URL map. The **fast path**: navigate straight to the channel ticket, no Linear discovery. If the target project/channel isn't listed (a new one), fall back to discovery — the Linear MCP has **no server-side filter for "projects with an Inboxes milestone"**, so: (1) `list_projects(includeMilestones: true)` and client-filter to projects whose milestones include one named `Inboxes`; (2) resolve the channel tickets by title — `list_issues` has **no milestone filter** either, so list the project's issues and filter by the 🔴🟠🔵🟢🟣🟡🟤🟦🟪📣🟩 channel-emoji titles, **and by an `Inbox:` title prefix**. The prefix is a second live convention, not a legacy one: *Product: Claims Data Consortium* names every channel `Inbox: <what>` with no emoji at all, so an emoji-only filter finds none of that project's channels. **Extend both lists whenever a channel is added** — an unlisted glyph is a channel that is invisible to discovery. **Don't hardcode a count**: the set is contextual per project, and a stale count is how this file came to claim "6 channels" while 7 existed. When the fallback runs, **self-heal**: rewrite the discovered rows into `INBOX_REGISTRY.md` so the next call is fast again. The registry is a cache; Linear is the source of truth.
*   **`assets/CHANNEL_TEMPLATES.md`** — the per-channel reporter templates (shared core + channel-specific fields) to fill. **Note the duplication risk**: the project's **Inbox Handbook** document now holds the canonical reporter template Linear-side (`¶INV_CHANNEL_MACHINERY_IN_ONE_DOC`), so this file is a local convenience copy. If the two disagree, **the handbook wins** — it is what a human reads before dropping. Reconcile rather than silently following the local copy.
*   **The project's Inbox Handbook** (a Linear Document on the project) — the shared machinery: reporter template, what-happens-next, the other-inboxes list, how a comment becomes a ticket. **Channel descriptions are deliberately thin** and link here; a sparse channel is correct, not a missing spec.

## The channels (classify the item into one)

*   🔴 **Observed problems** — a symptom / something seen going wrong.
*   🟠 **Identified shortcomings** — a diagnosed gap / structural weakness (why it's broken).
*   🔵 **Feature requirements** — a desired new behavior / capability (the what).
*   🟢 **Potential solutions** — a proposed fix / conjecture (the how).
*   🟣 **Feedback & Transcripts** — raw longform source (email / transcript / thread) dropped whole.
*   🟡 **Researches & Fixtures** — a human-ratified golden fixture (corrected AI output + evidence).
*   🟤 **Priorities & Deadlines** — a deadline / urgency / strategic weight the ranking can't see. An input, not a command — say *why*.
*   🟦 **Documentation** — docs missing, needed, wrong, or stale. **Both kinds**: our own engineering and process docs (runbooks, architecture, `CLAUDE.md`, engine directives) and product-facing docs (the Notion KB). Don't make the dropper classify which — triage sorts it.
*   🟪 **Inquiries** — a question, asked of the team. Anything: how a document is meant to be read, what a number in the data means, why the app behaves as it does, where the product is headed. No evidence required and half-formed is welcome — this is the one channel where **not knowing is the whole content**. The asker gets an answer as a reply, so this channel is never skipped in step 5.

*A project may not have all of them — the set is contextual (`¶INV_INBOX_IS_TICKETS`). Resolve the actual set from `INBOX_REGISTRY.md` or discovery; never assume a channel exists because it is listed here.*

## Algorithm

### 1. Resolve the project
*   If an `/intake` session is active, default to its project (from its `INTAKE.md`).
*   Else infer from the item + working context and match against `INBOX_REGISTRY.md`.
*   If ambiguous or multiple candidates, confirm via `AskUserQuestion` (offer the registry's projects).

### 2. Classify the channel
*   Read the item; pick the best-fit channel from the project's actual set. **Confirm via `AskUserQuestion`** — misfiling costs `/intake` an organize step, so a one-tap confirm is worth it. A single item may span channels → pick the **primary**, and note the cross-link in the comment body.
*   **Read the channel ticket's description, the Project description, and the project's Inbox Handbook.** The steer is split across three surfaces and reading only the channel silently drops every project-level one.
    *   **`## Directions`** (`¶INV_DIRECTIONS_IN_DESCRIPTIONS` — on the channel ticket, and project-wide on the Project; absent on many projects, which is fine). They say what that project is chasing right now and what evidence it wants here — use them to break a close classification call, and to decide which optional template fields are worth asking for. Precedence: channel > project. At the project tier it is **product steer only**; the per-item triage recipe is the handbook's `## What triage will chase`.
    *   **`## Ticketing Strategy`** (`¶INV_TICKETING_STRATEGY_IN_HANDBOOK` — the project's **Inbox Handbook**; on a project predating the move it may still sit on the Project description, so fall back there). A project that wants fewer, chunkier tickets needs richer drops, because a thin drop is the one that ends up folded or marinating rather than graduating — so let it inform **which optional fields are worth one extra question**, and mention an obviously-related existing ticket in the body so `/intake` can fold rather than duplicate.
    *   **`## Stakeholders`** (Project description only; optional, absence is normal). Facts about people, never assignment rules — use them to fill "who reported it" and "who should hear about this" from context instead of asking the dropper, and to name an obvious owner in the body as a *fact* ("Dana owns this area"), never as an assignment. Never @-mention or notify anyone on the strength of a Stakeholders line alone.
    *   **Never gate the drop on any of them.** Half-formed is still welcome; a steer is not an entry fee. In particular, Ticketing Strategy governs what `/intake` *graduates*, never what a reporter is allowed to *report* — do not talk anyone out of dropping something because it looks too small.

### 3. Fill the template
*   Load that channel's template from `CHANNEL_TEMPLATES.md`. Pre-fill fields known from context (reporter, refs, app page URL). Ask for the **missing critical** fields in ONE `AskUserQuestion` round — app page URL, repro/expected-actual (Observed problems), who reported it, what it blocks. Optional fields left blank are fine (half-formed is welcome).
*   **Evidence rides with the DROP, never a private preview (`§INV_PROVE_S3_URL_IS_SHAREABLE`, `§INV_CHANNEL_EVIDENCE_RIDES_THE_COMMENT`).** When the evidence is a rendered proof / report / screenshot / source document on disk (e.g. `builds/<slug>_PROOF.html`, a PNG, the transcript you are summarizing), plan to **upload it and embed it in the comment body** in step 4 — never as a ticket-level attachment. A `/prove` proof also has a public **S3 URL** (uploaded via `assets/publish-s3.sh`) a teammate can open directly — reference that if you have it. Either way the reader must be able to open the evidence without the author's session, **and** be able to tell which drop it belongs to.
*   **If you are describing something you read in a file, attach that file.** A summary is not a substitute for the source — this is the handbook's own rule, and it binds the poster as much as a human dropper. A restructured or condensed version in the comment body is fine *alongside* the source, never *instead of* it.
*   **Comment references in the body use `§FMT_TICKET_COMMENT_LINK`.** The `Source` line and any cross-reference to a specific comment (a 🟣 transcript passage, a related drop) renders as a labeled `#comment-<shortId>` deep-link, never a bare comment id or a link that only reaches the issue; ticket keys use `§FMT_TICKET_LINK`.

### 4. Post
*   Resolve the channel ticket ID from `INBOX_REGISTRY.md` (or discovery fallback).
*   **Upload each evidence file, then embed it in the comment body — one post, not two** (`§INV_CHANNEL_EVIDENCE_RIDES_THE_COMMENT`). Per file, **one at a time** (a signed URL expires in 60s, so never batch the prepares): `prepare_attachment_upload(issue, filename, contentType, size)` → PUT the raw bytes to `uploadRequest.url` with **every** signed header verbatim, casing included (`curl --data-binary @<path>`; omitting or altering one returns 403) → keep the returned `assetUrl`. Once you hold every `assetUrl`, write them into the comment markdown as labeled links (`[📄 <filename>](<assetUrl>)`) and post that body. **Put each link alone in its own block — nothing else on that line**: Linear renders an attachment as a preview *card* only when the link is the entire paragraph, so a link trailed by a description, or one sitting inside a bullet, silently degrades to plain inline text.
    *   **LINK them — a prose mention is not a link.** Every file you uploaded must appear as a real, clickable markdown link inside the posted body. *"📎 Attachments — the full report and a visual proof"* with no URL behind it is the defect, not the fix: the reader has nothing to click, and an uploaded asset no comment links to is **unreachable in the Linear UI entirely**. **Mechanical self-check before posting: for each file you uploaded, does its `assetUrl` appear inside a markdown link in the body you are about to send?** If not, the post is incomplete — fix it before posting, not after.
    *   **Do NOT call `create_attachment_from_upload`.** That creates a *ticket*-level attachment. An intake channel is a **frozen collector** holding hundreds of comments, so a ticket-level attachment is severed from the drop it came from the moment there are two of them — and "reference it by title in the body" is provenance by convention, which degrades silently rather than failing loudly. Embedding the `assetUrl` **is** the comment attachment; it is exactly what the Linear UI's in-comment upload does, and there is no separate comment-attachment API.
    *   *(The inverse holds where the target is a **worked** ticket — `/snapshot`'s closing debrief, `/ticket`'s evidence — where `create_attachment_from_upload` is correct because the attachment belongs to the ticket as a whole. `/inbox-post` never writes to one of those.)*
    *   If the evidence is a `/prove` proof with a public **S3 URL**, referencing that URL in the body is also fine (`§INV_PROVE_S3_URL_IS_SHAREABLE`) — the point is the reader can open it without the author's session.
*   Post the filled template as a comment via `§CMD_POST_TICKET_COMMENT` — the canonical path (subscribe-check → `save_comment` → sibling-notify), so the post is never a bare `save_comment`.

### 5. Triangulate what you just posted — the default, not the exception

**The drop is already safe.** It was posted in step 4 and nothing below can undo it. Everything here is additive: if the investigation is skipped, interrupted or fails, the item still stands in the channel exactly as dropped.

**Run it when the drop has something checkable in it** — it asserts something about the product, reports a defect, or is too thin to act on. **Skip it, and say so in one line**, for a pure feature idea with no claim in it, a documentation request, or an item the thread has already answered. The skip line matters: *"not triangulated — a feature request, nothing to check"* tells the next reader the silence was a decision.

**The one-line skip note covers those three cases and nothing else.** Any other reason not to dispatch — a harness that will not let you spawn a sub-agent, a worry about tokens or wall-clock, a belief that the item is obvious — is a **deviation from the protocol**, and it goes through `§CMD_REFUSE_OFF_COURSE`: state the conflict, offer the choice, let the user decide. **Never announce a substitution in one line and proceed.** The skip note and a self-authorized skip look identical on the page, which is exactly why the second one has to stop and ask.

*Measured, on this skill:* a run hit a harness rule against dispatching sub-agents, read the user's follow-up question as licence to answer inline instead, and wrote a one-line note saying so. The inline answer then asserted a false premise — *"there is no `Differ` label"*, from a `list_issue_labels` call that omitted `team` and reported `hasNextPage: false` — and nothing in the run caught it, because a single pass has nothing to disagree with. A human spotted it on sight.

**🟪 Inquiries is never skipped, and the skip-list does not reach it.** An inquiry looks like the "documentation request" case above and is not one: a doc request asserts that something is written down wrongly, while an inquiry asserts nothing at all — someone does not know something and is asking. **The answer IS the channel's output**, so skipping the investigation empties the channel of its purpose. Two things change for a 🟪 drop:
   *   **The report is an ANSWER, not a defect verdict.** `/inbox-triangulate` is written around a finding — "the defect, its evidence, its breadth, whether it is still live, and what to do". Pass the question as the subject and say plainly that the deliverable is the answer to it, with its evidence and its confidence. **"No answer exists yet" is a complete and valuable result**, not a failed run.
   *   **A 🟪 item normally graduates to nothing.** It is closed by being answered. It leaves the channel only when the investigation finds the answer *should* exist and does not — at which point it has become a 🔴 / 🟠 / 🟦 item, and is re-dropped as one with the answer thread linked.

**Why the default is ON, against `/inbox-triangulate`'s own "never universally".** That warning is aimed at running it over a backlog nobody will act on, where matching answers manufacture agreement theatre. A drop someone just took the trouble to write is the opposite case. **Measured, on this project**: two drops on [FIN-3445](https://linear.app/finchclaims/issue/FIN-3445) sat **17 days with no reply**, and the triage that eventually ran found the answer had existed the whole time — folded into a ticket the reporter had no way to learn about. A sibling drop on another channel got its answer in 5½ hours. The cost of the second angle is real; the cost of a drop nobody answers is a reporter who stops dropping.

**How:**
1.  **Dispatch `/inbox-triangulate` on the comment you just posted**, passing its **comment id** and the channel ticket. It runs the two angles and, if they need reconciling, the adjudicator.
2.  **The result posts as a REPLY on your drop** — `parentId` = the comment you just created — never as a new top-level comment on the channel. A channel is a frozen collector of hundreds of drops; an answer that lands at the top is severed from its question.
3.  **Wait for it, and say you are waiting.** Today `/inbox-post` runs in the main loop, so the sub-agents are children of this live session and die with it. Blocking is what makes the reply reliable. Report progress rather than going silent for ten minutes — the runs are ~10–15 minutes and ~2× a single triage in tokens, and a reader who does not know that will assume something hung.
4.  **If the user interrupts, say plainly what survived**: the drop is posted, the reply is not. Never imply an investigation landed when it did not (`¶INV_TERMINAL_PRODUCER_POSTS`).

**"I already know the answer" is NOT a reason to skip — it is a reason the run is cheap.**

This is the likeliest way step 5 fails, and it does not look like skipping. You read the drop, you can see how to check it, the check is a couple of queries, and dispatching two sub-agents to re-derive what you could produce in a minute feels like waste. It is not waste, for one reason: **your inline answer is one angle, run once, with nothing to disagree with it.** That is the precise thing triangulation exists to distrust — a finding that survives because only one method was ever applied to it, and a confident wrong answer is indistinguishable from a confident right one at the moment you write it.

So when you already have an answer: **dispatch anyway, and pass what you found in as a starting position** (`¶INV_STARTING_POSITION_NOT_A_FENCE` in spirit — the angles may confirm it, extend it, or refute it, and any of the three is worth having). A run that begins from a drafted answer is *faster and cheaper* than one starting cold, not redundant. Say plainly in the brief that the answer is a draft to be attacked, not a conclusion to be corroborated — otherwise both angles will agree with you and you will have manufactured the agreement theatre the skill warns about elsewhere.

**If the environment genuinely forbids the dispatch** — a harness rule against spawning sub-agents, a missing credential the preflight names — that is a **STOP and report**, not a licence to substitute. Say what is blocked, say the drop stands and the investigation is owed, and route the choice to the user through `§CMD_REFUSE_OFF_COURSE`. Reporting an inline answer as though it were the triangulated one is the failure `¶INV_TERMINAL_PRODUCER_POSTS` is there to prevent.

**Two things to pass the run, because they change what it should conclude:**
*   **The thread has no replies yet — you just created it.** `¶INV_REPLIES_ARE_SIGNAL` tells a triage run that a body without its replies means the caller withheld material. Here there are none to withhold, so say so; otherwise the run reports a gap that does not exist.
*   **Relate is the highest-value step on a fresh drop**, and it is the one that would have closed the 17-day gap: the answer may already be on the record, in a ticket the reporter cannot see from their own thread.

### 6. Report
*   Output the posted comment as a labeled link (`§FMT_TICKET_LINK`) + which project/channel it landed in.
*   Then the investigation's outcome: the reply's link if it posted, the one-line reason if it was skipped, or what survived if it was interrupted. **Both facts, always** — a report that names only the drop reads as though nothing was ever going to follow it.

## Keeping the registry fresh

`/intake` owns channel creation; this skill **consumes** the map. When channels/projects change (a new intake project, a renamed channel), refresh `assets/INBOX_REGISTRY.md`. The discovery fallback keeps the skill correct even when the registry lags — it's a cache, not the source of truth (Linear is).
