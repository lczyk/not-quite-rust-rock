# not quite Rust rock

This repository contains the SDK [rock](https://documentation.ubuntu.com/server/explanation/virtualisation/about-rock-images/) definitions for the [rust](https://www.rust-lang.org/) programming language.

The rock contains a minimal Rust toolchain (`rustc`), a minimal GCC toolchain for custom build steps, and [`not-quite-cargo`](https://github.com/lczyk/not-quite-cargo) -- a small replayer that builds rust projects from a pre-generated cargo `--build-plan` instead of running cargo inside the rock.

The rock does **not** ship `cargo` or `apt`. Builds happen in two stages: a planning stage (in any image with cargo) produces `build-plan.json` and populates a cargo registry; an execution stage (in this rock, with the network off) replays the plan via `not-quite-cargo run`. See [`not-quite-cargo`'s examples](https://github.com/lczyk/not-quite-cargo/tree/main/go/examples) for the pattern, or the spread tests in this repo (`tests/spread/general/test_fd`, `tests/spread/general/test_eza`) for a worked example.

## Pulling the image

```bash
docker pull ghcr.io/lczyk/not-quite-rust-rock/rust:1.93
```

## Available versions

* [Rust 1.93 (Ubuntu 26.04)](./rust/1.93-26.04/rockcraft.yaml)

## Building locally

```bash
cd rust/1.93-26.04
make build      # pack the rock
make test       # build test image + run spread tests
make help       # list make targets
```
