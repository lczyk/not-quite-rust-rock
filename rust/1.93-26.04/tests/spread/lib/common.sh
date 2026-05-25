# spellchecker: ignore sigpipe subshell
# Set bash options
set -eux

source defer.sh

# Translate a /rust/... path (inside this test container) to the
# equivalent path on the host docker daemon. Needed because the
# docker socket is shared with the host -- bind mounts resolve there,
# not against this container's filesystem.
function to_host() {
    local p="$1"
    printf '%s' "${p/#\/rust/$SPREAD_WORKDIR_HOST}"
}

# Launch a rock-under-test container. The name is `test_container`,
# suffixed with $1 if given (e.g. `test_container_fd`). The work dir
# ($2, defaulting to $(pwd)) is bind-mounted at /work read-write
# (path translated for the host daemon via to_host). Echoes the
# container name on stdout.
#
# Cleanup is the caller's job -- defer does not fire at function exit,
# only at script exit. Pair every call with:
#   defer "docker rm --force $name &>/dev/null || true" EXIT
function launch_container() {
    local name="test_container"
    [ -n "${1:-}" ] && name="${name}_$1"
    local work="$(pwd)"
    [ -n "${2:-}" ] && work="$2"
    docker rm -f "$name" &>/dev/null || true
    docker create --name "$name" -v "$(to_host "$work"):/work" "$IMAGE_NAME:latest" > /dev/null
    docker start "$name" &>/dev/null || true
    echo "$name"
}