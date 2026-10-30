# Handbook (fixture: the "Who owns each folder" section of kit handbook/README.md at a63569b6d)

## Who owns each folder

Each folder under `handbook/` has one owner, the lane that gives the go on changes there. The hub, Handbook, owns the root of `handbook/` and holds any folder no lane has claimed yet; a lane claims a folder for its own domain by changing its row here. In a folder another lane owns, the hub still reviews structure and word limits. `node handbook/handbook/inventory.mjs --check` fails when a folder has no row.

| Folder | Owner |
| --- | --- |
| `handbook/` | docs:handbook |
| `handbook/agent/` | domain:agent |
| `handbook/_generated/` | docs:handbook |
| `handbook/_plan/` | docs:handbook |
| `handbook/handbook/` | docs:handbook |
| `handbook/handbook/specimens/` | docs:handbook |
| `handbook/handbook/vocabulary/` | docs:handbook |
| `handbook/kernel/` | core:kernel |
| `handbook/language/` | domain:language |
| `handbook/realm/` | core:realm |
| `handbook/start/` | docs:handbook |
| `handbook/market/` | core:exchange |
| `handbook/resources/` | domain:platform |
| `handbook/ui/` | core:ui |
| `handbook/worlds/` | docs:handbook, until a lane claims it |
