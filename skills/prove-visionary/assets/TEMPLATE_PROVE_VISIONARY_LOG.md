# Prove-Visionary Notebook (Sub-agent's Ground/Cost/Compose Stream)
**Usage**: The direction-architect sub-agent appends its raw stream here (into the ACTIVE session's log) every ~5 tool calls, as it gathers the grounding, costs the options, and composes the page. A heartbeat hook BLOCKS after 10 tool calls without a log. This notebook is the raw material the dossier synthesizes — a thin log makes a thin page. Remember: you may PROPOSE; you may not invent a number or dress a projection as a measurement.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `log.sh`.

*Schemas below — use the one that fits the moment. Prefer the artefact (the query output, the quoted line, the option's cost) over narration.*

## 📏 Measured
*   **Claim**: "[the assertion]"
*   **Number & denominator**: "[N of M]"
*   **Date & source**: "[when it was taken · the file / query / report line]"
*   **Where the working will live on the page**: "[inline / behind a disclosure / workings appendix]"

## 🔗 Inferred
*   **Claim**: "[the conclusion, not itself observed]"
*   **The step**: "from [X], because [Y]"
*   **Falsifier**: "[the observation that would show it wrong]"

## 🧭 Proposed
*   **The shape / option / sequence**: "[what does not exist yet]"
*   **What it is for**: "[the part of the question it answers]"
*   **Falsifier or cheap check**: "[what would make it obviously wrong, or obviously right]"
*   **How it will render as proposed**: "[the visual convention — dashed border / `proposed` chip / distinct ground]"

## 🎯 Falsifier
*   **Claim it attaches to**: "[which claim or option]"
*   **What would falsify it**: "[the observation]"
*   **Cost of that check**: "[cheap / a day / needs a labelled corpus]"

## 💰 Option-Costed
*   **Option**: "[name]"
*   **Fixes**: "[what it removes]"
*   **Leaves unfixed**: "[what it does not touch — an empty field means under-examined]"
*   **Risks**: "[what goes wrong if this is the wrong call, and how you'd notice]"
*   **Cheap check that would size it**: "[the small piece of work]"

## 🪑 Do-Nothing
*   **Present?**: "[yes / ruled out by [who] on the grounds that [what]]"
*   **Its real risks**: "[drift · compounding cost · decision by default — not a strawman]"
*   **Where it genuinely wins**: "[if anywhere]"

## 🧱 Assumption
*   **Taken on faith**: "[the premise]"
*   **What would break it**: "[the observation]"
*   **What rests on it**: "[which claims or options collapse]"

## 🖼️ Asset-Rendered
*   **Asset**: `[<assetDir>/<file>]`
*   **Kind**: [grounding — captured from the real source / **proposed** — depicts something that does not exist yet]
*   **From / how**: "[the real source + command, or: hand-authored SVG of the proposed shape]"
*   **Shows**: "[what the reader will see in it]"

## 🕳️ Asset-Failed
*   **Wanted**: "[the grounding asset I could not capture]"
*   **Why**: "[no renderer / source unreachable / the measurement was never taken]"
*   **Degrade**: "[how the page makes the point without it — or, if the measurement doesn't exist, the cheap check it becomes]"

## ⬇️ Downgraded-To-Preference
*   **Claim as first drafted**: "[what the page was about to assert]"
*   **Why downgraded**: "[nothing could falsify it]"
*   **How it appears now**: "[stated as a preference, in that word, at …]"

## 📦 Moved-To-Workings
*   **What moved**: "[the exhibit / query / table]"
*   **Why**: "[it was in the reading path and a reader who skipped it could not state the direction / it was bulk a persuaded reader shouldn't walk through]"
*   **Now reachable at**: "[the disclosure / appendix section]"
