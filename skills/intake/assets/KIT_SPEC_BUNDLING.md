# Retired

`KIT_SPEC_BUNDLING.md` is retired. Its 18 rules describe **a different machine than the one that
exists**: "the concatenation of already-published stylesheets into a single fetchable object, the
`@layer` contract that makes such an object patchable." `grep -an '@layer' idea-cli/verbs/bundle.ts`
returns 0, and `bundle.ts:1` states its own model — "walk a tree of idea-HTML files … and write a
directory." Different subject entirely, not a drifted description of the same one.

**What replaced it**: `idea bundle --help`, which is the only place the live behaviour is stated.

**Falsifier**: if the CLI ever concatenates published stylesheets under `@layer`, read this body
first rather than re-deriving the contract — the rules were written against a real design.

Body, verbatim: **`_attic/D12_RETIRED_KIT_SPEC_BUNDLING.md.txt`**.
