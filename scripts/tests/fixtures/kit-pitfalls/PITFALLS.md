# Kit — Pitfalls (tree-wide)

Traps that cross package boundaries, in the form that lets the next agent recognise the **gesture**
rather than the category. Package-specific hazards live in each package's own
`.directives/PITFALLS.md` — `resource`, `resource-db`, `resource-edge`, `schemistry`, `agent`, `ui`.
**This file exists because until today they had nowhere to go**: every finding below is tree-wide,
and the tree had no root `.directives/`, so the knowledge went into a source docblock, two tsconfig
comments and one package's pitfalls file — each author picking the nearest reachable surface.

⚠️ **A stale pitfall is worse than none, because it is read with authority.** Every entry carries
the measurement that earned it and the moment it was taken.

⭐ **Re-measure before you quote.** Taken against this repo on branch `feature/reactor`,
**2026-09-09 between 11:36 and 17:10 WITA**, across HEADs `ae0f954b` → `4ba6a62b`. Several sessions
were committing throughout; HEAD moved repeatedly inside that window.

## Measuring

- **⛔⛔ ¶PTF_A_NUMBER_IS_A_CLAIM_ABOUT_A_PROGRAM_NEVER_ABOUT_THE_TREE**: Before reporting any count,
  name the **program** it came from — the tsconfig, the vitest project, the revision. A file count, a
  staleness reading, a red set and "the tree is mixed" are all program-scoped, and stating one
  tree-scoped is the single most common error this repo produces.
  - **Measured 2026-09-09 16:05**, one package, two configs, both answers correct:
    `resource-db/tsconfig.test.json` → **15 `dist` / 11 `src`**; `resource-db/tsconfig.json` →
    **15 / 0**. Two agents read these as a contradiction for twenty minutes. The mixing is
    `rootDir: ".."` in the test config, deliberate, so the specimen suites compile the real module
    rather than a fixture shaped like it.
  - **Same window**: `resource-edge/tsconfig.test.json` and `resource-edge/tsconfig.json` → 15 / 0
    both; `resource-example/tsconfig.json` → 0 / 15. ⛔ **A "the tree is mixed" warning was relayed
    to the one seat whose programs have never been mixed.**
  - *Why it survives*: every number is true where it was taken, so nobody re-checks it — and the
    scope is carried in the sentence, never in the number.
  - **The generalisation of `resource-edge`'s own rule** (*"a red set is a claim about a PROGRAM,
    never about a FILE"*), which was written for red sets and is true of every count.

- **⛔⛔ ¶PTF_A_POSITIVE_CONTROL_IS_ONLY_A_CONTROL_IF_YOU_KNOW_ITS_ANSWER_FIRST**: Before believing a
  zero, run the same instrument against a case whose answer you **already know**. A control string
  chosen because it *seems likely* to be present tells you nothing about the instrument and
  everything about your guess — **and a control returning 0 looks identical whether the instrument is
  blind or your guess was wrong.**
  - **Measured 2026-09-09 15:57**: `grep -c 'ideas' ideas-identity/src/__tests__/fakes.ts` → **0**,
    read as *the instrument cannot see this file*. The file is tracked and 9,375 bytes; the word
    simply is not in it. The correct form, run minutes later on the same question:
    `git grep -c 'import' <rev> -- ideas-identity/src/__tests__/` → **three known hits**, then the
    real query.
  - **The same day, done right by another seat**: `git log --all -S'installIdentityActions' --
    ideas-identity/` → **177**, chosen *because it had to be there*, which is what made the paired
    zero trustworthy.

- **⛔⛔⛔ ¶PTF_A_SAMENESS_CLAIM_CANNOT_LICENSE_AN_ACTION**: *"These two are the same"* and *"this is
  only a comment"* are the same move — a **sameness** claim used to authorise a **change**. Sameness
  is almost never what the action needs established. **Name what the action requires, then measure
  that.**
  - **Measured 2026-09-09 18:59**: an uncommitted edit to `resource/src/query.ts` was described as
    *"a +39 docblock"* to four sessions and **frozen into `resource/dist` twice on that description**,
    because "only prose" was the reason it was judged safe to freeze. It adds `SubjectReadFor` and
    **changes `QueryHandler`'s signature** — a type change on the store→system seam, live in the
    artifact every package compiles against.
  - **Same afternoon, same shape**: two copies of a check grammar were collapsed into one on the
    grounds they were *"identical member-for-member"*. ⛔ **That established sameness, not
    correctness — two copies can agree with each other and both disagree with what the emitters
    actually do.**
  - *Why it survives*: the sameness claim is usually **true**. It is the inference from it that is
    unlicensed, and nothing in the measurement flags the gap.
  - ⭐ **The asymmetry worth knowing**: a wrong path fails loudly at the first `ls`. **A wrong
    DESCRIPTION of a real change fails only when somebody makes a decision on it** — so it survives
    every gate until it has already cost something.

