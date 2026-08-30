# Push

```text
/push
```

Commit and push authorised DiskWise changes on the current branch.

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

## Output

```text
Committed:
- …
Pushed:
- …
Left unstaged:
- …
```
