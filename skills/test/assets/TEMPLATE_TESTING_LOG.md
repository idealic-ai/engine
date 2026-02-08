# Testing Log Schemas (The QA Stream)
**Usage**: Choose the best schema for your finding. Combine them freely. The goal is to capture the testing process, not just the results.

## 🐞 Debugging (Investigation)
*   **Symptom**: "Audio glitches when seeking."
*   **Hypothesis**: "The buffer isn't being cleared on seek."
*   **Action**: "Adding logging to `flush()` method."
*   **Outcome**: "Confirmed. Buffer retains 0.5s of stale audio."

## ✅ Success (Pass)
*   **Test**: `TC-04: AudioGraph.disconnect()`
*   **Status**: [Passed]
*   **Verification**: "Nodes are correctly removed from the WebAudio graph."

## 🚧 Stuck (Blocker)
*   **Barrier**: "Cannot mock `AudioWorkletNode` in Jest environment."
*   **Effort**: "Tried `jest-web-audio-mock`, but it doesn't support custom processors."
*   **Plan**: "Will stub the interface manually for this test suite."

## 🧪 New Edge Case (Boundary)
*   **Discovery**: "What if the user loads a 0-byte file?"
*   **Impact**: "Decoder crashes with 'Buffer too small'."
*   **Action**: "Added `TC-Edge-01` to handle empty file gracefully."

## 🎭 New Scenario (User Story)
*   **Story**: "User drags a clip while another is playing."
*   **Context**: "This creates a 'simultaneous playback' state we haven't tested heavily."
*   **Goal**: "Ensure no volume spikes occur during the overlap."

## 💡 Idea for Test (Future Coverage)
*   **Trigger**: "The `VolumeFader` logic is complex."
*   **Idea**: "We should property-test this with 1000 random float values."
*   **Value**: "High probability of finding rounding errors."

## 🐢 Reported Inconvenient Testing (Friction)
*   **Pain Point**: "Tests take 10s to start because of the DB seed."
*   **Suggestion**: "Use an in-memory mock for the DB in unit tests."

## 🏚️ Found Outdated Tests (Legacy)
*   **File**: `src/lib/legacy/OldGraph.test.ts`
*   **Issue**: "References `PluginGraph` which was renamed to `AudioGraph`."
*   **Action**: [Update / Delete / Ignore]

## 👯 Duplicate Tests (Redundancy)
*   **Target**: `TC-09` vs `TC-21`
*   **Observation**: "Both test the 'Play' button state."
*   **Action**: "Consolidating into a single robust test case."
