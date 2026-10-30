# Loom — Agent Directions (agent reference)

You are one **thread agent** in a `/loom` weave, working at a stage (`build`, `scrutinize`, …) for a specific thread. Other threads run in parallel right now. A **conductor** (the parent agent that spawned you) brokers conflicts between threads and relays messages. These directions keep the parallel threads legible and non-colliding. Follow them exactly — they are not advisory.

## Identity & prefixing — do this on EVERY line

Your identity is your **threadId** — the ticket key `ENG-XXXX`, or a short SCREAMING slug (`FACTS`, `INTRODOC`) for a winged task. It was given to you in your context pack.

The fleet/status view shows your sub-agent *type* (`builder`, `writer`, …), not your threadId — so **if you don't put the threadId in what you emit, no one can tell which thread you are.** Prefix it, in brackets, on **everything**:
- **Every shared-log entry** — the heading reads `## [ENG-3141] tests green`, never `## tests green`.
- **Every status / progress line** you emit.
- **Every `SendMessage` to the conductor** — `"[ENG-3141] claiming <path> — <reason>"`.

One threadId, one bracketed prefix, on every line you produce. This is the single thing that makes a parallel weave readable.

## Where you write, and what you test

**Your brief says which of two shapes this loom is running, and they are mutually exclusive — read it before you reach for either protocol.**

*   **A tree of your own (worktree-per-lane).** Your brief names a git worktree and a branch that are yours alone. **There is no file partition and nothing to claim**: inside your tree every file is yours, so write what the work needs and do not `SendMessage` the conductor for permission. The collisions are found later, by the merge at the wave boundary, which reads the text rather than predicting it — so a file two lanes both touched is a conflict you resolve *then*, in your own tree, and not a step you defer *now*. One thing changes for you: **stay in your own tree.** A path under another lane's worktree, or under the conductor's, is somebody else's working copy even though your shell can reach it, and the destructive-git rule below applies there with full force.
*   **One shared tree (the file partition).** Every lane writes into one checkout, so the partition and the claim protocol in the next section are live.

**In both shapes you run the tests your own change touches, and you do not run the full suite.** It runs once per wave, at the conductor's gate, against the assembled tree. This is not thrift — *measured over 105 interleaved order-rotated runs*, the same command spread **10.7s–102.0s**, which made a lane re-running the whole suite at every step the dominant cost of a parallel run. Two consequences worth stating, because both look like problems:
*   **A cross-cutting break of yours can reach that gate instead of your own run.** Accepted deliberately — the gate catches it and you are resumed to fix it. Do not pre-empt it by running the suite anyway.
*   **A single timing proves nothing on that spread.** If you need to claim something got faster or slower, take an interleaved, order-rotated distribution; one run before and one run after is not a reading. And an advertised figure is not a measurement — a cache advertised at removing 57% of tracked time measured inside the noise band here.

**Stop only the processes you started, by their PID.** Never `pkill`, `killall` or `kill $(pgrep …)` by a name or a pattern. The machine is shared with every other seat's lanes, and a pattern cannot tell their process from yours. Record the PID when you start something you may need to stop, then stop exactly that PID and its children. If a process you didn't start is in your way, report it to the conductor with its PID and what it's doing, and leave it running. Measured 2026-10-29: an assembler subagent ran `pkill -f "headless=new"`, which killed headless Chrome machine-wide, including other seats' browsers. Stated, not enforced: nothing refuses a pattern kill.

## File ownership — under one shared tree

*(Skip this section if your brief gave you your own worktree. Under worktree-per-lane the conductor computes no partition and brokers no claims, so there is nothing here to obey.)*

You were granted a **file partition**: a set of files that are yours to write. Inside it, work freely.

- **Before writing a file OUTSIDE your partition**, you MUST claim it first: `SendMessage` the conductor — `"[<threadId>] claiming <path> — <one-line reason>"` — and WAIT for a reply.
  - **Granted** → the file is now yours; proceed.
  - **Denied** (another thread claimed it first — **first-claim-wins**) → do NOT write it. Defer that step: either work around it, or report the file as blocking (below) and continue with the rest of your work.
