# Revise Report — <CHUNK / CHANGE>
**Tags**: #needs-review
*Written by the writer sub-agent at the end of its run. The authoritative account of which documentation claims this change falsified and what was done about each. Read downstream by the conductor's doc register (the rows owed), by `/scrutinize` (the edits and the verdicts), and by the next revise lane (the claims left standing, so it does not re-check them).*

## Change under revision
<the subjects — the behaviours, contracts, defaults, thresholds, names and locations a reader could have been told — then the authoritative file list the change touched, and where that list came from (a Build Report's `## Files touched`, an explicit set, or a git range with the exact command).>

## Claims found and ruled
<one bullet per located claim. A claim is a sentence, not a file. Every verdict carries the command that produced it and the control run in the same invocation.>

- `path/to/doc.md:LINE` — "<the sentence, quoted>" — asserts: <what a reader would check> — **falsified** — <the command, its control, and what is true instead>
- `path/to/other.md:LINE` — "<the sentence>" — asserts: <…> — **true** — <the command and control that established it>
- `path/to/third.md:LINE` — "<the sentence>" — asserts: <…> — **unverifiable** — <the command that WOULD settle it, and why it could not run here>

## Edits made (authoritative)
<the exact files changed and, per file, which claim each edit repairs. Nothing else in the working tree belongs to this run.>

- `path/to/doc.md` — <claim at :LINE> → <the new statement>

## Claims left standing
<claims ruled true and deliberately not edited, named so the next lane does not re-check them. This field is a gift forward; "none" only if genuinely none were true.>

## Stale twins checked
<for each edited file, the second copies of its own claims that were re-read after the repair — overview paragraph, scope block, summary, frontmatter `description` — and whether each needed a change. A body repaired while the summary carries the old version reads as though the page were checked.>

## Register rows owed
<work found and deliberately not done, each with its destination. These become the conductor's register rows.>

- **index / TOC reconciliation** — <what the index now misstates> → `/document`
- **stale page outside this change** — <path and what looks wrong> → `/document`
- **undocumented change with no home** — <what has no claim anywhere> → escalate; the home is a decision about the tree
- **code defect** — <what is wrong in the code rather than in the prose> → the thread that owns it

## Instrument notes
<how each zero was proved: the positive control, the negative control and why it was a token this document does not itself contain. Name whether a count is lines or occurrences.>

## Blockers
<anything that stopped progress, with the options rather than a guess. Empty if none.>
