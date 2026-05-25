#!/usr/bin/env bash

## TESTS

# not-quite-cargo
docker run --rm "$IMAGE_NAME:latest" exec not-quite-cargo --help \
    | grep -q "Available commands"
docker run --rm "$IMAGE_NAME:latest" exec not-quite-cargo --version \
    | grep -q '^not-quite-cargo '

# rust
docker run --rm "$IMAGE_NAME:latest" exec rustc --help \
    | grep -q "Usage: rustc"
docker run --rm "$IMAGE_NAME:latest" exec rustc --version \
    | grep -q 'rustc 1.93'

# gcc
docker run --rm "$IMAGE_NAME:latest" exec gcc --help \
    | grep -q "Usage: gcc"
docker run --rm "$IMAGE_NAME:latest" exec gcc --version \
    | head -n1 | grep -q 'gcc (Ubuntu 15'
