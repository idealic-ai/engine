# Decision Board — Return Payload Schema

The **answers** a Decision Board sends back, produced by the widget kit's "Copy answers" button and pasted into a wave. **This file owns the ingest rule outright** — `SKILL.md` Phase 6 states the intent in a sentence and points here. One place to edit; the rule used to be written out in both files, which is how two specs drift.

Deliberately **answers only** (`¶INV_BOARD_PAYLOAD_IS_ADVISORY`): it carries *what was picked*, never the facts (those were rendered on the board from the rich handoff). Its rigidity loses nothing.

---

## v2 — an event stream (current)

**Newline-delimited JSON: one event per line, each line self-contained.** A single line pasted on its own is still a valid, complete answer.

```jsonl
{"v":2,"board":"intake-sys-wave2","wave":"Intake System wave 2","type":"vote","id":"v:c:skeptic:finding:FIN-3461:do-it-now","ts":"2026-07-31T09:14:02Z","actor":{"kind":"council","lens":"Skeptic","icon":"🔍","rosterVersion":4,"report":"builds/intake-sys-wave2_COUNCIL_20260731T0914.md"},"item":"finding:FIN-3461","itemKind":"steer","key":"do-it-now","weight":5,"why":"The four numbers are one query; every wave that runs first makes the baseline a reconstruction.","alternative":"","thinGrounds":false}
{"v":2,"board":"intake-sys-wave2","wave":"Intake System wave 2","type":"vote","id":"v:h:yarik:finding:FIN-3461:measure:verify-payload-retains","ts":"2026-07-31T11:02:40Z","actor":{"kind":"human","name":"yarik"},"item":"finding:FIN-3461","itemKind":"steer","key":"measure:verify-payload-retains"}
{"v":2,"board":"intake-sys-wave2","wave":"Intake System wave 2","type":"note","id":"n:h:yarik:finding:G1","ts":"2026-07-31T11:02:40Z","actor":{"kind":"human","name":"yarik"},"item":"finding:G1","note":"also check the 20-page OCR cap"}
{"v":2,"board":"intake-sys-wave2","wave":"Intake System wave 2","type":"field","id":"f:h:yarik:FIN-9001:milestone","ts":"2026-07-31T11:02:40Z","actor":{"kind":"human","name":"yarik"},"item":"FIN-9001","field":"milestone","value":"Needs research"}
```

### Why an event stream rather than a snapshot

Three reasons, in the order they matter:

1. **Human and panel answers are the same kind of thing.** Both are *an actor took a position on an item*. Modelling them as one record type with a required `actor` puts the distinction **on every line a reader sees**, rather than in a tree position a reader must know the schema to decode.
2. **It is the shape the multiplayer layer already chose.** `/prove`'s shared-state work settled on event-append plus an owner that folds, because S3 has no append and browser-direct compare-and-swap is not presignable. A snapshot payload would have to be migrated to this anyway.
3. **The panel's answers exist for items no human touched.** A snapshot only emits items the voter interacted with — see the v1 note below — so panel answers nested inside those items would silently thin.

### Fields

