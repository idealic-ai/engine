# Outcomes Board Handoff Prompt — scaffold

The orchestrator fills this to dispatch the **Outcomes Board** render subagent at wave **Close** (Phase 7), after dispositions are confirmed. The board is a **static, faithful RECORD of what the wave actually did** — the actions-taken proof. No widgets (nothing left to collect; the decisions are made). It reuses `/prove`'s render discipline (real content, self-contained, honest scope block) and publishes to S3.

It is the second half of the wave's two-board arc: the interactive **Decision Board** (Phase 5) is where the wave decides; the **Outcomes Board** (Phase 7) is where the wave records. It is the "final actions-taken proof" the wave's Project Update / Slack announce links at close (`§PASS_HEARTBEAT` event 2).

**Repeatability = this handoff pins WHAT to record; the agent is free in HOW** (`¶INV_BOARD_HANDOFF_IS_FIXED_PRESENTATION_IS_FREE`). Content is never compressed away — the full working doc + triage reports travel + pointers (`¶INV_HANDOFF_STRUCTURED_NOT_LOSSY`).

Save the filled prompt to `builds/<wave-slug>-outcomes-board-handoff.md`; dispatch. The subagent writes `builds/<wave-slug>_OUTCOMES_BOARD.html`; the orchestrator publishes it (`§ Publish`).

---

## Fill this

**Wave**
- **Project / initiative + domain goal**: […]
- **Wave slug** `<wave-slug>` · **Wave** `<project> wave <n>` · **Window** `<since> → <now>`
- **Directions in force** (verbatim): […or "none set"]

**Full sources that travel** (record FROM these — pointers, not digests)
- **Working doc**: `INTAKE.md` `<path>` — the item registry, dispositions as applied, ranked "pull first", root-cause map.
- **Triage reports**: `builds/inbox-triage-<id>.md` … (for the evidence behind each call).
- **The Decision Board** (this wave's, if published): `<url>` — so the record can point back at where the decisions were made.

**Required coverage** (what every Outcomes Board records — layout is yours)
- A wave header: project · wave · window · honest counts (ingested `<N>` · filed `<F>` · merged `<M>` · adopted `<A>` · cancelled `<C>` · marinating `<R>`).
- **Per-item disposition TAKEN** — for each item the wave acted on: what happened, concretely — **filed** `FIN-X` (→ which milestone) · **folded/merged** into `FIN-Y` · **adopted** (stray → moved to `<milestone>`) · **cancelled** (→ `Cancelled`, with the reason) · **marinating** (why it's held). Each with its evidence pointer.
- **The ranked "pull this first, and why"** (`¶INV_RANKING_WITH_PROOFS`) — the durable ordering that guides doers, with the number behind each call.
- **A signal-provenance recap** — *where the signals came from & how*: per-channel counts, how they were drained + triaged, the Directions this wave ran under.
- The `/prove` **scope block** — *what this records (the actions taken, faithfully) · out of scope (the downstream work itself — dispatched, not done here) · what rests on trusted triage.*
- An **as-of stamp** — "recorded `<ts>` · Linear is authoritative". This board is a frozen S3 snapshot of the wave's decisions; a disposition can change in Linear afterward (a reply un-resolves a thread, a ticket is re-milestoned or closed), so state plainly that Linear — not this page — is the live truth, and this is the picture as of the render time.
- A closing note: **"these are done or dispatched — nothing was executed by the wave"** (`¶INV_INTAKE_DISPATCHES_NEVER_EXECUTES`), the wave's honest record.

**Presentation** (yours to design well — load `Skill(artifact-design)`)
- Self-contained + CSP-safe (inline all CSS/JS, embed assets as `data:` URIs, no external hosts), theme-aware (light+dark), responsive. Honest `<title>` + emoji favicon.
- **No widgets** — this board records; it does not collect. (Widgets live on the Decision Board only.)

**Output contract**
- WRITE the self-contained HTML to `builds/<wave-slug>_OUTCOMES_BOARD.html`.
- Notebook-log every ~5 tool calls via `engine log <session log path>`.
- RETURN a tight manifest: dispositions recorded (counts by kind), any asset that failed, and the HTML path. Do NOT dump the HTML/base64.

## Integrity pass + publish (orchestrator, after the subagent returns)
- **Integrity pass** (`¶INV_PROVE_FAITHFUL_PRESENTATION`): confirm each recorded disposition matches the working doc (filed keys, milestones, reasons are real), captions match assets, nothing oversells, the scope block is unburied.
- **Publish**: `~/.claude/engine/skills/prove/assets/publish-s3.sh builds/<wave-slug>_OUTCOMES_BOARD.html <wave-slug>-outcomes` → capture the public URL for the Project Update edit + the `§PASS_HEARTBEAT` event-2 Slack. If `PROVE_S3_BUCKET` is unset, keep the `builds/` file + poke the user; never fabricate a URL.
