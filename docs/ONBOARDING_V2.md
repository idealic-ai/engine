# Engine v2 — Release & Onboarding Runbook

How to release v2 over the v1 currently on GDrive, and how to bring another developer onto the engine.

Companion to `ENGINE_LIFECYCLE.md` (which defines the two-axis model). This doc is the **operational sequence** — what to run, in what order, and what breaks if you get the order wrong.

---

## 1. First, the mental model

Two axes, fully independent (`ENGINE_LIFECYCLE.md`):

*   **Mode — what Claude reads.** `engine local` / `engine remote` rewrite `~/.claude/` symlinks to point at either the local Git checkout or the GDrive copy. **Moves no files.**
*   **Sync — how content moves.** `engine push`/`pull` = Git ↔ GitHub. `engine deploy` = local → GDrive (`rsync -a --delete`). **This is the release step.**

**The consequence people get wrong:** `deploy` is *not* how you share with a developer. GDrive carries no `.git`, so it is a **consumer** channel — a place to read the engine from, not develop it in.

*   **Developer** → give them **Git**. They pull/push.
*   **Consumer** (just wants a working engine) → `engine deploy`, then they run `engine remote`.

---

## 2. Known drift — resolve before onboarding anyone

These are live inconsistencies in the current setup. Decide each one *before* a second person depends on it.

*   **Two remotes, one of them stale**
  *   `origin` → `git@github.com:idealic-ai/engine.git`
  *   `finch` → `git@github.com:finch-claims/engine.git`
  *   **`engine push` only pushes to `origin`.** As of this writing local is **7 ahead of `origin/main`** and **27 ahead of `finch/main`**.
  *   **Decide:** which remote is canonical for the person you're onboarding? If they're a Finch dev pointed at `finch-claims`, they will clone a months-stale engine and `engine push` will never update it.

*   **Branch pattern vs reality**
  *   `ENGINE_LIFECYCLE.md` documents per-developer branches: `{username}/engine` (e.g. `yarik/engine`).
  *   Current development is on **`main`**.
  *   **Decide:** adopt the documented per-dev branch model, or update the doc to match `main`. A new dev following the doc will land on a branch pattern your work doesn't use.

*   **No tags exist.** "v1" and "v2" are informal — Git has no marker for either. Combined with "no `.git` on GDrive", **there is no way to determine which commit the deployed v1 corresponds to**. It cannot be diffed or reconstructed.
  *   **Fix going forward:** tag the release commit (`git tag v2`) so the *next* release has something to diff against.

---

## 3. Releasing v2 over v1

### What deploy actually does

`cmd_deploy` (`scripts/engine.sh`):

1.  Backs up `GDRIVE_ENGINE` → `GDRIVE_ENGINE.bak` via `cp -a` (**your only rollback**).
2.  `rsync -a --delete` local → GDrive, excluding `.git`, `.mode`, `.user.json`, `.bak`, `node_modules`.

Two properties that matter:

*   **It syncs the working tree, not a commit.** Uncommitted edits ship. Commit first, or you are releasing unreviewed state.
*   **`--delete` mirrors.** Anything on GDrive but not local is destroyed.

### The size of this particular jump

v1 on GDrive is ~February-era (its `engine.bak` dates to Feb 11; newest real files are Feb–Mar). Local v2 is **492 files vs v1's 318**.

*   **Skills v1 has never seen:** `direct`, `do`, `improve-protocol`, `loop`, `session`.
*   **Skills deploy will DELETE from v1:** `dehydrate`, `reanchor`, `refine` (retired locally — intended, but irreversible on GDrive).
*   **Hook files deploy will DELETE from v1:** `pre-tool-use-heartbeat.sh`, `pre-tool-use-session-gate.sh`, `pre-tool-use-directive-gate.sh`, `pre-tool-use-overflow.sh`, `post-tool-use-discovery.sh`, `post-tool-complete-notify.sh`, `post-tool-failure-notify.sh`.
    *   v2 consolidated the first four into a single **`pre-tool-use-overflow-v2.sh`**.

