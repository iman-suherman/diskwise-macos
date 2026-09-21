# DiskWise for Android

On-device **Photos / gallery storage consultant**: scan MediaStore, surface reclaimable space, and move selected items to **Trash** (recoverable).

## Requirements

- JDK 17+ (Android Studio JBR works)
- Android SDK 35
- Device or emulator API 26+

## Build

From the repo root:

```bash
npm run build:android
```

Or:

```bash
cd app/DiskWiseAndroid
./scripts/build.sh assembleDebug
# signed release bundle (needs keystore.properties):
./scripts/build.sh bundleRelease
```

Debug APK: `app/build/outputs/apk/debug/app-debug.apk`  
Release AAB: `app/build/outputs/bundle/release/app-release.aab`

## Package

`net.suherman.diskwise.android`

## Privacy & safety

- Analysis stays on-device; media is not uploaded.
- Cleanup uses `MediaStore.createDeleteRequest` (API 30+) so the system Trash / confirmation UI handles deletion.
- v1 never empties Trash.
