### ¶CMD_OFFER_GRAPH_VIZ
**Definition**: Offers a `/graph` flowgraph visualization of the algorithm / structure / steps a skill just produced — a plan's step-dependencies, an analyzed control flow, a design's decision tree, a chapter dependency graph. The composable command any artifact-producing skill declares to compose `/graph` in. It **OFFERS, never forces** (`¶INV_OFFER_DONT_FORCE_SKILLS`), and is **context-gated**: it stays silent when the artifact is linear (nothing a flowgraph would clarify).
**Concept**: "What you just produced has real structure — want to see it as a flowgraph?"
**Trigger**: Declared as a step in a caller's plan-review / synthesis phase (see **Callers**). The caller names the artifact; this command assesses graph-worthiness, offers, and (on accept) invokes `/graph` inline.

---

## The caller contract
The caller declares this step and names, in its surrounding prose, the **artifact** and the **graph-worthy aspect** to visualize (the plan's step-dependency graph, the analyzed control flow, the brainstorm's decision tree, the chapter dependency graph, the bug's failure-path). One command, N callers, zero cross-reference.

## Difference from `§CMD_OFFER_COUNCIL_REVIEW`
Same offer-don't-force family, but **simpler**: `/graph` is suggest-tier, sessionless, and **inline** (it renders ASCII in-chat in seconds). So there is **no background task, no bounded wait, no `report_path`** — offer → on accept, invoke `/graph` right there → the diagram renders inline.

---

## Algorithm

### Step 1: Assess graph-worthiness (the context gate)
Look at the artifact. Does it have **branching, decisions, loops, or a dependency structure** — a plan with `Depends`/`Files`, an algorithm with conditionals, a state/lifecycle, a decision tree, chapters with sequencing, a bug with multiple failure paths?
- **No — it's linear / a flat list / a trivial change**: record `graphOffered: "no — linear"`, `decision: "skipped"`, and **RETURN silently. Do NOT offer.** A flowgraph of a `1 → 2 → 3` sequence is noise (this is `/graph`'s own "when NOT to use" — a numbered list is clearer). The silent auto-skip is the "contextual" behavior: a flat artifact never nags.
- **Yes**: proceed to Step 2.

### Step 2: Offer (interactive)
Present via `AskUserQuestion`, naming the concrete structure worth drawing:
> "The `<artifact>` has real structure (`<e.g. 5 plan steps with cross-dependencies / a 3-way decision tree / the failure-path of the bug>`). Render it as a flowgraph (`/graph`)?"
> - **"Graph it"** — render the flowgraph now.
> - **"No thanks"** — skip; continue the caller's flow.

- **No thanks** → `decision: "declined"`. Return.
- **Graph it** → Step 3.

### Step 3: Invoke `/graph` inline
Invoke `Skill(graph, "<the graph-worthy aspect> of <artifact>")` — pass the specific thing to visualize. `/graph` assesses → renders the ASCII flowgraph → presents it in-chat immediately (no session, no wait).

### Step 4: Offer to persist (optional)
Offer to embed the rendered flowgraph into the artifact document (the plan / report / brainstorm / vision) inside a code fence, so it survives the session. Record `decision: "rendered"`.

---

## Constraints
- **Offer, never force** (`¶INV_OFFER_DONT_FORCE_SKILLS`): `graphOffered`/`decision` record the offer + choice; nothing gates the caller on a graph being drawn.
- **Context-gated — silent on linear artifacts**: the Step-1 assessment gates the offer. A flat/linear artifact is auto-skipped with `decision: "skipped"`, no `AskUserQuestion`. This keeps the offer from nagging where a flowgraph adds nothing.
- **Inline, not background**: `/graph` renders in-chat; there is no `report_path` or bounded wait (unlike `§CMD_OFFER_COUNCIL_REVIEW`).
- **The caller names the artifact + aspect**: this command assesses, offers, and invokes; it does not decide *what* the artifact is.
- **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: the offer is `AskUserQuestion`, never bare text.

---

## Callers
Declared as a plan-review / synthesis step in these skills (the artifact + aspect each supplies):
- **`/analyze`** — synthesis/close (`the analyzed algorithm / control flow / structure`).
- **`/brainstorm`** — synthesis/close (`the decision tree / option structure of the design`).
- **`/implement`** — Phase 2 plan review (`the plan's step-dependency graph` — from the `Depends`/`Files` fields).
- **`/direct`** — synthesis (`the chapter dependency graph` — sequential/parallel chapters).
- **`/fix`** — synthesis/close (`the failure-path / control-flow of the bug`).

---

## PROOF FOR §CMD_OFFER_GRAPH_VIZ

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "graphOffered": {
      "type": "string",
      "description": "Whether the graph offer was presented (e.g., 'yes — offered on plan step-deps', or 'no — linear, auto-skipped')"
    },
    "decision": {
      "type": "string",
      "enum": ["rendered", "declined", "skipped"],
      "description": "rendered (graph drawn inline), declined (user said no), or skipped (auto-skipped — artifact was linear/trivial)"
    }
  },
  "required": ["graphOffered", "decision"],
  "additionalProperties": false
}
```
