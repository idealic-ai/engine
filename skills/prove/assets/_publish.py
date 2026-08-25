#!/usr/bin/env python3
"""Engine behind publish.sh — walk a directory, plan, refuse, write.

Invoked as:
    _publish.py <dir> <target> [--dry-run] [--force] [--flat] [--as <name>]
                               [--bump|--minor|--major|--fork <name>]
                               [--profile <awsProfile>] [--region <r>]

<target> is either  s3://<bucket>/<prefix>  or an absolute local directory.
Both take this same code path; the only thing that varies is `probe`, `put` and `list_versions`.

HTML IS THE ARTIFACT, AND A DIRECTORY IS THE UNIT. `bundle` produces a directory of self-contained
HTML; `publish` moves one and gives it a VERSION. The version belongs to the directory rather than
to each file inside it, for two reasons that both bite immediately:

  *  publish never rewrites your bytes, so it cannot rename `index.html` and then fix up the
     `<link href="css/bundle.css">` that names it. Versioning the container leaves every relative
     path inside untouched.
  *  a per-file version would let `page.v1.2.3.html` and `page.v1.2.4.html` share ONE `bundle.css`,
     so the older "immutable" address would silently render with the newer stylesheet. A resolved
     address has to pin the rendered result, not one file of it.

TWO KINDS OF ADDRESS, which is 016_agent_meta.md's reference/resolved split (§"Connecting Identity
to Address") in S3 keys:

  resolved    <unit>.v1.2.4/…      exact, immutable. --force never applies. This is the identity.
  reference   <unit>.v1.2/…        a QUERY — "latest compatible with 1.2". Moves, by design.
              <unit>.v1/…          publish mints exactly the references this version is the answer
              <unit>/…             to, and prints every one it moves.

A page holding a reference picks up a retint automatically; a page holding a resolved address keeps
its bytes forever. Both wants, no flag, no choice to get wrong.

THE FOUR GUARANTEES, and where each one lives in this file:

  content-addressed      an address whose name carries its own sha12 is a CONTENT address;
                         re-publishing identical bytes is a no-op, never a second write   -> plan()
  refuses to overwrite   an immutable address holding different bytes is an ERROR, and the run
                         stops BEFORE anything is written                                  -> main()
  complete or nothing    every regular file under <dir> is in the plan; there is no skip
                         list and no silent omission                                       -> walk()
  addresses resolve      after an S3 run, every address is read back the way an anonymous
                         reader reads it                                                   -> verify()

--flat turns unit versioning off and publishes the directory's own filenames verbatim. That is the
KIT path: kit files already carry their versions in their names (proof-blocks.v2.css) and 142
published pages reference them there, so nesting them under a unit directory would 404 every one.

Publishing does NOT transform. Input bytes and output bytes are identical, which is what makes
"is what I have what is published?" answerable with a checksum. --bundle and --single-file are
separate operations, off by default, and they are the only things here that may alter bytes.
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _version as V  # noqa: E402

CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".woff2": "font/woff2",
    ".woff": "font/woff",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".gif": "image/gif",
    ".txt": "text/plain; charset=utf-8",
    ".map": "application/json; charset=utf-8",
}
# A file type with no entry is still published — it just goes up as an opaque stream. Refusing to
# publish an unrecognised extension would be the "silently short list" failure in a new costume.
DEFAULT_TYPE = "application/octet-stream"

EXIT_OK, EXIT_REFUSED, EXIT_CONFIG = 0, 1, 2


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def walk(root):
    """Every regular file under root, relative-path sorted. No skip list, deliberately.

    A publisher that decides for itself what not to publish is a publisher whose output you cannot
    predict from its input — and an omission it makes silently is exactly how proof-module.css sat
    unpublishable while 142 files referenced it. What may be excluded is decided by whoever STAGES
    the directory, where the decision is visible, not in here where it would be invisible.
    """
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            if os.path.islink(full) and not os.path.exists(full):
                raise SystemExit("publish: broken symlink in the directory: %s" % full)
            if not os.path.isfile(full):
                continue
            out.append(os.path.relpath(full, root))
    return out


class S3Target:
    kind = "s3"

    def __init__(self, bucket, prefix, profile, region):
        self.bucket, self.prefix = bucket, prefix.strip("/")
        self.profile, self.region = profile, region
        self._pa = ["--profile", profile] if profile else []

    def __str__(self):
        return "s3://%s/%s" % (self.bucket, self.prefix)

    def key(self, rel):
        return "%s/%s" % (self.prefix, rel) if self.prefix else rel

    def url(self, rel):
        return "https://%s.s3.%s.amazonaws.com/%s" % (self.bucket, self.region, self.key(rel))

    def probe(self, rel):
        """-> None if absent, else (sha_or_None, size, lastModified). ETag is the fallback.

        S3 metadata is preferred over ETag because ETag is only the md5 for a single-part upload;
        every object this tool writes carries an explicit x-amz-meta-sha256 so the comparison is
        never guessing. Objects put by the OLD publisher carry none, so ETag-as-md5 is the bridge —
        and when neither is usable the answer is "unknown", which plan() treats as a conflict
        rather than as a match. Fail closed: a guard that can't tell must not say yes.
        """
        r = subprocess.run(
            ["aws", "s3api", "head-object", "--bucket", self.bucket, "--key", self.key(rel)]
            + self._pa + ["--output", "json"],
            capture_output=True, text=True)
        if r.returncode != 0:
            return None
        try:
            d = json.loads(r.stdout)
        except ValueError:
            # head-object succeeded but said nothing parseable. That is not "absent" — treating it
            # as absent would fail OPEN and overwrite an object we never looked at. Report it as an
            # unknown digest, which plan() already treats as a conflict.
            return (None, "", None, "")
        meta = d.get("Metadata") or {}
        sha = meta.get("sha256")
        etag = (d.get("ETag") or "").strip('"')
        return (sha, etag, d.get("ContentLength"), str(d.get("LastModified", ""))[:10])

    def put(self, src, rel, ctype, sha):
        r = subprocess.run(
            ["aws", "s3", "cp", src, "s3://%s/%s" % (self.bucket, self.key(rel))] + self._pa
            + ["--content-type", ctype, "--cache-control", "no-cache",
               "--metadata", "sha256=%s" % sha],
            capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError((r.stderr or r.stdout).strip()[:300])

    def list_versions(self, unit):
        """Which versions of <unit> are already published here? The TARGET is the ledger.

        Nothing local records the current version: not a constant in the HTML, not a state file.
        Asking the target is what makes `publish ./site` need no flags and no bookkeeping — and it
        is also how two concurrent publishers discover that they collided (016 §"Autonomous
        Evolution", the race that --fork exists to resolve) instead of silently overwriting.
        """
        pfx = (self.prefix + "/") if self.prefix else ""
        r = subprocess.run(
            ["aws", "s3api", "list-objects-v2", "--bucket", self.bucket,
             "--prefix", pfx + unit + ".v", "--delimiter", "/"] + self._pa + ["--output", "json"],
            capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError("cannot list %s: %s" % (self, (r.stderr or "").strip()[:200]))
        d = json.loads(r.stdout or "{}")
        out = []
        for cp in (d.get("CommonPrefixes") or []):
            tail = cp["Prefix"][len(pfx):].rstrip("/")
            v = version_of_dirname(tail, unit)
            if v:
                out.append(v)
        return out

    def list_keys(self, sub):
        pfx = (self.prefix + "/") if self.prefix else ""
        r = subprocess.run(
            ["aws", "s3api", "list-objects-v2", "--bucket", self.bucket,
             "--prefix", pfx + sub + "/"] + self._pa + ["--output", "json"],
            capture_output=True, text=True)
        if r.returncode != 0:
            return []
        try:
            d = json.loads(r.stdout or "{}")
        except ValueError:
            return []
        return sorted(c["Key"][len(pfx) + len(sub) + 1:] for c in (d.get("Contents") or []))


class LocalTarget:
    kind = "local"

    def __init__(self, root):
        self.root = os.path.abspath(root)

    def __str__(self):
        return self.root

    def key(self, rel):
        return rel

    def url(self, rel):
        return "file://" + os.path.join(self.root, rel)

    def probe(self, rel):
        p = os.path.join(self.root, rel)
        if not os.path.isfile(p):
            return None
        st = os.stat(p)
        return (sha256_of(p), "", st.st_size,
                datetime.date.fromtimestamp(st.st_mtime).isoformat())

    def put(self, src, rel, ctype, sha):
        dst = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(src, dst)

    def list_versions(self, unit):
        if not os.path.isdir(self.root):
            return []
        out = []
        for name in sorted(os.listdir(self.root)):
            if not os.path.isdir(os.path.join(self.root, name)):
                continue
            v = version_of_dirname(name, unit)
            if v:
                out.append(v)
        return out

    def list_keys(self, sub):
        base = os.path.join(self.root, sub)
        if not os.path.isdir(base):
            return []
        return sorted(os.path.relpath(os.path.join(dp, f), base)
                      for dp, _dn, fn in os.walk(base) for f in fn)


CAS_SEG_RE = re.compile(r"\.[0-9a-f]{12}\.")


def is_content_address(rel, sha=None):
    """Does this address name bytes? Decided from the NAME'S SHAPE, never from the bytes.

    A content address is one carrying a twelve-hex segment: `proof-blocks.v2.fb1c365fc87f.css` is
    one, `proof-blocks.v2.css` is not, and anything reading the address can tell which without
    asking this tool.

    It has to be the shape rather than a match against the bytes being published. Matching was the
    original test — `("." + sha[:12] + ".") in name` — and it inverted the guard in exactly the
    situation the guard exists for: when an address holds the WRONG bytes, the local sha no longer
    matches the name, the test returns False, the address is misread as a mutable alias, and
    --force writes straight through the one thing that must never be forced. Shape is also
    fail-closed: an ordinary filename that happens to look like a content address gets refused,
    which is the safe direction to be wrong in.
    """
    return bool(CAS_SEG_RE.search(os.path.basename(rel)))


UNIT_RE = re.compile(r"^[0-9A-Za-z][0-9A-Za-z._-]*$")


def version_of_dirname(name, unit):
    """'spacing.v1.2.4' + unit 'spacing' -> [1,2,4]. Anything else -> None.

    The version must start with a DIGIT, which is what keeps a unit legitimately named `foo.void`
    from being read as unit `foo` at version `oid`.
    """
    head = unit + ".v"
    if not name.startswith(head):
        return None
    tail = name[len(head):]
    if not tail or not tail[0].isdigit():
        return None
    try:
        return V.parse(tail)
    except V.VersionError:
        return None


def unit_name_for(root, override):
    """The published name of the unit. Directory basename unless --as says otherwise.

    A trailing `.bundle` is stripped because that is exactly what the paired `bundle` tool writes
    (`./study.bundle/`), and `study.bundle.v1` reads as a version of the bundler rather than of the
    study. Nothing else is stripped — guessing further would be the publisher deciding what your
    thing is called.
    """
    name = override or os.path.basename(os.path.normpath(root))
    if not override and name.endswith(".bundle"):
        name = name[: -len(".bundle")]
    if not UNIT_RE.match(name):
        raise SystemExit(
            "publish: %r is not usable as a published name (it becomes a URL segment).\n"
            "  Use letters, digits, dot, dash, underscore — or pass --as <name> to choose one.\n"
            "  e.g. publish %s --as spacing-study" % (name, root))
    return name


def unit_addresses(unit, new_segs, published, rels):
    """-> [(key, rel, immutable, treeLabel)] for every object this run publishes.

    One resolved tree plus one tree per reference this version answers. Each tree is a COMPLETE
    copy: a reference has to be openable at its own address with every relative link inside it
    working, which a partial tree cannot do.
    """
    items = []
    resolved_dir = "%s.v%s" % (unit, V.render(new_segs))
    for rel in rels:
        items.append(("%s/%s" % (resolved_dir, rel), rel, True, resolved_dir + "/"))
    for p in V.reference_prefixes(new_segs, published):
        ref_dir = ("%s.v%s" % (unit, V.render(p))) if p else unit
        for rel in rels:
            items.append(("%s/%s" % (ref_dir, rel), rel, False, ref_dir + "/"))
    return items


def human(n):
    return "{:,}".format(n)


def plan(files, root, target):
    """Flat plan: the directory's own relative paths ARE the addresses. The kit path."""
    return plan_items([(rel, rel, None, None) for rel in files], root, target)


def plan_items(items, root, target):
    """items: (key, sourceRel, immutableOrNone, treeLabel). immutable=None -> decide by CAS naming.

    `immutable=None` is flat mode, where an address's kind is self-describing (a name carrying its
    own sha12 is a content address). Unit mode passes it explicitly, because there the kind comes
    from WHICH TREE the object is in, not from its filename.
    """
    rows = []
    for key, rel, immutable, tree in items:
        full = os.path.join(root, rel)
        sha = sha256_of(full)
        size = os.path.getsize(full)
        ctype = CONTENT_TYPES.get(os.path.splitext(rel)[1].lower(), DEFAULT_TYPE)
        got = target.probe(key)
        if got is None:
            disp, remote = "new", None
        else:
            rsha, retag, rsize, rdate = got
            if rsha:
                known = rsha
            elif retag and len(retag) == 32 and all(c in "0123456789abcdef" for c in retag):
                # Single-part ETag == md5 of the body. Every kit asset is far under the multipart
                # threshold, so this identifies the OLD publisher's objects exactly.
                known = "md5:" + retag
            else:
                known = None
            if known and known.startswith("md5:"):
                local_md5 = hashlib.md5(open(full, "rb").read()).hexdigest()
                same = (known[4:] == local_md5)
                shown, kind = known[4:], "md5"
            elif known:
                same = (known == sha)
                shown, kind = known, "sha"
            else:
                same, shown, kind = False, "unknown", "sha"
            if same:
                disp = "same"
            elif immutable is False:
                # A REFERENCE, and this run derived it: the version algebra already established
                # that the new version outranks everything published under this prefix, so the
                # move is forward by construction and needs no --force. The guard exists because
                # the tool could not tell an intended move from an accidental one; here it can,
                # and it prints both hashes anyway so the move is on the terminal.
                disp = "move"
            else:
                disp = "ERROR"
            remote = (shown, rsize, rdate, kind)
        immovable = is_content_address(key, sha) if immutable is None else immutable
        rows.append(dict(rel=key, full=full, sha=sha, size=size, ctype=ctype,
                         disp=disp, remote=remote, tree=tree,
                         content_addressed=immovable))
    return rows


def render(rows, root, target, dry_run, force, wrote):
    w = max([len(r["rel"]) for r in rows] + [20])
    print("  plan  %s -> %s" % (root, target))
    for r in rows:
        line = " %5s  %-*s  %9s  sha %s" % (
            r["disp"], w, r["rel"], human(r["size"]), r["sha"][:8] + "…")
        if r["disp"] == "same":
            print(line + "   (already published, identical)")
        elif r["disp"] == "ERROR":
            print(line + "   address holds different bytes")
            shown, rsize, rdate, kind = r["remote"]
            # The digest KIND is stated, not implied. An object written by the old publisher carries no
            # x-amz-meta-sha256, so the only fingerprint available is its ETag (= md5 for a
            # single-part upload) — printing that as "sha" would invite a reader to compare it
            # against a sha256 and conclude the wrong thing.
            print("        published %s %s (%s B, %s)" % (
                kind, shown[:8] + "…", human(rsize) if rsize is not None else "?", rdate or "?"))
            if r["content_addressed"]:
                print("        this address is IMMUTABLE — its name pins these bytes, so different "
                      "bytes under it means corruption. --force does not apply.")
                print("        Publish a new version instead (no flag bumps the deepest position).")
            else:
                print("        --force to replace, or publish under a new address")
        elif r["disp"] == "move":
            shown, rsize, rdate, kind = r["remote"]
            print(line + "   reference moves forward")
            print("        was %s %s (%s B, %s)" % (
                kind, shown[:8] + "…", human(rsize) if rsize is not None else "?", rdate or "?"))
        else:
            print(line)
    n_new = sum(1 for r in rows if r["disp"] == "new")
    n_same = sum(1 for r in rows if r["disp"] == "same")
    n_move = sum(1 for r in rows if r["disp"] == "move")
    n_err = sum(1 for r in rows if r["disp"] == "ERROR")
    print("  ---")
    if dry_run:
        tail = "nothing written (dry run)"
    elif wrote is None:
        tail = "nothing written (refused)"
    else:
        tail = "%d written" % wrote
    moved = ", %d reference moved" % n_move if n_move else ""
    print("  %d new, %d unchanged%s, %d conflict — %s" % (n_new, n_same, moved, n_err, tail))
    return n_err


def verify(rows, target):
    """A successful PUT is not the same fact as a readable GET.

    The one invariant this whole build exists to apply — a declared address must resolve — is worth
    nothing if it is only checked at the moment of writing. So every address the run claims is read
    back the way a reader reads it: anonymously, no credential. An object that lands under a key the
    bucket policy does not serve is invisible to the uploader and a 403 to everyone else.
    """
    if target.kind != "s3":
        bad = [r for r in rows if not os.path.isfile(os.path.join(target.root, r["rel"]))]
        for r in bad:
            print(" ERROR  %s did not land at %s" % (r["rel"], target.url(r["rel"])))
        return bad
    bad = []
    for r in rows:
        url = target.url(r["rel"])
        p = subprocess.run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                            "--max-time", "20", "-I", url], capture_output=True, text=True)
        code = (p.stdout or "").strip()
        if code != "200":
            bad.append(r)
            print(" ERROR  %s reads back HTTP %s for an anonymous reader" % (r["rel"], code))
    return bad


