---
name: ask
description: "Ask a question without stopping: write it to a file instead of calling AskUserQuestion, keep working on everything that does not depend on the answer, and let a manager or the operator answer it — directly in the file, or through a small local web app that renders the decision tree and pushes the answer back to your seat. Re-ping after 10 minutes, pass it up one level after another 10. Triggers: \"ask the manager\", \"ask without blocking\", \"write this question down\", \"/ask\", \"put this to the operator\", \"open the asks app\"."
version: 2.1
tier: lightweight
args: "[serve [dir] | list | the question you need answered]"
---

Ask a question as a file, keep working, and pick the answer up when it lands.

# /ask Protocol (The Question That Does Not Block)

[!!!] A **sessionless utility** skill: no session directory, no phases, no log of its own. The ask file IS the record. It composes nothing and owns one store: `<fleet data dir>/asks/`.

**Why it exists.** `AskUserQuestion` blocks the asking agent, caps a round at four questions, and reaches only the person at that agent's own terminal. The operator ruled it out for seated work: *"it's blocking and limited… make agents produce… questions… pass those files to managers… managers could be answering directly or… present it to the user in browser"*. An ask file blocks nobody, holds any number of nested questions, and can be answered by whoever the chain reaches.

## When to write an ask instead of calling AskUserQuestion

*   **Write an ask** whenever you are a seated agent (you have a `FLEET_PANE`) and the question needs somebody above you: a manager's ruling, a fork beyond your grant, an operator-only decision. This is the default for seats.
*   **Use AskUserQuestion** only when a person is demonstrably at your own terminal and the answer is needed in this turn — an interactive session the operator started and is driving.
*   **A loom lane does not write asks.** A lane escalates to its conductor (`LOOM_AGENT_DIRECTIONS.md`); the conductor writes the ask when the question has to leave the loom.

## Writing one

**Before `engine ask new`, read the author guide: `skills/ask/assets/ASK_AUTHOR_GUIDE.md`** — what makes a fork answerable (its own stake, lean, counter and costed options), the fields the parser reads today, codes, and a worked before/after.

```bash
engine ask new --id <short-id> \
  --why "<what is blocked>" --importance high|medium|low --stakes "<cost of a wrong answer>" \
  --context "<path or one line>" --alternatives "<A; B; C>" --lean "<your pick>" \
  --falsifier "<what would prove the lean wrong>" [--dependsOn <other ask id>] <<'EOF'
Optional prose the answerer should read first.

## ¶ASK_LAYOUT: Choose one: Where do the files live?
- [ ] [ONE] One file per ask
  Moves up the chain by editing one field.
  - [ ] [FLT] Flat under the seat
  - [ ] [DAT] Bucketed by date
- [ ] [SEA] One file per seat

## ¶ASK_NAMING: Choose: Which id parts?
DependsOn: ASK_LAYOUT=ONE
- [ ] [TS] Timestamp
- [ ] [SLG] Slug
EOF
```

It prints the file path: `<fleet data dir>/asks/<your seat>/<id>.md`, and on the next line the ask's app URL, where the fleet data dir is `~/.claude/data/yarik/` (`engine ask path` prints the root). `--from` is your **live** seat (the pane's `window:@pane_label`, read from tmux; `$FLEET_PANE` only when tmux cannot be read) and may only repeat it; `--to` defaults to your live `@pane_parent` (`$FLEET_PARENT` only as the fallback), and a seat with no parent asks `operator`.

**Tell the operator about an ask by the URL `engine ask new` printed (`http://127.0.0.1:<port>/a/<seat>/<id>`), written as a clickable link. Copy the printed line; do not type the URL.** For an ask already filed, `engine ask url <seat>/<id>` prints it, and `engine ask list --url` adds it as a column. A bare id or a file path is not enough, because the operator cannot open either from where they read your message. This holds wherever an ask is reported, rowed or relayed to the operator; other skills cite this paragraph rather than restate it.

### The format