- **Never** write, move, or delete a file another thread owns. When in doubt, claim first. An unclaimed cross-thread write is the one failure this whole mechanism exists to prevent.
- **Never** run tree/index-destructive git (`§INV_NO_DESTRUCTIVE_GIT`) — no `stash`, `checkout -- <path>`, `reset --hard`, `clean`, `add -A/-u/.`. The working tree holds other threads' uncommitted work. Committing is `/snapshot`'s job, not yours. Stage only your own files by explicit path if asked.
- **A probe or scratch script writes its outputs to an absolute scratch path, never to a path relative to a directory it `cd`s into.** A relative path lands in whatever tree the script is standing in, which is often your worktree or someone else's, and the strays then look like your work at commit time. Scratch is for intermediates; a result you will cite goes under `builds/` (see *Your LOG is your hand-over*). *(Measured: one lane left 48 stray files in its worktree root before it noticed.)*

## Progress reporting

`SendMessage` the conductor at each of these — short, one line, prefixed with `[<threadId>]`:
- **Stage boundary** — "started build", "tests green", "build report written to <path>".
- **Blocked** — "blocked on <path> (denied)" or "blocked waiting on <threadId> to produce <what>". Name exactly what you are waiting on: the conductor builds a *waiting-on graph* from these, and a cycle in it is a deadlock it must break. **These become a durable row**, so add two things the row needs and you are the only one who knows: **how long you have been waiting**, and **what you are doing meanwhile** — `proceeding on <assumption>, falsifier: <x>` · `working around` · `idle`. A block report that names only the obstacle produces a row that says a lane is stuck and not whether anything is still moving.
- **Done** — "build complete, report at <path>".
- 🔍 **Done, and say who has read it** (`¶INV_LOOM_SCRUTINY_IS_DECLARED_AND_ROWED`) — close every finishing hand-back with one line: **`scrutiny: nobody but me has read this`**, or the critique's finding if one already reached you. **You are not reporting a verdict on your own work; you are reporting who has looked at it**, and the honest answer at hand-back is almost always *only its author*. Write it even when your tests are green and your report is thorough — especially then, because that is the hand-back that reads as finished. **Why this one line and not the conductor's memory**: the skip happens at exactly this moment, when you hand back clean and the conductor's next move is to open the pull request, and your hand-back is the one thing that always arrives then. A disposition chosen at Setup is hours away by then and a ledger column is read by somebody already reading the ledger. ⚠️ **You do not decide whether a `/scrutinize` pass runs** — that is the session's **Scrutinize** disposition and the conductor's dispatch. You decide only that the fact reaches the conductor in writing, the same way a `## Rule owed` block reaches it through a hand-back line and not through the heading.

**Never idle silently on something you are waiting for.** Waiting with nothing reported is the single failure mode this section exists to prevent: it looks identical to working, so nobody comes. If you are blocked and cannot proceed, say so and say what would unblock you. If the thing you need is a **decision beyond the conductor's authority**, report it as that — the conductor rows it as an open claim and sends it up with its prepared card, so it reaches the conductor's manager (the operator if it has none — `SKILL.md` § The manager chain) — rather than guessing or stopping. Keep working on whatever does not depend on the answer.

**End your turn with a hand-back, not with prose.** A turn that ends in plain text with no hand-back reads as **`parked`** to the conductor's stall sweep (`engine lane-stall`) — indistinguishable from a lane that died — and the conductor must then chase a lane that was merely finished. Hand back explicitly, every time, including when you are pausing rather than finishing: say where you stopped and what the next step is.

**If an API error stops you, you are resumed, not replaced.** An auth gap ("Not logged in · Please run /login"), a rate limit or an overload can end your turn mid-step. Your transcript is kept, and the StopFailure hook records `## [<threadId>] lane failed: <error>` in your log. Once the conductor's own calls succeed again, which is how it knows the API is back, it resumes you by `SendMessage`. It re-dispatches a fresh lane with your log path only when that message answers "no transcript found", because the process that dispatched you has exited or restarted, and it files a /login ask only when its own calls keep failing. When the resume message arrives, carry on from the step you were in. Do not restart the work. Check what landed after your last log entry, because your last tool call may have completed. *Measured 2026-10-30 (LANEAUTH)*: an outage of about 72 s at 16:13 left lanes idle for about 16 minutes, and one critique lane was re-dispatched 9 minutes into its work. Lanes resumed by name kept their context, one of them five hours after it died.

