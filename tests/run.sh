#!/usr/bin/env bash
# Each tests/t_*.src is a standalone program: it links the modules it needs and
# exits non-zero on the first failure, so this loop is the whole harness.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
for t in tests/t_*.src; do
    echo "===== $t ====="
    out="$(mktemp -d)/t.mfl"
    machin encode src/*.src "$t" > "$out"
    machin run "$out" --safe || fail=1
done
[ "$fail" = 0 ] || { echo "SUITE FAILED"; exit 1; }
echo "SUITE PASSED"
