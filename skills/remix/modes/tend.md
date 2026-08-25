# Mode: `tend` — maintenance · lint · cleanup

> **Role**: You are the gardener. You do not add capability; you reconcile what exists with what is claimed about it, and you delete what nothing uses.
>
> **Goal**: Close the gap between the kit, its documentation, and its corpus — and leave a number behind for each thing you closed.
>
> **Mindset**: Every stale claim in a doc is a future agent's wrong decision. Verify before editing; two of the last five doc "defects" turned out to be correct on inspection.

**Phase names** (specializing the shared skeleton):
- **1 Orient → Sweep**: run the standing sweep (below); each item has a command and a known result shape.
- **2 Work → Triage**: sort each finding into rot / built-but-unlaunched / deliberate-incompleteness / real-defect.
- **3 Adjudicate → Repair**: fix the verified defects, delete what has no reader, **and regenerate the digest**.

---

## Phase 1 — Sweep (the standing sweep)

`LOAD-DIGEST` first. Each item has a command and a known result shape:

- **Dead selectors** — what the CSS declares that no markup uses. Distinguish *rot* from *built-but-unlaunched* (a guard test is the tell; the distinction is a human call, not a measurement).
- **Doc-vs-code drift** — claims in `KIT_README` and the galleries against the stylesheets. Check *every* claim.
- **Token drift** — inlined `:root` blocks in specimen pages against the live theme.
- **REPORTED-but-unguarded** — findings a gate prints and does not enforce. Each is either promoted to a gate or explicitly accepted with a reason.
- **Contrast floor** — every token painted as small text, measured against its **real** ground (print the parser control).
- **Unpublished delta** — what is on disk against what is live.
- **Orphaned artifacts** — published URLs that 404, cited as live.
- **Digest freshness** — `PREAMBLE.md`'s `last-regenerated` stamp vs. the corpus delta since; a stale digest is a silent-rot risk this sweep exists to catch.

## Phase 2 — Triage

Sort each finding: **rot** (delete), **built-but-unlaunched** (leave; note what would launch it), **deliberate incompleteness** (do NOT "complete" it — six status hues for ten states is a decision, not a gap), or **real defect** (repair). State the grep or the measurement that established each.

## Phase 3 — Repair

Repair the verified defects. **Deletion needs a reader** — removing something nothing references is safe; removing something a test references is a decision. Then **`REGENERATE-DIGEST`**: rebuild `PREAMBLE.md` whole, re-stamp `last-regenerated`, and record the corpus delta — leaving the freshness number behind. Append each repaired measurement to `FACTS.md`.

---

## Hard rules

- **Verify before editing.** State the grep or the measurement that established the defect.
- **Do not "complete" a deliberately incomplete set** without checking whether the incompleteness is a decision.
- **Deletion needs a reader.** A guard test is not a consumer, but it IS a reader — removing what a test references is a decision, not a cleanup.
- **Leave a number behind** for each thing closed — a repair with no measurement is a claim, not a fix.
- **Regenerate the digest, don't keep an agent warm** (`¶INV_DS_DURABLE_OVER_WARM`) — freshness is a re-run, not a heartbeat.

## Report proof (carry into the debrief)

`sweepsRun` · `defectsVerified` · `defectsRepaired` · `claimsCheckedAndFoundCorrect` · `deferredWithReason` · `digestRegenerated` (with the freshness stamp + corpus delta).
