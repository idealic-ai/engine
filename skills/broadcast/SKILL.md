---
name: broadcast
description: "Tell a set of live seats something they should apply — your direct children, everyone under a seat, or every live seat — written so each reader knows who it is for, what to do and whether to ack, then sent with `engine broadcast` and its delivery read back. Queued for idle seats by default; waking them needs the operator's order. Triggers: \"/broadcast\", \"broadcast this\", \"tell all my children\", \"tell every seat\", \"send guidance to the fleet\", \"announce this to the seats\"."
version: 1.0
tier: lightweight
args: "<--children | --subtree <seat> | --all> [--sticky [--expires YYYY-MM-DD]] [--id <slug>] [--wake-reason \"<the operator's order>\"] -- <the guidance>"
---

Write a broadcast a seat can act on, send it, and read back who got it.

# /broadcast Protocol (Guidance Going Down or Across)

**Invocation.** Call it as

```
Skill(broadcast, "<--children | --subtree <seat> | --all> [--sticky [--expires YYYY-MM-DD]] [--id <slug>] [--wake-reason \"<the operator's order>\"] -- <the guidance>")
```

Everything before `--` picks the audience and the kind; everything after it is what you want the seats to know, in your own words. The skill writes the message to the standard below, sends it, and reports the delivery. Do not run `engine broadcast` (send) by hand: the skill is where the writing standard lives, and a hand-run send skips it.

[!!!] A **sessionless utility** skill: no session directory, no phases, no log of its own. The broadcast record under `~/.claude/data/yarik/broadcasts/<id>.md` is the record. If a session is active, log one line there after sending, naming the id and the delivery counts.

## When to broadcast and when to ask

*   **Broadcast** when you are telling several seats something they should apply: a ruling that came down, a landed change they must rebase onto, a rule to follow from now on. It expects no answer and grants no authority: a seat reads it as guidance from a peer, never as the operator's instruction, unless the text quotes the operator and says who relayed it.
*   **Ask instead** (`Skill(ask, "<the question you need answered> --to <seat> [--reserved-for operator]")`) when you need a decision back from someone above you. A broadcast that ends with a question collects its answers nowhere.
*   **Message one seat directly** when only one seat needs it. A broadcast to one seat is a message with extra bookkeeping.
*   **A loom lane never broadcasts.** It reports to its conductor, which decides what leaves the loom.

## Who it reaches

The audience comes from the live tmux tree, read at send time:

*   `--children`: your direct children.
*   `--subtree <seat>`: every seat under that seat, not the seat itself.
*   `--all`: every live seat with an interactive Claude session, except you. Shell panes are skipped and listed.

Pick the narrowest audience that holds everyone who must act. A seat outside your subtree is not yours to instruct; `--all` is for news every seat needs, such as a resume or a fleet-wide rule.

## Writing one a reader can act on

The reader is a busy agent who has not followed your work and may meet this message at its next prompt, an hour from now. It reads once and acts. So the text says, in this order:

1.  **Who it is from, and whose word it carries.** Open with `From <your seat>:`. If you are relaying the operator, say so and quote the ruling with its time: `Operator (23:05), relayed by manager:director: …`. Without that line a seat cannot tell a ruling from a suggestion.
2.  **What the reader must do.** One action per sentence, in the imperative, concrete enough to do without asking back: name the command, the commit sha, the file, the ticket key. When some seats must act and others need not, say which: *"If you have a lane on IDE-205, rebase it onto 8f483e67c. Everyone else: no action."*
3.  **What ack looks like.** Say which of these you want, and only one:
    *   *No ack needed* — for news.
    *   *Ack once applied* — the seat runs `engine broadcast ack <id>` after it has done the thing, and `engine broadcast status <id>` then shows who has. The delivered message already ends with the ack command, so you only need to say that you want it.
    *   *Reply to your manager in one line* — when you need to know what each seat did, not only that it did it.
4.  **Nothing else.** No history, no reasoning the reader does not need to act. A long message is cut at 1,500 characters in the delivered copy, with the record path for the rest, so the action must come first.

The skill shows you the text it composed from your guidance before sending. Check it against the four points, especially that the action names something concrete.

**A worked example.** Guidance given: *"tell my children VISIONMAP_REPORT has a Landed as column now and they should send docs:visions their artifacts."* Sent as:

> From manager:core: VISIONMAP_REPORT.md on main (39e07f968) now ends every row with "Landed as". When you file or write something for one of your vision rows, send docs:visions the artifact directly: a ticket key, a doc path on main with its sha, a probe report path, or the operator's ask link with the answer. No ack needed.

## Queue or wake

