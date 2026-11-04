# [NAME] — Vision
**Tags**: [lifecycle tags]

*Written by `/envision`. A line marked PROPOSED is a lean waiting on the fork it names; a `**State (…)**` line and a `🔄 STATUS RECONCILIATION` section record what happened and are written only by `reconcile`.*

## Provenance

*   **Written by**: [threadId] in [host session path], [YYYY-MM-DD]
*   **Record**: [host]/builds/[slug]_ENVISION.md
*   **Asks**: [[seat/id](app URL)] — [answered | open]
*   **Previous version**: [none | git ref]

## Decisions

*One line per answered fork. This is the list a reader checks before arguing with a chapter.*

*   **[FORKID]** — [the choice] — [ask seat/id] — decided against: [the options not taken, one clause each]

## 1. Background

*   **Problem**: [what is wrong today, in plain words]
*   **Current state**: [what exists, by path]
*   **Cost of inaction**: [what keeps happening if nothing changes]

## 2. Vision

### Goal
[The outcome, one paragraph.]

### Success criteria
*   [observable outcome]

### Non-goals
*   [exclusion]

### Constraints
*   [what bounds the work, with the ruling or reason behind it]

## 3. Architecture sketch

[The shape of the result: components, how data or control moves, the key technical decisions. Diagrams in the `§CMD_FLOWGRAPH` vocabulary.]

## 4. Decision principles

*   [the rule a builder applies when a choice comes up that this document did not foresee]

## 5. Context sources

*   [path or ticket] — [what it told us]

## 6. Dependency graph

[The chapters and their edges.]

### Parallel groups
*   **Wave 1**: [@slugs]
*   **Wave 2**: [@slugs]

### Critical path
[@slug → @slug → @slug]

### Shared resources
*   [a file or service two chapters both touch, and how they share it]

## 7. Glossary

*   **[term]**: [meaning in a few words]

## Chapters

### `@[area]/[slug]`: [Title]
**Thread**: [SLUG ≤12, A-Z 0-9 -, starts with a letter, never ends in a hyphen] · **Type**: [bug | feature | chore | tech-debt | spike] · **Ticket**: [none | IDE-NNN] · **Status**: [proposed | ripe | in flight | landed | dropped]
**State ([date], after [what])**: [one line; written by reconcile only]

- **Plain terms**: [one sentence, no project vocabulary]
- **Goal**: [the outcome this chapter makes true]
- **Wrong today**: [the file, row, output or behaviour that is wrong now]
- **Acceptance signals**:
    - [observable outcome]
- **First step**: [one line: where to put your hands]
- **Not in scope**: [exclusions]
- **Size**: [chunk | finding | too big — split] · **Effort**: [S | M | L]
- **Depends on**: [@slugs | none] · **Blocks**: [@slugs | none]
- **Wave**: [N, from the parallel groups]
- **Owner**: [lane] ([seat]), from [the ownership line it was read from] — [PROPOSED (fork X) when the map does not settle it]
- **Paths**: [dirs or file groups it will touch]
- **Open questions**: [each with its ask fork id | none]

## 🔄 Status reconciliation

*Appended by `reconcile`, one dated section per day: what moved, labelled measured / inferred / proposed, with any superseded wording kept.*
