#!/usr/bin/env bash
# Build the portable Linux GDExtension (.so) for x86_64 and aarch64 inside
# the glibc-2.31 builder container, then stage the results under
# native/bin/linux/<arch>/ where addons/shogi_core.gdextension expects them.
#
# Usage:
#   tools/build_linux_native.sh [--arch x86_64|arm64|all] [--rebuild-image]
#
# Why not `cargo build` on the host: the host's glibc leaks into the .so
# (trixie → GLIBC_2.43) and the AppImage would not start on older distros.
# See tools/Containerfile.linux-builder. After building, every .so is
# checked with objdump for its highest GLIBC_ symbol version; anything
# above GLIBC_FLOOR fails the build so the problem can't slip into a
# release.
#
# Caches: cargo registry and target dirs live in named podman volumes so
# incremental rebuilds are fast and the host target/ dir stays untouched.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

IMAGE="${LINUX_BUILDER_IMAGE:-seishingakuen/linux-builder:bullseye}"
GLIBC_FLOOR="${GLIBC_FLOOR:-2.31}"
ARCH=all
REBUILD=0

for arg in "$@"; do
    case "$arg" in
        --arch=*)         ARCH="${arg#--arch=}" ;;
        --arch)           shift_next=1 ;;
        --rebuild-image)  REBUILD=1 ;;
        -h|--help)        sed -n '2,7p' "$0"; exit 0 ;;
        *)
            if [[ "${shift_next:-0}" == 1 ]]; then ARCH="$arg"; shift_next=0
            else echo "unknown flag: $arg" >&2; exit 2; fi ;;
    esac
done

log() { printf '\n\033[1;34m[linux-native]\033[0m %s\n' "$*"; }

command -v podman >/dev/null || { echo "podman not installed" >&2; exit 1; }

# Build the image once; `--rebuild-image` forces a refresh (e.g. after a
# Rust version bump in rust-toolchain.toml — keep ARG RUST_VERSION in sync).
RUST_VERSION=$(sed -nE 's/^channel = "(.*)"$/\1/p' native/shogi_core/rust-toolchain.toml)
if (( REBUILD )) || ! podman image exists "$IMAGE"; then
    log "Building builder image $IMAGE (rust $RUST_VERSION, glibc floor $GLIBC_FLOOR)"
    podman build --build-arg "RUST_VERSION=$RUST_VERSION" \
        -t "$IMAGE" -f tools/Containerfile.linux-builder tools/
fi

case "$ARCH" in
    all)    TARGETS=(x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu) ;;
    x86_64) TARGETS=(x86_64-unknown-linux-gnu) ;;
    arm64)  TARGETS=(aarch64-unknown-linux-gnu) ;;
    *) echo "unknown --arch $ARCH (x86_64|arm64|all)" >&2; exit 2 ;;
esac

# Map Rust triple → native/bin/linux/<dir> (matches the .gdextension keys).
bin_dir_for() {
    case "$1" in
        x86_64-unknown-linux-gnu)  echo x86_64 ;;
        aarch64-unknown-linux-gnu) echo arm64 ;;
    esac
}

for triple in "${TARGETS[@]}"; do
    log "cargo build --release --target $triple (in container)"
    # The crate dir is mounted read-only at /work; cargo writes to the
    # named target volume. CARGO_TARGET_DIR must be outside the crate so
    # the host tree isn't touched and rust-toolchain.toml is honoured.
    podman run --rm \
        -v "$REPO_ROOT/native/shogi_core:/work:ro,Z" \
        -v seishingakuen-cargo-registry:/opt/cargo/registry \
        -v seishingakuen-linux-target:/target \
        -e CARGO_TARGET_DIR=/target \
        -w /work \
        "$IMAGE" \
        cargo build --release --target "$triple"

    dir=$(bin_dir_for "$triple")
    mkdir -p "native/bin/linux/$dir"
    # Copy out of the volume via a throwaway container.
    podman run --rm \
        -v seishingakuen-linux-target:/target:ro \
        -v "$REPO_ROOT/native/bin/linux/$dir:/out:Z" \
        "$IMAGE" \
        cp "/target/$triple/release/libshogi_core.so" /out/libshogi_core.so

    so="native/bin/linux/$dir/libshogi_core.so"
    # Portability gate: highest GLIBC_x.y symbol the .so requires.
    max_glibc=$(objdump -T "$so" | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -V | tail -1)
    if [[ "$(printf '%s\n%s\n' "$max_glibc" "$GLIBC_FLOOR" | sort -V | tail -1)" != "$GLIBC_FLOOR" ]]; then
        echo "ERROR: $so requires GLIBC_$max_glibc, above the $GLIBC_FLOOR floor." >&2
        echo "       The build did not happen inside the bullseye container, or the image is stale." >&2
        exit 1
    fi
    log "$so  ($(du -h "$so" | cut -f1), max GLIBC_$max_glibc ✓, $(file -b "$so" | cut -d, -f2 | xargs))"
done

log "Linux native libraries staged."
