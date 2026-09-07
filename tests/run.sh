#!/usr/bin/env bash
# Each tests/t_*.src is a standalone program: it links the library modules and
# exits non-zero on the first failure, so this loop is the whole harness.
# src/main.src is excluded because it owns main() -- the test provides its own.
set -uo pipefail
cd "$(dirname "$0")/.."
mapfile -t ALL < sources.txt
LIB=()
for f in "${ALL[@]}"; do [ "$f" = "src/main.src" ] || LIB+=("$f"); done
# Isolate anything that touches daemon state: without this the daemon suite
# reads the developer's real ~/.essaim registry and sees torrents it never added.
export ESSAIM_HOME="$(mktemp -d)/essaim-test-home"
trap 'rm -rf "$ESSAIM_HOME"' EXIT
fail=0
for t in tests/t_*.src; do
    out="$(mktemp -d)/t.mfl"
    if ! machin encode "${LIB[@]}" "$t" > "$out" 2>/tmp/essaim-enc.err; then
        echo "===== $t ===== ENCODE FAILED"; cat /tmp/essaim-enc.err; fail=1; continue
    fi
    echo "===== $t ====="
    machin run "$out" --safe || fail=1
done
# the module suites above never touch the built binary, so stdout shape is
# checked separately -- but only if a binary exists, so `./tests/run.sh` still
# works on a clean checkout before the first build.
if [ -x ./essaim ]; then
    echo; echo "===== tests/cli.sh ====="
    ./tests/cli.sh || fail=1
else
    echo; echo "===== tests/cli.sh ===== SKIPPED (no ./essaim -- run ./build.sh)"
fi
[ "$fail" = 0 ] || { echo; echo "SUITE FAILED"; exit 1; }
echo; echo "SUITE PASSED"
