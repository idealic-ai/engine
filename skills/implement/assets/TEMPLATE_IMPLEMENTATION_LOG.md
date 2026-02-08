# Implementation Log Schemas (The Flight Recorder)
**Usage**: Capture the *exact* state of the build. Do not summarize; record the struggle.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `log.sh`.

## ▶️ Task Start
*   **Item**: `[Step N from Plan]`
*   **Goal**: "Implement the `User` interface."
*   **Strategy**: "Create `types/User.ts` first, then add validation schema."
*   **Files**: `src/types.ts`, `src/utils/validation.ts`
*   **Dependencies**: "Depends on `AuthService` being ready."

## 🚧 Block / Friction
*   **Obstacle**: "TypeScript Error 2322 in `StreamController.ts`."
*   **Context**: "The `AudioContext` type is missing `createWorklet` in the test environment."
*   **Attempt**: "Trying to mock `window.AudioContext` manually."
*   **Hypothesis**: "The global `window` object is not being polyfilled by JSDOM correctly."
*   **Severity**: [Blocking / Annoyance]

## 😨 Stuck / Confusion (The "OMG" Moment)
*   **Symptom**: "The data is just... vanishing. `console.log` shows it enters the function but never leaves."
*   **Mental State**: "I suspect a silent failure in a Promise or a swallowed error."
*   **Trace**: "Function A -> Async B -> [BLACK HOLE] -> Function C"
*   **Next Move**: "Going to wrap the entire block in a `try/catch` with `console.error`."
*   **Time Spent**: "30 mins spinning on this."

## 🐞 Debugging Trace
*   **Symptom**: "Test `should_play` failing with timeout."
*   **Hypothesis**: "The worker is not receiving the `init` message in time."
*   **Probe**: "Adding `console.log` to the message port handler."
*   **Observation**: "The logs show the message IS received, but the handler returns early."
*   **Refinement**: "The state check `if (!ready) return` is triggering incorrectly."

## 💸 Tech Debt (The Shortcut)
*   **Item**: "Hardcoded `sampleRate` to 44100."
*   **Why**: "Getting the dynamic context sample rate requires an async fetch that breaks the constructor."
*   **Risk**: "Will fail on 48kHz hardware."
*   **Payoff Plan**: "Ticket #123: Refactor to Factory Pattern."
*   **Commitment**: "Added `// TODO: TECH DEBT` comment in code."

## 👁️ Observation (Side Channel)
*   **Focus**: `[File/Concept]`
*   **Detail**: "I noticed `utils.ts` is getting huge (500+ lines)."
*   **Implication**: "We should split this into `math.ts` and `string.ts` soon."
*   **Action**: "Logged in Parking Lot."
*   **Relevance**: [High/Low]

## 😟 Concern (The Worry)
*   **Topic**: "Memory Usage"
*   **Detail**: "We are creating a new `Float32Array` every frame."
*   **Gut Check**: "This feels like a GC trap."
*   **Validation**: "Will profile this after the feature works."
*   **Status**: [Tracking]

## 🔙 Revert / Rollback
*   **Reason**: "The mock strategy failed. The library requires a real browser environment."
*   **Action**: "Reverting commit `abc123` (The manual mock)."
*   **New Strategy**: "Switching to integration tests for this module."
*   **Lost Work**: "~1 hour of coding."

## ✅ Success / Commit
*   **Item**: `[Step N]`
*   **Changes**: "Created `src/types.ts`, Updated `App.tsx`."
*   **Verification**: "Unit tests passed. Manual check of UI rendering confirmed."
*   **Artifacts**: "New File: `User.ts`"
*   **Next**: "Proceeding to Step N+1."
