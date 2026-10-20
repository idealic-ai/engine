### ¶CMD_READ_INBOX_CHANNEL
**Definition**: The ONE canonical path for reading a Linear **inbox channel's** drained signal. It fetches the channel's comment trees, then removes the replies the intake machinery itself posted and the annotations that are not firehose signal, and hands back a flat list of new human signal. It carries the **exclusion vocabulary** — the marker set every skill-authored reply leads with — and the program that applies it, so neither lives in a caller.

**Rule**: A skill or agent reading an inbox channel routes the read through here, and **writes no filter of its own**. The drained set is what this command returns.

**A caller's own marker list is a different contract and stays with the caller.** This atom defines what a read must not count; a skill's list declares what that skill stamps. They are not duplicates, and collapsing them destroys the declaration the exclusion depends on. What they must share is the **vocabulary below** — a marker a skill stamps that this atom does not carry is a reply no drain recognises, which is the whole failure mode. **Current callers: `/groom` (Phase 0) and `/intake` (Phase 1, the Linear transport only).** See `¶INV_EXCLUDE_OWN_COMMENTS`.

**Constraint**: **READ-ONLY against Linear.** This atom fetches and filters. It never comments, resolves a thread, or advances a watermark — `/intake` owns its project watermark and `/groom` mints none (`¶INV_GROOM_ADDS_NO_NEW_WATERMARK`).

**Constraint**: **LINEAR ONLY.** The marker-prefix rule exists because every skill post on Linear lands under the operator's own human identity, so the author field distinguishes nothing. **Do not apply this command to Slack.** Slack gives the bot its own user id, so `engine slack-read` excludes own messages by a real author check — stronger, and free of this rule's cost, which is that a human reply opening with a marker word is dropped. A caller draining Slack uses that author check and does not reach for this atom.

**Prerequisites**:
*   **`engine project fetch` available**, and `jq` on the path. No `engine` CLI → report the skipped read in one line and fall back to the caller's own behaviour; never hang and never read a channel by hand-rolled MCP paging, which is what this atom replaces.
*   **A resolved project and channel scope.** Resolve the project through `§CMD_READ_PROJECT_HANDBOOK` when the caller does not already hold it — the channel set is a property of the project.
*   **No session required**: a pure read.

**Parameters**:
```json
{
  "project": "REQUIRED — the project id or name whose inbox channels are being read.",
  "since": "OPTIONAL ISO8601. Omitted → a full snapshot. A delta filters on `updatedAt`, so a thread nobody has touched since it was last looked at cannot appear in one.",
  "out": "REQUIRED — the payload file path. The payload is large; it is written to a file and processed with jq, never read into context.",
  "walk": "OPTIONAL 'new-signal' (default) | 'still-owed'. 'new-signal' returns the filtered flat set. 'still-owed' is a different question and is described below rather than filtered here."
}
```

**Algorithm**:
1.  **Fetch once, to a file.**
    ```
    engine project fetch <project> [--since=<ISO8601>] --out=<the session's builds dir>/inbox-fetch-<ts>.json
    ```
    One call returns the comment **trees** for every inbox channel plus the live `structure.channels`. **A non-zero exit wrote nothing** — surface it and advance no watermark. The command prints the payload path as its last stdout line.
2.  **Check `channelsResolved`.** `false` means the project's inbox milestone name did not resolve and the channel set came back empty. Say so and re-fetch with `PROJECT_FETCH_INBOX_MILESTONE=<the project's inbox milestone>`, rather than proceeding as though the project had no channels.
3.  **Apply the filter below to the payload.** It removes, in one pass: every comment whose body leads with a marker from the vocabulary, and every **anchored** comment (`quotedText != null`, which annotates a ticket's *description* rather than the firehose). It walks **every node at every depth**, because a reply is itself signal.
4.  **Dedup by comment id** against the caller's own raw input log, and write the surviving set there **before** advancing anything the caller tracks (`¶INV_WRITE_BEFORE_WATERMARK`).
5.  **Degrade in one line.** A missing CLI, a non-zero fetch, or an unresolved channel set → say which, and hand control back. Absence is a normal state and must be **visible**: a caller that could not drain says it could not drain, and never reports an empty channel instead.

**The exclusion vocabulary, and the program that applies it**

This fence **defines the vocabulary and is the only statement of the reader-side rule**, and it is the one that runs. A caller executes it (`jq -f`) rather than paraphrasing it, because a prose copy of a filter beside an executable drifts from it — which is the failure that put a `⏳ marinating` reply back into a drain as fresh human feedback.

Adding a disposition means adding its marker **here and in the skill's own writer-side list, in one edit**. A disposition the protocol can produce but cannot mark is a reply that returns next pass looking like new signal, and the likeliest offender is a reason posted onto a thread that stays unresolved by design. The agreement between this table and the skills' lists is checked by `scripts/tests/test-inbox-read-cmd.sh`, so a divergence fails a test rather than waiting to be noticed by a later pass.

```jq own-comment-filter
# Input:  an `engine project fetch --out` payload — .tickets[].comments[] as trees.
# Output: the flat new-signal set, each node tagged with the channel it arrived on.
def own_comment_markers: [
  "candidate",
  "seems like",
  "→",
  "🔎 needs-triage",
  "👀 claimed",
  "✅ result",
  "filed as",
  "shipped in",
  "⏳ marinating"
];

