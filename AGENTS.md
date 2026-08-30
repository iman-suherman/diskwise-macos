# Engineering Agent Instructions

## Mission

Assist building and shipping **DiskWise** — the macOS AI storage consultant (and related website, registry API, and optional iOS Photos product) in this repository.

Canonical docs: `README.md`, `docs/architecture.md`, `docs/local-development.md`, `docs/database.md`.

## Agent stack

See [`knowledge/agent-stack.md`](knowledge/agent-stack.md). Canonical prompts under `prompts/`; thin skills under `.agents/skills/`. Refresh adapters with `npm run link:agents`. Catalog: [`knowledge/prompts-catalog.md`](knowledge/prompts-catalog.md) (`/help`).

## Human-in-the-loop boundary

- Investigate and produce structured findings with live evidence.
- **Do not** invent green CI or invent deploy success.
- **Do not** force-push `main` or skip hooks unless explicitly asked.
- **Do not** paste secrets from `.env` / ADC / keychain into chat or docs.
- Commit and push only when the human asked (or via `/push` / `/release`).

## Deploy / CI truth

Local deploy dashboard: `npm run ci` → `scripts/ci-deploy-status.cjs` (state in `logs/deployments.json`).

| Target | Label | Retry |
|--------|-------|-------|
| `diskwise-website` | diskwise.suherman.net | `npm run deploy:retry -- --repo diskwise-website` |
| `diskwise-registry` | diskwise-registry.suherman.net | `npm run deploy:retry -- --repo diskwise-registry` |
| `diskwise-app` | DiskWise macOS DMG | `npm run release` / `deploy:retry -- --repo diskwise-app` |
| `diskwise-download` | diskwise-download.suherman.net | Checkpoint via `npm run deploy:sync`; Worker via suherman-net-infra Cloudflare |
| `diskwise-ios` | DiskWise iOS App Store | Checkpoint via `npm run deploy:sync`; publish via `npm run publish:testflight` |

Slash shortcuts: `/fix-failed-deploy`, `/release`, `/push`, `/investigate`, `/help`.

## Cleanup safety

Default destructive action is **Move to Trash**. Always preview; never permanent-delete without explicit confirmation.