def main(argv):
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("dir")
    ap.add_argument("target")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--bundle", action="store_true")
    ap.add_argument("--single-file", action="store_true")
    ap.add_argument("--profile", default="")
    ap.add_argument("--region", default="us-east-2")
    ap.add_argument("--no-verify", action="store_true")
    ap.add_argument("--flat", action="store_true")
    ap.add_argument("--as", dest="as_name", default="")
    ap.add_argument("--bump", action="store_true")
    ap.add_argument("--minor", action="store_true")
    ap.add_argument("--major", action="store_true")
    ap.add_argument("--fork", default="")
    a = ap.parse_args(argv)

    picked = [n for n, on in (("--bump", a.bump), ("--minor", a.minor),
                              ("--major", a.major), ("--fork", bool(a.fork))) if on]
    if len(picked) > 1:
        print("publish: %s name different positions to increment — pass one, not %d.\n"
              "  Each flag truncates the version to a position and increments there; two truncations "
              "cannot both be the answer." % (" and ".join(picked), len(picked)), file=sys.stderr)
        return EXIT_CONFIG
    mode = ("fork" if a.fork else "bump" if a.bump else "minor" if a.minor
            else "major" if a.major else "default")
    if a.flat and (picked or a.as_name):
        print("publish: --flat publishes the directory's own filenames, so there is no unit to "
              "name or version. Drop %s, or drop --flat."
              % (" / ".join(picked + (["--as"] if a.as_name else []))), file=sys.stderr)
        return EXIT_CONFIG

    if a.bundle or a.single_file:
        # Stated, not silently ignored. These are real operations with real trade-offs; shipping a
        # flag that quietly does nothing is worse than shipping no flag.
        print("publish: --bundle / --single-file are not implemented in this build. They are "
              "separate byte-transforming operations and publishing does not transform; see "
              "publish-cli_DESIGN.md §Open.", file=sys.stderr)
        return EXIT_CONFIG

    root = os.path.abspath(a.dir)
    if not os.path.isdir(root):
        print("publish: not a directory: %s" % a.dir, file=sys.stderr)
        return EXIT_CONFIG

    if a.target.startswith("s3://"):
        rest = a.target[5:].strip("/")
        if "/" not in rest and not rest:
            print("publish: --to s3://<bucket>/<prefix> — no bucket in %r" % a.target,
                  file=sys.stderr)
            return EXIT_CONFIG
        bucket, _, prefix = rest.partition("/")
        target = S3Target(bucket, prefix, a.profile, a.region)
    else:
        target = LocalTarget(a.target)

    files = walk(root)
    if not files:
        print("publish: %s holds no files — nothing to publish" % root, file=sys.stderr)
        return EXIT_CONFIG

    if a.flat:
        rows = plan(files, root, target)
    else:
        unit = unit_name_for(root, a.as_name)
        try:
            published = target.list_versions(unit)
        except RuntimeError as exc:
            print("publish: %s" % exc, file=sys.stderr)
            print("  publish reads the target to learn the current version — it keeps no local "
                  "state. Fix the credentials or the target, or pass --flat to publish the "
                  "filenames verbatim with no version at all.", file=sys.stderr)
            return EXIT_CONFIG
        current = V.latest(published)

        # Publishing identical bytes is a NO-OP, never a second write — the guarantee that lets you
        # answer "is what I have what is published?" with a checksum. Without this check the
        # version would climb on every invocation, so a nightly re-publish of an unchanged
        # directory would mint v40 and every one of those forty addresses would hold the same
        # bytes. A version that increments without a change records nothing.
        if current is not None:
            shas = {rel: sha256_of(os.path.join(root, rel)) for rel in files}

            def tree_matches(sub):
                if sorted(target.list_keys(sub)) != sorted(files):
                    return False
                return all((target.probe("%s/%s" % (sub, rel)) or (None,))[0] == shas[rel]
                           for rel in files)

            cur_dir = "%s.v%s" % (unit, V.render(current))
            # The references have to match too. Checking only the resolved tree would mean a
            # corrupted or half-written `study/` could never be healed: publish would see the
            # resolved bytes agreeing, call the run a no-op and leave the reference wrong forever.
            ref_dirs = [("%s.v%s" % (unit, V.render(p))) if p else unit
                        for p in V.reference_prefixes(current, published)]
            if all(tree_matches(d) for d in [cur_dir] + ref_dirs):
                print("  version  %s  %s — unchanged, nothing to publish" % (unit, V.render(current)))
                print("           %d file(s), byte-identical to what %s/ already holds."
                      % (len(files), cur_dir))
                print("           Edit the directory and run again; the version moves when the "
                      "bytes do.")
                entry = pick_entry(files)
                if entry:
                    print("  resolved  %s" % target.url("%s/%s" % (cur_dir, entry)))
                return EXIT_OK

        try:
            new_segs, note = V.next_version(current, mode, a.fork or None)
        except V.VersionError as exc:
            print("publish: %s" % exc, file=sys.stderr)
            return EXIT_CONFIG

        if any(v == new_segs for v in published):
            print("publish: %s.v%s is already published, so this run would overwrite a resolved "
                  "address." % (unit, V.render(new_segs)), file=sys.stderr)
            print("  Another publisher got there first. Take a branch instead of colliding:",
                  file=sys.stderr)
            print("    publish %s --fork <yourname>   ->  %s.v%s.<yourname>.1"
                  % (a.dir, unit, V.render(current) if current else "1"), file=sys.stderr)
            return EXIT_REFUSED

        refs = V.reference_prefixes(new_segs, published)
        ref_names = [("%s.v%s/" % (unit, V.render(p))) if p else (unit + "/") for p in refs]
        print("  version  %s  %s -> %s%s" % (
            unit, V.render(current) if current else "(nothing published)", V.render(new_segs),
            "   [%s]" % note if note else ""))
        if current is not None and not V.is_trunk(current) and mode == "default":
            print("           walking the '%s' branch — --major returns to the trunk"
                  % [s for s in current if not isinstance(s, int)][-1])
        print("  refs     %s" % (" ".join(ref_names) if ref_names
                                 else "(none — a higher version already answers every reference)"))
        rows = plan_items(unit_addresses(unit, new_segs, published, files), root, target)

    conflicts = [r for r in rows if r["disp"] == "ERROR"]
    # --force never applies to a content address. If the name derives from the bytes, then different
    # bytes under that name is not a decision anybody should be able to override — it is either
    # corruption or a sha256 collision, and the honest response to both is to stop.
    immovable = [r for r in conflicts if r["content_addressed"]]
    blocked = bool(conflicts) and (not a.force or bool(immovable))

    if a.dry_run or blocked:
        render(rows, root, target, dry_run=a.dry_run, force=a.force, wrote=None)
        if blocked and not a.dry_run:
            if immovable:
                print("publish: refused — %d immutable address(es) hold different bytes; --force "
                      "does not apply to an address whose name pins its bytes." % len(immovable),
                      file=sys.stderr)
            else:
                print("publish: refused — %d address(es) hold different bytes. Re-run with --force "
                      "to replace them." % len(conflicts), file=sys.stderr)
        return EXIT_REFUSED if conflicts else EXIT_OK

    wrote = 0
    for r in rows:
        if r["disp"] == "same":
            continue
        try:
            target.put(r["full"], r["rel"], r["ctype"], r["sha"])
            wrote += 1
        except Exception as exc:  # noqa: BLE001 — the message is the product here
            print(" ERROR  %s did not upload: %s" % (r["rel"], exc), file=sys.stderr)
            return EXIT_REFUSED

    render(rows, root, target, dry_run=False, force=a.force, wrote=wrote)

    if not a.no_verify:
        bad = verify(rows, target)
        if bad:
            print("publish: %d published address(es) do not resolve — the run wrote bytes but the "
                  "addresses do not answer." % len(bad), file=sys.stderr)
            return EXIT_REFUSED
        print("  verify  %d/%d addresses resolve" % (len(rows), len(rows)))

    # The URLs, last and unmissable. A publisher whose output you have to reconstruct by hand from a
    # bucket name and a key prefix has published nothing you can actually send to anyone.
    entry = pick_entry(files)
    if entry:
        seen = []
        for r in rows:
            tree = r.get("tree")
            if tree and r["rel"] == tree + entry and tree not in seen:
                seen.append(tree)
                kind = "resolved" if r["content_addressed"] else "reference"
                print("  %-9s %s" % (kind, target.url(r["rel"])))
    return EXIT_OK


def pick_entry(rels):
    """The one file a human would open. index.html wins; otherwise the shallowest single .html."""
    htmls = [r for r in rels if r.lower().endswith(".html")]
    if not htmls:
        return None
    for r in htmls:
        if os.path.basename(r).lower() == "index.html":
            return r
    return sorted(htmls, key=lambda r: (r.count(os.sep), len(r), r))[0]


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