- **⛔⛔ ¶PTF_A_PATH_LIST_IS_A_TABLE_OF_CONTENTS_NOT_A_REVIEW**: At commit time **neither the path list
  nor the pathspec tells you what you are about to commit. Only the content does.** `git diff --cached
  --name-only` answers *which files*; the question is *which lines*, and a file you legitimately own
  can hold another session's work by the time you stage it.
  - **Measured 2026-09-09 19:19**: a file measured at **+39/−1** at 18:59 was staged twenty minutes
    later and read **+243/−3**. The file had been rewritten at 19:06:57 by another session's lane.
    ⛔ **The path-list check PASSED** — exactly one path, the intended path. **Only `git diff --cached`
    saw the extra 204 lines**, and the commit was stopped there.
  - **It composes with the rule already known** — *a pathspec scopes WHICH PATHS, never WHAT CONTENT*
    — into one statement: **at commit time, read the content or you have not reviewed anything.**
  - ⭐ *It happened to the session that had spent the day policing this exact hazard, in the commit
    designed to prevent it.* **Knowing the rule does not fire it; the check does.**

- **⛔ ¶PTF_SOME_SUBJECTS_CHANGE_FASTER_THAN_A_RELAY_CAN_BE_HONEST_ABOUT**: This is not
  *re-measure before relaying* — that assumes a subject that holds still long enough to be described.
  **A file under active merge has a half-life shorter than a message round-trip.** Before relaying a
  finding about one, say **when** it was taken, or re-take it at the moment of sending.
  - **Measured 2026-09-09 19:18–19:23**: `resource/src/book.ts` was reported as breaking the build —
    `Unnavigable` used at `:476`/`:491` with no import, `TS2304`, confirmed independently by two
    lanes. **Four minutes later the build read `rc 0`, `0` errors** (control: the same invocation
    reported 77 on a sibling package), because the merge had brought `Unnavigable`'s definition into
    the file at `:610`. **mtime 19:22:45.**
  - **Both lanes were right when they measured.** ⭐ **The instrument was fine; the traffic was
    slower than the subject.** *A correct report about a mid-merge file was one message from being
    delivered as an accusation.*

- **⛔⛔ ¶PTF_A_PIPELINE_REPORTS_THE_LAST_COMMANDS_STATUS**: `cmd | tail -5; echo $?` measures `tail`.
  Read the printed verdict, or redirect to a file and read `$?` from the command itself. `PIPESTATUS`
  is not a portable substitute — it is empty under zsh, which is this repo's shell.
  - **Measured 2026-09-09 18:36**: `node resource/scripts/postbuild.mjs 2>&1 | tail -5; echo "rc=$?"`
    reported **rc 0** and was relayed to four sessions. Re-run unpiped: **rc 1, and always had been.**
  - ⭐⭐ **And the real finding was underneath it**: `postbuild` carries four `process.exit(1)` sites
    and has been **failing its undeclared-import check** while reading green. Two of its three
    findings are its own scanner reading dynamic-import **template literals**
    (`${specifier(probeDir, subject.systemAt, …)}`) as package names; the third, `typescript`
    undeclared, is real. ⛔ **A gate whose true verdict nobody has seen is worse than one nobody
    runs, because its name appears in the build.**

- **⛔ ¶PTF_A_GREEN_TYPECHECK_IS_NOT_A_MIGRATION_THAT_LANDED**: A keyword removed from a grammar can
  remain accepted at run time with no compiler-visible trace, and the removal then **silently drops**
  what it used to carry.
  - **Measured 2026-09-09 19:06**: after `db: { checks }` moved to `attribute.checks`,
    `resource-db/src/ddl/refusals.ts:81`'s `DB_TABLE_KEYS` **still listed `checks`** — so the old
    spelling was still accepted and its constraint discarded with **no error**. **Both `tsgo`
    programs read 0.** Six sites, none compiler-visible; the failures were only in vitest.
  - **Redirection**: when a vocabulary word moves, grep the **runtime key lists** — not just the
    types. A key list is data, and a typechecker has no opinion about data.