# Every node at every depth, flattened rather than pruned: a human reply nested under a
# skill-authored one is signal, and pruning the subtree would discard it with its parent.
def flatten_tree: [ .[] | ., (.children // [] | flatten_tree[]) ];

def leads_with_own_marker:
  ((.body // "") | sub("^\\s+"; "")) as $b
  | any(own_comment_markers[]; . as $m | $b | startswith($m));

[ .tickets[]?
  | { channel: (.identifier // null), channelTitle: (.title // null) } as $ch
  | (.comments // [] | flatten_tree)[]
  | select((.quotedText // null) == null)
  | select(leads_with_own_marker | not)
  | { channel: $ch.channel, channelTitle: $ch.channelTitle,
      id, author, createdAt, resolvedAt, body }
]
```

**Which disposition each marker marks**

A caller names its **outcome** and reads the marker from here, rather than carrying marker strings of its own — two lists that can disagree is the mechanism behind the leak, not merely its symptom.

*   **a ripeness nomination** → `candidate`
*   **a dedup link to a ticket or a cluster** → `seems like ENG-XXX` / `seems like <cluster>`
*   **a destination pointer**, naming the channel drop or chunk the signal was routed to → `→`
*   **a triage request** → `🔎 needs-triage`, then `👀 claimed by <who>` on the claim, then `✅ result` on the report
*   **a graduation**, naming the ticket → `filed as ENG-XXX`
*   **already shipped before the pass looked**, so no ticket was needed → `shipped in ENG-XXX`
*   **a marinate**, with the reason in the same reply → `⏳ marinating`

Markers are emoji-led wherever a bare word would collide with a human reply that happens to open with it. When a reply cites a **specific** comment, deep-link it via `§FMT_TICKET_COMMENT_LINK`; ticket keys via `§FMT_TICKET_LINK`.

**Constraints**:
*   **The two halves are one contract.** This atom is the reading half. The writing half is the caller's: every reply it posts onto a channel leads with the marker this atom gives its outcome. A caller that gains a new disposition and not a new marker has reopened the leak, whatever this filter does.
*   **A marker is matched on the body's leading text, never on the author.** The cost is accepted and stated rather than discovered: a human reply that happens to open with a marker word is dropped. That is why the emoji-led markers exist, and why `candidate` and `seems like` are the two worth watching.
*   **Never filter on resolved state** (`¶INV_RESOLVE_ON_DISPOSITION`). A resolved thread is *dispositioned*, not closed to input, so a new reply on one is live signal and drains like any other. Surface it prominently — it is usually someone correcting a triage the system got wrong.
*   **The still-owed walk is a different question and is not this filter's.** Resolution is a property of a **thread**, so a reply reads `resolvedAt: null` forever and a recursive walk overstates what is open by roughly the reply count. A caller asking what is still owed reads **root comments only**, from a fetch with **no `since`**, and does not reuse the flattened set above.
*   **The payload never enters the caller's context.** It is written to `out` and processed with `jq`; a single longform drop runs to tens of kilobytes.
*   **Do not copy the fence into a caller, an asset, or a handbook**, and do not write a second filter anywhere. A second *filter* is the defect this atom exists to remove, and the exclusion leaks at whichever copy was not updated. A caller's writer-side marker list is not such a copy and is left alone.

---

## PROOF FOR §CMD_READ_INBOX_CHANNEL

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "project": {
      "type": "string",
      "description": "The project whose channels were read, and how it was resolved"
    },
    "payloadPath": {
      "type": "string",
      "description": "The --out file written, or 'none — <reason>' when the fetch wrote nothing"
    },
    "since": {
      "type": "string",
      "description": "The ISO8601 window opened, or 'full snapshot' when no --since was passed"
    },
    "channelsResolved": {
      "type": "boolean",
      "description": "The payload's own flag. False means the inbox milestone did not resolve and the channel set came back empty — a caller must say so rather than report an empty inbox"
    },
    "nodesWalked": {
      "type": "integer",
      "description": "Comment nodes visited at every depth, before filtering"
    },
    "ownCommentsExcluded": {
      "type": "integer",
      "description": "Nodes dropped for leading with a marker from the fence"
    },
    "anchoredExcluded": {
      "type": "integer",
      "description": "Nodes dropped for carrying quotedText"
    },
    "drained": {
      "type": "integer",
      "description": "Nodes handed back as new signal. nodesWalked minus the two exclusion counts"
    },
    "filterSource": {
      "type": "string",
      "enum": ["command-fence", "hand-rolled"],
      "description": "Which program ran. 'hand-rolled' is a contract violation and must be reported as one, never recorded quietly"
    },
    "fallbackApplied": {
      "type": "string",
      "description": "The one-line degradation notice given to the caller, or 'none — channel drained in full'"
    }
  },
  "required": ["project", "payloadPath", "since", "channelsResolved", "nodesWalked", "ownCommentsExcluded", "anchoredExcluded", "drained", "filterSource", "fallbackApplied"],
  "additionalProperties": false
}
```
