# spellchecker: ignore sigpipe subshell
# Set bash options
set -eux

source defer.sh

# Launch a docker container with the given name prefix
# Mount the current directory as read-only at /work
# The container is removed on script exit
function launch_container() {
    local name="test_container"
    [ -n "${1:-}" ] && name="${name}_$1"
    local work="$(pwd)"
    [ -n "${2:-}" ] && work="$2"
    docker rm -f "$name" &>/dev/null || true
    # NOTE: bind-mount would not work here -- this script runs inside the
    #       sshd test container, but `docker` talks to the host daemon via
    #       the mounted socket, so `$work` does not exist on the docker
    #       host. Use `docker cp` instead.
    docker create --name "$name" "$IMAGE_NAME:latest" > /dev/null
    docker cp "$work/." "$name:/work"
    docker start "$name" &>/dev/null || true
    echo "$name"
    # NOTE: defer does not run at the end of the function, but it does
    #       if launch_container is called from the subshell
    # defer "docker rm --force $name &>/dev/null || true" EXIT
}