- **⛔⛔ ¶PTF_A_GREP_FOR_A_POSITIVE_SAYS_NOTHING_ABOUT_THE_ABSENT_SET**: Searching for what *has* a
  property returns only the haves. **The absent set is not the complement of what printed — it is
  unmeasured, and nothing on the screen bounds its size.** To claim something about what lacks a
  property, **enumerate the population** and test each member.
  - *Why it is worse than a zero*: a zero at least announces that it found nothing. **A list of
    positives announces nothing about what it did not find, and reads as a complete census precisely
    because it is full of results.**
  - **Measured 2026-09-09 17:45**: `grep -rn '"source"' --include=package.json` returned eight
    packages carrying a `source` export condition. `resource` was not among them, and that became
    *"`resource` is the only package in the tree without one."* **Enumerating all twenty: 8 have,
    12 lack.** The claim was off by eleven.
  - ⛔ **And the first correction to it was the same error again** — a reply sampling seven packages
    found one more and reported *"`ui` also lacks it"* as though that completed the set. **Ten more
    were behind it.** *Correcting a sampled claim with another sampled claim is the normal way this
    one survives.*
  - **The shape it belongs to**: the same disease as
    `¶PTF_A_NUMBER_IS_A_CLAIM_ABOUT_A_PROGRAM_NEVER_ABOUT_THE_TREE` — this is the strain where the
    instrument **returns plenty** and still says nothing about the question that was asked.

- **⛔⛔ ¶PTF_ZSH_DOES_NOT_WORD_SPLIT_AN_UNQUOTED_PARAMETER**: `for f in $LIST` runs **once** on the
  whole string. The loop body then operates on one long nonsense argument, exits 0, and prints a
  plausible number. Use an array — `LIST=(a b c); for f in "${LIST[@]}"`.
  - **Four instances on 2026-09-09, three seats, one shell semantic**, each caught only by a control
    written *before* the result was read:
    - a revert loop that reverted nothing and printed `17 failed | 933 passed` — identical to the
      un-reverted run, which would have "proved" the edits changed nothing;
    - a repo-wide reference sweep that *"returned clean and was false"*;
    - `grep --include=*.ts` unquoted — **zsh globs the flag itself**, the command aborts with
      `no matches found`, and a downstream `wc -l` prints **0**;
    - **17:53, in a staging command**: an 8-path exclusion list built the take set at **80 files
      instead of 72**, and would have committed every file it was written to exclude.
  - *Why it survives*: the failure prints a **number**, not an error, and the number is plausible.
  - ⭐ **The transferable half is the ordering**: a control written afterwards is a rationalisation.

- **⛔⛔⛔ ¶PTF_AN_UNRESOLVED_REFERENCE_HAS_FIVE_COSTUMES_AND_ONE_LOOKS_LIKE_SUCCESS**: A `$ref` this
  tree cannot resolve does not fail loudly. It derives as one of five things, and **no
  "is this type real" check distinguishes the fifth from a correct answer.**
  - **The five**, all measured 2026-09-09 between 11:00 and 19:34:
    - the whole type at a root  → `never`   *(loud — nothing is assignable to it)*
    - an optional property      → `?: undefined`
    - under `items`             → `[]`      ⛔ **inhabited: passes every existence check, and only
      `[]` is assignable to `[]`, so the CORRECT handler is refused and the broken one accepted**
    - a bad re-base (intersecting a base onto a node that already has an `$id`) → `unknown`
      *(refuses at both ends and names neither)*
    - ⛔⛔ **an unresolvable reference under schemistry → an explanatory STRING LITERAL.** A string
      literal is inhabited, so `Kind<T>` grades it **REAL**. **One row had a property whose type was
      a paragraph of prose.**
  - > ⭐⭐⭐ ***The fifth is the only one that looks like success, and it defeats every instrument that
    > asks whether a type exists. Only PRINTING the derived type catches it.***
  - **Redirection**: a type-level gate must print at least one derived type into its own assertion,
    not merely assert that one exists. **Four separate gates in this repo pinned an unresolved-`$ref`
    hole as intended behaviour before anyone printed it.**

- **⛔⛔ ¶PTF_AN_ABSENT_CAPABILITY_HAS_NO_LINE_TO_REVIEW**: A capability that does not exist cannot be
  found by reading code — there is nothing to read. **It announces itself only as vocabulary that
  implies it.** When a word in the code promises a capability — *graveyard*, *cache*, *retry*,
  *rollback*, *restore* — grep for the thing it promises, with a control. **A zero there is the
  finding.**
  - **Measured 2026-09-16**: a deletion shipped with a **graveyard** and a `live_path_of` mapping a
    graveyard key back to its live path, and **no restore anywhere** — `restore` / `restore_deleted`
    returned **zero occurrences**, against an `unlink` that does exist (the control). Neither the
    source nor the README said deletion was one-way. **The pair of words was the whole claim.**
  - ⭐⭐ **Why no instrument catches it**: grep, positive controls, hash assertions and planted
    mutations all **operate on lines that exist**. An absence has no line to plant a mutation into.
    What catches it is noticing that the vocabulary promises what the surface does not offer — a
    reading skill, not a tool.
  - **The family, three faces in one night**: a recovery that is partial while described as
    reversible · a sweep that is not transactional while its reader assumes it is · a graveyard that
    implies a restore. **The description is what somebody plans against**, so the person harmed is
    the one who read carefully.
  - **Its sibling already here** is `¶PTF_A_GREP_FOR_A_POSITIVE_SAYS_NOTHING_ABOUT_THE_ABSENT_SET`:
    there the absent set is a population you failed to enumerate; here it is a population with no
    members to enumerate.

