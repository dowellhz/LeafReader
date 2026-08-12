# Leaf Reader Agent Guidelines

These instructions apply to the entire repository.

## Project Context

- Leaf Reader is a native macOS application written primarily in Swift and built directly with repository scripts.
- The minimum supported system is macOS 12.0. Do not use newer APIs without an availability check and a working fallback.
- The application supports both Apple Silicon and Intel. Do not introduce architecture-specific behavior unless the feature is explicitly runtime-gated.
- Main application code lives in `mac-app/`; lightweight regression tests live in `tests/`; maintenance and release automation lives in `scripts/`.
- Read `docs/wiki/architecture.md` and the relevant section of `docs/wiki/development-tasks.md` before making a cross-cutting change.

## Change Discipline

- Keep each change focused. Do not refactor unrelated code while fixing a bug or adding a feature.
- Preserve user data and existing preferences. Treat document state, vocabulary records, notes, conversations, caches, and API credentials as sensitive persistent data.
- Prefer extending an existing focused module over growing a general controller file.
- Split large controllers by behavior using files such as `Type+Concern.swift`. Put reusable, UI-independent policy in a small dedicated type.
- A source code file must not exceed 500 physical lines after a change. This limit applies to Swift, JavaScript, shell, and Python source and test files. If a touched file already exceeds the limit, split it into focused modules as part of the change instead of adding to it. Generated files, vendored third-party code, and minified assets are exempt.
- Match surrounding naming, access control, and formatting. Use four-space indentation and no trailing whitespace.
- Add or update regression tests whenever behavior changes or a bug is fixed.
- Do not commit generated app bundles, downloaded model/runtime files, caches, credentials, signing material, or local release artifacts.

## Swift Conventions

- Prefer value types and pure functions for policies, parsing, transformations, and other testable logic.
- Use `guard` for validation and early exits. Avoid force unwraps and unchecked array access unless an invariant is immediately obvious and enforced locally.
- Keep visibility as narrow as possible (`private` or `fileprivate` where appropriate).
- Name booleans as predicates, such as `isEnabled`, `hasSelection`, or `allowsEdgePaging`.
- Keep constants explicit for thresholds, timeouts, limits, persistence keys, and user-visible policy values; avoid unexplained literals in control flow.
- Capture `self` weakly in escaping UI closures when retaining the owner would create a cycle. Dispatch UI mutations back to the main queue.
- Preserve structured error information and useful diagnostics. Do not silently replace actionable failures with generic errors.
- Use only frameworks already appropriate to the target unless a new dependency is clearly required. Avoid adding package dependencies for functionality available in Foundation or macOS frameworks.

## AppKit and UI

- All new user-visible text must provide Chinese and English variants through `AppText.localized(_:_:)` or an existing `AppText` property.
- New controls must work in all reader themes: `original`, `eyeCare`, and `dark`.
- Icon-only controls must use an SF Symbol with an accessibility description and theme-aware tinting.
- Dynamically created controls must apply the current theme at creation and participate in the owning surface's later theme refresh path.
- Preserve keyboard navigation, menu shortcuts, first-responder behavior, and native PDFKit/WebKit scrolling behavior.
- Keep expensive parsing, database work, network requests, model loading, and process execution off the main UI path.

## Persistence and SQLite

- Schema changes must be additive, idempotent, and safe for existing installations. Use `SQLiteSchemaMigrator` for column additions.
- Keep SQL column order, bind indexes, and decode indexes aligned; update all three together and cover the migration with a store test.
- Use prepared statements and bindings for values. Do not interpolate user-controlled values into SQL.
- Treat a multi-statement write as atomic: check `BEGIN`, every statement, and `COMMIT`; roll back and report failure if any step fails. Never return success before a successful commit.
- Add failure-path coverage for destructive replacement writes, including statement and commit failures, and verify that existing records remain intact.
- Never delete or reinterpret existing user records without an explicit migration policy and regression coverage.

