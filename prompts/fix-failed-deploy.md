# Fix failed deployments / CI

```text
/fix-failed-deploy
```

Diagnose and fix failed **DiskWise deploy / CI** (`npm run ci` dashboard), then ship the fix when authorised.

Optional focus:

```text
<failed deploy log path, repo name, or CI dashboard summary>
```

If omitted, discover failures via `npm run ci` / `logs/deployments.json` and recent `logs/diskwise-*/*.log`.

## Required reading

- `AGENTS.md`
- `knowledge/prompts-catalog.md`
- `scripts/deploy-config.cjs`
- `.cursor/rules/`

## Execute

1. **Identify failures** — prefer pasted dashboard lines / log paths; otherwise run `npm run ci` (or read `logs/deployments.json`) and list targets with `failure` or undeployed HEAD.
2. **Pull evidence** — open the matching `logs/<repo>/<deployment-id>.log`. Reproduce locally when practical (`npm run deploy:website`, `npm run deploy:registry`, `podman machine list`, `gcloud config get-value account`).
3. **Classify** — Podman stopped/corrupt storage, GHCR auth, wrong `gcloud` account, Cloud Run start failure (exec format / PORT), Xcode/notarize, skippable post-release sync only.
4. **Fix** — minimal change (scripts, Dockerfile, env). Prefer known working paths:
   - Website: ensure Podman is running **or** `gcloud run deploy --source website` with `applyGcpEnv` / correct account; amd64 for Cloud Run.
   - Registry/app: `npm run deploy:retry -- --repo <repo>` after fixing root cause.
5. **Verify** — re-check `npm run ci` / curl the service URL / confirm DMG release artifact when in scope.
6. **Ship** — commit+push only when the human asked (or via `/push`).
7. **Never** `git push --force` to `main`, skip hooks, or paste secrets.

## Output

```text
Failures addressed:
- …
Fixes:
- …
Remaining red / undeployed:
- …
Evidence:
- …
Risk / follow-up:
- …
```