- **⛔⛔ ¶PTF_CONSENSUS_IS_CORRELATION_NOT_CORROBORATION_WHEN_THE_LENSES_SHARE_A_PREMISE**: Agreement
  between reviewers reading the same artifact with the same background assumption is **one claim
  counted twice**. **Rank a finding by the independence of its evidence, never by how many seats
  raised it** — and settle a claim about a mechanism by RUNNING the construct, never by polling.
  - **Measured 2026-09-17, one council, two ways.** Two lenses independently escalated that a probe
    harness *"cannot fail"*, and **both were wrong about the same shell semantic**: a `while` body is
    not a `set -e`-exempt context, so a failing `cat` inside one aborts the script before the echoes
    they were reasoning about. The refuter ran the construct standalone — `exit=1`, the echo never
    printed.
  - **Same council**: **four** lenses agreed a tombstone set was newly unbounded. **All four had
    skipped the baseline.** The structure is at `9a3751eb:195`, pre-wave; the change raised the
    per-delete slope and introduced nothing.
  - *Why it survives*: the count is the cheapest number on the page and the panel's own format prints
    it. **The widest agreement and the best-evidenced finding are different rows** — in that same
    council two findings raised by ONE lens each also survived refutation, and the headline that five
    seats shared did not.
  - ⭐ **The raw escalation count from N lenses runs about 6× the real defect count** (seven seats
    escalated 37; six survived refutation). **A council's output is candidates, not findings**, and
    quoting the raw number outside the panel's own files misstates the work by most of an order of
    magnitude.

- **⛔⛔ ¶PTF_TRUE_OF_THE_TREE_AND_INTRODUCED_BY_THIS_CHANGE_ARE_DIFFERENT_CLAIMS**: A reviewer handed
  a change reads it as the cause of everything wrong inside it. **Run `git show <base>:<path>` before
  calling anything new**, and when the subject is prose or invariants rather than code, **audit the
  tree, not the diff.**
  - **Measured 2026-09-17**: every downgrade in a seven-seat council turned on `git show
    <base>:<path>` and nothing cleverer. The four-lens unbounded-tombstone escalation died on one
    baseline read.
  - **Measured 2026-09-18, the same rule pointing the other way**: a sweep of every docblock in two
    files (1,365 + 3,397 lines) found **eight false claims — two falsified by a sibling branch in the
    wave, and six already false at the fork point.** A changed-files-only audit would have missed
    three quarters of them. ⛔ **Keyword search would have found one of the eight**; the other seven
    are ordinary declarative sentences that stopped being true and contain no word to search for.
  - **Redirection**: name the base revision in the brief. A panel told only *what changed* reports
    the tree's standing defects as the change's, and it reports them at MUST FIX.

- **⛔⛔ ¶PTF_A_GENERATED_CORPUS_IS_SILENT_ON_EVERY_AXIS_ITS_GENERATOR_REFUSES**: A generated
  conformance corpus bounds only what its generator would have emitted. **Where the generator cannot
  express an input, a fully green corpus carries no information about it** — and it reads as coverage
  precisely because it is green.
  - **Measured 2026-09-17, twice in one package, both over fail-open behaviour.** The corpus **cannot
    express a deletion case** — the generating walk contains zero occurrences of deletion, so a
    hand-written arm is the only cover the ordering rule has. And it **cannot express an
    unstated-verbs clause**: `corpus.txt:9` makes a bare `-` legal only on a deny, and **the
    generator IS the evaluator, which throws on that input.** So `28/28` is the expected result
    either way, across the one divergence in the package that fails open on OPERATOR error.
  - **Redirection**: for any rule the generator refuses as input, write a unit test — a corpus row can
    never pin it. **Ask what the generator would refuse before quoting its pass rate**, and say so
    beside the number.

- **⛔⛔ ¶PTF_WIRING_A_HARNESS_INTO_CI_CEMENTS_IT_INSTEAD_OF_CHECKING_IT**: CI gates on exit status, so
  automating a harness that **cannot go red** makes it authoritative rather than catching it.
  **Demonstrate ability-to-fail first; automate second.**
  - **Measured 2026-09-17**: a package's harness census found two false greens, **both exit-0**. A CI
    job would have gone green on both and cemented them. The census was deliberately left unwired
    until each guard had been shown failing; wiring it afterwards is safe precisely because it can
    now fail.
  - **The reporting rule that came out of it**: a guard is green only when **its exit status is 0 AND
    its counted failure markers are 0**, and a disagreement between the two is its own finding.
    Neither number alone catches the shape.
  - ⭐ **The proof of a guard is a planted violation, never a reading of it.** Three spellings planted
    on 2026-09-13, all three caught and named, probe removed, green again — a minute's work, and the
    only thing that distinguishes a guard from a sentence about a guard.

