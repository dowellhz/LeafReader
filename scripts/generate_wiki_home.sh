#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_FILE="$ROOT_DIR/docs/wiki/index.md"
CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/mac-app/Info.plist")"

cat > "$OUT_FILE" <<EOF
# Leaf Reader Code Wiki

This wiki explains the codebase structure and stable engineering workflows for Leaf Reader.

This repo copy uses relative Markdown file links. The GitHub Wiki copy uses Wiki page names such as \`Architecture\` and \`Document-Loading\`.

## Current Version Status

- Current version: \`$CURRENT_VERSION\`
- Git tag: \`v$CURRENT_VERSION\`
- Website: [leafreader.space](https://leafreader.space)
- Appcast: [docs/appcast.xml](../appcast.xml)
- Latest installer: [LeafReader-$CURRENT_VERSION.pkg](https://github.com/dowellhz/LeafReader/releases/download/v$CURRENT_VERSION/LeafReader-$CURRENT_VERSION.pkg)

## Common Commands

\`\`\`sh
./scripts/check.sh
./scripts/release_pkg.sh <version>
./scripts/publish_release.sh <version>
./scripts/update_wiki.sh --push
\`\`\`

## Pages

- [Architecture](architecture.md)
- [Feature Map](feature-map.md)
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

\`\`\`sh
./scripts/update_wiki.sh
\`\`\`

- Prefer short flow descriptions and source file links over copied code.
EOF

echo "Generated $OUT_FILE"
