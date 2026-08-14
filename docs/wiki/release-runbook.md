# Release Runbook

关键词：发布、打包、签名、公证、Sparkle、Appcast、GitHub Release、版本号。

This page is the command-by-command release procedure. Use [Release Checklist](release-checklist.md) as the short preflight list.

## 1. Confirm Version State

```sh
./scripts/bump_version.sh --check <version>
git status --short
```

Expected:

- Version references already match `<version>`, or the release task intentionally updates them.
- The working tree contains only intended release changes.
- `README.md` includes `## What's New in <version>` with user-facing release notes.

## 2. Run Full Local Verification

```sh
./scripts/check.sh
```

Expected:

- JavaScript syntax checks pass.
- Swift logic tests pass.
- `Leaf Reader.app` builds and signs successfully.

If this fails, fix the code or signing environment before producing release artifacts.

## 3. Build The Installer

```sh
SPARKLE_PRIVATE_KEY_FILE=/path/to/sparkle-ed25519-private-key ./scripts/release_pkg.sh <version>
```

Expected:

- A signed package exists under `release/<version>/`.
- Release notes HTML exists or was generated.
- The script emits Sparkle metadata needed for `docs/appcast.xml`.

## 4. Verify Package

```sh
pkgutil --check-signature release/<version>/LeafReader-<version>.pkg
spctl --assess --type install release/<version>/LeafReader-<version>.pkg
./scripts/smoke_release_pkg.sh <version>
./scripts/release_size_report.sh <version>
```

Expected:

- Package signature is valid.
- Gatekeeper assessment succeeds.
- The expanded package contains a signed app with the expected version and bundled resources.
- Speech runtime size and signable file count are visible before publication.

## 5. Publish

```sh
./scripts/publish_release.sh <version>
```

For a full maintenance publish, include wiki sync and release cleanup:

```sh
./scripts/publish_release.sh <version> --push-wiki --cleanup-releases
```

Expected:

- Version checks pass.
- `v<version>` is pushed and a draft GitHub Release receives the artifacts.
- Every draft asset is downloaded and checksum-verified before the release becomes public.
- The public package is downloaded and checksum-verified before `main` exposes the appcast.
- `docs/appcast.xml`, `README.md`, and website references are current.
- With `--push-wiki`, GitHub Wiki and `docs/wiki` source are updated after publication.
- With `--cleanup-releases`, old ignored local release artifacts are removed after publication.

## 6. Verify Public Endpoints

```sh
curl -I -L https://github.com/dowellhz/LeafReader/releases/download/v<version>/LeafReader-<version>.pkg
curl -I -L https://dowellhz.github.io/LeafReader/appcast.xml
curl -I -L https://leafreader.space/
```

Expected:

- Release asset returns success.
- Appcast is reachable over HTTPS.
- Website is reachable over HTTPS.

## 7. App Update Check

- Open the installed app.
- Run the update check.
- Confirm Sparkle can retrieve update information.
- Confirm the update dialog references the expected version.

## 8. Sync Wiki

```sh
./scripts/update_wiki.sh --push
```

Expected:

- Code Map and Type Index are regenerated.
- GitHub Wiki receives updated pages.
- `docs/wiki` source changes are committed and pushed to `main`.

Skip this manual step when `publish_release.sh` was run with `--push-wiki`.

## Recovery

- If upload or verification fails before publication, the script removes the draft release and remote tag. Inspect the local package and retry; the local tag is accepted when it points to the release commit.
- If the release is public but pushing `main` fails, verify the public asset and recover with `git push origin main`; do not recreate the release.
- If the appcast is wrong, fix `docs/appcast.xml`, push `main`, and re-check the appcast URL.
- If notarization or signing fails, do not publish the appcast entry until the package verifies.
- If the update dialog fails, check [Troubleshooting](troubleshooting.md) before changing Sparkle configuration.