- **⛔ ¶PTF_A_RED_SUITE_IN_A_SHARED_REPO_NEEDS_ITS_OWNER_ESTABLISHED_BEFORE_ITS_FIX**: Before fixing
  any failure in a tree several lanes are editing, reproduce it against committed state and **diff
  the failing SETS, not the counts** — identical counts with different members are two causes wearing
  one number.
  - **Measured 2026-09-17**: fifteen failures reproduced **byte-identically** off committed state
    (`diff` of the two FAIL lists empty), which exonerated a neighbouring lane by measurement instead
    of by assumption.
  - **Expect a dominant cause**: twelve of the fifteen were **one line**, in a package the reporter
    did not own; a sibling commit records the same hole as twelve of another package's fourteen reds.
    **Fifteen symptoms with one root is a better report than fifteen fixes.**
  - **Then triage each failure three ways — code wrong · test wrong · ruling unclear — and for a test
    you change, cite the ruling you matched it to.** ⛔ **Never adjust an assertion merely to match
    what the code does**; that encodes the defect as an expectation.

## Surfaces the tree's own history cannot see

- **⛔⛔ ¶PTF_DIST_IS_GITIGNORED_SO_NOTHING_THAT_CONSULTS_GIT_CAN_SURVEY_IT**: `resource/dist` is
  gitignored and `git ls-files resource/dist` is empty, so **no instrument that asks git can report
  its age, its contents, or that a file in it has no source.** Check it directly or not at all.
  - **Measured 2026-09-09 14:29**: `dist` stamped **11:36** against a `src` stamped **14:09** —
    every typecheck any seat quoted that afternoon was taken against a 4.5-hour-stale artifact, and
    nothing anywhere flagged it. Rebuilt at 16:00; all four programs then read 0 errors.
  - **Measured 16:01, and only a per-file check finds it**: `dist/mount.js` has **no source in any
    commit** (`git log --all -- resource/src/mount.ts` → nothing, ever), **no export key**, and **no
    importer** (control: the same grep returns 13 files for a module that does exist). ⭐ **A build
    artifact for a module that never existed.**
  - ⛔ **Do not measure staleness as "oldest dist file vs newest source".** `tsc --build` is
    incremental, so an unchanged source legitimately keeps its old output; that comparison measures
    **rebuild activity**, not staleness, and it raises a false alarm on every partial build. Compare
    each `dist/X.js` against **its own** `src/X.ts`.
  - ⭐ **`resource-db/src/generic/bind.ts` is the one file in the tree that ever wrote this down** —
    *"importing the full interface would make this file's correctness depend on when the neighbour
    was last built"* — and it solved it locally without generalising. **That reasoning is true of
    every package that reads a sibling's `dist`.**

- **⛔ ¶PTF_THE_STAGING_AREA_IS_AN_ARTIFACT_AND_THE_NEXT_COMMAND_QUOTES_IT**: What the index says and
  what a commit says are two claims made at two moments, and both can be true.
  - **Measured 2026-09-09 15:53**: `git mv` asserts a rename **before** the content edit lands, so
    the index read `R100` for `code.ts -> resources/posts.ts`. After the content edit landed in the
    same commit, `git show -M20%` **refuses to pair them at all** — the result shares under a fifth
    of its source. **The index said *rename*; the commit says *replacement*.**
  - ⭐ **`git mv` leaves the rename STAGED**, so the next bare `git commit` by any session sweeps it.
    On 2026-09-09 the index simultaneously held two sessions' work — 22 renames from one, 7 from
    another — **and the only thing that revealed it was two agents reporting different totals** (22
    against 29) for what each believed was the same set.
  - **After every commit, read `git show --stat -M` for the SHAPE**, not just the paths: a `D` staged
    and an `M` committed are different words.

- **⛔ ¶PTF_A_RECONSTRUCTION_PREDICTS_A_TREE_IT_DOES_NOT_CONTAIN_ONE**: A scratch copy built to answer
  *"what will this look like after the commit"* necessarily fills in uncommitted files from the
  working tree. It therefore **cannot** answer *"what does this commit contain"*, and the two
  diverge exactly at the files nobody has committed.
  - **Measured 2026-09-09 15:56**: a pre-commit reconstruction reported a gate naming two broken
    references. One was real. The other lived **only in a working tree** — created and removed the
    same afternoon by one session, never present in any commit
    (`git log --all -S'<the string>' -- <path>` → empty). A clone could never have seen it.
  - *Why it matters*: the false half was written into a commit message as a pre-existing defect.

