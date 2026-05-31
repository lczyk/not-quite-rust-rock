#!/usr/bin/env bash
# Mirrors not-quite-cargo's sudo-build-plan example:
# plan in upstream rust+cargo image -> patch + run in this rock
# (with cargo absent and network off) -> verify built binary.
#
# sudo-rs FFIs libpam directly, so the rock needs libpam.so + the
# libpam.so.0 SONAME visible at link time. We do NOT want libpam in
# the rock proper -- so the test downloads libpam0g-dev / libpam0g
# / libaudit1 / libcap-ng0 as .debs on the spread host, extracts
# just the .so files we need from each .deb, and bind-mounts those
# into the rock container's /usr/lib/<triple>/ at build time only.
# Runtime verification of the built binary happens on the spread
# host, which has its own libpam, so no runtime mount is needed.
# spellchecker: ignore sudo libpam libaudit libcap dpkg

source common.sh
source defer.sh

SUDO_RS_REF=v0.2.3
SUDO_RS_REPO=https://github.com/trifectatechfoundation/sudo-rs.git
UPSTREAM_IMAGE=docker.io/ubuntu/rust:1.85-24.04_edge

arch=$(uname -m)
case "$arch" in
    aarch64) triple=aarch64-linux-gnu ;;
    x86_64)  triple=x86_64-linux-gnu ;;
    *) echo "unsupported arch $arch" >&2; exit 1 ;;
esac

tmpdir=$(mktemp -d)

# 1. clone sudo-rs at pinned tag
git -c advice.detachedHead=false clone --depth 1 \
    --branch "$SUDO_RS_REF" "$SUDO_RS_REPO" "$tmpdir/sudo-rs"
mkdir -p "$tmpdir/cargo"

# 2. plan: upstream image generates build-plan.json and populates
#    /cargo with the resolved crate registry.
docker run --rm \
    --volume "$(to_host "$tmpdir/sudo-rs"):/work" \
    --volume "$(to_host "$tmpdir/cargo"):/cargo" \
    --workdir /work \
    -e CARGO_HOME=/cargo -e RUSTC_BOOTSTRAP=1 \
    "$UPSTREAM_IMAGE" exec sh -c \
    'cd /work && cargo build -j1 --release -Z unstable-options --build-plan > build-plan.json'

# 2b. fetch libpam + transitive runtime deps as .debs and unpack just
#     the .so files needed for the link step into tmpdir/pam. Same
#     pattern as the nqc sudo-build-plan example's Dockerfile.
mkdir -p "$tmpdir/pam-debs" "$tmpdir/pam"
( cd "$tmpdir/pam-debs" && \
    apt-get update >/dev/null && \
    apt-get download libpam0g libpam0g-dev libaudit1 libcap-ng0 )

for deb in "$tmpdir"/pam-debs/libpam0g_*.deb; do
    dpkg-deb --fsys-tarfile "$deb" | tar -xf - -C "$tmpdir/pam" \
        "./usr/lib/${triple}/libpam.so.0" \
        "./usr/lib/${triple}/libpam.so.0.85.1"
done
for deb in "$tmpdir"/pam-debs/libpam0g-dev_*.deb; do
    dpkg-deb --fsys-tarfile "$deb" | tar -xf - -C "$tmpdir/pam" \
        "./usr/lib/${triple}/libpam.so"
done
for deb in "$tmpdir"/pam-debs/libaudit1_*.deb; do
    dpkg-deb --fsys-tarfile "$deb" | tar -xf - -C "$tmpdir/pam" \
        "./usr/lib/${triple}/libaudit.so.1" \
        "./usr/lib/${triple}/libaudit.so.1.0.0"
done
for deb in "$tmpdir"/pam-debs/libcap-ng0_*.deb; do
    dpkg-deb --fsys-tarfile "$deb" | tar -xf - -C "$tmpdir/pam" \
        "./usr/lib/${triple}/libcap-ng.so.0" \
        "./usr/lib/${triple}/libcap-ng.so.0.0.0"
done

# 3. launch rock-under-test container w/ sudo-rs src + populated
#    /cargo + libpam bind-mounted at the standard linker search path.
#    Mount the whole pam/usr/lib/<triple>/ subtree -- since the rock
#    already has its own /usr/lib/<triple>/ populated by libgcc-14-dev
#    / libc6-dev slices, we use per-file mounts instead of a
#    dir-level overlay so neither set obscures the other.
name=test_container_sudo
docker rm -f "$name" &>/dev/null || true
pam_mounts=()
for f in libpam.so libpam.so.0 libpam.so.0.85.1 \
         libaudit.so.1 libaudit.so.1.0.0 \
         libcap-ng.so.0 libcap-ng.so.0.0.0; do
    src="$tmpdir/pam/usr/lib/${triple}/${f}"
    [ -e "$src" ] || { echo "expected $src not found" >&2; exit 1; }
    pam_mounts+=( -v "$(to_host "$src"):/usr/lib/${triple}/${f}:ro" )
done
docker create --name "$name" \
    --network none \
    -v "$(to_host "$tmpdir/sudo-rs"):/work" \
    -v "$(to_host "$tmpdir/cargo"):/cargo" \
    "${pam_mounts[@]}" \
    "$IMAGE_NAME:latest" > /dev/null
defer "docker rm --force $name &>/dev/null || true" EXIT
docker start "$name" &>/dev/null || true

# 4. patch + run via not-quite-cargo (no cargo in the rock at all)
docker exec --workdir /work "$name" not-quite-cargo patch \
    --project-root=/work --cargo-home=/cargo \
    --linker=/usr/bin/cc --inplace build-plan.json
docker exec --workdir /work "$name" not-quite-cargo run build-plan.json

# 5. verify built binary works -- install onto the spread test host
#    and run it as a regular command. We only need --version, no
#    setuid / sudoers config required for that.
sudo_src=$(find "$tmpdir/sudo-rs/target/release/deps" -maxdepth 1 \
    -name 'sudo-*' -type f -executable ! -name '*.d' ! -name '*.rlib' | head -n1)
[ -n "$sudo_src" ] && [ -x "$sudo_src" ] || \
    { echo "could not locate built sudo binary under $tmpdir/sudo-rs/target/release/deps" >&2; exit 1; }
install -m 755 "$sudo_src" /usr/local/bin/sudo-rs
defer "rm -f /usr/local/bin/sudo-rs" EXIT

sudo-rs --version 2>&1 | grep -q "sudo-rs"
