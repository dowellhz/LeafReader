# Leaf Reader Code Wiki

This wiki explains the codebase structure and stable engineering workflows for Leaf Reader.

This repo copy uses relative Markdown file links. The GitHub Wiki copy uses Wiki page names such as `Architecture` and `Document-Loading`.

## Current Version Status

- Current version: `1.4.14`
- Git tag: `v1.4.14`
- Website: [leafreader.space](https://leafreader.space)
- Appcast: [docs/appcast.xml](https://dowellhz.github.io/LeafReader/appcast.xml)
- Latest installer: [LeafReader-1.4.14.pkg](https://github.com/dowellhz/LeafReader/releases/download/v1.4.14/LeafReader-1.4.14.pkg)

## Common Commands

```sh
./scripts/check.sh
./scripts/release_pkg.sh <version>
./scripts/publish_release.sh <version>
./scripts/update_wiki.sh --push
```

## Pages

<div class="grid" markdown>

[**Architecture** - System shape and module boundaries.](architecture.md){ .card }

[**Feature Map** - Find code by product feature.](feature-map.md){ .card }

[**Development Tasks** - Entry points for common engineering work.](development-tasks.md){ .card }

[**Document Loading** - PDF, EPUB, and DOCX loading flow.](document-loading.md){ .card }

[**AI Chat** - AI panel actions, requests, and rendering.](ai-chat.md){ .card }

[**AI Analysis Cache** - Embedding cache and retrieval workflow.](ai-analysis-cache.md){ .card }

[**Word Highlights** - Vocabulary storage, review, and highlights.](word-highlights.md){ .card }

[**Release Process** - Release scripts and files.](release-process.md){ .card }

[**Release Checklist** - Preflight publishing checklist.](release-checklist.md){ .card }

[**Release Runbook** - Command-by-command release procedure.](release-runbook.md){ .card }

[**Security** - Secret handling and generated artifacts.](security.md){ .card }

[**Troubleshooting** - Symptoms and fast checks.](troubleshooting.md){ .card }

[**Code Map** - Generated module summary.](code-map.md){ .card }

[**Type Index** - Generated Swift type index.](type-index.md){ .card }

</div>

## Maintenance

- Keep durable architecture notes in these pages.
- Regenerate and sync Wiki source after large refactors:

```sh
./scripts/update_wiki.sh
```

- Prefer short flow descriptions and source file links over copied code.
