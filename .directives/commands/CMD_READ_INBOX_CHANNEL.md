### ¶CMD_READ_INBOX_CHANNEL
**Definition**: The ONE canonical path for reading a Linear **inbox channel's** drained signal. It fetches the channel's comment trees, then removes the replies the intake machinery itself posted and the annotations that are not firehose signal, and hands back a flat list of new human signal. It carries the **exclusion vocabulary** — the marker set every skill-authored reply leads with — and the program that applies it, so neither lives in a caller.

**Rule**: A skill or agent reading an inbox channel routes the read through here, and **writes no filter of its own**. The drained set is what this command returns.

**A caller's own marker list is a different contract and stays with the caller.** This atom defines what a read must not count; a skill's list declares what that skill stamps. They are not duplicates, and collapsing them destroys the declaration the exclusion depends on. What they must share is the **vocabulary below** — a marker a skill stamps that this atom does not carry is a reply no drain recognises, which is the whole failure mode. **Current callers: `/groom` (Phase 0) and `/intake` (Phase 1, the Linear transport only).** See `¶INV_EXCLUDE_OWN_COMMENTS`.

**Constraint**: **READ-ONLY against Linear.** This atom fetches and filters. It never comments, resolves a thread, or advances a watermark — `/intake` owns its project watermark and `/groom` mints none (`¶INV_GROOM_ADDS_NO_NEW_WATERMARK`).

