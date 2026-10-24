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
