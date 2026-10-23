---
name: dehydrate
description: "Run the pre-work a hand-over owes BEFORE context dies, then hand off to the `§CMD_DEHYDRATE` atom. The host skill's closing duty first (for a loom: the mechanical sweep, the live registers brought current, `LOOM_INHERITANCE.md`), then the log receipt, then the atom — which stores and restarts. It composes the atom and never reimplements it; every step it adds is cheap enough to run at 95% context, and an expensive one degrades to a debt named in the payload rather than blocking. Triggers: \"dehydrate\", \"hand this over before the context goes\", \"close out and restart\", \"I'm about to overflow\", \"wrap the loom and dehydrate\"."
version: 1.0
tier: lightweight
args: "[--handover-only] [--now]"
---

Do what the hand-over owes, then dehydrate.

# /dehydrate Protocol (The Hand-Over Before the Restart)

[!!!] This is a **sessionless utility** skill that **rides the host session** — the one already active. It has no session directory, no log and no debrief of its own; its entries go in the host's log. Same shape as `/session` and `/sweep`, for the same reason.

[!!!] **The atom is composed, never copied.** The last step is `§CMD_DEHYDRATE`, which is always preloaded and which owns the JSON shape, the `requiredFiles` cap, the context-level table and the restart. If you find yourself writing a schema here, you are duplicating it. `/session` deliberately redirects "dehydrate" to that atom (`skills/session/SKILL.md`) and **this skill does not reverse that** — the atom keeps the mechanics; what was missing is the pre-work.

## What this is for

`.directives/HANDOFF.md` declares this sequence under `### Loom hand-over: /sweep fires first`: a conductor about to hand over — write `LOOM_INHERITANCE.md`, **or dehydrate** — runs the sweep before it writes either, because the live-context half of a sweep exists only in the conductor's own context and dies with it. **Nothing executed that sequence** — a rule in prose with no executor, which `¶INV_A_RULE_IN_PROSE_IS_NOT_ENFORCED_UNTIL_A_CHECK_CAN_FAIL` names. This skill is the executor it lacked.

HANDOFF.md's section owns the rule; `skills/loom/assets/TEMPLATE_LOOM_INHERITANCE.md` owns the inheritance file's shape and address. **This skill cites them and does not restate them** — a copy drifts, a citation cannot.

### Its operating condition, which decides everything else

This skill runs when context is nearly gone, so **every step it adds must be cheap**: a key-selected state read, a bounded script, a blind append. A step that must read a large file cannot run at the moment this skill is for.

**Safe at 95%**: `engine session find` · a key-selected `jq` over `.state.json` · `engine sweep-check` read by exit status · any `engine log` append (a blind write — `¶CMD_APPEND_LOG`) · `§CMD_DEHYDRATE`, already in your context.

**NOT safe at 95%**, each with its measured cost: invoking `/sweep` as a skill (its `SKILL.md` is ~10KB and it warns against its own repeated load) · reading `TEMPLATE_LOOM_INHERITANCE.md` (~16KB) · reading the loom log to compose a register block (it grows all session) · reading an existing `LOOM_INHERITANCE.md` to merge rows. Each has a degraded substitute below.

⭐ **The resolution: dehydration is not a death, it is a restart into a fresh context.** The cheapest place to do an expensive write is *immediately after* the restart. So with no headroom, row what you can from memory into the log and put the expensive write into the atom's `nextSteps` with its absolute path in `requiredFiles` — the rehydrated agent does it as its first act. **A named debt beats a half-shaped file**: `TEMPLATE_LOOM_INHERITANCE.md` is explicit that a partial row acted on silently reproduces the loss the file exists to prevent, and a short file at the sessions root *looks complete*.

### Ordering: worst-first, so an interruption truncates the tail

Each step deposits durably before the next begins, and value descends down the list, so a death mid-run loses the cheapest half.

*   **The inheritance write comes BEFORE the log receipt.** A lost receipt costs a paragraph in a file that already holds the narrative. A lost inheritance file costs every open thread, board, owed doc, owed rule and open claim — it is the only artifact a *successor* reads.
*   **Inside the loom's duty the order is data dependency, not preference.** HANDOFF.md: *the sweep rows nothing itself, so the conductor rows what it accepts into the registers before the inheritance file carries them.* The inheritance file copies from the rows; written first, it is short rows.
*   **The atom is last** because it kills the process.

### No gates, no confirm

The overflow hook fires `§CMD_DEHYDRATE NOW` unprompted, so a blocking question would stall the one path that most needs to finish; a human who typed `/dehydrate` has already asked. **Every step degrades honestly in one line and the run continues** — nothing here is a hard requirement.

### Flags

*   `--handover-only` — run the pre-work and **stop before the atom**. This is HANDOFF.md's other hand-over: handing a topic to another seat without restarting.
*   `--now` — skip the headroom branch and go straight to the memory lane. What the overflow hook wants.

---

## 0. Establish the host and its state

Open with one line naming the host skill, its phase and the lane you are taking — no `§CMD_REPORT_INTENT` block. `.directives/commands/CMD_REPORT_INTENT.md` excludes utility-tier skills, `/sweep` carries none, and the atom announces again at the end; a second announcement is spend for nothing at the moment spend matters most.

⚠️ **`sessionDir` is not in `.state.json` on a live session.** It is absent, not null — a `// null` guard will not catch it, and the only `sessionDir` spelling in the file sits inside `phaseHistory[].proof`, so a grep finds the wrong one. Resolve the directory, then read **only the keys you need**; the live file runs past 20KB and `cat` is a file read you cannot afford.

```bash
SESSION_DIR=$(engine session find) || echo "degraded: no active session — skip to the receipt and the atom"
jq -c '{skill,taskType,currentPhase,contextUsage,lifecycle}' "$SESSION_DIR/.state.json"
```

