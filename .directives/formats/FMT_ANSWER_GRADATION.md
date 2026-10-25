### ¶FMT_ANSWER_GRADATION

**When to use**: compact, at-a-glance gradation tags leading an `AskUserQuestion` **option label** — so the user reads risk / data-certainty / effort / recommendation right on the choice. Generalizes the old "(Recommended)" suffix. A **closed** set (like the `§CMD_FLOWGRAPH` glyphs — defined once, never freehand). Show **only the 1–2 dimensions that actually differentiate this answer set**; omit any dimension uniform across all options.

**The set** (fixed row order, packed — no spaces inside the cluster, one space before the label):
*   **risk** — `△` low · `◭` med · `▲` high  *(triangle = caution)*
*   **confidence** — `○` thin · `◑` med · `●` solid  *(certainty in the GATHERED DATA behind the call — "how much more analysis to verify"; fullness = evidence completeness)*
*   **effort** — `Ⓢ` small · `Ⓜ` med · `Ⓛ` large
*   **★** — the agent's recommendation, **last** in the row, ≤1 per set
*   *(rare optional)* `‡` — one-way / irreversible; appended only when genuinely relevant, not part of the default row

**Row order**: `risk · confidence · effort · ★` → e.g. `△●Ⓢ★ `, then the label text.

```markdown
[AskUserQuestion option labels:]
"△●Ⓢ★ Cherry-pick onto a fresh branch"    (low risk · solid data · small · recommended)
"▲◑Ⓢ Push the mixed branch as-is"          (high risk · medium data · small)
"◭○Ⓜ Rebase after a spike"                 (med risk · thin data—verify first · med effort)
```

**Anti-pattern**: tagging every dimension even when uniform across options (soup); freehand emoji/glyphs outside the closed set; putting the tags in the option `description` instead of leading the `label`.
