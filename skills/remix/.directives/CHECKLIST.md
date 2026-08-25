# Remix — Close Checklist

Processed by `§CMD_PROCESS_CHECKLISTS` during synthesis; a **hard gate** on session close (`¶INV_CHECKLIST_BEFORE_CLOSE`). Evaluate every applicable item and quote the result back to `engine session check`. Items marked *(page/tend)* apply only when the mode built or repaired a renderable artifact.

## The Look — `¶INV_DS_LOOK_AT_IT` *(page/tend, and any mode that produced a render)*
- [ ] Every render was **opened** — the config's full render matrix (every theme × every viewport; for `warm-print`: light AND dark, 1400 AND 390). (Not "rendered" — *opened*. The PNG is the instrument for the glyph class.)
- [ ] Both **body overflow** AND **per-element clipping** were asserted, with the clipper **named** (`¶INV_DS_ASSERT_THE_LOSS`). A body-overflow-only pass is not a pass.
- [ ] Every measurement printed its **control** first (parser control before contrast; isolation control before a layer claim).

## Honesty rules *(any mode that shipped colour/encoding)*
- [ ] Every colour that encodes a fact ships a **legend** (`¶INV_DS_ENCODE_OR_OMIT`) — no key ⇒ colour removed.
- [ ] Every meaning-bearing colour has a **non-colour channel** too (`¶INV_DS_NON_COLOUR_CHANNEL`).
- [ ] Absent facts render distinct from false ones and from zeros (`¶INV_DS_MISSING_NOT_EMPTY`).
- [ ] No stylesheet makes an **un-announced cut** (`¶INV_DS_CUTS_ARE_ANNOUNCED`).

## The Digest — `¶INV_DS_DURABLE_OVER_WARM`
- [ ] Every number that will cross a future dispatch boundary was **appended to `FACTS.md`** with how it was measured (`¶INV_DS_FACTS_ARE_CITED_NOT_COPIED`) — not left only in prose.
- [ ] Every channel this session used was **registered** in `REGISTRY.md` before it was dispatched on (`¶INV_DS_REGISTER_BEFORE_DISPATCH`); any collision was surfaced as a finding, not silently overwritten.
- [ ] *(tend)* The digest was **regenerated** and re-stamped with its freshness marker + corpus delta.

## Integration accounting *(orchestrate)*
- [ ] Every finding the wave produced is **landed**, **ticketed**, or **explicitly deferred with a reason** — none left unaccounted. Integration is the unpriced half; a wave does not close without this.
- [ ] Every ruling recorded **what was decided AND why**.

## Provenance
- [ ] Claims relayed to the human are labeled **verified-at-source** vs **agent-reported**; the orchestrator verified its **own briefs**, not only the agents' returns.
- [ ] Any reconciled count was **run against `FACTS` ids**, not asserted from memory.
