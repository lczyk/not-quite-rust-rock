#!/usr/bin/env bash
# override-build for the `chisel` part: clone the chisel-releases
# definitions ourselves (so the part itself is source-less), then
# chisel-cut the GCC + libc toolchain slices the rock needs for
# linking.
#
# Unlike the LLVM rock this does NOT cut rustc-1.93 -- rustc, rust-std
# and the cranelift codegen backend come from the published cranelift
# release (see hack/cranelift_override_build.sh). The slices the LLVM
# rock got transitively via rustc-1.93 are listed here explicitly:
# libc6 + libgcc-s1 (runtime libs) and base-files_tmp (the /tmp dir
# rustc needs for codegen scratch -- without it every compile fails
# with "couldn't create a temp dir").
#
# `chisel cut` is wrapped in hack/chisel_cut.sh to retry on the
# intermittent "expected digest ..." flake from the ubuntu archive.

set -euo pipefail

CHISEL_RELEASES_BRANCH=ubuntu-26.04
CHISEL_RELEASES_DIR=$(mktemp -d --suffix=-chisel-releases)
git clone --depth 1 --branch "$CHISEL_RELEASES_BRANCH" \
    https://github.com/canonical/chisel-releases.git \
    "$CHISEL_RELEASES_DIR"

bash "$CRAFT_PROJECT_DIR/hack/chisel_cut.sh" \
    "$CHISEL_RELEASES_DIR" \
    libgcc-14-dev_core \
    libc6_libs \
    libgcc-s1_libs \
    base-files_chisel \
    base-files_release-info \
    base-files_tmp
