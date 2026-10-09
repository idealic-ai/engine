# Experiment Loom Log (The Conductor's Journal)
**Usage**: Track the weave, the money and the verdicts — thread intake, spend, registrations, verdicts, reviews, landings, incidents and the operator's rulings.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `engine log`. Prefix lane-sourced entries with `[<threadId>]`.

## ▶️ Opened
*   **Goal**: [what should get better, measured how]
*   **Budget**: ceiling $[n] · default lane cap $[n] · reserve $[n]
*   **Model tier**: [as ruled; stronger judge: none | capped $[n] per lane for tie-breaks]
*   **Landing authority**: [verdict LAND + review approve | operator confirms each]
*   **Proof publishing**: [the data rule]

## 📦 Inventory
*   **Stored data**: [what outputs and bodies are kept; documents; held-out pool size by lever]
*   **Runtime**: [shared worker + commit; how a private worker starts; store]
*   **Instruments**: present [..] · missing [..] → proposed tooling threads [..]
*   **Spend so far**: $[n] from receipts

## 🧵 Ledger (live — rewrite in place, keep the previous copy)
| threadId | exp | tier | stage | cap / spent | verdict (class) | review | switch | proof |
|----------|-----|------|-------|-------------|-----------------|--------|--------|-------|
| [SLUG] | [NNN] | Registered | verdict | $[cap] / $[spent] | LAND (registered) | approve | off | [url] |
| [SLUG] | — | Light | proved | $0 / $0 | — | — | — | [url] |

## 💰 Spend
| lane | cap | spent (receipts) | in flight | note |
|------|-----|------------------|-----------|------|
| [SLUG] | $[n] | $[n] | $[n] | [..] |
*   **Total**: spent $[n] + committed caps $[n] = worst case $[n] of $[ceiling]

## 🌊 Wave
*   **Threads dispatched**: [threadIds, tiers, caps]
*   **Partition / claims**: [files; document clusters claimed]
*   **Shared-state turn**: [which lane holds the ledger regeneration turn]

## 🔏 Registration
*   **Thread**: [threadId] · **Design**: [path @ commit] · **Run id**: [..] · **Corpus pin**: [..] · **First call**: [time]

## 🏁 Verdict
*   **Thread**: [threadId] · **Line**: `[verbatim from the tool]`
*   **Effect**: [metric base → arm, placebo, p, bar, documents]
*   **Guards**: [each vs base]
*   **Evidence class**: [registered | descriptive | smoke]
*   **Next**: [land → review | park → negative result | confirm on fresh documents]

## 🔍 Review
*   **Change**: [commit] · **Result**: [APPROVE | APPROVE WITH COMMENTS | REQUEST CHANGES]
*   **MUST before merge**: [..] · **MUST before switch-on**: [..]

## 🔁 Landing / restart
*   **Merged**: [commits] · **Switch**: [off | on in code]
*   **Restart**: [old → new worker, commit, clean cutover checks, smoke result]
*   **Knock-on paid**: [lazy | all | changed, $]

## ⚠️ Incident
*   **What**: [..] · **Cost**: [spend, verdicts, time]
*   **Repair**: [..] · **Lesson**: [one line; add a ¶PTF if new]

## 🧑‍⚖️ Ruling (verbatim)
*   **Operator**: "[exact words]"
*   **Applies to**: [threads, COMMON_BRIEF section] · **Broadcast**: [yes, to ..]

## ⬆️ Escalation
*   **Trigger**: [cap reached | contested verdict | review MUST | ruling needed | infra]
*   **Posed as**: [the plain-language choice, recommended first]
*   **Decision**: [operator's choice | default taken and flagged]

## 🅿️ Parked
*   **Thread**: [threadId] · **Why**: [NO-EFFECT | underpowered | ruled out] · **What would reopen it**: [..]

## 💡 Decision
*   **Choice**: "Chose A over B."
*   **Why**: "Reasoning."
