# Triage Handoff Prompt — scaffold

The orchestrator fills this to dispatch a triage sub-agent (`/inbox-triage`, else `/probe`) on a not-yet-ticketable inbox signal. It must be **self-contained** (`¶INV_REQUEST_IS_SELF_CONTAINED`) — enough for the doer to start cold, with pointers to pull more. Save the filled prompt to `builds/inbox-triage-handoff-<origin-id>.md` and **attach it to the origin comment alongside the triage report** — so the full chain (question → answer) is reproducible and re-analyzable.

Triage is **light** — gather detail, reproduce, find related tickets — enough to make the signal ticketable. It is NOT deep research (that runs on a graduated `Needs research` ticket).

---

## Fill this

**Signal**
- **Origin**: [project · channel · origin comment URL/id]
- **Reported by**: [name] · [date]
- **What they said** (verbatim or tight paraphrase): […]
- **Attachments / screenshots**: [what's there — e.g. "2 screenshots of the Policies tab showing 'Extraction failed' rows"]

**What this triage must find out** (the specific gaps blocking a ticket)
- [ ] [e.g. which org/account + claim this is — infer from the screenshots via the read-only DB]
- [ ] [e.g. the page URL + claim id]
- [ ] [e.g. is it still reproducing? how often?]
- [ ] [e.g. any existing related/duplicate tickets]

**From the project's Inbox Handbook** (`¶INV_CHANNEL_MACHINERY_IN_ONE_DOC` — the shared machinery, held once per project)
- […paste the parts that bear on this triage: **this project's `## What triage will chase`** (its own recipe — it names the tools that actually identify a subject here, so paste it in full and never substitute another project's), what a ripe item looks like here, how a comment becomes a ticket. Or "no handbook on this project yet — the generic recipe below is the fallback."]
- Pasted, not linked: **you cannot read the project**, so anything not in this prompt does not reach you.

**Recipe** (do what's reachable; degrade gracefully when a source is missing)
- **Branch by report shape first** — a single failure needing a *cause* → start from the most detailed per-incident record (workflow history / the failed row); a recurring "keeps happening" report needing the *pattern* → start from an aggregate/histogram query (rate, onset, breadth), then drill into whichever incidents are still recoverable. The aggregate is what reveals a "recurring" report is often several different failures, not one bug.
- **Identify** account/org, claim, page URL from the screenshots/description via the **read-only staging DB** — connect to the shared tunnel at `127.0.0.1:15432` (use `127.0.0.1`, not `localhost`) as `data_ro` (SELECT-only by grant; already open for the wave — do NOT open your own).
- **PostHog** — if the report is PostHog-sourced (session link / event), pull the session + surrounding events.
- **Reproduce** — attempt a repro; note steps + frequency.
- **Related tickets** — search existing issues (`list_issues` query) for duplicates / the same root cause; list FIN-keys. **When the reporter is a repeat filer in this channel, run this first** — check their own recent drops before investigating, so you don't re-derive facts they already wrote down.

**Directions** (the project's own steer — verbatim from the channel's / project's `## Directions`; `¶INV_DIRECTIONS_IN_DESCRIPTIONS`)
- […paste verbatim, or "none set — skill defaults apply"]
- These outrank your own judgment about what's worth chasing here. If they conflict with the recipe below, follow the Directions and say so in the report.

**Ticketing Strategy** (how much ticketing this project wants — verbatim from the **Project description's** `## Ticketing Strategy`; `¶INV_TICKETING_STRATEGY_IN_PROJECT`)
- […paste verbatim, or "none set on the project — engine default applied" + the default's three bullets]
- **A separate block from Directions on purpose.** Directions steer what's worth *chasing*; this steers what's worth becoming *its own ticket*. Your recommendation below is a graduation-volume call, and you cannot read the project — so if it isn't in this block, it doesn't reach you.
- Bound your "ripe to graduate" recommendation by it. When an item is well-formed but reads as a facet of something already tracked, say **fold into &lt;parent&gt;** rather than recommending a new ticket. "Not its own ticket" never means discard.

**Known context** (what the orchestrator already knows — don't re-derive)
- **Initiative / domain goal**: […]
- **Related tickets / clusters**: […]
- **Prior triage on this item** (if any): [pointer to earlier `✅ result` replies / builds/ reports]
- **Who to ask** (from the project's `## Stakeholders`, if set): [person → what they can answer]. Facts, not authority — if you hit a question the read-only sources cannot close, name the person to ask in your Boundary instead of guessing or silently degrading. Do not contact them yourself.

**Deliverable**
- A **triage report** written to `builds/inbox-triage-<origin-id>.md`: what was found (account/claim/URL/repro/related), with evidence.
- A **recommendation**: ripe to graduate? → which milestone (`Needs decision` / `Needs research` / `Ready for action` / `Uncategorized`)? or still-needs-X (name it)?
- A **steering read** (`¶INV_STEERING_NOT_SOLUTIONS`) — process-steering, NOT solutions: a legitimacy/confidence read + the still-open questions + concrete *what to measure/triage next* + 3–5 suggested board options (`{key,label}`), all oriented by the Directions above. This feeds the Decision Board's steering widgets (the orchestrator polishes your options). Options to react to, never a manufactured answer — you stay read-only and light.
- A **1-line headline** the orchestrator can post inline (or attach the report if long).

**Constraints**
- **Read-only** — never edit app/claim data, never file tickets, never post to Linear yourself. Return findings; the orchestrator posts + files.
- Cite evidence (record-ids, URLs, query results) so the finding is verifiable, not asserted.
