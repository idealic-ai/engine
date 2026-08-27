# Root-Cause Taxonomy — Email Classification QA
**Registry contract**: one entry per class; Linear holds one consolidated ticket per class (instances = comments there; instance COUNT on the ticket is the consolidation/priority signal for /intake waves). Update the `status` line the moment a PR opens/merges or a flag flips. A NEW class = new entry here + consolidated ticket via /ticket (Tom confirms creation).

Seeded 2026-08-02 from the prototype session (sessions/2026_08_02_SHARPE_PROGRAM/ — evidence + build reports in its builds/).

---

## dropped-candidate-as-proposal — FIN-3622 · PR #1782 MERGED 2026-08-03
- **Shape**: link shows a green "LINK THIS EMAIL TO" proposal that Layer 4 explicitly REJECTED. Signature: rationale `[high_confidence_no_match, layer4_single_candidate_dropped]` + empty/irrelevant match_sources + proposed_claim_id set.
- **Mechanism**: intake-bootstrapper deliberately persisted droppedClaimIds[0] into proposedClaimId for "operator visibility"; UI rendered it as a recommendation; bulk approve-to-proposals trusted it.
- **Status**: FIXED + MERGED to dev (PR #1782, 2026-08-03). Read-time discriminator covers historical rows; server-side approve blocks live on next deploy. Chain: awaiting dev→main promotion (replay attestation for the wave).
- **Instance play**: clear the wrong proposal (guarded NULL), stamp the right claim if evidence supports.

## bound-claim-recall — FIN-3623 · PR #1784 MERGED 2026-08-03 (replay REQUIRED pre-main)
- **Shape**: identifier-less mail from a sender who IS a bound contact on the right claim, but the claim never appears in candidates; generic address/name hits win instead.
- **Mechanism** (pinned by red trace test): contact-only candidates score-capped at 10 (candidate-fetcher computeMatchScore) + final sort ranks weak-vs-non-weak before score → bound claim dies at the post-Layer-4 top-5 slice.
- **Status**: DONE — ticket closed + Archived (Linear check 2026-08-12); shipped through the main promotions (replay attestation wave merged pre-#1926). Residual: Layer-1 all-weak strip can still delete a LONE bound claim (deliberately out of scope — future class instance evidence welcome).
- **Instance play**: stamp proposal; fix binding hygiene (see sender-multi-bind).

## sender-multi-bind — FIN-3627
- **Shape**: sender bound to 2+ live claims (twins, false-attaches) → sender/recipient axes structurally ambiguous, no rescue possible.
- **Mechanism**: wave-mint duplicate claims + correspondent-seeding false-attaches (e.g. a contact seeded onto a claim from a mail that was itself mislinked).
- **Status**: DATA CLASS — no code fix; play = twin merge-retire + false-attach strip so the sender single-binds. Evidence bar: same property/loss for twins; the binding's evidence_msft_message_id disproving the attach for strips.

## wave-mint-twins — FIN-3628
- **Shape**: 2-4 claims, same insured, same property, one rich + rest thin/empty.
- **Status**: DATA CLASS — merge-retire losers into the rich survivor (merge-claims pattern; OPS_TOOLKIT § Merges). pncr CANNOT delete 0-link claims (no intake provenance → scanned=0); merge-retire is the working equivalent.

## truncated-or-variant-ref — FIN-3629 · carrier-suffix sub-shape → FIN-3783 (2026-08-10)
- **Shape**: claim carries a truncated/typo'd carrier ref (75-79G3-73D vs -73DE; 2024801356 vs ...256 with 0 votes) or is missing a suffix/zero-pad variant → exact-identifier match misses.
- **Status**: DATA CLASS — add the evidenced variant (≥5 votes or in-subject corroboration, collision-checked incl. zero-pad cores, O-vs-0 checked). Post-#1778 the zero-pad stack auto-bridges PURE pad variants — only promote non-pad variants.
- **CARRIER-SUFFIX sub-shape (FIN-3783, mechanically bridgeable, NOT a typo)**: the carrier quotes a base number, the CW import records the suffixed form (or vice versa) — `IMV5033`↔`IMV5033001H`, `083150F`↔`020221476228`, `M24GL526417`↔`M24GL5264170001`, `162546AB001`↔`162546AB`. An exact-PREFIX relationship the matcher never exploits; the zero-pad stack does not cover it. Direction runs both ways. Dillon: **115** pending rows blocked. Symptom = Definitive rows with the ref IN THE SUBJECT and an empty `Find claim…`.
- **Promotion guard (learned 2026-08-10, do not skip)**: the delta between the two forms must be SHORT and must CONTAIN A DIGIT. Pure-alpha deltas are extraction artifacts, not carrier suffixes — `034239458LEARY` (insured surname glued on) and `490026FW` (the `FW:` forward prefix leaking into extraction) both pass a naive prefix rule and both mint junk carrier refs.

## identifier-absent-refusal — FIN-3782 (NEW 2026-08-10)
- **Shape**: mail quotes a carrier ref; the CORRECT claim is in `candidate_claim_ids`; every non-identifier signal agrees (insured, claimant, policy #, DOL, property); Stage-2 still writes `[high_confidence_no_match] … no candidate matches <REF>` and queues with no proposal.
- **Mechanism**: the refusal is LITERALLY CORRECT — at decision time the claim did not carry that identifier. The ref usually arrives later via `review_correction` when a human approves the row. So the FIRST mail carrying any new carrier ref is structurally unmatchable, which on an onboarding corpus is every claim's first carrier correspondence.
- **Verify before classifying as this**: read `claim_event claim.identifier_added` for the ref. Ref added AFTER the link's `created_at` = ordinary staleness (re-drive), not this class. Dillon decomposition: 61 staleness · 9 ambiguous-at-decision · **68 unexplained** (ref present on exactly one live claim and still refused) — the 68 is the honest starting cohort, not yet proven to be this class.
- **Instance play**: stamp the proposal under guard once the ref is on the claim; log the instance on FIN-3782.

## alias-legacy-ref-gap — FIN-3625 · PR #1783 MERGED 2026-08-03
- **Shape**: mail To/CC a claimmail alias (`<org-slug>-<legacyref>@claimmail.net`) with no body identifiers → empty candidates; alias ref matches no claim surface.
- **Mechanism**: the alias LANE exists end-to-end (extraction → header-grade evidence → conf-100 short-circuit on file_number → candidate fetch on all 3 identity surfaces); legacy-system numbers were simply never recorded on claims.
- **Status**: DATA CLASS with a proven recipe — alias census + approved-sibling-vote mapping (≥5 votes, ≥90% dominance) → bulk ref promotion (OPS_TOOLKIT § Alias mapping). 2026-08-02: 30 BO mappings promoted ≈ 900 queue rows unlocked. Plus build `claimmail-alias-ref` precision fix (role-alias junk no longer enters claimNumbers) — MERGED to dev (PR #1783, 2026-08-03); awaiting dev→main promotion.

## below-threshold-no-rescue — FIN-3624 · CANCELED 2026-08-05 (mechanism stays dark)
- **Shape**: correct strong/moderate proposal from a bound sender sits in queue ("below-threshold confidence"); user expects auto-attach.
- **Mechanism**: the W2b/recipient rescue only runs on layer4 didDowngrade — below-auto-bar rows have NO lift path even single-bound with candidate agreement.
- **Status**: TICKET CANCELED 2026-08-05 (probe verdict stands: the dark flag fixes ~zero reported instances — address-evidence-only lift, 42 rows all-staging). Mechanism stays merged dark/OFF; the real lever is the evidence gate's role for bound senders (FIN-3616/3617). Operator relief meanwhile = FIN-3703 bulk ergonomics.

## stale-search-object — FIN-3630
- **Shape**: global search shows a person/claim that 404s on click.
- **Mechanism**: contact/claim deleted without party de-index (FIN-3022 durability class).
- **Status**: TRACKED (FIN-3022). Instance play: verify DB row gone → save object JSON → DELETE from Algolia (prod_parties, objectID=contact id) → verify 404 (async, may lag minutes).

## attachment-unavailable — FIN-3626 · PR #1781 MERGED 2026-08-03
- **Shape**: review-queue attachment chip → "This attachment is no longer available"; S3 404 on the download_url key.
- **Mechanism** (builder-verified): the promotion path copies temp→final and deletes the temp object but never repoints email_attachment.download_url (the review-serve column). NOT lifecycle: the staging bucket has NO lifecycle configuration at all.
- **Status**: FIXED in build `attachment-availability` (read-time recovery: promoted-copy resolve → Graph re-fetch, single-flight, terminal marker; + attachment-bytes-recovery CLI; Gmail scoped out). MERGED to dev (PR #1781, 2026-08-03); awaiting dev→main promotion. NOW DUE (Tom): bucket lifecycle config + retag-IAM check (post-merge queue comment on ticket). Exposure: ~94k queue-linked temp-prefix rows org-wide, gone-rate UNMEASURED — measure before committing to any bytes backfill.

## missing-claim — FIN-3631
- **Shape**: identifier-rich mail cohort (real refs, real property) with no claim anywhere — often pre-Finch losses.
- **Status**: DATA CLASS + DETECTOR MERGED (PR #1786, dev 2026-08-03) — review-queue banner surfaces unresolvable-ref cohorts (zero-pad-grouped, place-grain dedup, honest backscan-window copy). Create still Tom's call (UI preferred; programmatic mint = claim+property+file spine+ref+reindex — folder tree won't seed).

## thread-contamination — FIN-3632
- **Shape**: whole conversation proposes/binds to the wrong claim because an early message was mislinked; conversation_thread (50 pts) then dominates every sibling.
- **Status**: ARCHITECTURE CLASS — no derivation edge on links (FIN-3612 epic, propagation-containment phase FIN-3616). Instance play: stamp correct proposals on queue rows; auto_approved wrong-links are HUMAN reassignments (never overwrite review-grade states); log the instance as FIN-3616 evidence.

## artifact-minted-claim — FIN-3633
- **Shape**: create-lane-minted claim carries structured-output artifacts (`: null`, `}}}]}`, `$ref` fragments) in property address / claim fields; renders as JSON garbage in the queue proposal line, degrades dedup keys, and catches wrong proposals.
- **Mechanism**: pre-FIN-3312 create lane persisted artifact-bearing extraction output into minted claim/property rows; extractor leak fixed, minted-claim damage never censused (FIN-3314 cleaned links only).
- **Status**: DATA CLASS — 2026-08-02 census found 3 platform-wide, all repaired (BO Hawkins twin merge-retired + cleared; BO Chahin cleared; Grand Isle suffix stripped). property.address is NOT NULL — clear with `''`. Open residual: write-path artifact-shape guard at mint (small builder chunk if a post-fix instance appears).
- **Instance play**: census regex `(: null|\}\}\}|\$ref)` over property.address/claim.title → pre-image → clear/repair; twin of a real claim → merge-retire per wave-mint-twins; reindex.

## evidence-hold-at-band — FIN-3634 (CLOSED 2026-08-03)
- **Shape**: strong+×strong+ row with the CORRECT proposal held from auto-approve by the evidence layer — chips 'Held: no text-verifiable evidence…', 'Held by quote-verification guard…', 'Fabrication guard tripped (unsupported evidence)'. Codes: no_verifiable_evidence_tags / rationale_tags_unverified.
- **Mechanism**: verify-quoted-evidence + pre-routing fabrication guard downgrade unverifiable-quote rows; held cohort has NO rescue path. BO census 2026-08-03: 295 + 165 rows.
- **Status**: FIXED + MERGED (PR #1787, dev 2026-08-03) — guard verifies the full model-visible fence unconditionally (no flag); fence/fold mechanism metered; census predicts ~1,361 BO releases on deploy. Residual lever for OTHER hold shapes: lineage tier FIN-2751 (still dark). Owed: empty-candidate_id follow-up ticket.
- **Instance play**: none data-side (proposal correct; approval is the reviewer's). Log instance on FIN-3634.

## pipeline-error-stuck — FIN-3650
- **Shape**: unreviewed links whose pipeline_state never reached 'complete' sit in the pending backlog looking like review work — there is no decision to review.
- **Mechanism**: classification crashed/capped and nothing re-drives (resync-reclassify filters complete-only; UI doesn't distinguish; orphan sweep sees only failed_pending_recovery). Systemic = FIN-3636.
- **Instance play**: census `pipeline_state <> 'complete'` unreviewed per org → retag llm_call_audit pipeline-error → pipeline-error-superseded → flip to failed_pending_recovery → OrphanRecoveryService sweeps. Never hand-classify.
- **Known**: BO 128 threads (2026-08-03).

## footer-address-contamination — FIN-3355 (adopted anchor 2026-08-04)
- **Shape**: org's own footer/signature address rides `extracted_address` / `exact_address_match` as high-confidence evidence → one claim magnetizes the firm's entire correspondence (BO "224 Sapphire Ave": 7,439 of 10,105 "address-recoverable" stuck emails = one footer address; 1,001 candidate_mismatch links on one claim).
- **Status**: TRACKED on FIN-3355 (pre-dates the bench; adopted as the class anchor). Operational mitigation proven: any address-recovery run MUST filter high-concentration addresses (one address matching >N stuck emails ⇒ footer, not property) — 07-27 drain took only the ≤10-emails/address clean tail. Sharpe twin finding: 449 links / 200 refs on own signature addresses.
- **Instance play**: never act on address recovery without the concentration filter; log instances on FIN-3355.

## proposal-on-no-match-verdict — FIN-3672 · DONE 2026-08-05
- **Shape**: queue row's rationale head is `high_confidence_no_match` / `claim_below_threshold` yet `proposed_claim_id` is stamped — reviewer sees a recommendation the model disclaimed. Sharpe: 195/303 evidence-less proposals (~2/3 of wrong-proposal family).
- **Mechanism**: write path persists the Stage-2 candidate as proposal on no-match verdicts; NOT covered by FIN-3622's discriminator (verified 2026-08-04 — only layer4_single_candidate_dropped legs).
- **Status**: DONE (Linear 2026-08-05, closed with the FIN-3652 create-lane/cohort hardening wave; released to staging 08-05 #1845). Historical pre-fix rows still carry the shape — instance play stands.
- **Instance play**: clear wrong proposal under guard (pending/parked + NULL-or-known-wrong); log instance on FIN-3672.

## retired-claim-proposal-leak — FIN-3673 · DONE 2026-08-05
- **Shape**: claim retired (`intake_status='rejected'`) but live proposals still point at it; candidates and proposals read paths disagree (no shared fail-closed predicate). Recurs on every merge/retire.
- **Status**: DONE (Linear 2026-08-05; released 08-05 #1845). Post-retire proposal sweep still good hygiene on manual retires.
- **Instance play**: after ANY merge-retire, sweep proposals pointing at the loser (guarded NULL or re-point on evidence).

## own-domain-sender-handling — FIN-3674
- **Shape**: staff/own-domain senders (a) inflate correspondent-style evidence (free noise) and (b) silently lose doc-bearing mail (431 never-reviewed auto-rejected sharpeaa.com emails with real documents — no binding tier for staff mail).
- **Status**: DONE (Linear 2026-08-12 check; shipped — original ticket premise refuted per the 08-10 wave; own-domain handling landed). Fresh instances = regression signals; log on FIN-3674.
- **Instance play**: none inline (policy class); log instances on FIN-3674.

## fabricated-claim-identity — FIN-3675 · DONE 2026-08-05
- **Shape**: claim's stored title + property appear in ZERO org messages (Sharpe 2026070014 "Charles E. Saunders"/Deer Park = actually Pruett's Foods) → poisons merges + proposals.
- **Status**: DONE (Linear 2026-08-05, detector + repair recipe landed with the create-lane hardening wave).
- **Instance play**: identity repair MUST touch all four surfaces: claim.title + property row + claim.loss* (queue chip = formatLossAddress over claim.loss*) + Algolia reindex.

## placeholder-address-magnet — FIN-3676 · DONE 2026-08-05
- **Shape**: "SEE REMARKS" / "/, /" placeholder addresses never disqualify on the address axis → biggest claim absorbs weak proposals. Two orgs confirmed (Occidental, Sharpe).
- **Status**: DONE (Linear 2026-08-05, closed with the create-lane hardening wave).
- **Instance play**: blank evidenced placeholders (pre-imaged) + reindex; log on FIN-3676.

## reclassify-projection-drop — FIN-3669 · RELEASED to staging 2026-08-06 (#1845) · repair RUN GREEN (FIN-3677 dup-canceled)
- **Shape**: approved link, no `message` row on the claim; recovery runs report `projected=N` while inserting nothing. Census 41,665 messages / 7 orgs (BO 37,366; Sharpe 1,596); machine-lane drop rate 95.8% Aug 3-4.
- **Mechanism** (bench probe + PR converge): operator-reclassify lanes (backscan sweep, resync-reclassify, magnet-unwind, live ClaimBackscanSweepService) have no projecting caller — runPipeline runs standalone; `processed_at` then blinds projectRecord AND findMissedMessages self-heal; reproject tallies the no-op call as ok.
- **Status**: RELEASED to staging 2026-08-06 (#1845). projection-repair --all-orgs --apply RUN GREEN same night: 514 repaired / 0 failed (census cohort 528 — the original 41,665 had largely converged; 8,141 key-elsewhere + 14 key-conflict excluded by design). The claim-scoped phase-reclassify TOOLING GAP is now CLOSED: `phase-backfill --claim-ids` merged 2026-08-06 (PR #1854 `eb3ec097e`, + Redis-aware gate/ledger, stale-job recording, exit-2 semantics). Suppressed-cohort run DONE 2026-08-06 evening: 94/94 enqueued (org 0cd53418 GGG proper — NOT eda680f7 'GGG/AI (Rebuild)'), queue drained failed:0, 0 phase transitions (28 LLM-agreed + 66 no_signals_retain_phase) — converged no-op; ledgers in sessions/2026_08_06_EMAIL_QA_BENCH/builds/.
- **Instance play**: none inline — NEVER clear processed_at; log instances on FIN-3669.

## retrieval-fallback-generic-token — FIN-3678 · DONE · PR #1832 MERGED 2026-08-04, RELEASED to staging 2026-08-06 (#1845)
- **Shape**: wrong proposal whose ONLY match_source is a fallback axis on a generic token: `algolia_subject_fallback` ("station"/"fire"/"rooftop"/"allister"), `algolia_address_search` city-only ("St.Louis"), `algolia_name_search` short-acronym fuzz ("PDR"/"CHP" at 0.4-0.8). Feeds the magnet-claim pattern (Haden: Ference 461 + Perrone 135 pending proposals; 463 cleared 2026-08-04).
- **Status**: DONE — PR #1832 merged to dev 2026-08-04, released to staging with #1845 (2026-08-06). Census watch owed (post-deploy fallback-noise rate). Fresh post-08-06 instances of this shape = regression signals.
- **Instance play**: clear/re-point the wrong proposal under guard; log on FIN-3678. Check match_sources FIRST — fallback-only = presumptive noise.

## stranded-after-claim-create — FIN-3708 (minted 2026-08-06)
- **Shape**: rows classified before their claim existed (lead_filed / parked / pending no-match) never re-evaluate when the claim IS created; cohort-attach stamps then hit the not-recommended strike. Whole sender cohorts sit "should have attached" (BO: Chavarria, Rinder, Skinner, Ettinger, Williams).
- **Mechanism**: claim-create backscan (FIN-2962) + sweep (FIN-2926) cohorts key on IDENTIFIER resolution of PENDING links — lead_filed rows and name-only cohorts are structurally outside; no lane can lift them.
- **Status**: LEG 1 MERGED 2026-08-06 (PR #1855). LEG 2 MERGED 2026-08-08 (PR #1876 — claim-created re-drive arm, DARK: CLAIM_BACKSCAN_REDRIVE_ENABLED org-allowlist + CLAIM_BACKSCAN_REDRIVE_AXES per-axis, fail-closed; backscan-redrive-backtest CLI judges Wilson-hi vs tier-1 bar; enable = Tom on a staging backtest artifact, name axis first). Chunk 2 (end-to-end recall proof) owed. LEG 1 MERGED to dev 2026-08-06 (PR #1855 `d9519b2d4`) — claim-created suggestion pass: hint lifecycle, own-mailbox exclusion, lane-aware attach confirm on BOTH review surfaces, appended-marker labels finally rendering in Why-queued, sender-leg stamp ceiling (BACKSCAN_SUGGEST_MAX_SENDER_STAMPS=20). Ticket **deliberately LEFT OPEN**: acceptance signals (auto-attach at the tier bars, name/sender-signal cohorts) are UNMET by leg 1. Program note: Phase 3/4 territory (FIN-3616/3617) — check before building leg 2. Carries Tom's optimize-backscan directive.
- **Instance play**: stamp NULL-props → the claim under guard (correct proposals unblock single-row approve); log instance on FIN-3708. Struck stamps = the discriminator class, separate.

## queue-search-recipient-gap — FIN-3711 · PR #1853 MERGED + RELEASED to staging 2026-08-06 (#1861)
- **Shape**: review-queue search box misses emails that exist — predicate was `subject ILIKE … OR from_email ILIKE …` only, so recipient/cc addresses (staff → insured direction) never matched.
- **Status**: DONE — search now matches recipients + cc and trims input. Fresh misses post-08-06 = regression signal.
- **Instance play**: none data-side; log instances on FIN-3711.

## overlay-churn — FIN-3710 · PR #1856 MERGED + RELEASED to staging 2026-08-06 (#1861)
- **Shape**: review-panel/sidebar "shakes" or closes while approvals process — queue refetch while the thread panel is open unmounts/replaces the open row. Surface of the FIN-3659 jitter family.
- **Status**: DONE (overlay stability). ⚠ #1856 + the #1855 spec were the semantic-merge dev-red pair (no textual conflict; fixed e28f17f70 via #1859).
- **Instance play**: none data-side; log instances on FIN-3710.

## not-recommended-false-strike — FIN-3712 · PR #1851 MERGED 2026-08-06 · chip PR #1859 MERGED 2026-08-06 · RELEASED to staging 2026-08-06 (#1861)
- **Shape**: correct proposals render struck "not recommended" + bulk checkbox disabled — rows classified no-match BEFORE the claim existed, proposal stamped LATER by cohort-attach/hint sweeps.
- **Mechanism** (builder-proven, stronger than the staging hypothesis): rationale head + proposed_claim_id are CO-WRITTEN in one statement; the hcnm routing branch always writes NULL proposal → hcnm+proposal is structurally impossible from the decision = always a later stamp. original_decision is NOT a provenance signal (written only by Layer-4 downgrade paths — NULL on all no-match rows).
- **Status**: MERGED to dev 2026-08-06 (PR #1851 `fef27744e`; anchor is FIN-3712, NOT FIN-3672 — that parent closed 08-05). Strike narrowed to claim_below_threshold; SQL twin in lockstep; NEW writeLink chokepoint guard drops+warns an hcnm-paired proposal at write time, so the structural premise is enforced not assumed. Read-time only — ~6,541 rows move new_claim_suggested → matched on deploy, zero data changes. Provenance chip SHIPPED separately (PR #1859 `b2d8836d6`, via typegen #1858): "added after classification" on the queue cell + panel card, bulk approve eligibility pinned UNCHANGED by spec. ⚠ Merged with NO CI (Actions down) — local pre-push was the gate. ⚠ Post-fix, wrong post-decision stamps (T&I Williams case) render endorsed — human review + dropped_candidate/retired/staleness gates remain; upstream fix = cohort-attach ambiguity gate. OPEN product call: whether stamped rows join DEFAULT bulk approve-to-proposals sets.
- **Instance play**: none data-side where the proposal is correct (approve is human); wrong stamps → clear/re-point under guard.

## vendor-fanout-contact-evidence — MEASURED + REJECTED 2026-08-08 · PR #1887 CLOSED unmerged
- **Shape**: subject literally names the claim (or the insured) yet the proposal goes elsewhere — because a VENDOR on the mail is bound to many claims. Haden examples: subject `Passco` → R Cockrell; `Contents estimate for Laura Gross and update` → Mark Mayer; `Pereira` → Gabor; `Veca` / `Nixon report` → Ference; Chamberlin → Ference.
- **Mechanism** (source-verified): `candidate-fetcher.service.ts` `computeMatchScore` scores `contact_lookup` a FLAT **25** regardless of fanout, while `algolia_name_search` high-confidence scores **20**. Haden census: doncheym@gmail.com **40** live claims; firetestpro/moldtestpro/statefarm/bershad 12; pauldavis 10. Bindings are CORRECT data — the defect is the WEIGHT.
- **Narrower than it first looks**: contact-ONLY candidates are already capped at 10 (`isContactOnlyCandidate`) AND sorted below non-weak ones, so the real cohort is a claim with ≥1 vendor binding **AND** ≥1 non-contact source (the magnet shape). That cohort has never been counted.
- **Status**: **REJECTED ON EVIDENCE 2026-08-08.** Built, critiqued (8 findings), council-reviewed (5 lenses, 9 MUST FIX, 0 survived independent refutation), then MEASURED by a purpose-built `contact-fanout-backtest`. PR #1887 **closed unmerged**. Verdict: safe but inert — eviction **0** at every threshold on 2 orgs (Wilson upper ~0.25% over 1,511 opportunities, inside the Tier-1 bar), but **0 admissions**, 96-98% identical ordering, 14 movements across 1,972 rows (0.7%).
- **WHY IT FAILED — the reusable fact**: `computeMatchScore` already caps contact-only candidates at 10 (`candidate-fetcher.service.ts:2166`, applied AFTER max-over-sources). The pure-vendor-magnet case is therefore **already guarded**, and a 25→10 contact demotion is inert on it by construction. Check this cap before proposing ANY contact-evidence scoring change.
- **The reported instances have a different cause.** The motivating row (`Contents estimate for Laura Gross…` → Mark Mayer) carries a TARGETED lane alongside `contact_lookup`, so demoting contact still leaves 15-20 on the wrong claim. Evidence points at the **Algolia name/address lanes**, not contacts — that is where the next investigation goes.
- **Instance play**: NONE data-side — the bindings are legitimate. Log instances here; do not strip vendor bindings, and do not re-propose fanout demotion without first addressing the `:2166` cap.
- **Reusable harness**: the backtest (Nest-free fetcher instantiation, cohort SQL, input reconstruction, top-5 diff, threshold sweep — zero LLM calls) survives on branch `fin-3627-vendor-fanout-contact-evidence` (c312be0ff, 4a1ce664c). Lift it for any candidate-ordering question. Traps it encodes: `llm_call_audit.requestPayload` is rendered prose and NOT replayable; the conversation-thread lane injects the cohort row's own ground truth and must be disabled or the result is a vacuous 0%.

## junk-carrier-ref-regeneration — NEW 2026-08-08 (extends FIN-3581)
- **Shape**: non-carrier identifiers land in `claim.carrier_claim_numbers` and magnetize unrelated mail. Haden: EMSL lab order numbers (`3625xxxxx`) and the firm's OWN invoice numbers (`INV-000x`) on 5 claims.
- **Key fact**: **stripping does not hold.** The promotion path re-added a fresh EMSL number to a claim mid-session, minutes after it was cleaned. The org `junkCarrierRefs` blacklist is per-TOKEN, so it can never block a NEW order number.
- **Instance play**: strip (pre-imaged, guarded) + reindex, then **re-run the predicate as an independent post-write check** — a census/strip escaping mismatch silently dropped a row this session. Real fix = a shape/provenance rule at the promotion path.
- **Sibling shape**: a claim carrying ANOTHER claim's **file_number** as a carrier ref (Haden: Mayer 2025010015 held `2025120001`). Sweep with a self-join on `file_number`.

## carrier-name-insured-collision — FIN-3873 (NEW 2026-08-12)
- **Shape**: proposal lands on an insured whose surname fuzzy-matches a CARRIER name in the subject — `algolia_name_search` "Chubb" → "CHUBenko" 0.8 (the mechanism behind the Chubenko magnet threads). Distinct from FIN-3678: name lane, not subject fallback; the token is a carrier name, categorically never insured identity.
- **Status**: BACKTEST LANDED 2026-08-12 (bench B) — VERDICT: BUILD as **demotion-to-ambient** (not suppression). carrier_sole wrong-link 100% (4/4) Dillon / 60% (15/25) Haden, Wilson lower bounds ~50× the tier-1 bar; **153 Haden carrier_sole rows auto_approved = live breach cohort (ops audit owed)**; ambient-name filter does NOT bound the class (layer4 skipped_no_competing on 152/153). Artifact: sessions/2026_08_12_email_qa_drain_b/builds/FIN3873_BACKTEST_REPORT.md; harness = `carrier-name-backtest` command on fin-3627 branch (7a78c14ae). Fix build = Tier-1 chain (council+refuter, dark flag, enable on artifact) — NOT started.
- **Instance play**: clear/re-point wrong proposals under guard; log instances on FIN-3873. Check match_sources for a name-lane hit whose query equals a carrier on the org's book.

## blank-named-insured-blind-spot — FIN-3906 (NEW 2026-08-13)
- **Shape**: contamination/identity checks PASS any policy snapshot with a blank named_insured — blank never mismatches, so foreign policies hide exactly where extraction was weakest. BO census: 389 blank (172 real-policy; 21 provably foreign via policy-number cross-attribution); fleet 12,470 blank.
- **Status**: TICKETED 2026-08-13. Fix direction: blank NI = unverifiable/FLAG, never pass; secondary signal = normalized-policy-number cross-claim attribution.
- **Instance play**: census query (on the ticket) sizes it; cross-attributed rows are human-review candidates, never auto-detached.

## failed-job-dedup-swallow — evidence on FIN-3791 (bench 2026-08-12, class mint pending Tom)
- **Shape**: a queue job with a STABLE dedup jobId fails terminally; every later event-driven enqueue under that key is silently swallowed, so the entity stops converging (search-index `claim_<id>`: 96 rate-limit failures on 07-30 froze reindexing for ~2 weeks; nothing alarmed).
- **Instance play**: retry the failed set via bullmq job.retry() (script must live inside a tree with node_modules); malformed jobs get split/re-enqueued with unique manual jobIds; verify failed=0 after drain. Alarm systemic = FIN-3791.

## Bench watchlists (org-specific)
- **Dillon magnet**: **Sergey Chubenko `2023070013`** (49 Pine Street, Swampscott MA) — caught both the Dunphy thread and Sallie Squire's "Chubb Update" thread, whose only shared signal is the carrier **Chubb**. Any proposal to it on mail not obviously his = presumptive noise; never bulk-approve a set containing it.
- **Dillon onboarding shape (2026-07-06/07)**: the email backfill's create lane minted claims CONCURRENTLY with / ahead of the CW import that brought the real ones, so mint↔import twins are the org's dominant defect generator. 52 merged 2026-08-10. Twin census recipe: match mint→import on first+last name token, score on 3 independent axes (shared carrier ref · address prefix · **shared bound contact email**) — the contact axis is what catches middle-initial and `&`-spouse titles that an exact-name join misses (Emily Gould).
- **Merge semantics (FIN-3489), commonly mis-assumed**: a merge sets `claim_status='merged'` and LEAVES `intake_status='active'`; colliding `claim_contact` rows STAY on the anchor by design (`move_dedup`). Live read paths must exclude retired anchors via `notRetiredClaim()` — `sender-claim-binding.service.ts` already does (line ~144). Any multi-bind measurement MUST use the widened trust set `('manual','cw_import','email','extraction')`; filtering to cw_import/manual hides every create-lane binding and understated Dillon's multi-bind by ~7x.
- **Haden magnets**: Travis Ference 2025010011 + Charles Perrone 2025080001 + **Tracy Nightingale 2026030002** (added 2026-08-05: absorbed 12 cross-matter proposals — KMC/Bridgers/Cescolini/Dockside/receipts) — any proposal to them on mail not obviously theirs = presumptive noise; never bulk-approve sets containing them (memory: reference_haden_magnet_claims_ference_perrone).
- **Review-queue bulk ergonomics** ask (not-recommended rows selectable + leads bulk-approvable) = FIN-3703 (filed 2026-08-05).
- **Haden staging API OOM**: sequential approvals can OOM the API (FIN-3655, desired=1 → full outage FIN-3656) — approve in short bursts until fixed.

---

# The Architecture Program — Path to 100 (FIN-3612)

The structural remediation program behind the taxonomy, now living in the **Product: Email Classification** project. The bench feeds it: architecture-class instances are its live evidence, and several classes dissolve outright when its phases land. Sequencing is load-bearing (instruments → contracts → substrate → containment → retrieval → composition) — never build against a later phase's territory without checking the phase ticket.

- **FIN-3613 Phase 0 Instruments** — email classifier's OWN noise floor (the 84% figure is the PHASE classifier's, never email's), mechanism liveness alarms, falsifiable exit criteria. Bench relevance: any "is the classifier flaky" instance routes here; never size stochasticity work off borrowed numbers.
- **FIN-3614 Phase 1 Contract hardening** — fail-closed classifier_config (the recencyWindowDays fail-open we fixed in PR #1785 is this class), one-schema-per-cache-name, grounded checklist authority. Bench relevance: config-shaped instances (org silently re-enabled, tier silently dead) → this ticket.
- **FIN-3615 Phase 2 Decision substrate** — append-only decision record + propagation derivation edge. Bench relevance: every "rationale was overwritten / which column is truth" trap.
- **FIN-3616 Phase 3 Propagation containment** — typed blast-radius bound. Bench relevance: **thread-contamination class instances are this ticket's live evidence** — log them there.
- **FIN-3617 Phase 4 Retrieval completeness** — reviews compile to graph facts + coverage measurement. Bench relevance: the bench's data plays (ref promotions, alias mappings, binding fixes) are this phase run BY HAND — every manual recipe run is evidence for the compiler; hcnm cohort decompositions feed its denominator work.
- **FIN-3618 Phase 5 Composition** — runPipeline decomposition + deterministic-first inversion. Bench relevance: guard-ordering surprises (Layer-3-blocks-Layer-4 class) are its trap catalog.
- **FIN-3619 North-star: conversation-unit decisions** — would dissolve propagation classes entirely; Phase 2/3 designs must stay compatible.
- **FIN-3620 North-star spike: fine-tuned classifier** — accuracy/cost/determinism vs prompted gpt-4o-mini, gated on Phase 0's baseline. Cost inputs on the ticket (incl. GPU pricing: L40S $1.95/h, A100-80 $2.50/h, H100 $3.95/h, T4 $0.59/h — Tom, 2026-08-03).