- **⛔⛔⛔ ¶PTF_A_SHARED_WORKING_TREE_IS_SILENTLY_READ_AS_A_COMMITTED_ONE_BY_THREE_INSTRUMENTS**: In a
  checkout several lanes are editing, *what the code is* and *what the tree holds* are different
  things, and three separate instruments quietly answer with the second. **Run any cross-package
  measurement in an isolated worktree off committed state before concluding anything.**
  - **Three faces, found independently by three lanes in one morning, 2026-09-17**:
    - **a commit hazard** — a pathspec commit on a file carrying three lanes' work publishes two of
      them under your message *(the shape `¶PTF_A_PATH_LIST_IS_A_TABLE_OF_CONTENTS_NOT_A_REVIEW`
      already names, one level out)*;
    - ⛔ **it decides what the type program IS** — one uncommitted import changed whether the program
      read a package's new modules at all: **495 files live against 478 from a `git archive HEAD`**;
    - ⛔ **it decides what NEIGHBOURING packages test against** — a vitest config aliasing a sibling
      package **by path** runs every dependent's suite against that sibling's mid-edit source. The
      run that surfaced this happened to agree with the committed one; **that is luck, not
      isolation.**
  - **Redirection**: `git worktree add` off the commit, or `git archive HEAD | tar -x` into a scratch
    copy outside the repo with `node_modules` symlinked, then overlay exactly your own files.
    **Agreement between the live tree and committed state is a result you have to check for, never a
    default you may assume.**

## Comments that expire

- **⛔⛔ ¶PTF_A_COMMENT_THAT_IS_TRUE_NOW_BECOMES_PROOF_THE_BUG_CANNOT_EXIST**: A docblock asserting a
  safety property is read as verification. When the shape it depends on changes, the comment does not
  fail — it **argues against the code beside it**, and it sits at exactly the line that broke.
  - **In the tree now, 2026-09-09 16:40**: `resource/src/actions.ts:295` — *"two spellings of which
    rows this call is about are two chances for the guard to be asked about a different set from the
    one that gets gated"* — and `:2165` — *"gate would be advisory. It is not."* **Both are true
    today.** Both become false under an array-rooted action `input`, and each sits on the exact
    guard (`isNode(args)`, which is `false` for an array) that would stop running.
  - **The same shape already fired**: `resource-example/gates/validator-corpus.gate.test.ts` states
    *"bounded by the NEXT top-level `export`, never by a character count — a walk that cannot see a
    declaration cannot notice that nothing grades it"* **one line above a walk that violated it**;
    that file and its sibling were green while grading **one** of seven shipped declarations.
  - **And `resource/src/vocabulary.ts:360`** argues for a constraint a ruling now removes.
  - ⭐ **Move the comment in the same commit as the code.** Left alone it is the strongest available
    evidence that the defect cannot exist.

- **⛔⛔ ¶PTF_A_REGION_PARTITION_MAKES_MERGES_CLEAN_AND_CROSS_REGION_SENTENCES_UNVERIFIABLE**: Giving
  parallel threads disjoint regions removes conflicts from the CODE and removes nothing from the
  PROSE. **A thread is accurate about what it owns and speculative about what it merely reads, and
  the merge preserves both without distinguishing them** — a comment carries no assertion, so no gate
  can acquire one.
  - **Measured 2026-09-18, five branches merged in one wave**: zero conflicts, 89 green tests, 28/28
    conformance — **and two docblocks falsified by a sibling branch. Both described modules their
    author did not own.** Every claim each thread made about its OWN region survived. Both false
    sentences came from one branch, which is not a fact about that branch but about **writing prose
    that describes code you do not own.**
  - ⛔ **The expensive instance is a SIZING RATIONALE, not a description.** One falsified sentence was
    the justification for three timeout constants: it argued that a synchronous teardown could park
    the reaper loop and so end every other lease's deadline. A sibling then made the detach lazy and
    moved the drop onto its own thread. **The numbers survived the merge; the reason under them did
    not** — leaving whoever tunes them next to tune against a failure mode that no longer exists, and
    to conclude the budget can be relaxed because nothing catastrophic depends on it any more.
  - ⭐ **The habit that fixes it, and it is not a gate**: when a docblock names a function in another
    module, **state what that function RETURNS or GUARANTEES, never what it PRESENTLY DOES.** A
    contract survives a sibling's rewrite; a description of present behaviour cannot.