*   **Compute the sessions root** as the parent of `$SESSION_DIR` — the root you can *prove* rather than the one you can name. `TEMPLATE_LOOM_INHERITANCE.md` owns why, including the physical comparison (`pwd -P`) a symlinked `sessions/` demands. Do not type a root from convention.
*   **Branch on `taskType`.** `LOOM` takes Phase 1-L. Anything else takes Phase 1-X.
*   **Choose the lane.** `contextUsage` at or above `0.95`, or `--now`: the **memory lane**. Below that: the **full lane**, where the reads named above are affordable. Read the number as informational per `§CMD_DEHYDRATE`'s level table — it is the budget, not an alarm.

**Degrades**: no active session → say so in one line, skip Phase 1 entirely, run the receipt and the atom. `jq` unavailable or the file unparseable → say so, assume the memory lane and a non-loom host.

---

## 1-L. A loom's closing duty

Only when `taskType` is `LOOM`.

### The sweep, mechanical half

Read its **exit status directly, never through a pipeline** — HANDOFF.md states this and `¶PTF_A_BACKGROUNDED_COMMAND_LOSES_ITS_PIPE` is why.

```bash
engine sweep-check "$SESSION_DIR/LOOM_LOG.md"
```

Exit 3 lists each decision no register block was written after, so it **cannot** have been rowed. Exit 2 is an instrument fault. Exit 0 means only that *no decision is certainly unrowed* — it compares no content, and `skills/loom/SKILL.md` records which registers it does not read at all, so a clean exit is not a clean log. Take that verdict as given; do not re-derive it.

### The sweep, judgement half

**Full lane**: invoke `/sweep`. It writes `builds/sweep-findings.md` for `/groom` and rows nothing itself.

**Memory lane**: ⚠️ do **not** load `/sweep`. Its live-context half is the half you already are — sweep your own memory inline for what you decided, parked, owed or found and never rowed, and say in one line that the dispatched file-sweeping half was skipped for context. `/sweep`'s own protocol sanctions this split; what you are skipping is the file reader, not the judgement.

### Bring the live registers current

Append a fresh copy of each register block that has a row to change — the loom's registers are rewrite-in-place by convention, and in an append-only log the **latest copy wins**. Row what the sweep surfaced and you accept: threads, boards, docs owed, rules owed, open claims, parked items, seat handovers.

⚠️ **A short Ledger-only append hides every earlier decision from `sweep-check`**, which cannot tell an update from a full rewrite. If you append a partial block, say so in the receipt so the next clean exit is not misread as rowed.

**Degrades**: no loom log at the path → one line, skip to the inheritance step. Nothing to row → say that, which is itself a finding.

### `LOOM_INHERITANCE.md`

Its address, its computed root, its `UNKNOWN — <why>` rule and its per-row `owner` all live in `skills/loom/assets/TEMPLATE_LOOM_INHERITANCE.md`, whose *Where it lives* section is normative. Follow it.

**Full lane**: read the template, read any existing copy at the computed root, claim and carry the rows.

**Memory lane**: ⚠️ the template and the existing file are both too large to read here. If their shape is **already in your context** (you wrote or claimed the file this session), write it from memory. If it is not, **do not invent a half-shaped file at the sessions root** — instead carry the rows in the register appends you just made, and hand the write forward: name it as the first entry in the atom's `nextSteps` and put the template's and the file's absolute paths in `requiredFiles`. The rehydrated agent writes it with a fresh budget.

**Degrades**: template absent → one line, and the hand-forward path above.

---

## 1-X. Any other host's closing duty

The host **declares its own closing duty in its own state file**, so read it rather than guess:

```bash
jq -c '.phases[-1]' "$SESSION_DIR/.state.json"
```

That is the host's final phase with its steps — a few hundred bytes, and a skill added tomorrow needs no edit here.

Then rule honestly. `§CMD_DEHYDRATE`'s level table bars document writing above 85%, and a synthesis pipeline is document writing, so for most non-loom hosts on the memory lane the verdict is **no closing duty is cheap enough to run here**. Say which duty you are not running and name it into the atom's `nextSteps`; do not attempt it.

What *is* cheap and worth doing for any host: an append that records the unfinished work in the host's own log schema. A plan with unticked steps, an interrogation round answered but not written, a finding established and not recorded — each is a blind append away.

**Degrades**: no `phases` in state → one line, go to the receipt.

---

## 2. The receipt

Execute `§CMD_APPEND_LOG` against the host's log. For a loom that is a `## 🤝 Hand-over written` entry. State what you did, what you degraded, and what you handed forward:

*   What the sweep found and which half ran.
*   Which registers you brought current, and whether any append was partial.
*   Where `LOOM_INHERITANCE.md` stands — written at `<absolute path>`, or handed forward with its reason.
*   Which steps you skipped and the context reading that decided it.

Keep it to what a successor acts on. This entry is the cheapest thing in the run and the first thing worth losing, which is why it is here and not earlier.

---

## 3. `§CMD_DEHYDRATE`

With `--handover-only`: **stop here.** Report the pre-work and the atom you did not run.

Otherwise execute `§CMD_DEHYDRATE` from your context. It owns the announcement, the JSON, the `requiredFiles` cap and the restart, and it is the last command that runs.

What this skill adds to the payload it hands the atom:

*   **`nextSteps` opens with every write you handed forward**, in the order above — the inheritance file first where it is owed, because the rehydrated agent's fresh budget is the whole reason it was deferred.
*   **`requiredFiles` carries the absolute paths those writes need**, inside the atom's own cap and priority order. The computed sessions root goes in the payload as a path, never as a convention for the successor to re-derive.

Then it restarts. Nothing follows it.
