# Analysis Log Schemas (The Researcher's Notebook)
**Usage**: Choose the best schema for your finding. Combine them freely. The goal is to capture your thought process in high fidelity.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `log.sh`.

## 🔍 Discovery (Fact/Observation)
*   **Focus**: `[Concept/Doc]`
*   **Observation**: "The 'Pro Tier' pricing documentation explicitly mentions unlimited exports, but the feature specification sheet lists a hard cap of 10 per day."
*   **Evidence**: "Section 3.1 in `PRICING.md` vs Line 12 in `features/export_limits.ts`."
*   **Context**: "This contradiction likely stems from the marketing pivot last quarter where we tried to upsell 'Enterprise' plans, but the code was never updated to reflect the new tiered limits."

## ⚠️ Weakness (Critique/Risk)
*   **Target**: `[User Experience/Flow]`
*   **Flaw**: "The onboarding flow requires the user to connect a Spotify account *before* they can hear any generated music.
    This creates a massive 'Cold Start' problem where users cannot experience value without a high-friction commitment."
*   **Severity**: [Critical - Conversion Risk]
*   **Implication**: "We are likely losing 40-50% of top-of-funnel traffic at this specific step. The 'Time to Magic' is currently > 3 minutes."
*   **Mitigation**: "We should provide a 'Demo Set' of pre-licensed tracks so users can play immediately without login."

## 🔗 Connection (Synthesis)
*   **Link**: `[Viral Loop]` <--> `[Watermark Strategy]`
*   **Insight**: "The current 'Remove Watermark' upsell is effectively blocking our viral loop.
    Users who share free mixes are inadvertently advertising our competitor (who allows unbranded sharing) because they hate our aggressive branding."
*   **Consequence**: "Our `k-factor` (virality) is artificially depressed. We are trading long-term growth for short-term revenue."

## 💡 Spark (Idea/Innovation)
*   **Trigger**: "Analyzing the 'Session Duration' metrics..."
*   **Idea**: "What if we introduced a 'Collaborative Jam' mode?
    Instead of just sharing the final MP3, users could share a 'Live Link' where a friend can jump in and adjust the fader in real-time via WebSockets."
*   **Potential Benefit**: "This transforms the product from a 'Tool' (single player) to a 'Place' (multiplayer), significantly increasing retention and network effects."
*   **Feasibility**: "Moderate. The `StreamController` state is already serializable; we just need a transport layer."

## ❓ Gap (The Unknown)
*   **Missing**: "I cannot find any definition of the 'Churn Recovery' email sequence.
    The system cancels the subscription immediately, but there seems to be no automated attempt to win the user back."
*   **Question**: "Is this handled by an external CRM (HubSpot/Intercom) that isn't documented here? or is it a missing feature?"
*   **Action**: "Need to check the `webhooks/stripe` handler to see if it triggers any external events."

## 📊 Pattern (Recurring Theme)
*   **Occurrences**: `[Location 1]`, `[Location 2]`, `[Location 3]`
*   **Pattern**: "Every API endpoint that handles file uploads silently drops the `Content-Type` validation when the file is under 1MB.
    This appears in the avatar upload, document import, and CSV batch endpoints — three independent implementations with the same gap."
*   **Systemic Cause**: "Likely copy-pasted from an early prototype where small files were 'trusted'. No shared upload middleware exists."
*   **Implication**: "This is not three bugs — it's a missing abstraction. Fixing one endpoint leaves two vulnerable."

## ⚖️ Tradeoff (Decision Fork)
*   **Decision**: `[Architecture/Design Choice]`
*   **Option A**: "Use a shared Redis cache for session state across all services."
    *   **Pro**: "Sub-millisecond lookups, battle-tested, simple mental model."
    *   **Con**: "Single point of failure, added infrastructure cost, cold-start latency on cache miss."
*   **Option B**: "Use JWT tokens with embedded claims — no shared state needed."
    *   **Pro**: "Stateless, horizontally scalable, no cache infrastructure."
    *   **Con**: "Token revocation is hard, payload size grows with claims, clock skew issues."
*   **Lean**: "Option B for this scale — the revocation problem is solvable with a short TTL + refresh token pattern."

## 🛡️ Assumption (Untested Belief)
*   **Assumption**: "The codebase assumes that all webhook payloads from Stripe arrive exactly once and in order."
*   **Evidence**: "No idempotency key checking in `webhooks/stripe.ts`. No event deduplication table. The handler processes events synchronously."
*   **Risk**: "Stripe explicitly documents that webhooks can be retried and delivered out of order. A network hiccup could cause duplicate charge processing."
*   **Validation Needed**: "Check Stripe dashboard for retry configuration. Review production logs for duplicate `invoice.paid` events."

## ✅ Strength (What Works Well)
*   **Target**: `[Component/Pattern]`
*   **Observation**: "The error boundary system in the React app is exceptionally well-designed. Every route has a dedicated fallback UI, errors are captured with full stack traces via Sentry, and users see actionable recovery options instead of blank screens."
*   **Why It Works**: "Clear ownership — each team owns their route's error boundary. The shared `ErrorBoundary` component enforces the pattern without being prescriptive about recovery UX."
*   **Preserve**: "This pattern should be documented and replicated in the mobile app, which currently has no equivalent."
