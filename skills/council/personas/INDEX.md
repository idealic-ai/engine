# Council Persona Index

`roster_version: 2` — the version of this roster. Bump it whenever personas are added, removed, or materially reworded. Council stamps the version a report was selected against (`SKILL.md` §5.C/§5.D), so a report stays auditable against a specific roster state.

The seatable roster for `/council`. The compose step (§2) reads THIS file — the cheap one-liners — to generatively pick the N most relevant personas, then loads only the seated few's full profiles. **This index is the authoritative roster**; personas are added/removed here, not in `SKILL.md`.

Each entry: **name** · `domain`|`temperament` · *Good for … / Bad for …* · `→ file`. The **`domain`/`temperament` tag is load-bearing** — the hard diversity rule (any 3+ panel seats ≥1 `temperament`) keys off it. Every persona here is project-neutral; a project can add its own local personas by dropping a profile in `personas/` and an entry in this index.

**13 domain** (what you know) · **7 temperament** (how you think). A healthy panel mixes both.

## Domain personas

*   **Architect** · `domain` · Good for: diffs/PRs adding a module or seam, plans, refactors, anything changing how pieces fit · Bad for: one-line bug fixes, copy tweaks, config bumps, self-contained leaf changes · `→ architect.md`
*   **Operator** · `domain` · Good for: diffs/PRs touching queues, loops over rows, external calls, fan-out, cron/backfill, anything that runs unattended · Bad for: pure UI copy, a plan with no runtime yet, single-record CRUD, docs · `→ operator.md`
*   **Specialist** · `domain` · Good for: migrations, schema changes, SQL/Drizzle queries, index/transaction/cache work, anything touching the database or storage · Bad for: pure frontend, copy, prompt text, plans with no data layer · `→ specialist.md`
*   **Schema-Purist** · `domain` · Good for: LLM/structured-output code — JSON schemas handed to a model, classifiers, prompts, OpenAI/Gemini/Anthropic calls, Zod schemas passed to an LLM · Bad for: DB migrations, plain backend logic, UI, infra, a bare Drizzle schema · `→ schema-purist.md`
*   **Security** · `domain` · Good for: auth/access-control code, endpoints taking user input, tenant/org boundaries, secret handling, IDs from the request · Bad for: pure internal computation, copy, styling, a migration with no auth surface, offline batch logic · `→ security.md`
*   **Product-UX** · `domain` · Good for: frontend changes — components, data fetching, optimistic updates, loading/empty/error states · Bad for: backend logic, migrations, prompts, infra, pure API code the UI never touches · `→ product-ux.md`
*   **Copywriter** · `domain` · Good for: frontend UI changes, user-facing docs, error/empty states, naming, onboarding copy · Bad for: DB migrations, internal APIs, infra, pure backend logic · `→ copywriter.md`
*   **Visual Designer** · `domain` · Good for: frontend UI changes, new components/pages, pr/diff touching layout or CSS, design-system work, dashboards · Bad for: DB migrations, internal APIs, infra, backend logic, copy tone · `→ visual-designer.md`
*   **UX Designer** · `domain` · Good for: user-facing flows, multi-step forms/wizards, features touching navigation or IA, pr/diff changing how a task gets done · Bad for: DB migrations, internal APIs, infra, backend logic, pixel-level styling · `→ ux-designer.md`
*   **Accessibility** · `domain` · Good for: frontend UI changes, interactive components (modals/menus/forms), pr/diff touching markup, focus, color, or motion · Bad for: DB migrations, internal APIs, infra, backend logic, server-only code · `→ accessibility.md`
*   **Compliance Counsel** (legal-compliance) · `domain` · Good for: schema/data changes, anything logging or persisting user PII, LLM pipelines touching PII, third-party data flows, retention & audit surfaces · Bad for: pure aesthetics, perf tuning, refactors that move no data · `→ legal-compliance.md`
*   **Domain Expert** · `domain` · Good for: features encoding a business rule or real-world workflow — status/lifecycle & state machines, money/units/quantity math, entitlement/eligibility logic, anything asserting how the domain behaves · Bad for: build tooling, code craft, perf, infra, plumbing that asserts no domain fact · `→ domain-expert.md`
*   **Measurement Skeptic** (metrics-analyst) · `domain` · Good for: any feature shipped to change an outcome, plans that claim a benefit, LLM pipeline changes, dashboards · Bad for: subjective/aesthetic calls, one-off scripts, refactors with no behavioral claim · `→ metrics-analyst.md`

## Temperament personas

*   **Skeptic** · `temperament` · Good for: almost anything with inputs — diffs, functions, schemas, APIs, parsers, migrations, plans with steps · Bad for: pure prose/naming/tone, aesthetic calls, open-ended brainstorms where nothing has run yet · `→ skeptic.md`
*   **First-Principles Reductionist** · `temperament` · Good for: plans, architecture proposals, schemas, new abstractions, "how we've always done it" processes, anything with inherited structure · Bad for: tiny bugfixes, tightly-scoped diffs where the premise is settled, time-critical hotfixes · `→ first-principles-reductionist.md`
*   **Contrarian** · `temperament` · Good for: plans, design decisions, "obvious" choices nobody questioned, one-way-door commitments, brainstorms that converged too fast · Bad for: settled mechanical diffs, bugfixes with one right answer, irreversible decisions already made · `→ contrarian.md`
*   **Systems Thinker** · `temperament` · Good for: changes to shared/core code, schemas, events, caches, defaults, rate limits, anything with callers or subscribers, plans touching incentives or workflows · Bad for: genuinely leaf-node changes, isolated copy, self-contained scripts, one-off throwaways · `→ systems-thinker.md`
*   **Minimalist** · `temperament` · Good for: PRs that add surface (new flags, options, params, abstractions, deps), feature specs, configs, plans that grew mid-flight, APIs · Bad for: subjects that genuinely must grow — a deliberately extensible platform, an under-specified spec, a first draft that needs more before less · `→ minimalist.md`
*   **Historian** · `temperament` · Good for: changes resembling past incidents, reintroduced patterns, migrations, retries/idempotency, auth, a "we tried this before" smell, plans in well-trodden territory · Bad for: genuinely novel greenfield with no precedent, throwaway spikes, subjects where the past offers no analog · `→ historian.md`
*   **Naive Newcomer** · `temperament` · Good for: docs, onboarding, READMEs, public/user-facing APIs, error messages, plans meant for others to execute, any surface a stranger must understand cold · Bad for: deep-internals infra diffs where domain expertise IS the point, hot-path perf tuning, expert-only tooling · `→ naive-newcomer.md`
