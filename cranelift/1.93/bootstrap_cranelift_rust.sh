#!/usr/bin/env bash
# Bootstrap rust w/ a cranelift-only librustc_driver (no libLLVM
# DT_NEEDED), against the rust X.Y.Z source.
#
# Three pieces of magic, all hard-won from the spike documented in
# cranelift_plan.md (kept out-of-tree, ralph-loop scratch):
#
#   1. patch the aarch64 target spec to lower max_atomic_width from
#      128 to 64. cranelift's aarch64 backend doesn't implement
#      128bit atomics; without this, `core` won't compile.
#
#   2. set CG_CLIF_FORCE_GNU_AS=1 when compiling cranelift itself,
#      so the cranelift backend uses the system `as` binary for
#      global_asm! / asm! instead of shelling out to an LLVM-backed
#      rustc (which doesn't exist in our cranelift-only config).
#
#   3. build `--stage 1`, not `--stage 2`. stage1 rustc is compiled
#      BY stage0 (the upstream rust 1.X tarball, which has LLVM),
#      so stage1's librustc_driver is small + optimised. but stage1
#      itself has codegen-backends = ["cranelift"] so the shipped
#      rustc has no libLLVM linkage. stage2 would be cranelift-
#      compiled and ~3x larger -- avoid.
#
# Plus size-opts in config.toml (sweet spot found 2026-05-26):
#   - lto = "fat"
#   - codegen-units = 1
#   - strip = true
# brings librustc_driver from 82 MB stripped to 63 MB stripped
# without breaking correctness (smoke + 4448 cg_clif tests pass).
#
# Standalone artifact -- intended to be invoked manually or by CI
# (.github/workflows/cranelift-build.yaml) on a beefy machine
# (~30 GB free disk, ~10 minutes wall clock on 12-core aarch64).
# The output tarballs land in <work-dir>/rust/build/dist/.
#
# Usage:
#   ./cranelift/1.93/bootstrap_cranelift_rust.sh [<work-dir>]
#
# Env overrides:
#   RUST_TAG=1.93.0   rust release tag to bootstrap (default 1.93.0)
#
# If <work-dir> is omitted, defaults to /tmp/rust-cranelift-bootstrap.
# spellchecker: ignore rustc cranelift LLVM

set -euo pipefail

RUST_TAG=${RUST_TAG:-1.93.0}
WORK=${1:-/tmp/rust-cranelift-bootstrap}

case "$(uname -m)" in
    x86_64)  HOST_TRIPLE=x86_64-unknown-linux-gnu ;;
    aarch64) HOST_TRIPLE=aarch64-unknown-linux-gnu ;;
    *) echo "unsupported host arch: $(uname -m)" >&2; exit 1 ;;
esac

echo "[bootstrap] cloning rust@${RUST_TAG} into ${WORK}"
mkdir -p "$WORK"
cd "$WORK"
if [ ! -d rust ]; then
    # depth 2 (not 1) so bootstrap's git rev-parse HEAD^1 works
    # -- config.rs:1784 unwraps that call on every build, and
    # --depth 1 would leave HEAD with no parent.
    # No --recurse-submodules -- x.py lazily inits only the
    # submodules it actually needs. avoids cloning ~6 doc repos,
    # cargo, enzyme, rustc-perf, the gcc backend, and (with
    # download-ci-llvm = true) src/llvm-project. saves several
    # minutes of CI clone time.
    git clone --depth 2 --branch "$RUST_TAG" \
        https://github.com/rust-lang/rust.git
fi
cd rust

