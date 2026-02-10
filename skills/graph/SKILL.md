---
name: graph
description: "Creates ASCII flowgraph diagrams using the §CMD_FLOWGRAPH notation. Lightweight skill for rendering complex flows as structured visual diagrams. Triggers: \"draw a flowgraph\", \"create a flow diagram\", \"visualize this flow\", \"graph this process\"."
version: 1.0
tier: suggest
---

Creates ASCII flowgraph diagrams using the `§CMD_FLOWGRAPH` notation.

# Flowgraph Rendering Protocol

## Prerequisites
- Load `~/.claude/.directives/COMMANDS.md` — specifically `§CMD_FLOWGRAPH` (Section 5) for the glyph vocabulary and composition rules.

## Protocol

### 1. Assess
- Identify the flow to visualize (protocol, architecture, lifecycle, decision tree).
- Confirm the flow has branching, decisions, or loops (simple linear sequences don't need flowgraphs).

### 2. Render
- Draft the flowgraph using `§CMD_FLOWGRAPH` glyph vocabulary and composition rules.
- Use 2-space indentation per nesting level.
- Include textual labels at all junctions and loop-backs.
- Wrap in markdown code fences for whitespace preservation.

### 3. Present
- Output the flowgraph to the user or write it to the target document.
- Ask if revisions are needed.

## Notes
- This is a suggest-tier skill — no session activation, no log, no debrief.
- For complex multi-diagram projects, consider using `/implement` instead.
- The glyph vocabulary and composition rules live in `§CMD_FLOWGRAPH` (COMMANDS.md §5).
