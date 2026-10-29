# await-next

The blocking primitive every agent in the fleet calls to wait for its next piece of work. A director waits on its children, a worker waits on delegation tags, a coordinator waits on both at once and takes whichever fires first.

`engine await-next` reaches it through `scripts/await-next.sh`, which prefers a project-local `tools/await-next/await-next.sh` and falls back to this copy. The fallback matters more than it sounds: the delegator finds the project root by walking up for a `.claude/` directory, and `$HOME/.claude` always exists, so for any working directory outside a project that carries its own `.claude/` the walk terminates at `$HOME` and the project-local path it would look for is one no install creates. This copy is the one that is always reachable.

## Calling it

```bash
engine await-next [timeout_seconds] [options]
```

Identity comes from the environment that `run.sh` exports, and every part of it can be overridden on the command line:

| option | environment | what it means |
|---|---|---|
| `--panes a,b` | `FLEET_MANAGES` | the panes this agent is responsible for |
| `--claims a,b` | `FLEET_CLAIMS` | delegation nouns this agent will pick up untargeted |
| `--targeted-claims a,b` | `FLEET_TARGETED_CLAIMS` | nouns it will pick up only when addressed to it |
| `--pane window:label` | `FLEET_PANE` | who this agent is, for `%target` matching |
| `--sessions-dir PATH` | — | where tags are searched (default `<cwd>/sessions`) |
| `--socket NAME` | `FLEET_SOCKET` | tmux socket (default `fleet`) |
| `--no-connect` | — | skip the coordinator's purple-layer connect, for tests |

The role is derived rather than declared. Managed panes and no claims makes a director; claims and no managed panes makes a worker; both makes a coordinator.

## What comes back

Every return is a named outcome on the first line.

| first line | exit | meaning |
|---|---|---|
| `CHILD <pane>\|<state>\|<label>\|<location>` | 0 | a managed pane wants attention; a capture JSON line and a `STATUS` line follow |
| `WORK <file>\|<tag>\|<noun>` | 0 | a delegation tag was found and claimed; a `CLAIMED` line follows |
| `FOCUSED` | 0 | the only actionable panes are ones the user has focused, so they were left alone |
| `TIMEOUT` | 0 | the ceiling was reached with nothing to report |
| `NOCHANNEL` | 2 | neither channel is available, so there is nothing to wait on |
| usage error | 1 | unknown argument, non-numeric timeout, or a timeout above the ceiling |

`TIMEOUT` is deliberately not an error. A caller loops on this command, and a heartbeat that returns non-zero makes every loop look like a failure. `NOCHANNEL` does get its own exit code, because a caller that reaches it will spin: with no panes to watch and no tag directory to read, blocking would have no event that could ever end it.

Degradations are reported on stderr as a `DEGRADED` line and never silently: `no-tmux-server`, `no-sessions-dir`, `no-fswatch-polling-tags`.

## How the wait is bounded

The ceiling is a supervisor loop, not `timeout(1)`. The loop ticks every 250 ms for `timeout` seconds and then reaps its watchers, so a hung `fswatch` or a hung `tmux wait-for` cannot outlive it even if the watcher ignores a signal. `timeout(1)` was available on the machine this was written on but only through Homebrew, and a ceiling that depends on an optional binary is not a ceiling. A caller may not ask for more than an hour.

A wake is advisory. `fleet.sh` fires `coordinator-wake` on every `unchecked`, `error` and `done` transition and its own comment says the signal is an optimisation while the sweep is truth, so a wake that resolves to nothing actionable resumes the wait instead of ending it. The sweep also runs *before* any blocking, so a notification that arrived while the agent was busy costs a scan rather than a full wait.

The work channel's claim is atomic: a `mkdir` lock around a re-verified `#delegated-X` → `#claimed-X` rewrite, so a worker that lost the race hands back nothing rather than work it does not hold.

## Two places this diverges from its predecessor

`fleet.sh coordinate-wait`, now deprecated, is the working implementation this replaces, and it differs in two ways worth knowing if you are comparing output.

It takes panes in tmux enumeration order. `docs/FLEET.md` specifies `error > unchecked > done`, and this implementation follows the document.

It pipes its pane capture through `parse_pane_content`, which is a shell function inside `fleet.sh` and not reachable as a subcommand. The capture line here is a smaller shape — `{pane, state, label, lines, tail}` — and a richer parse would mean lifting that function out of `fleet.sh` first.

## Tests

`scripts/tests/test-await-next.sh`, run by the engine's own runner. It builds an isolated tmux server per arm through `setup_test_tmux`, so nothing it does reaches a live fleet.
