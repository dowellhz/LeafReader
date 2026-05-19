# Leaf Reader Code Wiki

This wiki explains the codebase structure and stable engineering workflows for Leaf Reader.

## Pages

- [Architecture](architecture.md)
- [Document Loading](document-loading.md)
- [AI Chat](ai-chat.md)
- [AI Analysis Cache](ai-analysis-cache.md)
- [Word Highlights](word-highlights.md)
- [Release Process](release-process.md)
- [Code Map](code-map.md)

## Maintenance

- Keep durable architecture notes in these pages.
- Regenerate [Code Map](code-map.md) after large refactors:

```sh
./scripts/generate_code_wiki.sh
```

- Prefer short flow descriptions and source file links over copied code.
