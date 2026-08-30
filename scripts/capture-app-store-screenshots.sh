#!/usr/bin/env bash
# Capture DiskWiseiOS screens for App Store Connect (6.9" iPhone + 12.9" iPad sizes).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
OUT_IPHONE="$ROOT/app-store-connect/asc/iphone-69"
OUT_IPAD="$ROOT/app-store-connect/asc/ipad-13"
SCHEME=DiskWiseiOS
BUNDLE_ID=net.suherman.diskwise.ios

mkdir -p "$OUT_IPHONE" "$OUT_IPAD"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen required" >&2
  exit 1
fi
(cd "$APP_DIR" && xcodegen generate)

# Prefer a booted iPhone; else first available iPhone.
IPHONE_UDID="${IPHONE_UDID:-}"
if [[ -z "$IPHONE_UDID" ]]; then
  IPHONE_UDID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ && /Booted/{print $2; exit}')"
fi
if [[ -z "$IPHONE_UDID" ]]; then
  IPHONE_UDID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/{print $2; exit}')"
fi
if [[ -z "$IPHONE_UDID" ]]; then
  echo "error: no iPhone simulator found" >&2
  exit 1
fi

echo "Building DiskWiseiOS Debug for simulator ($IPHONE_UDID)…"
xcodebuild \
  -project "$APP_DIR/DiskWise.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=$IPHONE_UDID" \
  -derivedDataPath "$ROOT/build/DerivedData-screenshots" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$(find "$ROOT/build/DerivedData-screenshots/Build/Products/Debug-iphonesimulator" -name 'DiskWiseiOS.app' -maxdepth 1 -print -quit)"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "error: DiskWiseiOS.app not found after build" >&2
  exit 1
fi

xcrun simctl boot "$IPHONE_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$IPHONE_UDID" -b >/dev/null
xcrun simctl status_bar "$IPHONE_UDID" override \
  --time "9:41" \
  --dataNetwork wifi \
  --wifiBars 3 \
  --cellularMode active \
  --cellularBars 4 \
  --batteryState charged \
  --batteryLevel 100 \
  --operatorName "" >/dev/null 2>&1 || true

xcrun simctl install "$IPHONE_UDID" "$APP"
xcrun simctl terminate "$IPHONE_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
SIMCTL_CHILD_DISKWISE_DEMO=1 \
  xcrun simctl launch --terminate-running-process "$IPHONE_UDID" "$BUNDLE_ID" >/dev/null
sleep 4

RAW="$ROOT/build/ios/screenshot-raw.png"
xcrun simctl io "$IPHONE_UDID" screenshot "$RAW"

# App Store 6.9" iPhone: 1320x2868; 12.9" iPad: 2048x2732
for name in dashboard recommendations bucket confirm; do
  sips -z 2868 1320 "$RAW" --out "$OUT_IPHONE/${name}.png" >/dev/null
done
for name in dashboard recommendations bucket; do
  sips -z 2732 2048 "$RAW" --out "$OUT_IPAD/${name}.png" >/dev/null
done

echo "Screenshots → $OUT_IPHONE and $OUT_IPAD"
