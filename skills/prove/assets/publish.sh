#!/usr/bin/env bash
#  publish — move a directory to an address, give it a version, and refuse to lie about what is
#  there.
#
#  USAGE
#    publish.sh <dir> [--to <target>] [version flag] [--as <name>] [--dry-run] [--flat] [--force]
#
#  START HERE. This is the whole common case:
#
#    publish.sh ./study.bundle              first run  -> study.v1/ and study/
#    publish.sh ./study.bundle              next run   -> study.v2/ and study/  (study/ moves)
#    publish.sh ./study.bundle --dry-run    print the plan, write nothing
#
#  You point it at a DIRECTORY, not a file — `bundle` writes one, and everything in it publishes
#  together so the relative links inside it keep working. The directory's name becomes the
#  published name (a trailing `.bundle` is dropped); `--as <name>` overrides it.
#
#  WHERE IT GOES
#    --to s3://bucket/prefix     an S3 bucket
#    --to ./out                  a local folder — same layout, same guard, no AWS. Rehearse here.
#    (omitted)                   the bucket in your project .env (PROVE_S3_BUCKET). Never guessed:
#                                if there is none you get exit 2 naming the key to set.
#
#  VERSIONS — every flag names a POSITION to truncate to, then increments there
#    (no flag)         the deepest position     1.2.3 -> 1.2.4      1.2.3.beta -> 1.2.3.beta.2
#    --bump            one level SHALLOWER      1.2.3 -> 1.3        1.2.3.4    -> 1.2.4
#    --minor           position 2               1.2.3 -> 1.3
#    --major           position 1               1.2.3 -> 2
#    --fork <name>     a named branch, at 1     1.2.3 -> 1.2.3.<name>.1
#  --bump is the only one that depends on how deep you already are. The current version is read
#  from the TARGET, not from a file you maintain — publish keeps no local state.
#
#  TWO KINDS OF ADDRESS, and you get both on every run
#    study.v1.2.4/    RESOLVED  — exact, immutable, --force never applies. Pin this in anything
#                                 that must render the same way in a year.
#    study.v1.2/      REFERENCE — "latest compatible with 1.2". Moves forward when you publish
#    study.v1/                    again, which is how a fix reaches a page nobody will recompose.
#    study/           REFERENCE — plain latest. The link to send someone.
#  A fork answers ONLY its own branch reference: publishing 1.2.3.wip.1 never moves study/.
#
#  OTHER FLAGS
#    --dry-run     print the plan and the exact addresses, write nothing.
#    --force       replace a REFERENCE that holds unexpected bytes. Never applies to a resolved
#                  address; if you need different bytes, publish a new version.
#    --flat        no unit directory, no version — publish the filenames exactly as they are.
#                  This is the kit path (proof-blocks.v2.css already carries its own version).
#    --as <name>   publish under a name other than the directory's.
#
#  EXIT  0 clean · 1 refused (an address holds different bytes, or a published address does not
#  resolve) · 2 misconfigured (no target, bad directory, contradictory flags).
#
#  It never DELETES, and it never TRANSFORMS. Input bytes and output bytes are identical, which is
#  what makes "is what I have what is published?" answerable with a checksum. An unpublish is a
#  separate, deliberate act, because "publish cleaned up the address I was still sharing" is not
#  recoverable.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/_prove-s3-env.sh"

dir=""
target=""
pass=()
while [ $# -gt 0 ]; do
  case "$1" in
    --to) target="${2:?--to needs a target}"; shift 2;;
    --to=*) target="${1#--to=}"; shift;;
    --fork) pass+=(--fork "${2:?--fork needs a branch name, e.g. --fork staging}"); shift 2;;
    --fork=*) pass+=(--fork "${1#--fork=}"); shift;;
    --as) pass+=(--as "${2:?--as needs a name}"); shift 2;;
    --as=*) pass+=(--as "${1#--as=}"); shift;;
    --dry-run|--force|--bundle|--single-file|--no-verify|--flat|--bump|--minor|--major)
      pass+=("$1"); shift;;
    -h|--help) sed -n '2,60p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0;;
    -*) echo "publish: unknown flag $1" >&2
        echo "  Run  publish.sh --help  for the whole surface. The common case is:" >&2
        echo "    publish.sh <dir> [--to <target>] [--bump|--minor|--major|--fork <name>]" >&2
        exit 2;;
    *) [ -z "$dir" ] && dir="$1" || { echo "publish: unexpected argument $1" >&2
        echo "  publish takes ONE directory. To publish several things, publish each directory" >&2
        echo "  separately — each gets its own name and its own version line." >&2
        exit 2; }; shift;;
  esac
done

if [ -z "$dir" ]; then
  echo "publish: name the directory to publish." >&2
  echo "  publish.sh <dir> [--to <target>]        e.g.  publish.sh ./study.bundle" >&2
  echo "  publish.sh --help                       the whole surface, with examples" >&2
  exit 2
fi
if [ ! -d "$dir" ]; then
  if [ -f "$dir" ]; then
    echo "publish: $dir is a file, and publish moves a DIRECTORY." >&2
    echo "  Everything published together keeps its relative links working, which one file" >&2
    echo "  cannot promise. Put it in a directory and publish that:" >&2
    echo "    mkdir -p ./$(basename "${dir%.*}") && cp $dir \$_/ && publish.sh ./$(basename "${dir%.*}")" >&2
  else
    echo "publish: no such directory: $dir" >&2
  fi
  exit 2
fi

# No target given: fall back to the project's configured bucket. If there is none, say which key to
# set — never invent one. A publisher that guesses is a publisher that one day puts an internal page
# in a bucket nobody meant to share.
if [ -z "$target" ]; then
  if [ -n "${PROVE_S3_BUCKET:-}" ]; then
    target="s3://${PROVE_S3_BUCKET}/${PROVE_S3_PREFIX}"
  else
    echo "publish: no target. Pass --to s3://<bucket>/<prefix> or --to <dir>, or set" >&2
    echo "  PROVE_S3_BUCKET=<bucket> (and optionally PROVE_S3_PREFIX, PROVE_S3_REGION)" >&2
    echo "  in your project's .env. No bucket is ever inferred." >&2
    echo "  To try it with no AWS at all:  publish.sh $dir --to ./out" >&2
    exit 2
  fi
fi

exec python3 "$here/_publish.py" "$dir" "$target" \
  --profile "${PROVE_S3_PROFILE:-}" --region "${PROVE_S3_REGION}" \
  ${pass[@]+"${pass[@]}"}
