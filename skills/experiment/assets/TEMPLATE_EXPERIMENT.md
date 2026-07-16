# Experiment — <slug>
*The experimenter subagent (`/experiment` §2) fills this and WRITES it to `<trailDir>/<slug>_EXPERIMENT.md`. It records what was TRIED and what was OBSERVED — raw evidence, not just claims. The orchestrator reads this back for the verdict relay + disposition gate (§3), and stamps the Disposition line at the end.*

## Hypothesis
<The single claim under test, stated so it can be falsified.>
*(Illustrative — adapt, don't copy: "The `extract_entities` function drops the final chunk if the token count is exactly 1024.")*

## Success Criteria
- **Proved if:** <The specific observation that would confirm the hypothesis>
- **Disproved if:** <The specific observation that would refute it>

## Environment / Setup
<What the run is against. Keep it to 1-2 lines. Include:>
- `branch@shortsha`
- Data/fixtures or seeds used
- Tool/runtime versions (only if they bear on the result)

## Method — What I Tried
<The approach taken, the vehicle used (throwaway test / scratch script / REPL / manual run / temporary edit), and **why** that vehicle was chosen. If the method was refined across multiple attempts, briefly note the progression.>

## Observations — What Happened
<Raw evidence, not assertions. Map exact commands/inputs to actual outputs. Paste the telling lines (a failing assertion, a log line, a specific value, a timing). This is the load-bearing section — a reader MUST be able to trust the verdict based solely on what is pasted here.>

```bash
# <Command run>
$ <exact command>

# <Actual output / result>
<paste raw logs/output here>
```

**Repro command:** `<One exact, copy-pasteable line to re-run the decisive probe>`

## Verdict
**<PROVED | DISPROVED | INCONCLUSIVE>** · Confidence: **<HIGH | MEDIUM | LOW>**

**Rationale:**
<One-paragraph justification tying the raw observations back to the success criteria. A clean **DISPROVED is a fully successful experiment** — state it plainly, don't hedge it toward "proved." If inconclusive, state exactly what blocked a clean answer (couldn't reproduce the setup, hypothesis was ill-posed, ran out of signal, hit the ~3-attempt probe cap).>

## Scope of Verdict / Not Tried
<What this verdict does NOT cover. List inputs, edge cases, or conditions deliberately left untested — bounding the current claim. Distinct from the forward "threads left open": this bounds what was proved, not what to do next. "Nothing material" is acceptable.
*(Illustrative — adapt, don't copy: "Tested on PDF and TXT, but did NOT test on DOCX.")*>

## Assumptions That Could Be Wrong
<The load-bearing beliefs this verdict rests on — "what would make this conclusion invalid". Bounds the certainty of the verdict so the reader knows exactly where it is fragile.
*(Illustrative — adapt, don't copy: "Assumed live extraction is heading-only; if real docs flow scope entities into a path where the flat-table item nanoid is consumed durably, this verdict is invalid.")*>

## Reusable Facts Discovered
<Durable truths about the codebase, data, or environment that this experiment PROVED (distinct from the main hypothesis verdict) — carry-forward know-how for the next `/build` or `/analyze`. The orchestrator appends these to LESSONS.md.
*(Illustrative — adapt, don't copy: "The `<g clip-path>` group carries NO transform; clipPath coords are in the same raw page-point space as the `<use>` origin — no transform correction needed.")*>

## Threads Left Open
<Neutral forward pointers — questions this experiment surfaced but didn't answer, a possible next probe, or a related unknown. Information for whoever picks it up (e.g., via `/ticket`), NOT a recommendation to act. "None" is acceptable.>

## Touched Files
*Complete list of files touched by the experiment. The orchestrator relies on this for a clean revert against the baseline, so NOTHING may be omitted.*

- **Created:** <New files, e.g., `x.experiment.test.ts`, scratch scripts>
- **Modified (Clean at baseline):** <Existing files edited to observe behavior. These can be safely reverted via `git checkout -- <path>`.>
- **Modified (Dirty at baseline):** <Files that ALREADY had parent edits. **CRITICAL:** These must be restored from backup (`<trailDir>/backup/<path>`), NOT via `git checkout`.>
- **Ran (No file change):** <Commands/probes that touched no files, if relevant>

## Disposition
*(To be stamped by the orchestrator after §3)*
< `reverted (tree clean)` | `kept for /implement: <files>` | `kept selective: <files kept> / <files reverted>` >
