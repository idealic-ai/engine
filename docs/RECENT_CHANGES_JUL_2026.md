# Recent Engine Changes & New Skills — Last 3 Weeks (Jul 2 → Jul 23, 2026)

*The notable engine changes and new skills that landed in the **last three weeks**. Written for someone who knows the engine's session-owning skills (`/implement`, `/analyze`, `/fix` — each activating a session, running phases, writing a debrief) but may not have seen the recent additions.*

> **Scope note.** **Part 0** frames the broad v1→v2 arc *at a glance*; the rest of the document zooms into the **recent window** in detail. This is deliberately not a complete v1→v2 changelog — and one isn't recoverable (v1/v2 are informal, untagged; see Part 0). For the full operational story, see `ONBOARDING_V2.md` and `WHY_ENGINE.md`.

**At a glance**: 12 new skills · four engine-wide capability areas · the v2 release landed mid-window.

---

## TL;DR

If you left after v1, the one thing to internalize: **skills are no longer only heavyweight, session-owning protocols.** The engine grew a family of **lightweight "building-block" skills** — small, single-purpose, mostly *sessionless* tools that do one job, report, and stop, and that **compose** with each other and with your existing session skills. Around that, four engine-wide capabilities landed: **cross-session ticket discussion** (Linear), **multi-agent git safety**, **reusable composability primitives**, and an **AskUserQuestion decision-UX overhaul**.

---

## Part 0 — v1 → v2 at a glance (the arc these features sit in)

**Honest caveat first.** "v1" and "v2" are **informal, untagged** labels — Git has no marker for either, and the deployed v1 is a ~February-era GDrive snapshot that *cannot be reconstructed or precisely diffed* (`ONBOARDING_V2.md` §2). So this is the **conceptual shift plus the documented deltas**, not a commit-level "everything that changed" list — that isn't recoverable.

What the v2 runbook does pin down:

- **Scale.** v2 is **492 files** vs v1's **318** — a span far wider than this document's recent window.
- **The two-axis model v2 formalized.** *Mode* = what Claude reads (`engine local`/`remote` re-point `~/.claude/` symlinks; move no files) vs *Sync* = how content moves (`push`/`pull` = Git ↔ GitHub; `deploy` = local → GDrive). GDrive carries no `.git`, so it's a **consumer** channel — read the engine from it, don't develop there.
- **Skill growth came in waves.** Skills v1 never saw at all: `direct`, `do`, `improve-protocol`, `loop`, `session` (an earlier wave). Skills v2 **retired**: `dehydrate`, `reanchor`, `refine`. The **newest wave** — the building-block family in Part 1 — is what the recent window added.
- **Hook consolidation + settings migration.** v2 folded seven `pre-tool-use-*` hooks into one `pre-tool-use-overflow-v2.sh`, and moved engine hook wiring from the **committed** `.claude/settings.json` to the **gitignored** `.claude/settings.local.json` (the single cleanest v1→v2 delta). Because of this, a consumer must run `engine setup` after a release or their old hooks break on every tool call.

For the full operational story — release sequence, the hook-migration landmine, onboarding a developer vs. a consumer — see `ONBOARDING_V2.md`. **The rest of this document zooms into the newest wave.**

---

## Part 1 — The building-block skill family (12 new skills)

In v1, invoking a skill meant activating a session: setup → interrogation → planning → work → synthesis → debrief. Great for a feature, heavy for "just go find something out."

The recent work added a new **class** of skill (`tier: lightweight`) that:

- **Does one thing and stops** — investigates, or checkpoints, or opens a PR — then reports and gets out of the way. It never oversteps into a job that isn't its own.
- **Is mostly sessionless** — runs *within* your active session, writing its paper trail into that session's `builds/` folder rather than owning a session of its own.
- **Composes** — each is a link you can chain into the next (noted inline below).
- **Is offered, never forced** — governed by **`¶INV_OFFER_DONT_FORCE_SKILLS`**: a skill surfaces the building block as an *offer* at a decision point; you decide. No auto-chaining.

