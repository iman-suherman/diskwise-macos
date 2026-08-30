# Prompts

**Canonical** task templates for every AI tool (Cursor, Codex, Copilot).

Do not maintain a second full copy elsewhere. Adapters:

- Cursor `/` skills → thin wrappers in `.agents/skills/` (symlinked from `.cursor/skills/`)
- Copilot → `.github/prompts/` symlinks to these files
- Codex → read these paths via `AGENTS.md` + `.agents/skills/`

| Prompt | Slash / skill |
|--------|----------------|
| [help.md](help.md) | `/help` |
| [fix-failed-deploy.md](fix-failed-deploy.md) | `/fix-failed-deploy` |
| [release.md](release.md) | `/release` |
| [push.md](push.md) | `/push` |
| [investigate.md](investigate.md) | `/investigate` |

Layout: [../knowledge/agent-stack.md](../knowledge/agent-stack.md). Catalog: [../knowledge/prompts-catalog.md](../knowledge/prompts-catalog.md).