## Security and Untrusted Input

- Store API keys, tokens, and other secrets in macOS Keychain. Do not derive encryption keys from predictable app, user, or filesystem metadata, and do not keep recoverable secrets in `UserDefaults` or ordinary files.
- Secret migrations must write and verify the Keychain item before deleting legacy data. Never log secrets, authorization headers, complete request payloads, or user document text.
- Treat EPUB, DOCX, model/runtime archives, manifests, HTML, and linked resources as untrusted input.
- Before extracting an archive, reject absolute paths, parent traversal, escaping symlinks, excessive entry counts, excessive expanded size, and unsafe compression ratios. Verify every resolved extracted path remains inside the owned destination and clean up partial output on failure.
- Runtime/model installation must fail closed unless a trusted manifest provides the expected asset, byte size, and non-empty checksum. Validate the archive before extracting or executing any installed file.
- Do not rely on regular-expression HTML rewriting as the sole security boundary. Use an allowlist policy for rendered elements, attributes, URL schemes, navigation, and remote subresources, and cover bypass cases with hostile-document tests.

## Resource Lifecycle and Caching

- Give every temporary file or directory an explicit owner. Clean it up on load failure, cancellation, stale async results, document replacement, window close, and owner deinitialization; do not delete shared persistent caches through this path.
- Async document work must use cancellation or generation guards before mutating state. A result discarded as stale must still release its owned resources.
- Persistent cache identity must include content identity, not only path, timestamp, or file size. Add invalidation coverage for content replacement that preserves metadata.

## Web Reader and Shell Code

- Keep code in `mac-app/Resources/reader-web*.js` compatible with the WebKit version available on macOS 12.
- Avoid duplicating reader state between Swift and JavaScript; use the existing bridge and message patterns.
- Shell scripts must use `#!/usr/bin/env bash` and `set -euo pipefail` unless there is a documented compatibility reason not to.
- Quote path and variable expansions, use repository-relative paths derived from the script location, and put temporary output under `mktemp` or `/private/tmp`.
- Do not weaken signing, notarization, bundle auditing, checksum, or architecture checks to make a build pass.

## Tests and Validation

Run the smallest relevant check while iterating, then run the standard repository check before handoff.

```sh
./tests/run.sh
./scripts/check.sh --no-build
```

For UI, theme, build-system, framework-integration, or packaging changes, also run:

```sh
./scripts/check_ui_theme.sh --warnings-as-errors
./scripts/build_app.sh
```

Use `./scripts/check.sh` for a full pre-commit verification when the local environment has the required runtimes and Sparkle framework. Release/TTS changes require the task-specific commands documented in `docs/wiki/development-tasks.md` and `docs/wiki/release-checklist.md`.

- Tests use lightweight executable Swift test runners rather than XCTest. Follow the existing `expect`/`expectEqual` and runner patterns.
- When adding a test-only source dependency, update the appropriate source list in `tests/run.sh`.
- JavaScript changes must pass `node --check` and `tests/ReaderWebScriptTests.js`; the standard test script runs these checks.
- Always run `git diff --check` before committing.

## Documentation and Generated Files

- Keep behavior, shortcuts, architecture notes, and development task guidance synchronized with code changes.
- `docs/wiki/code-map.md` and `docs/wiki/type-index.md` are generated. Do not edit them manually; regenerate them with:

```sh
./scripts/generate_code_wiki.sh
```

- Do not edit built output under `docs/manual/` directly. Change the source documentation and rebuild it through the repository scripts.
- Do not change versions, release notes, appcast entries, installers, or tags unless the task is explicitly a release task.

## Handoff

- Summarize the user-visible behavior changed, the important implementation boundary, and the validation performed.
- Call out checks that could not run and why. Never claim a build or test passed unless it was actually executed.
- Leave the working tree free of temporary files and unrelated generated output.
