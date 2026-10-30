---
id: broken-worktrees
to: operator
from: manager:director
why: Planner leftover R is the only unanswered fork on the 23:22 board; 33 broken temp worktrees and 26 broken registrations sit in two repositories
importance: medium
stakes: A prune before a repair deletes admin state that holds HEAD and the index; a broken registration may be someone's only record of a detached tip
context: sessions/2026_10_28_DIRECTOR/builds/planner-leftovers_PROBE.md item R; PITFALLS ¶PTF_AN_UNTRACKED_DIRECTORY_MAY_BE_A_REGISTERED_WORKTREE
alternatives: dispose all; census then dispose; leave
lean: census then dispose, repair before prune
falsifier: the census finds a registration whose branch tip exists nowhere else
status: answered
revision: 2
dependsOn:
created: 2026-10-28T16:38:31.539Z
delivery: delivered
deliveryNote:
reads: manager:director@2026-10-28T18:35:34.017Z
readAt: 2026-10-28T18:35:34.017Z
readBy: manager:director
acted: Disposed the broken registrations and their temp folders; tips recorded in builds/worktrees_TIPS.tsv; skipped 1 busy tree and 2 that broke mid-run
actedAt: 2026-10-28T19:03:04.049Z
actedBy: manager:director
---

Planner left 33 broken worktrees in a temp folder and 26 broken git worktree registrations. A broken registration (the folder is there but its .git is gone) is wiped by `git worktree prune`, and that can take with it the only record of a detached tip. The engine's PITFALLS file says: repair first, prune second.

## ¶ASK_DISPOSE: Choose one: What happens to the broken worktrees?
- [ ] [CEN] Census first, then dispose
  A lane lists each tree's branch and tip and whether that tip exists anywhere else. It repairs before pruning, and stops on any orphan tip.
  - [ ] [AUTO] Dispose everything the census clears
    Anything with an orphan tip comes back to you.
  - [ ] [ASK] Show me the census first
- [ ] [ALL] Dispose all now
  Fast. Loses any orphan tips.
- [ ] [LVE] Leave them
  Costs disk and leaves clutter. Nothing is lost.

## ¶ASK_WHO: Choose one: Who runs it?
DependsOn: ASK_DISPOSE=CEN
- [ ] [OPS] team:ops (it owns scripts/)
- [ ] [DOM] manager:domain (it holds Planner's engine leftovers)
- [ ] [DIR] The director, as a lane

```json answer
{
  "answers": {
    "DISPOSE": [
      "ALL"
    ]
  },
  "answeredBy": "operator",
  "answeredAt": "2026-10-28T18:35:28.169Z",
  "revision": 2
}
```
