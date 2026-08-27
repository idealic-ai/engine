# Ops Toolkit — Email QA bench recipes
Proven on 2026-08-02 (BO/Sharpe arcs). Stand these up ON FIRST NEED, not at boot.

## Tunnels & URLs
- db: `nohup bash scripts/staging-db-tunnel.sh &` (localhost:15432) · redis: `scripts/staging-redis-tunnel.sh` (16379) · keeper: nohup `tunnel-keeper.sh` (SSM dies ~hourly; every long process needs a retry chain).
- URL rebuild: `aws secretsmanager get-secret-value --secret-id staging/finch/db-url --region us-east-2 --query SecretString --output text` → re-encode pw (`python3 urllib.parse.quote(unquote(pw),safe='')`) → psql form `...sslmode=require`, node form `...sslmode=no-verify`. Redis: `rediss://:TOKEN@127.0.0.1:16379` (secret `staging/finch/redis-auth-token`).
- Secrets: `staging/finch/<kebab>`; GOOGLE_CLIENT_SECRET lives at `google-oauth-client-secret`. Worker env template: launcher scripts in sessions/2026_07_29_BLUE_OAKS_OPS_RUN/launchers/ (taskdef-env.tsv + secrets loop + NODE_TLS_REJECT_UNAUTHORIZED=0).

## Worktrees & bundles
- Ops/builder worktree: `git fetch origin dev && git worktree add /Users/tom/finch/wt-<slug> -b <branch> origin/dev && cd ... && rm -f apps/api/.env && npx -y pnpm@10.34.4 install --frozen-lockfile`.
- Re-drive bundle (resync-reclassify apply): `npx -y pnpm@10.34.4 --filter @finch/api exec nest build` → run `node dist/src/commands/resync-reclassify.js` (tsx CANNOT boot AppWorkerModule). Backscan apply vehicle needs `'NODE_TLS_REJECT_UNAUTHORIZED'` added to ALLOWED_EXACT in pending-backscan-sweep/apply-runner.ts (standing local patch until upstreamed).
- `tsc --noEmit` lies after any nest build until `rm -rf apps/api/dist`.

## SQL discipline
- Capture-first ALWAYS: `SELECT row_to_json(...)` → `pre-images/<name>.jsonl` (chmod 600) BEFORE any write. ABSOLUTE paths for pre-image files, and verify the capture landed (`wc -l`) in a SEPARATE command before the mutating one — a cwd-relative append that fails mid-compound-command lets the UPDATE run uncaptured (bitten 2026-08-02).
- Cohort sweeps by LIKE '%<digits>%' catch cross-org noise (FedEx tracking, confirmation numbers) — always org-scope AND eyeball the rows before counting or writing.
- Guarded single-purpose UPDATEs (`AND <current-state predicate>`); verify by re-read after commit.
- Bulk: temp mapping table + ONE joined UPDATE + `SET statement_timeout='90s'` — NEVER psql inside a `while read` loop (psql eats stdin; loop dies after 1 row, silently).
- `carrier_claim_numbers_normalized` is GENERATED — write values only.
- Reindex after ANY SQL claim mutation (no events fire): `tsx reindex-claims.tmp.ts <ids>` / `deindex-claims.tmp.ts` (REDIS_URL env).

## Merges & deletions
- Same-loss twin: `MERGE_DATABASE_URL=<node-url> tsx -r tsconfig-paths/register merge-claims.tmp.ts <survivor> <loser> [--apply]` — moves links/docs/facts, folds refs, retires loser (intake_status='rejected' → excluded from lists + candidate retrieval). Then reindex survivor + deindex loser.
- pncr (pending-new-claim-rollback jest vehicle) deletes intake-born claims only — 0-link claims yield scanned=0; use merge-retire instead. Vehicle env recipe: PNCR_APPLY=1 SKIP_TEST_DB_MIGRATE=1 PNCR_DATABASE_URL=<node-url> + full worker env; audit dir must NOT be under sessions/ (GDrive symlink guard); jest exit code can be POISONED by redis teardown noise after a SUCCESSFUL run — check the audit run-end line + DB state, never the exit code alone.
- Person merge = CONTACT COLLAPSE (contact has (person_id, organization_id) unique): repoint message_participant + claim_contact + move contact_email to survivor person → DELETE loser contact → Algolia party de-index. Do NOT insert into person_merge (different surface; FK-blocks contact deletes).

