# Intake Vision — [Initiative]
**Tags**: #needs-review

*The working cross-scope understanding for this initiative. This doc is the agent's reasoning surface; it is PROJECTED to the Linear Project description + updates. Linear is the source of truth — this is the vision synced onto it.*

## 1. The Initiative
*   **What**: [the improvement/hairball being untangled — e.g. "email classification accuracy"]
*   **Linear Project**: [URL/ID] — goal: [the interrogated domain goal]
*   **Inbox ticket** (under `Inboxes` milestone): [URL/ID] · **Watermark**: [last-synced comment timestamp]
*   **Status**: [Active / Checkpointed]
*   **Project Update** (this wave's two-event `§PASS_HEARTBEAT` state — the pinned home so Close can find it after a rehydrate): **id**: [the `save_status_update` id captured when event 1 posts the Update, for the Close in-place edit — or "not yet posted"] · **Decision Board**: [S3 url] · **Outcomes Board**: [S3 url, set at Close]

### Ticketing Strategy (loaded verbatim from the Project description — `¶INV_TICKETING_STRATEGY_IN_PROJECT`)
*How much ticketing this project wants. Project-level only — no channel override. Gates graduate-vs-fold-vs-marinate at Outcomes, AFTER ripeness passes. Mandatory: if the project has none, say so explicitly here and name the default as applied — a defaulted project must be visible as defaulted.*

*   **Volume**: [verbatim bullet, or "default applied — none set on the project"]
*   **Size**: [verbatim bullet, or "default applied"]
*   **Substance**: [verbatim bullet, or "default applied"]
*   **Changed since last wave**: [what changed · **which already-filed tickets it re-opens** — or "none". Unlike Directions, a changed ticketing policy invalidates past graduations, not just pending judgment.]

### Stakeholders (loaded from the Project description — optional, absence is normal)
*Facts about people, never assignment rules. Triage carries the relevant names into handoff prompts (who to ask); Outcomes infers assignee/reviewer and who an update should reach. Inference only — never authority.*

*   **Owns what**: [person → area/decision, or "none set"]
*   **Ask about what**: [person → the questions they can close]
*   **Cares about outcomes**: [who to notify · who to consult before shipping]
*   **Expiring**: [interim owners, leave, handovers in progress — or "none"]

### Directions (loaded verbatim from Linear — `¶INV_DIRECTIONS_IN_DESCRIPTIONS`)
*The project's own steer, copied from the `## Directions` sections. Channel > project > skill default. Every phase and every dispatched sub-agent reads THIS copy, so it must be verbatim. Note anything that changed since the last wave — a changed steer re-opens judgments made under the old one.*

*   **Project-wide**: [verbatim from the Project description's `## Directions`, or "none set"]
*   **[🔴 channel name]**: [verbatim, or "none set"]
*   **[🟠 channel name]**: [verbatim, or "none set"]
*   **Changed since last wave**: [which channels · what changed · what it re-opens — or "none"]

## 2. Cross-Scope Understanding
*The larger picture: how the threads relate, where the leverage is, what's blocked on what. This is the part that makes "where do I start" answerable.*

[2-4 paragraphs synthesizing the current understanding across all items.]

## 3. Ranked Priorities — "Pull this first, and why"
*The compass. v1: coarse impact/effort read. Reserved seam (¶INV_RANKING_WITH_PROOFS): evidence-backed ranking with proofs, tied to /probe /prove.*

*   **1.** [cluster] — impact: [H/M/L] · effort: [S/M/L] · why-first: [one line] · proof: [evidence pointer, or "TODO — reserved seam"]
*   **2.** [cluster] — …

## 4. Problem Dependency Graph + Research Memory
*Not a flat list — a graph of problems/solutions with dependency edges, plus the accumulated research per node. This is what makes decomposition and the 20/80 sub-problem visible, makes "solution Z fixes A–Y" conjecturable, and stops every problem being re-attacked from zero. Materialize edges as Linear relations; keep the readable version here. Keep it clean continuously: merge/dedup/supersede/connect.*

### [Problem / candidate-solution node]
*   **Symptoms it explains** (leads/tickets): [FIN-…, cluster refs]
*   **Dependencies**: stands-on [X, Y] · blocked-by [A, B] · unlocks [O] · needs-research-from [K]
*   **Candidate solution (Z)**: [the leap — a human conjecture, not auto-generated] — parent ticket: [FIN-XXX or "not yet filed"]
*   **Breadth**: [N symptoms] · **Confidence**: [H/M/L] · **Proof**: [evidence, or "TODO — reserved seam"]
*   **Research memory**: [findings so far · dead-ends tried · why/when it happens — lives on the ticket, synthesized here so nobody starts from zero]
*   **Cleanup actions**: [merges / dedups / supersedes / connects to apply — each needs human confirm]

## 5. Item Registry
*Every tracked cluster: bucket, maturity, ripeness checklist, Linear state.*

### [Cluster title]
*   **Bucket**: [conversational / research / action]
*   **Maturity**: [raw / shaped / ripe / filed]
*   **Ripeness**: [ ] crisp problem · [ ] next-action · [ ] brief type · [ ] non-self corroboration
*   **Brief**: [the drafted brief + type — #needs-research etc.]
*   **Origin**: [Inbox comment ref] · **State**: [candidate / seems-like-X / filed as FIN-XXX]

## 5. What's Marinating vs Ripe vs Filed
*   **Marinating** ([N]): [short list — not yet ripe, and why]
*   **Ripe / nominated** ([N]): [awaiting confirm]
*   **Filed this session** ([N]): [FIN-XXX → milestone]

## 6. Honest Signals
*Surface the embarrassing numbers, not just the flattering ones (¶ per council Measurement Skeptic).*

*   **Nomination-rejection rate**: [ripe nominees the user declined — gate precision]
*   **Staleness / rot**: [items marinating past [threshold] — ideas at risk of dying in the inbox]
*   **Throughput**: [raw → filed this session]

## 7. Open Threads / Next Pass
*   [What to revisit next intake pass]

---
*The Curator | Initiative: [name] | Linear: [Project URL]*
