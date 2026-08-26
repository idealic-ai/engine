---
name: interrogate
description: "Run a structured interrogation on a subject — depth-selected rounds of targeted questions with between-round context and an exit gate — then hand back a Q&A digest. The interactive, reusable front-half of any skill's pre-flight, extracted as a building block: /loom calls it per thread to scope each build. Rides the active session (logs rounds to its DIALOGUE.md); runs standalone too. It gathers and reports, never plans, edits, or files. Triggers: \"interrogate this\", \"ask me some questions first\", \"scope this before we build\", \"interrogate the requirements\", \"pin down the assumptions\"."
version: 1.0
tier: lightweight
args: "[<subject / topic to interrogate>] [--depth quick|standard|deep] [-- <what a good answer unlocks / focus>]"
---

Pull the assumptions out of a subject before anyone builds against it. `/interrogate` takes a **subject** — a ticket, a feature, a decision — and runs the engine's structured interrogation over it: pick a depth, ask rounds of targeted questions (each round carrying the prior round's recap as in-body context), stop at an exit gate. It hands back a **digest** — the questions, your answers, and a short resolved-scope synthesis — that a caller reads to build a context pack.

This is the interactive, reusable front-half of a skill's pre-flight, lifted out as its own primitive. Where a full protocol skill embeds `§CMD_INTERROGATE` inside its Interrogation phase, `/interrogate` exposes exactly that mechanism to any caller. `/ultrabuild` invokes it **per thread** to scope each ticket's build; a human runs it ad-hoc to think a problem through out loud. As a **building block** it gathers and reports — it never writes a plan, edits code, or files a ticket. What happens with the digest next is the caller's call.

*Crucial constraint:* `/interrogate` does NOT own a session. It reads the *active* session's context and writes its digest into that session's folder; when a session's DIALOGUE.md exists, the interrogation rounds log there automatically (the `AskUserQuestion` hook handles it). Run with no active session, it still interrogates and still writes a digest — it just skips the session logging.

# /interrogate Protocol

## 1. Frame the Subject, Depth & Trail

**A. The Subject** (what we're interrogating)
Resolve it from the arguments, else the active session / recent conversation. State it as one line naming the thing whose assumptions we're pulling out — a ticket (`FIN-3141: …`), a feature, a design decision. Text after `--` sharpens what a good answer unlocks and steers topic selection.
*Constraint:* if you cannot name the subject in one sentence, ask ONE `AskUserQuestion` to pin it. A vague subject produces a vague digest — the whole skill hinges on this.

**B. The Depth** (how many rounds, minimum)
- `--depth quick` → the `Short` minimum (a few rounds). Use for a tight, per-thread scope where the direction is mostly clear.
- `--depth standard` → the `Medium` minimum.
- `--depth deep` → the `Long` minimum.
- **No `--depth` arg** → present the depth menu (`§ASK_INTERROGATION_DEPTH`) and let the user choose. A machine caller (e.g. `/ultrabuild`) always passes `--depth` so no menu blocks the loop.

**C. The Trail**
If a session is active, set `<trailDir> = <sessionDir>/builds/` and mint a short kebab-case `<slug>` from the subject (e.g. `fin-3141-scope`, `flat-detector-multipage`). Before minting, run `ls <trailDir>`: if an existing `<slug>_*.md` matches this work (same ticket / chunk), REUSE that slug so the digest clusters with the `/build`, `/scrutinize`, and `/council` artifacts for the same thread. With no active session, write the digest to the working directory as `<slug>_INTERROGATE.md`.

**Acknowledge:** Echo your setup in exactly one line:
`Interrogating: <subject> — depth: <quick|standard|deep>; digest → <trailDir>/<slug>_INTERROGATE.md.`

## 2. Run the Interrogation

Execute `§CMD_INTERROGATE` with the subject as the topic source and the resolved depth as the **minimum**. `/interrogate` reuses the command's mechanics wholesale (depth → rounds → between-round context → exit gate) and layers two behaviors on top:

- **Offer a topic checklist, don't impose one.** Derive a candidate topic list from the subject and present it as a checklist the user can prioritize or prune (`AskUserQuestion`, multiSelect) — for a ticket the natural candidates are scope boundary, acceptance signals, constraints/non-goals, dependencies, data/edge cases, risk. The user picks what matters; the checklist is a menu, not a script. Skip the checklist under `--depth quick` (a machine caller wants tight rounds, not a menu) and just cover the highest-signal topics.
- **Mix topics within a round — never bind a round to one topic.** A round's up-to-4 questions may span several of the chosen topics; ask whatever is most worth knowing next, drawn from wherever. Mixed-topic rounds are native to `§CMD_INTERROGATE` — the questions cluster by *relevance*, not by topic label.
- **Depth**: skip the depth menu when `--depth` was passed (use its minimum directly); otherwise present `§ASK_INTERROGATION_DEPTH`.
- **Between-round context is mandatory** after Round 1 and lives IN the `AskUserQuestion` body (`§CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT` / `§FMT_CONTEXT_BLOCK`) — the Round N-1 recap plus the Round N framing — never as a separate chat block. Option labels lead with `§FMT_ANSWER_GRADATION` sigils where a dimension differentiates.
- **Exit gate**: after the minimum rounds, present `§ASK_INTERROGATION_EXIT`. "Proceed" ends interrogation.

When a session is active, every round auto-logs to its DIALOGUE.md (the `post-tool-use-details-log.sh` hook). Do not double-log.

## 3. Write the Digest & Echo

Write the gathered interrogation to `<trailDir>/<slug>_INTERROGATE.md` using `assets/TEMPLATE_INTERROGATE_DIGEST.md`. The digest carries, per the template:
- **Subject + depth** — what was interrogated and at what depth.
- **Q&A** — each round's questions and your verbatim answers, grouped by topic.
- **Resolved scope** — the synthesis: what is now settled, what is explicitly out of scope, and what remains open/deferred (mark open items so a caller knows the residue).

Then echo a one-line summary in chat with the digest path (`§CMD_LINK_FILE`): what got settled and any open residue. Do NOT dump the full digest into chat — the file is the handoff; the echo is the pointer.

## 4. Return & Stop

The digest path IS the return value. A machine caller (`/ultrabuild`) reads it to assemble a build context pack. A human reads it and decides the next move — `/build`, `/ticket`, `/implement` — which `/interrogate` offers but never runs. Interrogation gathered and reported; it stops here.

---

## Engine vs. Standalone

`/interrogate` runs the same either way; only the logging surface differs.
- **Inside a session** (invoked by `/ultrabuild` or another skill, or run by a human mid-session): rounds log to the active DIALOGUE.md automatically; the digest lands in `<sessionDir>/builds/`.
- **Standalone** (no active session): interrogation still runs (`AskUserQuestion` needs no session); the digest lands in the working directory. No DIALOGUE.md logging.

The presence of `COMMANDS.md` / the engine in context is not required — the skill degrades to standalone gracefully.

---

## Constraints

- **Read-and-gather only.** `/interrogate` never writes a plan, edits code, writes to a database, or files a ticket. It asks, records, synthesizes, and stops.
- **Owns no session.** It never calls `engine session activate`. It rides the active session or none.
- **`--depth` suppresses the menu.** A machine caller must pass `--depth` so the loop never blocks on the depth question.
- **`§INV_QUESTION_GATE_OVER_TEXT_GATE`**: all user interaction is via `AskUserQuestion`.
- **`§INV_LISTS_INSTEAD_OF_TABLES`**: no markdown tables in this file.
- **Digest is the interface.** The chat echo is a pointer; the file is the machine-readable handoff.
