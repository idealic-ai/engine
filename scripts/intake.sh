#!/bin/bash
# intake.sh — TOMBSTONE. `engine intake <doctor|setup|env-example>` moved to `engine env`.
#
# The credential doctor became a per-domain environment-and-secrets system:
#
#   engine intake <verb>  →  engine env <verb> --domain intake
#
# for verb in doctor, setup, env-example. There is NO deprecation shim: the old
# namespace stops existing rather than quietly forwarding.
#
# This file is NOT empty on purpose. `engine.sh` auto-dispatches to any executable
# `scripts/<subcmd>.sh`, and an emptied script returns 0 both exec'd and sourced — a
# stale caller would read SUCCESS from a command that checked nothing, which is
# strictly worse than a missing command. Every body below exits 2 and says where it went.
#
# `engine intake-announce` is a DIFFERENT, live command (scripts/intake-announce.sh).
# It is unaffected by this tombstone.
set -uo pipefail

_moved() {
  echo "engine intake $1: moved to \`engine env $1 --domain intake\`" >&2
  exit 2
}

case "${1:-}" in
  doctor)      _moved doctor ;;
  setup)       _moved setup ;;
  env-example) _moved env-example ;;
  *)
    echo "engine intake: retired — use \`engine env <doctor|setup|env-example> --domain intake\`" >&2
    exit 2
    ;;
esac
