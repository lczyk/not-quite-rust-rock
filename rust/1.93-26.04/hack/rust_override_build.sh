#!/usr/bin/env bash
# override-build for the `rust` part: clone the chisel-releases
# definitions ourselves (so the part itself is source-less), then
# chisel-cut the slices we want and surface `rustc-1.93` as `rustc`
# in the rock's PATH.
#
# `chisel cut` is wrapped in hack/chisel_cut.sh to retry on the
# intermittent "expected digest ..." flake from the ubuntu archive.

set -euo pipefail

CHISEL_RELEASES_BRANCH=ubuntu-26.04
CHISEL_RELEASES_DIR=$(mktemp -d --suffix=-chisel-releases)
git clone --depth 1 --branch "$CHISEL_RELEASES_BRANCH" \
    https://github.com/canonical/chisel-releases.git \
    "$CHISEL_RELEASES_DIR"

# Hot-patch the cloned rustc-1.93 slice to drop the `gcc_gcc:`
# dependency. Upstream lists it under slices.rustc.essential, which
# would pull a full gcc into the rock; we plan to keep the rock
# gcc-free, so strip the line before `chisel cut` sees it.
sed -i -E '/^[[:space:]]+gcc_gcc:[[:space:]]*$/d' \
    "$CHISEL_RELEASES_DIR/slices/rustc-1.93.yaml"

bash "$CRAFT_PROJECT_DIR/hack/chisel_cut.sh" \
    "$CHISEL_RELEASES_DIR" \
    rustc-1.93_rustc \
    base-files_chisel \
    base-files_release-info

# rustc-1.93 is not the default rustc for this base; expose it as `rustc`.
ln -s rustc-1.93 "$CRAFT_PART_INSTALL"/usr/bin/rustc
