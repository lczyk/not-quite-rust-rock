#!/usr/bin/env bash
# override-build for the `rust` part: chisel-cut the slices we want
# out of the canonical/chisel-releases tree pulled in as the part
# source, then surface `rustc-1.93` as `rustc` in the rock's PATH.
#
# `chisel cut` is wrapped in hack/chisel_cut.sh to retry on the
# intermittent "expected digest ..." flake from the ubuntu archive.
# spellchecker: ignore rustc

set -euo pipefail

bash "$CRAFT_PROJECT_DIR/hack/chisel_cut.sh" \
    rustc-1.93_rustc \
    base-files_chisel \
    base-files_release-info

# rustc-1.93 is not the default rustc for this base; expose it as `rustc`.
ln -s rustc-1.93 "$CRAFT_PART_INSTALL"/usr/bin/rustc
