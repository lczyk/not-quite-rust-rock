#!/usr/bin/env bash
# The rock ships the cranelift-only rustc, so `rustc -vV` must NOT
# print an `LLVM version:` line (that line only appears when rustc is
# built with the LLVM codegen backend). This is the in-rock proxy for
# the readelf "no libLLVM in DT_NEEDED" gate -- the bare rock has no
# readelf, but a missing LLVM-version line is a clean discriminator.

# shellcheck source=../../lib/common.sh
source common.sh
# shellcheck source=../../lib/defer.sh
source defer.sh

name=$(launch_container cranelift)
defer "docker rm --force $name &>/dev/null || true" EXIT

vv=$(docker exec "$name" rustc -vV)
echo "$vv"

if echo "$vv" | grep -qi 'LLVM version'; then
    echo "FAIL: rustc -vV reports an LLVM version -- not the cranelift-only build" >&2
    exit 1
fi
echo "OK: no LLVM version line -- cranelift-only rustc"
