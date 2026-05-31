#!/usr/bin/env bash
# Compute single sha256 over all local inputs that affect the rock build.
# Stdout: hex digest only.
set -euo pipefail

cd "$(dirname "$0")/.."

INPUTS=(
    rockcraft.yaml
    hack/chisel_cut.sh
    hack/chisel_override_build.sh
    hack/cranelift_override_build.sh
)

sha256sum "${INPUTS[@]}" | sha256sum | cut -d' ' -f1
