# Remix — Authoring Standards

Standards for the kit and the pages built against it. The honesty invariants (`¶INV_DS_*`, in `SKILL.md`) are the law; these are the coding conventions that keep them true.

- **Reference the kit, never retype it.** A page links the kit files; it does not paste a copy of the CSS/JS inline. A second copy is a second source of truth and forks from the real one the moment the kit ships a fix. (`page` mode declares inline-vs-linked *on the page* — inline is a deliberate frozen specimen, not a default.)
- **Colour is a claim, never decoration.** Every colour that carries meaning has a legend and a real referent, and a non-colour channel beside it. If you cannot name the fact a colour encodes, remove the colour.
- **A number on a page is a measured number.** No illustrative values, no lorem, no fabricated demo of a real behaviour. If you did not measure it, you do not have it — say so (`couldNotEstablish`).
- **Register a channel before you use it.** New channel → a `REGISTRY.md` row (`channel · values · meaning · reserved-for`) before dispatch. Reusing an existing channel for a new meaning is a collision, not a shortcut.
- **A stylesheet may only make cuts that need no announcement.** Wrapping, scrolling, ellipsizing is the stylesheet's; *shortening the text* is the author's. `overflow:hidden` that swallows prose is a governance violation.
- **Assert the loss, not its neighbour.** A check asserts the thing the reader loses (clipped prose, ink-on-ink), never a proxy that usually accompanies it. Print a control before every measurement — one trap manufactures failures, its inverse manufactures passes.
- **A finding that recurs becomes a gate.** Instruction is not the lever; the slot is. When `critique` classes a recurring geometry defect, hand it to a check — don't re-document it.
- **Comments follow the repo rule.** Default to none; a `¶INV_DS_*` pointer is fine, an incident narrative is not.