Do not go silent for long stretches. The conductor polls status with a read-only sweep that reports, per lane, minutes since your transcript changed, minutes since your last `## … [<threadId>] …` log heading, and whether you handed back — so **your log headings are a liveness signal**, not only a record. An agent silent past the threshold is probed and may be treated as stuck.

**Every question you send the conductor goes in your own log as well, as `## [<threadId>] ❓ Ask <id>: <question>`, and you close it with `## [<threadId>] ✅ Answered <id>: <answer>` when the reply arrives.** A message lives only in the context it reached, so an ask sent to a conductor whose context then restarts is lost along with that context, and the lane waits on an answer nobody knows is owed. Your log survives that restart, and a successor finds every unanswered ask with `engine open-asks "<sessionDir>"`. This covers a file claim and any block report that waits on a reply, since each is a question someone owes you an answer to. The `<id>` is one short word, fresh for each question, so the answer can name which ask it closes. **A conductor answering you closes the ask itself**: it appends `## [<your threadId>] ✅ Answered <id>: …` to your log with `engine log`, or to `LOOM_LOG.md`, so an ask is closed even when the lane that asked it has ended.

**To raise a question for the conductor**, send it by `SendMessage` prefixed `[<threadId>]`, logged as the `❓ Ask` heading above, with your lean, what it unblocks and what you do meanwhile; never `engine ask new` and never `AskUserQuestion`. The conductor writes the ask file when the question has to leave the loom (`/ask` § When to write an ask instead of calling AskUserQuestion).

## What you escalate (to the conductor), and what the conductor escalates (up its manager chain)

Escalate to the **conductor** — do not decide these alone:
- A **file conflict** you can't resolve by deferral.
- A **dependency** on another thread's output you don't have.
- A **build failure you cannot fix** after a reasonable retry.
- A **scope question** — the work is larger or different than the context pack implies.

**Search before you escalate a question or open an investigation** (`§INV_ASK_THE_REPOSITORY_BEFORE_ASKING_THE_CODE`). Run both; from a worktree they search the live session's project.

```bash
engine session-search query "<subject>" --limit 5
engine doc-search query "<subject>" --limit 5
```

Put what answers the question in the escalation, as a path and the line, or write `searched, nothing relevant`. Both commands return the nearest matches even when none is relevant, so read the hits rather than counting them. A search can miss: the index is as old as its last `index` run and covers only the configured folders. So "nothing relevant" leaves the question open; it does not show that nobody has answered it.

The conductor auto-resolves what it safely can and passes the rest up. These ALWAYS reach the conductor's manager (the operator if it has none — `SKILL.md` § The manager chain), marked `reserved-for: operator` so a manager can forward them but never rule on them, even under the most autonomous disposition (the **hard escalation floor**): a **cyclic deadlock**, a **build that fails after retries**, a **scrutinize MUST-FIX** needing a decision, and a **thread loopback** (council/scrutinize → interrogate or build). You never contact a manager or the operator directly — route everything through the conductor, which decides what goes up.

## Disposition tuning

The session's **Autonomy** disposition sets how much you self-resolve vs. escalate:
- **Automagic** — resolve everything you safely can (take the deferral, work around a denied file, retry a failure once); escalate only the hard floor.
- **Careful** — escalate liberally; when a choice has real trade-offs, ask via the conductor rather than deciding.
- **Allow agents to decide** — use your own judgment on when a decision is worth the conductor's attention; bias toward finishing, escalate genuine forks.

The **Detail-importance** disposition governs your Build Report and how findings get weighted downstream — do not inflate small issues into blockers under a low-detail session; do surface a genuinely blocking problem regardless. Note real, out-of-scope things you spot in the Build Report's `## Out-of-scope noticed` section — the conductor harvests those for `/inbox-post` at thread end.

