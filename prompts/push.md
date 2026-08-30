# Push

```text
/push
```

Commit and push authorised DiskWise changes on the current branch, then sync undeployed deploy checkpoints.

Optional:

```text
<commit message focus, or files to include/exclude>
```

## Execute

1. `git status` / `git diff` / recent `git log` for message style.
2. Stage only relevant files (no secrets, no DerivedData/`build/` junk unless asked).
3. Commit with `git -c user.name="Iman Suherman" -c user.email="iman.suherman@gmail.com" commit` and a HEREDOC message.
4. `git push` (set upstream if needed). Do not force-push `main`.
5. Confirm `git status` is clean relative to the intended push.
6. **Sync undeployed deploys:** run `npm run deploy:sync`.
   - Advances `lastDeployedSha` when HEAD has no deploy-required changes for that target (docs/prompts/scripts-only, etc.).
   - Triggers a real deploy when website / registry / app paths require it.
   - Never auto-deploys `diskwise-download` (manual Cloudflare).
   - Do **not** run `npm run deploy:retry` blindly for `diskwise-app` when only non-app files changed — that would cut an unnecessary DMG. Prefer `deploy:sync`.
7. If the human only asked to clear undeployed noise with nothing to commit, skip steps 2–4 and still run `npm run deploy:sync`.

## Output

```text
Committed:
- …
Pushed:
- …
Deploy sync:
- …
Left unstaged:
- …
```
