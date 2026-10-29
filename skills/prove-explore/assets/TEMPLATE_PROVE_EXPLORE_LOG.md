# Explore Notebook (The Cartographer's Journal)
**Usage**: The cartographer's running stream while grounding and composing a map. Append via `engine log <session log path>` every ~5 tool calls — a heartbeat hook BLOCKS after 10 tool calls without a log.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `log.sh`.
**Constraint**: Entries say what you ESTABLISHED, in your own words. Reference a file by path and summarise what it showed; quote only where the exact wording IS the finding. Long stretches of copied source are the shape most likely to be cut off mid-run by content filters, which costs the whole lane its result.

## 🗺️ Decomposition-Set
*The sub-question list, written down before composing. The page's outline.*
*   **Question**: [the one question]
*   **Sub-questions**: [the named list — enumerate, never state the count]
*   **Boundary**: [what is explicitly out]
*   **Why this decomposition**: [why it spans the question with the smallest set]

## 🔎 Checked-Here
*Something YOU confirmed, purely for the presentation.*
*   **What I confirmed**: [the fact, and the command or file that showed it]
*   **Control**: [the positive control in the same invocation — an instrument that returned nothing for a case it should have matched carries no information]
*   **Not**: [what this does NOT establish]

## 🧾 Trusted-Upstream
*A conclusion taken as given from established work. The default provenance.*
*   **Claim**: [what the page will assert]
*   **Source verdict**: [the report/section it comes from]
*   **How I'll show it**: [the asset that depicts it, or "attributed text" if nothing is renderable]

## 🖼️ Asset-Rendered
*   **Asset**: [path under the scratchpad asset dir]
*   **From**: [the actual command / file / URL — the real source]
*   **Shows**: [what its caption will claim — and nothing more]

## ⛔ Asset-Failed
*   **Asset**: [what could not be captured]
*   **Why**: [the reason]
*   **Degraded to**: [what the page shows instead — never a fabricated stand-in]

## 🌓 Epistemic-Sort
*Sorting a region into Known / Measured absent / Not established / Not looked at. The blank regions are part of the answer.*
*   **Region**: [the part of the territory]
*   **Verdict**: [known | measured absent | not established | not looked at]
*   **If measured absent**: [the reading, and the positive control that fired in the same invocation — an absence without a control is "not established"]
*   **If not established**: [what would settle it]
*   **If not looked at**: [why nobody has]

## ⛔ Instrument-Note
*The instrument answered a narrower question than its output suggested. Record it before any caption rests on that reading.*
*   **What the instrument reported**: [the row, and what looked fine about it]
*   **What it actually measured**: [the narrower question — e.g. a status code plus a content control does not catch a TRUNCATED read]
*   **What reconciles it**: [the check that does settle it — a byte count against `Content-Length`, a `cmp` against a local copy, a positive control]
*   **What it changed on the page**: [the captions re-measured, or "nothing rested on it"]

## ⚖️ Disagreement-Shown
*Two sources conflict. Resolving by preference is prohibited.*
*   **Side A**: [claim] — [evidence]
*   **Side B**: [claim] — [evidence]
*   **What I did**: [showed both unresolved | resolved by evidence: which, and what decided it]
*   **Why not smoothed**: [the reasoning — a contradiction is usually the most interesting finding on the page]

## ✂️ Overreach-Cut
*   **Claim as first drafted**: [what it said]
*   **Why cut / downgraded**: [the evidence did not reach that far / it asserted a history a point-in-time check cannot support / it ruled where a map may not]
*   **Where it landed**: [the narrower claim that survived, or removed entirely]

## 🧹 Padding-Cut
*The check against this skill's natural failure.*
*   **What I cut**: [the paragraph or section]
*   **Why**: [restated a neighbour / re-explained an introduced thing / narrated the investigation instead of its result / answered no sub-question]

## 💡 Decision
*   **Choice**: "Chose A over B."
*   **Why**: "Reasoning."
