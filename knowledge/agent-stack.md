# Multi-agent stack (no redundant definitions)

One canonical body of knowledge and prompts. Tool-specific paths are **adapters** (symlinks or thin pointers), not copies.

Same mechanism as [officeless-opentofu-control-plane](https://github.com/iman-suherman/officeless-opentofu-control-plane) / HaloRT infra.

## Canonical (edit these)

| Layer | Path | Used by |
|-------|------|---------|
| Agent behaviour | `AGENTS.md` | Cursor, Codex, Copilot |
| Architecture | `docs/architecture.md`, `.cursor/rules/` | All |
| Task prompts | `prompts/*.md` | All (paste or slash/skill body) |
| Workflows | `workflows/` | All |
| Skills | `.agents/skills/*/SKILL.md` | Cursor, Codex |
| Catalog | `knowledge/prompts-catalog.md` | `/help` |
| Rules | `.cursor/rules/*.mdc` | Cursor always-on |

Skills stay **thin**: frontmatter + “follow `prompts/<name>.md`”.

## Adapters (do not edit content here)

| Tool | Adapter | Points to |
|------|---------|-----------|
| **Cursor** | `.cursor/skills/*` | symlink → `.agents/skills/*` |
| **Cursor** | `.cursor/rules/*.mdc` | always-on policy |
| **GitHub Copilot** | `.github/prompts/*.md` | symlink → `prompts/*.md` |

## How each tool starts work

| Tool | Start |
|------|-------|
| Cursor | `/help`, `/fix-failed-deploy`, `/release`, `/push`, … |
| Codex | Read `AGENTS.md`; invoke skill by name from `.agents/skills/`; open `prompts/` |
| Copilot | Chat with `@workspace`; use `.github/prompts/` (same text as `prompts/`) |

## Adding a new prompt/skill

1. Write **only** `prompts/<name>.md`.
2. Add a thin `.agents/skills/<name>/SKILL.md` that says to follow that prompt.
3. Run `npm run link:agents`.
4. Add one row to `knowledge/prompts-catalog.md`.
5. Do **not** create a second full copy under `.github/prompts/` or `.cursor/skills/`.

## Repair adapters

```bash
npm run link:agents
```
