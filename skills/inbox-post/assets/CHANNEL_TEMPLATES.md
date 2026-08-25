# Inbox Channel Reporter Templates

Canonical per-channel report templates for the intake **Inboxes** channels. Single source of truth: `/inbox-post` fills these when posting, and each is synced into its channel ticket's Linear description (under a `## 📋 Report template` section) so a human dropping an item has the same basis.

Each template = a **shared core** (identical on every channel) + **channel-specific fields**. Fill what you know — half-formed is fine, and **attach anything that grounds it** (transcripts, screenshots, debriefs, logs, sample files) rather than describing it from memory.

> **⚠️ This file is incomplete — 8 of 10 channels.** 🟤 **Priorities & Deadlines** and 🟦 **Documentation** have live channel tickets but no template here, so `/inbox-post` filling from this file alone drops their channel-specific fields silently. Take those two from the **project's Inbox Handbook**, which is canonical Linear-side (`¶INV_CHANNEL_MACHINERY_IN_ONE_DOC`), and reconcile them back into this file rather than inventing them here. Noted rather than guessed: writing a plausible template for a channel whose real one already exists elsewhere is how two documents start disagreeing.

---

## Shared core (every channel)

```
### 🧾 [one-line title]
- **Reported by**: (name) · **Date**: (YYYY-MM-DD)
- **App page**: (URL in the app, if applicable)
- **Refs**: (claim / org / case / doc ids)
- **Attachments**: attach the evidence as **files on the issue** (Linear upload) — transcripts, screenshots / annotated PNGs, analysis debriefs & reports, logs, sample files (PDF/.esx/etc), a `/prove` proof HTML. Attach the real thing; don't retype it from memory. NOT a private preview link — a `claude.ai/…/artifact/…` URL isn't viewable by teammates, so upload the underlying file instead. More grounding = moves faster.
- **Impact — what this blocks**: (who/what it stops, how widely)
- **Severity**: (P0 / P1 / P2 — optional)
```

---

## 🔴 Observed problems

```
**Steps to reproduce**:
1.
2.
**Expected**:
**Actual**:
**Frequency**: (always / intermittent / seen once)
```

## 🟠 Identified shortcomings

```
**The gap**: (what's structurally missing or weak — one level deeper than a symptom)
**Why it matters / where it bites**:
**Evidence**: (what points to this being the shortcoming)
```

## 🔵 Feature requirements

```
**Desired behavior**: (what it should do)
**User story**: As a (role) I want (capability) so that (outcome)
**Why now / trigger**:
```

## 🟢 Potential solutions

```
**The conjecture** (proposed fix / mechanism):
**What it would fix** (which problems / clusters it addresses):
**Rough approach**:
**Risks / unknowns**:
```

## 🟣 Feedback & Transcripts

```
**Source**: (email / call / meeting / message thread)
**Participants / who said it**:
**Date of source**:
**Raw material** (paste whole below — to be chunked into the other channels):
```

## 📣 Announcements

*Outbound, not a signal. Skip the shared core's Severity/Impact framing where it doesn't apply — most announcements block nothing, and saying so plainly is the point.*

```
**What is now true**: (the new state, not what you did — "X now does Y by default", never "rewrote X")
**Who does something differently, and when**: (usually nobody — say that explicitly)
**How to check it**: (a URL to open, a file to read, a command to run — an unverifiable announcement can't be triaged)
**Is this a new default?**: (yes/no — a change that happens without anyone opting in is the most valuable kind here)
**Known gaps**: (what is true but incomplete — better learned here than by hitting it)
```

## 🟩 Chores & tracker hygiene

*Ten seconds or don't bother. One key + one sentence is a complete item; batch several in one comment if you spotted them together.*

```
**Target**: (the specific FIN-key, or the exact line — a chore without one is a mood)
**What's wrong with the record**: (misleading title / obsolete description / duplicate / already done / stale wording)
**What it cost you** (optional but high-value): ("I filed a duplicate because the existing one was titled unrecognizably")
```

## 🟡 Researches & Fixtures

```
**Workload**: (extraction / classification / comparison)
**Case**: (doc / claim / message id)
**Corrected answer — the oracle**: (what the output should be)
**Evidence**: (annotated screenshots / signals proving it)
**Suspected root cause** (optional):
```
