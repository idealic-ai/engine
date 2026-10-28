### ¶FMT_FILE_LINK

**When to use**: EVERY reference to a file/artifact — in chat or in a `.md` artifact — renders as a **labeled clickable link**, never a bare URL and never a dead relative path. Labeled links now render clickable in-terminal (the old bare-URL mandate existed only because they didn't).

**Rules** (smart-by-type):
*   **Editable** (code, `.md`, `.ts`/`.js`, `.json`, session artifacts, configs) → `[<label>](cursor://file/<abs-path>)` — opens in the editor.
*   **Viewable** (images `.png`/`.jpg`, `.pdf`, `.html`) → `[<label>](file:///<abs-path>)` — opens in the default viewer (Preview, browser). (`file://` opens Finder for editable files — so only use it for view-only kinds.)
*   **Label** = the basename or a short description (`[EDIT_SKILL.md]`, `[the debrief]`).
*   **Absolute path always** (resolve `~`/relative). Never a bare `cursor://…` / `file://…` blob in the prose.

```markdown
See [EDIT_SKILL.md](cursor://file/Users/me/proj/sessions/X/EDIT_SKILL.md).
Overlay: [overlay-3.png](file:///Users/me/proj/out/overlay-3.png).
```

**Anti-pattern**: a bare `cursor://file/…` URL dumped in text; a non-clickable relative path (`sessions/X/foo.md`); `file://` for a code file (opens Finder, not the editor).
