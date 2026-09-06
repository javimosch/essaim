#!/usr/bin/env bash
# Mint the canonical .mfl from the loose .src sources, then build the binary.
set -euo pipefail
cd "$(dirname "$0")"
machin encode src/*.src > essaim.mfl
machin build essaim.mfl
echo "built ./essaim"
