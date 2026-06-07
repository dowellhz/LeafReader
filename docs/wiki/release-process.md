# Release Process

Leaf Reader releases are built locally, signed, packaged, and published to GitHub Releases with Sparkle metadata.

## Commands

Run tests:

```sh
./tests/run.sh
```

Build the app:

```sh
./scripts/build_app.sh
```

Publish a release:

```sh
./scripts/publish_release.sh <version>
```

Publish, sync GitHub Wiki, and clean old local release artifacts:

```sh
./scripts/publish_release.sh <version> --push-wiki --cleanup-releases
```

Smoke-test a built package:

```sh
./scripts/smoke_release_pkg.sh <version>
```

Report release and speech runtime size:

```sh
./scripts/release_size_report.sh <version>
```

Check version references:

```sh
./scripts/bump_version.sh --check <version>
```

## Files

- `scripts/build_app.sh`: builds and signs `Leaf Reader.app`.
- `scripts/release_pkg.sh`: builds release package artifacts.
- `scripts/publish_release.sh`: runs tests, packages, checks version references, and publishes.
- `scripts/smoke_release_pkg.sh`: expands and validates the signed package payload.
- `scripts/release_size_report.sh`: reports app, package, and speech runtime size.
- `scripts/cleanup_releases.sh`: removes ignored generated artifacts from old release directories.
- `scripts/bump_version.sh`: updates and verifies version strings.
- `docs/appcast.xml`: Sparkle update feed.
- `docs/index.html`: GitHub Pages download page.
- `README.md`: release notes and latest installer link.

## Rule

Add a `## What's New in <version>` section to `README.md`, then run tests and version checks before publishing. Release artifacts under `release/` are local generated outputs unless explicitly committed.

## Related Files

- `scripts/check.sh`
- `scripts/build_app.sh`
- `scripts/release_pkg.sh`
- `scripts/publish_release.sh`
- `scripts/smoke_release_pkg.sh`
- `scripts/release_size_report.sh`
- `scripts/cleanup_releases.sh`
- `scripts/bump_version.sh`
- `docs/appcast.xml`
- `docs/index.html`
