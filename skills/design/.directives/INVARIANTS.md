# /design Invariants

Rules that bind only inside `/design` — composing a page from the idea library, or authoring an idea into it. They live here rather than in the shared `~/.claude/engine/.directives/INVARIANTS.md` because that file is read at every session boot and none of these govern a session that never opens the kit. They extend the shared invariants; they never replace one.

Each entry states the rule, what it forbids, where it sends you instead, and what goes red when it is broken. Where nothing goes red the entry says **stated, not enforced** — read that as a gap in the toolchain, not as permission.

## Must Do

- **¶INV_NO_UNPRICED_READ**: Take the library read only after reading the price the verb printed.
  - *Rule*: `node <cli> browse <pagePath>` prints its own cost — bytes and tokens — as the first line of stdout, measured over the string it is about to serve. Read that line before spending it, and take the number from there rather than from any figure written down elsewhere, including the one in `SKILL.md`, which has already been wrong by a third.
  - *Forbids*: spending the read without having read its price; and treating a read that announces itself `PARTIAL` — which is what `--names` and `--keys` produce — as having satisfied the whole-vocabulary step. A PARTIAL read is a roster for finding out whether something exists. It is not this step.
  - *Instead*: take the full read, or price it without taking it via `browse --stats`, which reports the same served figure from the same tokenizer.
  - *Reason*: an agent budgets in tokens and cannot decline a price it only learns by finishing. A remembered byte count is a number that has already moved.
  - *Enforcement*: the price line is mechanical — `idea-cli/verbs/browse.ts` writes it to stdout and a copy to stderr, and labels the PARTIAL case in the same note. **Whether it was read is stated, not enforced**: no invocation exits non-zero when an agent skips the line or substitutes a `--names` read for the whole one.

- **¶INV_LIBRARY_BUDGET_IS_APPROVED_BY_USER**: The user accepts the price of the library read; you do not decide it alone.
  - *Rule*: the read is genuinely expensive, around a third of a 1M-token context. Take it. If it will not fit, say so out loud with the measured number before composing.
  - *Forbids*: quietly spending the budget, and quietly dodging it. Specifically it forbids declining the read on arithmetic over the byte count — a prediction made by something with an interest in not paying is not a measurement of whether it fits — and it forbids reaching for a narrower read you happen to know about and then treating that result as the contract. The measured failure mode here is not refusal, it is **substitution**.
  - *Instead*: attempt the whole read. If it genuinely fails, you will find out by hitting the limit. Then tell the user, with the number; take the narrowest partial that still leaves you able to change your mind about what to reach for; and record in the report that you did. That is a legitimate outcome. Deciding it in advance is not.
  - *Reason*: a page composed against a smaller library looks exactly like a page by an author with less to say, and nothing in the artifact records which library it was. A gate grades what is present, so substitution leaves every check green.
  - *Enforcement*: **stated, not enforced.** Nothing observes whether a number was put in front of a human, and no invocation goes red when one was not.

- **¶INV_SPECIMEN_SHIPS_A_CONTROL**: A new or altered idea ships beside the same markup without its token.
  - *Rule*: the specimen demonstrating an idea is published next to a control — the identical shape with the idea's own token removed — so a reader can see what the idea actually does rather than taking the caption's word for it. Render the pair in one shot and compare them by eye.
  - *Forbids*: shipping a specimen alone; and shipping a control that something on the page paints. An ambient stylesheet, a page-level reset, or a bare-class rule reaching the un-tokened shape makes the control prove the opposite of its caption. Relatedly, a control indistinguishable from a defect has failed at its own job, so absent, zero and unknown must render as visibly different pictures.
  - *Instead*: before trusting a control, confirm nothing on the page styles the un-tokened shape. Keep the idea's rules inside the idea; a page-level reset keyed so the control receives it makes the control look serviced, which is the one thing a control may not do. Where an idea wraps, annotates or marks another idea's element, shoot the annotated and un-annotated element side by side and read both geometries — that claim is unfalsifiable as prose and checkable by eye as a picture.
  - *Reason*: on a page of six new ideas, every defect found was found by opening a shot and none by the readouts, which reported `pageErrors=0 failedRequests=0 hOverflow=0` throughout.
  - *Enforcement*: **stated, not enforced.** Neither `node <cli> check <pagePath>` nor `node <cli> lint <libDir>` carries a finding for a missing or serviced control; searching the CLI for one returns nothing. The skill's own prose says as much — a painted control passes while "every automated check stays green."