*   **Header** — a `---` block of one-line `key: value` fields: `id`, `to`, `from`, `why`, `importance`, `stakes`, `context`, `alternatives`, `lean`, `falsifier`, `status` (`open` | `answered` | `declined` | `superseded` | `withdrawn` | `ruled`), `revision`, `dependsOn`, `created`. Answering adds `delivery`, `deliveryNote` and, while a push is in flight, `deliveryWriter`; the life of the answer adds `readAt`/`readBy` (the asker's read), `reads` (every recipient's own read) and `acted`/`actedAt`/`actedBy`; a saved draft adds `draft`; a move up the chain adds `forwards`; a revise adds `revisions`; an ask ruled outside the file adds `ruledInChat`; a supersede adds `superseded-by`, `superseded-at` and `superseded-actor` to the old ask and `supersedes` to the new one. These are the store's fields: `engine ask new` refuses them, and refuses a body that holds a ```json answer``` or ```json draft``` block. **Fill `lean` and `falsifier`**: an ask with a lean is answered with a yes; one without is answered with a meeting.
*   **Card fields (v2, all optional — a v1 file reads exactly as before)**. Each one is a section on the question's card, shown only when filled, and each means what `§FMT_DECISION_CARD` means by it: `stake` (At stake), `unblocks` (Deciding this unblocks), `related` (Related, not asked here — collapsed), `lean` (start it with an option code, `B — because …`, and that option gets the **LEAN** badge), `counter` (Strongest counter), `evidence` (pieces separated by ` ; ` — the count chip), `rank` (`6 of 7`), `topic` (the card's short slug), `tickets` (`IDE-253, IDE-234`), `confidence` (high/med/low, with a reason), `reversible` (one-way door or not), `verify` (the cheap check that confirms or sizes the lean), `falsifier`, `ifUnanswered` (what you do by default, and from when), `neededBy`, `askedBy` (seat · thread · log), `blocks`, `reserved-for` (`operator`: only the operator may answer, directly or by relay; the holder may still forward), `provenance`, `sourceRef`. Every field is also a flag on `engine ask new` (`--stake …`). The header's card fields fill the **first** question's card; a later question carries its own as lines under its heading (below).
*   **Body** — the engine's decision-tree syntax, the same grammar `§CMD_DECISION_TREE` uses: a heading `## [¶ASK_NAME:] Choose one: …` (single) or `## [¶ASK_NAME:] Choose: …` (multi), options `- [ ] [CODE] Label` with codes of **at most 12 characters: a capital, then capitals or digits** (`A`, `L2`, `RESCOPE`, `KEEPBROAD`) — `new` and `revise` refuse anything else in the code brackets (`[THIRTEENCHARS]`, `[wt]`), naming it, and never fold it into the label (the codes are local to the file, so the Standard Label Vocabulary that binds engine trees does not apply), an indented plain line as the option's description, deeper indent for nested options. Nesting is unlimited and there is no cap on the number of questions.
*   **Question kinds** — the heading word picks the kind. `Choose one` and `Choose` as above; `Rank` (answer: every top-level code once, in order); `Text` (a non-blank string); `Number` (a number; optional `Range: 1..30` and `Unit: days` lines under the heading); `Date` (`YYYY-MM-DD`, a real date); `Yes or no` (options `YES`/`NO` are supplied when you write none; write them yourself to nest follow-ups under one). Option codes are 1–12 capitals or digits, starting with a capital (`A`, `L2`, `KEEPBROAD`).
*   **Prose under a heading** — lines under a `## ¶ASK_X` heading that are neither card lines nor options are kept: the reasons before the options are shown at the top of the fork's card, and an unindented note after the options is shown **between that card and the next**. A fenced block (```` ``` ````) inside a fork is part of its prose and never ends the fork. **The options are the last list in the fork**: a `- [ ]` line in the reasons above it (a checklist, an example) is prose, never an answerable option; an earlier list joins the options only when nothing but blank lines separates them and it agrees with them on having codes. Indented lines under an option stay that option's description. `- [X] Label` is option code `X`; a checked box is `[x]`, or `[X]` followed by a `[CODE]`.
*   **Per-question card lines** — under a heading, before its options, one per line: `Stake:`, `Unblocks:`, `Related:`, `Lean:`, `Counter:`, `Rank:`, `Topic:`, `Confidence:`, `Reversible:`, `Verify:`, `Falsifier:`, `IfUnanswered:`, `NeededBy:`, `Blocks:`, `Context:`, repeatable `Evidence:` lines, and repeatable `Panel: <lens> → <CODE> — <one-line why>` lines (an optional council read: the card shows each lens beside the option it picks, and the full read in a collapsed section), then one `Council: <path-or-url>` line naming the report the reads came from. **Per-option lines**, indented under the option: `Cost:`, `Effort:`, `Blast:`; further indented prose continues the description.
*   **Dependencies** — inside the body, a `DependsOn: ASK_OTHER` or `DependsOn: ASK_OTHER=CODE` line under a heading hides that question until the other one is answered (with that code). `new` and `revise` refuse a `DependsOn` that names a question the ask lacks, a code that breaks the code rule, or a code that question has no option for (it would hide the dependent for good). In the header, `dependsOn: <ask id>` hides the whole ask until that ask is answered; if that ask is **declined**, the dependent is shown, marked "depends on <id>, which was declined", rather than hidden forever.
*   **Ticket keys** — every key in the `tickets:` header and anywhere in the body (`IDE-253`) renders as a link with its status; hovering shows title, status and since-when, assignee and a one-line summary. The **local server** fetches these from Linear with the key in the env file named by `ASK_LINEAR_ENV`; `engine ask serve` defaults it to the working project's `.env.local`, then `.env` (resolved as `scripts/env-lib.sh` resolves every credential), and starts the server with any exported `LINEAR_API_KEY` removed from its environment. The key never reaches the browser, the page, argv or an ask file.
*   **The answer** — written into the same file as one fenced block, `status` flips to `answered` and `revision` goes up by one:

    ````
    ```json answer
    {"answers": {"LAYOUT": ["ONE", "FLT"], "NAMING": ["TS"]}, "note": "…", "answeredBy": "manager:idealic", "answeredAt": "…"}
    ```
    ````

    Answers are keyed by the ask name, or `q<index>` for a heading without one. Each value is a non-empty list of the chosen codes (labels for codeless options); free text goes under `<key>.other`, never into the codes list. The block also records the `revision` it created.
