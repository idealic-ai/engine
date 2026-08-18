# Fixture provenance — `project-lint`

What is real, what is reconstructed, and where each came from. Read before "fixing" a fixture.

| Fixture | Provenance |
|---|---|
| `desc-intake-clean.md` | **Verbatim.** The live `Product: Intake System` Linear description as stored on 2026-08-01 (read-only `get_project`, `updatedAt` 2026-07-31T16:26:54Z). Includes Linear's own normalization — bold *inside* the link, angle-bracketed URL. Case 5 depends on this being the real stored bytes. |
| `desc-intake-precleanup.md` | **Headings verbatim, bodies reconstructed.** The nine-section pre-cleanup shape of the same description, recovered from `sessions/2026_07_31_INTAKE_PROJECT_DESCRIPTIONS/PROTOCOL_IMPROVEMENT_LOG.md` L5 (section list), L29 (order), L148 (the five deleted sections). **The pre-cleanup body text is recorded nowhere** — the predecessor session used `patch` ops and never captured the before-text. Bodies here are one-line stand-ins; the linter reads headings, so the assertions are unaffected. Do not treat the bodies as historical quotes. |
| `handbook-intake.md` | **Verbatim.** The live `Inbox Handbook` document `28d8ea1b998f`, section headings only (bodies elided to one line each), as stored 2026-08-01. **It is the ordering OUTLIER, not the canonical shape.** An earlier revision of this row claimed it was "the shape all five handbooks were patched to"; the first live `--all` run falsified that — 4 of the 5 order `Data handling` differently, and the schema was reconciled to the majority. This fixture therefore lints with exactly one `section-order` warn, on purpose. |
| `desc-ticketing-only.md` | Synthetic, minimal — isolates Cases 1/2 to a single stray heading. |
| `desc-no-pointer.md` | Synthetic, minimal — Case 3. |
| `desc-out-of-order.md` | Synthetic, minimal — Case 6. |
| `channel-unknown.md` | Synthetic, minimal — Case 9 (a heading no container names). |
| `peers-same/*.md` | Synthetic. Case 7 tests peer *mechanics*; five real 4KB descriptions would bury the assertion. |
| `peers-differ/*.md` | Synthetic. Same reasoning, Case 8. |
| `peers-dup/*.md` | Synthetic, from the adversarial critique. Three handbooks with genuinely divergent `## Data handling`, where `h1` carries that heading **twice**. Before the fix the duplicate deleted `peer-text-differs` for that section across all three. |
| `peers-substring/*.md` | Synthetic, from the same critique. Three handbooks driven with peer labels where one name is a **prefix** of another (`Product: Claims` / `Product: Claims & Policies`), the shape jq `inside` silently mistook for membership. Only the labels matter; the bodies are minimal. |
| `peers-undeclared/*.md` | Synthetic, from the same critique. Five descriptions each carrying a byte-identical `## Operators & cadence` that **no container declares** — the historical incident (`INTAKE_SYSTEM.md:88`) in the one arrangement the linter used to be blind to. |
| `graphql/all/*.json` | Synthetic GraphQL responses, from the same critique. Two projects, both with **colon-bearing** names, in the exact call order `cmd_lint` issues: per project resolve-by-name → project → documents → channels. The descriptions share both a declared (`## Directions`) and an undeclared (`## Operators & cadence`) section verbatim, so one run exercises the peer axis, the last-colon label split, and the widened comparison together. |
| `registry-2proj.md` | Synthetic stand-in for `INBOX_REGISTRY.md`, shaped only as far as `_lint_scope_registry_drift` reads it. Its job is to let the `--all` fixture run reach the peer axis with zero drift findings; drift itself is asserted against the real registry. |
