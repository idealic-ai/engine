#!/usr/bin/env python3
"""Version algebra for publish — no I/O, no S3, no filesystem. Just strings and ordering.

A version is dot-separated segments, each either an integer or a NAME (a branch label):

    1        1.2        1.2.3        1.2.3.staging.1

Every publish flag names a POSITION TO TRUNCATE TO, then increments there. That is the whole
model; the flags differ only in which position they pick.

    (none)          the deepest position          1.2.3 -> 1.2.4      1.2.3.beta -> 1.2.3.beta.2
    --bump          one level SHALLOWER           1.2.3 -> 1.3        1.2.3.4    -> 1.2.4
    --minor         position 2, absolute          1.2.3 -> 1.3
    --major         position 1, absolute          1.2.3 -> 2
    --fork <name>   append a named branch at 1    1.2.3 -> 1.2.3.<name>.1

`--bump` is the only depth-DEPENDENT flag; the rest name an absolute position. On 1.2.3 it happens
to agree with --minor, which is why the two look redundant on a three-segment version and stop
looking redundant the moment the version is four deep.

A NAME segment carries an implicit ordinal of 1 — `1.2.3.beta` IS `1.2.3.beta.1` — which is why
incrementing at a named position appends `.2` rather than trying to increment a word. That is not a
special case invented here: 016_agent_meta.md §"Autonomous Evolution and Versioning" writes the
branched versions as `1.2.3.branch-A.1` / `1.2.3.branch-B.1`, ordinal included.

REFERENCE vs RESOLVED (016 §"Connecting Identity to Address") is the other half of this file.
A *resolved* version is exact and immutable. A *reference* is a query — "latest compatible with 1.2"
— and it moves. `reference_prefixes` computes which reference addresses a newly published version
becomes the answer to, and it is deliberately conservative in one place: a version carrying a branch
name NEVER answers a trunk reference. `1.2.3.staging.1` answers `1.2.3.staging` and nothing above it,
because a fork whose bytes silently became "the latest 1.2" would defeat the entire reason to fork.
"""
import re

NAME_RE = re.compile(r"^[A-Za-z][0-9A-Za-z_-]*$")
VERSION_RE = re.compile(r"^[0-9]+(\.[0-9A-Za-z_-]+)*$")


class VersionError(ValueError):
    """Raised with a message that names the fix, never only the fault."""


def parse(s):
    """'1.2.3.beta' -> [1, 2, 3, 'beta']. Ints stay ints so ordering is numeric, not lexical."""
    if not VERSION_RE.match(s or ""):
        raise VersionError(
            "%r is not a version. A version starts with a number and is dot-separated: "
            "1, 1.2, 1.2.3, 1.2.3.staging.1" % (s,))
    out = []
    for seg in s.split("."):
        out.append(int(seg) if seg.isdigit() else seg)
    return out


def render(segs):
    return ".".join(str(x) for x in segs)


def is_trunk(segs):
    """All-numeric. A trunk version is the only kind that can answer an unqualified reference."""
    return all(isinstance(x, int) for x in segs)


def _sort_key(segs):
    """Total order. A numeric segment OUTRANKS a named one at the same position.

    A named segment is a divergence, not a successor, so `1.2.3` ranks above `1.2.beta` and the
    trunk wins ties — which is what makes `max(published)` mean "the tip of the trunk" whenever a
    trunk tip exists at that depth, and therefore what stops an unflagged publish from silently
    continuing somebody else's branch.
    """
    key = []
    for seg in segs:
        if isinstance(seg, int):
            key.append((1, seg, ""))
        else:
            key.append((0, 0, seg))
    return key


def compare(a, b):
    ka, kb = _sort_key(a), _sort_key(b)
    return (ka > kb) - (ka < kb)


def latest(versions):
    """The current version: deepest-then-highest. None for an empty set (nothing published yet)."""
    if not versions:
        return None
    return max(versions, key=_sort_key)


