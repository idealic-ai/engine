# Probe Log Schemas (The Investigator's Notebook)
**Usage**: Your thinking stream while you investigate. Choose the schema that fits each finding; combine them freely. Capture your reasoning in high fidelity — this notebook is the raw material your Probe Report synthesizes, so a thin log makes a thin report.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `engine log` — never write them yourself.
**Cadence**: Append every ~5 tool calls. Under the engine, a heartbeat hook BLOCKS you after 10 tool calls without a log.
**Evidence rule**: Quote, don't paraphrase. `file:line`, the exact query AND its actual rows, the ticket's own words.

## 🔍 Discovery (Fact/Observation)
*   **Focus**: `[File/Table/Ticket]`
*   **Observation**: "The 'Pro Tier' pricing documentation explicitly mentions unlimited exports, but the feature specification sheet lists a hard cap of 10 per day."
*   **Evidence**: "Section 3.1 in `PRICING.md` vs Line 12 in `features/export_limits.ts`."
*   **Bears on the intent**: "This is the contradiction the question was about — the cap is real and enforced in code."

## ⚠️ Weakness (Critique/Risk)
*   **Target**: `[Component/Flow]`
*   **Flaw**: "The onboarding flow requires the user to connect a Spotify account *before* they can hear any generated music. This creates a 'Cold Start' problem where users cannot experience value without a high-friction commitment."
*   **Severity**: [Critical - Conversion Risk]
*   **Implication**: "We are likely losing 40-50% of top-of-funnel traffic at this step."

## 🔗 Connection (Synthesis)
*   **Link**: `[Viral Loop]` <--> `[Watermark Strategy]`
*   **Insight**: "The 'Remove Watermark' upsell is blocking the viral loop. Users who share free mixes are advertising our competitor, who allows unbranded sharing."
*   **Consequence**: "Our `k-factor` is artificially depressed — short-term revenue traded for long-term growth."

## 💡 Spark (Idea/Innovation)
*   **Trigger**: "While tracing the 'Session Duration' metrics..."
*   **Idea**: "A 'Collaborative Jam' mode — share a live link where a friend adjusts the fader in real-time via WebSockets, instead of just sharing the final MP3."
*   **Potential Benefit**: "Turns the product from a 'Tool' (single player) into a 'Place' (multiplayer)."
*   **Feasibility**: "Moderate — `StreamController` state is already serializable; needs a transport layer."

## ❓ Gap (The Unknown)
*   **Missing**: "I cannot find any definition of the 'Churn Recovery' email sequence. The system cancels the subscription immediately with no automated win-back attempt."
*   **Question**: "Is this handled by an external CRM that isn't in this repo, or is it a missing feature?"
*   **How to settle it**: "Check the `webhooks/stripe` handler for external event triggers."

## 📊 Pattern (Recurring Theme)
*   **Occurrences**: `[Location 1]`, `[Location 2]`, `[Location 3]`
*   **Pattern**: "Every API endpoint handling file uploads silently drops `Content-Type` validation under 1MB — avatar upload, document import, and CSV batch. Three independent implementations, same gap."
*   **Systemic Cause**: "Copy-pasted from an early prototype where small files were 'trusted'. No shared upload middleware exists."
*   **Implication**: "This is not three bugs — it's a missing abstraction. Fixing one leaves two vulnerable."

## ⚖️ Tradeoff (Decision Fork)
*   **Decision**: `[Architecture/Design Choice]`
*   **Option A**: "Shared Redis cache for session state."
    *   **Pro**: "Sub-millisecond lookups, battle-tested, simple mental model."
    *   **Con**: "Single point of failure, infra cost, cold-start latency on miss."
*   **Option B**: "JWT tokens with embedded claims — no shared state."
    *   **Pro**: "Stateless, horizontally scalable, no cache infrastructure."
    *   **Con**: "Revocation is hard, payload grows with claims, clock skew."
*   **Lean**: "Option B at this scale — revocation is solvable with a short TTL + refresh token."

## 🛡️ Assumption (Untested Belief)
*   **Assumption**: "The code assumes every Stripe webhook arrives exactly once and in order."
*   **Evidence**: "No idempotency key check in `webhooks/stripe.ts`. No dedup table. Handler processes events synchronously."
*   **Risk**: "Stripe documents that webhooks retry and can arrive out of order — a network hiccup could double-process a charge."
*   **Validation Needed**: "Check the Stripe dashboard retry config; grep production logs for duplicate `invoice.paid`."

## ✅ Strength (What Works Well)
*   **Target**: `[Component/Pattern]`
*   **Observation**: "The React error boundary system is exceptionally well-designed — every route has a dedicated fallback, errors carry full stack traces to Sentry, and users get actionable recovery instead of blank screens."
*   **Why It Works**: "Clear ownership — each team owns their route's boundary. The shared `ErrorBoundary` enforces the pattern without prescribing recovery UX."
*   **Preserve**: "Should be documented and replicated in the mobile app, which has no equivalent."

## 🚧 Blocker (Inaccessible Source)
*   **Wanted**: "Row counts for `claim_policy_snapshot` by created_at month."
*   **Blocked By**: "No `DATABASE_URL` configured in this environment; the read-only analyst connection is not reachable from here."
*   **Consequence for the answer**: "The scale half of the question is unanswerable — reporting it as a blind spot rather than estimating."