# Patch (1): lower max_atomic_width on aarch64 from 128 to 64 so
# core compiles under cranelift (which lacks 128bit atomics on
# aarch64). The same setting is 0 issues for x86_64 -- guard with
# the host arch.
if [ "$HOST_TRIPLE" = "aarch64-unknown-linux-gnu" ]; then
    spec=compiler/rustc_target/src/spec/targets/aarch64_unknown_linux_gnu.rs
    if grep -q 'max_atomic_width: Some(128),' "$spec"; then
        echo "[bootstrap] patching $spec -- max_atomic_width 128 -> 64"
        sed -i 's|max_atomic_width: Some(128),|max_atomic_width: Some(64),  // HACK cranelift|' "$spec"
    fi
fi

echo "[bootstrap] writing config.toml (cranelift-only, no LLVM, target=$HOST_TRIPLE)"
cat > config.toml <<CONFIG
change-id = "ignore"
profile = "dist"

[llvm]
# pull precompiled LLVM from rust-lang's CI. rustc_llvm crate has
# FFI bindings that need libLLVM at compile time of stage1, even
# though our stage1 codegen-backends below excludes llvm so the
# shipped librustc_driver does not link libLLVM. downloading saves
# ~30 minutes vs compiling from source. correctness unchanged --
# the readelf gate later still confirms no libLLVM in DT_NEEDED.
download-ci-llvm = true

[build]
# Native arch only -- cross targets need their own gcc toolchains
# installed (e.g. x86_64-linux-gnu-gcc on arm64 host), which the
# bootstrap sanity-check enforces. CI matrix builds each arch
# natively so we never need cross from this script.
target = ["$HOST_TRIPLE"]
docs = false
extended = false
tools = []

[rust]
# THE key flag -- drops LLVM as a codegen backend from the shipped
# rustc. librustc_driver will not DT_NEEDED libLLVM.
#
# channel stays default (stable). channel = "dev" would let
# x.py dist produce a cranelift tarball (it's gated behind
# unstable_features() in dist.rs:1600), but dev also enables
# nightly-only paths in compiler-builtins that emit `asm! sym`
# operands -- which cranelift cannot lower. so we keep stable
# here and package the cranelift .so manually after bootstrap
# (see the `Add cranelift codegen tarball` step in
# cranelift-build.yaml).
codegen-backends = ["cranelift"]
debug = false
debug-assertions = false
incremental = false
# size opts (sweet spot found 2026-05-26): fat LTO + 1 CGU + strip
# shrinks librustc_driver from 82 MB stripped to 63 MB stripped.
# default opt-level=3 stays -- opt-level=s + panic=abort were
# tried and either regressed sizes or had no effect.
lto = "fat"
codegen-units = 1
strip = true
CONFIG

# Patch (2): tell cranelift to use the system `as` (binutils) for
# global_asm! / asm! instead of forking rustc-w/-llvm. baked in at
# cranelift compile time via option_env!.
export CG_CLIF_FORCE_GNU_AS=1

# Patch (3): stage 1 not stage 2. stage1 librustc_driver is
# LLVM-compiled (stage0 has LLVM) and small (~63 MB stripped with
# size-opts); stage2 would be cranelift-compiled (~230 MB) and
# offset the libLLVM savings.
echo "[bootstrap] running ./x.py dist --stage 1 (CG_CLIF_FORCE_GNU_AS=1)"
./x.py dist --stage 1 rustc rust-std rustc_codegen_cranelift

echo "[bootstrap] verifying librustc_driver.so has no LLVM linkage"
driver=$(find build -path '*/stage1/lib/librustc_driver-*.so' | head -n1)
if [ -z "$driver" ]; then
    echo "[bootstrap] FAIL: no librustc_driver.so produced" >&2
    exit 1
fi
if readelf -dW "$driver" | grep -qi 'NEEDED.*libLLVM'; then
    echo "[bootstrap] FAIL: $driver still has libLLVM in DT_NEEDED" >&2
    readelf -dW "$driver" | grep NEEDED >&2
    exit 1
fi
echo "[bootstrap] OK: $driver has no libLLVM dependency"
ls -la "$driver"

echo "[bootstrap] tarballs ready in build/dist/:"
ls -la build/dist/*.tar.xz
