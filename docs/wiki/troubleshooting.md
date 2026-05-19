# Troubleshooting

This page records recurring Leaf Reader issues and the fastest checks to run before changing code.

## Sparkle Update Check Fails

Symptoms:

- The update dialog says update information could not be retrieved.
- The app still appears to use an old update URL.

Checks:

```sh
curl -I -L https://leafreader.space/appcast.xml
curl -I -L https://dowellhz.github.io/LeafReader/appcast.xml
```

Expected:

- The active appcast URL returns `200`.
- HTTPS works without certificate errors.
- `docs/appcast.xml` points release URLs at the intended host.

Common causes:

- The installed app still has an older `SUFeedURL`.
- GitHub Pages custom domain DNS or certificate is still provisioning.
- The appcast was updated locally but not pushed to GitHub Pages.

## GitHub Pages SSL Or Custom Domain Problems

Checks:

```sh
dig leafreader.space
dig www.leafreader.space
curl -I -L https://leafreader.space/
```

Expected:

- `docs/CNAME` contains the canonical custom domain.
- DNS points to GitHub Pages.
- GitHub Pages shows HTTPS as available and enforced.

If the certificate is wrong or missing, remove and re-add the custom domain in the repository Pages settings, then wait for GitHub to provision the certificate.

## Package Signing Or Notarization Fails

Checks:

```sh
./scripts/check.sh
security find-identity -v
pkgutil --check-signature release/pkg/LeafReader-<version>.pkg
```

Common causes:

- Missing Developer ID identity in the active keychain.
- Notary credentials are missing from the local keychain profile.
- Release artifact from a previous build is being reused.

## PDF Page Turn Feels Hard Or Double-Triggers

Relevant files:

- `mac-app/PDFReaderView.swift`
- `mac-app/PDFPagingPolicy.swift`
- `mac-app/ReaderWindowController+Navigation.swift`

Checks:

- Confirm edge paging is only triggered at the page top or bottom.
- Keep native PDFKit scrolling behavior intact.
- Verify the duplicate-page-turn cooldown before lowering thresholds.

## AI Analysis Status Looks Wrong

Relevant files:

- `mac-app/ReaderWindowController+EmbeddingStatus.swift`
- `mac-app/ReaderWindowController+EmbeddingActions.swift`
- `mac-app/ReaderWindowController+Theme.swift`
- `mac-app/PDFEmbeddingStore.swift`

Checks:

- Confirm the status label is visible only while indexing, paused, failed, cancelled, or reporting cache state.
- Confirm theme changes re-apply the intended status text color.
- Check whether the current document already has cached chunks.

## Book Or Vocabulary Records Look Stale

Relevant files:

- `mac-app/DocumentIdentity.swift`
- `mac-app/WordRecordSQLiteStore.swift`
- `mac-app/PDFEmbeddingStore.swift`
- `mac-app/ReaderWindowController+VocabularyStorage.swift`

Checks:

- Confirm the document ID is stable for the file.
- Check whether the file moved, changed size, or was modified.
- For vocabulary problems, inspect the word record store before deleting user data.

## Wiki Sync Fails

Commands:

```sh
./scripts/update_wiki.sh
./scripts/update_wiki.sh --push
```

Common causes:

- The GitHub Wiki worktree under `/private/tmp/leafreader-wiki-sync` has unexpected local changes.
- Network or SSH access to GitHub is unavailable.
- `docs/wiki` source files were edited but not committed after a previous sync.

Use dry-run mode first. Push mode updates the GitHub Wiki and commits changed `docs/wiki` files back to the main repository.
