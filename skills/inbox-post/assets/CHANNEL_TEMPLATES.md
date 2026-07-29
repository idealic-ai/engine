# Inbox Channel Reporter Templates

Canonical per-channel report templates for the intake **Inboxes** channels. Single source of truth: `/inbox-post` fills these when posting, and each is synced into its channel ticket's Linear description (under a `## 📋 Report template` section) so a human dropping an item has the same basis.

Each template = a **shared core** (identical on every channel) + **channel-specific fields**. Fill what you know — half-formed is fine, and **attach anything that grounds it** (transcripts, screenshots, debriefs, logs, sample files) rather than describing it from memory.

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

## 🟡 Researches & Fixtures

```
**Workload**: (extraction / classification / comparison)
**Case**: (doc / claim / message id)
**Corrected answer — the oracle**: (what the output should be)
**Evidence**: (annotated screenshots / signals proving it)
**Suspected root cause** (optional):
```
