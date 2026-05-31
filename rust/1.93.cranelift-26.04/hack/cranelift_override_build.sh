#!/usr/bin/env bash
# override-build for the `cranelift` part: download the cranelift-only
# rust toolchain published as a github release (built from source by
# .github/workflows/cranelift-build.yaml), install it under /usr, and
# gate on the installed librustc_driver having no libLLVM linkage.
#
# Three tarballs per triple (+ a .sha256 sidecar each):
#   - rustc-<ver>-<triple>.tar.xz          rust-installer layout, install.sh
#   - rust-std-<ver>-<triple>.tar.xz       -//-
#   - rustc-codegen-cranelift-<ver>-<triple>.tar.xz
#                                          plain layout, .so under
#                                          lib/rustlib/<triple>/codegen-backends/
#
# rustc + rust-std go in via rust-installer's install.sh (--prefix=/usr,
# so rustc lands at /usr/bin/rustc and the sysroot at
# /usr/lib/rustlib/<triple>/ -- no rustc-1.93 rename needed). The
# cranelift .so is hand-packed (plain layout) so it extracts straight
# into the prefix.
#
# The shipped rustc was built with codegen-backends = ["cranelift"]
# only -- cranelift is the sole, hence default, backend, so no
# -Zcodegen-backend flag is needed at runtime. The readelf gate below
# re-confirms there is no libLLVM in DT_NEEDED after install.
# spellchecker: ignore rustc cranelift readelf

set -euo pipefail

# Pinned to the current REVISION (cranelift-1.93/r3). Bump in lockstep
# with REVISION when a newer cranelift toolchain is published.
CRANELIFT_TAG=cranelift-1.93/r3
RUST_VER=1.93.0
RELEASE_BASE=https://github.com/lczyk/not-quite-rust-rock/releases/download/${CRANELIFT_TAG}

case "$CRAFT_ARCH_BUILD_FOR" in
    amd64) TRIPLE=x86_64-unknown-linux-gnu ;;
    arm64) TRIPLE=aarch64-unknown-linux-gnu ;;
    *) echo "unsupported arch: $CRAFT_ARCH_BUILD_FOR" >&2; exit 1 ;;
esac

tarballs=(
    "rustc-${RUST_VER}-${TRIPLE}"
    "rust-std-${RUST_VER}-${TRIPLE}"
    "rustc-codegen-cranelift-${RUST_VER}-${TRIPLE}"
)

workdir=$(mktemp -d --suffix=-cranelift)
cd "$workdir"

for base in "${tarballs[@]}"; do
    curl -fsSL --retry 5 --retry-delay 5 -O "${RELEASE_BASE}/${base}.tar.xz"
    curl -fsSL --retry 5 --retry-delay 5 -O "${RELEASE_BASE}/${base}.tar.xz.sha256"
done

# sha256 sidecars are produced as `<digest>  <filename>` so -c works
# straight against the .tar.xz sitting alongside.
for base in "${tarballs[@]}"; do
    sha256sum -c "${base}.tar.xz.sha256"
done

prefix="$CRAFT_PART_INSTALL/usr"
mkdir -p "$prefix"

for base in "${tarballs[@]}"; do
    if [[ "$base" == rustc-codegen-cranelift-* ]]; then
        # plain layout: lib/rustlib/<triple>/codegen-backends/*.so
        tar -xJf "${base}.tar.xz" -C "$prefix"
    else
        # rust-installer layout: extract then run install.sh
        tar -xJf "${base}.tar.xz"
        "${base}/install.sh" --prefix="$prefix" --disable-ldconfig --verbose
    fi
done

# Gate: the installed librustc_driver must have no libLLVM in DT_NEEDED
# -- proves this is the cranelift-only build, not an LLVM one.
driver=$(find "$prefix/lib" -name 'librustc_driver-*.so' | head -n1)
test -n "$driver" || { echo "no librustc_driver after install" >&2; exit 1; }
if readelf -dW "$driver" | grep -qi 'NEEDED.*libLLVM'; then
    echo "FAIL: installed $driver has libLLVM in DT_NEEDED" >&2
    readelf -dW "$driver" | grep NEEDED >&2
    exit 1
fi
echo "OK: $driver has no libLLVM dependency"

# Confirm the cranelift backend landed where rustc looks for it.
clif=$(find "$prefix/lib/rustlib/$TRIPLE/codegen-backends" \
    -name 'librustc_codegen_cranelift-*.so' | head -n1)
test -n "$clif" || { echo "no cranelift codegen backend after install" >&2; exit 1; }
echo "OK: cranelift backend at $clif"
