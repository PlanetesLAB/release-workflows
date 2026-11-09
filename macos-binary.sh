#!/usr/bin/env bash
# Builds the macos-arm64 executable of a release on this Mac and attaches it to the GitHub
# Release, as the binaries job of .github/workflows/release.yml does for linux-x86_64.
#
# Usage: ./macos-binary.sh <repository directory> <version>
# e.g.   ./macos-binary.sh ../limulus 1.9.0
set -euo pipefail

if [ $# -ne 2 ]; then
    echo "usage: $0 <repository directory> <version>" >&2
    exit 2
fi
if [ "$(uname -s) $(uname -m)" != "Darwin arm64" ]; then
    echo "$0: needs an arm64 Mac" >&2
    exit 1
fi

repo=$(cd "$1" && pwd)
version=$2
name=$(basename "$repo")
tag="v$version"

# build-env and build-args of the repository's caller file, as the binaries job uses them.
caller="$repo/.github/workflows/release.yml"
setting() { sed -n "s/^ *$1: *//p" "$caller" | head -n 1 | tr -d '"'; }
build_env=$(setting build-env)
build_args=$(setting build-args)

work=$(mktemp -d)
cleanup() {
    git -C "$repo" worktree remove --force "$work/src" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT

set -x
git -C "$repo" fetch --tags --quiet origin
git -C "$repo" worktree add --detach "$work/src" "$tag"
cd "$work/src"
# The oldest macOS the binary runs on; the target directory is kept between releases.
export MACOSX_DEPLOYMENT_TARGET=13.0
export CARGO_TARGET_DIR="$repo/target/macos-release"
# shellcheck disable=SC2086 # build_env and build_args are lists of words.
env $build_env cargo build --release --locked $build_args
exe="$CARGO_TARGET_DIR/release/$name"
"$exe" --version
otool -L "$exe"
archive="$work/$name-$version-macos-arm64.tar.gz"
tar -czf "$archive" -C "$CARGO_TARGET_DIR/release" "$name"
gh release upload "$tag" "$archive" --clobber -R "PlanetesLAB/$name"
