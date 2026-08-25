#!/usr/bin/env python3
"""Unit tests for the version algebra. No I/O, no network — pure functions.

Run:  python3 __tests__/version-algebra.test.py     ->  exit 0 all pass / 1 any fail

Every case in "the five behaviours" block is quoted verbatim from the owner's ruling as carried in
builds/publisher-html_CONTEXT_PACK.md §3. If one of them is edited, the ruling changed and the edit
needs to say so.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _version as V  # noqa: E402

FAILED = []
PASSED = [0]


def eq(label, got, want):
    if got == want:
        PASSED[0] += 1
        print("  ok   %s -> %r" % (label, got))
    else:
        FAILED.append(label)
        print("  FAIL %s -> %r, wanted %r" % (label, got, want))


def raises(label, fn, needle):
    try:
        fn()
    except V.VersionError as exc:
        if needle in str(exc):
            PASSED[0] += 1
            print("  ok   %s refuses, message names the fix" % label)
        else:
            FAILED.append(label)
            print("  FAIL %s refused but message lacks %r: %s" % (label, needle, exc))
        return
    except Exception as exc:  # noqa: BLE001
        FAILED.append(label)
        print("  FAIL %s raised the wrong type: %r" % (label, exc))
        return
    FAILED.append(label)
    print("  FAIL %s did not refuse" % label)


def nxt(cur, mode="default", fork=None):
    current = V.parse(cur) if cur else None
    segs, _note = V.next_version(current, mode, fork)
    return V.render(segs)


print("== parse / render round-trip ==")
for s in ["1", "1.2", "1.2.3", "1.2.3.beta", "1.2.3.beta.2", "1.2.3.branch-A.1"]:
    eq("parse+render %s" % s, V.render(V.parse(s)), s)
eq("segments are ints where numeric", V.parse("1.2.beta.3"), [1, 2, "beta", 3])
raises("parse('')", lambda: V.parse(""), "starts with a number")
raises("parse('v1')", lambda: V.parse("v1"), "starts with a number")
raises("parse('1..2')", lambda: V.parse("1..2"), "starts with a number")

print()
print("== the five behaviours (CONTEXT_PACK §3, verbatim cases) ==")
# default — deepest position. Numeric tail => increment; non-numeric => append .2
eq("default 1.2.3", nxt("1.2.3"), "1.2.4")
eq("default 1.2.3.beta", nxt("1.2.3.beta"), "1.2.3.beta.2")
eq("default 1.2.3.beta.2", nxt("1.2.3.beta.2"), "1.2.3.beta.3")
eq("default 1", nxt("1"), "2")
# --bump — RELATIVE: one level shallower than current depth. The only depth-dependent flag.
eq("--bump 1.2.3", nxt("1.2.3", "bump"), "1.3")
eq("--bump 1.2.3.4 (depth 4 -> position 3)", nxt("1.2.3.4", "bump"), "1.2.4")
eq("--bump 1.2 (depth 2 -> position 1)", nxt("1.2", "bump"), "2")
eq("--bump 1 (already shallowest)", nxt("1", "bump"), "2")
# --minor — position 2, absolute
eq("--minor 1.2.3", nxt("1.2.3", "minor"), "1.3")
eq("--minor 1.2.3.4.5 (still position 2)", nxt("1.2.3.4.5", "minor"), "1.3")
eq("--minor 1 (position 2 does not exist yet -> starts at 1)", nxt("1", "minor"), "1.1")
eq("--minor then default deepens the trunk", nxt("1.1"), "1.2")
# --major — position 1, absolute
eq("--major 1.2.3", nxt("1.2.3", "major"), "2")
eq("--major 1.2.3.beta.7", nxt("1.2.3.beta.7", "major"), "2")
# --fork <name> — appends a named branch segment starting at 1
eq("--fork mybranch 1.2.3", nxt("1.2.3", "fork", "mybranch"), "1.2.3.mybranch.1")
eq("--fork then default walks it", nxt("1.2.3.mybranch.1"), "1.2.3.mybranch.2")
eq("016 §111 branch-A", nxt("1.2.3", "fork", "branch-A"), "1.2.3.branch-A.1")
eq("016 §111 branch-B", nxt("1.2.3", "fork", "branch-B"), "1.2.3.branch-B.1")

print()
print("== --bump is depth-dependent and --minor is not (they only LOOK alike on 1.2.3) ==")
eq("--bump 1.2.3.4", nxt("1.2.3.4", "bump"), "1.2.4")
eq("--minor 1.2.3.4", nxt("1.2.3.4", "minor"), "1.3")

print()
print("== first publish ==")
eq("nothing published, no flag", nxt(None), "1")
eq("nothing published, --major", nxt(None, "major"), "1")
eq("nothing published, --minor", nxt(None, "minor"), "1")
eq("increment_at past the end pads with zeros",
   V.render(V.increment_at(V.parse("1"), 3)), "1.0.1")
raises("nothing published, --fork", lambda: nxt(None, "fork", "x"),
       "Publish it once with no flag")
raises("--fork with no name", lambda: nxt("1.2.3", "fork", None), "--fork needs a branch NAME")
raises("--fork 1abc", lambda: nxt("1.2.3", "fork", "1abc"), "--fork needs a branch NAME")

print()
print("== ordering: which published version is 'current' ==")
P = lambda *ss: [V.parse(s) for s in ss]  # noqa: E731
eq("latest of 1,2,10 is 10 (numeric, not lexical)",
   V.render(V.latest(P("1", "2", "10"))), "10")
eq("latest of 1.2, 1.10 is 1.10", V.render(V.latest(P("1.2", "1.10"))), "1.10")
eq("a deeper version off the same tip is later",
   V.render(V.latest(P("1.2.3", "1.2.3.beta.1"))), "1.2.3.beta.1")
eq("but a higher trunk beats a branch",
   V.render(V.latest(P("1.3", "1.2.3.beta.1"))), "1.3")
eq("trunk wins the tie at equal depth",
   V.render(V.latest(P("1.2.3", "1.2.beta"))), "1.2.3")
eq("latest of nothing", V.latest([]), None)

print()
print("== reference vs resolved (016 §'Connecting Identity to Address') ==")
R = lambda new, pub: [V.render(p) or "(bare)"                       # noqa: E731
                      for p in V.reference_prefixes(V.parse(new), P(*pub))]
eq("1.2.4 with 1.2.3 published answers 1.2, 1 and bare",
   R("1.2.4", ["1.2.3"]), ["1.2", "1", "(bare)"])
eq("1.2.4 published alongside a HIGHER 1.3 answers only 1.2",
   R("1.2.4", ["1.2.3", "1.3"]), ["1.2"])
eq("1.2.4 alongside a higher 2 answers 1.2 and 1 but not bare",
   R("1.2.4", ["1.2.3", "2"]), ["1.2", "1"])
eq("a FORK answers only its own branch reference, never the trunk's",
   R("1.2.3.staging.1", ["1.2.3"]), ["1.2.3.staging"])
eq("a fork's second build still answers only its branch",
   R("1.2.3.staging.2", ["1.2.3", "1.2.3.staging.1"]), ["1.2.3.staging"])
eq("a TRUNK build is not outranked by a longer branch version",
   R("1.2.4", ["1.2.3.staging.9"]), ["1.2", "1", "(bare)"])
eq("v1, first publish ever, answers bare", R("1", []), ["(bare)"])
eq("v1 when v2 already exists answers nothing", R("1", ["2"]), [])

print()
print("== branch_floor ==")
eq("branch_floor 1.2.3", V.branch_floor(V.parse("1.2.3")), 0)
eq("branch_floor 1.2.3.staging.1", V.branch_floor(V.parse("1.2.3.staging.1")), 4)
eq("branch_floor of a fork off a fork",
   V.branch_floor(V.parse("1.2.a.1.b.1")), 5)

print()
print("-- %d passed, %d failed" % (PASSED[0], len(FAILED)))
sys.exit(1 if FAILED else 0)