### ⚠ The landmine: deploy breaks every v1 remote-mode user instantly

Anyone in **remote mode** whose settings still reference the seven deleted hooks will hit **broken hooks on every tool call** the moment GDrive syncs the deletion — which happens before they know a release occurred.

**This is not a code bug; it is a sequencing problem.** v2's `engine setup` already repairs it (§4). The release must therefore be *announced and paired with a setup run*, not dropped silently.

### The sequence

```
1.  Review + commit the working tree     git status; git commit   (deploy ships the tree, not a commit)
2.  Tag the release                      git tag v2               (there are no tags — start here)
3.  Preserve v1                          cp -a <GDRIVE>/engine <somewhere-safe>
                                         (deploy overwrites engine.bak; that Feb-11 snapshot is lost otherwise)
4.  Backup to GitHub                     engine push              (origin only — see §2)
5.  RELEASE                              engine deploy            (rsync --delete → GDrive; auto-backs up to engine.bak)
6.  Tell every consumer to run           engine setup             (REQUIRED — repairs their hooks; see §4)
7.  [optional] Verify                    engine remote  →  engine status  →  engine local
```

**Rollback:** `GDRIVE_ENGINE.bak` — single-depth, overwritten by the *next* deploy. There is no second layer.

---

## 4. The hook migration (v1 → v2)

The most consequential behavioral change in v2, and the reason step 6 above is mandatory.

### What changed

There are **three** eras, and it is easy to collapse two of them. The global cleanup already happened in v1 — **v2's only change is committed → gitignored**:

*   **v0:** engine hooks lived in the **global** `~/.claude/settings.json`.
*   **v1:** `configure_hooks "$PROJECT_SETTINGS"` → hooks moved to the **project's `.claude/settings.json`** — the **committed** file. This pollutes the shared repo with per-user hook wiring. **v1 also strips engine config from the global settings** (`migration_006`) — that is v1 behavior, not new in v2.
*   **v2:** `configure_hooks "$PROJECT_LOCAL_SETTINGS"` → **`.claude/settings.local.json`** (gitignored), plus it defuses the leftovers still sitting in the committed `settings.json`.

So **the only v1 → v2 delta is committed → gitignored.** If you are auditing a machine and find engine hooks in the *global* `~/.claude/settings.json`, that box predates v1 — it is not a v2 migration gap.

### Where things live in v2

*   **`.claude/settings.local.json`** — engine hooks. Gitignored, per-developer.
*   **`.claude/settings.json`** — permissions + statusLine. Committed, shared.
*   **`~/.claude/settings.json`** (global) — engine config **stripped out**; holds only non-engine user config.

### Is it destructive?

**Mostly no — it merges.**

*   `configure_hooks` uses an `add_if_missing` jq pattern: an entry is added only if that command path isn't already present. Idempotent; **preserves custom hooks in `settings.local.json`**.
*   `merge_permissions` unions (`| unique`).

**Three exceptions — know these:**

1.  **`configure_statusline` replaces** a non-engine statusLine.
2.  **The defuse block is indiscriminate.** It runs `jq '.hooks |= map_values([])'` on `settings.json` — emptying **every** hook array (keys retained, values `[]`), engine and custom alike. `configure_hooks` then re-creates **only the engine's own hardcoded list**, and only into `settings.local.json`.
    *   **So a genuinely custom project hook living in `settings.json` is cleared and NOT migrated.** It is recoverable from Git (that file is committed), but it will not come back on its own.
    *   **Before running setup on an unfamiliar project**, check for non-engine hooks:
        ```bash
        jq -r '.hooks // {} | to_entries[] | .key as $k | .value[]? | .hooks[]? | "\($k): \(.command)"' \
          .claude/settings.json | grep -v "~/.claude/hooks/"
        ```
        Anything printed is a custom hook that setup will wipe. Migrate it into `settings.local.json` by hand.
