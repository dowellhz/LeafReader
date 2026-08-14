# Release Checklist

Use this checklist before publishing a Leaf Reader release.

## Before Building

- Confirm the working tree is clean or only contains intended release changes.
- Add a `## What's New in <version>` section to `README.md` with user-facing release notes.
- Confirm the target version is valid:

```sh
./scripts/bump_version.sh --check <version>
```

- Run the full local check:

```sh
./scripts/check.sh
```

## Package

- Build the signed and notarized installer:

```sh
SPARKLE_PRIVATE_KEY_FILE=/path/to/sparkle-ed25519-private-key ./scripts/release_pkg.sh <version>
```

- Verify package signature:

```sh
pkgutil --check-signature release/<version>/LeafReader-<version>.pkg
```

- Verify Gatekeeper assessment when needed:

```sh
spctl --assess --type install release/<version>/LeafReader-<version>.pkg
```

- Run the package smoke test:

```sh
./scripts/smoke_release_pkg.sh <version>
```

- Confirm the smoke test reports both `arm64` and `x86_64` app architectures.

- Review app, package, speech runtime size, and the largest bundled runtime files:

```sh
./scripts/release_size_report.sh <version>
```

## Appcast

- Confirm `docs/appcast.xml` uses the intended version.
- Confirm the enclosure URL points to the GitHub Release asset.
- Confirm the package length and Sparkle EdDSA signature are current.
- Check the appcast URL:

```sh
curl -I -L https://dowellhz.github.io/LeafReader/appcast.xml
curl -I -L https://leafreader.space/appcast.xml
```

## Publish

- Publish the release:

```sh
./scripts/publish_release.sh <version>
```

Use `--push-wiki` when the release should sync GitHub Wiki as part of the publish flow. Use `--cleanup-releases` to remove old ignored local release artifacts after a successful publish.

The publish script pushes the tag, creates a draft release, downloads and checksum-verifies its assets, publishes the release, verifies the public package, and only then pushes `main` with the appcast. A failure before publication removes the draft release and staged remote tag.

- Confirm the Git tag exists:

```sh
git tag --list "v<version>"
```

- Confirm the GitHub Release asset downloads:

```sh
curl -I -L https://github.com/dowellhz/LeafReader/releases/download/v<version>/LeafReader-<version>.pkg
```

## After Publishing

- Open Leaf Reader and run the update check.
- Confirm the website download link points to the new version.
- Confirm `README.md` current version, tag, and installer link are updated.
- Run Wiki update if it was not included in the publish command and the release changed architecture, scripts, or docs:

```sh
./scripts/update_wiki.sh --push
```

## Recovery Notes

- If GitHub Release upload or verification fails before publication, the script removes the draft release and remote tag. Keep the local release commit, tag, and package for diagnosis; rerunning is supported when the local tag still points to that commit.
- If the release becomes public but pushing `main` fails, do not republish. Verify the public package, then run `git push origin main` to expose the already-valid appcast commit.
- If appcast metadata is wrong, fix `docs/appcast.xml`, commit, push, and re-check the update dialog.
- If notarization fails, do not publish the appcast entry until the package is signed and accepted.