Here's the whole family, grouped by what each is for.

### Investigate & understand
- **`/probe`** — Quick, read-only investigation delegated to a subagent. State an *intent* (a question), it sweeps code / DB (read-only) / tickets and returns an answer-first report of ranked, evidence-backed findings you then triage. The lightweight, delegated counterpart to `/analyze`.
- **`/experiment`** — Hands-on hypothesis probe. Actually *tries* something in-tree (uncommitted, flagged, every touched file tracked) and returns a VERDICT (proved / disproved / inconclusive), then reverts or keeps it as a seed for `/implement`. Where `/analyze` reads, `/experiment` runs.
- **`/summarize`** — Inward, read-only recap of a chunk or the whole session. A reader subagent digests the trail into an intent-oriented report, then runs a two-way review (its uncertainties + a palette of questions you can fire back).
- **`/report`** — Present-tense **orientation**: where do things stand *right now*, what's blocked on you, what's next. Scans the raw transcript, reconciles against the orchestrator's bearings, and renders a work-trajectory graph. The "get me back in the flow" skill.
- **`/prove`** — Compiles the detective evidence of a *resolved* finding into a shareable visual **proof Artifact** (real rendered pages / screenshots / logs / overlays). It **trusts** the upstream finding and verifies only that the evidence is real and faithfully shown. The visual capstone of the investigative family — the natural next step after `/probe`, `/analyze`, `/experiment`, or `/fix`.

### Review & critique
- **`/scrutinize`** — Adversarially critiques a body of work with a subagent, triages each finding with you (fix / skip / defer), then applies approved fixes. The common partner to `/build`.
- **`/council`** — Convenes a diverse **expert panel** (N independent subagents from a persona palette) over a target, refutes its own MUST-FIX findings, and writes a consensus-tagged report. Read-only.

### Ship & checkpoint
- **`/build`** — Hands a scoped implementation task to a builder subagent with a **complete context pack** (goal, verbatim asks, plan slice, prior history, hard gates), returns a structured Build Report, and can chain straight into `/scrutinize`.
- **`/snapshot`** — Checkpoints work: a reviewer subagent *verifies* it (runs gates to confirm "done" claims), then on your confirm commits the reviewed files and posts a substantive ticket update. Verify → commit → report.
- **`/pr`** — Opens a context-maxed pull request: a PR-writer subagent reads commits, diff, linked tickets, and the `builds/` trail, then requests automated reviews (Copilot + the Codex connector) and relays them.
- **`/ticket`** — Turns in-context work into one or more premise-first Linear tickets (problem / intent / constraints / non-goals / acceptance), posted as sub-issues or new issues.

### Coordinate across sessions
- **`/communicate`** — Drives a **ticket discussion turn**: subscribe, ask/reply on a Linear ticket, notify local sibling agents, and keep a background watcher armed so replies wake you.

---

## Part 2 — Engine-wide capabilities & changes, by theme

*Themes A–C are **net-new** capabilities (they did not exist before this window); D–F are changes/refinements to things v1 already had.*

### Theme A — Cross-session ticket discussion (Linear) — **new**
A capability that **did not exist at all** before this window: agents can now hold a **Linear ticket conversation that survives across sessions**. One agent posts a question on a ticket; another agent — or a later session — is woken when the reply lands.
- **Subscribe / notify / watch + `/communicate`** — the core: subscribe a session to a ticket, notify sibling agents locally, and keep a background watcher armed that wakes you on new comments (an auto-watch gate arms it for you).
- **`§CMD_POST_TICKET_COMMENT`** — one canonical path for posting a comment, so the sibling-notify can never be forgotten. **`§FMT_TICKET_LINK`** — every ticket key renders as a labeled Linear link.
- *Refined within the same window* (not pre-existing): drain-before-re-arm killed a watcher spin-loop, a dirty-ticket indicator was added to the statusline, the queue auto-drains on wake, and sub-agents are exempt from the gate.

