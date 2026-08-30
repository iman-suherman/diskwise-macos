# App Store Connect — DiskWise iOS

Same mechanism as ArahBaik / HaloRT:

| Field | Value |
|-------|--------|
| Bundle ID | `net.suherman.diskwise.ios` |
| Apple ID | `6806657352` |
| Team | `Q3TXW887NM` |
| SKU | `diskwise-ios` |
| Primary locale | `en-US` |
| ASC API key | `halort-infra/.credentials/asc/` |

## One-time: create the app record

The shared ASC API key can manage uploads but **cannot CREATE apps** (same as ArahBaik). Create once in the UI:

1. Open [App Store Connect → Apps](https://appstoreconnect.apple.com/apps)
2. **+** → New App
3. Platforms: **iOS**
4. Name: **DiskWise**
5. Primary Language: **English (U.S.)**
6. Bundle ID: **net.suherman.diskwise.ios** (already registered on the Developer Portal)
7. SKU: **diskwise-ios**
8. User Access: Full Access

## Upload build

```bash
npm run asc:ensure
npm run publish:testflight
```

## Submit for App Review

```bash
npm run appstore:screenshots
ASC_PYTHON="$HOME/src/halort/halort-mobile-ios/app-store/.venv/bin/python" \
  "$ASC_PYTHON" scripts/prepare-app-store-metadata.py
npm run appstore:price-free
npm run appstore:submit
```

**Manual once (API cannot set this):** App Privacy → publish **Data Not Collected**  
https://appstoreconnect.apple.com/apps/6806657352/appData/privacy/practice

Successful uploads write `app-store-connect/testflight-status.json`.