## Alias mapping (alias-legacy-ref-gap recipe)
1. Census: regexp `([a-z]+)-([a-z0-9]{6,})@claimmail\.net` over to_emails/cc_emails (jsonb → ::text) on queue links; keep refs resolving to NO claim surface (file_number/carrier refs normalized).
2. Map: per alias ref, vote with approved/auto_approved siblings' claim_id over the FULL corpus; accept ≥5 votes AND ≥90% dominance.
3. Promote: bulk temp-table UPDATE appending the alias ref to the dominant claim's carrier_claim_numbers; reindex the claims. Rows then resolve via the existing conf-100 short-circuit / candidate fetch on the next re-drive or backscan sweep.

## Search index
- Party stale object: index `prod_parties`, objectID = contact id. GET-verify → save JSON → REST DELETE → GET-verify 404 (async task; may lag minutes).

## Re-drives & harvests (cost discipline)
- Dry-run prints cohort + cost; canary `--limit 100 --apply`; chain loop with MERGED-resume (merge ALL prior audits per attempt — newest-only re-pays LLM); run-end-aware retry (teardown noise poisons exit codes); advisory-lock clear after chain deaths: `SELECT pg_terminate_backend(a.pid) FROM pg_locks l JOIN pg_stat_activity a ON a.pid=l.pid WHERE l.locktype='advisory' AND a.state='idle';`
- Hourly stats: distinct-id counting over audit JSONLs (raw per-file sums double-count crash-retry overlap).

## Builders (systemic fixes)
- Pack per chunk → `<sessionDir>/builds/<CHUNK>_CONTEXT_PACK.md`; dispatch background builder; on landing RE-RUN its exact gate commands yourself; append reusableFacts to builds/LESSONS.md; chain build → scrutinize → PR (base dev) → codex; `classifier-replay --base=origin/dev` when the diff touches `.github/scripts/classifier-replay-watchlist.json` files. Tier-1 mechanism changes: + council+refuter, flag-gated dark ship, backtest arm, enable = Tom on the artifact.
- **Chain pickup (rework/PR legs from a PRIOR session)**: the pack = origin session's build report + the critique verdict findings (verbatim, incl. M/S/C ids) + current worktree state (`git -C <wt> status/diff --stat`) + the SAME gates as the origin build. Builder CONTINUES in the existing worktree (never a fresh one — uncommitted work lives there). A verdict of APPROVE means the next leg is PR, not rework — don't re-build what the critiquer already passed.
- Rationale-code registries when adding a code: FIVE — propagation-policy, rationale-code-labels, fp-tiers MECHANISM_REGISTRY, guardrails-scorecard metrics, override-classification.routingFromReasonCodes (precedence!).

## Traps
- Plain grep FALSE-EMPTIES on 4k+-line files (candidate-fetcher 4.5k, intake-bootstrapper 6.2k) — perl/sed/node only.
- macOS: no `timeout`, bash 3.2 (no declare -A); zsh doesn't word-split unquoted vars.
- engine log needs cwd=repo-root + a `## ` heading.
- sessions/ is GDrive-symlinked — CLI audit dirs must live elsewhere (symlink guards refuse).
- Review-queue UI counts THREADS; DB counts LINKS (~2.3:1 BO).
- W2b rescue runs only on layer4 didDowngrade (below-bar rows have no lift path unless the dark flag ships/enables).
- contact_lookup candidates are score-capped at 10 — "contact beats address" is FALSE pre-fix.
- Screenshot recovery: /var/folders/.../NSIRD_screencaptureui_* paths are reaped within SECONDS — copy to the session dir IMMEDIATELY on arrival; Desktop-pasted files persist, clipboard pastes are never recoverable.
- classifier-replay receipts record cliCommit `-dirty` if ANYTHING in the tree is uncommitted — and the CI gate rejects dirty receipts. Never run replay from the ops worktree (the standing apply-runner patch lives there); use a clean builder tree.
