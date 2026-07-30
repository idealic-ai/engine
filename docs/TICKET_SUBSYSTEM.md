# Ticket Subsystem — subscribe · notify · fetch · watch/auto-drain

How the engine tracks Linear tickets across sessions and pulls their content, and how the two
pieces fit: a **local signal layer** (who-touched-what, cross-session) and a **Linear pull layer**
(`ticket fetch`, reusing `project fetch`'s transform).

**Applies to**: `~/.claude/engine/scripts/ticket.sh`, `~/.claude/engine/scripts/linear-lib.sh`,
`~/.claude/engine/scripts/project.sh`; directives `§CMD_DRAIN_TICKET_QUEUE_ON_WAKE`,
`§CMD_INGEST_CONTEXT_BEFORE_WORK`.

---

## Architecture

```
linear-lib.sh        # SHARED: GraphQL seam (_graphql/_load_key/fixture) + per-issue jq transform
  │                  #         (comment tree w/ reactions, lifecycle, attachments) + child-pagination
  ├── project.sh     # `project fetch` — whole-PROJECT delta (adds channels/milestones/summary envelope)
  └── ticket.sh      # `ticket fetch` — a SET of tickets by key (thin envelope); PLUS the local
                     #                  signal layer (subscribe/notify/read/list) + watch/auto-drain
```

The two commands differ ONLY in their query filter (a project vs. an id-set of tickets) and their
envelope. The GraphQL seam, auth, fixture mechanism, and per-issue transform are shared in
`linear-lib.sh` so a field added for one is added for both (`¶INV_SHARED_TRANSFORM_NO_DIVERGE`).
`ticket resolve-comment` (FIN-3533) also reuses `linear-lib.sh`'s `_graphql`.

### Two layers, one `.state.json`

| Layer | What it is | Backed by |
|-------|-----------|-----------|
| **Signal** | Cross-session "ticket X was touched" — `subscribe`/`notify`/`read`/`list` over a local dirty queue. No Linear calls. | `.state.json`: `tickets[]` + `updatedTickets[]` + `ticketCursor` |
| **Pull** | `ticket fetch` — the actual Linear GraphQL pull of ticket content. Stateless. | Linear GraphQL via `linear-lib.sh` |

`.state.json` shape (per session):

```jsonc
tickets:        [ { key, subscribedAt } ]              // subscriptions
updatedTickets: [ { ticket, notifiedAt, from, note } ] // dirty queue (who touched what)
ticketCursor:   "<ISO8601>"                            // ONE shared read watermark W over the set
```

---

## `engine ticket fetch` — the Linear pull

```
engine ticket fetch <KEY...> [--since <ISO8601>] [--out <path>]
```

Pulls a delta of the given tickets from Linear as ONE JSON payload — comment **trees** (with
reactions), normalized **lifecycle** events, and **attachments** per ticket — reusing
`project fetch`'s transform. **Stateless**: `--since` is the caller's; no stored waterline. Omit
`--since` for the **full current thread** (a cold read). The payload is written to a **file**; only
the path is printed (last stdout line) — the payload never rides stdout (see *Truncation* below).
Needs `LINEAR_API_KEY` (env or `.env`).

Payload envelope (thinner than `project fetch` — no channels/milestones):

```jsonc
{ "since": "<W|empty>", "fetchedAt": "<ts>", "keys": ["FIN-1","FIN-2"],
  "tickets": [ { "identifier", "title", "state",
                 "comments":   <tree, each node { emoji-reactions[], author, body, children[] }>,
                 "lifecycle":  [ { type, actor, at, from, to } ],
                 "attachments":[ { id, title, url } ] } ],
  "summary": { "ticketCount", "requested" } }
```

### ⚠️ The Linear `or`-filter gotcha (grouped-by-team filtering)

Linear's `IssueFilter` has **no** `identifier: {in: […]}`, and it **silently ignores** a compound
`{team, number}` object nested inside an `or` — `or:[{team,number},…]` returns the *whole
workspace*, not the requested keys (real instance: **1191** issues for 2 keys). The working shape
is `{ team, or:[{number}…] }`. So `ticket fetch` **groups keys by team → one filter+fetch per
team**:

```jsonc
{ "team": {"key":{"eq":"FIN"}}, "or": [ {"number":{"eq":3473}}, {"number":{"eq":3475}} ],
  "updatedAt": {"gt": "<since>"} }
```

The common single-team case is one query. See `¶PTF_LINEAR_OR_COMPOUND_FILTER` — and note the
**fixture seam cannot validate the filter actually sent to Linear** (offline fixtures ignore the
query string), so any Linear filter must be **live-smoke tested**.

---

## The shared cursor `W` (`.ticketCursor`)

The session tracks ONE shared read watermark `W` over its whole watched set (not a per-ticket
watermark). The session "drains all its tickets together."

| Command | Effect on `W` / queue |
|---------|----------------------|
| `subscribe <KEY>` | adds `{key, subscribedAt}`; seeds `.ticketCursor = now` **iff absent** (baseline for `watch`) |
| `notify <KEY> [note]` | appends `{ticket, notifiedAt, …}` to `updatedTickets` on every *other* subscriber |
| `list [KEY]` | non-destructive view of pending (`notifiedAt > W`). `KEY`/`--since` are **display filters** |
| `read [KEY]` | drains the WHOLE queue + advances `W = now` (preserves entries newer than `now`). `KEY`/`--since` display-only — never a partial drain (would desync the single cursor) |
| `watch` | see below — auto-drains + advances `W` |

**`W` only advances on a drain** (`read` or the auto-drain). Because a fetch that fails must not
leap `W` past unseen comments (`¶INV_WRITE_BEFORE_WATERMARK`).

---

## `watch` — the auto-drain watcher

```
engine ticket watch [KEY] [--timeout N] <session>   # run via Bash run_in_background:true
```

Blocks (via `fswatch` on `.state.json`) until a watched ticket's `notifiedAt > W`, then
**auto-drains**:

```
wake → ticket fetch <matched keys> --since W --out <session>/.ticket-drain/drain-*.json
     → advance W = now, clear the acked queue
     → emit  "ticket update — <keys>\n{ keys, since, payload: <file path> }"
```

- **Payload rides a FILE, path on stdout.** The harness truncates large tool stdout but not a file
  the agent then reads — so the comments go to a file, the tiny stdout carries only its path.
- **Fail-closed.** If the fetch fails (network/auth), `W` is **not** advanced and the queue is
  **not** cleared; it emits `FETCH FAILED (since=…)` and still exits 0 so the agent re-arms and
  retries. (`¶INV_WRITE_BEFORE_WATERMARK`.)
- Self-registers `.state.json:watchTaskId {pid,startedAt,keys}`; a PreToolUse hard gate keeps a
  live background watcher armed whenever `tickets[]` is non-empty.
- Exit codes: `0` update drained · `124` `--timeout` deadline · `2` fswatch missing · `1` nothing
  subscribed.

---

## The two consumer flows

### 1. Wake-drain (`§CMD_DRAIN_TICKET_QUEUE_ON_WAKE`)
A background `watch` re-invokes the agent on wake. The agent reads the wake output's
`{ keys, since, payload }`, opens the **payload file** (already fetched — no per-comment MCP call),
acts on the new activity, and re-arms a fresh `watch`. On `FETCH FAILED`, just re-arm.

### 2. Cold read at context-intake (`§CMD_INGEST_CONTEXT_BEFORE_WORK`)
On session start, the "**Subscribed**" category cold-reads the session's own `.state.json:tickets[]`
via `ticket fetch <keys>` (**no `--since`** = full thread) and folds the payload into context —
the complete state of the tickets you're working, richer than the shallow `SRC_RELATED_TICKETS`
snippet. Pre-selected when non-empty; the user can prune. `W` is already seeded (by `subscribe` at
activation), so subsequent wake-drains ride that baseline (`¶INV_FULL_READ_SEEDS_CURSOR`).

### Newcomer rule (cold-read on subscribe)
When you `subscribe` to a ticket **mid-session** (e.g. `/ticket-search` fold-into-scope,
`/communicate`), pair it with a one-off `ticket fetch <KEY>` (no `--since`) to load its current
thread. That catches the newcomer up immediately so it rides the single shared `W` with the rest —
no per-ticket floor needed.

---

## Testing

| Suite | Covers |
|-------|--------|
| `tests/test-ticket-fetch-sh.sh` | `ticket fetch`: multi-key envelope, `--since`/full-read, reactions (+externalUser actor), payload→file, fail-closed, multi-team grouping |
| `tests/test-ticket-sh.sh` | signal layer + shared cursor + `watch` auto-drain (fixture-backed success + fail-closed) |
| `tests/test-project-sh.sh` | `project fetch` (regression guard for the shared `linear-lib.sh`) |

The GraphQL seam is fixture-injectable via **`LINEAR_FIXTURE`** (colon-separated file list;
`PROJECT_FETCH_FIXTURE` is a back-compat alias). The seam validates the **transform**, never the
**filter** — live-smoke Linear filters separately.

---

## Related
- `scripts/README.md` — the `ticket.sh` / `project.sh` / `linear-lib.sh` one-line reference rows.
- `project fetch` design: the FIN-3473 session. `ticket fetch` + shared-cursor + auto-drain design
  and build: the `2026_07_30_ticket_drain_poller` session (`IMPLEMENTATION.md`).
- Directives: `¶PTF_LINEAR_OR_COMPOUND_FILTER`, `¶INV_SHARED_TRANSFORM_NO_DIVERGE`,
  `¶INV_WRITE_BEFORE_WATERMARK`; commands `§CMD_DRAIN_TICKET_QUEUE_ON_WAKE`,
  `§CMD_INGEST_CONTEXT_BEFORE_WORK`.