*   **A refusal is a record, not a blank** (INV_REFUSAL_IS_NOT_EMPTY). An empty answer (`{}`), a `null`, an unknown key or an unknown code is refused by both the app and `engine ask answer`. To refuse an ask, **decline** it: `status: declined` and a ```json answer``` block carrying `"declined": true` and a non-empty `reason`.
*   **One answer wins** (INV_ONE_CHOSEN_DESTINATION). Every answer names the `revision` it read; if the ask moved since, the answer is refused (HTTP 409, or a `stale revision` error from the CLI) and nothing is written or pushed. Read the answer that won before answering again.

### Worked examples

**A decision-board card** — one question with everything a card can carry (this is the shape of the /decide Q6 card):

```bash
engine ask new --id who-funds --rank "6 of 7" --topic "who funds a world's seat contracts" \
  --stake "For a world's seats, nothing can be the funder yet." \
  --unblocks "E14 (contracts as a mountable resource)" \
  --related "The re-seed ruling (E1) lands before E14 either way." \
  --lean "B — because a re-seed then never touches contracts" \
  --counter "B is a root again; v3 dropped v2's per-world root because two roots' room could add up" \
  --evidence "v3 §Contracts line 478 ; v3 open question 6" --tickets "IDE-253" \
  --confidence "med — v3 is silent on B's room" --reversible "no — contracts outlive the ruling" \
  --falsifier "one contract granted room by both roots" --ifUnanswered "E14 stays parked" \
  --neededBy "before E14 is boarded" --askedBy "manager:app · AGENTS-MOUNT" <<'EOF'
A world's spend root is "never transferable" (roles.ts:455), so nothing can fund its seats' contracts.

## ¶ASK_FUND: Choose one: What does a world's document fund its seat contracts out of?
Verify: read roles.ts:306-316 and :455 side by side
Panel: Security → B — placed at set-up, so no signer can mint it
Panel: Economist → A — one root keeps the room in one place
- [ ] [A] Make the world's spend root transferable
  Contracts derive from the world's own root.
  Cost: changes what a holder can pass on
  Effort: M
  Blast: every world with seats
- [ ] [B] A separate transferable root at the world's budgets
  Cost: it is a root again
  Effort: S
EOF
```

**Every other kind**, with a conditional yes/no, deep nesting and a cross-question dependency:

```markdown
## ¶ASK_ORDER: Rank: Which seats move to /ask first?
- [ ] [MGR] Managers
- [ ] [LAN] Loom lanes
- [ ] [OPS] The operator's terminal

## ¶ASK_NAME: Text: What should the batch message be called?

## ¶ASK_DAYS: Number: How many days before a draft is flagged stale?
Range: 1..30
Unit: days

## ¶ASK_WHEN: Date: When does v2 replace v1?

## ¶ASK_PUSH: Yes or no: Push answers to every forwarder?
- [ ] [YES] Yes
  - [ ] [ALL] Every forwarder
  - [ ] [LST] Only the last holder
    - [ ] [CC] And copy the asker
- [ ] [NO] No

## ¶ASK_WHYNOT: Text: Why not?
DependsOn: ASK_PUSH=NO
```

