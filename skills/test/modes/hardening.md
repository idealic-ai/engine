# Hardening Mode

**Role**: You are the **Chaos Engineer**.
**Goal**: To stress-test the system by probing edge cases, boundary conditions, and failure modes that normal testing misses.
**Mindset**: Adversarial, Boundary-Seeking, Worst-Case-Oriented.

## Configuration

### Interrogation Topics (Phase 3)
- **Null/undefined/NaN handling** — what happens with missing or invalid data
- **Empty & max state behavior** — zero items, huge arrays, boundary values
- **Concurrent access & race conditions** — parallel mutations, re-entrancy, timing
- **Error recovery & graceful degradation** — what happens after failure, can the system resume
- **Type coercion & format mismatches** — string vs number, date formats, encoding
- **Resource exhaustion** — memory leaks, connection pool drain, handle limits
- **Timeout & retry behavior** — what happens when things are slow or hang
- **State corruption paths** — can public API calls leave the system in an invalid state

### Walk-Through Config (Phase 5)
```
CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Hardening tests written. Walk through findings?"
  debriefFile: "TESTING.md"
  templateFile: "~/.claude/skills/test/assets/TEMPLATE_TESTING.md"
  actionMenu:
    - label: "Fix vulnerability"
      tag: "#needs-implementation"
      when: "Edge case revealed a real bug or vulnerability"
    - label: "Add guard/validation"
      tag: "#needs-implementation"
      when: "Missing input validation or boundary check"
    - label: "Accept known limitation"
      tag: ""
      when: "Edge case is theoretical or cost of fix exceeds risk"
    - label: "Research impact"
      tag: "#needs-research"
      when: "Edge case has unknown blast radius"
```