An ordinary broadcast **wakes nobody**. It is pushed live only to a seat that is busy right now, because a busy seat is already awake, and it is queued for every idle seat, which sees it once at its next prompt, its next tool call or its next session start. A queued seat is a normal outcome, not a failure.

*   **Use an ordinary broadcast** for everything you decide to send yourself. This is the default and almost always right.
*   **`--wake-reason "<why>"` wakes every seat in the audience**, idle or not. Use it **only on the operator's explicit order** (the standing rule: no wake without the operator's order), such as a resume after a usage limit lifted. **The same rule covers `engine broadcast resend <id> --wake-reason "<why>"`**, which turns an ordinary record into a wake: a resend after exit 1 is `resend <id> --undelivered` with no wake flag, unless the operator ordered the wake.
*   **The reason cites something a reader can check**, never only a time and a paraphrase. Cite one of these:
    *   an answered ask marked `reserved-for: operator`, by its `<seat>/<id>`, whose answer orders the wake: `--wake-reason "operator, ask meta:engine/wake-resume-0431: resume, the limit lifted"`;
    *   the broadcast id of the operator's order as a seat relayed it: `--wake-reason "operator 04:37, relayed in broadcast account-changed-resume-4: resume"`.

    If you have neither, you do not have the order. Send it ordinary and let the queue deliver it, or, if waking seems necessary, ask first with `Skill(ask, "<why the seats need waking> --to operator --reserved-for operator")`.
*   **Nothing but this text enforces the rule.** `engine broadcast` checks only that the reason is one non-blank line, so a wake sent on a made-up reason goes out. Script-side enforcement belongs to `scripts/broadcast.sh`'s owner.
*   **`--sticky`** also reaches seats that start later, until they ack it or it expires (`--expires YYYY-MM-DD`). Use it for a rule that stands, not for news. Withdraw it with `engine broadcast retract <id>` when it stops applying.

## What the skill runs

1.  **Parse** the arguments: the audience flag, the optional `--sticky`, `--expires`, `--id` and `--wake-reason`, and the guidance after `--`. No audience flag, or no guidance, stops here with one line saying what is missing.
2.  **Refuse a wake without a checkable order.** If `--wake-reason` is present but does not cite an answered operator-reserved ask (`<seat>/<id>`) or the broadcast id that relayed the operator's order, stop and say so, and offer to send it ordinary instead. Read the cited ask (`engine ask read <seat>/<id>`) or record (`engine broadcast status <id>`) to confirm it says what the reason claims.
3.  **Compose** the text from the guidance to the four points above. Choose an id if none was given: a short lowercase slug of the subject, such as `rebase-onto-8f483e6`. An id that already exists is refused by the command, so pick another.
4.  **Dry run** to see the audience: `engine broadcast <audience flags> --id <id> --dry-run <<'MSG' … MSG`. Read the seats it lists. If it reaches seats you did not mean, narrow the flag rather than sending.
5.  **Send** with the same flags and no `--dry-run`, the composed text on stdin through a quoted heredoc (`<<'MSG'`) so nothing in it is expanded. Read the exit status from the command itself, never through a pipe:
    *   **0**: every seat was delivered or queued.
    *   **1**: the record is written and at least one seat was not delivered. Run `engine broadcast status <id>` and, once the cause is fixed, `engine broadcast resend <id> --undelivered`, with no `--wake-reason` unless the operator ordered the wake (see Queue or wake). Never send a second broadcast for the same guidance.
    *   **2**: usage, identity or an existing id. Fix the named problem and send again.
    *   **3** or **4**: a seat is not in the live tree, or the tree could not be read. Report it; do not retry blindly.
6.  **Report** in one or two lines: the id, the record path, and the delivered / queued / undelivered counts the command printed. If you asked for an ack, say that `engine broadcast status <id>` shows who has acked.

## Reading and answering broadcasts

These are read-side commands and stay direct; this skill does not wrap them.

*   `engine broadcast ack <id>` — you have applied a broadcast addressed to you.
*   `engine broadcast status <id>` — who was delivered, queued, and who acked.
*   `engine broadcast pending` — what is queued or standing for your seat.
*   `engine broadcast retract <id>` — withdraw your own sticky broadcast.

`engine broadcast go-request` (asking path owners for a go on a pull request) is LANDING.md's procedure, not a broadcast of guidance, and is run as that document says.

## Where the mechanism is described

`engine broadcast --help` is the reference for every flag, the queue, the wake rule and the exit codes, and `docs/ASK_AND_ESCALATION.md` places broadcasts beside asks. This skill cites them and does not restate the mechanism.