3.  **`migration_006`** deletes `.hooks` and `.statusLine` from global `~/.claude/settings.json` outright. (Not a v2 change — v1 does this too; listed here because it is destructive, not because it is new.)

### Current state of the `finch` repo — NOT yet migrated

As of this writing, `Projects/finch` is still in the **v1 layout**:

*   `.claude/settings.json` holds **all 18 engine hook entries** and is **tracked/committed**.
*   `.claude/settings.local.json` **does not exist**.
*   `.gitignore:81` already ignores `.claude/settings.local.json` — the rule is in place, nothing has moved yet.

Note the tell: those hooks are already **v2-era** (`pre-tool-use-overflow-v2.sh`, `pre-tool-use-ticket-watch-gate.sh`) but sit in the **v1 location** — `configure_hooks` last ran from a build with the new hook set and the old target.

**Migrating it is safe**: every entry is engine-owned (the lone `afplay …/Glass.aiff` belongs to the engine's own Stop entry), so nothing custom is lost. Running `engine setup` will produce a reviewable diff on `settings.json` — the arrays going empty — which is the intended cleanup and should be committed.

---

## 5. Onboarding a developer

1.  **Pick the remote and branch model first** (§2). Do not skip this — it is the step that silently wastes their first day.
2.  **They clone / bootstrap:** `engine local` handles Git onboarding automatically — detects no `.git`, prompts for the repo URL (or reads `.user.json`), clones into a temp dir, moves `.git` into the engine directory, creates their branch, caches URL + branch in `.user.json`.
3.  **They run `engine setup [project-name]`** in each project. This installs deps, creates GDrive dirs, links `~/.claude/{scripts,skills,hooks,agents,tools,commands,standards}`, runs pending migrations, links `./sessions/` + `./reports/`, writes project directives stubs, updates `.gitignore`, configures settings, and creates `/usr/local/bin/engine`.
4.  **Verify:** `engine status` — audits mode + symlinks + hook wiring.
5.  **Daily loop:** develop in **local mode** (`¶ENG_LOCAL_MODE_DEVELOPMENT` — GDrive is not a Git repo), commit ad-hoc, `engine push` to back up, `engine deploy` only when releasing to the team.

### Onboarding a consumer

`engine deploy` (you), then they run `engine remote` + `engine setup`. They read the engine from GDrive; they do not develop it.

---

## 6. Gotchas worth pre-empting

*   **GDrive strips `+x`.** `engine local` / `engine setup` call `fix_script_permissions` to restore. Manual: `find ~/.claude/engine -name "*.sh" -exec chmod +x {} +`.
*   **`engine doctor` does not see project-local skills.** It scans `~/.claude/engine/skills/` only — a project's `.claude/skills/` family is entirely unvalidated by it. A clean doctor run does not mean your project skills are clean.
*   **`engine doctor` reports hook commands with arguments as broken.** e.g. `SessionStart: ~/.claude/hooks/session-start-chunk.sh 0 24 does not exist` — the file exists; doctor is path-checking the whole command string including its args. Same for `Stop: afplay …Glass.aiff`. Known false positives; do not chase them.
*   **Sessions ≠ engine.** Sessions are per-project (`./sessions/`), synced by GDrive symlink in remote mode. The engine is global. Different systems, different sync.
*   **Search DBs are derived caches.** Delete-and-rebuild (`¶ENG_SEARCH_DB_REBUILD`); no migrations. If empty after `engine local` (GDrive offline), run `doc-search.sh index && session-search.sh index`.

---

## 7. Related

*   `ENGINE_LIFECYCLE.md` — the two-axis architecture, Git model, first-time setup, troubleshooting
*   `ENGINE_CLI.md` — CLI protocol, function signatures, migration system
*   `CONTRIBUTING.md` — development rules
