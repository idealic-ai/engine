# Prove Notebook (Sub-agent's Assemble/Render Stream)
**Usage**: The evidence-engineer sub-agent appends its raw stream here (into the ACTIVE session's log) every ~5 tool calls, as it assembles the evidence and renders the real assets. A heartbeat hook BLOCKS after 10 tool calls without a log. This notebook is the raw material the dossier synthesizes — a thin log makes a thin proof. Remember: you TRUST the finding; you are showing it, not re-proving it.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `log.sh`.

*Schemas below — use the one that fits the moment. Prefer evidence (the rendered asset, the quoted line) over narration.*

## 🧾 Trusted-Upstream
*   **Claim**: "[the assertion]"
*   **Source verdict**: "[what the finding concluded, quoted/attributed — taken as given, NOT re-run]"
*   **How I'll show it**: "[the real asset that will depict it on the page]"

## 🔎 Checked-Here
*   **What I confirmed for the presentation**: "[the render actually depicts the claim, e.g. 'p86 PNG shows rows 12–14', 'quoted log line matches file:line']"
*   **Not**: "[a re-run of the analysis — this is presentation integrity only]"

## 🖼️ Asset-Rendered
*   **Asset**: `[<assetDir>/<file>.png]`
*   **From**: "[the real source + command, e.g. mutool draw -r 150 estimate.pdf 86 / code block from src/x.ts:40 / log tail]"
*   **Shows**: "[what the reader will see in it]"

## 🕳️ Asset-Failed
*   **Wanted**: "[the asset I could not render]"
*   **Why**: "[no renderer / source unreachable / too large]"
*   **Degrade**: "[how the page shows the point without it — code block / table / CLI text / diagram]"

## ✂️ Overreach-Cut
*   **Claim as first drafted**: "[what the page was about to assert]"
*   **Why cut / downgraded**: "[claimed more than the asset shows, or more than upstream established]"
*   **Where it landed**: [cut entirely / downgraded to what the evidence actually shows / moved to attributed text]

## 🔗 Attributed-Text
*   **Claim with no showable asset**: "[the point that can't be rendered]"
*   **Attribution**: "[the trusted source it points at, e.g. 'per the /experiment VERDICT: …'] — carried as text, never dressed as rendered evidence"
