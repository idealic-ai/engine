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
- **`attachments`** (`type:"note"`, optional, Slack-sourced only) — files that arrived with the reply this note came from, as `[{name, mimetype, permalink, local_path?}]`. The board's copy path never emits it: a browser payload has no files. Absent and empty mean the same thing; a reader must not distinguish them.
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

### Ingestion (orchestrator, Phase 6) — **three sources, one rule-set**

Answers reach the wave by **three** routes, and the rules below apply identically to all of them. Which route an answer arrived by is a delivery detail; it must never change how it is counted.

1. **A pasted payload** — the kit's *Copy answers* button, newline-delimited, handed over in chat. Always available; it is the path that still works when the board's write window has expired, when signing was unavailable at publish, or when a POST failed.
2. **A fetched state doc** — `state/<docId>.json`, when the board carried a shared-state config and teammates voted **in the page**. Its envelope is `{"docId": …, "events": [ … ]}`; take `events` and treat each entry exactly like a pasted line. Its URL is recorded beside the board URL in `INTAKE.md` (Phase 5).
3. **A Slack reply** on the announce thread, drained by the *next* wave's Phase 1 Ingest (`engine slack-read`). A reply is prose, not a keyed option — it becomes a **`note` event**, never a `vote`, and it is one step *more* advisory than a board answer, not less. Mapping, all of it derived from what already exists:
   - **`item`** — the id cited by the reply's `[n]` ref, resolved through the announce's decision-refs block (`[3]` → that ref's `<board-url>#<item-id>`). The number is display only; the anchor carries the identity.
   - **`actor`** — `{kind:"human", name:<the Slack display name `slack-read` resolved>}`, so `actorId` is `h:<name-slug>` exactly as a board voter's is.
   - **`ts`** — the reply's Slack `ts`. **`id`** — `n:<actorId>:<item>`, the schema's existing `note` id.
   - **A file on the reply rides on the note, under the reply's own anchor** — `attachments`, populated from `slack-read`'s `files[]` (`name`, `mimetype`, `permalink`, and `local_path` when the bytes were downloaded). **This is the existing anchor rule, not a new one**: the anchor binds the *reply* to an item, and a screenshot attached to that reply is evidence for that same item. It follows that an **un-anchored** reply's file is wave-level signal in `INTAKE_DRAIN.md`, exactly as its prose is — a file cannot be attributed to a decision its own reply was not attributed to.
   - **A file-only reply (empty `text`) still becomes a note** when it carries an anchor, with `note` empty and `attachments` populated. A screenshot is how most visual defects get reported; dropping it for having no prose would discard the whole answer.
   - **`local_path` is a path on the machine that ran the read, and nothing more.** It is not durable, not shared, and not meaningful to any other reader — the `permalink` is the identity that travels. Never persist `local_path` into a board, a ticket, or anything another person opens.
   - **No anchor cited → it does NOT become an event.** It stays a wave-level drop in `INTAKE_DRAIN.md`, surfaced as ordinary signal. **Never infer which item an un-anchored sentence answers** — attributing prose to a decision by guesswork is worse than leaving it unattributed, because a wrong attribution is invisible once tallied.
   - **The cross-transport dedup falls out of the existing supersede rule** with no new machinery: one person answering both in Slack and on the board is one `(actor, item)` pair, and the greater `ts` wins. **Its one dependency is the name-slug matching across transports** — a Slack display name of "Justin H." and a board voter name of "justin" slug to different actors and will silently count twice. That is a real limit, not a solved problem: check the names when a wave has answers on both transports.

**The state doc is an append-only LOG, not a settled view.** The fold that writes it appends blindly and reconciles nothing, so duplicates and superseded answers are *expected to be present*. That is not a defect to route around — it is why steps 2's rules below are a **read-side** obligation for every reader, this ingest included. A reader that skips them will double-count and will resurrect answers their author already retracted. Transport detail: `~/.claude/engine/skills/prove/assets/STATE_TRANSPORT.md`.

**Any two routes may deliver the same answer.** A teammate who voted in the page *and* pasted produces two copies of the same events, with the same `id`s — step 2 collapses them exactly, which is the whole reason the ids are deterministic; a Slack reply from someone who also voted on the board collapses the same way, by `(actor, item)` under the supersede rule. Merge **all** sources into one list and run the rules **once over the union**; never tally them separately and add the totals.

**A `reader` reaction may appear in a fetched doc and never in a pasted one.** Exclude it from the human tally and from the council's, per the contributor filter above — do not treat its presence as a malformed doc.

1. Parse each line (pasted) / each `events[]` entry (fetched). **Malformed → say so and ask for a re-paste; never silently mis-tally.**
2. Dedupe by `id`; apply the supersede rule.
3. Group by `item`. Tally **human** votes by `key` — that is the teammate tally, and panel votes never enter it. A `reader` event is normal in a **fetched** doc and out of place in a **pasted** payload (the copy path cannot produce one): in either case never bucket it as human or council; in the pasted case, say so.
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
