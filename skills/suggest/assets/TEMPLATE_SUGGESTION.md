# Suggestion Report Template
**Tags**: #needs-review

## Overview
**Context**: Derived from the context loaded during [Previous Task].
**Goal**: To capture "collateral insights"—improvements, risks, and cleanups spotted while working on something else.

**Filename Convention**: `sessions/[YYYY_MM_DD]_[TOPIC]/SUGGESTIONS.md`.

---

## 1. Context Summary
*   **Source Context**: What files/topics were we looking at?
*   **Trigger**: Why did we run this suggestion session?

---

## 2. The "Context Squeeze" Findings

### A. Documentation vs. Reality
*Where do the docs lie?*
*   [ ] **Inaccuracy**: "The doc `AUDIO.md` says X, but code `Stream.ts` does Y."
*   [ ] **Missing**: "We have no documentation for the new `ShiftLogic`."

### B. Code Hygiene & Rot
*What smells?*
*   [ ] **Dead Code**: "The `LegacyParser` class seems unused."
*   [ ] **Messy Comments**: "`// TODO: Fix this` on line 42 of `Engine.ts` is 2 years old."
*   [ ] **Dangling Logic**: "We check `if (x)` but `x` is always true."

### C. Test Gaps
*Where are we flying blind?*
*   [ ] **Missing Case**: "We test `play()`, but not `play()` -> `pause()` -> `play()`."
*   [ ] **Brittle Mock**: "The `AudioContext` mock doesn't simulate clock drift."

### D. Architectural Inconsistencies
*Where are we breaking our own rules?*
*   [ ] **Pattern Violation**: "We use `Singleton` here but `Dependency Injection` there."
*   [ ] **Leaky Abstraction**: "The `View` knows too much about the `AudioNode`."

---

## 3. The "20 Questions" Scan
*Highlights from the interrogation.*

*   **Question**: "Is there a variable name that confused you?"
    *   **Answer**: "Yes, `buffer` usually means `AudioBuffer`, but here it means `Queue`."
*   **Question**: ...

---

## 4. Action Plan (Next Steps)
*Turn these into tickets.*

### Immediate Cleanups (Low Risk)
*   [ ] Rename `x` to `y`.
*   [ ] Delete unused file `Z.ts`.

### Strategic Refactors (High Value)
*   [ ] **Prompt**: "Let's run a Refactor Session on `StreamLoader`."
*   [ ] **Reason**: "It's becoming a God Class."

---

## 5. Context Map (The "Read This" List)
*The critical files to load if we start a new session on these suggestions.*

*   **Core Logic**: `src/lib/audio/StreamController.ts`
*   **Documentation**: `docs/domains/STREAMING_DATA/AUDIO_STREAMING.md`
*   **Tests**: `src/lib/audio/__tests__/Stream.test.ts`
