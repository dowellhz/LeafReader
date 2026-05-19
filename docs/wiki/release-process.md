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

Check version references:

```sh
./scripts/bump_version.sh --check <version>
```

## Files

- `scripts/build_app.sh`: builds and signs `Leaf Reader.app`.
- `scripts/release_pkg.sh`: builds release package artifacts.
- `scripts/publish_release.sh`: runs tests, packages, checks version references, and publishes.
- `scripts/bump_version.sh`: updates and verifies version strings.
- `docs/appcast.xml`: Sparkle update feed.
- `docs/index.html`: GitHub Pages download page.
- `README.md`: release notes and latest installer link.

## Rule

Run tests and version checks before publishing. Release artifacts under `release/` are local generated outputs unless explicitly committed.

## Related Files

- `scripts/check.sh`
- `scripts/build_app.sh`
- `scripts/release_pkg.sh`
- `scripts/publish_release.sh`
- `scripts/bump_version.sh`
- `docs/appcast.xml`
- `docs/index.html`