def increment_at(segs, position):
    """Truncate to `position` segments, then increment there. The single primitive under every flag.

    Numeric at that position  -> that number + 1, everything deeper dropped.
    Named   at that position  -> the position is kept and `.2` appended, because a name's implicit
                                 ordinal is 1 and the successor of an implicit 1 is an explicit 2.
    """
    if position < 1:
        raise VersionError("position must be >= 1")
    if position > len(segs):
        # The position does not exist yet, so it holds an implicit 0 and its successor is 1:
        # 1 --minor -> 1.1. Refusing here instead would make the trunk unable to ever grow deeper
        # (1 -> 2 -> 3 forever, all depth 1), which would leave --bump — the one depth-dependent
        # flag — with nothing it could ever mean.
        segs = list(segs) + [0] * (position - len(segs))
    head = segs[:position]
    last = head[-1]
    if isinstance(last, int):
        return head[:-1] + [last + 1]
    return head + [2]


def next_version(current, mode="default", fork_name=None):
    """current: a segment list or None (nothing published). -> (segments, note-for-the-human).

    The note is returned rather than printed because this module does no I/O; the caller prints it.
    It exists so a run that quietly did something depth-dependent says so on the terminal.
    """
    if current is None:
        if mode == "fork":
            raise VersionError(
                "nothing is published under this name yet, so there is no version to fork from.\n"
                "  Publish it once with no flag (that mints v1), then --fork %s."
                % (fork_name or "<name>"))
        note = "first publish" if mode == "default" else \
               "first publish — --%s has nothing to increment" % mode
        return [1], note

    if mode == "fork":
        if not fork_name or not NAME_RE.match(fork_name):
            raise VersionError(
                "--fork needs a branch NAME: letters/digits/-/_ starting with a letter, "
                "e.g. --fork staging. Got %r." % (fork_name,))
        return list(current) + [fork_name, 1], "forked off %s" % render(current)

    if mode == "major":
        return increment_at(current, 1), None
    if mode == "minor":
        if len(current) < 2:
            return increment_at(current, 2), \
                "--minor on %s: position 2 did not exist yet, so it starts at 1" % render(current)
        return increment_at(current, 2), None
    if mode == "bump":
        depth = len(current)
        if depth < 2:
            return increment_at(current, 1), \
                "--bump on %s: already at the shallowest position" % render(current)
        return increment_at(current, depth - 1), \
            "--bump is relative: one level shallower than %s (depth %d)" % (render(current), depth)
    if mode == "default":
        return increment_at(current, len(current)), None
    raise VersionError("unknown version mode %r" % (mode,))


def branch_floor(segs):
    """Shortest prefix length that still contains every named segment.

    A reference shorter than this would be a trunk reference, and a branch must never answer one.
    """
    floor = 0
    for i, seg in enumerate(segs):
        if not isinstance(seg, int):
            floor = i + 1
    return floor


def reference_prefixes(new, published):
    """Which reference addresses does `new` become the answer to?

    Returns prefix segment-lists LONGEST FIRST, including the empty list (the unqualified "latest")
    when `new` is on the trunk and is the highest trunk version there is.

    A prefix P is answered by `new` when both hold:
      *  every version already published under P that is BRANCH-COMPATIBLE with P is <= new.
         Branch-compatible means: V introduces no named segment that P does not already contain.
         Without that clause `1.2.3.staging.1` would outrank `1.2.4` for the reference `1.2` purely
         by being longer, and a staging build would start serving as the latest release.
      *  P is at least as deep as `new`'s branch floor — see branch_floor().
    """
    floor = branch_floor(new)
    out = []
    for plen in range(len(new) - 1, floor - 1, -1):
        p = new[:plen]
        beaten = True
        for v in published:
            if v[:plen] != p or len(v) < plen:
                continue
            if branch_floor(v) > plen:  # v lives on a branch P did not ask for
                continue
            if compare(v, new) > 0:
                beaten = False
                break
        if beaten:
            out.append(p)
    return out
