# Cut a DiskWise macOS release

```text
/release
```

Ship a new notarized macOS DMG with curated release notes.

Optional:

```text
<summary of user-facing changes, or leave blank to infer from git since last tag>
```

## Required reading

- `.cursor/rules/release-notes.mdc`
- `scripts/release-publish.cjs`
- Recent `release-notes/*.json` for tone

## Execute

1. **Scope** — `git status`, `git log v<prev>..HEAD`, and the real diff. Exclude unrelated WIP (e.g. unfinished iOS) unless asked to include it.
2. **Version** — next patch/minor from last tag / Firestore checkpoint (release script bumps unless `RELEASE_VERSION` is set).
3. **Notes** — write `release-notes/{version}.json` before `npm run release` (summary + concrete bullets; never vague fallback text).
4. **Commit feature + notes** — author `Iman Suherman <iman.suherman@gmail.com>` via `-c user.name` / `-c user.email`; push.
5. **Release** — `npm run release` (build, sign, notarize, GCS, Sparkle, registry, local tag).
6. **Post-release** — commit version bump (`package.json`, `app/project.yml`, Xcode sync); `git push` and `git push origin v{version}`.
7. **Website** — deploy when release notes / download page should update (`npm run deploy:website` or `/fix-failed-deploy` if GHCR/Podman is broken).

## Output

```text
Version:
- …
Commit / tag:
- …
Download:
- …
Website:
- …
Notes:
- …
```