- **`v`** — schema version. `2`.
- **`board`**, **`wave`** — board identity, repeated per line so a line stands alone.
- **`type`** — `vote` | `note` | `field` | `reaction`. Discriminated, so a new kind can be added without reshaping the existing ones.
- **`id`** — stable event id (see *Ids and dedupe*).
- **`ts`** — ISO-8601. **Every event from one copy action shares one `ts`.** That is what makes the supersede rule below work.
- **`actor`** — **required on every event.** `kind` is one of `human` | `council` | `reader` (see *Two scopes* below — the board's copy path only ever emits the first two). `{kind:"human", name}` · `{kind:"council", lens, icon, rosterVersion, report}` · `{kind:"reader"}`, optionally with whatever opaque handle the transport assigns. `icon` is the persona's own icon from the council roster, carried here so the board and the ingest need no persona registry and stay uncoupled from `rosterVersion`.
- **`item`** — the widget's `data-fb-item` id. **`itemKind`** — `steer` | `consolidation` | `adopt-cancel`.
- **`key`** (`vote`) — the option key. Stable machine ids the orchestrator authored (`needs-research`, `fold-into:FIN-1234`, `measure:extraction-count`, `approve`, `adopt`); labels are display-only and never travel.
- **`weight`**, **`why`**, **`alternative`**, **`thinGrounds`** (`vote`, council only) — the conviction 1–5, the one-line reason, an option the expert would have wanted offered, and whether it declared the grounds too thin to rule. The full reasoning cards stay in the council report.
- **`note`** (`type:"note"`) — free text for an item. Any fact the option keys can't capture, so a voter is never forced to compress a thought into a checkbox.
- **`field`** / **`value`** (`type:"field"`) — structured extras: `adopt` carries `milestone`, `cancel` carries `reason`.
- **`target`** / **`value`** (`type:"reaction"`) — reader-only: what was reacted to, and `up` | `down`. Reactions are **aggregated at the fold**, never tallied per-item alongside votes. Shape detail belongs to `prove/assets/STATE_TRANSPORT.md`; this file only reserves the slot in the vocabulary.

### Two scopes share one vocabulary

The same event grammar is written by two different paths, and they do not carry the same set of kinds. Naming only the kinds one path emits is correct for that path and silently wrong for the other — which is how a writer produces a kind the reader's enum has never heard of.

- **The board's copy path** (this file's subject — the kit's *Copy answers* button) emits **`human`** and **`council`** only. It has no reaction concept and never will: a reaction is not a position on a board item.
- **The transport's event inbox** (the shared-state layer, `STATE_TRANSPORT.md`) additionally carries **`reader`** reactions posted from a published page. Once the kit gains a submit branch, both paths write into the same event prefix, and a fold reading that prefix meets all three kinds.

So `reader` is **absent by design from a copy-back payload and real at the transport layer**. A validator for a pasted payload may reject `reader`; a fold over the event prefix must not.

### `actor.kind` is the load-bearing field

It is required on every event, and it is not a formality. The wave's contributor instrument counts **distinct human contributors per pass** — the abandonment alarm: if contributions collapse to one person, the cross-functional premise is dead however healthy the totals look. An answer that cannot be attributed to a *kind* of actor inflates that count with a machine and disables the one measurement that detects the system dying.

**The filter is `actor.kind == "human"`, and all three kinds must be named for it to stay honest**: `council` is a machine and is excluded; **`reader` is excluded too, and belongs to neither bucket** — a reaction on a published page is not a contribution to the pass and must never be counted as one, nor quietly folded into the council's. An unenumerated kind arriving at this filter either inflates the human count or vanishes from every bucket; both break the alarm, which is why the enum above lists what each path can actually write rather than only what this one does.

It is also why panel answers are events rather than a block nested on an item: the kit only emits items a voter actually **touched** (a deliberate "keep the payload about real answers" rule). Panel answers nested inside items would vanish for every item a given voter skipped — no error, the record just thins. Keep them first-class.

### Ids and dedupe

- `vote` → `v:<actorId>:<item>:<key>` · `note` → `n:<actorId>:<item>` · `field` → `f:<actorId>:<item>:<field>` · `reaction` → `r:<actorId>:<target>`.
- `<actorId>` is `c:<lens-slug>` for council, `h:<name-slug>` for a human, `r:<opaque>` for a reader.
- **Council events are static** — rendered into the board, identical in every reader's copy. Every paste therefore carries them, and their deterministic ids collapse the duplicates exactly. No divergence logic is needed: one wave publishes one board, from one render.
- **Supersede rule**: for each `(actor, item)`, keep only the events carrying that pair's **greatest `ts`**. A voter who changes their mind and copies again supersedes their own earlier answers for that item wholesale — which is what makes an unchecked box actually retract.

### Ingestion (orchestrator, Phase 6)

1. Parse each pasted line. **Malformed → say so and ask for a re-paste; never silently mis-tally.**
2. Dedupe by `id`; apply the supersede rule.
3. Group by `item`. Tally **human** votes by `key` — that is the teammate tally, and panel votes never enter it. A `reader` event reaching a pasted payload is out of place (the copy path cannot produce one): say so rather than tallying it, and never bucket it as human or council.
4. Present the panel separately: per `key`, **which lenses picked it and at what weight** — never a bare count, which flattens a 3–2 split into "3 for this one" and hides the more informative outcome. Surface dissent, any `alternative` an expert named (feedback on whether the option set itself was right), and any `thinGrounds` vote as such.
5. Both are an **advisory leaning** at the chat confirm. Every disposition / consolidation / adopt / cancel still passes the human confirm (`¶INV_TICKET_EARNED_BY_CONFIRM`). A panel vote is one layer further from authority than a teammate's, and nothing in how it is presented may imply otherwise.
6. Any `measure:*` key → queue/re-open triage on that item (unbounded re-open; the operator closes).

---

## v1 — legacy, still accepted

A board rendered before v2 carries its own inlined copy of the kit **permanently**, so it will emit this shape forever. Ingest keeps accepting it.

```json
{ "board": "…", "wave": "…", "voter": "…", "ts": "…",
  "items": [ { "id": "…", "kind": "steer", "selected": ["…"], "fields": {…}, "note": "…" } ] }
```

- **Discriminating the two**: v1 parses as a single JSON object with an `items` array; v2 is newline-delimited records. Check that — v1 carries no version field to test.
- **Reading it**: each `items[]` entry maps to one `vote` event per `selected` key, plus a `note` / `field` event where present, with `actor` = `{kind:"human", name:<voter>}`. It carries no panel answers, and that is the correct reading of a board that had none — never infer one.
- A **v2** board where no council ran likewise carries no `council` events. A council that fails to seat writes no report rather than faking one, so an absent panel is a normal outcome and never a parse failure.
