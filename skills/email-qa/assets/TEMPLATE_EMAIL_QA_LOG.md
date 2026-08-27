# Email QA Log
**Usage**: The bench's work stream — one entry per instance step, decision, builder event, or drain checkpoint.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `log.sh`.

## ▶️ Bench Open
*   **Mode**: [live / drain]
*   **Boot**: tunnels [ok/rebuilt], deploy [sha + green?], taxonomy [N classes, M drifted]
*   **Chunk** (drain mode): [N inbox comments pulled, oldest date]

## 🔎 Probe — [instance N, short name]
*   **Instance**: org · link/claim ids · symptom (Tom's words)
*   **Evidence**: [rationale codes, match_sources, candidates, bindings, graph findings]
*   **Read**: [what actually happened, mechanism level]

## 🔧 Fix — [instance N]
*   **Action**: [stamps/strips/promotions/merges/deletes applied]
*   **Pre-image**: `pre-images/<file>.jsonl`
*   **Verification**: [re-read result]

## 🧬 Classify — [instance N]
*   **Class**: [taxonomy key — existing/NEW]
*   **Systemic**: [none needed / folded into <ticket> / builder dispatched <chunk>]

## 💡 Decision
*   **Choice**: ...
*   **Why**: ...

## 🚧 Block
*   **Obstacle**: ...
*   **Attempt**: ...
*   **Next**: ...

## 🤖 Builder Event
*   **Chunk**: [slug] · [dispatched / landed / gates re-verified / scrutinized / PR #]
*   **Facts → LESSONS**: [reusable facts appended]

## ✅ Instance Done — [instance N]
*   **Ledger**: entry [N] complete
*   **Inbox**: posted `[email-qa handled]` comment [link]

## 👁️ Side Discovery
*   **Finding**: ...
*   **Relevance**: [High / Low]

