# /prove shared-state transport (FIN-3519 v1)

A lightweight multiplayer layer for published proofs: readers append reactions to an S3 **events inbox**, an agent-run **fold** merges them into one **CAS state doc**, and the page **polls** that doc. No always-on backend; correctness comes from S3 conditional writes.

## The pieces (`~/.claude/skills/prove/assets/`)
- **`_prove-s3-env.sh`** — shared config resolver (env var → project `.env` → default). Sourced by all the below.
- **`state-append.sh <doc> <event.json>`** — the CAS write: GET `state/<doc>.json` + its ETag → append the event → `put-object --if-match <etag>` (create via `--if-none-match '*'`), retrying on `412`. This is the only writer of the state doc. `NAIVE=1` disables the guard (race-test only).
- **`prove-sync.sh <doc>`** — the **fold** (the CAS owner). Snapshots `events/<doc>/` keys, `state-append`s each, deletes only the folded keys (a new event mid-fold waits for the next run; a failed fold leaves its event for retry).
- **`sign-post.py <doc> [expiry] [max_bytes]`** — pure-stdlib SigV4 **presigned POST** for `events/<doc>/` (`starts-with $key` + `content-length-range`). Emits `{postUrl, keyPrefix, fields, expiresAt}`. Reads creds from `AWS_*` env (`aws configure export-credentials --profile "$PROVE_S3_PROFILE" --format env`).
- **`state-demo.html`** — self-contained standalone demo: polls the state doc, renders a 👍/👎 tally + notes, submits reactions via the presigned POST (FormData, `file` last). Config injected at publish into `#prove-state-config`.
- **`__tests__/state-cas-race.sh [N]`** — the concurrency gate (N parallel appenders → assert `events == N`; `NAIVE=1` proves it has teeth). **`__tests__/post-event.py`** — stdlib multipart POST test helper (mimics the browser).

## Object layout (bucket `staging-finch-proofs`)
```
state/<doc>.json              # shared doc — PUBLIC read (bucket policy), CAS-written by the fold only
events/<doc>/<ts>-<rand>.json # append inbox — presigned-POST writes (authorized), owner-only reads
```

## Config (reuses the `.env` seam)
`PROVE_S3_BUCKET` / `PROVE_S3_REGION` / `PROVE_S3_PROFILE` (existing) + `PROVE_S3_STATE_PREFIX` (default `state`), `PROVE_S3_EVENTS_PREFIX` (default `events`). `PROVE_S3_CAS_ATTEMPTS` (default 30) tunes the retry budget.

## Data shape — owned by `PAYLOAD_SCHEMA.md`, not restated here
**The event shape, the `actor.kind` enum, the id grammar, and the dedupe / supersede / tally rules live in `~/.claude/engine/skills/intake/assets/PAYLOAD_SCHEMA.md`.** Read it there. This file used to restate them and the restatement went stale — it still described a pre-v2 record keyed by a top-level `class` field wrapping a nested per-item array, long after the contract moved to `actor.kind` and one self-contained event per record. A second copy of a contract is a second contract; there is now one.

What the **transport** owns, and all it owns:
- **One event per object.** Each key under `events/<doc>/` holds exactly ONE event object — `state-append.sh` takes a single `<event.json>` and appends that one object. A writer with N events posts N objects.
- **The state doc envelope** is `{"docId": "<doc>", "events": [ … ]}` — a flat array of whatever event objects the fold has appended, in append order.
- **The doc is an append-only LOG, not a reconciled view.** The fold is a blind append (`state-append.sh` does `events.append(ev)` and inspects nothing), so duplicates and superseded events are both *expected* to be present. **Every reader applies `PAYLOAD_SCHEMA.md`'s rules at read time** — dedupe by `id`, then greatest-`ts` per `(actor, item)` — the widget when it renders, the wave when it ingests. Do not teach the fold these rules: a shell script cannot import a markdown contract, which is exactly how the second drifting rule-set above was born.

## Security posture
- **No anonymous public write.** Writes are authorized by the SigV4 presigned-POST signature (the signer's own creds), not a public-write bucket policy. The bucket grants public **read** on `state/*` and `proofs/*` only; `events/*` is private (verified: `events/*` GET → **403**).
- **Unlisted, not secret.** `state/<doc>.json` is a known public key (meant to be polled/shared). There is no public `ListBucket`, so the prefix isn't enumerable, but the state doc is world-readable by design — do not put anything in it that isn't shareable.
- **Presign lifetime.** `sign-post.py` caps expiry at S3's 7-day max **for a static IAM user (`AKIA…`)**. With a temporary/STS profile (`ASIA…`, a session token) the presign is bounded by the **token's** lifetime (hours) — shorter. Re-mint on publish; for a durable page, re-publish to refresh, or degrade to the clipboard copy-back kit.
- **Size-capped, not rate-limited.** `content-length-range` bounds each object; S3 POST has no native rate limit. Fine for an internal/known audience; not for hostile public traffic (that's when the Lambda-collector upgrade earns its keep).
- **Same-origin.** The page is served from the S3 host and POSTs/fetches the same host → no CORS. Add a bucket CORS rule only if fronted by CloudFront/a custom domain.
- **HTTPS-only.** The bucket's `DenyInsecureTransport` covers `state/*` and `events/*` (Vanta).

## Liveness (v1 = agent-async)
The fold is **agent-run** (`prove-sync <doc>` on demand) — zero always-on compute, eventually-consistent. Upgrades to **cron** (near-live, no Lambda — just a timer calling `prove-sync`) or **Lambda on `events/` ObjectCreated** (live) **without changing the doc model, the widget, or the event shape** — only who runs the fold changes.

## Polling (conditional GET — the cheap read path)
The page polls `state/<doc>.json` with `If-None-Match: <last-etag>`. Because every CAS fold rewrites the doc, its **ETag changes on exactly the updates that matter** — an unchanged poll returns **304 + 0 bytes** (verified live: `If-None-Match` on the doc → 304), and the body transfers only when a fold has landed. So poll fast (1–2s) at near-zero idle cost; the widget tracks the ETag and skips re-render on 304. Requires **same-origin** (the ETag response header must be readable — the S3-hosted page already is; cross-origin would need `ETag` in `Access-Control-Expose-Headers`).

There is **no long-poll or push on a plain S3 object** — S3 GET is request/response (no held connection), and S3 event notifications reach only backend targets (Lambda/SNS/SQS/EventBridge), never a browser. So **conditional polling is the S3-only, no-compute liveness path**; held long-poll or WebSocket push require a server and are out of scope. (The other no-compute option is to drop the fold and read the `events/<doc>/` prefix directly via `ListObjectsV2` `start-after=<last-key>` — event-sourced, browser-reconstructs — at the cost of a public-list grant on that prefix.)

## Not in v1 (follow-ups)
- Wiring a reaction widget into a real `/prove` proof + a `PROVE_S3_STATE` SKILL.md mode.
- The board-widgets kit submitting to this transport (coordinated with FIN-3518's schema revision).
- cron/Lambda fold for live updates; cross-proof shared `doc-id`.
