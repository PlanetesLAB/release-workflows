# release-workflows

One shared release pipeline for every PlanetesLAB crate and package.

## The rules it enforces

For a manifest (Cargo.toml or pyproject.toml) and a tag prefix, let L be the highest existing tag `<prefix>X.Y.Z`.

- Manifest version == L: normal push, tests only, no release.
- Manifest version is X.Y.(Z+1), X.(Y+1).0 or (X+1).0.0: a valid release.
- Anything else (backwards, skipping, not plain MAJOR.MINOR.PATCH, Cargo.lock out of sync): the run fails.

A valid release on the release branch runs the tests, then creates the annotated tag and the GitHub Release
(notes = commit subjects since the previous tag, limited to the crate's directory; 0.x.y are marked pre-release).
Pull requests run the same checks but never release. Commit messages are never parsed.

The workflow cannot judge whether a bump is *big enough* (that is a human decision: tell Claude or decide yourself),
only that it is a legal step. On the Free organization plan GitHub cannot block a push, so a bad version shows up as a
red run and no release.

## One-time setup

1. Create the private repo `PlanetesLAB/release-workflows` and put `.github/workflows/release.yml` from here on `main`.
   Tag it: `git tag v1 && git push origin v1`. Move the tag (`git tag -f v1; git push -f origin v1`) after later fixes.
2. In that repo: Settings > Actions > General > Access > "Accessible from repositories in the PlanetesLAB organization".
3. Create a fine-grained personal access token (resource owner PlanetesLAB, repository access: the repos used as git
   dependencies, permission Contents: read-only). Add it as an organization secret `DEPS_TOKEN` shared with the repos
   (only needed by repos that have private git dependencies).
4. In each repo add `callers/release.yml` as `.github/workflows/release.yml`, with the right branch, prefix, manifest.
   Delete the old tag-triggered `release.yml` where one exists (planetes-ext, sundials, suitesparse).

## Per repo settings

| Repo | Branch | Prefix | Manifest |
|---|---|---|---|
| limulus | master | v | Cargo.toml |
| spectre | master | v | Cargo.toml |
| scorpia (Rust) | main | v | Cargo.toml |
| scorpia (Python) | main | scorpia-py-v | python/pyproject.toml |
| kappa, planetes-ext | check | v | Cargo.toml |
| sundials / sundials-sys | check | sundials-v / sundials-sys-v | each crate's Cargo.toml |
| suitesparse / suitesparse-sys | check | suitesparse-v / suitesparse-sys-v | each crate's Cargo.toml |

Repos with two crates or packages get two jobs in the caller file, one per manifest and prefix.

## Binaries and data archives

After a release, two optional jobs attach files to the GitHub Release:

- `binaries: true` builds the executable named like the repository for `linux-x86_64` (in the
  `manylinux_2_28` container, so it runs on glibc 2.28 and newer) and attaches
  `<repo>-<version>-linux-x86_64.tar.gz`. `build-env` sets variables for that build (scorpia:
  `SCORPIA_RELEASE_BUILD=1`, which lets `scorpia update` replace the binary); `linux-packages` are
  `dnf` arguments for the container (e.g. `--enablerepo=powertools clang-devel blas-devel lapack-devel`). `build-args` adds
  cargo arguments to that build (limulus: `--features analysis,tui`).
- `resources: <folder>` attaches the folder as `<repo>-resources-<version>.tar.gz`, with the folder
  at the top of the archive; `resources-exclude` lists paths to leave out (`.DS_Store` always is).

- `python-wheels: true` builds the maturin Python extension module as an abi3 wheel for
  `linux-x86_64` (`manylinux_2_28`, with `linux-packages` installed and shared libraries such as BLAS
  copied into the wheel) and attaches it. The run fails if the wheel is not abi3 (enable pyo3's
  `abi3-pyXY` feature, so one wheel serves every Python from 3.XY on), does not carry the release
  version (use `dynamic = ["version"]` in pyproject.toml so maturin takes it from Cargo.toml), or
  cannot be imported. `python-module` names the module to import (default: the repository name).

These jobs run only on a release, never on a plain push or a pull request.

The `macos-arm64` assets are built on an arm64 Mac, after the release run, with

```sh
./macos-binary.sh <repository directory> <version>
```

It checks out the tag `v<version>` in a temporary worktree and builds what the repository's caller
file asks for, with `MACOSX_DEPLOYMENT_TARGET=13.0` (runs on macOS 13 and newer):

- `binaries: true`: the executable as the `binaries` job does (`build-env`, `build-args`,
  `--release --locked`), packed as `<repo>-<version>-macos-arm64.tar.gz`; reuses
  `target/macos-release/` between releases.
- `python-wheels: true`: the wheel with `uvx maturin`, made self-contained with `delocate-wheel`,
  checked by importing it in a fresh venv; reuses `target/macos-wheel/`. Needs uv.

Each file is attached with `gh release upload --clobber`.

## Installing the Python wheels

Collaborators with read access to the repository install a release's wheel into the active
environment (uv venv, conda env or plain venv) with `gh` and pip or uv:

```sh
gh release download v1.2.3 -R PlanetesLAB/<repo> -p '*.whl' -D /tmp/<repo>-wheels
python -m pip install --find-links /tmp/<repo>-wheels <package>==1.2.3     # pip, also in a conda env
uv pip install --find-links /tmp/<repo>-wheels <package>==1.2.3            # uv
```

`--find-links` picks the wheel for the platform. Repositories can ship an `install-python.sh` that
does this (see limulus).

## Documentation workflow

`.github/workflows/docs.yml` runs `book/build.sh` in the calling repo. That script builds the API reference
(`cargo doc`), the HTML manual (mdBook) and the PDF manual (Sphinx with LuaLaTeX). Warnings fail the run. The three
outputs are uploaded as run artifacts (`api`, `book-html`, `book-pdf`), which only repo members can download.
With `deploy: true` the HTML manual, never the API reference, is also published to GitHub Pages. The caller must
then grant `pages: write` and `id-token: write`. It runs on every push and pull request; it never releases anything.
Move the `v1` tag after adding it, as above.
