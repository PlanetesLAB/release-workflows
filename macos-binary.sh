#!/usr/bin/env bash
# Builds the macos-arm64 release assets on this Mac and attaches them to the GitHub Release, as
# the binaries and wheels jobs of .github/workflows/release.yml do for linux-x86_64:
#   * binaries: true       -> <repo>-<version>-macos-arm64.tar.gz with the executable
#   * python-wheels: true  -> the abi3 Python wheel (maturin), self-contained via delocate
# Which ones is read from the repository's caller file.
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

# Settings of the repository's caller file, as the release workflow uses them.
caller="$repo/.github/workflows/release.yml"
setting() { sed -n "s/^ *$1: *//p" "$caller" | head -n 1 | tr -d '"'; }
binaries=$(setting binaries)
wheels=$(setting python-wheels)
build_env=$(setting build-env)
build_args=$(setting build-args)
module=$(setting python-module)
module=${module:-$name}
if [ "$binaries" != true ] && [ "$wheels" != true ]; then
    echo "$0: $caller sets neither binaries: true nor python-wheels: true" >&2
    exit 1
fi
if [ "$wheels" = true ] && ! command -v uv > /dev/null; then
    echo "$0: building the wheel needs uv" >&2
    exit 1
fi

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
# The oldest macOS the assets run on.
export MACOSX_DEPLOYMENT_TARGET=13.0

if [ "$binaries" = true ]; then
    # The target directory is kept between releases.
    export CARGO_TARGET_DIR="$repo/target/macos-release"
    # shellcheck disable=SC2086 # build_env and build_args are lists of words.
    env $build_env cargo build --release --locked $build_args
    exe="$CARGO_TARGET_DIR/release/$name"
    "$exe" --version
    otool -L "$exe"
    archive="$work/$name-$version-macos-arm64.tar.gz"
    tar -czf "$archive" -C "$CARGO_TARGET_DIR/release" "$name"
    gh release upload "$tag" "$archive" --clobber -R "PlanetesLAB/$name"
fi

if [ "$wheels" = true ]; then
    # A separate target directory: the Python build uses other features than the executable.
    export CARGO_TARGET_DIR="$repo/target/macos-wheel"
    uvx maturin build --release --locked --out "$work/wheels"
    whl=("$work"/wheels/*.whl)
    [ ${#whl[@]} -eq 1 ] || { echo "expected one wheel, got ${#whl[@]}" >&2; exit 1; }
    case "$(basename "${whl[0]}")" in
        *-"$version"-*-abi3-*) ;;
        *) echo "$(basename "${whl[0]}") is not an abi3 wheel of version $version" >&2; exit 1 ;;
    esac
    # Copy non-system dylibs (e.g. Homebrew libraries) into the wheel so it runs anywhere.
    uvx --from delocate delocate-wheel -v "${whl[0]}"
    uvx --from delocate delocate-listdeps --all "${whl[0]}"
    uv venv --quiet "$work/check"
    uv pip install --quiet --python "$work/check" "${whl[0]}"
    (cd "$work" && "$work/check/bin/python" -c "import $module; print($module.__file__)")
    gh release upload "$tag" "${whl[0]}" --clobber -R "PlanetesLAB/$name"
fi
