# Decision Record — <subject / thread>

**For**: <who reads this later — the conductor, the next pass, a teammate> · **Decided**: <YYYY-MM-DD> by <who> · **Pass**: <n>

**What this is**: the forks that were blocking work on <subject>, and how each was settled. Each entry carries what was decided **against**, so a later pass can tell a closed question from an open one.

**Board**: <S3 URL — a pass renders one unless the operator passed `--no-board`, which is recorded here as `--no-board — <who asked>`>
**Board state**: <the conductor's ledger row that owns this board's `docId`, fold and read status — the authority. `no ledger — handles below` when running standalone, and only then:> `docId` <id> · state doc <url>
**Panel**: <ran — one run over the whole board, N lenses, report path | not offered | declined>
**Items file**: <the `--items` path, and `written back` or `read-only — <reason>`; `none — mined` on a mining pass>
**Vocabulary**: <the caller's outcome terms when `--vocabulary` was passed, else `default dispositions`>

---

## Decided

### [1] <the fork, as a question>
- **Blocked**: <the thread / file / dispatch that was waiting, and since when>
- **Unblocks**: <what moves now that this is settled>
- **Options as framed**: <A — trade-off> · <B — trade-off> · <the honest do-nothing>
- **Decided**: <the chosen option, in the lane's own terms>
- **Decided against**: <each rejected option and the one-clause reason it lost>
- **Falsifier / revisit trigger**: <the observation or event that reopens this>
- **Panel read**: <per lens — `<lens>` (weight): <the one-line why>; its `alternative` and `thinGrounds` where declared. A lens count belongs here only under this label. `none` where no panel ran.>
- **Said in prose**: <any `note` / `field` answer left on the board that no option key could hold — the thought nobody had to compress>
- **Provenance**: <the log line, report finding, or handback that established the fork>

*(repeat per decided item)*

## Deferred

- **[n] <fork>** → returns on <the named trigger>. Still blocks: <what>.

## Delegated to the lane

- **[n] <fork>** → <lane / agent> chooses, bounded by <the constraint it must stay inside>.

## Routed out

- **[n] <fork>** → `/interrogate` — needs <the information> before it is decidable.
- **[n] <fork>** → inbox — nothing was waiting on it.
- **[n] <fork>** → dropped: <why it dissolved, so it is not re-mined>.

## Noted, no action

- <one line per `I've-got-this` / `FYI` item — what and why no action>

---

## Open after this pass

<the forks still unsettled, and what each still holds up — the next pass's starting worklist. `none` is a valid and good answer.>
