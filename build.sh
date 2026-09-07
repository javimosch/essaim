#!/usr/bin/env bash
# Mint the canonical .mfl from the loose .src sources, then build the binary.
#
# The order in sources.txt is DEPENDENCY order, not alphabetical: MFL does not
# hoist type declarations across files, so a struct with a field of another
# struct's type must be encoded after it.
set -euo pipefail
cd "$(dirname "$0")"
mapfile -t SRC < sources.txt
machin encode "${SRC[@]}" > essaim.mfl
machin build essaim.mfl
echo "built ./essaim"
