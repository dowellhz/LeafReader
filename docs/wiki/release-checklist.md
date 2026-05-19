# Release Checklist

Use this checklist before publishing a Leaf Reader release.

## Before Building

- Confirm the working tree is clean or only contains intended release changes.
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
- Run Wiki update if the release changed architecture, scripts, or docs:

```sh
./scripts/update_wiki.sh --push
```

## Rollback Notes

- If GitHub Release upload fails, keep the tag and local package until the failure is understood.
- If appcast metadata is wrong, fix `docs/appcast.xml`, commit, push, and re-check the update dialog.
- If notarization fails, do not publish the appcast entry until the package is signed and accepted.
