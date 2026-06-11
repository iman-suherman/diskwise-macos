# DiskWise updates (Sparkle)

DiskWise uses [Sparkle](https://sparkle-project.org/) for native macOS auto-updates.

## Architecture

| Component | URL |
|-----------|-----|
| Appcast feed (registry API) | `https://diskwise-registry.suherman.net/appcast.xml` |
| Appcast feed (API, explicit) | `https://diskwise-registry.suherman.net/api/v1/plugins/diskwise-macos/appcast.xml` |
| Website appcast proxy (legacy) | `https://diskwise.suherman.net/appcast.xml` → registry API |
| Update downloads | `https://diskwise-download.suherman.net/downloads/DiskWise-{version}.zip` |
| Manual DMG downloads | `https://diskwise-download.suherman.net/downloads/` |

The registry API reads `appcast.xml` from GCS (`gs://{bucket}/releases/appcast.xml`) on each request. When you release a new version, `npm run release` uploads the updated appcast to GCS and registers the path in Firestore — no website redeploy is required for Sparkle.

Sparkle checks for updates on launch and every 24 hours, downloads updates in the background, and prompts to install when ready.

## One-time signing setup

```bash
npm run sparkle:setup-keys
```

This generates an EdDSA key pair (private key in your login keychain) and writes the public key to:

- `config/sparkle-public-ed-key.txt`
- `app/DiskWise/Info.plist` (`SUPublicEDKey`)

## Release flow

```bash
npm run release
```

This builds, signs, notarizes, uploads the DMG + Sparkle ZIP to GCS, updates `appcast.xml` in GCS, and registers the version in Firestore. Deploy the registry API after API changes:

```bash
npm run deploy:registry
```

## Local testing

Debug builds use the local website feed (`http://127.0.0.1:3000/appcast.xml`). Release builds use the registry API.

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

Reads signed ZIPs from `releases/sparkle/`, signs entries, and writes `releases/sparkle/appcast.xml`. With `SPARKLE_LOCAL=1`, also copies to `website/public/appcast.xml` for local dev.

Production releases upload the appcast to GCS only; the registry API serves it to Sparkle clients.
