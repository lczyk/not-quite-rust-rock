#!/usr/bin/env bash
# override-build for the `wild` part: download a prebuilt wild linker
# tarball for the build-for arch, drop the binary at /usr/bin/wild,
# add an `ld -> wild` symlink, and a `cc -> not-quite-cargo` symlink
# so rustc's default cc-driver linker invocation routes into nqc's
# built-in driver (see the driver package in not-quite-cargo, ships
# in v0.8.0+). nqc translates the gcc-style args into raw ld-style
# and exec's whatever /usr/bin/ld points at -- here, wild.

set -euo pipefail

WILD_VERSION=0.9.0

case "$CRAFT_ARCH_BUILD_FOR" in
    amd64) WILD_TRIPLE=x86_64-unknown-linux-gnu ;;
    arm64) WILD_TRIPLE=aarch64-unknown-linux-gnu ;;
    *) echo "unsupported arch: $CRAFT_ARCH_BUILD_FOR" >&2; exit 1 ;;
esac

tarball="wild-linker-${WILD_VERSION}-${WILD_TRIPLE}.tar.gz"
url="https://github.com/wild-linker/wild/releases/download/${WILD_VERSION}/${tarball}"

workdir=$(mktemp -d --suffix=-wild)
curl -fsSL --retry 5 --retry-delay 5 -o "$workdir/wild.tar.gz" "$url"
tar -xzf "$workdir/wild.tar.gz" -C "$workdir"

mkdir -p "$CRAFT_PART_INSTALL/usr/bin"
install -m 755 \
    "$workdir/wild-linker-${WILD_VERSION}-${WILD_TRIPLE}/wild" \
    "$CRAFT_PART_INSTALL/usr/bin/wild"
ln -s wild "$CRAFT_PART_INSTALL/usr/bin/ld"

# /usr/bin/cc -> not-quite-cargo. The not-quite-cargo binary lives
# in the sibling `not-quite-cargo` part; at prime time both parts
# merge into the rock root so this relative symlink resolves.
ln -s not-quite-cargo "$CRAFT_PART_INSTALL/usr/bin/cc"

# Surface the gcc-14 linker script libgcc_s.so under the standard
# library search path so wild's `-lgcc_s` resolves. The script itself
# (a GROUP/INPUT line) redirects to libgcc_s.so.1, which already
# sits at /usr/lib/<triple>/ via the libgcc-s1 slice.
case "$CRAFT_ARCH_BUILD_FOR" in
    amd64) TRIPLE=x86_64-linux-gnu ;;
    arm64) TRIPLE=aarch64-linux-gnu ;;
esac
mkdir -p "$CRAFT_PART_INSTALL/usr/lib/${TRIPLE}"
ln -s "/usr/lib/gcc/${TRIPLE}/14/libgcc_s.so" \
    "$CRAFT_PART_INSTALL/usr/lib/${TRIPLE}/libgcc_s.so"
