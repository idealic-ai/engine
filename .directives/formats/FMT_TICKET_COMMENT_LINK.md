### ¶FMT_TICKET_COMMENT_LINK

**When to use**: EVERY reference to a *specific tracker comment* — a transcript passage, a prior triage / corroboration, a provenance source — renders as a **labeled deep-link to that comment**, never a bare comment id and never a link that only reaches the issue. The comment-level sibling of `¶FMT_TICKET_LINK`.

**Rules** (config-driven — do NOT hardcode the tracker):
*   Source the **comment-anchor template** from the project's `## Tracker` config (the project `CLAUDE.md`), alongside the issue-URL template. Finch (Linear): `<issue-url>#comment-<shortId>`, where `<shortId>` is the comment id's first 8 hex chars — e.g. `https://linear.app/finchclaims/issue/FIN-3457/feedback-and-transcripts#comment-e3b45fac`. Other trackers set their own anchor form; this never bakes one into the engine.
*   Render `[<label>](<comment-deep-link>)` with a meaningful label (source + short id), e.g. `[🟣 comment e3b45fac](…#comment-e3b45fac)`.
*   The `<shortId>` comes from the comment object you already hold — `save_comment` returns it on create, `list_comments` on read (first 8 chars of the id). The issue slug comes from the issue URL / `get_issue`.
*   A comment reference with no `## Tracker` anchor configured → leave the bare id as plain text (nothing to deep-link to).

```markdown
Source: [Rob ↔ Yarik call (🟣 comment e3b45fac)](https://linear.app/finchclaims/issue/FIN-3457/feedback-and-transcripts#comment-e3b45fac)
```

**Anti-pattern**: a bare `` `e3b45fac` `` / "comment 9c6208d5" in prose; a markdown link whose text names a comment but whose URL stops at the issue (`…/issue/FIN-3457`); hardcoding the `#comment-` anchor in the engine instead of sourcing it from the project config.