Answered, that is `{"ORDER":["MGR","OPS","LAN"],"NAME":"the ask digest","DAYS":7,"WHEN":"2026-11-02","PUSH":["NO"],"WHYNOT":"one push per seat is enough"}`. `ASK_WHYNOT` is hidden until `PUSH` is `NO` (a conditional yes/no); `CC` sits three levels deep; a whole ask can wait on another with the header's `dependsOn:`.

## While you wait — the operator's ruling on timing

**Push is fine; timers aren't** (the operator's ruling, 2026-10-28, on the IDE-182 question and under IDE-135's no-scheduler rule). The push is triggered by an event — somebody answering — so it is not a scheduler, and it ships. The re-ping and pass-up below are **steps you take yourself** when you next look at the clock; nothing in `/ask` runs a timer, polls, or re-pings on your behalf, and nothing should be added that does.

**Keep working on whatever does not depend on the answer.** That is the point of the file. Then, per the operator: *"we ping manager again in 10 min, and then go up one level if it doesnt respond in 10."*

1.  **At 10 minutes unanswered**, re-ping the recipient: one `SendMessage` (or a line in your log the manager's sweep reads) naming the file path. Do not rewrite the ask.
2.  **At 20 minutes unanswered**, ask the holder to pass it up. **Only the current holder (the `to:` seat) may move an ask**, and it does so with `engine ask forward <seat>/<id> --to <its own FLEET_PARENT>`: that rewrites `to:`, appends the hop to `forwards:`, moves the revision, and the answer is later pushed to the asker **and every seat that forwarded it**. **When the holder is silent, the holder's own parent may move it** (a seat whose `FLEET_MANAGES` lists the holder); the hop is recorded through the parent, so the parent hears the answer too. **The asker may re-ping, never forward.** The file stays in your seat's directory. Never edit `to:` by hand; an asker that moves its own ask makes two owners of one question.
3.  **To change the question**, the asker revises it: `engine ask revise <seat>/<id> [card flags as for new]` with the new body on stdin (or `--keep-body` to change only card fields). Only the asker (`from:`) may; the ask must be open. The id, `from:`, `to:`, the forward chain and `created:` stay; the revision moves and `revisions:` records what changed. A draft or an answer made against the old revision is refused as stale. The holder and every forwarder get one `[ask-revised]` notice; the asker gets none. To replace an ask outright, see *Replacing an ask* below — never re-file it.

## Replacing an ask: revise it, never re-file it

**To change an open ask, revise it** (step 3 above): same id, same file, one place to answer. **If it really must become a new ask** (a different addressee, or a split), file the new one and then retire the old one in the same breath: `engine ask supersede <seat>/<old-id> --by <seat>/<new-id>`. **Never re-file** — a copy left beside its open original gets two answers, and the one acted on last wins (IDE-261's ticket flip-flopped that way).

*   **Who** — the old ask's asker (`from:`), a manager of that asker (its `FLEET_MANAGES` lists it — **by choice the same rule `forward` and relay use**, so a label entry such as `kernel` matches any `<window>:kernel` seat; it is an honour rule like the rest of R4), or the operator (`--by operator` from a bare terminal, as for every verb; the actor `--by` has no `/`, the replacement's does, so both may be given). A `reserved-for: operator` ask may be superseded: it settles nothing.
*   **What it writes** — the old ask: `status: superseded`, `superseded-by: <seat>/<new-id>`, `superseded-at`, `superseded-actor`, its revision moves and `revisions:` records `N@<time>:superseded`; any draft on it is dropped. The new ask: `supersedes: <seat>/<old-id>` (its revision does not move). The old ask's holder and forwarders get one `[ask-superseded]` notice, and so does its asker whenever someone else superseded it.
*   **Refused** — either ask missing; an ask superseding itself; an old ask already answered, declined or ruled (answered asks are history: file a new ask instead); an old ask already superseded (the error names its replacement); a replacement that is itself superseded, declined or ruled, or that a seat (not the operator) answered — a replacement answered by the operator is allowed (the IDE-261 clean-up). The CLI takes exactly one old ask, written before `--by <new>`; anything else is refused with the form to use.
*   **After** — an answer, decline, draft or send on the old ask is refused naming the new one (the app gets HTTP 409 with `supersededBy`). `engine ask list` no longer shows it; `--status superseded` does.

## Taking a question back: withdraw it

**To take back an open ask that no longer needs answering, withdraw it**: `engine ask withdraw <seat>/<id> --reason "<why it is no longer asked>"`. Withdraw is not supersede: no newer ask replaces it, so nothing is left to answer anywhere. **Never file an ask asking anyone to confirm a withdrawal**, and never answer or acknowledge a withdrawal notice: the withdrawal is the record, and a "confirm withdrawal" ask only puts a dead question back in the operator's queue.

*   **Who** — supersede's set: the asker (`from:`), a manager of that asker (its `FLEET_MANAGES` lists it), or the operator (`--by operator` from a bare terminal). Pending an operator ruling on who may withdraw.
*   **What it writes** — `status: withdrawn`, `withdrawn-at`, `withdrawn-actor`, `withdrawn-reason` (one line); the revision moves and `revisions:` records `N@<time>:withdrawn`. A saved draft on it is discarded and `withdrawn-draft-of: <seat>` records whose it was. The holder and forwarders get one `[ask-withdrawn]` notice that says no action is needed, and so does the asker whenever someone else withdrew it; the operator is never pushed.
*   **Refused** — a missing ask; no `--reason`, or a blank one; an ask already answered, declined or ruled (that one is history: file a new ask if its answer no longer holds); an ask already superseded (the error names its replacement) or already withdrawn.
*   **After** — an answer, decline, draft or send on it is refused (the app gets HTTP 409 with `status: "withdrawn"`, `withdrawnBy`, `withdrawnAt`, `withdrawnReason`). It leaves the Open list and is under All only; `engine ask list --status withdrawn` reaches it, and `list` and `read` print who withdrew it and why. `rename-seat` rewrites `withdrawn-actor` and `withdrawn-draft-of`.

## Answering

*   **Who answers** — **only the addressed seat (`to:`), a seat in its forward chain, or the operator** (the operator's ruling). Never the asker of its own ask, never a bystander. An ask is filed by the live seat (`new --from` may only repeat it, never name another seat or `operator`) and is addressed to somebody else: `to:` equal to `from:` is refused, and so is forwarding an ask back to its asker. `reserved-for: operator` narrows that to the operator.
*   **Declining a reserved ask passes it up** (the operator's ruling, 2026-10-30) — on an ask marked `reserved-for: operator`, `engine ask answer … --decline "<reason>"` by anyone but the operator does not close it: it is forwarded one rung, to the decliner's own parent (its live `@pane_parent`, the default `--to`; `operator` when it has none), by `forward`'s standing rule (the holder, or the holder's parent). **When that parent is the ask's own asker**, who cannot answer an operator-reserved ask either, it climbs past it to the asker's live parent, and on up, ending at `operator` (also when a parent cannot be read, e.g. outside tmux). The ask stays `open`, the revision moves, the hop in `forwards:` carries the reason as `a→b@<time> [declined: <reason>]` (a reason is kept on one line, and its `%`, `@`, `;` and `]` are percent-escaped in the file so the hop still parses — in older readers too; `forwardChain` reads it back whole, and each hop splits at its timestamp), and the next holder gets one `[ask-passed-up]` push with the reason; an operator's saved draft on it is dropped. A seat's **`draft --decline`** of a reserved ask is refused ("use `engine ask answer --decline` to pass it up"): a pass-up moves the ask at once and is never held as a draft. The CLI prints `passed up, not declined  <seat>/<id> → <to>`. The operator's own decline, and any decline of an unreserved ask, close it as before.
*   **Who you are** — your seat is read **live** from tmux (`#{window_name}:#{@pane_label}`, and `#{@pane_parent}` for the default `--to`), the rule hop.sh uses; `FLEET_PANE`/`FLEET_PARENT` are run.sh's launch-time cache, used only when tmux cannot be read, and a stale one is warned about. A seat (FLEET_PANE set) acts as itself on `answer`, `draft`, `send`, `discard`, `forward`, `revise`, `supersede` and `acted`: a `--by` naming anyone else is refused, and no seat may claim `operator` (nor may `FLEET_PANE=operator`). A shell with no `FLEET_PANE` is not a seat, so it must name itself with `--by` — the operator at a bare terminal passes `--by operator`. The app stamps `answeredBy: operator, answeredVia: browser`; the CLI stamps `answeredVia: cli`.
*   **These rules guard against honest mistakes, not against a hostile process.** Everything here runs as one user on one machine: any local process that can fetch the app's page can read its token and write as the browser, and any process can set `FLEET_PANE` or edit a file. `answeredVia` records how an identity was claimed, not proof of it.
*   **A relayed operator answer** — when the operator answers in a seat's terminal, that seat records it: `engine ask answer <seat>/<id> --revision N --json … --relayed-from operator --note "<when and where the operator said it>"`. It is stamped `answeredBy: operator, answeredVia: relay:<your seat>` and is allowed on a reserved ask. **Only a seat with standing relays**: the addressee, a seat in the forward chain, or a manager of the asker (its `FLEET_MANAGES` lists the asker). **The asker never relays to its own ask**, and a bystander never relays; the store refuses both, not only the CLI. The card shows **relayed by <seat>** and `engine ask read` prints `by operator, relayed by <seat>`, so the operator can spot a relay it never gave. `FLEET_MANAGES` names the managed panes by **label** (`ideas,writer`) or by seat; a label names any seat `<window>:<label>`. The operator may replace or discard any seat's draft from the app (a seat never replaces another author's), and the card never pre-fills a seat's draft as the operator's choice. A relay is an **honour record**, exactly like the rest of R4: nothing checks that the operator said it.
*   **Drafts and the batch** — the app's default: **Save draft** writes the answer into the file as a ```json draft``` block (the ask stays `open`, its revision does not move), and **Send batch** settles the operator's drafts and pushes **one message per seat**, listing `title → answer · seat/id#KEY` per question. A draft belongs to whoever saved it: only its author replaces, discards or sends it, and the store honours a draft only as the file's last block with the `draft:` header it stamps beside it. The batch request carries refs only; every line is read back from the file it just wrote, so a message can never carry an answer the file does not hold. A draft whose ask moved since it was saved (forwarded, revised or answered) is refused with `stale revision: …: the ask moved…`, and one whose question text was edited with `stale draft, the question was edited…`; the rest still go. CLI: `engine ask draft <seat>/<id> --revision N --json …` · `engine ask send [refs…]` (with no refs, **your own drafts only**) · `engine ask discard <seat>/<id>`.
*   **From the CLI** — `engine ask answer <seat>/<id> --revision <N> --json '{"LAYOUT":["ONE"]}' [--note "…"]`, or decline with `--decline "<reason>"`. `<N>` is the revision you read; `engine ask list` prints it as `rev=`.
*   **A grant class** (IDE-339) — the asker's manager records what its answer grants with `engine ask answer <seat>/<id> --revision <N> --json … --grant <A|B|C|D>`, stamped `"grantClass"` in the answer record, and printed on the push's first line (`· grant B`), as a `grant class B, given by <seat>` answer line, and beside `by …` in `engine ask read`. It is refused unless the answerer's `FLEET_MANAGES` lists the asker (its seat or its label), so a peer addressee cannot write one; refused too when the answerer is the operator (a relay included), on a `reserved-for` ask (the pass-up included), and on `engine ask draft`. A manager's decline keeps its grant class; the app's `/api/answer` and `/api/draft` refuse any `grantClass` from the browser. `hop.sh may-rule` writes none.
*   **An overrule and the answer history** (IDE-339) — every settle keeps the answers it replaced, whole and oldest first, in one ```json history``` block before the ```json answer``` block (`/api/asks` returns it as `history`). When the new answer is by a different answerer than the one it replaces (the operator over a seat's settled answer), the file is stamped `overruled: <prior answerer>` and the push leads `[ask-overruled] from <answerer> via ask-app: <seat>/<id> …`, keeping the `Replaced:` line; it goes to the overruled seat as well as the asker and its forwarders (never to the operator, which is not a seat). A later change by the same answerer keeps the stamp, so the header still shows the overrule, and its push stays `[ask-answer-changed]`; only a different answerer moves the stamp. A prior answer that names no answerer stamps nothing. A history block that cannot be read whole (not JSON, not a list, an entry that is not a record) leaves the ask listed, with `historyError` set, and any answer to it is refused, naming the file, until it is fixed by hand.
*   **A follow-up from the operator** (ASKFOLLOWUP) — from a question in the app, the operator can send the asker a follow-up instead of an answer: a question back (`kind: question`) or "do this first" (`kind: first`). `POST /api/followup {seat, id, expectedRevision, kind, fork?, text, picks?}` writes it as a `## Follow-up <n>` entry holding one ```json followup``` record (`n`, `at`, `by` — stamped by the server, as an answer is — `kind`, `fork`, `text`, the unsent `picks`, and the push's `delivery`). The ask stays `open`, its answer is untouched, its revision moves (409 when stale, or when the ask is no longer open — a superseded ask's 409 carries `supersededBy` and a withdrawn one's `withdrawnBy`/`withdrawnAt`/`withdrawnReason`, as `/api/answer`'s do; 400 on empty text, an unknown kind or fork). A draft saved at the revision the follow-up moves from is re-based onto the new one, so the operator's own follow-up does not stale the operator's draft; a draft already stale stays stale, and neither the question parse nor the body digest sees the entry; `new` and `revise` refuse a body that carries one. The asker gets one push: `[ask-followup] from operator on <seat>/<id> (fork <F>: "<question>"): <text>`, then the kind, the title, the unsent picks, the file and how to reply; a failed push leaves the entry `delivery: undelivered`. `engine ask read` prints every follow-up. **Reply by revising**: `engine ask revise <seat>/<id> [--keep-body] --answers-followup <n>[,<n>]` — a revision that only answers follow-ups is allowed — stamps each one `addressedIn`/`addressedBy`/`addressedAt`, which the app shows as addressed; naming a follow-up already addressed is refused, so the first stamp stands. The push names the reply: `--keep-body` for a question, `--body-file` (or `--keep-body`) for a "first". `/api/asks` returns follow-ups in `history` as `{type: "followup", …}` beside the replaced answers, oldest first; `rename-seat` rewrites their `by` and `addressedBy`. **The operator may also draft over a seat's settled answer** (the overrule form), and sending that draft is an overrule; a seat never drafts over any settled answer, and a relay draft (`--relayed-from operator`) counts as the seat's: over a settled answer it is taken only as a change to the operator's own answer (IDE-304).
*   **An answer's note** — `engine ask read`, the single-answer push and each item of a batch push print an answer's `note` on its own line, marked `⚠ note from <answerer>: "<text>"` and never folded into the choice line, so a note that questions the premise is seen.
*   **In the browser** — `engine ask serve [dir]` starts the app on `127.0.0.1` (default port 4977) and prints its URL; run it again and it reuses the running instance (pidfile `<dir>/.ask-app.pid`). `--stop` stops it. **After an ask-app change lands, restart the server**: `engine ask serve --stop`, then `engine ask serve`. `serve` reuses a running server and the build-id check covers only the client, so a server started before IDE-339 landed keeps settling with the old `format.ts`: it leaves the history block where it is and never adds the answer it replaced (that record is lost for good on the next new settle), leaves a stale or missing `overruled:` stamp, and computes a different `bodyDigest`, so a draft saved by one version is refused as stale by the other. It lists open asks live as files change, shows the header context, renders nested trees and holds back what depends on an unanswered question, and writes the answer or a decline into the file. It accepts writes only from its own page: the Host must be the loopback origin, and a write must be JSON from that origin carrying the per-serve token the server puts in the page. So another web page the operator has open cannot answer as the operator. A stale pidfile is never trusted: `serve` and `--stop` act only on a process whose command line and health check both prove it is this root's ask-app. Servers are found by their **root**, not by the pidfile's port, so a lost pidfile never yields a second server, and `--stop` stops every proven one. A serve lock left by a killed `serve` is recovered after 30 seconds. **The client is identified by its build id** — a hash of `src/client/**`, `format.ts` and every stylesheet `main.tsx` imports, written into the build as `.build-id`. `serve` rebuilds only when that id differs from the sources' (never by file times), builds into a temp directory and moves it into place under a lock on the client directory, and the server refuses — with a 503 that says why — to serve a client whose id is missing or not its own sources'. `ASK_APP_DIST` names the client directory (default `tools/ask-app/dist`); **any serve that is not the live one sets it to a scratch path.**
*   `engine ask list [--status open|answered|declined|settled|all|a,b] [--to <seat>] [--seat <seat>] [--url]` lists asks across every seat; `settled` is answered + declined; `--json` for a reader (each row carries `url`); `--url` adds the ask's app URL as the last column.
*   `engine ask url <seat>/<id>` prints one ask's app URL, the link the operator is given (§ Writing one). It warns on stderr when nothing answers on the port yet (`engine ask serve` starts it). The state column shows `draft`, then `queued` → `read` → `acted` — never `delivered` as if it were read.

## How the answer reaches you

**The file is written first, then the answer is pushed to the asker and to every seat that forwarded the ask** over Claude Code's cross-session socket, addressed by seat name: the app finds the live session whose registry entry (`~/.claude/sessions/<pid>.json`) carries that name, and writes one user message to its socket. **The message carries the answer's lines** — `title → answer · seat/id#KEY` per question, read back from the file just written, the same lines a batch carries (a batch sends one message per seat for all its asks) — and names the file, which stays the record. The seat that answered, or that relayed the operator's answer, is never pushed its own answer; its delivery is stamped delivered. The socket stamps no sender, so the message's first line does: `[ask-answer] from <answerer> via ask-app: <seat>/<id> is answered` (a batch: `[ask-batch] …`). **`delivery: delivered` means queued at the seat, not read.** A seat that is mid-turn holds the message in its input queue and takes it in only when the turn ends. Measured on the build probe: queued at 14:25:08Z, taken in at 14:36:19Z, **11 minutes to pickup** on a busy conductor. When two live sessions answer to the seat name (including case-only differences such as `docs` and `Docs`), the push is refused as ambiguous and the reason is written into `deliveryNote`; the answer stays in the file. The protocol is undocumented, so this lives behind one adapter (`tools/ask-app/src/lib/deliver.ts`) and is best effort.

**The fallback is the file.** When the push fails, no live session holds the seat, or the seat is ambiguous, the file stays answered and says `delivery: undelivered` with the reason in `deliveryNote`. A `delivery: pending` carries its writer (`deliveryWriter: <pid>@<time>`); one whose writer's pid is **dead** — a crash between writing and pushing — is pushed again by the next `engine ask send` or `engine ask read` (and the app's Send batch), claimed and re-checked under the file's lock so two processes never push it twice. A slow writer that is still alive is never pushed over, however old its stamp. A pending with no writer (written by v1) is pushed again only for a caller the answer is for, once a minute has passed since the answer.

**Read means a read stamp, never `delivery`.** `delivery: delivered` is a queued push. Reads are kept **per recipient**: `readAt`/`readBy` is the **asker's** read (what the app's life strip shows), and `reads: seat@time ; …` holds every recipient's own read, so a forwarder's read never stands for the asker's. They are stamped by **reading through the CLI**, never by opening the file:

*   **`engine ask read <seat>/<id>`** prints the collapsed list (`title → answer · id` per question; `--full` adds the answer block) and stamps the **reader's own** read the first time a **recipient** of the answer reads it — the asker, or a seat that forwarded it. Anyone else's read prints but stamps nothing, so the operator re-reading its own answer is never shown as the asker having seen it. A new answer clears every read and `acted`.
*   **The seat's `/next` pickup**: `engine ask read --unread [--seat <seat>]` (the seat defaults to `FLEET_PANE`) prints every settled ask — **answered and declined** — that the seat asked **or forwarded** and has not itself read, and stamps the **caller's** read. Run for another seat, it prints that seat's unread answers and stamps the caller's read only if the caller is a recipient — never the other seat's. To look without folding: `engine ask list --status all --seat <seat> --json`, select the asks whose `answer` is set and that **this seat** has not read — for the asker, `header.readAt` absent; for a forwarder, no `<seat>@…` entry in `header.reads` — then fold each with `engine ask read`. Do **not** select by `delivery` (a queued push is not a read) and do not use `--status answered` alone (it drops declines).
*   **`engine ask acted <seat>/<id> "<one-line summary>"`** stamps `acted` once the answer has been used — by a recipient only (the asker, a forwarder or the addressed seat); acting implies the actor's own read. The app shows **queued → read → acted** live. An ask the operator ruled in chat is closed honestly one of two ways: record the answer as a relay (above), then `acted`; or, when there is no answer to record, `engine ask acted <seat>/<id> "<summary>" --ruled-in-chat "<who, when>"`, which closes it as `status: ruled` with `ruledInChat:` and invents no answer. On a `reserved-for: operator` ask that close is itself a relay of the operator's ruling: it needs `--relayed-from operator --note "<when and where>"` from a seat with standing to relay — the asker alone can never close it.

## Constraints

*   **Never answer your own ask.** An ask is a question to somebody else; answering it yourself is deciding without the record saying so.
*   **One question per decision, many decisions per file.** Put related forks in one file with `DependsOn` between them rather than a chain of files the answerer has to reassemble.
*   **Every fence carries a language.** A fenced block in an ask body opens with its language, `text` when nothing fits; `new` and `revise` refuse (exit 2) an untagged one, naming its line. See the author guide's "What the parser reads today".
*   **The answer is the file's.** A reply sent only as a message, with nothing written to the file, is lost the moment the asker's context ends.