### Theme B — Multi-agent git safety — **new**
A safety net that **did not exist before**, captured from a real incident (an agent reverted 8 off-lane files with `git checkout`):
- **`¶INV_NO_DESTRUCTIVE_GIT`** — a **one-strike PreToolUse guard** over the entire tree/index-destructive git family (`stash`, `checkout -- `, `reset --hard`, `clean`, `rm`, force-push, index sweeps). The tree is always dirty with parallel-agent work; destructive git is now a stop-and-ask.
- **`¶INV_ADJACENCY_IS_NOT_OWNERSHIP`** — you can't infer who owns a file from proximity/mtime; attribute from the owner's own record, or ask.
- **Per-sub-agent hook state** — PreToolUse hook state scoped via `agent_id`, ending shared-transcript cross-talk between parallel agents.

### Theme C — Composability primitives (reusable `§CMD` offers) — **new**
New shared steps so that, instead of each skill re-implementing "offer a review" or "draw a graph," any skill declares one line:
- **`§CMD_OFFER_COUNCIL_REVIEW`** — offer a `/council` panel on a just-produced artifact (wired into 6 callers).
- **`§CMD_OFFER_GRAPH_VIZ`** — offer a `/graph` flowgraph of a just-produced structure; context-gated to auto-skip linear artifacts (5 callers).
- **`§CMD_ELICIT`** — a disclosure layer that surfaces the agent's own judgment per finding/decision as a triaged card.
- **`§CMD_LOG_SKILL_INVOCATION`** — a crash-recovery breadcrumb written right before a sub-agentic skill dispatches its subagent.

### Theme D — AskUserQuestion decision-UX overhaul — *reworked*
`AskUserQuestion` already existed; how the engine *uses* it was substantially reworked:
- **`§FMT_DECISION_CARD`** — a heading-per-card layout for rich per-item decisions.
- **Complete context in the question body** (`§CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT`) — killed the old "context block above, terse options below" duality; the question now stands alone.
- **`§FMT_ANSWER_GRADATION`** — compact glyph tags (risk · confidence · effort · ★-recommended) leading option labels.

### Theme E — Session & hook infrastructure — *fixes & hardening*
- **Chunked SessionStart preload** + full `configure_hooks` wiring.
- **Repo-root session anchoring** via a `.claude` marker, plus **stray-session reaping** (merges bug-created `sessions/` dirs).
- **Dehydrate/restart** now kills the lingering watchdog in the tmux path.
- Fixed a **hook error that fired on every tool call** for consumers (root-config linkage), and **bounded stdin reads** so held-open pipes can't hang session subcommands.

### Theme F — Integrity & flow reframes — *reframes & fixes*
- **Restored the real JSON-Schema validator** — proof-schema enforcement had been a *silent no-op* (`¶PTF_SILENT_NO_OP_TOOLING`); it validates again.
- **`/analyze` calibration reframe** — the calibration exit became a gap-driven forward fork (DEEPEN vs. SYNTHESIZE) instead of burying "more analysis" as a backward jump. *(This is the exact flow that produced this document.)*
- **`/review` narrative mode** (separated from the daily mode); **`/pr`** also polls + relays the Codex-connector review (gated on its 👀 reaction); the AFK idle timeout was effectively disabled.

---

## Part 3 — The v2 release (mid-window landmark)

The **v2 release + onboarding runbook** shipped inside this window — alongside the destructive-git guard, the validator restoration, and `/review` narrative mode — and was immediately followed by the promotion of the first eight building-block skills. If you're re-onboarding, `ONBOARDING_V2.md` is the front door.

---

## Notes

- **`/prove`** currently lives only in `~/.claude/skills/` and isn't yet committed to the engine repo — a small loose end.
- The outer `~/.claude` git repo is stale/non-live, so all durable engine history lives in `~/.claude/engine`.
