#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"
CONFIGURATION="${1:-debug}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required. Install with: brew install xcodegen"
  exit 1
fi

ICON_SRC="$ROOT_DIR/website/public/app-icon.png"
ICON_DST="$APP_DIR/DiskWiseiOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
if [[ -f "$ICON_SRC" ]]; then
  echo "==> Preparing iOS app icon"
  sips -z 1024 1024 "$ICON_SRC" --out "$ICON_DST" >/dev/null
fi

echo "==> Generating Xcode project"
cd "$APP_DIR"
xcodegen generate

XCODE_CONFIG="Debug"
case "$CONFIGURATION" in
  [Rr][Ee][Ll][Ee][Aa][Ss][Ee])
    XCODE_CONFIG="Release"
    ;;
esac

DESTINATION="${IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 16}"

echo "==> Building DiskWiseiOS ($XCODE_CONFIG)"
if ! xcodebuild \
  -project DiskWise.xcodeproj \
  -scheme DiskWiseiOS \
  -configuration "$XCODE_CONFIG" \
  -destination "$DESTINATION" \
  -derivedDataPath "$ROOT_DIR/.build/DerivedData-iOS" \
  build; then
  echo "xcodebuild failed. Try: IOS_DESTINATION='platform=iOS Simulator,name=iPhone 15' npm run build:ios"
  exit 1
fi

echo "Built DiskWiseiOS ($XCODE_CONFIG). Open app/DiskWise.xcodeproj and run the DiskWiseiOS scheme."
