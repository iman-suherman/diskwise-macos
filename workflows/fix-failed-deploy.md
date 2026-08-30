# Workflow: fix failed deploy / CI

1. Follow `prompts/fix-failed-deploy.md` / `/fix-failed-deploy`.
2. Prefer the pasted `npm run ci` dashboard or log paths as the source of truth.
3. Retry with `npm run deploy:retry -- --repo <repo>` only after the root cause is fixed.
4. Re-check the dashboard before declaring success.
