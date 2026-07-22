---
name: communicate
description: "Drive a ticket discussion turn — subscribe, ask/reply on a Linear ticket via MCP, notify local sibling agents, and keep a background watcher armed so replies wake you. Triggers: \"ask on the ticket\", \"reply on FIN-1234\", \"discuss this in the ticket\", \"communicate with the other agent\", \"post a question to the ticket and wait\"."
version: 1.0
tier: lightweight
---

Drive one full ticket-discussion turn over a Linear ticket's comment thread, then keep watching it.

# Communicate Protocol (The Ticket Conversation)

[!!!] This is a **sessionless utility** skill. No session directory, no logging, no debrief. It operates *within the current active session* — it reads and writes that session's `tickets[]` / `watchTaskId` in `.state.json`. If there is no active session, tell the user to run inside a ticketed session (or `engine session activate` one) and stop.

[!!!] Linear MCP is **agent-turn-only**. Every Linear read/write below is an MCP tool call *you* make in your turn — never from a script. The engine's `engine ticket …` verbs only track dirty-flags + watermarks locally; comment content always lives in Linear.

---

## 0. Setup

1.  **Resolve the target ticket KEY**: from the `/communicate` arguments (`/communicate FIN-1234 "message"`), else from the current session's `tickets[]` (if exactly one, use it; if several, `AskUserQuestion` which). Normalize to the `FIN-1234` form.

2.  **Confirm an active session exists**: the loop below reads/writes the current session's state. If `engine ticket subscribe` reports no active session, stop and ask the user to run inside a ticketed session.

3.  **Detect Linear MCP availability**: if the `mcp__linear-server__*` tools are not present (headless / cron runs), you cannot post or fetch comments. Do the local half (subscribe + notify + watch) and tell the user clearly that the Linear post/fetch was skipped because MCP is unavailable. Never hang waiting on a missing tool.

---

## 1. Post a turn (ask or reply)

Whether this turn is an *ask* (new question) or a *reply* (responding to an unread comment) is just thread context — the mechanics are identical: you post a comment.

Steps 1–4 below (subscribe-check → resolve → post → notify) **are `§CMD_POST_TICKET_COMMENT`** — the canonical ticket-comment atom (`~/.claude/engine/.directives/commands/CMD_POST_TICKET_COMMENT.md`, `¶INV_TICKET_COMMENT_VIA_CMD`). That atom is the **single source of truth** for the subscribe+post+notify sequence; this skill is one caller of it (it adds the watcher in step 5). Run the atom's three steps here, then continue to the watcher:

1.  **Subscribe-check** (idempotent, atom step 1): `engine ticket subscribe <KEY>`. This joins the current session's `tickets[]` so sibling agents' notifies reach you.

2.  **Resolve KEY → Linear issue id** (part of atom step 2): `mcp__linear-server__get_issue` with the `FIN-1234` key (or search if needed). Keep the returned issue id for the comment call.

3.  **Post the comment** (atom step 2): via `mcp__linear-server__save_comment` (the create/update comment tool — pass `issueId` + `body`) on that issue: your question or reply, in Markdown, plain content (no escaped `\n` — real newlines).

4.  **Notify local siblings** (atom step 3): `engine ticket notify <KEY> "<decision-grade note>" --from <this-session>`. This flags every *other* local session subscribed to `<KEY>` (never yourself) so their watcher wakes. **Make the note decision-grade** — a reader drains only this hint (not the Linear body) on wake, so write it so they can answer *"do I need to act?"* without opening Linear. Include, when they apply: the **commit SHA(s)** if a commit landed, the **one-phrase what-changed**, and an **affects-you verdict** (`no action` / `rebase onto <sha>` / `your files X untouched` / `needs your reply`). One line, terse. The full content still lives in the Linear comment for anyone who needs detail — but a good note means they usually won't. Example: `engine ticket notify FIN-2833 "2db0ecea6: entities/ scaffold committed byte-equal; scope.ts aliases left for FIN-2737 — no action for you"`.

5.  **Arm / keep the background watcher** — this is what lets a sibling's reply wake you:
    *   Check armed state: read the current session's `.state.json:watchTaskId`; it is armed only if `watchTaskId.pid` is present AND `kill -0 <pid>` succeeds (a hard-killed watcher leaves a stale field). The auto-watch hard gate also enforces this, so arming is your natural first move anyway.
    *   If not armed, spawn it with `Bash` and `run_in_background: true`:
        ```bash
        engine ticket watch
        ```
        (Add the `<KEY>` to narrow to one ticket; omit to watch all your subscriptions.) **No `--timeout` by default — it blocks until a *real* update**, so a long-idle discussion never fake-wakes you (no re-invocation, no wasted tokens) and `watchTaskId` stays live so the gate never churns. Pass `--timeout N` only if you deliberately want a bounded watch (exits 124 on the deadline). The watcher self-registers its pid into `watchTaskId` on start and clears it on graceful exit. The harness re-invokes you when it exits.
    *   **Name the background command as a wake-instruction.** The harness re-invokes you with `Background command "<description>" completed (exit code N)` — that completion line IS your wake signal, so make the `Bash` tool's `description` an imperative that tells you what to do, not a label. Use something like **`Ticket watcher fired — drain with 'engine ticket read', then fetch the new comments via Linear MCP`**. A bare label like "Re-arm ticket watcher" leaves you staring at an opaque `exit code 0` and guessing; a self-instructing description means the wake message itself carries the next step. (Still branch on the exit code per §2 — exit 0 is the drain-and-read case.)

---

## 2. On wake (the watcher exited)

When the background `engine ticket watch` exits, the harness re-invokes you. Branch on its exit:

*   **Exit 0** — a watched ticket changed (stdout is the matched key(s)):
    1.  `engine ticket read` (add `--json`) — drains the local dirty queue and returns each ticket with a `since` datetime (the prior watermark) and advances it.
    2.  Fetch the new comments from Linear via `mcp__linear-server__list_comments` on the issue, filtered to `>= since`. (`read` gives you the note/hint only; Linear holds the actual text.)
    3.  Compose your reply and post it — loop back to **§1** (post → notify → re-arm). Each turn re-arms the watcher, so the back-and-forth is self-sustaining.

*   **Exit 124** — bounded timeout reached (only happens if you passed `--timeout N`; the default is unbounded and never exits this way). Re-arm (`§1` step 5) to keep listening, or stop if the discussion is done — ask the user if unsure.

*   **Exit 2** — `fswatch` not installed (`brew install fswatch`). You can still post/notify; you just won't get local wake signals until it's installed.

*   **Exit 1** — nothing subscribed to watch. Subscribe first (`§1` step 1).

---

## Known limitation — local-signal only

The wake signal is **local**: `engine ticket watch` only fires on another *local* agent's `engine ticket notify`. A human (or any actor) commenting **directly in Linear** does NOT call `notify`, so your local watcher will not wake for it — you'd only see that comment on your next manual `list_comments` fetch. This is an accepted limitation of v1. A future Linear-poll (Option B) would close the gap by polling `list_comments` on an interval and firing `notify` itself; it is intentionally not built yet. Do not add a poll as part of this skill.

## Degrade cleanly

*   **No active session** → stop; ask the user to run inside a ticketed session.
*   **No Linear MCP** (headless) → do the local half (subscribe/notify/watch), report the skipped post/fetch, never hang.
*   **No `fswatch`** → post/notify still work; local wake is unavailable until installed.
