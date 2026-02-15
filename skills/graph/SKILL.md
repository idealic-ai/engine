---
name: graph
description: "Creates ASCII flowgraph diagrams using the `§CMD_FLOWGRAPH` notation. Lightweight skill for rendering complex flows as structured visual diagrams. Triggers: \"draw a flowgraph\", \"create a flow diagram\", \"visualize this flow\", \"graph this process\"."
version: 3.0
tier: suggest
---

Creates ASCII flowgraph diagrams. Lightweight skill for rendering complex flows as structured visual diagrams.

# Flowgraph Rendering Protocol

## Protocol

### 1. Assess
- Identify the flow to visualize (protocol, architecture, lifecycle, decision tree).
- Confirm the flow has branching, decisions, or loops (simple linear sequences don't need flowgraphs — use a numbered list).

### 2. Render
- Draft the flowgraph using the Glyph Vocabulary and Composition Rules below.
- Use 2-space indentation per nesting level.
- Include textual labels at all junctions and loop-backs.
- Wrap in markdown code fences for whitespace preservation.

### 3. Present
- Output the flowgraph to the user or write it to the target document.
- Ask if revisions are needed.

## Notes
- This is a suggest-tier skill — no session activation, no log, no debrief.
- For complex multi-diagram projects, consider using `/implement` instead.

---

## ¶CMD_FLOWGRAPH
**Definition**: Render an ASCII flowgraph using the standardized glyph vocabulary. Flowgraphs are hand-crafted by agents to visualize complex flows — protocols, architecture, tag lifecycles, decision trees — in plain-text Markdown.

**When to Consider** (suggestions, not mandatory):
*   Implementation plans with branching logic or decision gates
*   Architecture documentation showing data flows with conditional routing
*   Bug analysis where the flow has multiple failure paths
*   Tag lifecycle diagrams with state transitions
*   Skill protocol overviews (phase flows with optional sub-phases)

**When NOT to Use**: Simple linear sequences (1 → 2 → 3). If the flow has no branches, decisions, or loops, a numbered list is clearer.

**Algorithm**:
1.  **Assess**: Does the flow have branching, decisions, or loops? If yes, a flowgraph adds value. If no, use prose.
2.  **Draft**: Construct the flowgraph using the Glyph Vocabulary below.
3.  **Rules**: Follow the Composition Rules (especially 2-space indentation).
4.  **Embed**: Place the flowgraph in the target document inside a markdown code fence (` ```  ``` `) or as raw text. Code fences preserve spacing reliably.

**Constraint**: Flowgraphs are the canonical representation — no dual JSON/YAML format. Agents parse them directly.

---

### Glyph Vocabulary

| Glyph | Name | Meaning | Usage |
|-------|------|---------|-------|
| `→` | Arrow | Horizontal flow / terminal transition | `START → Label`, `END → Label` |
| `↓` | Down | Vertical flow (next step) | Between major blocks |
| `│` | Pipe | Continuation line (vertical spine) | Sequential flow within a block |
| `├►` | Branch | Fork to a sub-step (non-terminal) | Non-last item in a branch group |
| `╰►` | Last Branch | Fork to a sub-step (terminal) | Last item in a branch group |
| `╭───╯` | Rejoin | Convergence point — branches merge here, or loop-back to earlier block | For convergence: placed after branches merge. For loop-back: **must** include textual label (e.g., `╰► Loop back to BLOCK`). Width varies: `╭──╯`, `╭────╯`, `╭───────────╯` |
| `◆` | Diamond | Decision point | Question or conditional check |
| `║` | Double Pipe | Decision continuation line | Conditional flow within a decision block |
| `╠⇒` | Decision Branch | Conditional branch (non-terminal) | Non-last branch of a decision diamond |
| `╚⇒` | Decision Last | Conditional branch (terminal/else) | Last/default branch of a decision |
| `•` | Bullet | Annotation within a step | Detail items inside a process block |
| `⟨text⟩` | Angle Bracket | Behavioral annotation | `⟨streaming⟩`, `⟨callback⟩`, `⟨async⟩` |
| `LABEL` | Block Header | Named process block (ALL CAPS) | `INPUT PROCESSING`, `TASK EXECUTION` |

**Glyph Sets** (visual disambiguation):
*   **Single-line** (`│ ├ ╰`): Sequential flow and branches. "This is a step."
*   **Double-line** (`║ ╠ ╚`): Decision/conditional flow. "This is a choice."

---

### Composition Rules

1.  **Indentation**: 2-space indent per nesting level. Consistent across the entire graph.
2.  **Block Headers**: ALL CAPS, standalone on their own line. Represent named process blocks.
3.  **Rejoin Glyphs** (`╭───╯`): Two uses — **convergence** (branches merge forward to the next block) and **loop-back** (rejoin an earlier block). Convergence rejoins do not require a label — the `↓` after them makes the forward flow clear. Loop-back rejoins MUST include a textual label (e.g., `╰► Loop back to TASK EXECUTION`). Width varies to match indentation: `╭──╯`, `╭────╯`, `╭───────────╯`.
4.  **Decision Diamonds**: Always followed by `║` continuation, then `╠⇒` / `╚⇒` branches. Each branch gets a label (e.g., `YES →`, `ERROR →`).
5.  **Terminal Nodes**: `START →` and `END →` mark entry/exit points.
6.  **Annotations**: Use `•` bullets for detail within a step. Use `⟨text⟩` for behavioral markers (streaming, async, callback).
7.  **Code Fences**: Wrap flowgraphs in markdown code fences to preserve whitespace.

---

### Pattern Library

**Pattern 1 — Linear Sequence**
```
START → User Request
  ↓
STEP ONE
  │ • Detail about step one
  │ • Another detail
  ↓
STEP TWO
  │ • Detail about step two
  ↓
END → Result
```

**Pattern 2 — Branch Group**
```
PROCESSING
  │
  ├► SUB-STEP A
  │   │ • First thing
  │   │ • Second thing
  │   ↓
  ├► SUB-STEP B
  │   │ • Another path
  │   ↓
  ╰► SUB-STEP C (final)
      │ • Last branch
```

**Pattern 3 — Decision Diamond**
```
  ◆ Is the input valid?
  ║
  ╠⇒ YES → Continue processing
  ║       │ • Validate schema
  ║       │ • Transform data
  ║
  ╚⇒ NO → Return error
          │ • Log failure reason
          │ • Send error response
```

**Pattern 4 — Loop-Back**
```
TASK EXECUTION
  │ • Process current item
  │ • Update state
  ╭───╯
  ↓
CONTINUATION CHECK
  │
  ◆ More items?
  ║
  ╠⇒ YES → Continue
  ║       ╰► Loop back to TASK EXECUTION
  ║
  ╚⇒ NO → Proceed to OUTPUT
```

**Pattern 5 — Nested Blocks**
```
OUTER PROCESS
  │
  ├► INNER BLOCK A
  │   │
  │   ├► Detail 1
  │   │   │ • Sub-detail
  │   │   ↓
  │   ╰► Detail 2
  │       │ • Sub-detail
  │   ╭───╯
  │   ↓
  ╰► INNER BLOCK B
      │
      ◆ Decision inside nest?
      ║
      ╠⇒ YES → Handle it
      ║
      ╚⇒ NO → Skip
```

**Pattern 6 — Decision Convergence (branches merge forward)**
```
PROCESSING
  │
  ◆ Which path?
  ║
  ╠⇒ PATH A → Handle case A
  ║         │ • Do A-specific work
  ║         │ • Produce A result
  ║    ╭────╯
  ║    ↓
  ╚⇒ PATH B → Handle case B
            │ • Do B-specific work
            │ • Produce B result
  ╭─────────╯
  ↓
MERGED CONTINUATION
  │ • Both paths arrive here
  │ • Process combined result
  ↓
END → Done
```

*Key*: The `╭────╯` glyph after each branch signals "this branch feeds forward." The `↓` immediately after it shows the flow continuing downward. The next block after the last branch's `╭─────────╯` receives flow from ALL branches. Width of `╭───╯` varies to match indentation depth.

**Pattern 7 — Multi-Branch Convergence with Nested Decisions**
```
DISPATCH
  │
  ◆ Result type?
  ║
  ╠⇒ ERROR → Error handling
  ║         │ • Log error
  ║         │ • Execute fallback
  ║    ╭────╯
  ║    ↓
  ╚⇒ SUCCESS → Update state
              │ • Store result
  ╭───────────╯
  ↓
CONTINUATION CHECK
  │
  ◆ More items?
  ║
  ╠⇒ YES → Continue
  ║       ╰► Loop back to DISPATCH
  ║
  ╚⇒ NO → All done
  ╭──────╯
  ↓
END → Complete
```

*Key*: Convergence (`╭───╯`) and loop-back (`╰► Loop back to`) can coexist in the same graph. Convergence merges branches forward; loop-back returns to an earlier block.
