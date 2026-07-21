# Cloud Run images (GHCR)

Cloud Run services deploy from **GitHub Container Registry**, not Artifact Registry / `gcloud run deploy --source`.

Local `npm run deploy:*` uses the shared helper in `suherman-net-infra` (`scripts/lib/ghcr-cloudrun-deploy.cjs`): Docker/Podman build → push GHCR → `gcloud run deploy --image`.

| Service | Image |
|---------|--------|
| Registry API | `ghcr.io/iman-suherman/diskwise-registry-api` |
| Website | `ghcr.io/iman-suherman/diskwise-website` |

```bash
npm run deploy:registry
npm run deploy:website
```

GitHub Actions also builds/pushes images on path-filtered pushes to `main` (`.github/workflows/build-images.yml`).

## Remove leftover Artifact Registry charges

```bash
npm run deploy:cleanup-ar              # dry-run
npm run deploy:cleanup-ar -- --apply

# Or from suherman-net-infra:
npm run gcp:artifact-registry:delete -- --execute
```