- **⛔⛔⛔ ¶PTF_A_FALSE_COMMENT_DOES_NOT_ONLY_MISDESCRIBE_THE_CODE_IT_AUTHORISES_THE_DEFECT**: Where
  docblocks carry the rulings, **prose is enforcement surface.** A rule that has stopped being true
  does not merely mislead the next author — it tells them the thing it forbids is already handled.
  **A stale rule is a licence, not documentation debt.**
  - **Measured 2026-09-17**: an empty module whose entire content was the rule *"the gate runs at
    `open` and nowhere else"* — written as a design property, and true when written. But `truncate(2)`
    **takes a path and opens nothing**: it arrives as a bare SETATTR, and with no
    `default_permissions` the kernel's permission hook returns 0, so **the request reached the daemon
    with no gate anywhere behind it.** A caller holding only `read` could zero a stored object,
    bypassing the delete path so that no graveyard copy existed either.
  - ⛔ **Every reader adding an operation had been told by the rule-stating module that `open` was the
    only place a gate belongs.**
  - ⭐ **And a warning can invert into the error it was written to prevent**: a line reading *"the
    mount lease is the one deadline here that bites"* existed to stop a reader generalising
    *deadlines here are advisory*. Once two more deadlines were built, it told the reader that
    **three** biting deadlines were advisory.
  - **Redirection**: where a comment states that a rule is enforced at some point, name that point by
    **what reaches it**, and re-read the sentence whenever a new entry path lands. **Same family as
    `¶PTF_A_COMMENT_THAT_IS_TRUE_NOW_BECOMES_PROOF_THE_BUG_CANNOT_EXIST`, one step worse**: there the
    comment argues the defect cannot exist; here it invites it.

## Working alongside other sessions

- **⛔ ¶PTF_A_DECISION_THAT_NEVER_TRAVELLED_IS_NOT_A_DECISION**: A ruling recorded in your own log or
  session doc has not reached the session it constrains, and **they cannot detect its absence** —
  they can measure the file, not the intent.
  - **2026-09-09 15:29**: one session was told a file was "kept in" at 14:44, the decision was
    reversed while writing a handoff, and the affected session learned of it as a contradiction
    between two messages ninety minutes later. They had to measure their own file to find out.

- **⛔⛔ ¶PTF_A_FILE_PROTECTED_BY_EVERY_BRIEF_IS_A_FILE_NOBODY_SURVEYS**: A do-not-touch list is a
  coverage hole with a safety rationale, and **it cannot announce itself — the briefs that create it
  are the same briefs that would have to notice it.**
  - **2026-09-09**: eleven files under `resource-example/demo/src` sat on every lane's do-not-touch
    list all day. **No lane measured them.** Three carried 159/54, 103/1 and 134/11 line changes and
    were invisible from both sides of the boundary simultaneously.
  - **Redirection**: when a boundary has held for a while, survey the protected region **once**,
    deliberately, as its own task. Nothing else will.

- **⛔ ¶PTF_ABSENCE_OF_A_MARKER_IS_NOT_EVIDENCE_OF_INDEPENDENCE**: *"This file carries no import
  re-point, so it is unrelated to the move"* is not sound. A re-point is evidence of connection; its
  absence is evidence of nothing.
  - **Measured 2026-09-09 15:41**: an exclusion set built on exactly that rule produced **3
    `error TS`** in the demo program. Three files had to come back, each for a different reason —
    one welded to a changed export, one whose *comment* lines a path gate reads, one whose test
    goldens moved with a semantic change elsewhere.

- **⛔⛔ ¶PTF_PEER_CORRESPONDENCE_IS_THE_UNREVIEWED_SURFACE**: Everything else you write has a reader
  positioned to refuse it — a brief is executed by someone who can push back, an artifact is
  critiqued, a commit is reviewed. **A message to a peer session is read by a recipient with every
  reason to treat it as settled.** It is the one surface written with authority and no reader.
  **Verify a peer's claim before acting on it, and expect the same of your own.**
  - **Measured 2026-09-16, two sessions in one night, two different rules, the same channel**:
    - one lane was handed *"cite file and symbol, not file and line"* at session start, **instructed
      two design threads in it**, and shipped clean — zero line-citations across both designs, three
      phase reports, the proof dossier and the committed code. **It leaked only in the message typed
      by hand**: three of five citations stale, two pointing at text that was not the claim.
    - another session briefed four lanes on *a match inside a docblock is not a definition*, then told
      a peer as established fact that a symbol lived in a file it does not live in. They had run
      `grep -rln` (**files-with-matches**) and **read a filename as a location.** The peer had already
      replied *"I am rewriting ours to match"*; a retraction one message ahead of it was all that
      stood between the error and two durable files.
  - ⭐ **The shape is structural rather than a lapse: the rule holds wherever it is written down as an
    instruction and fails where the author is the one writing.** Being the reviewer is a position, not
    a virtue, and nobody occupies it for their own outgoing messages.
  - ⚠️ **Cite text, not line numbers, for anything meant to outlive the night.** On a branch taking
    commits from several lanes, line numbers age in hours; both sessions relocated the same six
    docblocks by grepping banner phrases, a form that still resolves a week later.

