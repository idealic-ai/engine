# Inbox registry (fixture)

A two-project stand-in for `skills/inbox-post/assets/INBOX_REGISTRY.md`, shaped only as far as
`_lint_scope_registry_drift` reads it: a `## Product: <name>` heading per project, and the
handbook slugId present somewhere in the text.

Its job is to make the `--all` fixture run reach the peer axis with ZERO scope-registry drift
findings, so the peer assertions are unambiguous. Drift itself is asserted elsewhere, against
the real registry.

## Product: Alpha

- Inbox Handbook: `aaa000000001`

## Product: Beta

- Inbox Handbook: `bbb000000002`