**Constraint**: **LINEAR ONLY.** The marker-prefix rule exists because every skill post on Linear lands under the operator's own human identity, so the author field distinguishes nothing. **Do not apply this command to Slack.** Slack gives the bot its own user id, so `engine slack-read` excludes own messages by a real author check — stronger, and free of this rule's cost, which is that a human reply opening with a marker word suppresses its whole thread. A caller draining Slack uses that author check and does not reach for this atom.

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
  "walk": "OPTIONAL 'new-signal' (default) | 'open-threads'. 'new-signal' returns the filtered flat set. 'open-threads' lists every unresolved root with a `dispositioned` flag — the deliberately-open threads the drain no longer offers. Both run from the one fence below, selected by the INBOX_WALK environment variable (`INBOX_WALK=open-threads jq -f ...`)."
}
```

**Algorithm**:
1.  **Fetch once, to a file.**
    ```
    engine project fetch <project> [--since=<ISO8601>] --out=<the session's builds dir>/inbox-fetch-<ts>.json
    ```
    One call returns the comment **trees** for every inbox channel plus the live `structure.channels`. **A non-zero exit wrote nothing** — surface it and advance no watermark. The command prints the payload path as its last stdout line.
2.  **Check `channelsResolved`.** `false` means the project's inbox milestone name did not resolve and the channel set came back empty. Say so and re-fetch with `PROJECT_FETCH_INBOX_MILESTONE=<the project's inbox milestone>`, rather than proceeding as though the project had no channels.
3.  **Apply the filter below to the payload.** It removes, in one pass: every comment whose body leads with a marker from the vocabulary, and every **anchored** comment (`quotedText != null`, which annotates a ticket's *description* rather than the firehose). It walks **every node at every depth**, because a reply is itself signal, and it withholds a **root** whose thread carries a marker-led comment anywhere beneath it: disposition is a property of the thread, so the parent of a groom reply is not new signal. On such a thread a non-marker descendant is emitted **only when it was created after the thread's latest marker-led reply**: an earlier one was in front of whoever wrote that disposition, so returning it would hand the caller an echo of something already decided. A later one is someone answering the disposition and drains.
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

# An emoji-led marker matches on its SIGIL alone: the emoji is the machine signature and the words
# after it are prose a writer re-phrases, so `⏳ still marinating` is the same marker as
# `⏳ marinating`. A word-led marker still needs its whole phrase, because a bare word is exactly
# what the emoji-led markers exist to avoid colliding with — `seems` must not match a human's
# "seems unrelated". Derived from the table rather than listed beside it, so emptying the table
# empties the prefixes and a control arm stays honest.
def own_comment_prefixes:
  [ own_comment_markers[]
    | . as $m
    | ($m | split(" ")[0]) as $head
    | if ($head == $m) or (($head | explode | .[0]) < 128) then $m else $head end ];

def leads_with_own_marker:
  ((.body // "") | sub("^\\s+"; "")) as $b
  | any(own_comment_prefixes[]; . as $m | $b | startswith($m));

# Disposition is a property of a thread: a marker-led comment anywhere under a root marks the
# whole root as dealt with. Keyed on the marker, never on resolvedAt.
def dispositioned: any((.children // []) | flatten_tree[]; leads_with_own_marker);

# The latest marker-led reply is the disposition that had every earlier reply in front of it, so
# an earlier reply is an echo and only a later one is new. null when the thread carries no marker.
def last_marker_at: [ (.children // []) | flatten_tree[] | select(leads_with_own_marker) | .createdAt ] | max;
def after_last_marker($root):
  ($root | last_marker_at) as $t
  | if $t == null then . else map(select((.createdAt // "") > $t)) end;

# Selected by the INBOX_WALK environment variable; unset means new-signal.
#   new-signal  (default) the flat set of new human signal.
#   open-threads  every unresolved root with a `dispositioned` flag, so a deliberately-open
#                 thread (marinating, or owed an answer) stays listable although the drain
#                 no longer offers it. Roots only, from a fetch with no `since`.
($ENV.INBOX_WALK // "new-signal") as $walk

| ([.structure.channels[]?.identifier]) as $inbox_channels
| [ .tickets[]?
    | { channel: (.identifier // null), channelTitle: (.title // null) } as $ch
    | if $walk == "open-threads" then
        select(.identifier | IN($inbox_channels[]))
        | (.comments // [])[]
        | select((.quotedText // null) == null and (.resolvedAt // null) == null)
        | select(leads_with_own_marker | not)
        | { channel: $ch.channel, channelTitle: $ch.channelTitle,
            id, author, createdAt, dispositioned: dispositioned, body }
      else
        (.comments // [])[] as $root
        # A dispositioned root is withheld, and so is every reply the latest marker already answered;
        # a reply after that marker is new signal and drains.
        | (if ($root | dispositioned) then [] else [$root] end
           + ($root.children // [] | flatten_tree | after_last_marker($root)))[]
        | select((.quotedText // null) == null)
        | select(leads_with_own_marker | not)
        | { channel: $ch.channel, channelTitle: $ch.channelTitle,
            id, author, createdAt, resolvedAt, body }
      end
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

Markers are emoji-led wherever a bare word would collide with a human reply that happens to open with it. **An emoji-led marker matches on its sigil alone** — the emoji is the machine signature, and the words after it are prose a writer re-phrases, so `⏳ still marinating` is the same marker as `⏳ marinating`. The phrase in the table is the canonical wording a writer should use, not the string the filter compares. **A word-led marker still needs its whole phrase**, because a bare word is precisely what the emoji exists to avoid colliding with: `seems` must not match a human's *"seems unrelated to the export bug"*. When a reply cites a **specific** comment, deep-link it via `§FMT_TICKET_COMMENT_LINK`; ticket keys via `§FMT_TICKET_LINK`.

**Constraints**:
*   **The two halves are one contract.** This atom is the reading half. The writing half is the caller's: every reply it posts onto a channel leads with the marker this atom gives its outcome. A caller that gains a new disposition and not a new marker has reopened the leak, whatever this filter does.
*   **A marker is matched on the body's leading text, never on the author, and one marker-led comment anywhere under a root withholds the whole thread.** Matching an emoji-led marker on the whole phrase rather than the sigil is how a reply in the family escaped a table it was already in: `⏳ still marinating` drained as fresh human signal for two days while the vocabulary agreement and the writer-side lists all read clean, because the marker *was* in the table and the reply *was* in the family. A writer re-phrases prose; it does not re-pick the emoji. The cost is accepted and stated rather than discovered: a **human** reply that happens to open with a marker word suppresses its entire thread, not only itself. A root *"Totals wrong on report"* with the human reply *"→ same thing on the Friday export, attaching a screenshot"* drains nothing, and `INBOX_WALK=open-threads` then lists it `dispositioned: true`, so a live human signal reads as groomed. `→` is the sharpest case because people use it constantly. That is why the emoji-led markers exist, and why `candidate`, `seems like` and `→` are the three worth watching. `scripts/tests/test-inbox-read-cmd.sh` pins this behaviour so a change to it is deliberate.
*   **Never filter on resolved state** (`¶INV_RESOLVE_ON_DISPOSITION`). A resolved thread is *dispositioned*, not closed to input, so a new reply on one is live signal and drains like any other. Surface it prominently — it is usually someone correcting a triage the system got wrong. **New means after the thread's latest marker-led reply**, read from `createdAt` and never from `resolvedAt`: a reply that predates that marker is an echo the disposition already answered, and on a real Product: Handbook fetch five such echoes were the whole of what the drain returned from its channels. The cost, accepted: a human reply posted between a `🔎 needs-triage` and its `✅ result` is treated as answered by the result.
*   **The still-owed walk is a different question from the drain.** Resolution is a property of a **thread**, so a reply reads `resolvedAt: null` forever and a recursive walk overstates what is open by roughly the reply count. A caller asking what is still owed runs the fence with `INBOX_WALK=open-threads`, which reads **root comments only**, from a fetch with **no `since`**, and does not reuse the flattened set. Listing by `resolvedAt` there is a read of thread state for a human, not a drain filter: suppression from the drain keys on the marker-led descendant, so `¶INV_RESOLVE_ON_DISPOSITION` is not touched.
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