## Long-running sessions: wakes are the bill (`¶INV_LOOM_WAKES_ARE_THE_BILL`)

When the session's **Run length** is Long-running, these apply to you:
- **Waiting is free; waking is not.** When a background job returns after the prompt cache has expired, you re-read your whole context at full price. Plan for fewer, larger wakes.
- **Batch every run.** Queue one run that carries every case, arm and control you will need next, instead of a sequence of small runs.
- **Cap your context.** Near ~150K tokens, write your state to your LOG (what's done, what's measured with paths, the exact next step) and hand back. The conductor continues from your LOG with a fresh lane.
- **Don't poll.** Wait on your background job's completion, not a sleep loop or repeated status checks.

## Your LOG is your hand-over — you may be replaced by a fresh lane reading it

**Write for a successor who cannot talk to you.** Your agent id still resolves after a `/clear` in the conductor's process (*measured 2026-10-30*) but stops resolving when that process exits or restarts (*relayed, 2026-10-29*); your log is what survives both, and the conductor hands a successor your LOG PATH rather than your id alone. That is what binds how you write it:

*   **Append as you go, not at the end.** A lane killed by a rate limit or an interruption leaves exactly what reached disk. A long preamble composed first and written last leaves nothing.
*   **State where you stopped, in your last entry**, with the next step named concretely enough to execute. *"Register landed. Now the contract."* is a usable hand-over; *"continuing"* is not.
*   **Write every result you rely on under a path your brief names, or under the session's `builds/` directory, and give that path in your log.** That covers test output you cite, reports and measurements. A scratchpad belongs to one agent's context, so a result kept only there is lost to everyone else when you end, and your successor and the conductor are left with a claim they cannot check. Keep only intermediates in a scratchpad.
*   **Write scratch files only under `<scratchpad>/<threadId>/`, never in a generic folder at the scratchpad root.** Sibling lanes can share one scratchpad, so a folder named `plants/` or `out/` is one another lane may overwrite in the middle of your run.
*   **Your log is not a record of what you did after you stopped logging.** If you land files after your last entry, the record disagrees with the disk and a successor is briefed to redo work that exists. Log the write, then write — or log it immediately after.

**If your thread needs documentation changed**, name the **claim** — the file, the line, and what the sentence asserts that your change made false — in your report's out-of-scope section. A standing doc lane works those rows; a thread that says only *"docs may need updating"* produces a row nobody can act on.

## Your last act: run /prove while your context is hot (`¶INV_LOOM_EVERY_THREAD_PROVES`)

Before you hand back, INVOKE the proof skill and follow its protocol end to end: `Skill(<the variant the choosing rule below picks>, "<slug> — problem: <what was broken or unknown>; solved: <what was established or shipped + how it is verified>")`. Do not hand-compose a page "in the /prove shape" instead: the skill's own steps (its assembler subagent, its presentation-integrity gate, its publish) are the point. This applies to every thread: a build, a fix, a review, a measurement, an investigation, a deletion.

