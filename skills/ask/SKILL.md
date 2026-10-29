---
name: ask
description: "Ask a question without stopping: write it to a file instead of calling AskUserQuestion, keep working on everything that does not depend on the answer, and let a manager or the operator answer it — directly in the file, or through a small local web app that renders the decision tree and pushes the answer back to your seat. Re-ping after 10 minutes, pass it up one level after another 10. Triggers: \"ask the manager\", \"ask without blocking\", \"write this question down\", \"/ask\", \"put this to the operator\", \"open the asks app\"."
version: 1.0
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

It prints the file path: `<fleet data dir>/asks/<your seat>/<id>.md`, where the fleet data dir is `~/.claude/data/yarik/` (`engine ask path` prints the root). `--from` defaults to `$FLEET_PANE`, `--to` to `$FLEET_PARENT`, and a seat with no parent asks `operator`.

### The format

*   **Header** — a `---` block of one-line `key: value` fields: `id`, `to`, `from`, `why`, `importance`, `stakes`, `context`, `alternatives`, `lean`, `falsifier`, `status` (`open` | `answered` | `declined` | `superseded`), `revision`, `dependsOn`, `created`. Answering adds `delivery` and `deliveryNote`. **Fill `lean` and `falsifier`**: an ask with a lean is answered with a yes; one without is answered with a meeting.
*   **Body** — the engine's decision-tree syntax, the same grammar `§CMD_DECISION_TREE` uses: a heading `## [¶ASK_NAME:] Choose one: …` (single) or `## [¶ASK_NAME:] Choose: …` (multi), options `- [ ] [CODE] Label` with codes of 2–4 capitals (the codes are local to the file, so the Standard Label Vocabulary that binds engine trees does not apply), an indented plain line as the option's description, deeper indent for nested options. Nesting is unlimited and there is no cap on the number of questions.
*   **Dependencies** — inside the body, a `DependsOn: ASK_OTHER` or `DependsOn: ASK_OTHER=CODE` line under a heading hides that question until the other one is answered (with that code). In the header, `dependsOn: <ask id>` hides the whole ask until that ask is answered.
*   **The answer** — written into the same file as one fenced block, `status` flips to `answered` and `revision` goes up by one:

    ````
    ```json answer
    {"answers": {"LAYOUT": ["ONE", "FLT"], "NAMING": ["TS"]}, "note": "…", "answeredBy": "manager:idealic", "answeredAt": "…"}
    ```
    ````

    Answers are keyed by the ask name, or `q<index>` for a heading without one. Each value is a non-empty list of the chosen codes (labels for codeless options); free text goes under `<key>.other`, never into the codes list. The block also records the `revision` it created.
*   **A refusal is a record, not a blank** (INV_REFUSAL_IS_NOT_EMPTY). An empty answer (`{}`), a `null`, an unknown key or an unknown code is refused by both the app and `engine ask answer`. To refuse an ask, **decline** it: `status: declined` and a ```json answer``` block carrying `"declined": true` and a non-empty `reason`.
*   **One answer wins** (INV_ONE_CHOSEN_DESTINATION). Every answer names the `revision` it read; if the ask moved since, the answer is refused (HTTP 409, or a `stale revision` error from the CLI) and nothing is written or pushed. Read the answer that won before answering again.

## While you wait — the operator's ruling on timing

**Push is fine; timers aren't** (the operator's ruling, 2026-10-28, on the IDE-182 question and under IDE-135's no-scheduler rule). The push is triggered by an event — somebody answering — so it is not a scheduler, and it ships. The re-ping and pass-up below are **steps you take yourself** when you next look at the clock; nothing in `/ask` runs a timer, polls, or re-pings on your behalf, and nothing should be added that does.

**Keep working on whatever does not depend on the answer.** That is the point of the file. Then, per the operator: *"we ping manager again in 10 min, and then go up one level if it doesnt respond in 10."*

1.  **At 10 minutes unanswered**, re-ping the recipient: one `SendMessage` (or a line in your log the manager's sweep reads) naming the file path. Do not rewrite the ask.
2.  **At 20 minutes unanswered**, pass it up one level: set `to:` to your recipient's own `FLEET_PARENT` (the operator when there is none) and ping that seat. **Moving an ask changes only its `to:` field** — the file stays in your seat's directory: `sed -i '' 's/^to: .*/to: <next seat>/' <file>`.
3.  **To change the question**, do not edit it under an answerer's feet: write a new ask and set the old one's `status: superseded`. A superseded ask is refused by `engine ask answer`.

## Answering

*   **From the CLI** — any seat may answer: `engine ask answer <seat>/<id> --revision <N> --json '{"LAYOUT":["ONE"]}' [--note "…"] [--by <your seat>]`, or decline with `--decline "<reason>"`. `<N>` is the revision you read; `engine ask list` prints it as `rev=`.
*   **In the browser** — `engine ask serve [dir]` starts the app on `127.0.0.1` (default port 4977) and prints its URL; run it again and it reuses the running instance (pidfile `<dir>/.ask-app.pid`). `--stop` stops it. It lists open asks live as files change, shows the header context, renders nested trees and holds back what depends on an unanswered question, and writes the answer or a decline into the file. It accepts writes only from its own page: the Host must be the loopback origin, and a write must be JSON from that origin carrying the per-serve token the server puts in the page. So another web page the operator has open cannot answer as the operator. A stale pidfile is never trusted: `serve` and `--stop` act only on a process whose command line and health check both prove it is this root's ask-app.
*   `engine ask list [--status open|answered|all] [--to <seat>]` lists asks across every seat; `--json` for a reader.

## How the answer reaches you

**The file is written first, then the answer is pushed to the asking seat** over Claude Code's cross-session socket, addressed by seat name: the app finds the live session whose registry entry (`~/.claude/sessions/<pid>.json`) is named `from:`, and writes one user message to its socket. **The message is a pointer, not a copy**: it names the ask, the revision and the file, and the file is the only record of the answer. The socket stamps no sender, so the message's first line does: `[ask-answer] from <answerer> via ask-app: <seat>/<id> is answered`. **`delivery: delivered` means queued at the seat, not read.** A seat that is mid-turn holds the message in its input queue and takes it in only when the turn ends. Measured on the build probe: queued at 14:25:08Z, taken in at 14:36:19Z, **11 minutes to pickup** on a busy conductor. When two live sessions answer to the seat name (including case-only differences such as `docs` and `Docs`), the push is refused as ambiguous and the reason is written into `deliveryNote`; the answer stays in the file. The protocol is undocumented, so this lives behind one adapter (`tools/ask-app/src/lib/deliver.ts`) and is best effort.

**The fallback is the file.** When the push fails, no live session holds the seat, or the seat is ambiguous, the file stays answered and says `delivery: undelivered` with the reason in `deliveryNote`. Treat a `delivery: pending` that outlived its writer as undelivered. **The asker's `/next` picks undelivered answers up** from `engine ask list --status answered --seat <seat>`; wiring that into `/next` belongs to the LOOMESC/NEXT threads, not to this skill. Until it lands, check your own seat's answered asks when you resume.

## Constraints

*   **Never answer your own ask.** An ask is a question to somebody else; answering it yourself is deciding without the record saying so.
*   **One question per decision, many decisions per file.** Put related forks in one file with `DependsOn` between them rather than a chain of files the answerer has to reassemble.
*   **The answer is the file's.** A reply sent only as a message, with nothing written to the file, is lost the moment the asker's context ends.
