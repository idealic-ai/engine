# Groom Log (The Grooming Journal)
**Usage**: Track the pass — what drained, how it clustered, what each topic's outcome was, and where each topic went.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `log.sh`.

## ▶️ Groom Opened
*   **Project**: [name]
*   **Riding**: [the active loom session's dir | standalone — own light session]
*   **Handbook**: [doc id · updatedAt | `none published — defaulted, and here is the default applied`]
*   **Dials**: Volume=[…] · Size=[…] · Substance=[…] · 🛠️ channel=[present | absent]

## 🪣 Drain
*   **Inbox**: [payload path] · `--since`=[the value supplied, or `none — full snapshot`] · [N] new signals (recursive walk) · [M] still-owed threads (root-only walk)
*   **Tickets**: `engine project next` · [T] open rows · [X] excluded as In-Progress · `degraded`=[true/false]
*   **Leftovers**: [L] gathered via `/inbox-next` §3b · [or the one-line degradation, naming which]
*   **Taken**: [K] — **Ruling**: [who decided the bound and on what basis]
*   **Watermark**: not advanced — /groom mints none

## 🧺 Cluster
*   **Proposed**: [N] topics from [M] members across [which sources]
*   **Cross-source topics**: [which ones, and what joined them]
*   **Relations**: read from the rows' own keys — [which topics that joined] · derived for [inbox/leftover members only]
*   **Human changes**: [merged X+Y | split Z into two | moved a member | taken as proposed]
*   **Single-member topics**: [how many, and that this is legitimate]
*   **Topic list**: [path]

## 🎯 Disposition
*   **Topic**: [SLUG]
*   **Outcome**: [graduate | fold | route 🛠️ | marinate | dispatch as-is | re-scope | defer]
*   **Where**: [ticket key(s) · parent · channel comment · `marinating` · `rides its own ticket` · `deferred at rank N`]
*   **Per member**: [what became of each member under the one outcome]
*   **Why**: [the dial or the evidence]
*   **Marker**: [the prefix posted, or `none posted — no channel thread`]
*   **Resolved**: [comment ids, after the pointer reply — or `left open: <reason>`]

## 🚚 Dispatch
*   **Topic**: [SLUG or the ticket key it took]
*   **Thread**: [threadId] | `not dispatched — <reason>`
*   **Carried**: [tickets riding this thread · inbox signals · leftovers · any re-scope · dials]

## 🧭 Next Move
*   **The move**: [KEY — title] — read from `importance` order, never a ranking of this skill's
*   **Why first**: [milestone · priority · blocked · estimate, as the row carries them]
*   **Instead of**: [the runner-up]
*   **Route**: [`/inbox-next` offered — accepted/declined]

## 🅿️ Deferred
*   **What**: [inbox signals · tickets · leftovers not taken this pass]
*   **State**: [signals unresolved in Linear · tickets open at their rank · leftovers in their debrief, with the reason written to this pass's `## Leftovers`] — the next pass re-offers all three

## 💡 Decision
*   **Choice**: "Chose A over B."
*   **Why**: "Reasoning."
