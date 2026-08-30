# Prompts and slash catalog

Single catalog for DiskWise. `/help` reads this file.

**Layout:** [agent-stack.md](agent-stack.md)

## Cursor slash skills (`/` in Agent chat)

Canonical skill files: `.agents/skills/<name>/SKILL.md` (`.cursor/skills/` are symlinks).

| Slash | Path | Explanation |
|-------|------|-------------|
| `/help` | `.agents/skills/help/SKILL.md` | List slash skills and prompts. |
| `/fix-failed-deploy` | `.agents/skills/fix-failed-deploy/SKILL.md` | Diagnose and fix failed `npm run ci` / deploy targets. |
| `/release` | `.agents/skills/release/SKILL.md` | Cut a macOS app version (notes → `npm run release` → push tag). |
| `/push` | `.agents/skills/push/SKILL.md` | Commit and push dirty DiskWise changes when authorised. |
| `/investigate` | `.agents/skills/investigate/SKILL.md` | Structured investigation with evidence (no guessing). |

## Canonical prompts (`prompts/`)

| Prompt | Slash |
|--------|-------|
| `prompts/help.md` | `/help` |
| `prompts/fix-failed-deploy.md` | `/fix-failed-deploy` |
| `prompts/release.md` | `/release` |
| `prompts/push.md` | `/push` |
| `prompts/investigate.md` | `/investigate` |

## Workflows (`workflows/`)

| Workflow | Path |
|----------|------|
| Fix failed deploy | `workflows/fix-failed-deploy.md` |
| Cut release | `workflows/release.md` |

## How to add a new entry

1. Add `prompts/<name>.md` only.
2. Add thin `.agents/skills/<name>/SKILL.md` → follow that prompt.
3. Run `npm run link:agents`.
4. Add one row here.
5. Never duplicate full text under `.github/prompts/` or `.cursor/skills/`.
