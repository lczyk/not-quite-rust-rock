function main() {
    flavour=$(echo $SPREAD_SYSTEM | cut -d- -f1,2)
    arch=$(echo $SPREAD_SYSTEM | cut -d- -f3)
    # precompiled docker images for amd64 and arm64
    image="sshd-$flavour-$arch"
    echo "Using image: $image"

    # Add random suffix to container name for uniqueness
    random_suffix=$(head /dev/urandom | tr -dc a-f0-9 | head -c8)
    container_name="${SPREAD_SYSTEM}-${random_suffix}"

    # remove any existing container with the same name
    docker rm -f $container_name 2>/dev/null || true

    docker run \
        --rm \
        --platform "linux/$arch" \
        --privileged \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -e DEBIAN_FRONTEND=noninteractice \
        -e "usr=$SPREAD_SYSTEM_USERNAME" \
        -e "pass=$SPREAD_SYSTEM_PASSWORD" \
        --name "$container_name" \
        -d "$image"

    until docker exec "$container_name" pgrep sshd; do sleep 1; done

    ADDRESS "$(docker inspect "$container_name" --format '{{.NetworkSettings.Networks.bridge.IPAddress}}')"
}

main
