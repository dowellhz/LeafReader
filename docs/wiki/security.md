# Security

This page records security practices for Leaf Reader development and release work.

## API Keys

- Never commit API keys, tokens, private keys, signing keys, `.env` files, or local credentials.
- AI provider keys should be entered through the app settings UI and stored locally.
- Do not hard-code provider keys in Swift, JavaScript, HTML, shell scripts, docs, app bundles, or tests.
- If a key appears in GitHub Secret Scanning, treat it as exposed even if it was removed from the current branch.

## Secret Scanning Response

When GitHub reports a leaked secret:

1. Revoke or delete the exposed key in the provider console.
2. Generate a new key only after the old one is revoked.
3. Confirm the key is not present in the current working tree.
4. Check Git history to identify where it appeared.
5. Mark the GitHub Secret Scanning alert as resolved only after revocation.
6. Do not reuse the exposed key.

Useful local checks:

```sh
rg -n "sk-[A-Za-z0-9_-]+" .
git log --all -S"secret-prefix" --oneline
git grep -l "secret-prefix" <commit>
```

Use a short prefix for investigation and avoid printing full secrets in logs or chat.

## Repository History

Early history may contain generated app bundle files or old credentials. If a secret was ever public, revocation is required even if history is later rewritten.

History rewriting should be avoided unless there is a clear reason, because it changes commit hashes, tags, release references, and local clones. Prefer revoking leaked keys and preventing new leaks.

## Generated Artifacts

Do not commit generated app bundles or local release outputs unless there is a deliberate release reason.

Generated outputs include:

- `Leaf Reader.app`
- `release/`
- temporary package roots
- local signing or notarization artifacts

## GitHub Wiki Sync

Security docs live in `docs/wiki/security.md` and should be synced to GitHub Wiki with:

```sh
./scripts/sync_github_wiki.sh --push
```

## Related Files

- `docs/wiki/security.md`
- `scripts/sync_github_wiki.sh`
- `scripts/update_wiki.sh`
- `.gitignore`
