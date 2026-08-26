### ¶CMD_SLACK_POST

**Definition**: The ONE canonical path for sending a Slack message. Bundles resolve → compose → confirm → post → verify into a single atom, so a message cannot be composed for a recipient that does not resolve, and cannot go out without a human saying yes.

**Rule**: Any skill or agent about to send Slack routes it through here — never a bare `curl` against `chat.postMessage`, and never a hand-rolled channel or person lookup. `engine slack-post` is the transport; this atom is the discipline around it.

**Prerequisites**:
*   **A bot token** on the shared chain (`$SLACK_INTAKE_TOKEN` / `$SLACK_BOT_TOKEN`, then `./.env.local`, then `./.env`; an explicit `--env-file` replaces the dotfile step entirely). Absent → report the skipped send and stop; do not ask the user to paste a token into chat.
*   **Scopes** for what the send actually needs: `chat:write` to post, `channels:read` to resolve a channel name, `users:read` to resolve a bare name, `users:read.email` to resolve an email, `im:write` to open a DM. A scope change needs an app REINSTALL to take effect.
*   **A destination the user named.** Never infer a recipient from context and send to it.

**Parameters**:
```json
{
  "destination": "either a place (--channel '#name' or a C…/G…/D… id) or a person (--to <name|email|U… id>) — never both",
  "text": "the message body, mrkdwn, plain content (real newlines, no escaped \\n)",
  "layout": "optional — --title <text> for a header, or --blocks <path|-> to supply a Block Kit array verbatim",
  "threading": "optional — --thread-ts <ts> to reply inside a thread, --update-ts <ts> to edit an existing message in place"
}
```

**Algorithm**:
1.  **Resolve the destination BEFORE composing.** Run `engine slack-post --dry-run` with the destination and a placeholder body. An unresolvable recipient must fail while nothing has been written, so the failure costs a flag and not a draft.
    *   **A person** goes to `--to`, which resolves strictest-first: a `U…` id is taken as given, anything containing `@` goes to `users.lookupByEmail`, and a bare name is matched case-insensitively as a SUBSTRING of display name, real name and email local-part across the workspace directory.
    *   **More than one match** prints the candidates, posts nothing, and exits non-zero. Re-invoke with the `U…` id from the printed row — it resolves to exactly one person. Do NOT guess which candidate was meant, and do NOT narrow the query and re-run hoping for one hit; hand the candidate list to the user when the id is not obvious from what they asked for.
    *   **Zero matches** and **a missing scope** are different failures and print differently. Report which one happened: "nobody by that name" sends the user to the spelling, "the token cannot look" sends them to the app's scopes.
2.  **Compose.** Write the body for someone who has not read the thread and cannot ask a follow-up: what this is, what it is about, and what they should do. Slack is a poor place to be terse — the reader has no session context. `--text` longer than a section's 3000-character cap is split across successive sections automatically; a caller-supplied `--blocks` layout is never re-chunked, so keep every section in it under the cap yourself.
3.  **Confirm.** Show the user the resolved destination and the exact body, and wait for an explicit yes. **A Slack post is not undoable** — an edit leaves the notification already delivered, and a delete leaves the recipient having read it. Confirm even when the destination came from config.
4.  **Post.** Run `engine slack-post` with the confirmed body. Capture the message `ts` it prints on stdout — a later `--update-ts <ts>` edits that same message in place, and a `--thread-ts <ts>` on the same value replies under it. An uncaptured `ts` makes the message permanently unreachable.
5.  **Verify.** Exit 0 means Slack accepted the request, not that anyone saw it. When the message asks for something, read the thread back (`engine slack-read --thread-ts <ts>`) rather than assuming the ask landed. When the setup itself is in question, `engine slack-post --verify --channel '#name'` walks token → validity → scopes → channel → bot membership and self-joins where it can; `--dry-run` contacts Slack only for the person lookup and proves nothing about posting.

**Constraints**:
*   **Prefer a channel over a DM.** A DM is invisible to everyone else and cannot be picked up by whoever is actually free. Use `--to` when the content is genuinely for one person — a nudge, something private, a direct reply. Everything else goes to a channel.
*   **An ambiguous query never reaches a human's DM.** Ambiguity is resolved by the caller re-invoking with an id, never by the script picking a candidate. There is no TTY inside `slack-post` to ask on.
*   **`--channel` is a place and `--to` is a person.** Passing both is refused. A `U…` id handed to `--channel` is redirected to `--to` rather than posted.
*   **An absent wrapper is not an absent capability.** Before reporting that Slack cannot do something, try it — a "channel not found" for a user id, or a lookup that was never attempted, reads as a platform restriction and is not one. When a scope really is missing, name the scope so it is fixable.
*   **The token is never printed.** It travels in the Authorization header only, and never appears in `--dry-run` output, in logs, or in chat.
*   **Never invent a mention.** An unresolved `@name` renders as plain text and notifies nobody; an invented one manufactures an obligation for someone who does not exist. No known Slack id → plain name, no mention.

---

## PROOF FOR §CMD_SLACK_POST

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "destination": {
      "type": "string",
      "description": "What was asked for and what it resolved to (e.g. \"--to leo → U0BRSTG0RB7 → D…\", or \"#intake-alerts → C…\")"
    },
    "confirmed": {
      "type": "string",
      "description": "How the user approved this specific body and destination, or 'not sent — <reason>'"
    },
    "posted": {
      "type": "string",
      "description": "The message ts if it landed, or 'skipped — <reason>' (no token, ambiguous target, missing scope)"
    },
    "verified": {
      "type": "string",
      "description": "What was checked after the post (thread read back, --verify ladder), or 'accepted by Slack only'"
    }
  },
  "required": ["destination", "confirmed", "posted", "verified"],
  "additionalProperties": false
}
```
