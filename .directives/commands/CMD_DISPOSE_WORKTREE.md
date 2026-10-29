### ¶CMD_DISPOSE_WORKTREE
**Definition**: What a lane does when it is finished with a worktree — remove the *install*, leave the *tree*.
**Rule**: The install is reinstallable; the tree may hold uncommitted work. Reach for the install first, always. A ceremony that reaches for the tree first is both more destructive and less effective.
**Rule**: Everything below is one command — `engine worktree`. Run it rather than hand-rolling the steps; it is dry-run by default and refuses what this atom forbids.

**Why the install and not the tree**: measured on this fleet's `kit` clone — a bare worktree is ~272 MiB, an installed one ~1764 MiB, of which ~1482 MiB is `node_modules`. About **84% of the cost is the install**, and the install is the only part a `yarn install` brings back.

**Algorithm**:
1.  **Look before you touch.** `engine worktree census` — population by health class, and what the installs actually hold. Never size the problem by counting `node_modules` directories: on this fleet a large fraction of them are empty skeletons or symlink farms that hold no reclaimable bytes (see step 6).
2.  **Drop the install.** `engine worktree drop-install <path>` to see it, `--apply` to do it. `--all` does every worktree whose install holds files, skipping locked ones — a lock is a lane's claim on the tree, and dropping its install breaks a build that is mid-run. This is the disposal move that matters and the only one that is reversible.
3.  **Stop there, by default.** A lane that has finished its work is finished at step 2. The tree costs ~272 MiB and may hold the only copy of someone's uncommitted work. Leave it.
4.  **Before removing ANY directory — including one `git status` calls untracked** — ask whether it is a registered worktree: `engine worktree check <path>`. There is no tell; the check is the only way to know. Per `¶PTF_AN_UNTRACKED_DIRECTORY_MAY_BE_A_REGISTERED_WORKTREE`.
5.  **If the tree genuinely must go** — `engine worktree remove-tree <path> --apply`. It refuses a tree with uncommitted or untracked content, refuses a locked tree, refuses the main worktree, refuses a path that is not a registered worktree, and calls `git worktree remove`. ⛔ **Never `rm -rf` a worktree.** The half that matters lives in the main clone's `.git/worktrees/`, and removing the directory leaves it behind, pointing at nothing.
6.  **Repairing the registry is REPAIR FIRST, PRUNE SECOND, never the reverse.** `engine worktree repair --apply`, then `engine worktree prune --apply`. Prune cannot distinguish a *dangling* registration (path absent — prune is the right clear) from a *broken* one (directory present, its `.git` file gone — prune DEREGISTERS it and destroys the admin dir holding its HEAD and index, orphaning contents still on disk). Git reports both with the same reason string. `engine worktree prune` refuses to run while any broken registration exists; do not route around that refusal.

**Never**:
*   ⛔ Never `rm -rf` a worktree directory. Step 5.
*   ⛔ Never `git worktree prune` before `git worktree repair`. Step 6.
*   ⛔ Never remove a directory you have not run step 4 against.
*   ⛔ Never treat a lock as a guard. A locked worktree does not report `prunable`, so a lock *incidentally* protects a broken registration — but the locks on this fleet carry lane reasons, not hold-for-review reasons, so that protection is a habit and it evaporates the first time somebody tidies lock reasons.
*   ⚠️ Work under `/private/tmp` is losable in a way work under a project directory is not — this machine runs an active reaper there. Treat an uncommitted change in a `/private/tmp` worktree as having no second copy.

**Constraints**:
*   **`¶INV_NO_DESTRUCTIVE_GIT`**: none of the steps above may be substituted with `git clean`, `git checkout`, `git restore`, `git reset` or `git rm`. `git worktree remove`/`repair`/`prune` are the only tree-level writes this atom authorizes, and only through the command.
*   **Dry-run is the default and `--apply` is the only way past it.** This programme has lost work to exactly this class of operation.

---

## PROOF FOR §CMD_DISPOSE_WORKTREE

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "disposalLevel": {
      "type": "string",
      "enum": ["census_only", "install_dropped", "tree_removed", "registry_repaired"],
      "description": "How far down the ladder this run went"
    },
    "paths": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Absolute worktree paths acted on"
    },
    "applied": {
      "type": "boolean",
      "description": "false for a dry run (the default)"
    },
    "refusals": {
      "type": "string",
      "description": "Guards that fired and why, or 'none'"
    }
  },
  "required": ["executed", "disposalLevel", "applied"],
  "additionalProperties": false
}
```
