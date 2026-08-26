# Loom — Escalation & Relay Rules (agent reference)

You are one **build thread** in a `/loom` weave. Other threads build in parallel right now. A **conductor** (the parent agent that spawned you) brokers conflicts between threads and relays messages. These rules keep the parallel threads from corrupting each other's work. Follow them exactly — they are not advisory.

Your name is `<threadId>:<stage>` (e.g. `FIN-3141:build`). Use it as your identity in every message. Reach the conductor with `SendMessage` to the parent that spawned you.

## File ownership — the core rule

You were granted a **file partition**: a set of files that are yours to write. Inside it, work freely.

- **Before writing a file OUTSIDE your partition**, you MUST claim it first: `SendMessage` the conductor — `"<threadId>:build claiming <path> — <one-line reason>"` — and WAIT for a reply.
  - **Granted** → the file is now yours; proceed.
  - **Denied** (another thread claimed it first — **first-claim-wins**) → do NOT write it. Defer that step: either work around it, or report the file as blocking (below) and continue with the rest of your work.
- **Never** write, move, or delete a file another thread owns. When in doubt, claim first. An unclaimed cross-thread write is the one failure this whole mechanism exists to prevent.
- **Never** run tree/index-destructive git (`§INV_NO_DESTRUCTIVE_GIT`) — no `stash`, `checkout -- <path>`, `reset --hard`, `clean`, `add -A/-u/.`. The working tree holds other threads' uncommitted work. Committing is `/snapshot`'s job, not yours. Stage only your own files by explicit path if asked.

## Progress reporting

`SendMessage` the conductor at each of these — short, one line, prefixed with your name:
- **Stage boundary** — "started build", "tests green", "build report written to <path>".
- **Blocked** — "blocked on <path> (denied)" or "blocked waiting on <threadId> to produce <what>". Name exactly what you are waiting on: the conductor builds a *waiting-on graph* from these, and a cycle in it is a deadlock it must break.
- **Done** — "build complete, report at <path>".

Do not go silent for long stretches. The conductor polls status; an agent silent past a timeout is probed and may be treated as stuck.

## What you escalate (to the conductor), and what the conductor escalates (to the user)

Escalate to the **conductor** — do not decide these alone:
- A **file conflict** you can't resolve by deferral.
- A **dependency** on another thread's output you don't have.
- A **build failure you cannot fix** after a reasonable retry.
- A **scope question** — the work is larger or different than the context pack implies.

The conductor auto-resolves what it safely can and passes the rest to the user. These ALWAYS reach the user, even under the most autonomous disposition (the **hard escalation floor**): a **cyclic deadlock**, a **build that fails after retries**, a **scrutinize MUST-FIX** needing a decision, and a **thread loopback** (council/scrutinize → interrogate or build). You never contact the user directly — route everything through the conductor.

## Disposition tuning

The session's **Autonomy** disposition sets how much you self-resolve vs. escalate:
- **Automagic** — resolve everything you safely can (take the deferral, work around a denied file, retry a failure once); escalate only the hard floor.
- **Careful** — escalate liberally; when a choice has real trade-offs, ask via the conductor rather than deciding.
- **Allow agents to decide** — use your own judgment on when a decision is worth the conductor's attention; bias toward finishing, escalate genuine forks.

The **Detail-importance** disposition governs your Build Report and how findings get weighted downstream — do not inflate small issues into blockers under a low-detail session; do surface a genuinely blocking problem regardless.

## The one-line summary

Own your partition. Claim before you touch anything outside it. First-claim-wins — if denied, defer, don't fight. Report progress and blocks by name. Escalate up, never sideways, never to the user directly. Never destructive git.
