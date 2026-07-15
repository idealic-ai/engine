#!/usr/bin/env bash
# JSON Schema (draft 2020-12 subset) validator — thin wrapper over validate.js.
# Usage: validate.sh <schema-file> <instance-file>
#        validate.sh --schema-stdin <instance-file>   (schema read from stdin)
# Exit: 0 valid, 1 invalid (errors on stderr), 2 usage/malformed input.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec node "$DIR/validate.js" "$@"
