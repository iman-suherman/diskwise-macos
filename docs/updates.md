# DiskWise updates (Sparkle)

DiskWise uses [Sparkle](https://sparkle-project.org/) for native macOS auto-updates.

## Architecture

| Component | URL |
|-----------|-----|
| Appcast feed | `https://diskwise.suherman.net/appcast.xml` |
| Update downloads | `https://diskwise-download.suherman.net/downloads/DiskWise-{version}.zip` |
| Manual DMG downloads | `https://diskwise-download.suherman.net/downloads/` |

Sparkle checks for updates on launch and every 24 hours, downloads updates in the background, and prompts to install when ready.

## One-time signing setup

```bash
npm run sparkle:setup-keys
```

This generates an EdDSA key pair (private key in your login keychain) and writes the public key to:

- `config/sparkle-public-ed-key.txt`
- `app/DiskWise/Info.plist` (`SUPublicEDKey`)

For GitHub Actions, export the private key and store it as `SPARKLE_PRIVATE_KEY`:

```bash
.sparkle-tools/bin/generate_exported_private_key
```

## Release flow

Local (existing pipeline, now includes Sparkle artifacts):

```bash
npm run release
```

On tag push (`v*`), `.github/workflows/release.yml` builds, signs, notarizes, uploads DMG + ZIP, updates `appcast.xml`, and publishes a GitHub Release.

Required GitHub secrets:

| Secret | Purpose |
|--------|---------|
| `SPARKLE_PRIVATE_KEY` | Sparkle update signatures |
| `MACOS_CODESIGN_IDENTITY` | Developer ID Application identity |
| `APPLE_NOTARIZE_KEYCHAIN_PROFILE` or `APPLE_ID` + `APPLE_APP_SPECIFIC_PASSWORD` + `APPLE_TEAM_ID` | Notarization |
| `GCP_PROJECT_ID`, `GOOGLE_APPLICATION_CREDENTIALS`, `GCS_APP_BUCKET` | GCS upload |

## Local testing

Debug builds use the local website feed (`http://127.0.0.1:3000/appcast.xml`). Release builds use production.

```bash
npm run release:local      # build + sign + notarize + publish local Sparkle artifacts
npm run dev:website        # serve appcast.xml and downloads/
npm run dev:app            # Debug app checks local feed (5 min interval)
```

Or publish Sparkle artifacts only:

```bash
npm run sparkle:local
npm run dev:website
```

Set `SPARKLE_LOCAL=0` to skip local Sparkle publishing during `npm run start` or `npm run release:local`.

## Production appcast generation

```bash
npm run sparkle:appcast
```

Reads signed ZIPs from `releases/sparkle/`, signs entries, writes `releases/sparkle/appcast.xml`, and copies to `website/public/appcast.xml`.

Deploy the website so `appcast.xml` is served at the site root:

```bash
npm run deploy:website
```