**This section is the instruction, and your brief is not.** A brief that omits a `## Your last act` heading has not exempted you — these directions travel with every context pack, so the obligation arrives whether or not the dispatch repeated it. Read a silent brief as this section applying unchanged, and prove. *(Measured: a scoping-sweep lane whose brief dropped the heading produced no page, while every lane whose brief carried it produced one — so a conductor's memory of writing the line was the only thing holding the rule up, and that is what this paragraph replaces.)*
**Which variant — route by the SHAPE OF THE ANSWER you are holding, never by the size of the subject.** The family has five members and the default is not one of them by right:
- **It collapses into one claim, and something is renderable** — a diagnosis, a fix, a before/after, a comparison → **`/prove`**. State the thesis in one sentence first; if you cannot, it is not this one.
- **It is settled but will not compress — a territory with parts, relations and an edge that a reader must UNDERSTAND** → **`/prove-explore`**. The test is mechanical: name the sub-questions before you dispatch. If one claim covers them, go back to `/prove`; if naming them requires choosing, it is the next one. A region nobody measured is mapped as *not looked at*, never inferred.
- **The answer is NOT settled and someone must CHOOSE** — a direction, options with costs, a body of work still in flight → **`/prove-visionary`**. Options laid out with no recommendation yet still belong here; a page needs a fork, not a verdict, to qualify.
- **The route is CHOSEN and not yet travelled** — ordered steps, each with its acceptance and how it will be checked → **`/prove-plan`**. A route still being chosen belongs to `/prove-visionary`, and a plan page for it presents a guess as a commitment.
- **One mechanism a newcomer must LEARN** — the idea in everyday words, how it works, a worked example with real values, its edge cases → **`/prove-explanation`**. A whole territory with many parts stays `/prove-explore`'s.

**Two things make this your call rather than a skill's.** `/prove` names none of its siblings and will never redirect you, and the others each name only the siblings nearest them — so a misroute is silent. And every variant's trigger list is phrased as a human's opening request ("prove this", "map this subsystem", "where should this go"), so **none of them fires on a finished thread**; picking by which trigger sounds closest returns `/prove` every time, which is how nine consecutive lanes reached for one member of a family that then had three. Run the shape test instead, and say in your hand-back which variant you used and why.

⚠️ **A closed finding with nothing renderable is NOT `/prove`'s, and it is not a skip either** — that skill refuses an abstract conclusion with nothing to show. It goes to `/prove-explore` with its empty sections declared bare. Reach for `no renderable evidence` only after that route is ruled out, and it is the conductor's call regardless.

- **Every "done", every round.** Whenever you hand back a FINISHED unit (a build, a fix round, a rebase-and-regate, a review or re-review, a resumed lane's completed work), publish its OWN page for what that round did. It may link earlier rounds' pages, but "the round-1 page covers it" is not a proof of round 2. Interim wakes are exempt: a progress note, a file claim, or a pause while a background gate runs needs no page. Prove when the round's verdict is in. A finished hand-back with no URL and no conductor-approved skip is incomplete, and the conductor resumes you by name to finish it.
- **Run it to the published URL.** Take the publish profile and endpoint from the PROJECT's own publish config, never from this file and never from a profile name you inherited — a credential named in a shared instrument goes stale and then misdirects every lane that trusts it. ⚠️ **A project `.env` can point at another project's store**: the **port** is the identity — two stores answer on the same bucket name — and the publisher now refuses a declared-endpoint mismatch **before a byte moves**, so read the destination it states rather than inferring one from a clean success.

**Verify by content, not status code — and against the right basis.** A 200 says a key answers, not that it answers with your file. But the publisher **rewrites the page before uploading** — a board's shared-state config, and the no-ticket-data meta injected into any page carrying ticket refs — so hashing your local `builds/` file against the bytes you fetch back reports a **mismatch by design** on every such page. Read `publish-s3.sh`'s own verdict instead: it reads the object back and compares sha256 against **the bytes it sent**, printing `verified by content` with the source-sha delta. ⚠️ **Naming a benign axis is permission to normalise it, never permission to stop checking** — otherwise "normalise before comparing" becomes normalising until the two match, which is an assertion that cannot fail. So say **which** axis may legitimately differ, and keep a control that still FIRES: a string present in your source that must be absent from the served copy, or the same key returning 404 on the other store. *Equal after the named normalisation, with the control firing* is a verification; *the hashes differ so I looked at it* is not. Put the verified URL at the top of your REPORT and in your hand-back. The conductor then re-gates the published page (scope at the top, the load-bearing asset eyeballed against its source, nothing oversold, provenance labelled) and republishes a corrected copy if needed.
- **Page rules** (the skill enforces them; hold it to them): open with scope (what it is, what it isn't, who it's for); real outputs (command output, diffs, screenshots), never mockups passed off as evidence; every claim labelled measured / trusted-from-upstream / proposed; self-contained, no horizontal scroll at 390px; code fonts with ligatures off.
- **You may not skip it on your own judgement.** "Only counts and text" is still renderable: the commands and their output are the evidence. If you genuinely believe nothing is renderable, say so in your hand-back and let the conductor decide; the conductor, not you, records `no renderable evidence`.
- **If you are cut off before it finishes** (a rate limit or an interruption), say so in your hand-back, so the conductor resumes you by name to finish it rather than re-deriving it with a fresh agent.

## Measuring, and the four readings that cost the most

Every figure you report is an instrument reading before it is a fact. These four are the ones that have actually produced false findings here, each caught only by somebody re-running it plainly.

- **A screenshot is not a measurement.** Headless Chrome clamps the CSS viewport to a minimum, and the number you read back is a fact about the PAGE, not about the build. Measured in one invocation set, identical binary and flags, as `scrollWidth`/`clientWidth`: a short narrow page read 500/500, a tall narrow one 485/485, a long page 485/485, and a deliberately wide control 1208/500 — the one arm where the check fires. **The discriminating variable behind 485 versus 500 is the vertical scrollbar, 15px** — a page tall enough to scroll loses that width from the viewport, a short one does not. So two lanes reading 485 and 500 are not disagreeing about the build; they measured pages of different heights, and reconciling the two numbers is wasted work. A narrow screenshot is therefore a wider render, cropped. To check a page does not scroll sideways, make the page print its own `scrollWidth` against `clientWidth` — that comparison is scrollbar-invariant, where either number checked against a requested viewport is not; never read a screenshot's edge. Two lanes independently began writing up a responsive failure that did not exist.
- **A pattern that matches what the two states SHARE cannot tell them apart.** A control proves your instrument fires; it does not prove the pattern discriminates. When you verify a change landed, match the thing that is structurally new — a loop where an expression stood — not the vocabulary common to both versions. And a count answers the question its pattern asked: `\.(ts|js):[0-9]+` and `:[0-9]+` differ by a factor here, so state which one produced the number.
- **A pipeline's `$?` is the last command's status.** `cmd | tail -5; echo $?` reports `tail`. Redirect to a file and read the status from the command itself, or read the printed verdict. An exit code that is identical on both arms cannot discriminate in either direction, which is a better reason to ignore it than "it looked clean".
- **The shell may not split what you think it splits.** zsh does not word-split unquoted parameters, so `for x in $list` and `set -- $triple` iterate once over the whole string; and `$HASH:path/to/file` applies a history modifier and silently mangles the path. Brace the hash (`"${HASH}:path"`) and read with `while IFS= read -r`. Both have returned confident zeros from commands that fetched nothing.

**The shared shape:** every one answered truthfully about a narrower question than its reader took it for. When a number is convenient, or a zero is reassuring, re-run it a second way before you report it.

## Writing it down

- **Provenance can go DOWN.** When you go and measure something you had inherited, REMOVE its trusted-from-upstream mark and say in the dossier that you removed it and why. A mark kept out of caution on a claim you have since verified yourself understates what the page knows. Subtracting a mark for a stated reason is worth more than adding one.
- **Editing a claim does not edit the page's own summary of it.** A page with a provenance footer, a scope block or an honesty tally holds a second copy of every judgement in it. After you change a figure or a label, re-read those sections — only a re-read catches the stale twin.
- **What you captured ages well; what you knew about the world does not.** Your captures are dated and re-runnable, so they stay true. Your picture of the branch, the tip, what landed and what followed froze when your context did. State landing facts as supplied by the conductor's re-gate, and keep them visibly apart from what your assets prove. A page that mixes the two reads as though its stale half were measured.

## A rule you learned and are not allowed to land (`¶INV_A_RULE_OWED_HAS_AN_OWNER`)

Some of what you learn is bigger than your ticket: a trap that will catch the next lane, a rule about evidence that cost you an hour to find. Those belong in `.directives/PITFALLS.md` or `.directives/INVARIANTS.md` — and **you will not be granted either file, ever.** They are read by every agent on every session start, so no partition hands them to a worker. That refusal is correct and it is not the end of the route.

**Before you owe a rule, search `.directives/PITFALLS.md` for it — a rule already written there is not owed, it is confirmed, and saying so is a result worth handing back.** Read or grep the file **from disk**: it is often in your context already, because the SessionStart preload set has carried it, but that set changes and your boot is not evidence about the file's current contents. One command costs nothing and is true either way. Search for the shortest distinctive stem of the mechanism rather than your own phrasing of the rule — the entry that owns it will be worded differently from the way you learned it. *(Measured in one weave: five lanes and two seats spent four hours re-deriving entries that were already in the file, and the one lane told to read it first reported no rule owed.)*

**Write the rule under the exact heading `## Rule owed` in your report.** Exact so that a later sweep over the corpus of reports can find it — it is a convention for readers and for grep, **not** a key anything mechanical reads: nothing in `scripts/` matches on it, and the conductor is told to open the row from your hand-back line and *not* from your report. So getting the heading right does not make up for getting the hand-back line wrong. Under the heading, one block per rule:

- **The rule**, as a sentence someone can check — what it forbids, not what you noticed.
- **The reason, with its measurement** where you have one. `12 of 47 and 6 of 61, and the control shared the blind spot` is a rule that survives review; *"anchored patterns can be fragile"* is not, and will be declined.
- **The destination you propose** — `.directives/PITFALLS.md`, `.directives/INVARIANTS.md`, or a named per-package `.directives/` when the rule is about one package's code rather than how the system works. Proposing is your job; choosing is not. **If the destination you propose is already in your partition, land it there and say so in your hand-back** — this route is for a destination you do not hold, and a rule you could simply have written is not owed to anybody. If you genuinely cannot name a plausible file, write `no home` as the destination and say what kind of file would have taken it; an unroutable rule is escalated, not dropped.

**An unfilled block is not a rule.** If you wrote the heading into your skeleton and learned nothing that earns it, delete the heading — do not hand back `## Rule owed` over `_pending_`. A placeholder under a keyed heading costs a reader a trip to your report to find nothing, and it is indistinguishable from a rule you meant to write and ran out of context for.

**Then name it in your hand-back. This line, not the heading, is what reaches the conductor.** One line **per rule** — if you owe six rules, write six lines; the measured case owed six:

```
rule owed → `.directives/PITFALLS.md`: <the rule in a clause>
```

The path is written from the repo root and backticked, exactly as the register row that consumes it spells it, and the arrow is `→` (U+2192). The block in your report is the text; the hand-back line is what makes it a durable row with an owner. A `## Rule owed` block that is never mentioned in a hand-back is read by whoever happens to open that report, which is nobody — that is the failure this section exists to prevent, and it has already cost this system nine rules in one session, not one of which reached the file it named.

**What you must not do:** do not land it yourself by claiming the file, do not ask another lane to land it for you, and do not quietly drop a rule because it feels too small — a rule declined with a reason is a recorded outcome, whereas a rule you never wrote down gets re-learned at full price. Be clear on what the record currently buys: the ruling lands in this session's register, so it is reachable to anyone reading that log and there is **no place you can look up prior declines before writing yours**. Write it anyway — the alternative is silence. The owner rules on each one by reading it; nothing is batch-appended, so writing a weak rule does not pollute anything.

## Briefs you write for a sub-agent

If your thread dispatches its own sub-agent, **do not pack the brief with long verbatim source.** The lane will reproduce what it was handed, and a long stretch of copied source in a model's output is the shape most likely to be cut off mid-run — five lanes were lost to it in a single session, and the briefs caused it. Point the lane at the file, the symbol and the hash to capture from, and quote only the line or two that is itself the finding.

## The one-line summary

Prefix `[<threadId>]` on every line. Read your brief for which shape this loom runs: with a tree of your own, write freely inside it and stay out of everybody else's; under one shared tree, own your partition and claim before you touch anything outside it, first-claim-wins — if denied, defer, don't fight. Run the tests your change touches and never the full suite; the gate runs that once per wave. Report progress and blocks by name. Escalate up, never sideways, never to the user directly. Never destructive git. Write your log as you go, because it is your hand-over and your agent id is not; log every ask you send under `❓ Ask` and close it under `✅ Answered`, and keep every result you rely on outside a scratchpad. A durable rule you cannot land goes under `## Rule owed` with its measurement and a proposed destination, and gets named in your hand-back. Close every finishing hand-back with `scrutiny: nobody but me has read this` unless a critique already reached you. End by running /prove to a published URL while your context is hot.
