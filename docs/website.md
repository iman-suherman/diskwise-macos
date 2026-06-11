# Website

Marketing site for DiskWise at **https://diskwise.suherman.net/** (Cloud Run + Cloudflare).

Built with Next.js 15, React 19, and Tailwind CSS — same deploy pattern as [urp-ct-mcp-studio](https://github.com/iman-suherman/urp-ct-mcp-studio).

## Local development

```bash
npm run dev:website
```

Open http://127.0.0.1:3000

## One-time setup (deploy)

```bash
npm run setup    # generate-env + GCP login + git hooks
```

Or step by step:

```bash
npm run generate-env    # copy .env.example → .env
npm run login           # GCP browser auth + project selection
npm run install-hooks   # auto-deploy website/ on commit & push
```

## Manual deploy

```bash
npm run deploy:website
```

Deploys `website/` to Cloud Run service `diskwise-website` via `gcloud run deploy --source`.

## Auto-deploy

Git hooks in `githooks/` trigger background deploys when commits touch `website/`:

| Hook | Script | Disable with |
|------|--------|----------------|
| post-commit | `post-commit-website.cjs` | `DISKWise_POST_COMMIT_WEBSITE=0` |
| pre-push | `post-push-website.cjs` | `DISKWise_POST_PUSH_WEBSITE=0` |

Track deploy status:

```bash
npm run ci
npm run deploy:retry -- --repo diskwise-website
npm run deploy:stop -- --repo diskwise-website
```

## Environment variables

See `.env.example`. Build-time vars baked into the Next.js client:

| Variable | Default |
|----------|---------|
| `WEBSITE_SERVICE` | `diskwise-website` |
| `NEXT_PUBLIC_REGISTRY_API_URL` | `https://diskwise-registry.suherman.net` |
| `NEXT_PUBLIC_APP_ID` | `diskwise-macos` |
| `NEXT_PUBLIC_DOWNLOAD_BASE_URL` | `https://diskwise-download.suherman.net/downloads` |

## Routes

| Path | Purpose |
|------|---------|
| `/` | Landing page |
| `/install` | macOS DMG install guide |
| `/versions` | Release history + downloads |

Release metadata is fetched client-side from the registry API (when configured).