- **⛔⛔ ¶PTF_A_BRIEF_CARRIES_A_CLAIM_FURTHER_AND_FASTER_THAN_A_REPORT**: A fact quoted into parallel
  briefs arrives carrying the conductor's authority, at threads with no way to check it and no
  standing to refuse it. **Before a fact goes into a brief it needs what a fact going into a report
  needs: measured, or marked unverified.**
  - **Measured 2026-09-17**: a README sentence was written into three briefs as established fact **by
    the same session whose wave was falsifying it.** That README carried ten false claims by the time
    anyone audited it; its last edit predated seven merges, and it is the package's only readable
    description of the system.
  - *Why it survives*: a brief feels like a lower-stakes document than a report. **It is the same
    claim reaching more readers, earlier, with less ability to refuse it.**

- **⛔⛔ ¶PTF_AN_UNOWNED_CHANGE_IS_A_DEFECT_VECTOR_INDEPENDENT_OF_ITS_QUALITY**: A change that sits
  uncommitted and unclaimed across sessions is **reviewed by everyone and adopted by nobody** — and
  each individual refusal is correct, because claiming another lane's migration is the same error as
  sweeping it. **Give an orphan an owner before it lands, not after.**
  - **Measured 2026-09-17**: a kernel commit — found half-staged in the shared index with no lane
    admitting authorship — made dispatch grade a verb's declared input for the first time, so every
    declaration gap in every package surfaced at once: **twelve of one package's fifteen failures, and
    twelve of another's fourteen.** Three lanes examined it and declined it, each correctly.
  - ⛔ **And here is what nobody owned it enough to check.** Its refusal shape returns a call-level
    envelope for a per-target fault, collapsing every sibling slot — **contradicted by a ruling
    written down in its own neighbouring file** (*"a call-level refusal answers `results: []`, and the
    only producer of one is query mode"*), by the validation module that already keys faults per
    target, and by the consuming package's own declared output.
  - *The tell*: **a change nobody will name as theirs.** The fix is not better review — all three
    reviews happened and every decision in them was right. **The outcome was a defect anyway.**

## Measuring a safety property against a subsystem that does not exist yet

- **⛔⛔ ¶PTF_A_GATE_YOU_CAN_REMOVE_FOR_FREE_IS_A_GATE_THAT_ISNT_THERE_YET**: When a change removes,
  bypasses or short-circuits a **protection**, measuring its cost against today's tree answers the
  wrong question — because the protection may be unbuilt, in which case removing it is genuinely
  free **today** and a hole **later**, with no event in between to re-run the measurement. *"I
  measured it and nothing broke"* is true exactly while there is nothing there to break.
  - **Measured 2026-09-10**: a consumer session was one declaration from turning prefetch off on its
    `write` path, and framed it honestly as cost — a wasted `adapter.exists` per target per layer
    against paths that by definition do not exist yet. **In this pipeline prefetch IS the reach
    check** (one pass, by design), so the declaration is a gate bypass with a performance benefit
    attached. Against the tree as it stands it loses **nothing**: `grants` is read by **zero lines**
    of `resource-kernel/src` logic — three occurrences in `vocabulary.ts`, two of them docblock prose.
    So the measurement returns *free*, correctly, and **the day grants land the same declaration
    silently exempts that write from them** and every caller-supplied path becomes writable over an
    existing row.
  - ⭐ **The tell is the direction of the error.** The **cost** of keeping the gate is visible today;
    the **risk** of dropping it is not, and will not become visible on the day it becomes real. So
    the evidence available at decision time points the wrong way, and points there with numbers.
  - **Redirection**: measure a protection against its **intent**, never against its current
    implementation. Where the subsystem is unbuilt, the honest reading of *what does removing this
    cost* is **unknown**, never *nothing*. And write the refusal onto the member, so it is not
    re-added the day somebody notices the I/O.
  - ⛔⛔ **AND THE PAIRED TESTING RULE, which is the half that catches it: A TEST THAT DISTINGUISHES
    TWO CANDIDATE DESIGNS MUST BE RED UNDER THE WRONG ONE, NOT MERELY GREEN UNDER THE RIGHT ONE.**
    An arm proving *a create stops reporting a false refusal* passes under **both** the safe design
    (gate still runs, misses insert) and the unsafe one (nothing loaded, nothing gated) — **so it
    would bless the hole.** The discriminating arm needs the negative half: a write whose targets
    include a row the caller must NOT reach, asserting **that row is still refused while the absent
    ones insert cleanly**. Red before, green under the safe design, **still red under the unsafe
    one.** Same family as `¶PTF_A_POSITIVE_CONTROL_IS_ONLY_A_CONTROL_IF_YOU_KNOW_ITS_ANSWER_FIRST`,
    one level up: the control is not a known input but a rejected **design**.
  - *Both halves were articulated by the consumer session that had proposed the bypass and then
    talked itself out of it, which is worth more than either of us reasoning about it alone.*
