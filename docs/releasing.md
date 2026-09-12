# Releases

GitHub Actions runs tests for pull requests and pushes to `main`. Pushing a semantic-version tag
builds the universal macOS app, packages a DMG, writes its SHA-256 checksum, and publishes both files
to a GitHub Release.

Create a release:

```sh
git switch main
git pull --ff-only
make bump 1.0.0
git push origin main
git push origin v1.0.0
```

`make bump <version>` requires a clean worktree and a version matching `<major>.<minor>.<patch>`. It
updates `MARKETING_VERSION`, increments `CURRENT_PROJECT_VERSION`, regenerates the Xcode project,
creates a version commit, and creates the matching annotated tag locally. It does not push.

The release workflow rejects a tag that does not match `MARKETING_VERSION` in `project.yml`. It sets
the packaged app build number from the GitHub Actions run number.

Delete a mistaken tag before its release is consumed:

```sh
git tag -d v1.0.0
git push origin :refs/tags/v1.0.0
```

The generated app is unsigned and not notarized. Users may receive a Gatekeeper warning. Public
distribution should add Developer ID signing and Apple notarization after the required Apple
Developer credentials are available as GitHub Actions secrets.
