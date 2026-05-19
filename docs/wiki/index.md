# Leaf Reader Code Wiki

This wiki explains the codebase structure and stable engineering workflows for Leaf Reader.

This repo copy uses relative Markdown file links. The GitHub Wiki copy uses Wiki page names such as `Architecture` and `Document-Loading`.

## Current Version Status

- Current version: `1.4.14`
- Git tag: `v1.4.14`
- Website: [leafreader.space](https://leafreader.space)
- Appcast: [docs/appcast.xml](../appcast.xml)
- Latest installer: [LeafReader-1.4.14.pkg](https://github.com/dowellhz/LeafReader/releases/download/v1.4.14/LeafReader-1.4.14.pkg)

## Common Commands

```sh
./scripts/check.sh
./scripts/release_pkg.sh <version>
./scripts/publish_release.sh <version>
./scripts/update_wiki.sh --push
```

## Pages

- [Architecture](architecture.md)
- [Feature Map](feature-map.md)
- [Development Tasks](development-tasks.md)
- [Document Loading](document-loading.md)
- [AI Chat](ai-chat.md)
- [AI Analysis Cache](ai-analysis-cache.md)
- [Word Highlights](word-highlights.md)
- [Release Process](release-process.md)
- [Release Checklist](release-checklist.md)
- [Release Runbook](release-runbook.md)
- [Security](security.md)
- [Troubleshooting](troubleshooting.md)
- [Code Map](code-map.md)
- [Type Index](type-index.md)

## Maintenance

- Keep durable architecture notes in these pages.
- Regenerate and sync Wiki source after large refactors:

```sh
./scripts/update_wiki.sh
```

- Prefer short flow descriptions and source file links over copied code.
