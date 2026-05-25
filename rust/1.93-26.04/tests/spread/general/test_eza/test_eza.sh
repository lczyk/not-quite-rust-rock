#!/usr/bin/env bash
# Mirrors not-quite-cargo's eza-build-plan example:
# plan in upstream rust+cargo image -> patch + run in this rock
# (with cargo absent and network off) -> verify built binary.
# spellchecker: ignore eza rustc nqc

source common.sh
source defer.sh

EZA_REF=v0.20.24
EZA_REPO=https://github.com/eza-community/eza.git
UPSTREAM_IMAGE=docker.io/ubuntu/rust:1.85-24.04_edge

tmpdir=$(mktemp -d)

# 1. clone eza at pinned tag
git -c advice.detachedHead=false clone --depth 1 \
    --branch "$EZA_REF" "$EZA_REPO" "$tmpdir/eza"
mkdir -p "$tmpdir/cargo"

# 2. plan: upstream image generates build-plan.json and populates
#    /cargo with the resolved crate registry.
docker run --rm \
    --volume "$(to_host "$tmpdir/eza"):/work" \
    --volume "$(to_host "$tmpdir/cargo"):/cargo" \
    --workdir /work \
    -e CARGO_HOME=/cargo -e RUSTC_BOOTSTRAP=1 \
    "$UPSTREAM_IMAGE" exec sh -c \
    'cd /work && cargo build -j1 --release --no-default-features -Z unstable-options --build-plan > build-plan.json'

# 3. launch rock-under-test container w/ eza src + populated /cargo,
#    network off. Inline create + start (not launch_container) so we
#    can add the /cargo mount and --network=none.
name=test_container_eza
docker rm -f "$name" &>/dev/null || true
docker create --name "$name" \
    --network none \
    -v "$(to_host "$tmpdir/eza"):/work" \
    -v "$(to_host "$tmpdir/cargo"):/cargo" \
    "$IMAGE_NAME:latest" > /dev/null
defer "docker rm --force $name &>/dev/null || true" EXIT
docker start "$name" &>/dev/null || true

# 4. patch + run via not-quite-cargo (no cargo in the rock at all)
docker exec --workdir /work "$name" not-quite-cargo patch \
    --project-root=/work --cargo-home=/cargo --inplace build-plan.json
docker exec --workdir /work "$name" not-quite-cargo run build-plan.json

# 5. verify built binary works -- install onto the spread test host
#    and run it as a regular command. target/release/eza is a symlink
#    whose target is written as the in-rock absolute path (/work/...),
#    broken from this side, so pick the real binary under deps/.
eza_src=$(find "$tmpdir/eza/target/release/deps" -maxdepth 1 \
    -name 'eza-*' -type f -executable ! -name '*.d' | head -n1)
[ -n "$eza_src" ] && [ -x "$eza_src" ] || \
    { echo "could not locate built eza binary under $tmpdir/eza/target/release/deps" >&2; exit 1; }
install -m 755 "$eza_src" /usr/bin/eza
defer "rm -f /usr/bin/eza" EXIT

eza --version | grep -q "eza"
eza /etc/ | head -n5 | grep -q .
