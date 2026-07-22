### ¶CMD_LOG_SKILL_INVOCATION
**Definition**: Before a sub-agentic skill hands control to its subagent, the orchestrator writes ONE curated session-log entry recording WHY the skill/subagent was invoked and WHAT inputs are being fed — so a crashed or restarted session can re-tread the dispatch. Agent-authored, not a raw-prompt dump: high-signal, not bloat.

**Trigger**: Fired as the step **immediately before the `Task`/`Agent` dispatch** in any sub-agent-dispatching skill (`/build`, `/council`, `/probe`, `/scrutinize`, `/experiment`, `/summarize`, `/snapshot`, `/ticket`, `/pr`, `/report`). Fire it once per dispatch — right before control leaves for the subagent, when the context pack path is already known.

**Why**: A sub-agentic dispatch is where a session can lose the most on a crash — the subagent's context pack + the intent behind it live only in the orchestrator's working memory and the tool-call payload. If Claude dies mid-dispatch, an un-logged invocation is unrecoverable: the reactivated session can't tell what it was running or with what inputs. This entry is the recovery breadcrumb — intent + pack pointer + how to re-dispatch — placed at the last moment before the handoff so it reflects what actually went to the subagent.

**Algorithm**:
1.  **Assemble** the dispatch as the skill normally does — context pack, target, foreground/background — up to the moment before the `Task`/`Agent` call.
2.  **Write** ONE log entry via `§CMD_APPEND_LOG` using `§FMT_SKILL_DISPATCH` below. Curated, ~5 lines. Do NOT paste the full subagent prompt — **point to** the on-disk context pack (skills that write one, e.g. `/build`'s `CONTEXT_PACK.md`) or summarize inline inputs in 1–2 lines. (`¶INV_INVOCATION_LOG_IS_CURATED`.)
3.  **Dispatch** the subagent.

**§FMT_SKILL_DISPATCH** (the entry shape):
```
## 🚀 Skill dispatch — /<skill> [<mode/scope>]
*   **Why**: <intent in your own words — what this dispatch is for, the question it answers>
*   **Inputs**: <context-pack path> (+ key input docs/paths); or a 1–2 line summary if the input is inline
*   **Dispatch**: <foreground | background> → expects <return artifact path, e.g. builds/<slug>_BUILD.md>
*   **Re-tread**: <one line — how to re-dispatch this if the session restarts>
```

**Constraints**:
*   **`¶INV_INVOCATION_LOG_IS_CURATED`**: Agent-authored why + pointers. NEVER paste the raw subagent prompt / full context pack into the log — that is the bloat this command exists to avoid. The pack lives on disk (referenced by path); the log holds the *reasoning* and the *pointer*.
*   **Once per dispatch**: A parallel fan-out (N subagents) writes one entry per subagent, or one grouped entry listing each — fired before the batch launches.
*   **Right before dispatch**: Fire after the pack is assembled, immediately before the `Task`/`Agent` call — the true recovery point (not step-0, where the pack doesn't exist yet).
*   **Sub-agentic skills only**: Inline skills (`/do`) don't dispatch a subagent, so they don't need it. A skill cites this command at its dispatch site; it does not restate the format.

---

## PROOF FOR §CMD_LOG_SKILL_INVOCATION

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "invocationLogged": {
      "type": "string",
      "description": "What dispatch was logged before subagent handoff (e.g., 'logged /build chunk-3 dispatch + pack pointer')"
    }
  },
  "required": ["invocationLogged"],
  "additionalProperties": false
}
```
